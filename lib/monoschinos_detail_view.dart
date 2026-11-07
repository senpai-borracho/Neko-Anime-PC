import 'package:flutter/material.dart';

import 'app_ui.dart';
import 'anime_detail_panel.dart';
import 'monoschinos_client.dart';

String monosDisplayTitle(String title) => title
    .replaceFirst(RegExp(r'^Ver\s+Anime\s+', caseSensitive: false), '')
    .replaceFirst(RegExp(r'\s+Online(?:\s+Gratis)?$', caseSensitive: false), '')
    .trim();
String monosEpisodeNumber(MonosEntry entry) =>
    RegExp(
          r'(?:episodio|capitulo|episode|capítulo)[\s\-:/]*(\d+(?:\.\d+)?)',
          caseSensitive: false,
        )
        .firstMatch('${Uri.tryParse(entry.url)?.path ?? ''} ${entry.title}')
        ?.group(1) ??
    RegExp(r'^\s*(\d+(?:\.\d+)?)\s*$').firstMatch(entry.title)?.group(1) ??
    '';

// Pure presentation: source requests and playback callbacks stay in their module.
class MonosDetailView extends StatefulWidget {
  final bool compact;
  final VoidCallback? onClose;
  final String synopsis;
  final bool synopsisLoading, synopsisError;
  final VoidCallback? onSynopsisRetry;
  final MonosEntry anime;
  final String source;
  final List<MonosEntry> episodes;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;
  final ValueChanged<MonosEntry> onOpen;
  const MonosDetailView({
    super.key,
    this.compact = false,
    this.onClose,
    required this.anime,
    this.synopsis = '',
    this.synopsisLoading = false,
    this.synopsisError = false,
    this.onSynopsisRetry,
    required this.source,
    required this.episodes,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.onOpen,
  });
  @override
  State<MonosDetailView> createState() => _MonosDetailViewState();
}

class _MonosDetailViewState extends State<MonosDetailView> {
  String query = '';
  bool newest = true;
  final search = TextEditingController();
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.compact) {
      return AnimeDetailPanel(
        title: monosDisplayTitle(widget.anime.title),
        cover: widget.anime.image,
        source: widget.source,
        synopsis: widget.synopsis,
        loading: widget.loading,
        error: widget.error,
        onRetry: widget.onRetry,
        onClose: widget.onClose,
        synopsisLoading: widget.synopsisLoading,
        synopsisError: widget.synopsisError,
        onSynopsisRetry: widget.onSynopsisRetry,
        onPlay: widget.episodes.isEmpty
            ? null
            : () => widget.onOpen(
                widget.episodes.reduce((a, b) {
                  final x = double.tryParse(monosEpisodeNumber(a)),
                      y = double.tryParse(monosEpisodeNumber(b));
                  return x != null && y != null && y < x ? b : a;
                }),
              ),
        episodes: [
          for (final e in widget.episodes)
            PanelEpisode(
              number: monosEpisodeNumber(e).isEmpty
                  ? e.title
                  : monosEpisodeNumber(e),
              onTap: () => widget.onOpen(e),
            ),
        ],
      );
    }
    final episodes = widget.episodes.where((entry) {
      final number = monosEpisodeNumber(entry);
      return query.isEmpty ||
          (RegExp(r'^\d+(?:\.\d+)?$').hasMatch(query)
              ? number == query
              : entry.title.toLowerCase().contains(query));
    }).toList();
    episodes.sort((a, b) {
      final x = double.tryParse(monosEpisodeNumber(a)),
          y = double.tryParse(monosEpisodeNumber(b));
      if (x == null || y == null) return 0;
      return x.compareTo(y) * (newest ? -1 : 1);
    });
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: const Color(0xff101622),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xff222a3b)),
            ),
            child: LayoutBuilder(
              builder: (context, c) {
                final narrow = c.maxWidth < 540;
                final cover = ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: narrow ? 92 : 142,
                    height: narrow ? 136 : 206,
                    child: widget.anime.image.isEmpty
                        ? const ColoredBox(
                            color: Color(0xff211832),
                            child: Icon(
                              Icons.movie_outlined,
                              size: 42,
                              color: Color(0xffa577ff),
                            ),
                          )
                        : Image.network(
                            widget.anime.image,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const Icon(
                              Icons.movie_outlined,
                              size: 42,
                              color: Color(0xffa577ff),
                            ),
                          ),
                  ),
                );
                return Padding(
                  padding: EdgeInsets.all(narrow ? 16 : 24),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      cover,
                      SizedBox(width: narrow ? 16 : 24),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            sourceBadge(widget.source),
                            const SizedBox(height: 12),
                            Text(
                              monosDisplayTitle(widget.anime.title),
                              style: TextStyle(
                                fontSize: narrow ? 20 : 29,
                                fontWeight: FontWeight.w800,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Sinopsis',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 7),
                            if (widget.synopsisLoading)
                              const Text(
                                'Cargando sinopsis…',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xff8e98ad),
                                ),
                              )
                            else if (widget.synopsisError)
                              Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  const Text(
                                    'No se pudo cargar la sinopsis.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xff8e98ad),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: widget.onSynopsisRetry,
                                    child: const Text('Reintentar sinopsis'),
                                  ),
                                ],
                              )
                            else
                              SelectableText(
                                widget.synopsis.isEmpty
                                    ? 'Esta fuente no proporciona una sinopsis.'
                                    : widget.synopsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  height: 1.7,
                                  color: Color(0xffbac3d5),
                                ),
                              ),
                            const SizedBox(height: 16),
                            Text(
                              widget.loading
                                  ? 'Consultando episodios…'
                                  : '${widget.episodes.length} episodios disponibles',
                              style: const TextStyle(
                                color: Color(0xff8e98ad),
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 18),
                            if (widget.episodes.isNotEmpty)
                              FilledButton.icon(
                                onPressed: () => widget.onOpen(
                                  widget.episodes.reduce((a, b) {
                                    final x = double.tryParse(
                                          monosEpisodeNumber(a),
                                        ),
                                        y = double.tryParse(
                                          monosEpisodeNumber(b),
                                        );
                                    return x != null && y != null && y < x
                                        ? b
                                        : a;
                                  }),
                                ),
                                icon: const Icon(
                                  Icons.play_arrow_rounded,
                                  size: 19,
                                ),
                                label: const Text('Comenzar a ver'),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              const Icon(
                Icons.video_library_outlined,
                color: Color(0xffa577ff),
                size: 20,
              ),
              const SizedBox(width: 9),
              const Expanded(
                child: Text(
                  'Episodios',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                '${episodes.length} de ${widget.episodes.length}',
                style: const TextStyle(fontSize: 11, color: Color(0xff8e98ad)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 16,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 230,
                height: 38,
                child: TextField(
                  controller: search,
                  onChanged: (value) =>
                      setState(() => query = value.trim().toLowerCase()),
                  style: const TextStyle(fontSize: 12),
                  decoration: const InputDecoration(
                    hintText: 'Buscar episodio por número',
                    prefixIcon: Icon(Icons.search_rounded, size: 18),
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              DropdownButton<bool>(
                value: newest,
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(
                    value: true,
                    child: Text(
                      'Más recientes primero',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  DropdownMenuItem(
                    value: false,
                    child: Text(
                      'Desde el episodio 1',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => newest = value!),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (widget.loading) const LinearProgressIndicator(minHeight: 2),
          if (widget.error != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xff191929),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    color: Color(0xffa577ff),
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.error!,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  TextButton(
                    onPressed: widget.onRetry,
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            ),
          if (!widget.loading && widget.error == null && episodes.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: Text(
                'No hay episodios que coincidan con la búsqueda.',
                style: TextStyle(color: Color(0xff8e98ad), fontSize: 12),
              ),
            ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 350,
              mainAxisExtent: 88,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: episodes.length,
            itemBuilder: (context, index) {
              final episode = episodes[index],
                  number = monosEpisodeNumber(episode);
              return Tooltip(
                message: episode.title,
                child: Material(
                  color: const Color(0xff101622),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: Color(0xff252d40)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => widget.onOpen(episode),
                    hoverColor: const Color(0xff24183e),
                    child: Padding(
                      padding: const EdgeInsets.all(13),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 46,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: const Color(0xff24183e),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              number.isEmpty ? '▶' : number,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 17,
                                color: Color(0xffbc98ff),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  number.isEmpty
                                      ? episode.title
                                      : 'Episodio $number',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                const Text(
                                  'Ver episodio',
                                  style: TextStyle(
                                    color: Color(0xff8e98ad),
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.play_circle_outline_rounded,
                            size: 24,
                            color: Color(0xffa577ff),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
