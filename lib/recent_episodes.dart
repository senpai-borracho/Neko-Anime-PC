import 'package:html/parser.dart' as html;

import 'catalog.dart';

class RecentEpisode {
  final String title, number, episodeUrl, cover;
  final String? animeUrl;
  const RecentEpisode(
    this.title,
    this.number,
    this.episodeUrl,
    this.cover, {
    this.animeUrl,
  });
  String get provider => providerForUrl(episodeUrl);
  Anime get card => Anime(
    title,
    animeUrl ?? episodeUrl,
    cover,
    'Episodio $number · $provider',
  );
}

/// Reads public release listings only; playback resolvers remain in catalog.dart.
class RecentEpisodes {
  final ProviderClient api;
  RecentEpisodes(this.api);
  final Map<String, List<RecentEpisode>> bySource = {};
  List<String> failures = [];
  DateTime? checkedAt;
  static const homes = {
    'AnimeAV1': 'https://animeav1.com/',
    'TioAnime': 'https://tioanime.com/',
    'AnimeFLV': 'https://animeflv.or.at/',
  };

  List<RecentEpisode> items({String provider = 'Todas'}) {
    final groups = bySource.entries
        .where((e) => provider == 'Todas' || provider == e.key)
        .map((e) => e.value)
        .toList();
    final result = <RecentEpisode>[];
    final seen = <String>{};
    for (var i = 0; groups.any((g) => i < g.length); i++) {
      for (final group in groups) {
        if (i >= group.length) continue;
        final item = group[i];
        if (seen.add('${ProviderClient.key(item.title)}:${item.number}')) {
          result.add(item);
        }
      }
    }
    return result;
  }

  Future<void> refresh(Set<String> enabled) async {
    final active = {...enabled};
    final failed = <String>[];
    bySource.removeWhere((key, _) => !active.contains(key));
    await Future.wait(
      homes.entries.where((e) => active.contains(e.key)).map((e) async {
        try {
          final text = await api
              .fetch(e.value, cached: false)
              .timeout(const Duration(seconds: 25));
          final results = parse(e.key, text);
          if (results.isEmpty) throw const FormatException('Listado vacío');
          if (api.enabledProviders.contains(e.key)) bySource[e.key] = results;
        } catch (_) {
          failed.add(
            e.key,
          ); // Keep the previous successful listing on a transient failure.
        }
      }),
    );
    failures = failed;
    checkedAt = DateTime.now();
  }

  Future<Anime> animeFor(RecentEpisode item) async {
    if (item.animeUrl != null) return item.card;
    final doc = html.parse(await api.fetch(item.episodeUrl));
    for (final link in doc.querySelectorAll(
      'a.breadcrumb-current[href], a[href*="/anime/"]',
    )) {
      final url = Uri.parse(item.episodeUrl)
          .resolve(link.attributes['href'] ?? '');
      if (url.host != 'animeflv.or.at' ||
          url.pathSegments.where((s) => s.isNotEmpty).length != 2) {
        continue;
      }
      if (link.classes.contains('breadcrumb-current') ||
          ProviderClient.key(link.text) == ProviderClient.key(item.title)) {
        return Anime(item.title, url.toString(), item.cover);
      }
    }
    throw const FormatException(
      'No se encontró el enlace publicado a la ficha.',
    );
  }

  static List<RecentEpisode> parse(String provider, String text) {
    final results = <RecentEpisode>[];
    if (provider == 'AnimeAV1') {
      for (final node in ProviderClient.objects(ProviderClient.avData(text))) {
        if (node['number'] == null || node['media'] is! Map) continue;
        final anime = ProviderClient.avCard(node['media'] as Map);
        if (anime != null) {
          results.add(
            RecentEpisode(
              anime.title,
              '${node['number']}',
              '${anime.url}/${node['number']}',
              anime.cover,
              animeUrl: anime.url,
            ),
          );
        }
      }
    } else {
      final base = Uri.parse(homes[provider]!);
      final doc = html.parse(text);
      for (final link in doc.querySelectorAll('a[href]')) {
        final url = base.resolve(link.attributes['href'] ?? '');
        if (url.host != base.host) continue;
        final isTio = provider == 'TioAnime';
        if (isTio
            ? !url.path.startsWith('/ver/')
            : !RegExp(r'^/\d{4}/\d{2}/\d{2}/').hasMatch(url.path)) {
          continue;
        }
        final title =
            (link.querySelector('h2,h3')?.text ??
                    link.querySelector('img')?.attributes['alt'] ??
                    '')
                .trim();
        final match = RegExp(
          isTio
              ? r'^(.*?)\s+(\d+(?:\.\d+)?)$'
              : r'^(.*?)\s+Episodio\s+(\d+(?:\.\d+)?)$',
          caseSensitive: false,
        ).firstMatch(title);
        if (match == null) continue;
        final image = link.querySelector('img');
        final src =
            image?.attributes['data-src'] ?? image?.attributes['src'] ?? '';
        String? animeUrl;
        if (isTio) {
          final slug = url.pathSegments.last.replaceFirst(
            RegExp(r'-\d+(?:\.\d+)?$'),
            '',
          );
          animeUrl = base.resolve('/anime/$slug').toString();
        }
        results.add(
          RecentEpisode(
            match[1]!.trim(),
            match[2]!,
            url.toString(),
            src.isEmpty ? '' : base.resolve(src).toString(),
            animeUrl: animeUrl,
          ),
        );
      }
    }
    final seen = <String>{};
    return results.where((r) => seen.add(r.episodeUrl)).toList();
  }
}
