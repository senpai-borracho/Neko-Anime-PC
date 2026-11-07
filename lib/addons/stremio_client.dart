import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'catalog_models.dart';
import '../catalog.dart';
import 'plugin_models.dart';
import 'stremio_ref.dart';
import 'spanish_policy.dart';

typedef StremioFetch = Future<Map<String, dynamic>> Function(Uri uri);

/// Mantiene las cabeceras del addon sin cambiar el motor de fuentes existente.
class StremioSource extends StreamSource {
  final Map<String, String> headers;
  final List<Map<String, dynamic>> subtitles;
  StremioSource(String url, this.headers, [this.subtitles = const []])
    : super(url, headers['referer'] ?? '', headers['cookie'] ?? '');
}

class StremioClient {
  final StremioFetch? fetchJson;
  final DateTime Function() _now;
  final Map<String, (DateTime, Map<String, dynamic>)> _manifests = {};
  final Map<String, Future<Map<String, dynamic>>> _pendingManifests = {};
  StremioClient({this.fetchJson, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  static Uri endpoint(
    String manifest,
    String resource,
    String type,
    String id, [
    Map<String, String> extra = const {},
  ]) {
    final base = Uri.parse(manifest);
    if (base.scheme != 'https' || base.host.isEmpty) {
      throw const FormatException('El addon debe usar HTTPS.');
    }
    final segments = [...base.pathSegments]..removeLast();
    final prefix = segments.map(Uri.encodeComponent).join('/');
    final tail = [resource, type, id].map(Uri.encodeComponent).join('/');
    final args = extra.entries
        .map(
          (e) =>
              '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
        )
        .join('&');
    return base.replace(
      path: '$prefix/$tail${args.isEmpty ? '' : '/$args'}.json',
      fragment: '',
    );
  }

  Future<Map<String, dynamic>> _get(Uri uri) async {
    if (fetchJson != null) return fetchJson!(uri);
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final req = await http.getUrl(uri).timeout(const Duration(seconds: 15));
      req.headers.set(HttpHeaders.userAgentHeader, 'NekoMobile/0.3');
      final res = await req.close().timeout(const Duration(seconds: 25));
      if (res.statusCode != 200) {
        throw HttpException('El addon respondió ${res.statusCode}.');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in res.timeout(const Duration(seconds: 25))) {
        bytes.add(chunk);
        if (bytes.length > 8 * 1024 * 1024) {
          throw const FormatException('Respuesta del addon demasiado grande.');
        }
      }
      final json = jsonDecode(utf8.decode(bytes.takeBytes()));
      if (json is! Map) {
        throw const FormatException('Respuesta del addon inválida.');
      }
      return Map<String, dynamic>.from(json);
    } finally {
      http.close(force: true);
    }
  }

  Future<Map<String, dynamic>> manifest(String url) {
    final cached = _manifests[url];
    if (cached != null &&
        _now().difference(cached.$1) < const Duration(seconds: 60)) {
      return Future.value(cached.$2);
    }
    return _pendingManifests.putIfAbsent(url, () => _readManifest(url));
  }

  Future<Map<String, dynamic>> _readManifest(String url) async {
    try {
      final data = await _get(Uri.parse(url));
      _manifests.remove(url);
      _manifests[url] = (_now(), data);
      while (_manifests.length > 8) {
        _manifests.remove(_manifests.keys.first);
      }
      return data;
    } finally {
      _pendingManifests.remove(url);
    }
  }

  Future<BrowseResult> browse(
    InstalledPlugin plugin, {
    String query = '',
    String genre = '',
    int page = 1,
  }) async {
    final url = plugin.info.fileUrl;
    final m = await manifest(url);
    final catalogs = m['catalogs'] is List ? m['catalogs'] as List : const [];
    final items = <Series>[];
    Object? lastError;
    var succeeded = false, more = false;
    // Se limita la concurrencia: cada addon puede declarar muchos catálogos.
    for (final c in catalogs.whereType<Map>()) {
      if (c['type'] is! String || c['id'] is! String) continue;
      final extras = c['extra'] is List ? c['extra'] as List : const [];
      final names = <String>{
        for (final e in extras.whereType<Map>()) '${e['name']}',
        if (c['extraSupported'] is List)
          ...List<String>.from(c['extraSupported']),
      };
      if (query.isNotEmpty && !names.contains('search')) continue;
      if (genre.isNotEmpty && !names.contains('genre')) continue;
      if (genre.isNotEmpty &&
          extras.whereType<Map>().any(
            (e) =>
                e['name'] == 'genre' &&
                e['options'] is List &&
                !(e['options'] as List).contains(genre),
          )) {
        continue;
      }
      if (page > 1 && !names.contains('skip')) continue;
      final args = <String, String>{
        if (query.isNotEmpty) 'search': query,
        if (genre.isNotEmpty) 'genre': genre,
        if (page > 1) 'skip': '${(page - 1) * 100}',
      };
      // No se inventa un género ni otros parámetros obligatorios.
      if (extras.whereType<Map>().any(
        (e) => e['isRequired'] == true && !args.containsKey('${e['name']}'),
      )) {
        continue;
      }
      if (c['extraRequired'] is List &&
          (c['extraRequired'] as List).any((e) => !args.containsKey('$e'))) {
        continue;
      }
      try {
        final data = await _get(
          endpoint(url, 'catalog', '${c['type']}', '${c['id']}', args),
        );
        succeeded = true;
        final metas = data['metas'] is List ? data['metas'] as List : const [];
        if (metas.length >= 100 && names.contains('skip')) more = true;
        for (final meta in metas.whereType<Map>()) {
          if (meta['id'] is! String || meta['name'] is! String) continue;
          final ref = StremioRef(
            url,
            '${meta['type'] ?? c['type']}',
            meta['id'],
            plugin.info.name,
          );
          final title = '${meta['name']}';
          final cover = '${meta['poster'] ?? ''}';
          items.add(
            Series(title, cover, [SourceRef(-2, ref.url, title, cover)]),
          );
        }
      } catch (e) {
        lastError = e;
      }
    }
    if (!succeeded && lastError != null) throw lastError;
    return BrowseResult(items, more);
  }

  Future<SeriesDetail> detail(Series series, SourceRef source) async {
    final ref = StremioRef.parse(source.url)!;
    final data = await _get(endpoint(ref.manifest, 'meta', ref.type, ref.id));
    final meta = data['meta'];
    if (meta is! Map) {
      throw const FormatException('El addon no devolvió la ficha.');
    }
    final type = '${meta['type'] ?? ref.type}';
    final videos = meta['videos'] is List
        ? (meta['videos'] as List)
              .whereType<Map>()
              .where((v) => v['id'] is String)
              .toList()
        : <Map>[];
    videos.sort((a, b) {
      num number(dynamic v) => v is num ? v : num.tryParse('$v') ?? 0;
      final season = number(a['season']).compareTo(number(b['season']));
      return season != 0
          ? season
          : number(a['episode'] ?? a['number'])
                .compareTo(number(b['episode'] ?? b['number']));
    });
    final multiSeason = videos.any(
      (v) => (num.tryParse('${v['season']}') ?? 1) > 1,
    );
    final episodes = <Episode>[
      for (var i = 0; i < videos.length; i++)
        Episode(
          multiSeason
              ? '${videos[i]['season'] ?? 1}x${videos[i]['episode'] ?? i + 1}'
              : '${videos[i]['episode'] ?? videos[i]['number'] ?? i + 1}',
          StremioRef(ref.manifest, type, '${videos[i]['id']}', ref.name).url,
        ),
      if (videos.isEmpty && type == 'movie')
        Episode('1', StremioRef(ref.manifest, type, ref.id, ref.name).url),
    ];
    if (episodes.isEmpty) {
      throw const FormatException('El addon no devolvió episodios.');
    }
    return SeriesDetail(
      series,
      source,
      '${meta['description'] ?? ''}',
      episodes,
    );
  }

  Future<List<Server>> servers(Episode episode) async {
    final ref = StremioRef.parse(episode.url)!;
    final data = await _get(endpoint(ref.manifest, 'stream', ref.type, ref.id));
    final raw = data['streams'] is List ? data['streams'] as List : const [];
    final servers = <Server>[];
    for (final s in raw.whereType<Map>()) {
      if (!SpanishPolicy.allows(s)) continue;
      final uri = Uri.tryParse('${s['url'] ?? ''}');
      if (uri == null ||
          !['http', 'https'].contains(uri.scheme) ||
          uri.host.isEmpty) {
        continue;
      }
      final headers = <String, String>{};
      void add(dynamic h) {
        if (h is Map) h.forEach((k, v) => headers['$k'.toLowerCase()] = '$v');
      }

      add(s['headers']);
      final hints = s['behaviorHints'];
      if (hints is Map && hints['proxyHeaders'] is Map) {
        add((hints['proxyHeaders'] as Map)['request']);
      }
      final payload = base64Url.encode(
        utf8.encode(
          jsonEncode({
            'url': uri.toString(),
            'headers': headers,
            'subtitles': SpanishPolicy.subtitles(s),
          }),
        ),
      );
      servers.add(
        Server(
          '${s['name'] ?? s['description'] ?? s['title'] ?? 'Enlace'}',
          'neko-stream:$payload',
        ),
      );
    }
    if (servers.isEmpty) {
      throw const FormatException(
        'El addon no devolvió enlaces HTTP con español identificado. '
        'Los torrents y enlaces para navegador no están soportados.',
      );
    }
    return servers;
  }

  static StremioSource resolve(Server server) {
    final data = jsonDecode(
      utf8.decode(
        base64Url.decode(server.url.substring('neko-stream:'.length)),
      ),
    );
    return StremioSource(
      '${data['url']}',
      Map<String, String>.from(data['headers'] as Map),
      [
        for (final s in (data['subtitles'] as List? ?? []))
          Map<String, dynamic>.from(s as Map),
      ],
    );
  }
}
