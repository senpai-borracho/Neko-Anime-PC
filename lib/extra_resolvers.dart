// Resolutores adicionales para los servidores de LatAnime, OtakusTV, AnimeYT y
// AnimeYTX.
//
// El resolutor de catalog.dart solo sabe leer Voe y las páginas que muestran el
// .mp4/.m3u8 a simple vista (mp4upload, uqload, yourupload...). Otros servidores
// (Mixdrop, StreamWish, VidHide...) esconden el enlace dentro de un script
// empaquetado ("p,a,c,k,e,d"). Aquí se lee ese script como DATO: se desempaqueta
// con texto, NUNCA se ejecuta JavaScript. No modifica catalog.dart.
import 'catalog.dart';

// Un script empaquetado termina en: }('payload',base,cantidad,'a|b|c'.split('|')
final RegExp _packed = RegExp(
  r"\}\('([^'\\]*(?:\\.[^'\\]*)*)',\s*(\d+),\s*(\d+),\s*'([^'\\]*(?:\\.[^'\\]*)*)'\.split\('\|'\)",
  dotAll: true,
);

const _digits =
    '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';

int? _index(String word, int radix) {
  var value = 0;
  for (final unit in word.split('')) {
    final digit = _digits.indexOf(unit);
    if (digit < 0 || digit >= radix) return null;
    value = value * radix + digit;
  }
  return value;
}

String _unescape(String value) =>
    value.replaceAllMapped(RegExp(r'\\(.)', dotAll: true), (m) => m[1]!);

/// Devuelve el texto de cada script empaquetado encontrado en [text].
List<String> unpackAll(String text) {
  final results = <String>[];
  for (final match in _packed.allMatches(text)) {
    final radix = int.tryParse(match[2]!) ?? 0;
    if (radix < 2 || radix > 62) continue;
    final words = _unescape(match[4]!).split('|');
    results.add(
      _unescape(match[1]!).replaceAllMapped(RegExp(r'\b\w+\b'), (word) {
        final i = _index(word[0]!, radix);
        return i != null && i < words.length && words[i].isNotEmpty
            ? words[i]
            : word[0]!;
      }),
    );
  }
  return results;
}

/// Busca el enlace del video dentro de un script ya desempaquetado.
String? _mediaIn(String script, String base) {
  final text = script.replaceAll(r'\/', '/');
  // Mixdrop: MDCore.wurl="//host/v2/ID.mp4?s=...&e=..."
  final wurl = RegExp(
    r'''wurl\s*=\s*["']([^"']+)["']''',
  ).firstMatch(text)?[1];
  if (wurl != null) {
    final url = Uri.parse(base).resolve(wurl).toString();
    if (url.startsWith('https://') && !ProviderClient.fake(url)) return url;
  }
  // StreamWish / VidHide y similares: file:"...m3u8", "hls2":"...", "hls4":"/stream/..."
  for (final match in RegExp(
    r'''["']([^"'\s]+\.(?:m3u8|mp4)[^"'\s]*)["']''',
    caseSensitive: false,
  ).allMatches(text)) {
    final url = Uri.parse(base).resolve(match[1]!).toString();
    if (url.startsWith('https://') &&
        ProviderClient.isMedia(url) &&
        !ProviderClient.fake(url)) {
      return url;
    }
  }
  return null;
}

/// Intenta resolver [server] con lectores extra. Devuelve null cuando el
/// servidor es de los que ya resuelve catalog.dart (Voe o enlace directo).
Future<StreamSource?> resolveExtra(
  ProviderClient api,
  Server server,
  Episode episode,
) async {
  final uri = Uri.tryParse(server.url);
  if (uri == null || uri.scheme != 'https') return null;
  if (server.name.toLowerCase().startsWith('voe') || uri.host == 'voe.sx') {
    return null; // Voe tiene su propio lector en catalog.dart.
  }
  if (ProviderClient.isMedia(server.url)) return null;
  final text = await api.fetch(server.url, referer: episode.url, cached: false);
  if (RegExp(
    r'cf-turnstile|g-recaptcha|cf-chl-widget',
    caseSensitive: false,
  ).hasMatch(text)) {
    throw const FormatException(
      'El servidor solicita verificación de navegador. Elige otro servidor.',
    );
  }
  String? media;
  // El script empaquetado es el reproductor real: va primero.
  for (final script in unpackAll(text)) {
    media = _mediaIn(script, server.url);
    if (media != null) break;
  }
  media ??= ProviderClient.extract(text, server.url);
  if (media == null) {
    throw FormatException(
      '${server.name} no expone un video compatible. Prueba otro servidor.',
    );
  }
  return StreamSource(media, server.url, api.cookieHeader(media));
}
