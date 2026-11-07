import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neko_player_pc/anix_engine.dart';
import 'package:neko_player_pc/anix_page.dart';

class LanguageEngine extends AnixEngine {
  Map<String, dynamic>? searchOptions;
  @override
  Future<dynamic> call(
    String op, {
    String? plugin,
    Map<String, dynamic> args = const {},
  }) async {
    if (op == 'list')
      return [
        {
          'id': 'spanish',
          'name': 'Fuente española',
          'supported': true,
          'languages': {
            'sub': ['es'],
          },
        },
        {
          'id': 'english',
          'name': 'Fuente inglesa',
          'supported': true,
          'languages': {
            'sub': ['en'],
            'dub': ['en'],
          },
        },
      ];
    if (op == 'search') {
      searchOptions = Map<String, dynamic>.from(args['options'] as Map);
      return [];
    }
    if (op == 'server')
      return {
        'videoSources': [
          {
            'url': 'https://example.org/video.mp4',
            'language': 'en',
            'subtitles': [
              {'url': 'https://example.org/fr.vtt', 'lang': 'fr'},
              {'url': 'javascript:invalid', 'lang': 'es'},
            ],
          },
        ],
      };
    throw StateError(op);
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  testWidgets(
    'language declarations are labelled and warning allows entry without a search filter',
    (tester) async {
      final engine = LanguageEngine();
      await tester.pumpWidget(MaterialApp(home: AnixPage(engine: engine)));
      await tester.pumpAndSettle();
      expect(find.text('Extensión con contenido en español'), findsOneWidget);
      expect(
        find.text('Esta extensión no declara contenido español'),
        findsOneWidget,
      );
      await tester.tap(find.text('Fuente española'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(find.text('Todas las extensiones'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fuente inglesa'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Esta extensión no declara contenido español. Si entras y no encuentras animes subtitulados en español, no es responsabilidad de Neko Anime.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.text('Fuente española'), findsOneWidget);
      await tester.tap(find.text('Fuente inglesa'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Entrar'));
      await tester.pumpAndSettle();
      expect(find.text('Buscar en Fuente inglesa'), findsOneWidget);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
        isNotNull,
      );
      await tester.enterText(find.byType(TextField), 'Naruto');
      await tester.tap(find.text('Buscar'));
      await tester.pumpAndSettle();
      expect(engine.searchOptions!.containsKey('language'), false);
      expect(tester.takeException(), isNull);
    },
  );
  test('Anix keeps videos and subtitles in other languages', () async {
    final page = AnixPlayerPage(
      engine: LanguageEngine(),
      plugin: 'english',
      episode: const {'number': 1},
      servers: const ['default'],
    );
    final stream = await page.resolve('default');
    expect(stream.url, 'https://example.org/video.mp4');
    expect(stream.subtitles.single['lang'], 'fr');
  });
}
