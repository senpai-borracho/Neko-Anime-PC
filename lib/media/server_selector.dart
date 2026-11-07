import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'source.dart';
import 'http_media.dart';

class ServerMeasurement {
  final int index;
  final MediaSource source;
  final double bytesPerSecond;
  const ServerMeasurement(this.index, this.source, this.bytesPerSecond);
}

/// Muestra corta de video, no ping ni tamaño de la lista HLS.
class ServerSelector {
  static Future<double> measure(MediaSource source) async {
    if (Uri.parse(source.url).scheme == 'file') return double.infinity;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    final timeout = Timer(
      const Duration(seconds: 7),
      () => client.close(force: true),
    );
    try {
      final clock = Stopwatch()..start();
      var result = await mediaGet(
        client,
        Uri.parse(source.url),
        source.headers,
        range: 'bytes=0-524287',
      );
      for (var depth = 0; hlsResponse(result); depth++) {
        if (depth >= 4) {
          throw const FormatException('Demasiadas listas HLS anidadas.');
        }
        final text = await mediaText(result);
        final variant = hlsVariant(result.uri, text);
        final segment = const LineSplitter()
            .convert(text)
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty && !s.startsWith('#'))
            .firstOrNull;
        if (variant == null && segment == null) {
          throw const FormatException('HLS vacío.');
        }
        result = await mediaGet(
          client,
          variant ?? result.uri.resolve(segment!),
          source.headers,
          range: 'bytes=0-524287',
        );
      }
      final type = result.response.headers.contentType?.mimeType ?? '';
      if (invalidMediaType(type)) {
        throw const FormatException(
          'El servidor devolvió una página, no video.',
        );
      }
      var bytes = 0;
      await for (final chunk in result.response.timeout(
        const Duration(seconds: 4),
      )) {
        bytes += chunk.length;
        if (bytes >= 512 * 1024 || clock.elapsedMilliseconds >= 4500) break;
      }
      if (bytes == 0) {
        throw const FormatException('El servidor no entregó video.');
      }
      return bytes * 1000000 / clock.elapsedMicroseconds.clamp(1, 1 << 62);
    } finally {
      timeout.cancel();
      client.close(force: true);
    }
  }

  static Future<List<ServerMeasurement>> rank(
    List<Future<MediaSource> Function()> candidates, {
    bool Function()? cancelled,
    Future<double> Function(MediaSource)? probe,
  }) async {
    final found = <ServerMeasurement>[];
    var next = 0;
    final elapsed = Stopwatch()..start();
    Future<void> worker() async {
      while (next < candidates.length &&
          elapsed.elapsed.inSeconds < 30 &&
          !(cancelled?.call() ?? false)) {
        final index = next++;
        try {
          final source = await candidates[index]().timeout(
            const Duration(seconds: 12),
          );
          if (cancelled?.call() ?? false) return;
          var speed = 0.0;
          try {
            speed = await (probe ?? measure)(source)
                .timeout(const Duration(seconds: 8));
          } catch (_) {}
          found.add(ServerMeasurement(index, source, speed));
        } catch (_) {}
      }
    }

    await Future.wait([worker(), worker()]);
    found.sort((a, b) {
      final speed = b.bytesPerSecond.compareTo(a.bytesPerSecond);
      return speed != 0 ? speed : a.index.compareTo(b.index);
    });
    return found;
  }
}
