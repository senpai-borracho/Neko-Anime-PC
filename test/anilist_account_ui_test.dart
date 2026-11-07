
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neko_player_pc/anilist_account.dart';
import 'package:neko_player_pc/anilist_account_tile.dart';

class FakeAccount extends AniListAccount {
  bool signedIn = false;
  @override
  bool get connected => signedIn;
  @override
  Future<void> load() async {}
  @override
  Future<void> login() async {
    signedIn = true;
    name = 'Senpai';
  }

  @override
  Future<void> logout() async {
    signedIn = false;
  }
}

void main() {
  testWidgets('user can connect, view account identity and disconnect', (
    tester,
  ) async {
    final account = FakeAccount();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AniListAccountTile(account: account, onSearch: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Conectar con AniList'), findsOneWidget);
    await tester.tap(find.text('Conectar'));
    await tester.pumpAndSettle();
    expect(find.text('Senpai'), findsOneWidget);
    expect(find.text('Ver mi lista'), findsOneWidget);
    await tester.tap(find.text('Desconectar'));
    await tester.pumpAndSettle();
    expect(find.text('Conectar con AniList'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    account.close();
  });
}
