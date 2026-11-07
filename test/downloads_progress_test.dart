import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neko_player_pc/media/downloads.dart';
import 'package:neko_player_pc/media/downloads_page.dart';
import 'package:neko_player_pc/media/source.dart';

DownloadTask task(String id) => DownloadTask(
  id,
  'Episodio $id',
  const MediaSource('Test', 'https://example.test/video', {}),
);

class UiDownloads extends Downloads {
  @override
  Future<void> get ready async {}
  @override
  Future<void> remove(DownloadTask task) async {
    tasks.remove(task);
    notifyListeners();
  }
}

void main() {
  testWidgets('small mascot stays centered on the actual filled endpoint', (
    tester,
  ) async {
    for (final value in [0.0, .02, .25, .73, 1.0]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 600, child: DownloadProgress(value: value)),
          ),
        ),
      );
      final bar = tester.getRect(find.byType(LinearProgressIndicator));
      final mascot = tester.getRect(find.byType(Image));
      final expected = (bar.left + bar.width * value).clamp(
        bar.left + 28,
        bar.right - 28,
      );
      expect(mascot.center.dx, closeTo(expected, .01));
      expect(mascot.width, 56);
      expect(mascot.bottom, closeTo(bar.top, .01));
      expect(
        tester.widget<Image>(find.byType(Image)).filterQuality,
        FilterQuality.high,
      );
    }
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('cancelled download can be retried or deleted', (tester) async {
    final manager = UiDownloads();
    manager.tasks.add(task('cancelled')..status = DownloadStatus.cancelled);
    await tester.pumpWidget(
      MaterialApp(home: DownloadsPage(downloads: manager)),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Reintentar'), findsOneWidget);
    await tester.tap(find.byTooltip('Eliminar episodio'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eliminar'));
    await tester.pumpAndSettle();
    expect(manager.tasks, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'cancelled history can be deleted without an existing video folder',
    () async {
      final root = await Directory.systemTemp.createTemp('neko-cancel-delete-');
      try {
        final manager = Downloads(
          directory: Directory('${root.path}/videos'),
          stateDirectory: Directory('${root.path}/state'),
        );
        await manager.ready;
        final t = task('cancelled')..status = DownloadStatus.cancelled;
        manager.tasks.add(t);
        await manager.remove(t);
        final restored = Downloads(
          directory: manager.directory,
          stateDirectory: manager.stateDirectory,
        );
        await restored.ready;
        expect(restored.tasks, isEmpty);
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test('progress distinguishes bytes, HLS segments and unknown totals', () {
    final t = task('1');
    expect(t.progressValue, isNull);
    t.bytes = 25;
    t.total = 100;
    expect(t.progressValue, .25);
    t.total = 0;
    t.segmentsTotal = 4;
    t.segmentsDone = 2;
    expect(t.progressValue, .5);
    final restored = DownloadTask.fromJson(t.toJson());
    expect(restored.progressValue, .5);
  });

  testWidgets(
    'bar uses actual zero and fractional values and animates unknown progress',
    (tester) async {
      for (final value in <double?>[0, .37, null]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: DownloadProgress(value: value)),
          ),
        );
        expect(
          tester
              .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator),
              )
              .value,
          value,
        );
        await tester.pump(const Duration(milliseconds: 500));
        final imageBottom = tester.getBottomLeft(find.byType(Image)).dy;
        final barTop = tester
            .getTopLeft(find.byType(LinearProgressIndicator))
            .dy;
        expect((imageBottom - barTop).abs(), lessThan(2));
        expect(
          tester
              .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator),
              )
              .backgroundColor,
          isNot(
            tester
                .widget<LinearProgressIndicator>(
                  find.byType(LinearProgressIndicator),
                )
                .color,
          ),
        );
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  test('deletion removes video, subtitle and persisted history but preserves neighbors', () async {
    final root = await Directory.systemTemp.createTemp('neko-delete-');
    try {
      final manager = Downloads(
        directory: Directory('${root.path}/videos'),
        stateDirectory: Directory('${root.path}/state'),
      );
      await manager.ready;
      await manager.directory.create();
      final t = task('1')
        ..status = DownloadStatus.done
        ..path = '${manager.directory.path}/episode-1.mp4'
        ..subtitlePath = '${manager.directory.path}/episode-1.es.vtt';
      final neighbor = File('${manager.directory.path}/episode-2.mp4');
      for (final name in [t.path, t.subtitlePath, neighbor.path]) {
        await File(name).writeAsString('fixture');
      }
      manager.tasks.add(t);
      await manager.removeCompleted(t);
      expect(await File(t.path).exists(), false);
      expect(await File(t.subtitlePath).exists(), false);
      expect(await neighbor.exists(), true);
      expect(manager.tasks, isEmpty);
      final restored = Downloads(
        directory: manager.directory,
        stateDirectory: manager.stateDirectory,
      );
      await restored.ready;
      expect(restored.tasks, isEmpty);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test(
    'deletion rejects foreign and shared files before removing any file',
    () async {
      final root = await Directory.systemTemp.createTemp('neko-delete-');
      try {
        final manager = Downloads(
          directory: root,
          stateDirectory: Directory('${root.path}/state'),
        );
        await manager.ready;
        final t = task('1')
          ..status = DownloadStatus.done
          ..path = '${root.path}/episode-1.mp4';
        await File(t.path).writeAsString('fixture');
        final other = task('2')..path = t.path;
        manager.tasks.addAll([t, other]);
        await expectLater(
          manager.removeCompleted(t),
          throwsA(isA<FileSystemException>()),
        );
        expect(await File(t.path).exists(), true);
        manager.tasks.remove(other);
        t.path = '${root.path}/episode-2.mp4';
        await File(t.path).writeAsString('other');
        await expectLater(
          manager.removeCompleted(t),
          throwsA(isA<FileSystemException>()),
        );
        expect(await File(t.path).exists(), true);
        expect(manager.tasks, contains(t));
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  testWidgets(
    'completed episode requires confirmation and updates after deletion',
    (tester) async {
      final manager = UiDownloads();
      final t = task('1')..status = DownloadStatus.done;
      manager.tasks.add(t);
      await tester.pumpWidget(
        MaterialApp(home: DownloadsPage(downloads: manager)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Eliminar episodio'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(manager.tasks, contains(t));
      await tester.tap(find.byTooltip('Eliminar episodio'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eliminar'));
      await tester.pumpAndSettle();
      expect(manager.tasks, isEmpty);
      expect(find.byTooltip('Eliminar episodio'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
