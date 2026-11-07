import 'dart:io';
import 'package:neko_player_pc/addons/plugin_models.dart';
import 'package:neko_player_pc/addons/stremio_client.dart';

Future<void> main() async {
  const url = 'https://pigamer37.alwaysdata.net/manifest.json';
  final client = StremioClient();
  final manifest = await client.manifest(url);
  final plugin = InstalledPlugin(info: PluginInfo(kind: PluginKind.stremio,
      id: '${manifest['id']}', name: '${manifest['name']}', repoUrl: url, fileUrl: url));
  final result = await client.browse(plugin, query: 'Naruto');
  final series = result.items.firstWhere((s) => s.title == 'Naruto');
  final detail = await client.detail(series, series.refs.first);
  final servers = await client.servers(detail.episodes.first);
  final video = StremioClient.resolve(servers.first);
  stdout.writeln('AnimES: ${result.items.length} resultados, ${detail.episodes.length} episodios, ${servers.length} enlaces.');
  stdout.writeln('Cabeceras: ${video.headers.keys.join(', ')}');
}
