import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:neko_player_pc/main.dart';
import 'package:neko_player_pc/catalog.dart';

Future<void> waitReal(WidgetTester tester, Duration duration) async {
  await tester.runAsync(() => Future<void>.delayed(duration));
  await tester.pump();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(MediaKit.ensureInitialized);
  testWidgets('Desktop live catalogue and navigation', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(key: key, child: const NekoApp()));
    for (
      int i = 0;
      i < 35 && find.text('Ver episodios').evaluate().isEmpty;
      i++
    ) {
      await waitReal(tester, const Duration(seconds: 2));
    }
    expect(find.text('Ver episodios'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await waitReal(tester, const Duration(seconds: 3));
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(
      Platform.environment['NEKO_SCREENSHOT_PATH'] ?? 'tool/desktop.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    await tester.tap(find.text('Catálogo').first);
    await tester.pump();
    expect(find.text('Explorar catálogo'), findsOneWidget);
    await tester.tap(find.text('Mi lista').first);
    await tester.pump();
    expect(find.byType(ChoiceChip), findsNWidgets(6));
  });
  testWidgets('Native libmpv decodes the local generated fixture', (
    tester,
  ) async {
    final player = Player();
    final controller = VideoController(player);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Video(controller: controller)),
      ),
    );
    try {
      await tester.runAsync(
        () => player.open(
          Media('${Directory.current.path}/tool/native_smoke.mp4'),
        ),
      );
      for (
        int i = 0;
        i < 20 && player.state.position.inMilliseconds < 500;
        i++
      ) {
        await waitReal(tester, const Duration(milliseconds: 500));
      }
      expect(player.state.position.inMilliseconds, greaterThan(0));
      expect(player.state.videoParams.w, 640);
      expect(player.state.videoParams.h, 360);
    } finally {
      await player.dispose();
    }
  });
  testWidgets('Remote episode decodes independently from the local fixture', (
    tester,
  ) async {
    final report = <String, dynamic>{
      'remoteVerified': false,
      'attempts': <String>[],
    };
    await File('tool/native_playback_result.json')
        .writeAsString(jsonEncode(report));
    final result = await tester.runAsync(() async {
      for (int attempt = 0; attempt < 3; attempt++) {
        final api = ProviderClient();
        try {
          const episode = Episode('1', 'https://jkanime.net/naruto/1/');
          final servers = await api.servers(episode);
          final stream = await api.resolve(servers.first, episode);
          return <String, Object>{
            'source': stream,
            'server': servers.first.name,
          };
        } catch (e) {
          (report['attempts'] as List<String>).add(e.toString());
        } finally {
          api.close();
        }
      }
      return <String, Object>{'error': (report['attempts'] as List).join('; ')};
    });
    expect(result, isNotNull);
    expect(
      result!['error'],
      isNull,
      reason: 'Provider request failed: ${result['error']}',
    );
    final source = result['source']! as StreamSource;
    // A fresh player guarantees that old local playback cannot satisfy this check.
    final player = Player();
    final controller = VideoController(player);
    final errors = <String>[];
    final subscription = player.stream.error.listen(errors.add);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Video(controller: controller)),
      ),
    );
    try {
      await tester.runAsync(
        () => player.open(
          Media(
            source.url,
            httpHeaders: {
              'User-Agent': userAgent,
              'Referer': source.referer,
              if (source.cookies.isNotEmpty) 'Cookie': source.cookies,
            },
          ),
        ),
      );
      for (
        int i = 0;
        i < 40 && player.state.position.inMilliseconds < 1000;
        i++
      ) {
        await waitReal(tester, const Duration(seconds: 1));
      }
      report.addAll({
        'server': result['server'],
        'mediaHost': Uri.parse(source.url).host,
        'positionMs': player.state.position.inMilliseconds,
        'durationSeconds': player.state.duration.inSeconds,
        'width': player.state.videoParams.w,
        'height': player.state.videoParams.h,
        'errors': errors,
      });
      final valid =
          player.state.position.inMilliseconds > 0 &&
          player.state.duration.inSeconds > 60 &&
          (player.state.videoParams.w ?? 0) > 0;
      report['remoteVerified'] = valid;
      await File('tool/native_playback_result.json')
          .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
      expect(
        valid,
        isTrue,
        reason: const JsonEncoder.withIndent('  ').convert(report),
      );
    } finally {
      await subscription.cancel();
      await player.dispose();
    }
  });
}


