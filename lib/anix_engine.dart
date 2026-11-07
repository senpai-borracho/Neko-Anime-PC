import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'runtime/node_runtime.dart';

class AnixEngine {
  AnixEngine({File? manifestFile})
    : _manifestFile =
          manifestFile ??
          File(
            '${Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path}/NekoPlayerPC/anix/manifest.json',
          );
  final File _manifestFile;
  Process? _process;
  Future<void>? _starting;
  final _pending = <int, Completer<dynamic>>{};
  int _counter = 0;
  Directory? _temporary;
  String? _manifestOverride;
  bool _loadedSaved = false;
  bool get importedManifest => _manifestOverride != null;

  Future<void> start() {
    if (_starting != null) return _starting!;
    if (_process != null) return Future.value();
    final task = _start();
    _starting = task;
    return task.whenComplete(() {
      if (identical(_starting, task)) _starting = null;
    });
  }

  Future<void> _start() async {
    if (!_loadedSaved) {
      if (await _manifestFile.exists()) {
        final text = await _manifestFile.readAsString();
        _validate(text);
        _manifestOverride = text;
      }
      _loadedSaved = true;
    }
    final temporary = await Directory.systemTemp.createTemp('neko-anix-');
    _temporary = temporary;
    final catalog = File('${temporary.path}/extensions.json');
    final worker = File('${temporary.path}/worker.cjs');
    try {
      if (_manifestOverride != null) {
        await catalog.writeAsString(_manifestOverride!);
      } else {
        final data = await rootBundle.load(
          'assets/extensions/anix-extensions.json',
        );
        await catalog.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
      }
      final data = await rootBundle.load('assets/extensions/anix_worker.cjs');
      await worker.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      final crypto = await rootBundle.load('assets/extensions/crypto-js.cjs');
      await File('${temporary.path}/crypto-js.cjs').writeAsBytes(
        crypto.buffer.asUint8List(crypto.offsetInBytes, crypto.lengthInBytes),
      );
      final process = await NodeRuntime.start([worker.path, catalog.path]);
      _process = process;
      final diagnostics = StringBuffer();
      process.stderr.transform(utf8.decoder).listen((text) {
        if (diagnostics.length < 4000) diagnostics.write(text);
      });
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            if (!identical(_process, process)) return;
            try {
              final msg = jsonDecode(line) as Map<String, dynamic>;
              final completion = _pending.remove(msg['id']);
              if (msg['ok'] == true) {
                completion?.complete(msg['result']);
              } else {
                completion?.completeError(StateError('${msg['error']}'));
              }
            } catch (_) {
              /* Ignore non-protocol output. */
            }
          });
      process.exitCode.then((code) {
        // A stopped generation must never clear the replacement process.
        if (!identical(_process, process)) return;
        _process = null;
        final detail = diagnostics.toString().trim();
        _failPending(
          StateError(
            'El motor Anix terminó (código $code).${detail.isEmpty ? '' : ' $detail'}',
          ),
        );
      });
    } catch (_) {
      if (await temporary.exists()) await temporary.delete(recursive: true);
      if (identical(_temporary, temporary)) _temporary = null;
      rethrow;
    }
  }

  void _failPending(Object error) {
    for (final completion in _pending.values) {
      if (!completion.isCompleted) completion.completeError(error);
    }
    _pending.clear();
  }

  Future<dynamic> call(
    String op, {
    String? plugin,
    Map<String, dynamic> args = const {},
  }) async {
    await start();
    final process = _process;
    if (process == null) throw StateError('No se pudo iniciar el motor Anix.');
    final id = ++_counter;
    final completion = Completer<dynamic>();
    _pending[id] = completion;
    try {
      process.stdin.writeln(
        jsonEncode({
          'id': id,
          'op': op,
          if (plugin != null) 'plugin': plugin,
          ...args,
        }),
      );
      return await completion.future.timeout(const Duration(seconds: 38));
    } finally {
      _pending.remove(id);
    }
  }

  int _validate(String text) {
    if (text.length > 3000000)
      throw const FormatException('Manifiesto demasiado grande.');
    final decoded = jsonDecode(text);
    if (decoded is! Map || decoded['plugins'] is! List)
      throw const FormatException(
        'El manifiesto debe contener una lista plugins.',
      );
    final entries = decoded['plugins'] as List;
    if (entries.length > 300)
      throw const FormatException('Manifiesto demasiado grande.');
    final ids = <String>{};
    for (final item in entries) {
      if (item is! Map ||
          item['id'] is! String ||
          item['name'] is! String ||
          !ids.add(item['id'] as String)) {
        throw const FormatException(
          'Extensión incompleta o identificador duplicado.',
        );
      }
    }
    return entries.length;
  }

  Future<void> downloadPlugin(String id) async {
    await start();
    final text =
        _manifestOverride ??
        await rootBundle.loadString('assets/extensions/anix-extensions.json');
    final catalog = Map<String, dynamic>.from(jsonDecode(text) as Map);
    final entries = List<dynamic>.from(catalog['plugins'] as List);
    final index = entries.indexWhere((p) => p is Map && p['id'] == id);
    if (index < 0) throw const FormatException('No se encontró la extensión.');
    final entry = Map<String, dynamic>.from(entries[index] as Map);
    final prepared = await call('prepare', args: {'entry': entry});
    if (prepared is! Map ||
        prepared['id'] != id ||
        prepared['payload'] is! String) {
      throw const FormatException(
        'La descarga no devolvió una extensión válida.',
      );
    }
    entries[index] = Map<String, dynamic>.from(prepared);
    catalog['plugins'] = entries;
    await installManifest(jsonEncode(catalog));
  }

  Future<int> installManifest(String text) async {
    final count = _validate(text);
    await _manifestFile.parent.create(recursive: true);
    await _manifestFile.writeAsString(text, flush: true);
    await dispose();
    _manifestOverride = text;
    _loadedSaved = true;
    return count;
  }

  Future<void> dispose() async {
    try {
      await _starting;
    } catch (_) {}
    final process = _process;
    final temporary = _temporary;
    _process = null;
    _temporary = null;
    _failPending(StateError('Motor Anix reiniciado.'));
    if (process != null) {
      process.kill();
      try {
        await process.exitCode.timeout(const Duration(seconds: 5));
      } on TimeoutException {
        process.kill();
      }
    }
    if (temporary != null) {
      try {
        await temporary.delete(recursive: true);
      } catch (_) {}
    }
  }
}
