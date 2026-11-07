import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';

import 'media/source.dart';
import 'addons/addon_player.dart';
import 'anix_engine.dart';
import 'addons/spanish_policy.dart';
import 'addons/anix_catalog.dart';

const _bg = Color(0xff090c13);
const _panel = Color(0xff141923);
const _accent = Color(0xffb483ff);
Map<String, dynamic> _map(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
List<Map<String, dynamic>> _items(dynamic value) =>
    value is List ? value.map(_map).toList() : [];
String _str(dynamic value) => value?.toString() ?? '';

class AnixPage extends StatefulWidget {
  final AnixEngine? engine;
  final AnixCatalog? catalog;
  const AnixPage({super.key, this.engine, this.catalog});
  @override
  State<AnixPage> createState() => _AnixPageState();
}

class _AnixPageState extends State<AnixPage> {
  late final engine = widget.engine ?? AnixEngine();
  final searchController = TextEditingController();
  final httpClient = HttpClient();
  List<Map<String, dynamic>> plugins = [], matches = [], episodes = [];
  Map<String, dynamic>? source, chosenAnime;
  Map<String, dynamic> settings = {};
  String? error;
  bool busy = false, dub = false, searched = false;
  int operation = 0, total = 0;

  bool _spanish(Map<String, dynamic> p) {
    final language = p['lang'];
    return ['sub', 'dub'].any(
          (k) => (_map(p['languages'])[k] as List? ?? []).any(
            SpanishPolicy.spanish,
          ),
        ) ||
        (language is List
            ? language.any(SpanishPolicy.spanish)
            : language != null && SpanishPolicy.spanish(language));
  }

  String sourceStatus(Map<String, dynamic> p) {
    final language = _spanish(p)
        ? 'Extensión con contenido en español'
        : 'Esta extensión no declara contenido español';
    if (p['downloadable'] == true) return '$language · Requiere descargar';
    if (p['supported'] != true)
      return '$language · Formato no compatible con Neko';
    return language;
  }

  List<dynamic> sourceLanguages(String mode) =>
      _map(source?['languages'])[mode] as List? ?? [];
  bool get canDub => sourceLanguages('dub').isNotEmpty;
  bool get canSub => sourceLanguages('sub').isNotEmpty || !canDub;
  @override
  void initState() {
    super.initState();
    initialize();
  }

  @override
  void dispose() {
    ++operation;
    searchController.dispose();
    httpClient.close(force: true);
    engine.dispose();
    super.dispose();
  }

  Future<void> initialize() async {
    final token = ++operation;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final list = _items(await engine.call('list'));
      if (!mounted || token != operation) return;
      setState(() {
        total = list.length;
        plugins = list;
        source = null;
        chosenAnime = null;
        matches = [];
        episodes = [];
        searched = false;
      });
    } catch (e) {
      if (mounted && token == operation) setState(() => error = '$e');
    } finally {
      if (mounted && token == operation) setState(() => busy = false);
    }
  }

  Future<void> openSource(Map<String, dynamic> value) async {
    if (!_spanish(value)) {
      final enter = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Idioma de la extensión'),
          content: const Text(
            'Esta extensión no declara contenido español. Si entras y no encuentras animes subtitulados en español, no es responsabilidad de Neko Anime.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Entrar'),
            ),
          ],
        ),
      );
      if (enter != true || !mounted) return;
    }
    ++operation;
    setState(() {
      source = value;
      chosenAnime = null;
      matches = [];
      episodes = [];
      settings = {};
      searched = false;
      error = null;
      busy = false;
      dub = !canSub && canDub;
      searchController.clear();
    });
  }

  void back() {
    ++operation;
    setState(() {
      busy = false;
      error = null;
      if (chosenAnime != null) {
        chosenAnime = null;
        episodes = [];
      } else {
        source = null;
        matches = [];
        searched = false;
        searchController.clear();
      }
    });
  }

  Future<void> search() async {
    final title = searchController.text.trim();
    final active = source;
    if (title.isEmpty || active == null) return;
    final token = ++operation;
    setState(() {
      busy = true;
      error = null;
      matches = [];
      episodes = [];
      chosenAnime = null;
      searched = true;
    });
    try {
      final result = _items(
        await engine.call(
          'search',
          plugin: '${active['id']}',
          args: {
            'options': {
              'query': title,
              'title': title,
              'dub': dub,
              'media': {
                'title': {'romaji': title, 'english': title},
                'synonyms': [title],
              },
            },
          },
        ),
      );
      if (mounted && token == operation) setState(() => matches = result);
    } catch (e) {
      if (mounted && token == operation)
        setState(() => error = '${active['name']}: $e');
    } finally {
      if (mounted && token == operation) setState(() => busy = false);
    }
  }

  Future<void> openAnime(Map<String, dynamic> anime) async {
    final active = source;
    if (active == null) return;
    final token = ++operation;
    setState(() {
      busy = true;
      error = null;
      episodes = [];
      chosenAnime = anime;
    });
    try {
      final data = _items(
        await engine.call(
          'episodes',
          plugin: '${active['id']}',
          args: {'animeId': anime['id']},
        ),
      );
      if (!mounted || token != operation) return;
      setState(() => episodes = data);
      final value = _map(
        await engine.call('settings', plugin: '${active['id']}'),
      );
      if (mounted && token == operation) setState(() => settings = value);
    } catch (e) {
      if (mounted && token == operation) setState(() => error = '$e');
    } finally {
      if (mounted && token == operation) setState(() => busy = false);
    }
  }

  Future<void> openEpisode(Map<String, dynamic> episode) async {
    final active = source;
    if (active == null) return;
    final servers = (settings['episodeServers'] as List? ?? ['default'])
        .map((s) => '$s')
        .toList();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AnixPlayerPage(
          engine: engine,
          plugin: '${active['id']}',
          episode: episode,
          servers: servers,
          title: _str(chosenAnime?['title']),
        ),
      ),
    );
  }

  Future<void> install(String text) async {
    final count = await engine.installManifest(text);
    if (!mounted) return;
    await initialize();
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Manifiesto cargado: $count extensiones.')),
      );
  }

  Future<void> importFile() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Manifiesto Anix', extensions: ['json']),
        ],
      );
      if (file == null || !mounted) return;
      if (await file.length() > 3000000)
        throw const FormatException('Archivo demasiado grande.');
      await install(await file.readAsString());
    } catch (e) {
      if (mounted) setState(() => error = 'Importación fallida: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> importUrl() async {
    var input = '';
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Agregar extensiones por URL'),
        content: SizedBox(
          width: 480,
          child: TextField(
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'URL del manifiesto',
              hintText: 'https://.../extensions.json',
            ),
            onChanged: (v) => input = v,
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, input.trim()),
            child: const Text('Agregar'),
          ),
        ],
      ),
    );
    if (url == null || url.isEmpty || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final uri = Uri.parse(url);
      if (uri.scheme != 'https')
        throw const FormatException('Solo se admiten direcciones HTTPS.');
      final request = await httpClient
          .getUrl(uri)
          .timeout(const Duration(seconds: 12));
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      if (response.statusCode != 200)
        throw HttpException('HTTP ${response.statusCode}');
      final bytes = <int>[];
      await for (final part in response.timeout(const Duration(seconds: 20))) {
        bytes.addAll(part);
        if (bytes.length > 3000000)
          throw const FormatException('Archivo demasiado grande.');
      }
      await install(utf8.decode(bytes));
    } catch (e) {
      if (mounted) setState(() => error = 'Importación fallida: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> downloadSource(Map<String, dynamic> entry) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await engine.downloadPlugin('${entry['id']}');
      if (!mounted) return;
      await initialize();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${entry['name']} descargada y lista.')),
        );
    } catch (e) {
      if (mounted)
        setState(() => error = 'No se pudo descargar ${entry['name']}: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget sourceList() => plugins.isEmpty
      ? Center(
          child: Text(
            busy
                ? 'Cargando extensiones…'
                : 'No hay extensiones cargadas. Importa un manifiesto.',
          ),
        )
      : ListView(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                '${engine.importedManifest ? 'Manifiesto importado' : 'Manifiesto incluido'} · $total extensiones',
                style: const TextStyle(color: Colors.white70),
              ),
            ),
            for (final p in plugins)
              Card(
                color: _panel,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  leading: const Icon(Icons.extension_outlined, color: _accent),
                  title: Text(_str(p['name'])),
                  subtitle: Text(sourceStatus(p)),
                  trailing: p['downloadable'] == true
                      ? OutlinedButton.icon(
                          onPressed: busy ? null : () => downloadSource(p),
                          icon: const Icon(Icons.download_outlined),
                          label: const Text('Descargar'),
                        )
                      : Icon(
                          p['supported'] == true
                              ? Icons.chevron_right
                              : Icons.info_outline,
                        ),
                  onTap: busy
                      ? null
                      : p['downloadable'] == true
                      ? () => downloadSource(p)
                      : p['supported'] != true
                      ? null
                      : () => openSource(p),
                ),
              ),
          ],
        );
  Widget results() {
    final isEpisode = chosenAnime != null;
    final items = isEpisode ? episodes : matches;
    if (items.isEmpty)
      return Center(
        child: Text(
          busy
              ? 'Cargando…'
              : error != null
              ? 'La extensión no pudo completar la consulta.'
              : isEpisode
              ? 'Esta extensión no devolvió episodios.'
              : searched
              ? 'Sin resultados en ${source!['name']}.'
              : 'Busca un título en ${source!['name']} para ver su contenido.',
        ),
      );
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (_, i) {
        final item = items[i];
        return Card(
          color: _panel,
          child: ListTile(
            leading: isEpisode
                ? const Icon(Icons.play_circle_outline, color: _accent)
                : _str(item['image']).isEmpty
                ? const Icon(Icons.movie_outlined)
                : Image.network(
                    _str(item['image']),
                    width: 52,
                    fit: BoxFit.cover,
                    errorBuilder: (_, error, stack) =>
                        const Icon(Icons.movie_outlined),
                  ),
            title: Text(
              isEpisode
                  ? 'Episodio ${_str(item['number'])}'
                  : _str(item['title']),
            ),
            subtitle: Text(
              isEpisode
                  ? _str(item['title'])
                  : '${source!['name']} · ${_str(item['subOrDub'])}',
            ),
            trailing: const Icon(Icons.chevron_right, color: _accent),
            onTap: busy
                ? null
                : () => isEpisode ? openEpisode(item) : openAnime(item),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _bg,
    appBar: AppBar(
      title: Text(
        source == null ? 'Extensiones Anix' : 'Anix · ${source!['name']}',
      ),
      backgroundColor: _panel,
    ),
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (source == null) ...[
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: busy ? null : importFile,
                  icon: const Icon(Icons.file_open_outlined),
                  label: const Text('Importar archivo'),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : importUrl,
                  icon: const Icon(Icons.link),
                  label: const Text('Agregar por URL'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Abre una extensión para explorar sus resultados por separado.',
              style: TextStyle(color: Colors.white70),
            ),
          ] else ...[
            TextButton.icon(
              onPressed: back,
              icon: const Icon(Icons.arrow_back),
              label: Text(
                chosenAnime == null
                    ? 'Todas las extensiones'
                    : 'Resultados de ${source!['name']}',
              ),
            ),
            if (chosenAnime == null) ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: searchController,
                      onSubmitted: (_) {
                        if (!busy) search();
                      },
                      decoration: InputDecoration(
                        hintText: 'Buscar en ${source!['name']}',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: busy ? null : search,
                    icon: const Icon(Icons.search),
                    label: const Text('Buscar'),
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Doblaje'),
                value: dub,
                onChanged: busy || !canDub || !canSub
                    ? null
                    : (v) {
                        ++operation;
                        setState(() {
                          dub = v;
                          matches = [];
                          episodes = [];
                          searched = false;
                          error = null;
                        });
                      },
              ),
            ] else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _str(chosenAnime!['title']),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
          ],
          if (busy) const LinearProgressIndicator(),
          if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: SelectableText(
                error!,
                style: const TextStyle(color: Colors.orangeAccent),
              ),
            ),
          const SizedBox(height: 8),
          Expanded(child: source == null ? sourceList() : results()),
        ],
      ),
    ),
  );
}

class AnixPlayerPage extends StatelessWidget {
  final AnixEngine engine;
  final String plugin;
  final Map<String, dynamic> episode;
  final List<String> servers;
  final String title;
  const AnixPlayerPage({
    super.key,
    required this.engine,
    required this.plugin,
    required this.episode,
    required this.servers,
    this.title = '',
  });

  Future<MediaSource> resolve(String server) async {
    final data = _map(
      await engine.call(
        'server',
        plugin: plugin,
        args: {'episode': episode, 'server': server},
      ),
    );
    final sources = _items(data['videoSources']);
    final src = sources
        .where((s) => _str(s['url']).startsWith('https://'))
        .firstOrNull;
    if (src == null)
      throw const FormatException(
        'La extensión no devolvió un enlace de video válido.',
      );
    final headers = <String, String>{};
    _map(data['headers']).forEach((k, v) => headers[k.toLowerCase()] = '$v');
    _map(src['headers']).forEach((k, v) => headers[k.toLowerCase()] = '$v');
    return MediaSource(
      '${data['server'] ?? server}',
      _str(src['url']),
      headers,
      [
        for (final subtitle in _items(({...data, ...src})['subtitles']))
          if ([
            'http',
            'https',
          ].contains(Uri.tryParse(_str(subtitle['url']))?.scheme))
            subtitle,
      ],
    );
  }

  @override
  Widget build(BuildContext context) => AddonPlayer(
    title:
        '${title.isEmpty ? plugin : title} · Episodio ${_str(episode['number'])}',
    resolvers: [
      for (final server in <String>{'default', ...servers})
        () => resolve(server),
    ],
  );
}
