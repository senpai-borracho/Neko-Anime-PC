import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neko_player_pc/anix_engine.dart';
import 'package:neko_player_pc/anix_page.dart';

class SourceEngine extends AnixEngine {
  final searches = <String>[];
  @override
  Future<dynamic> call(
    String op, {
    String? plugin,
    Map<String, dynamic> args = const {},
  }) async {
    if (op == 'list')
      return [
        {
          'id': 'one',
          'name': 'Fuente Uno',
          'version': '1',
          'supported': true,
          'languages': {
            'sub': ['es'],
          },
        },
        {
          'id': 'two',
          'name': 'Fuente Dos',
          'version': '2',
          'supported': true,
          'languages': {
            'sub': ['es'],
            'dub': ['es'],
          },
        },
      ];
    if (op == 'search') {
      searches.add(plugin!);
      return [
        {'id': 'naruto', 'title': 'Naruto de $plugin', 'subOrDub': 'sub'},
      ];
    }
    if (op == 'episodes')
      return [
        {'id': 'ep1', 'number': 1, 'title': 'Inicio'},
      ];
    if (op == 'settings')
      return {
        'episodeServers': ['default'],
      };
    throw StateError('Unexpected call: $op');
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  testWidgets(
    'extensions open separately; searches never combine providers; back preserves results',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final engine = SourceEngine();
      await tester.pumpWidget(MaterialApp(home: AnixPage(engine: engine)));
      await tester.pumpAndSettle();
      expect(find.text('Fuente Uno'), findsOneWidget);
      expect(find.text('Fuente Dos'), findsOneWidget);
      expect(find.byType(GridView), findsNothing);
      expect(find.byType(FilterChip), findsNothing);
      final file = tester.getRect(
        find.widgetWithText(FilledButton, 'Importar archivo'),
      );
      final url = tester.getRect(
        find.widgetWithText(OutlinedButton, 'Agregar por URL'),
      );
      expect(file.top, url.top);
      expect(file.right, lessThan(url.left));
      await tester.tap(find.text('Fuente Uno'));
      await tester.pumpAndSettle();
      expect(find.text('Buscar en Fuente Uno'), findsOneWidget);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
        isNull,
      );
      await tester.enterText(find.byType(TextField), 'Naruto');
      await tester.tap(find.text('Buscar'));
      await tester.pumpAndSettle();
      expect(engine.searches, ['one']);
      expect(find.text('Naruto de one'), findsOneWidget);
      expect(find.text('Naruto de two'), findsNothing);
      await tester.tap(find.text('Naruto de one'));
      await tester.pumpAndSettle();
      expect(find.text('Episodio 1'), findsOneWidget);
      await tester.tap(find.text('Resultados de Fuente Uno'));
      await tester.pumpAndSettle();
      expect(find.text('Naruto de one'), findsOneWidget);
      await tester.tap(find.text('Todas las extensiones'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fuente Dos'));
      await tester.pumpAndSettle();
      expect(find.text('Naruto de one'), findsNothing);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
        isNotNull,
      );
      await tester.enterText(find.byType(TextField), 'Naruto');
      await tester.tap(find.text('Buscar'));
      await tester.pumpAndSettle();
      expect(engine.searches, ['one', 'two']);
      expect(find.text('Naruto de two'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
