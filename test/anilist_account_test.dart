import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neko_player_pc/anilist_account.dart';

void main() {
  late Directory temp;
  late HttpServer api;
  late AniListAccount account;
  var reject = false;
  var badViewer = false;
  var wrongStateRejected = false;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('neko-anilist-');
    api = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    reject = false;
    badViewer = false;
    wrongStateRejected = false;
    api.listen((req) async {
      expect(req.headers.value('authorization'), 'Bearer fixture-token');
      final body = jsonDecode(await utf8.decoder.bind(req).join()) as Map;
      req.response.headers.contentType = ContentType.json;
      if (reject) {
        req.response.statusCode = 401;
        req.response.write('{}');
      } else if ('${body['query']}'.contains('Viewer')) {
        req.response.write(
          jsonEncode({
            'data': {
              'Viewer': badViewer ? null : {'id': 42, 'name': 'Senpai'},
            },
          }),
        );
      } else {
        expect(body['variables']['user'], 42);
        final entry = {
          'id': 5,
          'status': 'CURRENT',
          'progress': 3,
          'media': {
            'title': {'userPreferred': 'Test anime'},
            'episodes': 12,
          },
        };
        req.response.write(
          jsonEncode({
            'data': {
              'MediaListCollection': {
                'lists': [
                  {
                    'entries': [entry],
                  },
                  {
                    'entries': [entry],
                  },
                ],
              },
            },
          }),
        );
      }
      await req.response.close();
    });
    account = AniListAccount(
      sessionFile: File('${temp.path}/anilist.json'),
      endpoint: Uri.parse('http://127.0.0.1:${api.port}'),
      callbackPort: 0,
      openBrowser: (uri) async {
        expect(uri.host, 'anilist.co');
        expect(uri.queryParameters['client_id'], '56003');
        expect(uri.queryParameters['response_type'], 'token');
        final redirect = Uri.parse(uri.queryParameters['redirect_uri']!);
        final client = HttpClient();
        try {
          final page = await client.getUrl(redirect);
          final response = await page.close();
          expect(response.headers.value('cache-control'), 'no-store');
          expect(
            await utf8.decoder.bind(response).join(),
            contains('location.hash'),
          );
          Future<int> post(String state) async {
            final req = await client.postUrl(redirect.replace(path: '/token'));
            req.headers.contentType = ContentType(
              'application',
              'x-www-form-urlencoded',
            );
            req.headers.set('Origin', 'http://127.0.0.1:${redirect.port}');
            req.write(
              Uri(
                queryParameters: {
                  'state': state,
                  'access_token': 'fixture-token',
                  'token_type': 'Bearer',
                  'expires_in': '3600',
                },
              ).query,
            );
            final res = await req.close();
            await res.drain<void>();
            return res.statusCode;
          }

          wrongStateRejected = await post('wrong-state') == 400;
          expect(await post(uri.queryParameters['state']!), 200);
        } finally {
          client.close(force: true);
        }
      },
    );
  });
  tearDown(() async {
    account.close();
    await api.close(force: true);
    await temp.delete(recursive: true);
  });

  test(
    'OAuth validates state, verifies viewer and restores a separate session',
    () async {
      await account.login();
      expect(wrongStateRejected, isTrue);
      expect(account.connected, isTrue);
      expect(account.name, 'Senpai');
      final restored = AniListAccount(sessionFile: account.sessionFile);
      await restored.load();
      expect(restored.connected, isTrue);
      expect(restored.userId, 42);
      await restored.logout();
      expect(await account.sessionFile.exists(), isFalse);
      restored.close();
    },
  );

  test('lists use the signed-in user and deduplicate custom groups', () async {
    await account.login();
    final entries = await account.animeList();
    expect(entries, hasLength(1));
    expect(entries.single['progress'], 3);
  });

  test('revoked session is removed and prompts reconnection', () async {
    await account.login();
    reject = true;
    await expectLater(account.animeList(), throwsA(isA<HttpException>()));
    expect(account.connected, isFalse);
    expect(await account.sessionFile.exists(), isFalse);
  });

  test('invalid viewer never persists a successful session', () async {
    badViewer = true;
    await expectLater(account.login(), throwsA(isA<HttpException>()));
    expect(account.connected, isFalse);
    expect(await account.sessionFile.exists(), isFalse);
  });

  test('expired sessions are discarded', () async {
    await account.sessionFile.writeAsString(
      jsonEncode({
        'token': 'expired',
        'expires': 1,
        'name': 'Old',
        'userId': 42,
      }),
    );
    await account.load();
    expect(account.connected, isFalse);
    expect(await account.sessionFile.exists(), isFalse);
  });
}
