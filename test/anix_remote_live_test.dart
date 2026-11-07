import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neko_player_pc/anix_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'download all five referenced providers and reopen cached code',
    () async {
      final dir = await Directory.systemTemp.createTemp('neko-remote-live-');
      final file = File('${dir.path}/manifest.json');
      final engine = AnixEngine(manifestFile: file);
      try {
        await engine.installManifest(
          await rootBundle.loadString('assets/extensions/anix-extensions.json'),
        );
        for (final id in [
          'animeav1',
          'tioanime',
          'voir-anime-online-streaming',
          'voir-anime-v2-online-streaming',
          'animex-online-streaming',
        ]) {
          await engine.downloadPlugin(id);
          final list = await engine.call('list') as List;
          final provider = list.cast<Map>().singleWhere((p) => p['id'] == id);
          expect(provider['supported'], true);
          expect(provider['downloadable'], false);
          expect(await engine.call('settings', plugin: id), isA<Map>());
          print('$id: descargada, compilada y settings OK');
        }
        await engine.dispose();
        final reopened = AnixEngine(manifestFile: file);
        try {
          final list = await reopened.call('list') as List;
          expect(list.where((p) => p['supported'] == true).length, 38);
        } finally {
          await reopened.dispose();
        }
      } finally {
        await engine.dispose();
        await dir.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
    skip: Platform.environment['ANIX_LIVE_DOWNLOADS'] != '1',
  );
}
