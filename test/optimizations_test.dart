import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neko_player_pc/main.dart' show Cover;
import 'package:neko_player_pc/addons/stremio_client.dart';

void main() {
  test(
    'concurrent manifest requests share one fetch and expire after a minute',
    () async {
      var calls = 0;
      var time = DateTime(2026);
      final pending = Completer<Map<String, dynamic>>();
      final client = StremioClient(
        now: () => time,
        fetchJson: (_) {
          calls++;
          return pending.future;
        },
      );
      final first = client.manifest('https://example.org/manifest.json');
      final second = client.manifest('https://example.org/manifest.json');
      expect(calls, 1);
      pending.complete({'name': 'fixture'});
      expect(await first, await second);
      await client.manifest('https://example.org/manifest.json');
      expect(calls, 1);
      time = time.add(const Duration(seconds: 61));
      await client.manifest('https://example.org/manifest.json');
      expect(calls, 2);
    },
  );

  test(
    'failed manifests can retry and bounded cache evicts old repositories',
    () async {
      var fails = true, calls = 0;
      final client = StremioClient(
        fetchJson: (_) async {
          calls++;
          if (fails) throw const FormatException('offline');
          return {'name': 'fixture'};
        },
      );
      await expectLater(
        client.manifest('https://example.org/first.json'),
        throwsFormatException,
      );
      fails = false;
      await client.manifest('https://example.org/first.json');
      expect(calls, 2);
      for (var i = 0; i < 8; i++) {
        await client.manifest('https://example.org/$i.json');
      }
      await client.manifest('https://example.org/first.json');
      expect(calls, 11);
    },
  );

  testWidgets(
    'poster thumbnails decode at physical display width; full covers remain unchanged',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(devicePixelRatio: 2),
            child: Column(
              children: [
                SizedBox(
                  width: 120,
                  height: 180,
                  child: Cover(
                    'https://example.invalid/poster.jpg',
                    thumbnail: true,
                  ),
                ),
                SizedBox(
                  width: 120,
                  height: 180,
                  child: Cover('https://example.invalid/full.jpg'),
                ),
              ],
            ),
          ),
        ),
      );
      final images = tester.widgetList<Image>(find.byType(Image)).toList();
      expect(images.first.image, isA<ResizeImage>());
      expect((images.first.image as ResizeImage).width, 240);
      expect(images.last.image, isA<NetworkImage>());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
