import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class MediaResponse {
  final Uri uri;
  final HttpClientResponse response;
  MediaResponse(this.uri, this.response);
}

Future<MediaResponse> mediaGet(
  HttpClient client,
  Uri uri,
  Map<String, String> headers, {
  String? range,
}) async {
  if (!['http', 'https'].contains(uri.scheme) || uri.host.isEmpty) {
    throw const FormatException('El enlace no es HTTP(S).');
  }
  final request = await client.getUrl(uri).timeout(const Duration(seconds: 12));
  request.headers.set('User-Agent', 'Mozilla/5.0 NekoPlayerPC');
  headers.forEach((key, value) => request.headers.set(key, value));
  if (range != null) request.headers.set('Range', range);
  final response = await request.close().timeout(const Duration(seconds: 15));
  if (response.statusCode != 200 && response.statusCode != 206) {
    throw HttpException('El servidor respondió ${response.statusCode}.');
  }
  var finalUri = uri;
  for (final redirect in response.redirects) {
    finalUri = finalUri.resolveUri(redirect.location);
  }
  return MediaResponse(finalUri, response);
}

Future<String> mediaText(
  MediaResponse result, {
  int limit = 2 * 1024 * 1024,
}) async {
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in result.response.timeout(
    const Duration(seconds: 15),
  )) {
    bytes.add(chunk);
    if (bytes.length > limit) {
      throw const FormatException('Lista de video demasiado grande.');
    }
  }
  return utf8.decode(bytes.takeBytes());
}

/// Selecciona una variante de video. Rechaza audio separado para evitar descargas mudas.
Uri? hlsVariant(Uri base, String text) {
  final lines = const LineSplitter()
      .convert(text)
      .map((s) => s.trim())
      .toList();
  Uri? best;
  var highest = -1;
  for (var i = 0; i + 1 < lines.length; i++) {
    if (!lines[i].startsWith('#EXT-X-STREAM-INF:')) continue;
    if (RegExp(r'(^|,)AUDIO="')
            .hasMatch(lines[i].split(':').skip(1).join(':')) &&
        lines.any(
          (line) =>
              line.startsWith('#EXT-X-MEDIA:') &&
              line.contains('TYPE=AUDIO') &&
              line.contains('URI='),
        )) {
      throw const FormatException(
        'Este HLS usa audio separado; elige otro servidor para descargar.',
      );
    }
    final bandwidth =
        int.tryParse(
          RegExp(r'(?:^|[, :])BANDWIDTH=(\d+)')
                  .firstMatch(lines[i])
                  ?.group(1) ??
              '',
        ) ??
        0;
    final next = lines
        .skip(i + 1)
        .where((line) => line.isNotEmpty && !line.startsWith('#'))
        .firstOrNull;
    if (next != null && bandwidth > highest) {
      highest = bandwidth;
      best = base.resolve(next);
    }
  }
  return best;
}

bool hlsResponse(MediaResponse result) =>
    result.uri.path.toLowerCase().endsWith('.m3u8') ||
    (result.response.headers.contentType?.mimeType ?? '').contains('mpegurl');

bool invalidMediaType(String type) =>
    type.contains('html') || type.contains('json') || type.startsWith('text/');
