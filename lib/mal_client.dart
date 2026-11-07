// Inicio de sesión con MyAnimeList (API oficial v2, OAuth2 con PKCE).
//
// Cada persona conecta SU cuenta en SU equipo: el token se guarda solo en
// %LOCALAPPDATA%\NekoPlayerPC\mal.json y Neko nunca ve la contraseña (el login
// ocurre en la página de MAL, en el navegador). Solo lectura: nombre y lista.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Client ID de la app registrada en https://myanimelist.net/apiconfig
/// (tipo "other", Redirect URI: http://localhost:8765/callback).
/// El Client ID es público: no es una contraseña, se puede incluir en el programa.
const malClientId = '51ceafb740554e41ca327cdf6920f370';

const _port = 8765;
const _redirect = 'http://localhost:$_port/callback';

class MalEntry {
  final int id;
  final String title, status, picture;
  final int watched, total;
  final int score;
  const MalEntry({
    required this.id,
    required this.title,
    required this.status,
    required this.picture,
    required this.watched,
    required this.total,
    required this.score,
  });
}

class MalClient {
  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10);
  String? _access, _refresh;
  DateTime? _expires;
  String name = '';

  /// Marcar episodios vistos en MAL automáticamente (se guarda junto a la sesión).
  bool autoSync = true;

  bool get configured =>
      malClientId.isNotEmpty && !malClientId.startsWith('PEGA');
  bool get connected => _refresh != null;

  File get _file {
    final base = Platform.environment['LOCALAPPDATA'] ?? Directory.current.path;
    return File('$base/NekoPlayerPC/mal.json');
  }

  void close() => _http.close(force: true);

  Future<void> load() async {
    try {
      if (!await _file.exists()) return;
      final data = jsonDecode(await _file.readAsString());
      if (data is! Map) return;
      _access = data['access'] as String?;
      _refresh = data['refresh'] as String?;
      final ms = data['expires'];
      _expires = ms is num ? DateTime.fromMillisecondsSinceEpoch(ms.toInt()) : null;
      name = '${data['name'] ?? ''}';
      autoSync = data['autoSync'] != false;
    } catch (_) {
      // Archivo dañado: se ignora y se vuelve a iniciar sesión.
    }
  }

  Future<void> saveSettings() => _save();

  Future<void> _save() async {
    try {
      await _file.parent.create(recursive: true);
      await _file.writeAsString(
        jsonEncode({
          'access': _access,
          'refresh': _refresh,
          'expires': _expires?.millisecondsSinceEpoch,
          'name': name,
          'autoSync': autoSync,
        }),
      );
    } catch (_) {}
  }

  Future<void> logout() async {
    _access = _refresh = null;
    _expires = null;
    name = '';
    try {
      if (await _file.exists()) await _file.delete();
    } catch (_) {}
  }

  static String _random(int length) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final random = Random.secure();
    return List.generate(length, (_) => chars[random.nextInt(chars.length)]).join();
  }

  static void _openBrowser(String url) {
    if (Platform.isWindows) {
      Process.run('rundll32', ['url.dll,FileProtocolHandler', url]);
    } else if (Platform.isMacOS) {
      Process.run('open', [url]);
    } else {
      Process.run('xdg-open', [url]);
    }
  }

  /// Abre el navegador, espera a que la persona autorice y guarda la sesión.
  Future<void> login() async {
    if (!configured) {
      throw const FormatException('Falta el Client ID de MAL en mal_client.dart.');
    }
    final verifier = _random(96); // MAL solo admite PKCE "plain".
    final state = _random(24);
    final done = Completer<String>();
    final servers = <HttpServer>[];

    void handle(HttpRequest request) {
      final query = request.uri.queryParameters;
      final ok = request.uri.path == '/callback' &&
          query['state'] == state &&
          query['code'] != null;
      request.response
        ..statusCode = ok ? 200 : 400
        ..headers.contentType = ContentType.html
        ..write(
          '<html><head><meta charset="utf-8"></head>'
          '<body style="font-family:sans-serif;background:#111;color:#eee;'
          'text-align:center;padding-top:80px">'
          '<h2>${ok ? 'Listo, ya puedes volver a Neko' : 'No se pudo conectar'}</h2>'
          '<p>${ok ? 'Puedes cerrar esta pestaña.' : 'Vuelve a intentarlo desde Neko.'}</p>'
          '</body></html>',
        );
      request.response.close();
      if (done.isCompleted) return;
      if (ok) {
        done.complete(query['code']!);
      } else if (request.uri.path == '/callback') {
        done.completeError(
          const HttpException('MAL no autorizó la conexión (o fue cancelada).'),
        );
      }
    }

    try {
      try {
        final v4 = await HttpServer.bind(InternetAddress.loopbackIPv4, _port);
        servers.add(v4);
        v4.listen(handle);
      } on SocketException {
        throw const HttpException(
          'El puerto 8765 está ocupado. Cierra otros programas e inténtalo de nuevo.',
        );
      }
      try {
        // "localhost" a veces resuelve a IPv6: se escucha en ambos.
        final v6 = await HttpServer.bind(InternetAddress.loopbackIPv6, _port);
        servers.add(v6);
        v6.listen(handle);
      } catch (_) {}

      _openBrowser(
        Uri.https('myanimelist.net', '/v1/oauth2/authorize', {
          'response_type': 'code',
          'client_id': malClientId,
          'code_challenge': verifier,
          'code_challenge_method': 'plain',
          'state': state,
          'redirect_uri': _redirect,
        }).toString(),
      );
      final code = await done.future.timeout(
        const Duration(minutes: 3),
        onTimeout: () => throw const HttpException(
          'Se acabó el tiempo esperando la autorización.',
        ),
      );
      await _token({
        'client_id': malClientId,
        'grant_type': 'authorization_code',
        'code': code,
        'code_verifier': verifier,
        'redirect_uri': _redirect,
      });
    } finally {
      for (final server in servers) {
        server.close(force: true);
      }
    }
    final me = await _get('/users/@me');
    name = '${me['name'] ?? ''}';
    await _save();
  }

  Future<void> _token(Map<String, String> form) async {
    final request = await _http
        .postUrl(Uri.parse('https://myanimelist.net/v1/oauth2/token'))
        .timeout(const Duration(seconds: 12));
    request.headers.contentType = ContentType(
      'application',
      'x-www-form-urlencoded',
      charset: 'utf-8',
    );
    request.write(Uri(queryParameters: form).query);
    final response = await request.close().timeout(const Duration(seconds: 15));
    final text = await response.transform(utf8.decoder).join();
    final data = jsonDecode(text);
    if (response.statusCode != 200 || data is! Map || data['access_token'] == null) {
      throw HttpException(
        'MAL rechazó la sesión (${response.statusCode}). Vuelve a conectar tu cuenta.',
      );
    }
    _access = data['access_token'] as String;
    _refresh = (data['refresh_token'] as String?) ?? _refresh;
    final seconds = (data['expires_in'] as num?)?.toInt() ?? 3600;
    _expires = DateTime.now().add(Duration(seconds: seconds));
    await _save();
  }

  Future<Map> _get(String path, [Map<String, String>? query]) async {
    final uri = Uri.parse('https://api.myanimelist.net/v2$path')
        .replace(queryParameters: query);
    return _getUri(uri);
  }

  Future<Map> _getUri(Uri uri) => _send('GET', uri);

  Future<Map> _send(
    String method,
    Uri uri, {
    Map<String, String>? form,
    bool retry = true,
  }) async {
    if (_refresh == null) throw const HttpException('Cuenta de MAL no conectada.');
    if (_access == null ||
        (_expires != null &&
            _expires!.isBefore(DateTime.now().add(const Duration(seconds: 60))))) {
      await _token({
        'client_id': malClientId,
        'grant_type': 'refresh_token',
        'refresh_token': _refresh!,
      });
    }
    final request = await _http.openUrl(method, uri).timeout(const Duration(seconds: 12));
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_access');
    if (form != null) {
      request.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
        charset: 'utf-8',
      );
      request.write(Uri(queryParameters: form).query);
    }
    final response = await request.close().timeout(const Duration(seconds: 15));
    final text = await response.transform(utf8.decoder).join();
    if (response.statusCode == 401 && retry) {
      _expires = DateTime.fromMillisecondsSinceEpoch(0);
      return _send(method, uri, form: form, retry: false);
    }
    if (response.statusCode != 200) {
      throw HttpException('MAL respondió ${response.statusCode}.');
    }
    final data = jsonDecode(text);
    return data is Map ? data : const {};
  }

  /// Estado de un anime en la lista del usuario: total de episodios de MAL,
  /// estado ('' si no está en su lista) y episodios vistos.
  Future<({int total, String status, int watched})> myStatus(int malId) async {
    final data = await _get('/anime/$malId', {'fields': 'num_episodes,my_list_status'});
    final mine = data['my_list_status'];
    return (
      total: (data['num_episodes'] as num?)?.toInt() ?? 0,
      status: mine is Map ? '${mine['status'] ?? ''}' : '',
      watched: mine is Map ? (mine['num_episodes_watched'] as num?)?.toInt() ?? 0 : 0,
    );
  }

  /// Marca [episodes] vistos y deja el anime en [status] dentro de la lista.
  Future<void> setProgress(int malId, int episodes, String status) => _send(
    'PUT',
    Uri.parse('https://api.myanimelist.net/v2/anime/$malId/my_list_status'),
    form: {'status': status, 'num_watched_episodes': '$episodes'},
  );

  /// Busca por título en MAL (para cuando AniList no conoce el ID de MAL).
  /// Devuelve pares (id, títulos conocidos).
  Future<List<({int id, List<String> titles})>> search(String title) async {
    if (title.trim().length < 3) return const [];
    final data = await _get('/anime', {
      'q': title.trim().length > 64 ? title.trim().substring(0, 64) : title.trim(),
      'limit': '6',
      'fields': 'alternative_titles',
    });
    final results = <({int id, List<String> titles})>[];
    for (final item in (data['data'] is List ? data['data'] as List : const [])) {
      if (item is! Map || item['node'] is! Map) continue;
      final node = item['node'] as Map;
      final alt = node['alternative_titles'];
      results.add((
        id: (node['id'] as num?)?.toInt() ?? 0,
        titles: [
          '${node['title'] ?? ''}',
          if (alt is Map && alt['en'] is String) alt['en'] as String,
          if (alt is Map && alt['synonyms'] is List)
            for (final s in alt['synonyms'] as List) '$s',
        ],
      ));
    }
    return results;
  }

  /// Lista del usuario filtrada por [status]: watching, completed, on_hold,
  /// dropped o plan_to_watch.
  Future<List<MalEntry>> list(String status) async {
    final entries = <MalEntry>[];
    Uri? next = Uri.https('api.myanimelist.net', '/v2/users/@me/animelist', {
      'status': status,
      'limit': '100',
      'sort': 'list_updated_at',
      'fields': 'list_status,num_episodes',
    });
    for (var page = 0; next != null && page < 10; page++) {
      final data = await _getUri(next);
      for (final item in (data['data'] is List ? data['data'] as List : const [])) {
        if (item is! Map || item['node'] is! Map) continue;
        final node = item['node'] as Map;
        final state = item['list_status'] is Map ? item['list_status'] as Map : const {};
        final picture = node['main_picture'] is Map
            ? '${(node['main_picture'] as Map)['medium'] ?? ''}'
            : '';
        entries.add(
          MalEntry(
            id: (node['id'] as num?)?.toInt() ?? 0,
            title: '${node['title'] ?? ''}',
            status: '${state['status'] ?? status}',
            picture: picture,
            watched: (state['num_episodes_watched'] as num?)?.toInt() ?? 0,
            total: (node['num_episodes'] as num?)?.toInt() ?? 0,
            score: (state['score'] as num?)?.toInt() ?? 0,
          ),
        );
      }
      final paging = data['paging'];
      final url = paging is Map ? paging['next'] : null;
      next = url is String && url.isNotEmpty ? Uri.tryParse(url) : null;
    }
    return entries;
  }
}
