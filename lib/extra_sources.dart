// Fuentes adicionales (LatAnime, OtakusTV, AnimeYT, AnimeYTX).
//
// Reutilizan el cliente HTTP de MonosClient (mismo manejo de errores, cabeceras
// y reproductor). No modifican TioAnime, AnimeFLV, AnimeAV1 ni catalog.dart.
// Cada fuente nueva = una clase aquí + una línea en monosSites.
import 'dart:convert';

import 'package:html/parser.dart' as html;

import 'catalog.dart';
import 'monoschinos_client.dart';

abstract class ExtraSource {
  const ExtraSource();
  Future<List<MonosEntry>> catalog(MonosClient client, int page, String search);
  Future<List<MonosEntry>> episodes(MonosClient client, MonosEntry anime);
  Future<List<Server>> streams(MonosClient client, MonosEntry episode);
}

final Map<String, ExtraSource> _extraSources = {
  'latanime': const LatAnimeSource(),
  'otakustv': TemplateSource(catalogPath: '/animes', ajaxPath: '/backend'),
  'animeyt': TemplateSource(
    catalogPath: '/animes',
    ajaxPath: '/yt',
    episodeLink: (slug, number) => '/anime/$slug-episodio-$number',
  ),
  'animeytx': TemplateSource(
    catalogPath: '/catalogo',
    ajaxPath: '/yt',
    episodeLink: (slug, number) => '/ver/$slug-$number',
  ),
};

/// null = sitio con los lectores originales de MonosChinos.
ExtraSource? extraSourceFor(MonosSite site) => _extraSources[site.kind];

// ---------------------------------------------------------------- utilidades

String _clean(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();

String _title(String value) => _clean(value)
    .replaceFirst(RegExp(r'^Ver\s+Anime\s+', caseSensitive: false), '')
    .replaceFirst(RegExp(r'\s+Online(?:\s+Gratis)?$', caseSensitive: false), '')
    .trim();

String _pretty(String name) {
  final value = _clean(name);
  return value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);
}

String? _base64Text(String value) {
  try {
    return utf8.decode(base64.decode(base64.normalize(value.trim())));
  } catch (_) {
    return null;
  }
}

/// Equivalente de hex2a() de las páginas: "68747470..." -> "http...".
String? _hexText(String value) {
  final hex = value.trim();
  if (hex.length < 8 ||
      hex.length.isOdd ||
      !RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex)) {
    return null;
  }
  return String.fromCharCodes([
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ]);
}

/// Igual que slugify() de las fichas de AnimeYT.
String _slugify(String text) {
  const from = 'áàäâãéèëêíìïîóòöôõúùüûñç';
  const to = 'aaaaaeeeeiiiiooooouuuunc';
  var value = text.toLowerCase();
  for (var i = 0; i < from.length; i++) {
    value = value.replaceAll(from[i], to[i]);
  }
  return value
      .replaceAll(RegExp(r'[.\s]+'), '-')
      .replaceAll(RegExp(r'[^a-z0-9-]'), '')
      .replaceAll(RegExp(r'-+'), '-')
      .trim();
}

/// Contenido del arreglo `var eps = [["3",""],["2",""],...]` de la ficha.
List<List<String>> _epsArray(String body) {
  final match = RegExp(r'var\s+eps\s*=\s*\[').firstMatch(body);
  if (match == null) return const [];
  final start = match.end - 1;
  var depth = 0;
  var inString = false;
  var escaped = false;
  for (var i = start; i < body.length; i++) {
    final ch = body[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (ch == '\\') {
        escaped = true;
      } else if (ch == '"') {
        inString = false;
      }
      continue;
    }
    if (ch == '"') {
      inString = true;
    } else if (ch == '[') {
      depth++;
    } else if (ch == ']') {
      depth--;
      if (depth == 0) {
        try {
          final data = jsonDecode(body.substring(start, i + 1));
          if (data is List) {
            return [
              for (final row in data)
                if (row is List && row.isNotEmpty)
                  [for (final cell in row) '$cell'],
            ];
          }
        } catch (_) {}
        return const [];
      }
    }
  }
  return const [];
}

/// Los servidores que Neko sabe reproducir van primero; el resto, al final.
const _rankOrder = [
  'voe',
  'mp4upload',
  'yourupload',
  'uqload',
  'mixdrop',
  'streamwish',
  'vidhide',
  'filelions',
];

int _rank(Server server) {
  final text = '${server.name} ${Uri.tryParse(server.url)?.host ?? ''}'
      .toLowerCase();
  for (var i = 0; i < _rankOrder.length; i++) {
    if (text.contains(_rankOrder[i])) return i;
  }
  return _rankOrder.length;
}

List<Server> _sorted(Iterable<Server> servers) {
  final list = servers.toList();
  final position = {for (var i = 0; i < list.length; i++) list[i].url: i};
  list.sort((a, b) {
    final byRank = _rank(a).compareTo(_rank(b));
    return byRank != 0 ? byRank : position[a.url]!.compareTo(position[b.url]!);
  });
  return list;
}

void _addServer(
  Map<String, Server> out,
  MonosClient client,
  String name,
  String raw,
  String page,
) {
  final url = client.absolute(raw, page);
  if (url.isEmpty) return;
  final host = Uri.parse(url).host;
  if (host.endsWith('mega.nz')) return; // no se puede reproducir con libmpv
  out[url] = Server(_pretty(name.isEmpty ? host : name), url);
}

// ------------------------------------------------------------------ LatAnime

/// latanime.org: catálogo /animes?p=N, búsqueda /buscar?q=, servidores en
/// atributos data-player (base64).
class LatAnimeSource extends ExtraSource {
  const LatAnimeSource();

  @override
  Future<List<MonosEntry>> catalog(
    MonosClient client,
    int page,
    String search,
  ) async {
    // La búsqueda devuelve una sola página de resultados.
    if (search.isNotEmpty && page > 1) return const [];
    final url = search.isEmpty
        ? '${client.site.base}/animes?p=$page'
        : '${client.site.base}/buscar?q=${Uri.encodeQueryComponent(search)}';
    final doc = html.parse(await client.get(url));
    final result = <MonosEntry>[];
    final seen = <String>{};
    for (final a in doc.querySelectorAll('a[href]')) {
      final link = client.absolute(a.attributes['href'] ?? '', url);
      if (link.isEmpty ||
          Uri.parse(link).host != Uri.parse(client.site.base).host ||
          !Uri.parse(link).path.startsWith('/anime/')) {
        continue;
      }
      final heading = a.querySelector('h3');
      if (heading == null) continue;
      final title = _title(heading.text);
      if (title.length < 2 || !seen.add(link)) continue;
      result.add(MonosEntry(title, link, client.imageOf(a, url)));
    }
    if (result.isEmpty && page == 1 && search.isEmpty) {
      throw const FormatException(
        'No se encontraron tarjetas. Es posible que el sitio haya cambiado su HTML.',
      );
    }
    return result;
  }

  @override
  Future<List<MonosEntry>> episodes(MonosClient client, MonosEntry anime) async {
    final doc = html.parse(await client.get(anime.url));
    final result = <MonosEntry>[];
    final seen = <String>{};
    for (final a in doc.querySelectorAll('a[href]')) {
      final link = client.absolute(a.attributes['href'] ?? '', anime.url);
      if (link.isEmpty ||
          Uri.parse(link).host != Uri.parse(client.site.base).host ||
          !Uri.parse(link).path.startsWith('/ver/') ||
          !seen.add(link)) {
        continue;
      }
      final title = _clean(a.text);
      result.add(
        MonosEntry(
          title.isEmpty ? Uri.parse(link).pathSegments.last : title,
          link,
          '',
        ),
      );
    }
    if (result.isEmpty) {
      throw const FormatException('No se encontraron episodios en esta ficha.');
    }
    return result;
  }

  @override
  Future<List<Server>> streams(MonosClient client, MonosEntry episode) async {
    final doc = html.parse(await client.get(episode.url));
    final links = <String, Server>{};
    for (final e in doc.querySelectorAll('[data-player]')) {
      final raw = _base64Text(e.attributes['data-player'] ?? '');
      if (raw != null) _addServer(links, client, e.text, raw, episode.url);
    }
    if (links.isEmpty) {
      throw const FormatException(
        'No se encontraron servidores de reproducción.',
      );
    }
    return _sorted(links.values);
  }
}

// ---------------------------------------------- plantilla OtakusTV / AnimeYT

/// Misma plantilla que MonosChinos1: tarjetas article.li, búsqueda ?buscar=,
/// paginación ?pag=. Los servidores se piden por AJAX (acc=opt) y vienen como
/// <li encrypt="HEX">. Los episodios vienen por AJAX (OtakusTV) o en el
/// arreglo `eps` de la ficha (AnimeYT).
class TemplateSource extends ExtraSource {
  TemplateSource({
    required this.catalogPath,
    required this.ajaxPath,
    this.episodeLink,
  });
  final String catalogPath, ajaxPath;
  final String Function(String slug, String number)? episodeLink;

  @override
  Future<List<MonosEntry>> catalog(
    MonosClient client,
    int page,
    String search,
  ) async {
    final path = Uri(
      path: catalogPath,
      queryParameters: {'pag': '$page', if (search.isNotEmpty) 'buscar': search},
    ).toString();
    final base = '${client.site.base}/';
    final doc = html.parse(await client.get('${client.site.base}$path'));
    final result = <MonosEntry>[];
    final seen = <String>{};
    for (final item in doc.querySelectorAll('article.li')) {
      String link = '';
      for (final a in item.querySelectorAll('a[href]')) {
        final candidate = client.absolute(a.attributes['href'] ?? '', base);
        if (candidate.isNotEmpty &&
            Uri.parse(candidate).path.startsWith('/anime/')) {
          link = candidate;
          break;
        }
      }
      if (link.isEmpty || !seen.add(link)) continue;
      final title = _title(
        item.querySelector('h3 a')?.text ??
            item.querySelector('img')?.attributes['alt'] ??
            '',
      );
      if (title.length < 2) continue;
      result.add(MonosEntry(title, link, client.imageOf(item, base)));
    }
    if (result.isEmpty && page == 1 && search.isEmpty) {
      throw const FormatException(
        'No se encontraron tarjetas. Es posible que el sitio haya cambiado su HTML.',
      );
    }
    return result;
  }

  void _collect(
    MonosClient client,
    String fragment,
    List<MonosEntry> result,
    Set<String> seen,
  ) {
    final base = '${client.site.base}/';
    for (final item in html.parse(fragment).querySelectorAll('article.li')) {
      final a = item.querySelector('h3 a') ?? item.querySelector('a[href]');
      if (a == null) continue;
      final link = client.absolute(a.attributes['href'] ?? '', base);
      if (link.isEmpty ||
          !Uri.parse(link).path.startsWith('/ver/') ||
          !seen.add(link)) {
        continue;
      }
      final title = _clean(a.text);
      result.add(
        MonosEntry(
          title.isEmpty ? Uri.parse(link).pathSegments.last : title,
          link,
          '',
        ),
      );
    }
  }

  @override
  Future<List<MonosEntry>> episodes(MonosClient client, MonosEntry anime) async {
    final body = await client.get(anime.url);
    final result = <MonosEntry>[];
    final seen = <String>{};
    final link = episodeLink;
    if (link != null) {
      // AnimeYT: la ficha trae `var eps = [[numero, titulo], ...]`.
      final slug = RegExp(r'data-sl="([^"]+)"').firstMatch(body)?.group(1) ?? '';
      if (slug.isNotEmpty) {
        for (final row in _epsArray(body)) {
          final number = row[0].trim();
          final custom = row.length > 1 ? _clean(row[1]) : '';
          final url = client.absolute(
            link(slug, _slugify(number)),
            '${client.site.base}/',
          );
          if (number.isEmpty || url.isEmpty || !seen.add(url)) continue;
          result.add(
            MonosEntry(
              custom.isEmpty || custom == 'Episodio $number'
                  ? 'Episodio $number'
                  : 'Episodio $number - $custom',
              url,
              '',
            ),
          );
        }
      }
    } else {
      // OtakusTV: la ficha trae los 16 más recientes; el resto por AJAX.
      _collect(client, body, result, seen);
      final dt = html.parse(body).querySelector('#dt');
      if (dt != null) {
        final total = int.tryParse(dt.attributes['data-e'] ?? '') ?? 0;
        final id = dt.attributes['data-i'] ?? '';
        final url = dt.attributes['data-u'] ?? '';
        final pages = (total / 16).ceil().clamp(1, 200).toInt();
        for (var from = 2; from <= pages; from += 6) {
          final parts = await Future.wait([
            for (var p = from; p < from + 6 && p <= pages; p++)
              client
                  .get(
                    '${client.site.base}$ajaxPath',
                    form: {'acc': 'episodes', 'i': id, 'u': url, 'p': '$p'},
                  )
                  .catchError((_) => ''),
          ]);
          for (final part in parts) {
            _collect(client, part, result, seen);
          }
        }
      }
    }
    if (result.isEmpty) {
      throw const FormatException('No se encontraron episodios en esta ficha.');
    }
    return result;
  }

  @override
  Future<List<Server>> streams(MonosClient client, MonosEntry episode) async {
    final doc = html.parse(await client.get(episode.url));
    final base = '${client.site.base}/';
    final links = <String, Server>{};
    Object? failure;
    final token = doc.querySelector('[data-encrypt]')?.attributes['data-encrypt'];
    if (token != null && token.isNotEmpty) {
      try {
        final options = html.parse(
          await client.get(
            '${client.site.base}$ajaxPath',
            form: {'acc': 'opt', 'i': token},
          ),
        );
        for (final li in options.querySelectorAll('[encrypt]')) {
          final value = li.attributes['encrypt'] ?? '';
          _addServer(links, client, li.text, _hexText(value) ?? value, base);
        }
      } catch (e) {
        failure = e;
      }
    }
    for (final e in doc.querySelectorAll('[data-player]')) {
      final raw = _base64Text(e.attributes['data-player'] ?? '');
      if (raw != null) _addServer(links, client, e.text, raw, base);
    }
    if (links.isEmpty) {
      throw FormatException(
        failure == null
            ? 'No se encontraron servidores de reproducción.'
            : 'No se pudieron pedir los servidores: $failure',
      );
    }
    return _sorted(links.values);
  }
}
