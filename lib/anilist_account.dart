import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

const anilistClientId = '56003';

/// Account requests are separate from the public metadata client.
class AniListAccount {
  final String clientId;
  final File sessionFile;
  final Uri endpoint;
  final int callbackPort;
  final Future<void> Function(Uri) openBrowser;
  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12);
  String? _token;
  DateTime? _expires;
  String name = '';
  int userId = 0;
  HttpServer? _callback;
  Completer<String>? _login;
  bool _closed = false;

  AniListAccount({
    this.clientId = anilistClientId,
    File? sessionFile,
    Uri? endpoint,
    this.callbackPort = 8766,
    Future<void> Function(Uri)? openBrowser,
  }) : sessionFile =
           sessionFile ??
           File(
             '${Platform.environment['LOCALAPPDATA'] ?? Directory.current.path}/NekoPlayerPC/anilist.json',
           ),
       endpoint = endpoint ?? Uri.parse('https://graphql.anilist.co'),
       openBrowser = openBrowser ?? _openBrowser;

  bool get configured => RegExp(r'^\d+$').hasMatch(clientId);
  bool get connected =>
      _token != null && (_expires == null || _expires!.isAfter(DateTime.now()));

  static Future<void> _openBrowser(Uri uri) async {
    final result = Platform.isWindows
        ? await Process.run('rundll32', ['url.dll,FileProtocolHandler', '$uri'])
        : await Process.run(Platform.isMacOS ? 'open' : 'xdg-open', ['$uri']);
    if (result.exitCode != 0) {
      throw const HttpException('No se pudo abrir el navegador.');
    }
  }

  Future<void> load() async {
    if (!await sessionFile.exists()) return;
    try {
      final data = jsonDecode(await sessionFile.readAsString()) as Map;
      if (_closed) return;
      final expiry = data['expires'];
      _expires = expiry is int
          ? DateTime.fromMillisecondsSinceEpoch(expiry)
          : null;
      _token = data['token'] as String?;
      name = data['name'] as String? ?? '';
      userId = (data['userId'] as num?)?.toInt() ?? 0;
      if (!connected) await logout();
    } on FormatException {
      await logout();
    } on TypeError {
      await logout();
    }
  }

  Future<void> logout() async {
    _token = null;
    _expires = null;
    name = '';
    userId = 0;
    if (await sessionFile.exists()) await sessionFile.delete();
  }

  void cancelLogin() {
    final login = _login;
    if (login != null && !login.isCompleted) {
      login.completeError(
        const HttpException('Conexión con AniList cancelada.'),
      );
    }
  }

  void close() {
    _closed = true;
    cancelLogin();
    _callback?.close(force: true);
    _http.close(force: true);
  }

  Future<void> login() async {
    if (!configured) {
      throw const FormatException('Falta configurar el Client ID de AniList.');
    }
    if (_login != null) {
      throw const HttpException('Ya hay una conexión en curso.');
    }
    final random = Random.secure();
    final state = base64Url.encode(
      List.generate(32, (_) => random.nextInt(256)),
    );
    final done = Completer<String>();
    _login = done;
    // Attach the timeout/error handler before opening the browser.
    final result = done.future.timeout(
      const Duration(minutes: 3),
      onTimeout: () => throw const HttpException(
        'Se agotó el tiempo para conectar AniList.',
      ),
    );
    // Consume errors even if binding or opening the browser fails first.
    unawaited(result.then<void>((_) {}, onError: (Object _, StackTrace _) {}));
    try {
      final server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        callbackPort,
      );
      _callback = server;
      server.listen((request) async {
        request.response.headers.set('Cache-Control', 'no-store');
        request.response.headers.set('Referrer-Policy', 'no-referrer');
        if (request.method == 'GET' && request.uri.path == '/callback') {
          request.response.headers.contentType = ContentType.html;
          request.response.headers.set(
            'Content-Security-Policy',
            "default-src 'none'; script-src 'unsafe-inline'; connect-src 'self'",
          );
          request.response.write('''<!doctype html><meta charset="utf-8">
<title>Conectar AniList con Neko</title><p id="status">Conectando con Neko…</p>
<script>
const data = new URLSearchParams(location.hash.slice(1));
history.replaceState(null, '', '/callback');
fetch('/token', {method:'POST', headers:{'Content-Type':'application/x-www-form-urlencoded'}, body:data.toString()})
 .then(r => {document.getElementById('status').textContent = r.ok ? 'Autorización recibida. Vuelve a Neko para comprobar la conexión.' : 'No se pudo conectar. Vuelve a Neko e inténtalo de nuevo.';})
 .catch(() => {document.getElementById('status').textContent = 'Vuelve a Neko para reintentar.';});
</script>''');
        } else if (request.method == 'POST' && request.uri.path == '/token') {
          try {
            final body = await utf8.decoder
                .bind(request)
                .join()
                .timeout(const Duration(seconds: 5));
            if (body.length > 16384) throw const FormatException();
            final data = Uri.splitQueryString(body);
            final origin = request.headers.value('origin');
            final validOrigin = origin == 'http://127.0.0.1:${server.port}';
            // AniList no devuelve "state" en este flujo: si viene, debe coincidir.
            final badState = data.containsKey('state') && data['state'] != state;
            if (!validOrigin || badState || done.isCompleted) {
              request.response.statusCode = 400;
            } else if (data['error'] != null) {
              done.completeError(
                const HttpException('AniList no autorizó la conexión.'),
              );
              request.response.statusCode = 400;
            } else if (data['access_token']?.isNotEmpty == true &&
                data['token_type']?.toLowerCase() == 'bearer') {
              final seconds =
                  int.tryParse(data['expires_in'] ?? '') ?? 31536000;
              _expires = DateTime.now().add(Duration(seconds: seconds));
              done.complete(data['access_token']!);
              request.response.write('OK');
            } else {
              request.response.statusCode = 400;
            }
          } catch (_) {
            request.response.statusCode = 400;
          }
        } else {
          request.response.statusCode = 404;
        }
        await request.response.close();
      });
      await openBrowser(
        // AniList (implicit grant) solo acepta client_id y response_type; usa la
        // Redirect URL registrada en la app. Si se envía redirect_uri responde
        // "unsupported_grant_type".
        Uri.https('anilist.co', '/api/v2/oauth/authorize', {
          'client_id': clientId,
          'response_type': 'token',
        }),
      );
      _token = await result;
      final data = await request('query { Viewer { id name } }');
      final viewer = data['Viewer'];
      if (viewer is! Map || viewer['id'] is! num || viewer['name'] is! String) {
        throw const HttpException('AniList no devolvió el perfil de usuario.');
      }
      if (_closed) throw const HttpException('La conexión se cerró.');
      userId = (viewer['id'] as num).toInt();
      name = viewer['name'] as String;
      await sessionFile.parent.create(recursive: true);
      await sessionFile.writeAsString(
        jsonEncode({
          'token': _token,
          'expires': _expires?.millisecondsSinceEpoch,
          'name': name,
          'userId': userId,
        }),
        flush: true,
      );
    } catch (_) {
      await logout();
      rethrow;
    } finally {
      if (!done.isCompleted) done.complete('');
      await _callback?.close(force: true);
      _callback = null;
      _login = null;
    }
  }

  Future<Map> request(
    String query, [
    Map<String, Object?> variables = const {},
  ]) async {
    if (!connected) {
      throw const HttpException('Vuelve a conectar tu cuenta de AniList.');
    }
    final req = await _http
        .postUrl(endpoint)
        .timeout(const Duration(seconds: 12));
    req.headers.contentType = ContentType.json;
    req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_token');
    req.write(jsonEncode({'query': query, 'variables': variables}));
    final response = await req.close().timeout(const Duration(seconds: 15));
    final body = await utf8.decoder
        .bind(response)
        .join()
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 401) {
      await logout();
      throw const HttpException(
        'La sesión de AniList venció o fue revocada. Vuelve a conectar.',
      );
    }
    if (response.statusCode != 200) {
      throw HttpException('AniList respondió ${response.statusCode}.');
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map ||
        decoded['errors'] != null ||
        decoded['data'] is! Map) {
      throw const HttpException('No se pudo obtener tu cuenta de AniList.');
    }
    return decoded['data'] as Map;
  }

  Future<List<Map>> animeList() async {
    final data = await request(
      r'''query($user: Int!) {
      MediaListCollection(userId: $user, type: ANIME) {
        lists { entries { id status progress score media {
          id episodes title { userPreferred } coverImage { medium }
        } } }
      }
    }''',
      {'user': userId},
    );
    final collection = data['MediaListCollection'];
    final groups = collection is Map ? collection['lists'] : null;
    final entries = <int, Map>{};
    if (groups is List) {
      for (final group in groups.whereType<Map>()) {
        final list = group['entries'];
        if (list is List) {
          for (final entry in list.whereType<Map>()) {
            if (entry['id'] is num) {
              entries[(entry['id'] as num).toInt()] = entry;
            }
          }
        }
      }
    }
    return entries.values.toList();
  }
}
