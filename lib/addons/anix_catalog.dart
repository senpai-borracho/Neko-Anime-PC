import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

typedef CatalogFetch = Future<Map<String, dynamic>> Function(
  Uri uri,
  Map<String, dynamic>? body,
);

class AnixCatalogResult {
  final List<Map<String, dynamic>> items;
  final String notice;
  const AnixCatalogResult(this.items, [this.notice = '']);
}

/// Metadatos de portadas, independiente del motor de extensiones.
class AnixCatalog {
  Future<void> _saving = Future.value();
  final CatalogFetch? fetch;
  final Directory directory;
  AnixCatalog({this.fetch, Directory? directory})
    : directory =
          directory ??
          Directory(
            '${Platform.environment['LOCALAPPDATA'] ?? Directory.current.path}/NekoPlayerPC/anix_ui',
          );

  Future<Map<String, dynamic>> _request(
    Uri uri,
    Map<String, dynamic>? body,
  ) async {
    if (fetch != null) return fetch!(uri, body);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    final timeout = Timer(
      const Duration(seconds: 8),
      () => client.close(force: true),
    );
    try {
      final req = await client.openUrl(body == null ? 'GET' : 'POST', uri);
      req.headers.set('Accept', 'application/json');
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(body));
      }
      final res = await req.close();
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      final bytes = BytesBuilder(copy: false);
      await for (final part in res) {
        bytes.add(part);
        if (bytes.length > 3000000) {
          throw const FormatException('Respuesta demasiado grande');
        }
      }
      final data = jsonDecode(utf8.decode(bytes.takeBytes()));
      if (data is! Map) throw const FormatException('JSON inválido');
      return Map<String, dynamic>.from(data);
    } finally {
      timeout.cancel();
      client.close(force: true);
    }
  }

  Future<List<Map<String, dynamic>>> cached(int page) async {
    try {
      final data = jsonDecode(
        await File('${directory.path}/catalog-$page.json').readAsString(),
      );
      return [
        for (final item in (data as List).whereType<Map>())
          Map<String, dynamic>.from(item),
      ];
    } catch (_) {
      return [];
    }
  }

  Future<AnixCatalogResult> load(int page) async {
    try {
      final data = await _request(
        Uri.parse(
          'https://api.jikan.moe/v4/top/anime?filter=airing&page=$page&limit=24',
        ),
        null,
      );
      final raw = data['data'];
      if (raw is! List) throw const FormatException('Catálogo inválido');
      final items = <Map<String, dynamic>>[];
      for (final item in raw.whereType<Map>()) {
        final titles = (item['titles'] is List ? item['titles'] as List : [])
            .whereType<Map>();
        final english = titles.where((t) => t['type'] == 'English').firstOrNull;
        final names = english?['title'];
        final images = item['images'];
        final jpg = images is Map ? images['jpg'] : null;
        items.add({
          'id': 'mal:${item['mal_id']}',
          'title': names is String && names.isNotEmpty
              ? names
              : '${item['title'] ?? ''}',
          'originalTitle': '${item['title'] ?? ''}',
          'image': jpg is Map ? '${jpg['large_image_url'] ?? ''}' : '',
          'synopsis': '${item['synopsis'] ?? ''}',
          'score': item['score'],
          'year': item['year'],
        });
      }
      await _cache(page, items);
      return AnixCatalogResult(items);
    } catch (_) {
      try {
        final result = await _request(Uri.parse('https://graphql.anilist.co'), {
          'query': r'query($page:Int){Page(page:$page,perPage:24){media(type:ANIME,sort:TRENDING_DESC,isAdult:false){id idMal title{romaji english} coverImage{large} description averageScore seasonYear}}}',
          'variables': {'page': page},
        });
        final data = result['data'];
        final p = data is Map ? data['Page'] : null;
        final raw = p is Map ? p['media'] : null;
        if (raw is! List || raw.isEmpty) {
          throw const FormatException('Catálogo vacío');
        }
        final items = [
          for (final item in raw.whereType<Map>())
            <String, dynamic>{
              'id': item['idMal'] != null
                  ? 'mal:${item['idMal']}'
                  : 'ani:${item['id']}',
              'title':
                  '${item['title']?['english'] ?? item['title']?['romaji'] ?? ''}',
              'originalTitle': '${item['title']?['romaji'] ?? ''}',
              'image': '${item['coverImage']?['large'] ?? ''}',
              'synopsis': '${item['description'] ?? ''}',
              'score': (item['averageScore'] as num?)?.toDouble(),
              'year': item['seasonYear'],
            },
        ];
        await _cache(page, items);
        return AnixCatalogResult(items);
      } catch (_) {
        final saved = await cached(page);
        if (saved.isNotEmpty) {
          return AnixCatalogResult(
            saved,
            'Se muestran las portadas guardadas. Puedes seguir buscando en las extensiones.',
          );
        }
        throw const FormatException(
          'No se pudieron cargar las portadas. Puedes buscar un título en las extensiones o reintentar.',
        );
      }
    }
  }

  Future<void> _cache(int page, List<Map<String, dynamic>> items) async {
    if (items.isEmpty) return;
    try {
      await directory.create(recursive: true);
      await File('${directory.path}/catalog-$page.json')
          .writeAsString(jsonEncode(items));
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> preferences() async {
    try {
      return Map<String, dynamic>.from(
        jsonDecode(
          await File('${directory.path}/preferences.json').readAsString(),
        ) as Map,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> savePreferences(Set<String> selected, bool dub) async {
    final text = jsonEncode({'selected': selected.toList(), 'dub': dub});
    _saving = _saving.catchError((_) {}).then((_) async {
      try {
        await directory.create(recursive: true);
        await File('${directory.path}/preferences.json').writeAsString(text);
      } catch (_) {}
    });
    await _saving;
  }
}
