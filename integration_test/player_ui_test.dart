import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:neko_player_pc/catalog.dart';
import 'package:neko_player_pc/main.dart';

// UI testing uses only a local clip. No requests to any provider or server.
class LocalProvider extends ProviderClient {
  @override
  Future<List<Server>> servers(Episode episode) async => [
    const Server('Servidor de prueba con nombre largo', 'local'),
  ];
  @override
  Future<StreamSource> resolve(Server server, Episode episode) async =>
      StreamSource('${Directory.current.path}/tool/native_smoke.mp4', '');
}

class IsolatedLibrary extends Library {
  @override
  void record(Anime a, Episode e, Duration p, Duration d) {}
  @override
  int resume(Episode e) => 0;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(MediaKit.ensureInitialized);
  testWidgets(
    'Visible back buttons work in window and fullscreen without overflow',
    (tester) async {
      final api = LocalProvider();
      const episode = Episode('1', 'local');
      const detail = Detail(
        Anime(
          'Anime con un título muy largo para comprobar el ajuste del encabezado',
          'https://animeav1.com/media/prueba',
          '',
        ),
        '',
        [episode],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PlaybackPage(
                      detail: detail,
                      episode: episode,
                      api: api,
                      library: IsolatedLibrary(),
                    ),
                  ),
                ),
                child: const Text('Abrir reproductor'),
              ),
            ),
          ),
        ),
      );
      for (final fullscreen in [false, true]) {
        await tester.binding.setSurfaceSize(
          fullscreen ? const Size(720, 480) : const Size(1280, 720),
        );
        await tester.tap(find.text('Abrir reproductor'));
        await tester.pumpAndSettle();
        for (var i = 0; i < 15; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 300)),
          );
          await tester.pump();
          final dynamic state = tester.state(find.byType(PlaybackPage));
          if ((state.player as Player).state.position.inMilliseconds > 100) {
            break;
          }
        }
        expect(find.byKey(const ValueKey('player-back')), findsOneWidget);
        expect(tester.widget<Video>(find.byType(Video)).fit, BoxFit.contain);
        expect(tester.takeException(), isNull);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(tester.getCenter(find.byType(Video)));
        await tester.pumpAndSettle();
        if (fullscreen) {
          await enterFullscreen(
            tester.element(find.byKey(const ValueKey('video-back'))),
          );
          await tester.pumpAndSettle();
          expect(
            isFullscreen(
              tester.element(find.byKey(const ValueKey('video-back')).last),
            ),
            true,
          );
        }
        final center = tester.getCenter(find.byType(Video).last);
        await mouse.moveTo(center + const Offset(8, 8));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('video-back')).last, findsOneWidget);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(seconds: 5)),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('video-back')),
          findsNothing,
          reason: 'Back button must hide with idle video controls',
        );
        await mouse.moveTo(center + const Offset(20, 12));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('video-back')).last, findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('video-back')).last);
        await mouse.removePointer();
        await tester.pumpAndSettle();
        expect(find.text('Abrir reproductor'), findsOneWidget);
        expect(find.byType(PlaybackPage), findsNothing);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      api.close();
    },
  );
}
