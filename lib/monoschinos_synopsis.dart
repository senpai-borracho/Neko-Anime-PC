import 'package:html/parser.dart' as html;

import 'monoschinos_client.dart';

// Metadata only; does not alter episode or playback extraction.
class MonosSynopsis {
  static Future<String> load(MonosClient client, MonosEntry anime) async =>
      parse(await client.get(anime.url), client.site);

  static String parse(String body, MonosSite site) {
    final doc = html.parse(body);
    final selectors = [
      '.sinopsis',
      '.synopsis',
      '[itemprop="description"]',
      if (site.base == monosSites[0].base) '.h-100 .mb-3 p',
      if (monosSites.length > 1 && site.base == monosSites[1].base)
        'p[class~="text-white/75"]',
      // LatAnime
      if (site.kind == 'latanime') 'p.my-2.opacity-75',
      // OtakusTV / AnimeYT / AnimeYTX
      if (site.kind != 'monos' && site.kind != 'latanime') '.tx p',
    ];
    for (final selector in selectors) {
      final text =
          doc
              .querySelector(selector)
              ?.text
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim() ??
          '';
      if (text.isNotEmpty) {
        return text.replaceFirst(
          RegExp(r'^Sinopsis de [^:]{1,150}:\s*', caseSensitive: false),
          '',
        );
      }
    }
    return '';
  }
}
