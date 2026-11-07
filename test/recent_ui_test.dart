import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neko_player_pc/catalog.dart';
import 'package:neko_player_pc/main.dart';

class OfflineCatalog extends ProviderClient {
  @override
  Future<PageResult> catalog({
    int page = 1,
    String query = '',
    void Function(PageResult)? onPartial,
  }) async => const PageResult([], false);
  @override
  Future<String> fetch(
    String url, {
    String referer = '',
    Map<String, String>? form,
    bool cached = true,
  }) async {
    if (url == 'https://tioanime.com/') {
      return '<a href="/ver/prueba-2"><h3>Prueba 2</h3></a>';
    }
    throw const FormatException('offline test');
  }

  @override
  Future<Detail> detail(Anime card) async => Detail(
    card,
    'Sinopsis de prueba',
    const [Episode('2', 'https://tioanime.com/ver/prueba-2')],
  );
}

void main() {
  testWidgets(
    'General releases work with an empty personal list and open the existing detail page',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync('neko_recent_ui_');
      final library = Library(
        storageFile: File('${directory.path}/library.json'),
      );
      final api = OfflineCatalog();
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(api: api, library: library),
        ),
      );
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(library.savedAnime, isEmpty);
      await tester.tap(find.byTooltip('Nuevos episodios'));
      await tester.pumpAndSettle();
      expect(find.text('Prueba'), findsOneWidget);
      expect(find.text('Episodio 2 · TioAnime'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'Release listing layout');
      await tester.ensureVisible(find.text('Prueba'));
      await tester.tap(find.text('Prueba'));
      await tester.pumpAndSettle();
      expect(find.text('Sinopsis de prueba'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await library.flushed;
      directory.deleteSync(recursive: true);
    },
  );
}
