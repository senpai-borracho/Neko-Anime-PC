import 'package:flutter/material.dart';

class PanelEpisode {
  final String number;
  final bool resume;
  final VoidCallback onTap;
  const PanelEpisode({
    required this.number,
    required this.onTap,
    this.resume = false,
  });
}

/// Shared presentation only. All data loading and playback remain with the caller.
class AnimeDetailPanel extends StatefulWidget {
  final String title, cover, source, synopsis;
  final bool loading, saved, synopsisLoading, synopsisError;
  final String? error;
  final VoidCallback? onClose, onPlay, onSave, onRetry, onSynopsisRetry;
  final List<PanelEpisode> episodes;
  const AnimeDetailPanel({
    super.key,
    required this.title,
    required this.cover,
    required this.source,
    required this.synopsis,
    required this.episodes,
    this.loading = false,
    this.saved = false,
    this.synopsisLoading = false,
    this.synopsisError = false,
    this.error,
    this.onClose,
    this.onPlay,
    this.onSave,
    this.onRetry,
    this.onSynopsisRetry,
  });
  @override
  State<AnimeDetailPanel> createState() => _AnimeDetailPanelState();
}

class _AnimeDetailPanelState extends State<AnimeDetailPanel> {
  bool expanded = false, descending = false;
  String query = '';
  static const violet = Color(0xffae80ff), muted = Color(0xff9aa3b9);
  @override
  Widget build(BuildContext context) {
    final episodes = widget.episodes
        .where((e) => query.isEmpty || e.number.toLowerCase().contains(query))
        .toList();
    if (descending) {
      episodes.sort(
        (a, b) => (double.tryParse(b.number) ?? 0).compareTo(
          double.tryParse(a.number) ?? 0,
        ),
      );
    }
    return ColoredBox(
      color: const Color(0xff0c101b),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 9, 8, 4),
            child: Row(
              children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(
                    color: violet,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    widget.source,
                    style: const TextStyle(
                      fontSize: 11,
                      color: muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Cerrar ficha',
                  onPressed: widget.onClose,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded, size: 18, color: muted),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 72,
                      height: 104,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: const Color(0xff303044)),
                      ),
                      child: widget.cover.isEmpty
                          ? const Icon(Icons.movie_outlined, color: muted)
                          : Image.network(
                              widget.cover,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => const Icon(
                                Icons.movie_outlined,
                                color: muted,
                              ),
                            ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              height: 1.3,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -.25,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            widget.loading
                                ? 'Cargando episodios…'
                                : '${widget.episodes.length} episodios',
                            style: const TextStyle(fontSize: 11, color: muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (widget.synopsisLoading)
                  const Text(
                    'Cargando sinopsis…',
                    style: TextStyle(color: muted, fontSize: 12),
                  )
                else if (widget.synopsisError)
                  TextButton(
                    onPressed: widget.onSynopsisRetry,
                    child: const Text('Reintentar sinopsis'),
                  )
                else ...[
                  Text(
                    widget.synopsis.isEmpty
                        ? 'Sin sinopsis disponible.'
                        : widget.synopsis,
                    maxLines: expanded ? null : 3,
                    overflow: expanded
                        ? TextOverflow.visible
                        : TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: muted,
                      fontSize: 12,
                      height: 1.55,
                    ),
                  ),
                  if (widget.synopsis.isNotEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: violet,
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 28),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => setState(() => expanded = !expanded),
                        child: Text(
                          expanded ? 'Ver menos' : 'Ver sinopsis',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 42,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: widget.onPlay == null
                            ? const [Color(0xff30243f), Color(0xff241d30)]
                            : const [Color(0xffa04aff), Color(0xff7133cf)],
                      ),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color: const Color(0xffb780ff).withValues(alpha: .45),
                      ),
                      boxShadow: widget.onPlay == null
                          ? []
                          : [
                              BoxShadow(
                                color: const Color(0xff8b35ed)
                                    .withValues(alpha: .18),
                                blurRadius: 14,
                                offset: const Offset(0, 4),
                              ),
                            ],
                    ),
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        disabledBackgroundColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        shadowColor: Colors.transparent,
                        overlayColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: widget.onPlay,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 23,
                            height: 23,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .13),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              size: 17,
                            ),
                          ),
                          const SizedBox(width: 9),
                          const Text(
                            'Reproducir',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: .15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (widget.onSave != null) ...[
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Mi lista',
                    child: SizedBox(
                      width: 44,
                      height: 42,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          foregroundColor: violet,
                          backgroundColor: const Color(0xff1c152b),
                          overlayColor: violet,
                          side: const BorderSide(color: Color(0xff39304c)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: widget.onSave,
                        child: Icon(
                          widget.saved
                              ? Icons.bookmark_rounded
                              : Icons.bookmark_border_rounded,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xff222637)),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 10, 6),
            child: Row(
              children: [
                const Text(
                  'Episodios',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                IconButton(
                  tooltip: descending
                      ? 'Orden ascendente'
                      : 'Orden descendente',
                  onPressed: () => setState(() => descending = !descending),
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    descending ? Icons.south_rounded : Icons.north_rounded,
                    size: 17,
                    color: muted,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
            child: SizedBox(
              height: 36,
              child: TextField(
                onChanged: (value) =>
                    setState(() => query = value.trim().toLowerCase()),
                style: const TextStyle(fontSize: 12),
                decoration: InputDecoration(
                  hintText: 'Buscar episodio',
                  hintStyle: const TextStyle(fontSize: 12, color: muted),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    size: 17,
                    color: muted,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  filled: true,
                  fillColor: const Color(0xff141826),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.zero,
            child: widget.loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : widget.error != null
                ? Center(
                    child: TextButton(
                      onPressed: widget.onRetry,
                      child: const Text('Reintentar episodios'),
                    ),
                  )
                : episodes.isEmpty
                ? Center(
                    child: Text(
                      query.isEmpty
                          ? 'Sin episodios disponibles'
                          : 'Sin resultados',
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    itemCount: episodes.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 5),
                    itemBuilder: (_, index) {
                      final e = episodes[index];
                      return Material(
                        color: e.resume
                            ? const Color(0xff221735)
                            : const Color(0xff111522),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: e.resume
                                ? const Color(0xff623d91)
                                : const Color(0xff1c2131),
                          ),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: e.onTap,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 11,
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.play_arrow_rounded,
                                  size: 20,
                                  color: violet,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Episodio ${e.number}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                if (e.resume)
                                  const Text(
                                    'Continuar',
                                    style: TextStyle(
                                      color: violet,
                                      fontSize: 10,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
