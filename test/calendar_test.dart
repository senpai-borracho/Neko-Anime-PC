import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neko_player_pc/anilist_client.dart';
import 'package:neko_player_pc/calendar_page.dart';

class FakeAniList extends AniListClient {
  int calls = 0;
  @override
  Future<List<Map>> airingSchedules(int fromSec, int toSec, {int maxPages = 10}) async {
    calls++;
    return [
      {
        'airingAt': fromSec + 3600 * 30,
        'episode': 5,
        'media': {
          'id': 1,
          'isAdult': false,
          'title': {'romaji': 'Prueba no Anime', 'english': 'Test Anime', 'native': null},
          'coverImage': {'large': 'https://x/y.jpg'},
        },
      },
      {
        'airingAt': fromSec + 3600 * 40,
        'episode': 1,
        'media': {'id': 2, 'isAdult': true, 'title': {'romaji': 'Adulto'}},
      },
    ];
  }
}

void main() {
  test('Semana lunes-domingo y estados sin "Disponible"', () {
    // Viernes 2026-11-06 -> lunes 2026-11-02.
    expect(CalendarController.mondayOf(DateTime(2026, 11, 6, 16)), DateTime(2026, 11, 2));
    expect(CalendarController.mondayOf(DateTime(2026, 11, 8, 23)), DateTime(2026, 11, 2));
    expect(CalendarController.mondayOf(DateTime(2026, 11, 9)), DateTime(2026, 11, 9));
    final item = AiringItem(
      mediaId: 1,
      episode: 3,
      title: 'X',
      airingAt: DateTime(2026, 11, 6, 12),
    );
    expect(item.statusAt(DateTime(2026, 11, 6, 11)), 'Próximo estreno');
    expect(item.statusAt(DateTime(2026, 11, 6, 13)), 'Emitido');
  });

  test('Caché: una sola consulta por semana y nueva consulta al cambiar de lunes', () async {
    final dir = Directory.systemTemp.createTempSync('neko_calendar_');
    final file = File('${dir.path}/calendar_cache.json');
    var now = DateTime(2026, 11, 6, 10);
    final api = FakeAniList();
    final first = CalendarController(api, cacheFile: file, clock: () => now);
    await first.ensureFresh();
    expect(api.calls, 1);
    expect(first.thisWeek.length, 1); // el +18 se descarta
    expect(first.thisWeek.single.title, 'Prueba no Anime');

    // Reabrir Neko el mismo día: usa caché.
    final second = CalendarController(api, cacheFile: file, clock: () => now);
    await second.ensureFresh();
    expect(api.calls, 1);
    expect(second.thisWeek.length, 1);

    // Botón manual: fuerza consulta.
    await second.ensureFresh(force: true);
    expect(api.calls, 2);

    // Lunes siguiente: vuelve a consultar.
    now = DateTime(2026, 11, 9, 9);
    final third = CalendarController(api, cacheFile: file, clock: () => now);
    await third.ensureFresh();
    expect(api.calls, 3);
    dir.deleteSync(recursive: true);
  });

  test('Mis animes: coincide por título normalizado', () {
    final item = AiringItem(
      mediaId: 1,
      episode: 1,
      title: 'Prueba no Anime',
      titleEnglish: 'Test Anime',
      airingAt: DateTime(2026, 11, 6),
    );
    expect(isFollowedAiring(item, {calendarKey('Test Anime!')}), isTrue);
    expect(isFollowedAiring(item, {calendarKey('Otra cosa distinta')}), isFalse);
  });
}
