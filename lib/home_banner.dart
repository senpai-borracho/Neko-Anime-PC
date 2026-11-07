// Banner rotatorio del Inicio. Solo presentación: los datos y las acciones los
// entrega main.dart. Los colores se repiten aquí para no importar main.dart.
import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'app_ui.dart' show sourceBadge;

/// Datos opcionales que completan una diapositiva (nota, géneros, sinopsis...).
class BannerInfo {
  final String status, synopsis, banner, cover;
  final double? score;
  final List<String> genres;
  const BannerInfo({
    this.status = '',
    this.synopsis = '',
    this.banner = '',
    this.cover = '',
    this.score,
    this.genres = const [],
  });
}

class BannerSlide {
  final String id, title, cover, source, label;
  final bool saved;
  final VoidCallback onOpen, onSave;

  /// Se llama una sola vez por diapositiva, cuando está por mostrarse.
  final Future<BannerInfo?> Function()? loadInfo;

  /// Alternativa a [loadInfo] que va entregando datos a medida que llegan
  /// (primero lo rápido: imagen, nota, géneros; después la sinopsis).
  final Stream<BannerInfo?> Function()? infoStream;
  const BannerSlide({
    required this.id,
    required this.title,
    required this.cover,
    required this.source,
    required this.label,
    required this.onOpen,
    required this.onSave,
    this.saved = false,
    this.loadInfo,
    this.infoStream,
  });
}

const _bg = Color(0xff0b0f1a);
const _muted = Color(0xff9aa3b9);
const _ink = Color(0xfff0f1f6);
const _accent = Color(0xffa577ff);

class HomeBanner extends StatefulWidget {
  final List<BannerSlide> slides;
  final Duration interval;
  const HomeBanner({
    super.key,
    required this.slides,
    this.interval = const Duration(seconds: 8),
  });
  @override
  State<HomeBanner> createState() => _HomeBannerState();
}

class _HomeBannerState extends State<HomeBanner> {
  int index = 0;
  bool hovered = false;
  Timer? timer;
  final Map<String, ValueNotifier<BannerInfo?>> infos = {};

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(widget.interval, (_) {
      // Pausa con el cursor encima y mientras otra pantalla (p. ej. el
      // reproductor) está por encima del Inicio.
      if (!mounted || hovered) return;
      if (ModalRoute.of(context)?.isCurrent == false) return;
      go(1);
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    for (final notifier in infos.values) {
      notifier.dispose();
    }
    super.dispose();
  }

  void go(int step) {
    final count = widget.slides.length;
    if (count < 2) return;
    setState(() => index = ((index % count) + step) % count);
  }

  ValueNotifier<BannerInfo?> infoFor(BannerSlide slide) =>
      infos.putIfAbsent(slide.id, () {
        final notifier = ValueNotifier<BannerInfo?>(null);
        void deliver(BannerInfo? info) {
          if (info == null || !mounted) return;
          notifier.value = info;
          // En cuanto llegan los datos se descargan las imágenes, para que ya
          // estén listas cuando la diapositiva aparezca.
          precacheArt(slide, info);
        }

        final stream = slide.infoStream;
        final load = slide.loadInfo;
        if (stream != null) {
          stream().listen(deliver, onError: (Object _) {}, cancelOnError: false);
        } else if (load != null) {
          load().then(deliver).catchError((Object _) {});
        }
        return notifier;
      });

  void precacheArt(BannerSlide slide, BannerInfo? info) {
    if (!mounted) return;
    for (final url in {slide.cover, info?.banner ?? '', info?.cover ?? ''}) {
      if (url.isEmpty) continue;
      precacheImage(NetworkImage(url), context).catchError((Object _) {});
    }
  }

  Widget arrow(IconData icon, String tooltip, int step) => IconButton(
    tooltip: tooltip,
    onPressed: () => go(step),
    visualDensity: VisualDensity.compact,
    icon: Icon(icon, size: 20),
    style: IconButton.styleFrom(
      backgroundColor: const Color(0x80000000),
      foregroundColor: Colors.white,
      fixedSize: const Size(34, 34),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final slides = widget.slides;
    if (slides.isEmpty) return const SizedBox.shrink();
    final current = index % slides.length;
    // Se precargan las dos siguientes (datos e imágenes) para que ya estén
    // listas al aparecer.
    for (var ahead = 1; ahead <= 2 && ahead < slides.length; ahead++) {
      infoFor(slides[(current + ahead) % slides.length]);
    }
    return MouseRegion(
      onEnter: (_) => hovered = true,
      onExit: (_) => hovered = false,
      child: Container(
        height: 292,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xff2b3350)),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 450),
              child: _SlideView(
                key: ValueKey(slides[current].id),
                slide: slides[current],
                info: infoFor(slides[current]),
              ),
            ),
            if (slides.length > 1) ...[
              Positioned(
                left: 10,
                top: 0,
                bottom: 0,
                child: Center(
                  child: arrow(Icons.chevron_left_rounded, 'Anterior', -1),
                ),
              ),
              Positioned(
                right: 10,
                top: 0,
                bottom: 0,
                child: Center(
                  child: arrow(Icons.chevron_right_rounded, 'Siguiente', 1),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 6,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < slides.length; i++)
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () => setState(() => index = i),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 3,
                              vertical: 8,
                            ),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: i == current ? 22 : 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: i == current
                                    ? const Color(0xffc9b6ff)
                                    : const Color(0x66FFFFFF),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SlideView extends StatelessWidget {
  final BannerSlide slide;
  final ValueNotifier<BannerInfo?> info;
  const _SlideView({super.key, required this.slide, required this.info});

  Widget pill(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: const Color(0xcc1b1530),
      borderRadius: BorderRadius.circular(7),
      border: Border.all(color: const Color(0xff4a3a78)),
    ),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: Color(0xffd7c8ff),
      ),
    ),
  );

  Widget chip(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: const Color(0x990b0f1a),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: const Color(0x33FFFFFF)),
    ),
    child: Text(
      text,
      style: const TextStyle(fontSize: 10, color: Color(0xffd5dbea)),
    ),
  );

  Widget image(String url, {BoxFit fit = BoxFit.cover, Alignment? alignment}) =>
      Image.network(
        url,
        fit: fit,
        alignment: alignment ?? Alignment.center,
        // Aparece con un fundido suave en vez de "saltar" al terminar de cargar.
        frameBuilder: (context, child, frame, sync) => sync
            ? child
            : AnimatedOpacity(
                opacity: frame == null ? 0 : 1,
                duration: const Duration(milliseconds: 450),
                curve: Curves.easeOut,
                child: child,
              ),
        errorBuilder: (_, _, _) => const ColoredBox(color: _bg),
      );

  Widget background(String banner, String poster) {
    if (banner.isNotEmpty) {
      return image(banner, alignment: const Alignment(.4, -.3));
    }
    if (poster.isEmpty) return const ColoredBox(color: _bg);
    // Sin arte horizontal: la portada se desenfoca de fondo y se muestra
    // nítida a la derecha.
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
      child: Transform.scale(scale: 1.35, child: image(poster)),
    );
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<BannerInfo?>(
    valueListenable: info,
    builder: (context, data, _) {
      final banner = data?.banner ?? '';
      // Portada nítida de AniList si la hay; si no, la de la fuente.
      final poster = (data?.cover ?? '').isNotEmpty ? data!.cover : slide.cover;
      final status = (data?.status ?? '').isEmpty
          ? 'Nuevo episodio'
          : data!.status;
      final synopsis = data?.synopsis ?? '';
      final genres = (data?.genres ?? const <String>[]).take(2).toList();
      final showPoster = poster.isNotEmpty;
      return Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: _bg),
          RepaintBoundary(child: background(banner, poster)),
          // Degradado suave solo a la izquierda, para que la imagen se vea clara.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Color(0xe60b0f1a), Color(0x8c0b0f1a), Color(0x000b0f1a)],
                stops: [0, .5, 1],
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x000b0f1a), Color(0x660b0f1a)],
                stops: [.65, 1],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(56, 18, 56, 32),
            child: Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: LayoutBuilder(
                        builder: (context, box) => FittedBox(
                          // Si el contenido no cabe (título largo, varios géneros), se
                          // reduce un poco en vez de cortarse o chocar con los puntos.
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: SizedBox(width: box.maxWidth, child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            pill(status),
                            const SizedBox(height: 10),
                            Text(
                              slide.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 27,
                                fontWeight: FontWeight.w800,
                                height: 1.15,
                                letterSpacing: -.6,
                                color: Colors.white,
                              ),
                            ),
                            if (synopsis.isNotEmpty) ...[
                              const SizedBox(height: 9),
                              Text(
                                synopsis,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  height: 1.5,
                                  color: Color(0xffc9cfe0),
                                ),
                              ),
                            ],
                            const SizedBox(height: 11),
                            Wrap(
                              spacing: 10,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                if (data?.score != null)
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.star_rounded,
                                        size: 18,
                                        color: Color(0xffff6f91),
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        data!.score!.toStringAsFixed(1),
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                if (slide.source.isNotEmpty) sourceBadge(slide.source),
                                Text(
                                  slide.label,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: _muted,
                                  ),
                                ),
                                for (final genre in genres) chip(genre),
                              ],
                            ),
                            const SizedBox(height: 15),
                            Wrap(
                              spacing: 12,
                              runSpacing: 10,
                              children: [
                                FilledButton.icon(
                                  onPressed: slide.onOpen,
                                  icon: const Icon(Icons.play_arrow_rounded),
                                  label: const Text('Ver episodios'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xff8b43ee),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: 12,
                                    ),
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                                OutlinedButton.icon(
                                  onPressed: slide.onSave,
                                  icon: Icon(
                                    slide.saved ? Icons.check : Icons.add,
                                  ),
                                  label: Text(
                                    slide.saved ? 'En mi lista' : 'Mi lista',
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    backgroundColor: const Color(0x99000000),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 22,
                                      vertical: 12,
                                    ),
                                    foregroundColor: _ink,
                                    side: const BorderSide(
                                      color: Color(0x44FFFFFF),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        )),
                        ),
                      ),
                    ),
                  ),
                ),
                if (showPoster)
                  Padding(
                    padding: const EdgeInsets.only(left: 28),
                    child: SizedBox(
                      height: 200,
                      child: AspectRatio(
                        aspectRatio: 2 / 3,
                        child: Container(
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x66000000),
                                blurRadius: 18,
                                offset: Offset(0, 6),
                              ),
                            ],
                          ),
                          child: image(poster),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    },
  );
}
