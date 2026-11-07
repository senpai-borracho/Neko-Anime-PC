import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:neko_player_pc/catalog.dart';

void main() {
  test(
    'Fast provider becomes visible before the slow provider completes',
    () async {
      final api = DelayedProvider();
      final partial = <PageResult>[];
      final pending = api.catalog(onPartial: partial.add);
      await Future<void>.delayed(Duration.zero);
      expect(partial.single.cards.single.title, 'Fast anime');
      api.slow.complete(
        'var animes = {"data":[{"title":"Slow anime","url":"https://jkanime.net/slow/","image":""}],"last_page":1};',
      );
      expect((await pending).cards, hasLength(2));
      api.close();
    },
  );
  test(
    'Svelte literal parser handles nested data without executing JavaScript',
    () {
      final data =
          LiteralReader(
                r'''[{type:"data",data:{results:[{title:"Naruto",slug:"naruto",description:"A ] bracket"}],missing:void 0,number:12,ok:true}}]''',
                0,
              ).value()
              as List;
      expect(data.first['data']['results'][0]['title'], 'Naruto');
      expect(data.first['data']['missing'], isNull);
      expect(data.first['data']['ok'], true);
    },
  );
  test('Data wrapper keeps returned object only', () {
    final value =
        LiteralReader(
              r'''(function(a){return {title:"Test",episodes:[{number:1}]}}(null))''',
              0,
            ).value()
            as Map;
    expect(value['title'], 'Test');
    expect(value['episodes'].length, 1);
  });
  test('Unified catalog preserves both playback providers', () {
    final cards = ProviderClient.merge([
      const Anime('Bokú no Hero', 'https://jkanime.net/hero/', 'a'),
      const Anime('Boku no Hero', 'https://animeav1.com/media/hero', 'b'),
    ]);
    expect(cards, hasLength(1));
    expect(cards.single.alternatives, ['https://animeav1.com/media/hero']);
  });
  test(
    'Embedded video extraction preserves signed query and rejects samples',
    () {
      expect(
        ProviderClient.extract(
          '<source src="https://cdn.example/ep.mp4?key=abc&amp;part=1">',
          'https://example.com',
        ),
        'https://cdn.example/ep.mp4?key=abc&part=1',
      );
      expect(
        ProviderClient.extract(
          '<source src="https://samplelib.com/test.mp4">',
          'https://example.com',
        ),
        isNull,
      );
    },
  );
}

class DelayedProvider extends ProviderClient {
  DelayedProvider() : super(enabledProviders: {'JKAnime', 'AnimeAV1'});
  final slow = Completer<String>();
  @override
  Future<String> fetch(
    String url, {
    String referer = '',
    Map<String, String>? form,
    bool cached = true,
  }) async {
    if (url.contains('jkanime.net')) return slow.future;
    return '<script>__sveltekit_test; data:[{results:[{title:"Fast anime",slug:"fast",id:1}],pagination:{currentPage:1,totalPages:1}}]</script>';
  }
}
