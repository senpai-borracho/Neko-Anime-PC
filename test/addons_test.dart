import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neko_player_pc/main.dart' show NekoApp;
import 'package:neko_player_pc/addons/addons_page.dart';
import 'package:neko_player_pc/addons/plugin_manager.dart';
import 'package:neko_player_pc/addons/plugin_models.dart';
import 'package:neko_player_pc/addons/stremio_client.dart';
import 'package:neko_player_pc/addons/nuvio_runtime.dart';
import 'package:neko_player_pc/addons/spanish_policy.dart';

const url = 'https://example.org/config/manifest.json';
const manifest = {
  'id': 'test.animes', 'name': 'AnimES', 'version': '1.0',
  'types': ['series'], 'resources': ['catalog','meta','stream'],
  'catalogs': [{'type': 'Anime', 'id': 'genres', 'extra': [
    {'name': 'genre', 'isRequired': true, 'options': ['accion']},
  ]}],
};

class MemoryManager extends PluginManager {
  @override
  Future<void> load() async {}
}

void main() {
  test('Spanish policy permits Spain, Latin America and Spanish subtitles only', () {
    for (final lang in ['es', 'es-ES', 'es-419', 'es-MX', 'spa', 'Spanish', 'Español latino', 'Castellano']) {
      expect(SpanishPolicy.allows({'language': lang}), isTrue, reason: lang);
    }
    for (final lang in ['en', 'ja', 'pt', 'fr', 'de', 'English']) {
      expect(SpanishPolicy.allows({'language': lang}, trustedSpanish: true), isFalse, reason: lang);
    }
    expect(SpanishPolicy.allows({'name': 'AnimeAV1', 'description': '🇯🇵🇪🇸'}), isTrue);
    expect(SpanishPolicy.allows({'name': 'Unknown SUB'}), isFalse);
    expect(SpanishPolicy.allows({'name': 'Unknown'}), isFalse);
    expect(SpanishPolicy.onlySpanish(['es', 'es-MX']), isTrue);
    expect(SpanishPolicy.onlySpanish(['en', 'es']), isFalse);
    expect(SpanishPolicy.allows({'language': 'ja', 'subtitles': [
      {'lang': 'es', 'url': 'https://example.org/es.vtt'},
      {'lang': 'en', 'url': 'https://example.org/en.vtt'},
    ]}), isTrue);
    expect(SpanishPolicy.subtitles({'subtitles': [
      {'lang': 'en', 'url': 'https://example.org/en.vtt'},
      {'language': 'Spanish', 'url': 'https://example.org/es.vtt'},
    ]}).length, 1);
  });
  test('Stremio import, genre, episodes and request headers work independently', () async {
    final manager = MemoryManager();
    await manager.importJson(jsonEncode(manifest), fileName: 'manifest.json', baseUrl: 'https://example.org/config/');
    final info = manager.entries().single.info;
    expect(info.kind, PluginKind.stremio);
    expect(info.fileUrl, url);
    final plugin = InstalledPlugin.fromJson(InstalledPlugin(info: info).toJson());
    final calls = <Uri>[];
    final client = StremioClient(fetchJson: (uri) async {
      calls.add(uri);
      if (uri.toString() == url) return manifest;
      if (uri.pathSegments.contains('catalog')) return {'metas': [
        {'id': 'animeav1:naruto', 'name': 'Naruto', 'type': 'series', 'poster': 'https://example.org/cover.jpg'},
      ]};
      if (uri.pathSegments.contains('meta')) return {'meta': {'videos': [
        {'id': 'animeav1:naruto:1', 'episode': 1, 'season': 1},
      ]}};
      return {'streams': [{'url': 'https://example.org/video.mp4', 'language': 'es', 'behaviorHints': {
        'proxyHeaders': {'request': {'User-Agent': 'Addon UA', 'Referer': 'https://example.org/'}},
      }}]};
    });
    final result = await client.browse(plugin, genre: 'accion');
    expect(calls.last.pathSegments.last, 'genre=accion.json');
    final series = result.items.single;
    expect(series.cover, endsWith('cover.jpg'));
    final detail = await client.detail(series, series.refs.single);
    final servers = await client.servers(detail.episodes.single);
    final video = StremioClient.resolve(servers.single);
    expect(video.headers['user-agent'], 'Addon UA');
    expect(video.referer, 'https://example.org/');
    final before = calls.length;
    expect((await client.browse(plugin, genre: 'missing')).items, isEmpty);
    expect(calls.length, before); // Reutiliza el manifiesto sin otra petición.
  });

  test('Nuvio scripts still import as JavaScript providers', () async {
    final manager = MemoryManager();
    await manager.importJson(jsonEncode({'providers': [
      {'id':'provider', 'name':'Nuvio', 'filename':'provider.js'},
    ]}), fileName:'repo.json', baseUrl:'https://example.org/repo');
    expect(manager.entries().single.info.kind, PluginKind.nuvio);
    expect(manager.entries().single.info.fileUrl, 'https://example.org/repo/provider.js');
  });

  test('Nuvio runtime passes TMDB and episode arguments to getStreams', () async {
    final temp = await Directory.systemTemp.createTemp('neko-addon-test-');
    try {
      final script = File('${temp.path}/provider.js');
      await script.writeAsString(r'''
module.exports.getStreams = async (id,type,season,episode) => [{
  url:'https://example.org/'+id+'/'+type+'/'+season+'/'+episode+'.mp4',
  headers:{Referer:'https://example.org/'}, name:'Fixture'
}];
''');
      final result = await NuvioRuntime.run(script.path, '46260', 'tv', 1, 2);
      expect(result.single['url'], 'https://example.org/46260/tv/1/2.mp4');
      await script.writeAsString('module.exports.getStreams = async () => { throw new Error("provider failure"); };');
      await expectLater(NuvioRuntime.run(script.path, '1', 'movie', null, null), throwsFormatException);
    } finally { await temp.delete(recursive: true); }
  });

  testWidgets('Complementos uses existing theme and offers catalog and activation', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final manager = MemoryManager();
    const info = PluginInfo(kind: PluginKind.stremio, id: 'test', name:'AnimES', repoUrl:url, fileUrl:url);
    manager.installed[info.key] = InstalledPlugin(info:info);
    await tester.pumpWidget(NekoApp(home: AddonsPage(manager:manager)));
    await tester.pumpAndSettle();
    expect(find.text('Ver catálogo'), findsOneWidget);
    expect(find.text('Extensiones Anix'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('Ver catálogo'), findsNothing);
    expect(tester.takeException(), isNull);
    final asset = await tester.runAsync(() => rootBundle.loadString('assets/extensions/anix-extensions.json'));
    expect(jsonDecode(asset!)['plugins'], isA<List>());
  });
}
