import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neko_player_pc/anix_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('real import restarts repeatedly, isolates process generations and persists exact manifest', () async {
    final directory = await Directory.systemTemp.createTemp(
      'neko-reload-test-',
    );
    final file = File('${directory.path}/manifest.json');
    final engine = AnixEngine(manifestFile: file);
    addTearDown(() async {
      await engine.dispose();
      await directory.delete(recursive: true);
    });
    final text = await rootBundle.loadString(
      'assets/extensions/anix-extensions.json',
    );
    await Future.wait([
      engine.call('list'),
      engine.call('settings', plugin: 'anizone'),
    ]);
    for (var i = 0; i < 15; i++) {
      expect(await engine.installManifest(text), 38);
      final results = await Future.wait([
        engine.call('list'),
        engine.call('settings', plugin: 'anizone'),
      ]);
      expect((results[0] as List).length, 38);
      expect(results[1], isA<Map>());
    }
    await engine.dispose();
    final reopened = AnixEngine(manifestFile: file);
    try {
      expect((await reopened.call('list') as List).length, 38);
      expect(reopened.importedManifest, true);
      expect(await file.readAsString(), text);
      await expectLater(
        reopened.installManifest('{"plugins":null}'),
        throwsFormatException,
      );
      expect((await reopened.call('list') as List).length, 38);
    } finally {
      await reopened.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
