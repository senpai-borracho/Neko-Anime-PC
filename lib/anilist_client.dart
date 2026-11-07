// Cliente mínimo de AniList (API pública GraphQL, sin clave).
// Solo lectura: busca un anime por título y devuelve nota, géneros, estado y
// arte horizontal. Se usa para completar el banner del Inicio; si falla, el
// banner funciona igual sin esos datos. Más adelante servirá de base para el
// cuestionario de recomendaciones y la integración con la cuenta.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

class AniListInfo {
  final int id;

  /// ID del mismo anime en MyAnimeList (null si AniList no lo tiene enlazado).
  final int? malId;

  /// Títulos tal como los publica AniList (romaji e inglés; pueden venir vacíos).
  final String title, titleEnglish;

  /// Ya en español: "En emisión", "Finalizado"...
  final String status;

  /// Nota sobre 10 (AniList la da sobre 100). Null si no tiene.
  final double? score;
  final List<String> genres;

  /// Arte horizontal (puede venir vacío) y portada vertical.
  final String banner, cover;

  /// Sinopsis en inglés, sin etiquetas HTML.
  final String description;
  final int? year;
  const AniListInfo({
    required this.id,
    this.malId,
    this.title = '',
    this.titleEnglish = '',
    this.status = '',
    this.score,
    this.genres = const [],
    this.banner = '',
    this.cover = '',
    this.description = '',
    this.year,
  });
}

class AniListClient {
  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10);
  final Map<String, AniListInfo?> _cache = {};

  void close() => _http.close(force: true);

  static const _query = r'''
query ($search: String) {
  Media(search: $search, type: ANIME, sort: SEARCH_MATCH) {
    id
    idMal
    status
    averageScore
    genres
    bannerImage
    seasonYear
    description(asHtml: false)
    coverImage { extraLarge }
  }
}''';

  static const _status = {
    'RELEASING': 'En emisión',
    'FINISHED': 'Finalizado',
    'NOT_YET_RELEASED': 'Próximamente',
    'CANCELLED': 'Cancelado',
    'HIATUS': 'En pausa',
  };

  static const _genres = {
    'Action': 'Acción',
    'Adventure': 'Aventura',
    'Comedy': 'Comedia',
    'Drama': 'Drama',
    'Ecchi': 'Ecchi',
    'Fantasy': 'Fantasía',
    'Horror': 'Terror',
    'Mahou Shoujo': 'Mahō Shōjo',
    'Mecha': 'Mecha',
    'Music': 'Música',
    'Mystery': 'Misterio',
    'Psychological': 'Psicológico',
    'Romance': 'Romance',
    'Sci-Fi': 'Ciencia ficción',
    'Slice of Life': 'Recuentos de la vida',
    'Sports': 'Deportes',
    'Supernatural': 'Sobrenatural',
    'Thriller': 'Suspenso',
  };

  static String _key(String title) =>
      title.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');

  static String _plain(String html) => html
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Busca [title]. Devuelve null si AniList no lo conoce. Lanza error si no
  /// hay red; esos fallos no se guardan, para poder reintentar.
  Future<AniListInfo?> lookup(String title) async {
    final key = _key(title);
    if (key.isEmpty) return null;
    if (_cache.containsKey(key)) return _cache[key];
    final result = await _fetch(title);
    _cache[key] = result;
    return result;
  }

  static const _rankQuery = r"""
query ($sort: [MediaSort], $perPage: Int, $season: MediaSeason, $seasonYear: Int, $status: MediaStatus) {
  Page(page: 1, perPage: $perPage) {
    media(type: ANIME, sort: $sort, isAdult: false, season: $season, seasonYear: $seasonYear, status: $status) {
      id
      idMal
      title { romaji english }
      status
      averageScore
      genres
      bannerImage
      seasonYear
      description(asHtml: false)
      coverImage { extraLarge }
    }
  }
}""";

  static const _sorts = {
    'trending': 'TRENDING_DESC',
    'popular': 'POPULARITY_DESC',
    'top': 'SCORE_DESC',
    'season': 'POPULARITY_DESC',
  };

  final Map<String, List<AniListInfo>> _rankCache = {};

  /// Ranking de AniList: [mode] es 'trending', 'popular', 'top' o 'season'.
  Future<List<AniListInfo>> ranking(String mode, {int count = 10}) async {
    final cached = _rankCache[mode];
    if (cached != null) return cached;
    final sort = _sorts[mode];
    if (sort == null) return const [];
    var result = <AniListInfo>[];
    if (mode == 'season') {
      // Estrenos: temporada actual de AniList (invierno, primavera, verano u
      // otoño), ordenados por popularidad.
      final now = DateTime.now();
      final season = ['WINTER', 'SPRING', 'SUMMER', 'FALL'][(now.month - 1) ~/ 3];
      try {
        result = await _rankRequest(sort, count, season: season, year: now.year);
      } catch (_) {}
      // Plan B: si la temporada viene vacía (o falla), los que están en emisión.
      if (result.isEmpty) {
        result = await _rankRequest(sort, count, status: 'RELEASING');
      }
    } else {
      result = await _rankRequest(sort, count);
    }
    if (result.isNotEmpty) _rankCache[mode] = result;
    return result;
  }

  Future<List<AniListInfo>> _rankRequest(
    String sort,
    int count, {
    String? season,
    int? year,
    String? status,
  }) async {
    final data = await _post(_rankQuery, {
      'sort': [sort],
      'perPage': count,
      if (season != null) 'season': season,
      if (year != null) 'seasonYear': year,
      if (status != null) 'status': status,
    });
    final page = data is Map ? data['Page'] : null;
    final media = page is Map ? page['media'] : null;
    return [
      for (final item in (media is List ? media : const []))
        if (item is Map) _info(item),
    ];
  }

  static const _airingQuery = r'''
query ($from: Int, $to: Int, $page: Int) {
  Page(page: $page, perPage: 50) {
    pageInfo { hasNextPage }
    airingSchedules(airingAt_greater: $from, airingAt_lesser: $to, sort: TIME) {
      airingAt
      episode
      media {
        id
        idMal
        isAdult
        title { romaji english native }
        coverImage { large extraLarge }
      }
    }
  }
}''';

  Future<List<Map>> airingSchedules(int fromSec, int toSec, {int maxPages = 10}) async {
    final out = <Map>[];
    for (var page = 1; page <= maxPages; page++) {
      final data = await _post(_airingQuery, {'from': fromSec, 'to': toSec, 'page': page});
      final root = data is Map ? data['Page'] : null;
      final list = root is Map ? root['airingSchedules'] : null;
      if (list is List) {
        for (final item in list) {
          if (item is Map) out.add(item);
        }
      }
      final info = root is Map ? root['pageInfo'] : null;
      if (info is! Map || info['hasNextPage'] != true) break;
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
    return out;
  }

  Future<AniListInfo?> _fetch(String title) async {
    final data = await _post(_query, {'search': title});
    final media = data is Map ? data['Media'] : null;
    if (media is! Map) return null; // "Not Found": no es un error de red.
    return _info(media);
  }

  /// Devuelve el campo "data" de la respuesta GraphQL.
  Future<Object?> _post(String query, Map<String, Object?> variables) async {
    final request = await _http
        .postUrl(Uri.parse('https://graphql.anilist.co'))
        .timeout(const Duration(seconds: 12));
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.add(utf8.encode(jsonEncode({'query': query, 'variables': variables})));
    final response = await request.close().timeout(const Duration(seconds: 15));
    final text = await response
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 429) {
      throw const HttpException('AniList: demasiadas peticiones. Reintenta en un momento.');
    }
    final decoded = jsonDecode(text);
    if (decoded is Map && decoded['data'] == null && decoded['errors'] is List) {
      final errors = decoded['errors'] as List;
      final message = errors.isNotEmpty && errors.first is Map
          ? '${(errors.first as Map)['message']}'
          : 'respuesta no válida';
      throw HttpException('AniList: $message');
    }
    return decoded is Map ? decoded['data'] : null;
  }

  AniListInfo _info(Map media) {
    final score = media['averageScore'];
    final genres = media['genres'];
    final cover = media['coverImage'];
    final banner = media['bannerImage'];
    final description = media['description'];
    final year = media['seasonYear'];
    final names = media['title'];
    return AniListInfo(
      id: (media['id'] as num?)?.toInt() ?? 0,
      malId: (media['idMal'] as num?)?.toInt(),
      title: names is Map && names['romaji'] is String ? names['romaji'] as String : '',
      titleEnglish:
          names is Map && names['english'] is String ? names['english'] as String : '',
      status: _status['${media['status']}'] ?? '',
      score: score is num && score > 0 ? score / 10 : null,
      genres: [
        for (final genre in (genres is List ? genres : const []))
          _genres['$genre'] ?? '$genre',
      ],
      banner: banner is String ? banner : '',
      cover: cover is Map && cover['extraLarge'] is String
          ? cover['extraLarge'] as String
          : '',
      description: description is String ? _plain(description) : '',
      year: year is num ? year.toInt() : null,
    );
  }
}
