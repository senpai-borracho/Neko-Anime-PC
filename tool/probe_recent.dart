import 'dart:io';
import 'dart:convert';

import 'package:neko_player_pc/catalog.dart';
import 'package:neko_player_pc/recent_episodes.dart';

Future<void> main() async {
  final api = ProviderClient();
  final feed = RecentEpisodes(api);
  await feed.refresh(api.enabledProviders);
  final report = <String, dynamic>{
    'total': feed.items().length,
    'failures': feed.failures,
  };
  for (final source in RecentEpisodes.homes.keys) {
    final items = feed.items(provider: source);
    report[source] = {'count': items.length};
    if (items.isNotEmpty) {
      try {
        final anime = await feed.animeFor(items.first);
        final detail = await api.detail(anime);
        report[source] = {
          'count': items.length,
          'title': anime.title,
          'announcedEpisode': items.first.number,
          'episodePresent': detail.episodes.any(
            (e) => e.number == items.first.number,
          ),
        };
      } catch (e) {
        report[source] = {'error': e.toString()};
      }
    }
  }
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
  await File('tool/recent_probe.json').writeAsString(jsonEncode(report));
  api.close();
}
