import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:neko_player_pc/catalog.dart';
import 'package:neko_player_pc/main.dart';

class IsolatedLibrary extends Library {
  @override
  void record(
    Anime anime,
    Episode episode,
    Duration position,
    Duration duration,
  ) {}
  @override
  int resume(Episode episode) => 0;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(MediaKit.ensureInitialized);
  for (final provider in ['JKAnime', 'AnimeAV1']) {
    testWidgets(
      'Dark Machine 1 $provider keeps playing without a false failure overlay',
      (tester) async {
        final api = ProviderClient();
        final base = provider == 'JKAnime'
            ? 'https://jkanime.net/dark-machine-the-animation/'
            : 'https://animeav1.com/media/dark-machine-the-animation';
        final episode = Episode(
          '1',
          provider == 'JKAnime' ? '${base}1/' : '$base/1',
        );
        final detail = Detail(
          Anime('Dark Machine: The Animation', base, ''),
          '',
          [episode],
        );
        final errors = <String>[];
        await tester.pumpWidget(
          MaterialApp(
            home: PlaybackPage(
              detail: detail,
              episode: episode,
              api: api,
              library: IsolatedLibrary(),
            ),
          ),
        );
        final dynamic state = tester.state(find.byType(PlaybackPage));
        final player = state.player as Player;
        final subscription = player.stream.error.listen(errors.add);
        final report = <String, dynamic>{
          'provider': provider,
          'episode': 1,
          'verified': false,
        };
        try {
          for (
            int i = 0;
            i < 65 && player.state.position.inMilliseconds < 700;
            i++
          ) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(seconds: 1)),
            );
            await tester.pump();
            if (find.text('Probemos otra opción').evaluate().isNotEmpty) break;
          }
          expect(
            player.state.position.inMilliseconds,
            greaterThan(0),
            reason: errors.join('\n'),
          );
          expect(player.state.videoParams.w, greaterThan(0));
          final initial = player.state.position;
          // Same path as an innocuous decoder/network diagnostic from media_kit.
          state.health.note(
            'Recoverable diagnostic injected while the video advances',
          );
          for (int i = 0; i < 35; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(seconds: 1)),
            );
            await tester.pump();
            expect(
              find.text('Probemos otra opción'),
              findsNothing,
              reason: 'A diagnostic must not cover progressing video',
            );
          }
          final native = player.platform as NativePlayer;
          final timeout = await native.getProperty('network-timeout');
          final buffer = await native.getProperty('demuxer-max-bytes');
          report.addAll({
            'positionMs': player.state.position.inMilliseconds,
            'durationSeconds': player.state.duration.inSeconds,
            'width': player.state.videoParams.w,
            'height': player.state.videoParams.h,
            'timeoutSeconds': timeout,
            'bufferBytes': buffer,
            'nativeDiagnostics': errors,
            'falseOverlayVisible': find
                .text('Probemos otra opción')
                .evaluate()
                .isNotEmpty,
            'verified':
                player.state.position > initial + const Duration(seconds: 10),
          });
          expect(double.tryParse(timeout), 20);
          expect(report['verified'], true);
        } finally {
          await File(
            'tool/recovery_${provider.toLowerCase()}.json',
          ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
          await subscription.cancel();
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          api.close();
        }
      },
    );
  }
}
