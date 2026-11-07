import 'package:flutter/material.dart';

/// Shows the welcome artwork while the initial library/catalog request is pending.
/// The existing home page stays mounted, so its startup runs only once.
class StartupOverlay extends StatelessWidget {
  final bool loading;
  final Widget child;
  const StartupOverlay({super.key, required this.loading, required this.child});

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      ExcludeFocus(
        excluding: loading,
        child: ExcludeSemantics(excluding: loading, child: child),
      ),
      if (loading)
        Positioned.fill(
          child: ColoredBox(
            color: const Color(0xff080b15),
            child: Center(
              child: AspectRatio(
                aspectRatio: 1672 / 941,
                child: LayoutBuilder(
                  builder: (context, bounds) => Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset(
                        'assets/neko_welcome.png',
                        fit: BoxFit.contain,
                        semanticLabel: 'Bienvenido a Neko Anime',
                        errorBuilder: (_, _, _) => const Center(
                          child: Icon(
                            Icons.pets_rounded,
                            color: Color(0xffae80ff),
                            size: 48,
                          ),
                        ),
                      ),
                      // Beside the artwork's existing "Iniciando…" label, away from the mascot.
                      Positioned(
                        left: bounds.maxWidth * .171,
                        top: bounds.maxHeight * .864,
                        child: SizedBox(
                          width: (bounds.maxWidth * .009).clamp(10, 18),
                          height: (bounds.maxWidth * .009).clamp(10, 18),
                          child: const CircularProgressIndicator(
                            strokeWidth: 1.6,
                            color: Color(0xffb77cff),
                            semanticsLabel: 'Cargando catálogo',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}
