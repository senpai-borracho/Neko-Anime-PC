import 'package:flutter/material.dart';

import '../main.dart' show AnimePoster, accent, muted;
import '../catalog.dart' show Anime, Episode;
import '../app_ui.dart';
import 'catalog_models.dart';
import 'plugin_models.dart';
import 'stremio_client.dart';
import 'addon_player.dart';

class StremioPage extends StatefulWidget {
  final InstalledPlugin plugin;
  const StremioPage({super.key, required this.plugin});
  @override
  State<StremioPage> createState() => _StremioPageState();
}

class _StremioPageState extends State<StremioPage> {
  final client = StremioClient();
  final search = TextEditingController();
  List<Series> items = [];
  List<String> genres = [];
  String genre = '', query = '';
  String? error;
  bool loading = true, more = false;
  int request = 0, page = 1;
  @override
  void initState() {
    super.initState();
    initialize();
  }

  @override
  void dispose() {
    request++;
    search.dispose();
    super.dispose();
  }

  Future<void> initialize() async {
    try {
      final manifest = await client.manifest(widget.plugin.info.fileUrl);
      final values = <String>{};
      for (final c in (manifest['catalogs'] as List? ?? []).whereType<Map>()) {
        for (final e in (c['extra'] as List? ?? []).whereType<Map>()) {
          if (e['name'] == 'genre' && e['options'] is List) {
            values.addAll((e['options'] as List).whereType<String>());
          }
        }
      }
      if (!mounted) return;
      genres = values.toList()..sort();
      if (genres.isNotEmpty) genre = genres.first;
      await load();
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = '$e';
        });
      }
    }
  }

  Future<void> load({bool next = false}) async {
    final token = ++request;
    final target = next ? page + 1 : 1;
    setState(() {
      loading = true;
      error = null;
      if (!next) items = [];
    });
    try {
      final result = await client.browse(
        widget.plugin,
        query: query,
        genre: query.isEmpty ? genre : '',
        page: target,
      );
      if (!mounted || token != request) return;
      final seen = <String>{};
      setState(() {
        items = [
          ...items,
          ...result.items,
        ].where((s) => seen.add(s.refs.first.url)).toList();
        page = target;
        more = result.more;
        loading = false;
      });
    } catch (e) {
      if (mounted && token == request) {
        setState(() {
          error = '$e';
          loading = false;
        });
      }
    }
  }

  void submit() {
    query = search.text.trim();
    load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Catálogo · ${widget.plugin.info.name}')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(22),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: search,
                  onSubmitted: (_) => submit(),
                  decoration: InputDecoration(
                    hintText: 'Buscar en ${widget.plugin.info.name}',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      onPressed: submit,
                      icon: const Icon(Icons.arrow_forward),
                    ),
                  ),
                ),
              ),
              if (genres.isNotEmpty) ...[
                const SizedBox(width: 16),
                SizedBox(
                  width: 190,
                  child: DropdownButtonFormField<String>(
                    initialValue: genre,
                    decoration: const InputDecoration(labelText: 'Género'),
                    isExpanded: true,
                    items: [
                      for (final g in genres)
                        DropdownMenuItem(value: g, child: Text(g)),
                    ],
                    onChanged: (g) {
                      if (g != null) {
                        genre = g;
                        query = '';
                        search.clear();
                        load();
                      }
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
        if (loading) const LinearProgressIndicator(color: accent),
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Text(error!, style: const TextStyle(color: muted)),
                ),
                TextButton(
                  onPressed: initialize,
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Text(
                    loading
                        ? 'Cargando…'
                        : 'Sin resultados. Prueba otro título o género.',
                    style: const TextStyle(color: muted),
                  ),
                )
              : CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 190,
                              childAspectRatio: .56,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                            ),
                        delegate: SliverChildBuilderDelegate((ctx, i) {
                          final s = items[i];
                          return AnimePoster(
                            anime: Anime(s.title, s.refs.first.url, s.cover),
                            sourceLabel: widget.plugin.info.name,
                            favorite: false,
                            showFavorite: false,
                            onFavorite: () {},
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => AddonDetailPage(series: s),
                              ),
                            ),
                          );
                        }, childCount: items.length),
                      ),
                    ),
                    if (more)
                      SliverToBoxAdapter(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: OutlinedButton(
                              onPressed: loading
                                  ? null
                                  : () => load(next: true),
                              child: const Text('Cargar más'),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    ),
  );
}

class AddonDetailPage extends StatefulWidget {
  final Series series;
  const AddonDetailPage({super.key, required this.series});
  @override
  State<AddonDetailPage> createState() => _AddonDetailPageState();
}

class _AddonDetailPageState extends State<AddonDetailPage> {
  final client = StremioClient();
  late final future = client.detail(widget.series, widget.series.refs.first);
  bool busy = false;
  Future<void> play(Episode episode) async {
    setState(() => busy = true);
    try {
      final servers = await client.servers(episode);
      final streams = [
        for (final server in servers)
          video(server.name, StremioClient.resolve(server)),
      ];
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => AddonPlayer(
            title: '${widget.series.title} · Episodio ${episode.number}',
            streams: streams,
          ),
        ),
      );
    } catch (e) {
      if (mounted) showCompactNotice(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  AddonVideo video(String name, StremioSource stream) =>
      AddonVideo(name, stream.url, stream.headers, stream.subtitles);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.series.title)),
    body: FutureBuilder<SeriesDetail>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: SelectableText('${snapshot.error}'));
        }
        final detail = snapshot.data;
        if (detail == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return Column(
          children: [
            if (busy) const LinearProgressIndicator(color: accent),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(22),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.series.cover.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.network(
                            widget.series.cover,
                            width: 150,
                            errorBuilder: (_, _, _) =>
                                const Icon(Icons.movie_outlined),
                          ),
                        ),
                      const SizedBox(width: 22),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.series.title,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(detail.synopsis),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Text(
                    '${detail.episodes.length} episodios',
                    style: const TextStyle(color: accent),
                  ),
                  for (final episode in detail.episodes)
                    ListTile(
                      title: Text('Episodio ${episode.number}'),
                      trailing: const Icon(Icons.play_circle_outline),
                      onTap: busy ? null : () => play(episode),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );
}
