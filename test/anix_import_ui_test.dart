import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:neko_player_pc/anix_engine.dart';
import 'package:neko_player_pc/anix_page.dart';

class SelectedManifest extends FileSelectorPlatform {
  @override
  Future<XFile?> openFile({List<XTypeGroup>? acceptedTypeGroups, String? initialDirectory, String? confirmButtonText}) async => XFile(Platform.environment['ANIX_TEST_MANIFEST'] ?? 'assets/extensions/anix-extensions.json');
}
void main() {
  testWidgets('import button loads the user manifest into the real engine and displays all entries', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final previous = FileSelectorPlatform.instance;
    FileSelectorPlatform.instance = SelectedManifest();
    final dir = await tester.runAsync(() => Directory.systemTemp.createTemp('neko-import-ui-'));
    final engine = AnixEngine(manifestFile: File('${dir!.path}/manifest.json'));
    addTearDown(() async { FileSelectorPlatform.instance = previous; await engine.dispose(); await dir.delete(recursive:true); });
    await tester.runAsync(() => engine.call('list'));
    await tester.pumpWidget(MaterialApp(home: AnixPage(engine: engine)));
    Future<void> waitFor(String text) async {
      for(var i=0;i<50;i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump();
        if(find.text(text).evaluate().isNotEmpty) return;
      }
      fail('Missing UI text: $text');
    }
    await waitFor('Manifiesto incluido · 38 extensiones');
    for(var i=0;i<3;i++) {
      await tester.runAsync(() async { await tester.tap(find.text('Importar archivo')); await Future<void>.delayed(const Duration(milliseconds: 500)); });
      await waitFor('Manifiesto importado · 38 extensiones');
      expect(find.textContaining('Bad state'), findsNothing);
      final list = await tester.runAsync(() => engine.call('list')) as List;
      expect(list.length,38);
      expect(list.any((p)=>p['id']=='miruro'),true);
    }
    expect(find.text('Miruro'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.runAsync(engine.dispose);
    await tester.pumpWidget(const SizedBox());
  });
}
