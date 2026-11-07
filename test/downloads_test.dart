import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neko_player_pc/media/source.dart';
import 'package:neko_player_pc/media/server_selector.dart';
import 'package:neko_player_pc/media/downloads.dart';

void main() {
  test(
    'server selection prefers measured throughput and tolerates failed hosts',
    () async {
      final result = await ServerSelector.rank([
        () async => const MediaSource('Slow', 'https://slow.test', {}),
        () async => const MediaSource('Fast', 'https://fast.test', {}),
        () async => throw const SocketException('offline'),
      ], probe: (s) async => s.name == 'Fast' ? 8000000 : 1000000);
      expect(result.first.source.name, 'Fast');
      expect(result.first.index, 1);
      expect(result.length, 2);
    },
  );

  test('cancelled comparisons do not resolve more candidates', () async {
    var calls = 0;
    final result = await ServerSelector.rank([
      () async {
        calls++;
        return const MediaSource('', 'https://x.test', {});
      },
    ], cancelled: () => true);
    expect(result, isEmpty);
    expect(calls, 0);
  });

  late Directory temporary;
  late HttpServer server;
  late Downloads downloads;
  late String base;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('neko-download-test-');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    downloads = Downloads(
      directory: Directory('${temporary.path}/videos'),
      stateDirectory: Directory('${temporary.path}/state'),
    );
    server.listen((request) async {
      try {
        if (request.headers.value('Referer') != 'https://provider.test/') {
          request.response.statusCode = 403;
          await request.response.close();
          return;
        }
        final path = request.uri.path;
        if (path == '/master.m3u8') {
          request.response.headers.contentType = ContentType(
            'application',
            'vnd.apple.mpegurl',
          );
          request.response.write(
            '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=100\nlow.m3u8\n#EXT-X-STREAM-INF:BANDWIDTH=900\nhigh.m3u8\n',
          );
        } else if (path == '/high.m3u8') {
          request.response.headers.contentType = ContentType(
            'application',
            'vnd.apple.mpegurl',
          );
          request.response.write(
            '#EXTM3U\n#EXTINF:3,\na.ts\n#EXTINF:3,\nb.ts\n#EXT-X-ENDLIST\n',
          );
        } else if (path == '/encrypted.m3u8') {
          request.response.headers.contentType = ContentType(
            'application',
            'vnd.apple.mpegurl',
          );
          request.response.write(
            '#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI="key"\n#EXTINF:3,\na.ts\n#EXT-X-ENDLIST\n',
          );
        } else if (path.endsWith('.ts')) {
          request.response.headers.contentType = ContentType('video', 'mp2t');
          request.response.write(path == '/a.ts' ? 'segment-A' : 'segment-B');
        } else if (path == '/sub.vtt') {
          request.response.headers.contentType = ContentType('text', 'vtt');
          request.response.write(
            'WEBVTT\n\n00:00:00.000 --> 00:00:01.000\nHola\n',
          );
        } else if (path == '/partial.mp4') {
          request.response.statusCode = 206;
          request.response.headers.set('Content-Range', 'bytes 0-3/1000');
          request.response.headers.contentType = ContentType('video', 'mp4');
          request.response.write('part');
        } else if (path == '/page') {
          request.response.headers.contentType = ContentType.html;
          request.response.write('<html>not video</html>');
        } else if (path == '/large.mp4') {
          request.response.headers.contentType = ContentType('video', 'mp4');
          request.response.contentLength = 8 * 1024 * 1024;
          final chunk = List<int>.filled(65536, 7);
          for (var i = 0; i < 128; i++) { request.response.add(chunk); }
        } else if (path == '/slow.mp4') {
          request.response.headers.contentType = ContentType('video', 'mp4');
          request.response.contentLength = 1000000;
          for (var i = 0; i < 100; i++) {
            request.response.add(List.filled(10000, 0));
            await request.response.flush();
            await Future<void>.delayed(const Duration(milliseconds: 15));
          }
        } else {
          request.response.headers.contentType = ContentType('video', 'mp4');
          final data = utf8.encode('complete-video-fixture');
          request.response.contentLength = data.length;
          request.response.add(data);
        }
        await request.response.close();
      } catch (_) {
        /* Un cliente puede cancelar o terminar la muestra antes. */
      }
    });
  });
  tearDown(() async {
    await server.close(force: true);
    await temporary.delete(recursive: true);
  });
  MediaSource source(
    String path, [
    List<Map<String, dynamic>> subtitles = const [],
  ]) => MediaSource('Fixture', '$base$path', {
    'Referer': 'https://provider.test/',
  }, subtitles);

  test('direct download preserves headers, saves Spanish subtitles and persists completion', () async {
    final task = await downloads.enqueue(
      'Naruto / episodio 1',
      source('/video.mp4', [
        {'lang': 'es', 'url': '$base/sub.vtt'},
      ]),
    );
    await downloads.waitFor(task).timeout(const Duration(seconds: 10));
    expect(task.status, DownloadStatus.done, reason: task.error);
    expect(await File(task.path).readAsString(), 'complete-video-fixture');
    expect(await File(task.subtitlePath).readAsString(), contains('Hola'));
    final restored = Downloads(
      directory: downloads.directory,
      stateDirectory: downloads.stateDirectory,
    );
    await restored.ready;
    expect(restored.tasks.single.status, DownloadStatus.done);
    expect(
      (await downloads.directory.list().toList()).any(
        (f) => f.path.endsWith('.part'),
      ),
      isFalse,
    );
  });

  test(
    'HLS downloads chosen variant and combines segments in playlist order',
    () async {
      final task = await downloads.enqueue('HLS', source('/master.m3u8'));
      await downloads.waitFor(task).timeout(const Duration(seconds: 10));
      expect(task.status, DownloadStatus.done, reason: task.error);
      expect(task.path, endsWith('.ts'));
      expect(await File(task.path).readAsString(), 'segment-Asegment-B');
    },
  );

  test('multi-megabyte downloads cross bounded flushes without truncating data', () async {
    final task = await downloads.enqueue('Large', source('/large.mp4'));
    await downloads.waitFor(task).timeout(const Duration(seconds:10));
    expect(task.status, DownloadStatus.done, reason: task.error);
    expect(task.bytes, 8 * 1024 * 1024);
    final bytes=await File(task.path).readAsBytes();
    expect(bytes.length, 8 * 1024 * 1024);
    expect(bytes.every((b)=>b==7), isTrue);
    await downloads.waitFor(task);
  });

  test('cancelling queued tasks completes their waiters without starting a transfer', () async {
    final active=await downloads.enqueue('Active',source('/slow.mp4'));
    final queued=await downloads.enqueue('Queued',source('/large.mp4'));
    final waiting=downloads.waitFor(queued);
    downloads.cancel(queued);
    await waiting.timeout(const Duration(seconds:2));
    expect(queued.status,DownloadStatus.cancelled);
    expect(queued.bytes,0);
    downloads.cancel(active);
    await downloads.waitFor(active).timeout(const Duration(seconds:10));
  });

  test('HTML and encrypted HLS do not become completed videos', () async {
    for (final path in ['/page', '/encrypted.m3u8', '/partial.mp4']) {
      final task = await downloads.enqueue('Invalid', source(path));
      await downloads.waitFor(task).timeout(const Duration(seconds: 10));
      expect(task.status, DownloadStatus.failed);
      expect(task.path, isEmpty);
    }
    expect(await downloads.directory.list().toList(), isEmpty);
  });

  test(
    'cancellation removes only the partial file and finishes the task',
    () async {
      final task = await downloads.enqueue('Cancel', source('/slow.mp4'));
      while (task.bytes == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      downloads.cancel(task);
      await downloads.waitFor(task).timeout(const Duration(seconds: 10));
      expect(task.status, DownloadStatus.cancelled);
      expect(await downloads.directory.list().toList(), isEmpty);
    },
  );

  test(
    'speed probe rejects HTML and measures actual bytes with required headers',
    () async {
      expect(
        await ServerSelector.measure(source('/video.mp4')),
        greaterThan(0),
      );
      expect(
        await ServerSelector.measure(source('/master.m3u8')),
        greaterThan(0),
      );
      await expectLater(
        ServerSelector.measure(source('/page')),
        throwsFormatException,
      );
    },
  );
}
