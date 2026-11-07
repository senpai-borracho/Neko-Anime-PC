import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neko_player_pc/main.dart';
import 'package:neko_player_pc/catalog.dart';

void main() {
  late Directory temp;
  late File file;
  const anime = Anime('Prueba', 'https://animeav1.com/media/prueba', '');
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('neko_tracking_');
    file = File('${temp.path}/library.json');
  });
  tearDown(() async => temp.delete(recursive: true));

  test('Old favorites, sources and history survive adding tracking', () async {
    final oldHistory = {
      'anime': anime.toJson(),
      'episodeUrl': '${anime.url}/1',
      'seconds': 20,
      'duration': 120,
    };
    await file.writeAsString(
      jsonEncode({
        'favorites': [anime.toJson()],
        'history': [oldHistory],
        'sources': ['AnimeAV1'],
      }),
    );
    final library = Library(storageFile: file);
    await library.load();
    library.setStatus(anime, 'Terminados');
    await library.flushed;
    final reloaded = Library(storageFile: file);
    await reloaded.load();
    expect(reloaded.statusFor(anime), 'Terminados');
    expect(reloaded.favorites.keys, [anime.url]);
    expect(reloaded.history[anime.url], oldHistory);
    expect(reloaded.enabledSources, {'AnimeAV1'});
    expect(reloaded.savedAnime.length, 1);
  });

  test(
    'Every status persists and removing tracking preserves bookmarks',
    () async {
      final library = Library(storageFile: file);
      await library.load();
      library.toggle(anime);
      for (final status in Library.statuses) {
        library.setStatus(anime, status);
        await library.flushed;
        final reloaded = Library(storageFile: file);
        await reloaded.load();
        expect(reloaded.statusFor(anime), status);
      }
      library.setStatus(anime, null);
      await library.flushed;
      final reloaded = Library(storageFile: file);
      await reloaded.load();
      expect(reloaded.statusFor(anime), isNull);
      expect(reloaded.savedAnime.single.url, anime.url);
    },
  );
  test('Removing continue watching persists without removing tracking or favorites', () async {
    final library = Library(storageFile: file);
    await library.load();
    library.toggle(anime);
    library.setStatus(anime, 'Viendo');
    library.record(
      anime,
      Episode('1', '${anime.url}/1'),
      const Duration(seconds: 30),
      const Duration(seconds: 120),
    );
    await library.flushed;
    library.removeHistory(anime);
    await library.flushed;
    final reloaded = Library(storageFile: file);
    await reloaded.load();
    expect(reloaded.history, isEmpty);
    expect(reloaded.resume(Episode('1', '${anime.url}/1')), 0);
    expect(reloaded.statusFor(anime), 'Viendo');
    expect(reloaded.favorites.containsKey(anime.url), true);
  });
}
