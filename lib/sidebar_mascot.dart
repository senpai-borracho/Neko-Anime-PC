import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SidebarMascot extends StatefulWidget {
  final bool compact;
  const SidebarMascot({super.key, required this.compact});
  @override
  State<SidebarMascot> createState() => _SidebarMascotState();
}

class _SidebarMascotState extends State<SidebarMascot> {
  ui.Image? sheet;
  Timer? reaction;
  int pose = 0;
  bool hovered = false;
  Offset gaze = Offset.zero;

  @override
  void initState() {
    super.initState();
    loadSheet();
  }

  Future<void> loadSheet() async {
    final bytes = await rootBundle.load('assets/neko_mascot.png');
    final codec = await ui.instantiateImageCodec(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
    final frame = await codec.getNextFrame();
    codec.dispose();
    if (!mounted) {
      frame.image.dispose();
      return;
    }
    setState(() => sheet = frame.image);
  }

  @override
  void dispose() {
    reaction?.cancel();
    sheet?.dispose();
    super.dispose();
  }

  void react(int value) {
    reaction?.cancel();
    setState(() => pose = value);
    reaction = Timer(const Duration(milliseconds: 1700), () {
      if (mounted) setState(() => pose = hovered ? 1 : 0);
    });
  }

  void rest() {
    reaction?.cancel();
    setState(() {
      pose = pose == 0 ? 1 : 0;
      gaze = Offset.zero;
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) => MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        reaction?.cancel();
        setState(() {
          hovered = true;
          pose = 1;
        });
      },
      onExit: (_) {
        reaction?.cancel();
        setState(() {
          hovered = false;
          pose = 0;
          gaze = Offset.zero;
        });
      },
      onHover: (event) {
        if (pose == 0) return;
        setState(
          () => gaze = Offset(
            ((event.localPosition.dx / bounds.maxWidth) - .5).clamp(-.5, .5) *
                .025,
            0,
          ),
        );
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => react(2),
        onDoubleTap: () => react(3),
        onSecondaryTap: rest,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(5, 4, 5, 8),
          child: SizedBox(
            width: double.infinity,
            height: widget.compact ? 48 : 145,
            child: AnimatedSlide(
              offset: gaze,
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              child: AnimatedScale(
                scale: pose == 2 ? 1.025 : 1,
                duration: const Duration(milliseconds: 200),
                child: Semantics(
                  label: pose == 0
                      ? 'Mascota de Neko descansando'
                      : 'Mascota de Neko interactuando',
                  button: true,
                  child: CustomPaint(painter: _MascotPainter(sheet, pose)),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _MascotPainter extends CustomPainter {
  final ui.Image? sheet;
  final int pose;
  const _MascotPainter(this.sheet, this.pose);
  @override
  void paint(Canvas canvas, Size size) {
    final image = sheet;
    if (image == null) return;
    final w = image.width / 2, h = image.height / 2;
    final src = Rect.fromLTWH((pose % 2) * w, (pose ~/ 2) * h, w, h);
    final fitted = applyBoxFit(BoxFit.contain, Size(w, h), size);
    final dst = Alignment.bottomCenter.inscribe(
      fitted.destination,
      Offset.zero & size,
    );
    canvas.drawImageRect(
      image,
      src,
      dst,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_MascotPainter oldDelegate) =>
      oldDelegate.sheet != sheet || oldDelegate.pose != pose;
}
