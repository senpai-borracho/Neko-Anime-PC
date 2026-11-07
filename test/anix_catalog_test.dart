import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:neko_player_pc/addons/anix_catalog.dart';

void main() {
  test('Jikan failure falls back to AniList; cached covers survive both services failing', () async {
    final directory = await Directory.systemTemp.createTemp(
      'neko-anix-catalog-',
    );
    try {
      final calls = <String>[];
      final client = AnixCatalog(
        directory: directory,
        fetch: (uri, body) async {
          calls.add(uri.host);
          if (uri.host == 'api.jikan.moe')
            throw const SocketException('timeout');
          return {
            'data': {
              'Page': {
                'media': [
                  {
                    'id': 1,
                    'idMal': 20,
                    'title': {'romaji': 'Naruto'},
                    'coverImage': {'large': 'https://example.org/naruto.jpg'},
                  },
                ],
              },
            },
          };
        },
      );
      expect((await client.load(1)).items.single['title'], 'Naruto');
      expect(calls, ['api.jikan.moe', 'graphql.anilist.co']);
      final offline = AnixCatalog(
        directory: directory,
        fetch: (_, _) async => throw const SocketException('offline'),
      );
      final cached = await offline.load(1);
      expect(cached.items.single['title'], 'Naruto');
      expect(cached.notice, contains('guardadas'));
      await client.savePreferences({'anizone', 'animeparadise'}, false);
      expect((await offline.preferences())!['selected'], [
        'anizone',
        'animeparadise',
      ]);
    } finally {
      await directory.delete(recursive: true);
    }
  });

}
