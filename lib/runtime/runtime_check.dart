import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../anix_engine.dart';
import '../addons/nuvio_runtime.dart';
import 'node_runtime.dart';

Future<void> verifyBundledRuntime(String output) async {
  final directory = await Directory.systemTemp.createTemp(
    'neko-runtime-check-',
  );
  final manifestFile = File('${directory.path}/manifest.json');
  final engine = AnixEngine(manifestFile: manifestFile);
  try {
    final node = await NodeRuntime.start([
      '-p',
      'JSON.stringify({path:process.execPath,version:process.version})',
    ]);
    final raw = await node.stdout.transform(utf8.decoder).join();
    await node.stderr.drain<void>();
    if (await node.exitCode != 0)
      throw const FormatException('Fallo el runtime incluido.');
    final info = jsonDecode(raw);
    if (File('${info['path']}').absolute.path.toLowerCase() !=
        File(NodeRuntime.resolve()).absolute.path.toLowerCase()) {
      throw const FormatException(
        'Se ejecuto un runtime distinto al incluido.',
      );
    }
    final plugins = await engine.call('list') as List;
    if (plugins.isEmpty)
      throw const FormatException('No se cargaron las extensiones Anix.');
    await engine.call('settings', plugin: 'latanime');
    final inputPath = Platform.environment['NEKO_VERIFY_MANIFEST'];
    final manifest = inputPath == null
        ? await rootBundle.loadString('assets/extensions/anix-extensions.json')
        : await File(inputPath).readAsString();
    final expectedIds = ((jsonDecode(manifest) as Map)['plugins'] as List)
        .map((p) => p['id'])
        .toList();
    for (var i = 0; i < 8; i++) {
      await engine.installManifest(manifest);
      final responses = await Future.wait([
        engine.call('list'),
        engine.call('settings', plugin: 'anizone'),
      ]);
      final actualIds = (responses[0] as List).map((p) => p['id']).toList();
      if (jsonEncode(actualIds) != jsonEncode(expectedIds))
        throw StateError('La lista no coincide con el manifiesto importado.');
    }
    var downloadedProviders = 0;
    if (Platform.environment['NEKO_VERIFY_DOWNLOADS'] == '1') {
      final pending = (await engine.call('list') as List)
          .where((p) => p['downloadable'] == true)
          .toList();
      for (final entry in pending) {
        await engine.downloadPlugin('${entry['id']}');
        await engine.call('settings', plugin: '${entry['id']}');
        downloadedProviders++;
      }
    }
    await engine.dispose();
    final reopened = AnixEngine(manifestFile: manifestFile);
    try {
      final loaded = await reopened.call('list') as List;
      if (!reopened.importedManifest ||
          jsonEncode(loaded.map((p) => p['id']).toList()) !=
              jsonEncode(expectedIds)) {
        throw StateError('No se conservó el manifiesto importado.');
      }
    } finally {
      await reopened.dispose();
    }
    final script = File('${directory.path}/fixture.js');
    await script.writeAsString(
      "module.exports.getStreams=async(id,type,s,e)=>[{url:'https://example.invalid/'+id+'/'+type+'/'+s+'/'+e+'.mp4'}];",
    );
    final streams = await NuvioRuntime.run(script.path, '20', 'tv', 1, 2);
    if (streams.single['url'] != 'https://example.invalid/20/tv/1/2.mp4')
      throw const FormatException('Fallo el contrato Nuvio.');
    await File(output).writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'ok': true,
        'node': info,
        'anixProviders': plugins.length,
        'anixSettings': true,
        'manifestRestartCycles': 8,
        'importedIdsMatch': true,
        'manifestPersists': true,
        'downloadedProviders': downloadedProviders,
        'nuvioContract': true,
        'pathUsedForNode': false,
        'nodeOptionsInherited': NodeRuntime.environment.containsKey(
          'NODE_OPTIONS',
        ),
      }),
      flush: true,
    );
  } finally {
    await engine.dispose();
    await directory.delete(recursive: true);
  }
}
