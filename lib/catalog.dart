import 'dart:convert';
import 'dart:io';

import 'package:html/parser.dart' as html;

const userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';
String providerForUrl(String url) {
  final host = Uri.parse(url).host;
  if (host.endsWith('animeav1.com')) return 'AnimeAV1';
  if (host.endsWith('tioanime.com')) return 'TioAnime';
  if (host == 'animeflv.or.at') return 'AnimeFLV';
  return 'JKAnime';
}

class Anime {
  final String title, url, cover, badge;
  final List<String> alternatives;
  const Anime(
    this.title,
    this.url,
    this.cover, [
    this.badge = '',
    this.alternatives = const [],
  ]);
  String get provider => providerForUrl(url);
  Map<String, dynamic> toJson() => {
    'title': title,
    'url': url,
    'cover': cover,
    'badge': badge,
    'alternatives': alternatives,
  };
  factory Anime.fromJson(Map<String, dynamic> j) => Anime(
    j['title'],
    j['url'],
    j['cover'] ?? '',
    j['badge'] ?? '',
    List<String>.from(j['alternatives'] ?? []),
  );
}

class Episode {
  final String number, url;
  const Episode(this.number, this.url);
}

class Detail {
  final Anime anime;
  final String synopsis;
  final List<Episode> episodes;
  const Detail(this.anime, this.synopsis, this.episodes);
}

class Server {
  final String name, url;
  const Server(this.name, this.url);
}

class StreamSource {
  final String url, referer, cookies;
  const StreamSource(this.url, this.referer, [this.cookies = '']);
}

class PageResult {
  final List<Anime> cards;
  final bool more;
  const PageResult(this.cards, this.more);
}

/// Public provider pages are parsed as data; remote JavaScript is never evaluated.
class ProviderClient {
  final Set<String> enabledProviders;
  ProviderClient({Set<String>? enabledProviders})
    : enabledProviders = {
        ...(enabledProviders ?? {'TioAnime', 'AnimeFLV', 'AnimeAV1'}),
      };
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..userAgent = userAgent;
  final Map<String, List<Cookie>> _cookies = {};
  final Map<String, (DateTime, String)> _cache = {};
  String notice = '';
  Future<String> fetch(
    String url, {
    String referer = '',
    Map<String, String>? form,
    bool cached = true,
  }) async {
    final uri = Uri.parse(url);
    if (uri.scheme != 'https') {
      throw const FormatException('El servidor debe utilizar HTTPS.');
    }
    if (form == null && cached) {
      final hit = _cache[url];
      if (hit != null && DateTime.now().difference(hit.$1).inSeconds < 90) {
        return hit.$2;
      }
    }
    final request = await _client
        .openUrl(form == null ? 'GET' : 'POST', uri)
        .timeout(const Duration(seconds: 20));
    request.headers.set(HttpHeaders.userAgentHeader, userAgent);
    if (referer.isNotEmpty) {
      request.headers.set(HttpHeaders.refererHeader, referer);
    }
    request.cookies.addAll(_cookies[uri.host] ?? []);
    if (form != null) {
      request.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
        charset: 'utf-8',
      );
      request.headers.set('X-Requested-With', 'XMLHttpRequest');
      request.write(Uri(queryParameters: form).query);
    }
    final response = await request.close().timeout(const Duration(seconds: 25));
    final jar = _cookies.putIfAbsent(uri.host, () => []);
    for (final cookie in response.cookies) {
      jar.removeWhere((c) => c.name == cookie.name);
      jar.add(cookie);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.drain<void>();
      throw HttpException('HTTP ${response.statusCode} en ${uri.host}');
    }
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 25))) {
      bytes.addAll(chunk);
      if (bytes.length > 4 * 1024 * 1024) {
        throw const FormatException(
          'Respuesta del proveedor demasiado grande.',
        );
      }
    }
    final text = utf8.decode(bytes, allowMalformed: true);
    if (form == null && cached) {
      _cache[url] = (DateTime.now(), text);
      if (_cache.length > 60) _cache.remove(_cache.keys.first);
    }
    return text;
  }

  String cookieHeader(String url) => (_cookies[Uri.parse(url).host] ?? [])
      .map((c) => '${c.name}=${c.value}')
      .join('; ');
  static String key(String title) {
    var t = title.toLowerCase();
    for (final pair in ['áa', 'ée', 'íi', 'óo', 'úu', 'ñn', 'üu']) {
      t = t.replaceAll(pair[0], pair[1]);
    }
    return t.replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ').trim();
  }

  static List<Anime> merge(List<Anime> cards) {
    final groups = <String, List<Anime>>{};
    for (final c in cards) {
      groups.putIfAbsent(key(c.title), () => []).add(c);
    }
    return groups.values.map((g) {
      final first = g.first;
      return Anime(
        first.title,
        first.url,
        first.cover,
        first.badge,
        g
            .expand((a) => [a.url, ...a.alternatives])
            .where((u) => u != first.url)
            .toSet()
            .toList(),
      );
    }).toList();
  }

  Future<PageResult> catalog({
    int page = 1,
    String query = '',
    void Function(PageResult)? onPartial,
  }) async {
    final failures = <String>[];
    final ready = <PageResult>[];
    Future<PageResult> safe(
      String provider,
      Future<PageResult> Function() action,
    ) async {
      try {
        final result = await action();
        ready.add(result);
        if (result.cards.isNotEmpty) {
          onPartial?.call(
            PageResult(
              merge(ready.expand((p) => p.cards).toList()),
              ready.any((p) => p.more),
            ),
          );
        }
        return result;
      } catch (_) {
        failures.add(provider);
        return const PageResult([], false);
      }
    }

    final tasks = <Future<PageResult>>[
      if (enabledProviders.contains('AnimeFLV'))
        safe('AnimeFLV', () => _mirrorPage(page, query)),
      if (enabledProviders.contains('TioAnime'))
        safe('TioAnime', () => _tioPage(page, query)),
      if (enabledProviders.contains('AnimeAV1'))
        safe('AnimeAV1', () => _avPage(page, query)),
      if (enabledProviders.contains('JKAnime'))
        safe('JKAnime', () => _jkPage(page, query)),
    ];
    if (tasks.isEmpty) return const PageResult([], false);
    final results = await Future.wait(tasks);
    notice = failures.isEmpty
        ? ''
        : '${failures.join(' y ')} no respondió. Puedes reintentar.';
    if (failures.length == tasks.length) throw HttpException(notice);
    return PageResult(
      merge(results.expand((p) => p.cards).toList()),
      results.any((p) => p.more),
    );
  }

  Future<PageResult> _jkPage(int page, String query) async {
    final url = query.isEmpty
        ? 'https://jkanime.net/directorio?p=$page'
        : 'https://jkanime.net/buscar?q=${Uri.encodeQueryComponent(query)}';
    final text = await fetch(url, referer: 'https://jkanime.net/');
    if (query.isNotEmpty) {
      final doc = html.parse(text);
      final cards = <Anime>[];
      for (final item in doc.querySelectorAll('.anime__item')) {
        final a =
            item.querySelector('h5 a[href]') ?? item.querySelector('a[href]');
        if (a == null) continue;
        final uri = Uri.parse(url).resolve(a.attributes['href'] ?? '');
        final title = item.querySelector('h5')?.text.trim() ?? '';
        final img =
            item.querySelector('[data-setbg]') ?? item.querySelector('img');
        if (uri.host == 'jkanime.net' && title.isNotEmpty) {
          cards.add(
            Anime(
              title,
              'https://jkanime.net/${uri.path.split('/').where((s) => s.isNotEmpty).first}/',
              Uri.parse(url)
                  .resolve(
                    img?.attributes['data-setbg'] ??
                        img?.attributes['src'] ??
                        '',
                  )
                  .toString(),
            ),
          );
        }
      }
      return PageResult(cards, false);
    }
    final marker = RegExp(r'var\s+animes\s*=').firstMatch(text);
    if (marker == null) {
      throw const FormatException('Directorio de JKAnime incompatible.');
    }
    final reader = LiteralReader(text, text.indexOf('{', marker.end));
    final data = reader.value() as Map;
    return PageResult(
      (data['data'] as List)
          .map(
            (v) => Anime(
              v['title'].toString(),
              v['url'].toString(),
              v['image']?.toString() ?? '',
              v['tipo']?.toString() ?? '',
            ),
          )
          .toList(),
      page < (data['last_page'] as num).toInt(),
    );
  }

  static List<Anime> parseMirrorCards(String text) {
    final doc = html.parse(text);
    final out = <String, Anime>{};
    for (final a in doc.querySelectorAll('a[href*="/anime/"]')) {
      final image = a.querySelector('img');
      if (image == null) continue;
      final url = Uri.parse('https://animeflv.or.at')
          .resolve(a.attributes['href'] ?? '');
      if (url.host != 'animeflv.or.at' ||
          !url.path.startsWith('/anime/') ||
          url.path == '/anime/') {
        continue;
      }
      final title =
          (image.attributes['alt'] ?? a.querySelector('h2,h3')?.text ?? '')
              .trim();
      if (title.isEmpty) continue;
      final img = image.attributes['data-src'] ?? image.attributes['src'] ?? '';
      out[url.toString()] = Anime(
        title,
        url.toString(),
        img.isEmpty
            ? ''
            : Uri.parse('https://animeflv.or.at').resolve(img).toString(),
        'Anime',
      );
    }
    return out.values.toList();
  }

  Future<PageResult> _mirrorPage(int page, String query) async {
    final url =
        Uri.parse(
              query.isEmpty
                  ? 'https://animeflv.or.at/anime/'
                  : 'https://animeflv.or.at/',
            )
            .replace(
              queryParameters: {
                if (page > 1) 'paged': '$page',
                if (query.isNotEmpty) 's': query,
              },
            )
            .toString();
    final text = await fetch(url, referer: 'https://animeflv.or.at/');
    return PageResult(
      parseMirrorCards(text),
      html.parse(text).querySelector('a.next.page-numbers,a[rel="next"]') !=
          null,
    );
  }

  static Detail parseMirrorDetail(Anime card, String text) {
    final doc = html.parse(text);
    final script = doc.querySelector('script.animeflv-episodes-data');
    if (script == null) {
      throw const FormatException(
        'AnimeFLV no entregó los episodios de esta ficha.',
      );
    }
    final values = jsonDecode(script.text) as List;
    final episodes =
        values
            .whereType<Map>()
            .map((e) => Episode('${e['number']}', e['permalink'].toString()))
            .where((e) => Uri.parse(e.url).host == 'animeflv.or.at')
            .toList()
          ..sort(
            (a, b) => (double.tryParse(a.number) ?? 0).compareTo(
              double.tryParse(b.number) ?? 0,
            ),
          );
    return Detail(
      card,
      doc
              .querySelector('.anime-synopsis')
              ?.text
              .replaceFirst('Sinopsis', '')
              .trim() ??
          '',
      episodes,
    );
  }

  static List<Server> parseMirrorServers(String text) {
    final doc = html.parse(text);
    final servers = <Server>[];
    for (final button in doc.querySelectorAll('.server_btn[data-src]')) {
      final name =
          button.parent?.querySelector('.tooltip-text')?.text.trim() ??
          'Servidor';
      if (!RegExp(
        r'mp4upload|voe|yourupload',
        caseSensitive: false,
      ).hasMatch(name)) {
        continue;
      }
      try {
        final url = utf8.decode(base64.decode(button.attributes['data-src']!));
        if (url.startsWith('https://')) {
          servers.add(
            Server('$name · ${button.attributes['app_type'] ?? 'SUB'}', url),
          );
        }
      } on FormatException {
        continue;
      }
    }
    servers.sort(
      (a, b) => (a.name.startsWith('MP4Upload') ? 0 : 1).compareTo(
        b.name.startsWith('MP4Upload') ? 0 : 1,
      ),
    );
    if (servers.isEmpty) {
      throw const FormatException(
        'Este episodio de AnimeFLV no tiene servidores compatibles.',
      );
    }
    return servers;
  }

  static List<Anime> parseTioCards(String text) {
    final doc = html.parse(text);
    final result = <Anime>[];
    for (final item in doc.querySelectorAll('article.anime')) {
      final link = item.querySelector('a[href*="/anime/"]');
      final title = item.querySelector('h3.title')?.text.trim() ?? '';
      if (link == null || title.isEmpty) continue;
      final url = Uri.parse('https://tioanime.com')
          .resolve(link.attributes['href'] ?? '');
      if (url.host != 'tioanime.com' || !url.path.startsWith('/anime/')) {
        continue;
      }
      final image = item.querySelector('img');
      final cover =
          image?.attributes['data-src'] ?? image?.attributes['src'] ?? '';
      result.add(
        Anime(
          title,
          url.toString(),
          cover.isEmpty
              ? ''
              : Uri.parse('https://tioanime.com').resolve(cover).toString(),
          'Anime',
        ),
      );
    }
    return {for (final card in result) card.url: card}.values.toList();
  }

  Future<PageResult> _tioPage(int page, String query) async {
    final text = await fetch(
      'https://tioanime.com/directorio?p=$page${query.isEmpty ? '' : '&q=${Uri.encodeQueryComponent(query)}'}',
      referer: 'https://tioanime.com/',
    );
    final cards = parseTioCards(text);
    final more = html.parse(text).querySelector('a[rel="next"]') != null;
    return PageResult(cards, more);
  }

  static dynamic dataVariable(String text, String name) {
    final marker = RegExp('(?:var\\s+)?${RegExp.escape(name)}\\s*=')
        .firstMatch(text);
    if (marker == null) throw FormatException('El proveedor no entregó $name.');
    var index = marker.end;
    while (index < text.length && RegExp(r'\s').hasMatch(text[index])) {
      index++;
    }
    return LiteralReader(text, index).value();
  }

  static Detail parseTioDetail(Anime card, String text) {
    final doc = html.parse(text);
    final slug = Uri.parse(card.url).pathSegments
        .where((v) => v.isNotEmpty)
        .last;
    final numbers = <int>{};
    try {
      final list = dataVariable(text, 'episodes');
      if (list is List) {
        for (final value in list) {
          final number = int.tryParse(value.toString());
          if (number != null && number > 0) numbers.add(number);
        }
      }
    } on FormatException {
      /* Fall back to ordinary episode links. */
    }
    if (numbers.isEmpty) {
      for (final a in doc.querySelectorAll('a[href*="/ver/"]')) {
        final match = RegExp('${RegExp.escape(slug)}-(\\d+)')
            .firstMatch(a.attributes['href'] ?? '');
        if (match != null) numbers.add(int.parse(match[1]!));
      }
    }
    final ordered = numbers.toList()..sort();
    return Detail(
      card,
      doc.querySelector('p.sinopsis,.description')?.text.trim() ?? '',
      ordered
          .map((n) => Episode('$n', 'https://tioanime.com/ver/$slug-$n'))
          .toList(),
    );
  }

  static List<Server> parseTioServers(String text) {
    final values = dataVariable(text, 'videos');
    final servers = <Server>[];
    if (values is List) {
      for (final value in values) {
        if (value is! List || value.length < 2) continue;
        final name = value[0].toString();
        final url = value[1].toString();
        if (url.startsWith('https://') &&
            (RegExp(
                  r'voe|yourupload|mp4upload',
                  caseSensitive: false,
                ).hasMatch(name) ||
                isMedia(url))) {
          servers.add(Server('$name · SUB', url));
        }
      }
    }
    servers.sort(
      (a, b) => (a.name.startsWith('YourUpload') ? 0 : 1).compareTo(
        b.name.startsWith('YourUpload') ? 0 : 1,
      ),
    );
    if (servers.isEmpty) {
      throw const FormatException(
        'TioAnime no entregó servidores compatibles para este episodio.',
      );
    }
    return servers;
  }

  static dynamic avData(String text) {
    final doc = html.parse(text);
    final script = doc
        .querySelectorAll('script')
        .map((s) => s.text)
        .firstWhere(
          (s) => s.contains('__sveltekit_') && s.contains('data:'),
          orElse: () => throw const FormatException(
            'AnimeAV1 no entregó datos compatibles.',
          ),
        );
    return LiteralReader(
      script,
      script.indexOf('[', script.indexOf('data:')),
    ).value();
  }

  static Iterable<Map> objects(dynamic value) sync* {
    if (value is Map) {
      yield value;
      for (final child in value.values) {
        yield* objects(child);
      }
    } else if (value is List) {
      for (final child in value) {
        yield* objects(child);
      }
    }
  }

  static Anime? avCard(Map node) {
    final title = node['title']?.toString() ?? '',
        slug = node['slug']?.toString() ?? '';
    if (title.isEmpty || slug.isEmpty) return null;
    final image =
        node['poster'] ??
        node['image'] ??
        node['cover'] ??
        'https://cdn.animeav1.com/covers/${node['id']}.jpg';
    return Anime(
      title,
      'https://animeav1.com/media/$slug',
      Uri.parse('https://animeav1.com').resolve(image.toString()).toString(),
      'AnimeAV1',
    );
  }

  Future<PageResult> _avPage(int page, String query) async {
    final url =
        'https://animeav1.com/catalogo?page=$page${query.isEmpty ? '' : '&search=${Uri.encodeQueryComponent(query)}'}';
    final nodes = objects(
      avData(await fetch(url, referer: 'https://animeav1.com/')),
    ).toList();
    final payload = nodes
        .where((n) => n['results'] is List && n['pagination'] is Map)
        .firstOrNull;
    var cards =
        (payload != null
                ? (payload['results'] as List).whereType<Map>()
                : nodes)
            .map(avCard)
            .whereType<Anime>()
            .toList();
    if (query.isNotEmpty) {
      cards = cards
          .where(
            (c) =>
                key(query)
                    .split(' ')
                    .every((term) => key(c.title).contains(term)),
          )
          .toList();
    }
    final pagination = payload?['pagination'] as Map?;
    return PageResult(
      cards,
      query.isEmpty &&
          pagination != null &&
          page < (pagination['totalPages'] as num),
    );
  }

  Future<Detail> detail(Anime card) async {
    final text = await fetch(card.url);
    if (card.provider == 'TioAnime') return parseTioDetail(card, text);
    if (card.provider == 'AnimeFLV') return parseMirrorDetail(card, text);
    if (card.provider == 'AnimeAV1') {
      final slug = Uri.parse(card.url).pathSegments.last;
      final media = objects(avData(text)).firstWhere(
        (n) => n['episodes'] is List && n['slug'] == slug,
        orElse: () =>
            throw const FormatException('No se encontró la ficha del anime.'),
      );
      final episodes =
          (media['episodes'] as List)
              .whereType<Map>()
              .map(
                (e) => Episode('${e['number']}', '${card.url}/${e['number']}'),
              )
              .toList()
            ..sort(
              (a, b) => (double.tryParse(a.number) ?? 0).compareTo(
                double.tryParse(b.number) ?? 0,
              ),
            );
      return Detail(
        card,
        html
                .parse(
                  media['synopsis']?.toString() ??
                      media['description']?.toString() ??
                      '',
                )
                .body
                ?.text ??
            '',
        episodes,
      );
    }
    final doc = html.parse(text);
    int total = 0;
    for (final li in doc.querySelectorAll('li')) {
      final match = RegExp(r'Episodios:\s*(\d+)').firstMatch(li.text);
      if (match != null) total = int.parse(match[1]!);
    }
    final upcoming =
        doc.querySelector('.enemision.standby,[data-status=standby]') != null;
    final endpoint = RegExp(r'/ajax/episodes/(\d+)/').firstMatch(text)?[1];
    final token = doc
        .querySelector('meta[name=csrf-token]')
        ?.attributes['content'];
    if (!upcoming &&
        endpoint != null &&
        token != null &&
        (total == 0 || doc.querySelector('.enemision.finished') == null)) {
      try {
        final body = await fetch(
          'https://jkanime.net/ajax/episodes/$endpoint/1',
          referer: card.url,
          form: {'_token': token},
        );
        final json = jsonDecode(html.parse(body).body?.text ?? body);
        total = (json['total'] as num?)?.toInt() ?? total;
      } catch (_) {
        /* Keep the episode count supplied by the page. */
      }
    }
    if (upcoming) total = 0;
    if (total == 0 && !upcoming) {
      throw const FormatException('No se pudo obtener la lista de episodios.');
    }
    return Detail(
      card,
      doc.querySelector('.description p,.description,.sinopsis')?.text.trim() ??
          '',
      List.generate(
        total.clamp(0, 5000),
        (i) => Episode(
          '${i + 1}',
          '${card.url.replaceAll(RegExp(r'/$'), '')}/${i + 1}/',
        ),
      ),
    );
  }

  Future<List<Server>> servers(Episode episode) async {
    final text = await fetch(episode.url, cached: false);
    if (providerForUrl(episode.url) == 'TioAnime') return parseTioServers(text);
    if (providerForUrl(episode.url) == 'AnimeFLV') {
      return parseMirrorServers(text);
    }
    final result = <Server>[];
    if (Uri.parse(episode.url).host == 'animeav1.com') {
      for (final node in objects(avData(text))) {
        for (final key in ['embeds', 'streamLinks', 'servers']) {
          final variants = node[key];
          if (variants is! Map) continue;
          for (final variant in ['SUB', 'DUB']) {
            final links = variants[variant] ?? variants[variant.toLowerCase()];
            if (links is List) {
              for (final link in links.whereType<Map>()) {
                final url = link['url']?.toString() ?? '';
                final name = link['server']?.toString() ?? 'Servidor';
                if (url.startsWith('https://') &&
                    !name.toLowerCase().startsWith('byse') &&
                    !name.toLowerCase().startsWith('hls')) {
                  result.add(Server('$name · $variant', url));
                }
              }
            }
          }
        }
      }
      result.sort(
        (a, b) => (a.name.startsWith('MP4Upload') ? 0 : 1).compareTo(
          b.name.startsWith('MP4Upload') ? 0 : 1,
        ),
      );
    } else {
      for (final match in RegExp(
        r"video\[(\d+)\]\s*=\s*'(.*?)';",
        dotAll: true,
      ).allMatches(text)) {
        if (!['0', '1'].contains(match[1])) continue;
        final frame = html.parse(match[2]).querySelector('iframe[src]');
        if (frame != null) {
          final url = Uri.parse(episode.url)
              .resolve(frame.attributes['src']!)
              .toString();
          if (url.startsWith('https://')) {
            result.add(
              Server(match[1] == '1' ? 'Principal' : 'Alternativo', url),
            );
          }
        }
      }
      result.sort(
        (a, b) => (a.name == 'Principal' ? 0 : 1).compareTo(
          b.name == 'Principal' ? 0 : 1,
        ),
      );
    }
    if (result.isEmpty) {
      throw const FormatException(
        'Este episodio no tiene servidores compatibles disponibles.',
      );
    }
    return {for (final server in result) server.url: server}.values.toList();
  }

  static bool isMedia(String url) =>
      RegExp(
        r'\.(m3u8|mp4|webm)(?:[?&#]|$)',
        caseSensitive: false,
      ).hasMatch(url) ||
      url.contains('/stream/jkmedia/');
  static bool fake(String url) => RegExp(
    r'big.?buck.?bunny|test-videos|samplelib|commondatastorage.*gtv',
    caseSensitive: false,
  ).hasMatch(url);
  static String? extract(String text, String base) {
    final cleaned = text.replaceAll(r'\/', '/');
    final doc = html.parse(cleaned);
    for (final element in doc.querySelectorAll(
      'video[src],source[src],meta[property="og:video"]',
    )) {
      final raw =
          element.attributes['src'] ?? element.attributes['content'] ?? '';
      final url = Uri.parse(base).resolve(raw).toString();
      if (isMedia(url) && !fake(url)) return url;
    }
    for (final match in RegExp(
      r'''https://[^\s"'<>\\]+''',
    ).allMatches(cleaned)) {
      final url = html.parseFragment(match[0]!).text ?? match[0]!;
      if (isMedia(url) && !fake(url)) return url;
    }
    return null;
  }

  Future<StreamSource> resolve(Server server, Episode episode) async {
    if (isMedia(server.url)) return StreamSource(server.url, episode.url);
    var base = server.url;
    var text = await fetch(base, referer: episode.url, cached: false);
    if (RegExp(
      r'cf-turnstile|g-recaptcha|cf-chl-widget',
      caseSensitive: false,
    ).hasMatch(text)) {
      throw const FormatException(
        'El servidor solicita verificación de navegador. Elige otro servidor.',
      );
    }
    if (server.name.toLowerCase().startsWith('voe') ||
        Uri.parse(base).host == 'voe.sx') {
      final visited = <String>{base};
      for (int i = 0; i < 3; i++) {
        final next = RegExp(
          r'''window\.location\.href\s*=\s*['"](https://[^'"]+)['"]''',
        ).firstMatch(text)?[1];
        if (next == null) break;
        if (!visited.add(next)) {
          throw const FormatException('Redirección circular del servidor.');
        }
        text = await fetch(next, referer: base, cached: false);
        base = next;
      }
      for (final script
          in html
              .parse(text)
              .querySelectorAll('script[type="application/json"]')) {
        try {
          final payload = jsonDecode(script.text);
          if (payload is! List || payload.isEmpty || payload.first is! String) {
            continue;
          }
          final encoded = payload.first as String;
          final rotated = String.fromCharCodes(
            encoded.codeUnits.map(
              (c) => c >= 65 && c <= 90
                  ? 65 + (c - 65 + 13) % 26
                  : c >= 97 && c <= 122
                  ? 97 + (c - 97 + 13) % 26
                  : c,
            ),
          );
          final cleaned = rotated.replaceAll(
            RegExp(r'@\$|\^\^|~@|%\?|\*~|!!|#&|_'),
            '',
          );
          final decoded = utf8.decode(base64.decode(cleaned));
          final reversed = String.fromCharCodes(
            decoded.codeUnits.map((c) => c - 3).toList().reversed,
          );
          final data = jsonDecode(utf8.decode(base64.decode(reversed)));
          for (final key in ['source', 'direct_access_url']) {
            final url = data[key]?.toString() ?? '';
            if (url.startsWith('https://') && !fake(url)) {
              return StreamSource(url, base, cookieHeader(url));
            }
          }
        } catch (_) {
          continue;
        }
      }
    }
    final media = extract(text, base);
    if (media == null) {
      throw FormatException(
        '${server.name} no expone un video compatible. Prueba otro servidor.',
      );
    }
    return StreamSource(media, base, cookieHeader(media));
  }

  void close() => _client.close(force: true);
}

/// Restricted literal parser, not a JavaScript interpreter. Supports Svelte data wrappers.
class LiteralReader {
  final String text;
  int index;
  LiteralReader(this.text, this.index);
  void space() {
    while (index < text.length && RegExp(r'\s').hasMatch(text[index])) {
      index++;
    }
  }

  dynamic value() {
    space();
    if (index < 0 || index >= text.length) {
      throw const FormatException('Datos incompletos del proveedor.');
    }
    if (text.startsWith('(function(', index)) {
      final end = balanced(index, '(', ')');
      final returned = text.indexOf('return ', index);
      if (returned < 0 || returned > end) {
        throw const FormatException('Datos incompatibles.');
      }
      final nested = LiteralReader(text, text.indexOf('{', returned));
      final result = nested.value();
      index = end + 1;
      return result;
    }
    final c = text[index];
    if (c == '"' || c == "'") return string();
    if (c == '[') {
      index++;
      final out = <dynamic>[];
      space();
      while (text[index] != ']') {
        out.add(value());
        space();
        if (text[index] == ',') {
          index++;
          space();
        } else if (text[index] != ']') {
          throw const FormatException('Lista incompatible.');
        }
      }
      index++;
      return out;
    }
    if (c == '{') {
      index++;
      final out = <String, dynamic>{};
      space();
      while (text[index] != '}') {
        final key = text[index] == '"' || text[index] == "'"
            ? string()
            : token();
        space();
        if (text[index++] != ':') {
          throw const FormatException('Objeto incompatible.');
        }
        out[key] = value();
        space();
        if (text[index] == ',') {
          index++;
          space();
        } else if (text[index] != '}') {
          throw const FormatException('Objeto incompleto.');
        }
      }
      index++;
      return out;
    }
    if (text.startsWith('void 0', index)) {
      index += 6;
      return null;
    }
    final t = token();
    if (t == 'null' || t == 'undefined') return null;
    if (t == 'true') return true;
    if (t == 'false') return false;
    return num.tryParse(t) ?? t;
  }

  String token() {
    space();
    final start = index;
    while (index < text.length &&
        !RegExp(r'[\s,:\[\]{}]').hasMatch(text[index])) {
      index++;
    }
    if (start == index) throw const FormatException('Literal no compatible.');
    return text.substring(start, index);
  }

  String string() {
    final quote = text[index++];
    final out = StringBuffer();
    while (index < text.length) {
      var c = text[index++];
      if (c == quote) return out.toString();
      if (c == '\\') {
        c = text[index++];
        switch (c) {
          case 'n':
            out.write('\n');
          case 'r':
            out.write('\r');
          case 't':
            out.write('\t');
          case 'u':
            out.writeCharCode(
              int.parse(text.substring(index, index + 4), radix: 16),
            );
            index += 4;
          default:
            out.write(c);
        }
      } else {
        out.write(c);
      }
    }
    throw const FormatException('Texto incompleto.');
  }

  int balanced(int start, String open, String close) {
    int depth = 0;
    String? quote;
    bool escaped = false;
    for (int i = start; i < text.length; i++) {
      final c = text[i];
      if (quote != null) {
        if (escaped) {
          escaped = false;
        } else if (c == '\\') {
          escaped = true;
        } else if (c == quote) {
          quote = null;
        }
      } else {
        if (c == '"' || c == "'") {
          quote = c;
        } else if (c == open) {
          depth++;
        } else if (c == close && --depth == 0) {
          return i;
        }
      }
    }
    throw const FormatException('Datos incompletos.');
  }
}
