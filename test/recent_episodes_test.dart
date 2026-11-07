import 'package:flutter_test/flutter_test.dart';
import 'package:neko_player_pc/catalog.dart';
import 'package:neko_player_pc/recent_episodes.dart';

const tio =
    '<a href="/ver/prueba-2"><img src="/uploads/1.jpg"><h3>Prueba 2</h3></a>';
const mirror =
    '<a href="https://animeflv.or.at/2026/10/29/prueba-episodio-2/"><img src="/cover.jpg"><h2>Prueba Episodio 2</h2></a>';

class FeedProvider extends ProviderClient {
  bool fail = false;
  @override
  Future<String> fetch(
    String url, {
    String referer = '',
    Map<String, String>? form,
    bool cached = true,
  }) async {
    if (fail) throw const FormatException('offline');
    if (url == 'https://tioanime.com/') return tio;
    if (url == 'https://animeflv.or.at/') return mirror;
    return '<a class="breadcrumb-current" href="https://animeflv.or.at/anime/prueba-publicada/">Prueba</a>';
  }
}

void main() {
  test('TioAnime releases include title, episode, image and anime link', () {
    final item = RecentEpisodes.parse('TioAnime', tio).single;
    expect(item.title, 'Prueba');
    expect(item.number, '2');
    expect(item.cover, 'https://tioanime.com/uploads/1.jpg');
    expect(item.animeUrl, 'https://tioanime.com/anime/prueba');
  });
  test('AnimeFLV preserves the actual published episode permalink', () {
    final item = RecentEpisodes.parse('AnimeFLV', mirror).single;
    expect(item.title, 'Prueba');
    expect(item.number, '2');
    expect(
      item.episodeUrl,
      'https://animeflv.or.at/2026/10/29/prueba-episodio-2/',
    );
    expect(item.animeUrl, isNull);
  });
  test('AnimeAV1 releases read structured media and episode data', () {
    final items = RecentEpisodes.parse(
      'AnimeAV1',
      '<script>__sveltekit_x = {data:[{episodes:[{number:4,media:{id:1,title:"Prueba",slug:"prueba"}}]}]};</script>',
    );
    expect(items.single.title, 'Prueba');
    expect(items.single.number, '4');
    expect(items.single.animeUrl, 'https://animeav1.com/media/prueba');
  });
  test('Deduplicate across sources, filter, preserve offline results and respect disabled sources', () async {
    final api = FeedProvider();
    addTearDown(api.close);
    final feed = RecentEpisodes(api);
    await feed.refresh({'TioAnime', 'AnimeFLV'});
    expect(feed.items().length, 1);
    expect(feed.items(provider: 'AnimeFLV').single.provider, 'AnimeFLV');
    api.fail = true;
    await feed.refresh({'AnimeFLV'});
    expect(feed.bySource.containsKey('TioAnime'), false);
    expect(feed.items().length, 1);
    expect(feed.failures, ['AnimeFLV']);
  });
  test(
    'AnimeFLV opens the published anime breadcrumb instead of inventing a URL',
    () async {
      final api = FeedProvider();
      addTearDown(api.close);
      final anime = await RecentEpisodes(api)
          .animeFor(RecentEpisodes.parse('AnimeFLV', mirror).single);
      expect(anime.url, 'https://animeflv.or.at/anime/prueba-publicada/');
    },
  );
}
