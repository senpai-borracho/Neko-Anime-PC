// Traductor inglés → español para las sinopsis que solo existen en inglés
// (las de AniList). Se usa como ÚLTIMO recurso: primero se intenta la sinopsis
// en español de la propia fuente.
//
// Servicios gratuitos, sin clave, en este orden:
//   1) endpoint público de Google Translate (no oficial);
//   2) MyMemory (API gratuita) si el primero falla.
// Si ninguno responde, se devuelve el texto original en inglés. Las
// traducciones se guardan en %LOCALAPPDATA%\NekoPlayerPC\translations.json para
// no repetir consultas.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

class Translator {
  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8);
  final Map<String, String> _cache = {};
  bool _loaded = false;

  /// Interruptor de Ajustes: si está apagado se devuelve el texto original.
  bool enabled = true;

  void close() => _http.close(force: true);

  File get _file {
    final base = Platform.environment['LOCALAPPDATA'] ?? Directory.current.path;
    return File('$base/NekoPlayerPC/translations_es.json');
  }

  /// Lee el interruptor y las traducciones guardadas. Se puede llamar varias veces.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      if (!await _file.exists()) return;
      final data = jsonDecode(await _file.readAsString());
      if (data is! Map) return;
      enabled = data['enabled'] != false;
      final cache = data['cache'];
      if (cache is Map) {
        for (final e in cache.entries) {
          if (e.value is String) _cache['${e.key}'] = e.value as String;
        }
      }
    } catch (_) {}
  }

  /// Cambia el interruptor y lo guarda.
  Future<void> setEnabled(bool value) async {
    enabled = value;
    await _save();
  }

  Future<void> _save() async {
    try {
      // Se conservan solo las últimas 300 para que el archivo no crezca sin fin.
      while (_cache.length > 300) {
        _cache.remove(_cache.keys.first);
      }
      await _file.parent.create(recursive: true);
      await _file.writeAsString(jsonEncode({'enabled': enabled, 'cache': _cache}));
    } catch (_) {}
  }

  /// Recorta a [maxChars] cortando en un punto, y quita notas como "(Source: ...)".
  static String _shorten(String text, int maxChars) {
    var value = text
        .replaceAll(RegExp(r'\(Source:[^)]*\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    value = value.replaceFirst(RegExp(r'\s*Note:.*$', caseSensitive: false), '').trim();
    if (value.length <= maxChars) return value;
    final cut = value.substring(0, maxChars);
    final end = [cut.lastIndexOf('. '), cut.lastIndexOf('! '), cut.lastIndexOf('? ')]
        .reduce((a, b) => a > b ? a : b);
    return end > maxChars ~/ 2 ? cut.substring(0, end + 1) : '${cut.trimRight()}…';
  }

  /// Traduce [text] al español. Devuelve el original si no se pudo traducir.
  /// El banner solo muestra dos líneas, así que basta con el inicio del texto.
  Future<String> toSpanish(String text, {int maxChars = 380}) async {
    final source = _shorten(text, maxChars);
    if (source.isEmpty) return '';
    await load();
    if (!enabled) return text;
    final cached = _cache[source];
    if (cached != null) return cached;
    String? result;
    try {
      result = await _google(source);
    } catch (_) {}
    if (result == null || result.trim().isEmpty) {
      try {
        result = await _myMemory(source.length > 480 ? _shorten(source, 480) : source);
      } catch (_) {}
    }
    if (result == null || result.trim().isEmpty) return source;
    _cache[source] = result;
    await _save();
    return result;
  }

  Future<String> _get(Uri uri) async {
    final request = await _http.getUrl(uri).timeout(const Duration(seconds: 10));
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close().timeout(const Duration(seconds: 12));
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw HttpException('Traductor respondió ${response.statusCode}');
    }
    return body;
  }

  Future<String?> _google(String text) async {
    final body = await _get(
      Uri.https('translate.googleapis.com', '/translate_a/single', {
        'client': 'gtx',
        'sl': 'en',
        'tl': 'es',
        'dt': 't',
        'q': text,
      }),
    );
    final data = jsonDecode(body);
    final parts = data is List && data.isNotEmpty ? data[0] : null;
    if (parts is! List) return null;
    return parts
        .map((part) => part is List && part.isNotEmpty ? '${part[0] ?? ''}' : '')
        .join()
        .trim();
  }

  Future<String?> _myMemory(String text) async {
    final body = await _get(
      Uri.https('api.mymemory.translated.net', '/get', {
        'q': text,
        'langpair': 'en|es',
      }),
    );
    final data = jsonDecode(body);
    final answer = data is Map && data['responseData'] is Map
        ? (data['responseData'] as Map)['translatedText']
        : null;
    if (answer is! String || answer.toUpperCase().contains('MYMEMORY WARNING')) {
      return null;
    }
    return answer.trim();
  }
}
