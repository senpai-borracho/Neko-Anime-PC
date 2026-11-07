import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neko_player_pc/anix_engine.dart';
import 'package:neko_player_pc/anix_page.dart';

class RemoteFixture extends AnixEngine {
  bool downloaded = false;
  @override
  Future<dynamic> call(
    String op, {
    String? plugin,
    Map<String, dynamic> args = const {},
  }) async => [
    {
      'id': 'remote',
      'name': 'Remota',
      'version': '1',
      'supported': downloaded,
      'downloadable': !downloaded,
      'manifestURI': 'https://example.org/manifest.json',
      'languages': {
        'sub': ['es'],
      },
    },
  ];
  @override
  Future<void> downloadPlugin(String id) async {
    expect(id, 'remote');
    downloaded = true;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  testWidgets(
    'download action changes pending entry into a separate runnable extension',
    (tester) async {
      final engine = RemoteFixture();
      await tester.pumpWidget(MaterialApp(home: AnixPage(engine: engine)));
      await tester.pumpAndSettle();
      expect(find.textContaining('Requiere descargar'), findsOneWidget);
      await tester.tap(find.text('Descargar'));
      await tester.pumpAndSettle();
      expect(engine.downloaded, true);
      expect(find.textContaining('Requiere descargar'), findsNothing);
      expect(find.text('Descargar'), findsNothing);
      await tester.tap(find.text('Remota'));
      await tester.pumpAndSettle();
      expect(find.text('Buscar en Remota'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
