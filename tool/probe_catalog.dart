import 'dart:io';
import 'dart:convert';

import 'package:neko_player_pc/catalog.dart';

Future<void> main() async {
  final api = ProviderClient();
  final report = <String, dynamic>{};
  try {
    for (final entry in {
      'jk': 'https://jkanime.net/directorio?p=1',
      'av': 'https://animeav1.com/catalogo?page=1',
    }.entries) {
      try {
        final text = await api.fetch(entry.value);
        await Directory('tool/fixtures').create(recursive: true);
        await File('tool/fixtures/${entry.key}.html').writeAsString(text);
        report['${entry.key}Bytes'] = text.length;
      } catch (e) {
        report['${entry.key}Error'] = e.toString();
      }
    }
    final result = await api.catalog();
    report['catalogCount'] = result.cards.length;
    report['hasMore'] = result.more;
    report['notice'] = api.notice;
    report['providers'] = result.cards.map((a) => a.provider).toSet().toList();
    final search = await api.catalog(query: 'Naruto');
    report['searchCount'] = search.cards.length;
    final choice =
        search.cards
            .where((c) => c.title.toLowerCase() == 'naruto')
            .firstOrNull ??
        search.cards.first;
    final detail = await api.detail(choice);
    report['detailTitle'] = detail.anime.title;
    report['episodes'] = detail.episodes.length;
    final servers = await api.servers(detail.episodes.first);
    report['servers'] = servers.map((s) => s.name).toList();
    for (final server in servers.take(2)) {
      try {
        final stream = await api.resolve(server, detail.episodes.first);
        report['resolved_${server.name}'] = Uri.parse(stream.url).host;
      } catch (e) {
        report['resolverError_${server.name}'] = e.toString();
      }
    }
  } catch (e, stack) {
    report['fatal'] = e.toString();
    report['stack'] = stack.toString();
    exitCode = 1;
  } finally {
    api.close();
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
    await File('tool/catalog_probe.json')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
  }
}
