import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as paths;

import 'source.dart';
import 'http_media.dart';

enum DownloadStatus { queued, downloading, done, cancelled, failed }

class DownloadTask {
  final String id, title;
  final MediaSource source;
  DownloadStatus status;
  String path = '', subtitlePath = '', error = '';
  int bytes = 0, total = 0;
  double progress = 0;
  int segmentsDone = 0, segmentsTotal = 0;
  double? get progressValue => total > 0
      ? (bytes / total).clamp(0.0, 1.0)
      : segmentsTotal > 0
      ? (segmentsDone / segmentsTotal).clamp(0.0, 1.0)
      : null;
  DownloadTask(
    this.id,
    this.title,
    this.source, {
    this.status = DownloadStatus.queued,
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'source': source.toJson(),
    'status': status.name,
    'path': path,
    'subtitlePath': subtitlePath,
    'error': error,
    'bytes': bytes,
    'total': total,
    'progress': progress,
    'segmentsDone': segmentsDone,
    'segmentsTotal': segmentsTotal,
  };
  factory DownloadTask.fromJson(Map json) {
    final task = DownloadTask(
      '${json['id']}',
      '${json['title']}',
      MediaSource.fromJson(json['source'] as Map),
    );
    task.status = DownloadStatus.values.firstWhere(
      (s) => s.name == json['status'],
      orElse: () => DownloadStatus.failed,
    );
    if (task.status == DownloadStatus.downloading ||
        task.status == DownloadStatus.queued) {
      task.status = DownloadStatus.failed;
      task.error = 'Descarga interrumpida. Puedes reintentar.';
    } else {
      task.error = '${json['error'] ?? ''}';
    }
    task.path = '${json['path'] ?? ''}';
    task.subtitlePath = '${json['subtitlePath'] ?? ''}';
    task.bytes = (json['bytes'] as num?)?.toInt() ?? 0;
    task.total = (json['total'] as num?)?.toInt() ?? 0;
    task.progress = (json['progress'] as num?)?.toDouble() ?? 0;
    task.segmentsDone = (json['segmentsDone'] as num?)?.toInt() ?? 0;
    task.segmentsTotal = (json['segmentsTotal'] as num?)?.toInt() ?? 0;
    return task;
  }
}

class Downloads extends ChangeNotifier {
  static final shared = Downloads();
  final Directory directory, stateDirectory;
  final List<DownloadTask> tasks = [];
  final Map<String, Completer<void>> _finished = {};
  HttpClient? _active;
  DownloadTask? _current;
  bool _running = false;
  Future<void>? _ready;
  Future<void> _saving = Future.value();
  DateTime _lastNotification = DateTime(2000);
  Downloads({Directory? directory, Directory? stateDirectory})
    : directory =
          directory ??
          Directory(
            '${Platform.environment['USERPROFILE'] ?? Directory.current.path}/Downloads/Neko',
          ),
      stateDirectory =
          stateDirectory ??
          Directory(
            '${Platform.environment['LOCALAPPDATA'] ?? Directory.current.path}/NekoPlayerPC',
          );
  Future<void> get ready => _ready ??= _load();

  Future<void> _load() async {
    await stateDirectory.create(recursive: true);
    final file = File('${stateDirectory.path}/downloads.json');
    if (await file.exists()) {
      try {
        final json = jsonDecode(await file.readAsString());
        if (json is List) {
          for (final value in json.whereType<Map>()) {
            tasks.add(DownloadTask.fromJson(value));
          }
        }
      } catch (_) {
        /* No modifica biblioteca ni otros datos de Neko. */
      }
    }
    notifyListeners();
  }

  Future<void> _save() {
    final text = jsonEncode(tasks.map((t) => t.toJson()).toList());
    return _saving = _saving.catchError((_) {}).then((_) async {
      await stateDirectory.create(recursive: true);
      final temporary = File('${stateDirectory.path}/downloads.json.tmp');
      await temporary.writeAsString(text, flush: true);
      await temporary.rename('${stateDirectory.path}/downloads.json');
    });
  }

  Future<DownloadTask> enqueue(String title, MediaSource source) async {
    await ready;
    final uri = Uri.parse(source.url);
    if (!['https', 'http'].contains(uri.scheme)) {
      throw const FormatException(
        'Este archivo ya es local o no se puede descargar.',
      );
    }
    final duplicate = tasks
        .where(
          (t) =>
              t.source.url == source.url &&
              [
                DownloadStatus.queued,
                DownloadStatus.downloading,
              ].contains(t.status),
        )
        .firstOrNull;
    if (duplicate != null) return duplicate;
    final task = DownloadTask(
      '${DateTime.now().microsecondsSinceEpoch}',
      title,
      source,
    );
    tasks.insert(0, task);
    _finished[task.id] = Completer<void>();
    await _save();
    notifyListeners();
    unawaited(_pump());
    return task;
  }

  Future<void> waitFor(DownloadTask task) =>
      _finished[task.id]?.future ?? Future.value();

  void cancel(DownloadTask task) {
    if (![
      DownloadStatus.queued,
      DownloadStatus.downloading,
    ].contains(task.status)) {
      return;
    }
    task.status = DownloadStatus.cancelled;
    if (_current == task) {
      _active?.close(force: true);
    } else {
      final done = _finished.remove(task.id);
      if (done != null && !done.isCompleted) done.complete();
    }
    notifyListeners();
    unawaited(_save());
  }

  Future<void> retry(DownloadTask task) async {
    if ([
      DownloadStatus.queued,
      DownloadStatus.downloading,
      DownloadStatus.done,
    ].contains(task.status)) {
      return;
    }
    if (_current == task) await waitFor(task);
    if (!tasks.contains(task)) return;
    task.status = DownloadStatus.queued;
    task.error = '';
    task.bytes = 0;
    task.progress = 0;
    task.total = 0;
    task.segmentsDone = task.segmentsTotal = 0;
    _finished[task.id] = Completer<void>();
    await _save();
    notifyListeners();
    unawaited(_pump());
  }

  Future<void> removeCompleted(DownloadTask task) async {
    if (task.status != DownloadStatus.done) return;
    await remove(task);
  }

  Future<void> remove(DownloadTask task) async {
    await ready;
    if (!tasks.contains(task) ||
        [
          DownloadStatus.queued,
          DownloadStatus.downloading,
        ].contains(task.status)) {
      return;
    }
    if (_current == task) await waitFor(task);
    if (!tasks.contains(task)) return;
    await directory.create(recursive: true);
    final root = paths.normalize(
      paths.absolute(await directory.resolveSymbolicLinks()),
    );
    final files = <File>[];
    // Only explicit episode files; never enumerate or recursively remove a directory.
    for (final name in {
      task.path,
      task.subtitlePath,
    }.where((p) => p.isNotEmpty)) {
      final file = File(name);
      if (!await file.exists()) continue;
      final resolved = paths.normalize(
        paths.absolute(await file.resolveSymbolicLinks()),
      );
      if (!paths.isWithin(root, resolved) ||
          !paths.basename(resolved).contains('-${task.id}.')) {
        throw const FileSystemException(
          'El archivo no pertenece a este episodio.',
        );
      }
      for (final other in tasks.where((t) => t != task)) {
        for (final shared in [
          other.path,
          other.subtitlePath,
        ].where((p) => p.isNotEmpty)) {
          final candidate = File(shared);
          final target = await candidate.exists()
              ? await candidate.resolveSymbolicLinks()
              : paths.absolute(shared);
          if (paths.equals(resolved, paths.normalize(target))) {
            throw const FileSystemException(
              'El archivo está compartido con otra descarga.',
            );
          }
        }
      }
      files.add(file);
    }
    for (final file in files) {
      await file.delete();
    }
    final index = tasks.indexOf(task);
    tasks.remove(task);
    try {
      await _save();
    } catch (_) {
      tasks.insert(index, task);
      rethrow;
    }
    notifyListeners();
  }

  void _check(DownloadTask task) {
    if (task.status == DownloadStatus.cancelled) {
      throw const HttpException('Cancelada.');
    }
  }

  void _progress(DownloadTask task) {
    if (DateTime.now().difference(_lastNotification).inMilliseconds > 250) {
      _lastNotification = DateTime.now();
      notifyListeners();
    }
  }

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    try {
      while (tasks.any((t) => t.status == DownloadStatus.queued)) {
        // Primero la más antigua; una sola transferencia evita competir por ancho de banda.
        final task = tasks.lastWhere((t) => t.status == DownloadStatus.queued);
        _current = task;
        task.status = DownloadStatus.downloading;
        _active = HttpClient()..connectionTimeout = const Duration(seconds: 12);
        notifyListeners();
        File? part, subtitlePart;
        IOSink? sink;
        try {
          await directory.create(recursive: true);
          var safe = task.title
              .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
              .trim();
          if (safe.isEmpty) safe = 'Video';
          if (safe.length > 90) safe = safe.substring(0, 90);
          final base = '${directory.path}/$safe-${task.id}';
          part = File('$base.part');
          if (await part.exists()) {
            await part.delete(); // Solo el parcial de esta tarea.
          }
          sink = part.openWrite();
          var response = await mediaGet(
            _active!,
            Uri.parse(task.source.url),
            task.source.headers,
          );
          final String extension;
          if (hlsResponse(response)) {
            extension = await _hls(task, response, sink);
          } else {
            final type = response.response.headers.contentType?.mimeType ?? '';
            if (invalidMediaType(type)) {
              throw const FormatException(
                'El servidor devolvió una página en vez del video.',
              );
            }
            extension = type.contains('webm')
                ? 'webm'
                : response.uri.path.toLowerCase().endsWith('.mkv')
                ? 'mkv'
                : 'mp4';
            task.total = response.response.contentLength;
            if (response.response.statusCode == 206) {
              final range =
                  response.response.headers.value('content-range') ?? '';
              final match = RegExp(r'^bytes 0-(\d+)/(\d+)$').firstMatch(range);
              if (match == null ||
                  int.parse(match[1]!) + 1 != int.parse(match[2]!)) {
                throw const HttpException(
                  'El servidor solo entregó una parte del video.',
                );
              }
            }
            await _copy(task, response, sink);
            if (task.total > 0 && task.bytes != task.total) {
              throw const HttpException('El video llegó incompleto.');
            }
          }
          if (task.bytes == 0) {
            throw const HttpException('El archivo está vacío.');
          }
          await sink.flush();
          await sink.close();
          sink = null;
          _check(task);
          if (task.source.subtitles.isNotEmpty) {
            final sub = task.source.subtitles.first;
            final response = await mediaGet(
              _active!,
              Uri.parse('${sub['url']}'),
              task.source.headers,
            );
            final text = await mediaText(response);
            if (text.trim().isEmpty || text.toLowerCase().contains('<html')) {
              throw const FormatException(
                'No se pudieron guardar los subtítulos en español.',
              );
            }
            final subExtension = text.trimLeft().startsWith('WEBVTT')
                ? 'vtt'
                : 'srt';
            subtitlePart = File('$base.es.$subExtension.part');
            await subtitlePart.writeAsString(text, flush: true);
            _check(task);
            task.subtitlePath = '$base.es.$subExtension';
            await subtitlePart.rename(task.subtitlePath);
            subtitlePart = null;
          }
          _check(task);
          task.path = '$base.$extension';
          await part.rename(task.path);
          part = null;
          task.status = DownloadStatus.done;
          task.progress = 1;
        } catch (e) {
          if (task.status != DownloadStatus.cancelled) {
            task.status = DownloadStatus.failed;
            task.error = '$e'.replaceFirst(RegExp(r'^\w+Exception: *'), '');
          }
        } finally {
          _active?.close(force: true);
          _active = null;
          try {
            await sink?.close();
          } catch (_) {}
          if (part != null && await part.exists()) await part.delete();
          if (subtitlePart != null && await subtitlePart.exists()) {
            await subtitlePart.delete();
          }
          _current = null;
          await _save();
          notifyListeners();
          final done = _finished.remove(task.id);
          if (done != null && !done.isCompleted) done.complete();
        }
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _copy(
    DownloadTask task,
    MediaResponse result,
    IOSink sink,
  ) async {
    var buffered = 0;
    await for (final chunk in result.response.timeout(
      const Duration(seconds: 30),
    )) {
      _check(task);
      sink.add(chunk);
      buffered += chunk.length;
      if (buffered >= 1024 * 1024) {
        await sink.flush();
        buffered = 0;
        _check(task);
      }
      task.bytes += chunk.length;
      if (task.total > 0) {
        task.progress = (task.bytes / task.total).clamp(0, .999);
      }
      _progress(task);
    }
    await sink.flush();
  }

  Future<String> _hls(
    DownloadTask task,
    MediaResponse result,
    IOSink sink,
  ) async {
    var text = '';
    for (var depth = 0; ; depth++) {
      if (depth > 4) {
        throw const FormatException('Demasiadas listas HLS anidadas.');
      }
      text = await mediaText(result);
      if (!text.trimLeft().startsWith('#EXTM3U')) {
        throw const FormatException('Lista HLS inválida.');
      }
      final variant = hlsVariant(result.uri, text);
      if (variant == null) break;
      result = await mediaGet(_active!, variant, task.source.headers);
    }
    if (!text.contains('#EXT-X-ENDLIST')) {
      throw const FormatException('No se descargan emisiones en vivo.');
    }
    if (RegExp(r'#EXT-X-KEY:.*METHOD=(?!NONE)').hasMatch(text)) {
      throw const FormatException(
        'Este HLS está cifrado. Elige otro servidor para descargar.',
      );
    }
    if (text.contains('#EXT-X-BYTERANGE:')) {
      throw const FormatException(
        'Este HLS usa rangos de fragmentos. Elige otro servidor para descargar.',
      );
    }
    final maps = RegExp(r'#EXT-X-MAP:.*URI="([^"]+)"')
        .allMatches(text)
        .map((m) => m[1]!)
        .toSet();
    if (maps.length > 1 || RegExp(r'#EXT-X-MAP:.*BYTERANGE=').hasMatch(text)) {
      throw const FormatException(
        'Este HLS cambia su inicialización. Elige otro servidor para descargar.',
      );
    }
    final segments = const LineSplitter()
        .convert(text)
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && !s.startsWith('#'))
        .toList();
    if (segments.isEmpty || segments.length > 20000) {
      throw const FormatException('Número de fragmentos HLS inválido.');
    }
    final urls = [if (maps.isNotEmpty) maps.single, ...segments];
    task.total = 0;
    task.segmentsTotal = urls.length;
    task.segmentsDone = 0;
    notifyListeners();
    for (var i = 0; i < urls.length; i++) {
      _check(task);
      final segment = await mediaGet(
        _active!,
        result.uri.resolve(urls[i]),
        task.source.headers,
      );
      if (invalidMediaType(
        segment.response.headers.contentType?.mimeType ?? '',
      )) {
        throw const FormatException('Un fragmento HLS no es video.');
      }
      final before = task.bytes;
      await _copy(task, segment, sink);
      if (segment.response.contentLength > 0 &&
          task.bytes - before != segment.response.contentLength) {
        throw const HttpException('Fragmento HLS incompleto.');
      }
      task.segmentsDone = i + 1;
      task.progress = (i + 1) / urls.length;
      _progress(task);
    }
    return maps.isEmpty ? 'ts' : 'mp4';
  }
}
