import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:neko_player_pc/catalog.dart';

void main() {
  test('Three primary sources are enabled; JKAnime stays optional', () {
    final api = ProviderClient();
    expect(api.enabledProviders, {'TioAnime', 'AnimeFLV', 'AnimeAV1'});
    api.close();
  });
  test('TioAnime cards use the correct source and absolute image', () {
    final cards = ProviderClient.parseTioCards(
      '<article class="anime"><a href="/anime/test"><img src="/cover.jpg"><h3 class="title">Test</h3></a></article>',
    );
    expect(cards.single.provider, 'TioAnime');
    expect(cards.single.cover, 'https://tioanime.com/cover.jpg');
  });
  test('TioAnime episodes are sorted and deduplicated', () {
    final result = ProviderClient.parseTioDetail(
      const Anime('Test', 'https://tioanime.com/anime/test', ''),
      '<p class="sinopsis">Story</p><script>var episodes=[3,1,2,2];</script>',
    );
    expect(result.episodes.map((e) => e.number), ['1', '2', '3']);
    expect(result.episodes.first.url, 'https://tioanime.com/ver/test-1');
  });
  test('Unsupported embed types are not offered as playable servers', () {
    final servers = ProviderClient.parseTioServers(
      'var videos=[["Mega","https://mega.nz/embed/a"],["Voe","https://voe.sx/e/a"],["YourUpload","https://yourupload.com/embed/b"]];',
    );
    expect(servers, hasLength(2));
    expect(servers.any((s) => s.name.startsWith('Mega')), false);
  });
  test('AnimeFLV uses published episode permalinks, not invented paths', () {
    final detail = ProviderClient.parseMirrorDetail(
      const Anime('Test', 'https://animeflv.or.at/anime/test/', ''),
      '<script class="animeflv-episodes-data" type="application/json">[{"number":1,"permalink":"https://animeflv.or.at/2026/10/13/test-episodio-1/"}]</script>',
    );
    expect(
      detail.episodes.single.url,
      'https://animeflv.or.at/2026/10/13/test-episodio-1/',
    );
  });
  test('AnimeFLV decodes public embed attributes without executing scripts', () {
    final encoded = base64Encode(
      utf8.encode('https://www.mp4upload.com/embed-abc.html'),
    );
    final result = ProviderClient.parseMirrorServers(
      '<div><span class="tooltip-text">MP4Upload</span><button class="server_btn" data-src="$encoded" app_type="SUB"></button></div>',
    );
    expect(result.single.url, 'https://www.mp4upload.com/embed-abc.html');
  });
  test('Merging preserves all discovered source alternatives', () {
    final cards = ProviderClient.merge([
      const Anime('Test', 'https://tioanime.com/anime/test', '', '', [
        'https://animeav1.com/media/test',
      ]),
      const Anime('Test', 'https://animeflv.or.at/anime/test/', ''),
    ]);
    expect(cards.single.alternatives, hasLength(2));
  });
}
