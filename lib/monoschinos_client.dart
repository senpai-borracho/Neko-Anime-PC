import 'dart:convert';
import 'dart:io';

import 'package:html/parser.dart' as html;
import 'package:html/dom.dart' as dom;

import 'catalog.dart';
import 'extra_resolvers.dart';
import 'extra_sources.dart';

class MonosSite {
  final String label, base;

  /// 'monos' = lectores de MonosChinos; otro valor = lector de extra_sources.dart.
  final String kind;
  const MonosSite(this.label, this.base, [this.kind = 'monos']);
}

// Importante: no cambiar el orden; los índices se usan en el menú.
const monosSites = [
  MonosSite('MonosChinos1', 'https://vww.monoschinos2.net'),
  MonosSite('MonosChinos2', 'https://monoschinos.st'),
  MonosSite('LatAnime', 'https://latanime.org', 'latanime'),
  MonosSite('OtakusTV', 'https://www.otakustv.net', 'otakustv'),
  MonosSite('AnimeYT', 'https://vvw.animeyt.one', 'animeyt'),
  MonosSite('AnimeYTX', 'https://animeytx.org', 'animeytx'),
];

class MonosEntry {
  final String title, url, image;
  const MonosEntry(this.title, this.url, this.image);
}

class MonosClient {
  final MonosSite site;
  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12);
  MonosClient(this.site);
  final ProviderClient _resolver = ProviderClient();
  void close() {
    _http.close(force: true);
    _resolver.close();
  }

  Future<String> get(String url, {Map<String, String>? form}) async {
    final uri = Uri.parse(url);
    if (uri.scheme != 'https' || uri.host != Uri.parse(site.base).host) {
      throw const FormatException('Enlace fuera del dominio seleccionado.');
    }
    final req = await _http
        .openUrl(form == null ? 'GET' : 'POST', uri)
        .timeout(const Duration(seconds: 15));
    req.headers.set(
      'User-Agent',
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/131.0 Safari/537.36',
    );
    req.headers.set('Referer', '${site.base}/');
    if (form != null) {
      req.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
      );
      req.headers.set('X-Requested-With', 'XMLHttpRequest');
      req.write(Uri(queryParameters: form).query);
    }
    final res = await req.close().timeout(const Duration(seconds: 20));
    if (res.statusCode == 403 || res.statusCode == 503) {
      await res.drain<void>();
      throw FormatException(
        '${site.label} solicita verificación de navegador (HTTP ${res.statusCode}). No se puede cargar con el cliente nativo.',
      );
    }
    if (res.statusCode != 200) {
      await res.drain<void>();
      throw HttpException('HTTP ${res.statusCode}', uri: uri);
    }
    final chunks = <int>[];
    await for (final part in res.timeout(const Duration(seconds: 20))) {
      chunks.addAll(part);
      if (chunks.length > 5 * 1024 * 1024) {
        throw const FormatException('Página demasiado grande');
      }
    }
    final body = utf8.decode(chunks, allowMalformed: true);
    if (body.contains('cf_chl_opt') || body.contains('<title>Just a moment')) {
      throw FormatException(
        '${site.label} solicita verificación de navegador.',
      );
    }
    return body;
  }

  String absolute(String value, String page) {
    if (value.trim().isEmpty || value.startsWith('data:')) return '';
    try {
      final uri = Uri.parse(page).resolve(value.trim());
      return uri.scheme == 'https' ? uri.toString() : '';
    } catch (_) {
      return '';
    }
  }

  String imageOf(dom.Element e, String page) {
    for (final img in e.querySelectorAll('img')) {
      for (final attr in [
        'data-src',
        'data-original',
        'data-lazy-src',
        'src',
      ]) {
        final url = absolute(img.attributes[attr] ?? '', page);
        if (url.isNotEmpty) return url;
      }
    }
    return '';
  }

  List<MonosEntry> parseCards(String body, String page) {
    final doc = html.parse(body);
    final result = <MonosEntry>[];
    final seen = <String>{};
    for (final a in doc.querySelectorAll('a[href]')) {
      final url = absolute(a.attributes['href'] ?? '', page);
      if (url.isEmpty || Uri.parse(url).host != Uri.parse(site.base).host) {
        continue;
      }
      final path = Uri.parse(url).path.toLowerCase();
      if (!path.startsWith('/anime/')) continue;
      final wrapper = a.querySelector('img') != null
          ? a
          : (a.parent?.querySelector('img') != null ? a.parent! : a);
      final img = imageOf(wrapper, page);
      if (img.isEmpty) continue;
      final title =
          (a.attributes['title'] ??
                  a.querySelector('img')?.attributes['alt'] ??
                  wrapper.querySelector('img')?.attributes['alt'] ??
                  a.text)
              .trim();
      if (title.length < 2 || title.length > 170 || !seen.add(url)) continue;
      result.add(MonosEntry(title, url, img));
    }
    return result;
  }

  Future<List<MonosEntry>> catalog(int page, {String search = ''}) async {
    final extra = extraSourceFor(site);
    if (extra != null) return extra.catalog(this, page, search);
    final routes = site == monosSites[0]
        ? [
            Uri(
              path: '/animes',
              queryParameters: {
                'pag': '$page',
                if (search.isNotEmpty) 'buscar': search,
              },
            ).toString(),
          ]
        : [
            Uri(
              path: search.isEmpty ? '/animes' : '/buscar',
              queryParameters: {
                'p': '$page',
                if (search.isNotEmpty) 'q': search,
              },
            ).toString(),
          ];
    Object? last;
    for (final route in routes) {
      try {
        final url = '${site.base}$route';
        final cards = parseCards(await get(url), url);
        if (cards.isNotEmpty) return cards;
      } catch (e) {
        last = e;
      }
    }
    if (last != null) {
      throw Exception('No se pudo consultar ${site.label}: $last');
    }
    throw const FormatException(
      'No se encontraron tarjetas. Es posible que el sitio haya cambiado su HTML.',
    );
  }

  Future<List<MonosEntry>> episodes(MonosEntry anime) async {
    final extra = extraSourceFor(site);
    if (extra != null) return extra.episodes(this, anime);
    var body = await get(anime.url);
    final doc = html.parse(body);
    final dt = doc.querySelector('#dt[data-i][data-u]');
    if (dt != null) {
      final count = int.tryParse(dt.attributes['data-e'] ?? '') ?? 0;
      final parts = <String>[];
      for (var page = 1; page <= (count / 50).ceil().clamp(1, 500); page++) {
        parts.add(
          await get(
            '${site.base}/ajax_pagination',
            form: {
              'acc': 'episodes',
              'i': dt.attributes['data-i']!,
              'u': dt.attributes['data-u']!,
              'p': '$page',
            },
          ),
        );
      }
      body = parts.join('\n');
    }
    final episodeDoc = html.parse(body);
    final entries = <MonosEntry>[];
    final seen = <String>{};
    for (final a in episodeDoc.querySelectorAll('a[href]')) {
      final url = absolute(a.attributes['href'] ?? '', '${site.base}/');
      if (url.isEmpty ||
          Uri.parse(url).host != Uri.parse(site.base).host ||
          url == anime.url ||
          !seen.add(url)) {
        continue;
      }
      final title = (a.attributes['title'] ?? a.text).trim().replaceAll(
        RegExp(r'\s+'),
        ' ',
      );
      final path = Uri.parse(url).path.toLowerCase();
      if (!RegExp(r'episod|capitulo|chapter|/ver/|/watch/|/episode/')
          .hasMatch('$path $title')) {
        continue;
      }
      entries.add(
        MonosEntry(title.isEmpty ? path.split('/').last : title, url, ''),
      );
    }
    if (entries.isEmpty) {
      throw const FormatException(
        'No se encontraron episodios con el extractor experimental.',
      );
    }
    return entries;
  }

  Future<List<Server>> streams(MonosEntry episode) async {
    final extra = extraSourceFor(site);
    if (extra != null) return extra.streams(this, episode);
    final body = await get(episode.url);
    final doc = html.parse(body);
    final token = doc
        .querySelector('[data-encrypt]')
        ?.attributes['data-encrypt'];
    final options = token == null
        ? doc
        : html.parse(
            await get(
              '${site.base}/ajax_pagination',
              form: {'acc': 'opt', 'i': token},
            ),
          );
    final links = <String, Server>{};
    for (final e in options.querySelectorAll(
      '[data-player], video source[src], video[src], iframe[src]',
    )) {
      var raw = e.attributes['src'] ?? '';
      if (e.attributes.containsKey('data-player')) {
        try {
          raw = utf8.decode(base64.decode(e.attributes['data-player']!));
        } catch (_) {
          continue;
        }
      }
      final url = absolute(raw, '${site.base}/');
      if (url.isNotEmpty) {
        links[url] = Server(
          e.text.trim().isEmpty ? Uri.parse(url).host : e.text.trim(),
          url,
        );
      }
    }
    final direct = ProviderClient.extract(body, episode.url);
    if (direct != null) links[direct] = Server('Directo', direct);
    if (links.isEmpty) {
      throw const FormatException(
        'No se encontraron servidores de reproducción.',
      );
    }
    return links.values.toList()..sort(
      (a, b) => (a.name.toLowerCase() == 'voe' ? 0 : 1).compareTo(
        b.name.toLowerCase() == 'voe' ? 0 : 1,
      ),
    );
  }

  Future<StreamSource> resolve(Server server, MonosEntry episode) async {
    final entry = Episode(episode.title, episode.url);
    // Solo las fuentes nuevas usan los lectores extra; MonosChinos1 no cambia.
    if (extraSourceFor(site) != null) {
      final extra = await resolveExtra(_resolver, server, entry);
      if (extra != null) return extra;
    }
    return _resolver.resolve(server, entry);
  }
}
