import 'catalog.dart';

bool hasAnimeSource(Anime anime, String source) =>
    source == 'Todas' ||
    [
      anime.url,
      ...anime.alternatives,
    ].any((url) => providerForUrl(url) == source);

// Presentation selection: the stored anime identity remains unchanged.
Anime animeForSource(Anime anime, String source) {
  if (source == 'Todas' || anime.provider == source) return anime;
  final urls = [anime.url, ...anime.alternatives];
  final selected = urls
      .where((url) => providerForUrl(url) == source)
      .firstOrNull;
  if (selected == null) return anime;
  return Anime(
    anime.title,
    selected,
    anime.cover,
    anime.badge,
    urls.where((url) => url != selected).toList(),
  );
}

const animeFormats = [
  'Todos',
  'Series / TV',
  'Películas',
  'OVA',
  'ONA',
  'Especiales',
  'Sin especificar',
];

String animeFormat(Anime anime) {
  final badge = anime.badge.trim().toLowerCase();
  return switch (badge) {
    'tv' ||
    'serie' ||
    'series' ||
    'series / tv' ||
    'television' => 'Series / TV',
    'movie' ||
    'movies' ||
    'pelicula' ||
    'peliculas' ||
    'película' ||
    'películas' ||
    'film' => 'Películas',
    'ova' || 'ovas' => 'OVA',
    'ona' || 'onas' => 'ONA',
    'special' || 'specials' || 'especial' || 'especiales' => 'Especiales',
    _ => 'Sin especificar',
  };
}

List<Anime> filterAnimePresentation(
  Iterable<Anime> input, {
  String source = 'Todas',
  String format = 'Todos',
  String order = 'Original',
}) {
  final result = input
      .where(
        (a) =>
            hasAnimeSource(a, source) &&
            (format == 'Todos' || animeFormat(a) == format),
      )
      .toList();
  if (order != 'Original') {
    result.sort(
      (a, b) =>
          a.title.toLowerCase().compareTo(b.title.toLowerCase()) *
          (order == 'Z–A' ? -1 : 1),
    );
  }
  return result;
}
