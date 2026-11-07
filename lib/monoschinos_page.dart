// Pantallas experimentales de MonosChinos; reutilizan el resolutor nativo.
import 'dart:io';

import 'monoschinos_client.dart';
import 'monoschinos_sources.dart';
import 'catalog.dart';
import 'monoschinos_catalog_view.dart';
import 'monoschinos_detail_view.dart';
import 'monoschinos_synopsis.dart';
import 'main.dart' show Library, PlaybackPage;

import 'package:flutter/material.dart';

const _bg = Color(0xff090c13);

class MonosChinosPage extends StatefulWidget {
  final int initialSite;
  final bool embedded;
  final MonosClient? client;
  final ValueChanged<int>? onSourceChanged;
  final Widget Function(MonosEntry, VoidCallback)? cardBuilder;
  const MonosChinosPage({
    super.key,
    this.initialSite = 0,
    this.embedded = false,
    this.client,
    this.cardBuilder,
    this.onSourceChanged,
  });
  @override
  State<MonosChinosPage> createState() => _MonosChinosPageState();
}

class _MonosChinosPageState extends State<MonosChinosPage> {
  MonosEntry? selectedAnime;
  int selected = 0, page = 1;
  late MonosClient client = MonosClient(monosSites[0]);
  final search = TextEditingController();
  String activeSearch = "";
  List<MonosEntry> cards = [];
  bool busy = false;
  String? error;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    selected = monosSiteEnabled(widget.initialSite)
        ? widget.initialSite
        : enabledMonosSiteIndexes.first;
    client.close();
    if (widget.client != null && widget.client!.site != monosSites[selected]) {
      widget.client!.close();
    }
    client =
        widget.client != null && widget.client!.site == monosSites[selected]
        ? widget.client!
        : MonosClient(monosSites[selected]);
    load();
  }

  @override
  void dispose() {
    generation++;
    client.close();
    search.dispose();
    super.dispose();
  }

  void switchTo(int index) {
    if (!monosSiteEnabled(index) || index == selected) return;
    generation++;
    client.close();
    setState(() {
      selectedAnime = null;
      selected = index;
      client = MonosClient(monosSites[index]);
      page = 1;
      cards = [];
      error = null;
      search.clear();
    });
    load();
  }

  Future<void> load({bool append = false}) async {
    final id = ++generation;
    setState(() {
      busy = true;
      error = null;
      if (!append) {
        page = 1;
        activeSearch = search.text.trim();
        cards = [];
      }
    });
    try {
      final requestedPage = page;
      final data = await client.catalog(requestedPage, search: activeSearch);
      if (!mounted || id != generation) return;
      setState(() {
        cards = append
            ? [
                ...cards,
                ...data.where((e) => !cards.any((old) => old.url == e.url)),
              ]
            : data;
      });
    } catch (e) {
      if (mounted && id == generation) {
        setState(() {
          error = e.toString();
          if (append && page > 1) page--;
        });
      }
    } finally {
      if (mounted && id == generation) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => widget.embedded
      ? catalogPanel()
      : Scaffold(backgroundColor: _bg, body: catalogPanel());

  Widget catalogPanel() => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(
        child: MonosCatalogView(
          selected: selected,
          entries: cards,
          busy: busy,
          error: error,
          search: search,
          onSearch: () => load(),
          onMore: () {
            page++;
            load(append: true);
          },
          onSourceChanged: widget.onSourceChanged ?? switchTo,
          cardBuilder:
              widget.cardBuilder ??
              (entry, onTap) => Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onTap,
                  child: Column(
                    children: [
                      Expanded(
                        child: Image.network(
                          entry.image,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              const Center(child: Icon(Icons.movie_outlined)),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          entry.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          onOpen: (item) => setState(() => selectedAnime = item),
        ),
      ),
      if (selectedAnime != null)
        SizedBox(
          width: 350,
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xff101622),
              border: Border(left: BorderSide(color: Color(0xff222a3b))),
            ),
            child: _MonosDetail(
              key: ValueKey(selectedAnime!.url),
              client: client,
              anime: selectedAnime!,
              embedded: true,
              onClose: () => setState(() => selectedAnime = null),
            ),
          ),
        ),
    ],
  );
}

class _MonosDetail extends StatefulWidget {
  final MonosClient client;
  final MonosEntry anime;
  final bool embedded;
  final VoidCallback? onClose;
  const _MonosDetail({
    super.key,
    required this.client,
    required this.anime,
    this.embedded = false,
    this.onClose,
  });
  @override
  State<_MonosDetail> createState() => _MonosDetailState();
}

class _MonosDetailState extends State<_MonosDetail> {
  late Future<String> synopsis = MonosSynopsis.load(
    widget.client,
    widget.anime,
  );
  late Future<List<MonosEntry>> future = widget.client.episodes(widget.anime);
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: widget.embedded
        ? null
        : AppBar(title: const Text('Detalle del anime')),
    body: FutureBuilder<String>(
      future: synopsis,
      builder: (context, metadata) => FutureBuilder<List<MonosEntry>>(
        future: future,
        builder: (context, snapshot) => MonosDetailView(
          compact: widget.embedded,
          onClose: widget.onClose,
          anime: widget.anime,
          synopsis: metadata.data ?? '',
          synopsisLoading: metadata.connectionState != ConnectionState.done,
          synopsisError: metadata.hasError,
          onSynopsisRetry: () => setState(
            () => synopsis = MonosSynopsis.load(widget.client, widget.anime),
          ),
          source: widget.client.site.label,
          episodes: snapshot.data ?? const [],
          loading: snapshot.connectionState != ConnectionState.done,
          error: snapshot.hasError
              ? snapshot.error.toString().replaceFirst(
                  RegExp(r'^(Exception|FormatException):\s*'),
                  '',
                )
              : null,
          onRetry: () =>
              setState(() => future = widget.client.episodes(widget.anime)),
          onOpen: (episode) => openMonosPlayer(
            context,
            widget.client,
            widget.anime,
            snapshot.data ?? const [],
            episode,
          ),
        ),
      ),
    ),
  );
}

/// Panel de detalle de MonosChinos para usarlo desde el catálogo principal.
Widget monosDetailPanel({
  required MonosClient client,
  required MonosEntry anime,
  required VoidCallback onClose,
}) => _MonosDetail(
  key: ValueKey(anime.url),
  client: client,
  anime: anime,
  embedded: true,
  onClose: onClose,
);

/// Adaptador: el reproductor principal de Neko pide servidores y enlaces a
/// este objeto, que los obtiene con el cliente de MonosChinos sin modificarlo.
class MonosPlaybackApi extends ProviderClient {
  MonosPlaybackApi(this.client);
  final MonosClient client;
  MonosEntry _entry(Episode e) => MonosEntry(e.number, e.url, '');
  @override
  Future<List<Server>> servers(Episode episode) =>
      client.streams(_entry(episode));
  @override
  Future<StreamSource> resolve(Server server, Episode episode) =>
      client.resolve(server, _entry(episode));
}

// El avance de MonosChinos se guarda aparte para no mezclarse con el historial
// de las demás fuentes.
final Library _monosLibrary = Library(
  storageFile: File(
    '${Platform.environment['LOCALAPPDATA'] ?? Directory.current.path}'
    '/NekoPlayerPC/monoschinos_progress.json',
  ),
);
Future<void>? _monosLibraryLoaded;

Episode _monosEpisode(MonosEntry e) {
  final number = monosEpisodeNumber(e);
  return Episode(number.isEmpty ? e.title : number, e.url);
}

Future<void> openMonosPlayer(
  BuildContext context,
  MonosClient client,
  MonosEntry anime,
  List<MonosEntry> entries,
  MonosEntry selected,
) async {
  await (_monosLibraryLoaded ??= _monosLibrary.load());
  if (!context.mounted) return;
  // El botón "siguiente" necesita los episodios en orden ascendente.
  final numbers = [
    for (final e in entries) double.tryParse(monosEpisodeNumber(e)),
  ];
  final ordered = [...entries];
  if (numbers.isNotEmpty && !numbers.contains(null)) {
    final byEntry = {
      for (var i = 0; i < entries.length; i++) entries[i]: numbers[i]!,
    };
    ordered.sort((a, b) => byEntry[a]!.compareTo(byEntry[b]!));
  }
  final episodes = [for (final e in ordered) _monosEpisode(e)];
  final api = MonosPlaybackApi(client);
  try {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlaybackPage(
          detail: Detail(
            Anime(monosDisplayTitle(anime.title), anime.url, anime.image),
            '',
            episodes.isEmpty ? [_monosEpisode(selected)] : episodes,
          ),
          episode: _monosEpisode(selected),
          api: api,
          library: _monosLibrary,
          sourceLabel: client.site.label,
        ),
      ),
    );
  } finally {
    api.close();
  }
}
