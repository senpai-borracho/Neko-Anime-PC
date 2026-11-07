import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neko_player_pc/main.dart';
import 'package:neko_player_pc/catalog.dart';
import 'package:neko_player_pc/startup_overlay.dart';

class StartupApi extends ProviderClient {
  final pending = Completer<PageResult>();
  @override
  Future<PageResult> catalog({int page = 1, String query = '', void Function(PageResult)? onPartial}) => pending.future;
  @override
  Future<String> fetch(String url, {String referer = '', Map<String, String>? form, bool cached = true}) async => '';
}
class StartupLibrary extends Library {
  @override
  Future<void> load() async {}
  @override
  void save() {}
}

void main() {
  for (final fail in [false, true]) {
    testWidgets('Welcome waits for real initial catalog; failure=$fail', (tester) async {
      final api = StartupApi();
      await tester.pumpWidget(NekoApp(home: HomePage(api: api, library: StartupLibrary())));
      await tester.pump();
      expect(tester.widget<StartupOverlay>(find.byType(StartupOverlay)).loading, isTrue);
      expect(find.bySemanticsLabel('Bienvenido a Neko Anime'), findsOneWidget);
      if (fail) { api.pending.completeError(Exception('Offline')); }
      else { api.pending.complete(const PageResult([], false)); }
      await tester.pumpAndSettle();
      expect(tester.widget<StartupOverlay>(find.byType(StartupOverlay)).loading, isFalse);
      if (fail) expect(find.text('El catálogo no está disponible'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
