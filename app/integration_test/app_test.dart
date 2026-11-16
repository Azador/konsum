// Integrationstests auf einem echten Android-Gerät (Emulator), ohne Netz:
// Die App läuft mit einem Speicher im Arbeitsspeicher und ohne Matrix.
//
// Nur über tool/integration_test.sh starten. Es wählt den Emulator
// „konsum_pixel7a“, denn ein Debug-Build auf einem Telefon mit der
// installierten Release-App ersetzt diese samt ihren Daten.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:konsum/main.dart';
import 'package:konsum/state/app_state.dart';
import 'package:konsum/storage/store.dart';
import 'package:konsum_core/konsum_core.dart';

import '../test/support/sample_data.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;

  setUpAll(() => initializeDateFormatting('de'));

  Future<AppState> start(WidgetTester tester) async {
    final state = await AppState.load(MemoryStore(), random: math.Random(1));
    await tester.pumpWidget(KonsumApp(state: state));
    await tester.pumpAndSettle();
    return state;
  }

  Finder field(String label) => find.widgetWithText(TextField, label);

  /// Text in einem Listeneintrag (nicht in der Summenzeile).
  Finder inTile(String text) => find.descendant(
    of: find.byType(CheckboxListTile),
    matching: find.textContaining(text),
  );

  Future<void> addViaInput(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
  }

  Future<void> checkAndClear(WidgetTester tester) async {
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Abgehakte entfernen'));
    await tester.pumpAndSettle();
  }

  testWidgets('Einkauf mit Preis, danach Schätzung und bestätigter Preis', (
    tester,
  ) async {
    final state = await start(tester);
    final group = state.currentGroup!.group;

    // Laden wählen, damit Preise und Käufe ihm zugeordnet werden.
    final shop = group.createShop('Famila');
    state.currentGroup!.apply(shop.changes);
    state.selectShop(state.currentGroup!, shop.id);
    await tester.pumpAndSettle();

    await addViaInput(tester, '2 Kochschinken');
    expect(find.text('Kochschinken'), findsOneWidget);
    expect(find.text('2 Packungen'), findsOneWidget);

    // Preis je Packung eintragen.
    await tester.tap(find.byTooltip('Bearbeiten'));
    await tester.pumpAndSettle();
    await tester.enterText(field('€/Packung'), '2,59');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Speichern'));
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(inTile('5,18'), findsOneWidget);
    expect(inTile('2,59\u00A0€/Pkg'), findsOneWidget);

    await checkAndClear(tester);
    expect(find.text('Die Liste ist leer.'), findsOneWidget);
    final price = group.priceHistory().single;
    expect(price.cents, 518);
    expect(price.shopId, shop.id);
    expect(group.purchases.single.shopId, shop.id);

    // Wieder auf die Liste: Der letzte Preis gilt als Schätzung.
    await addViaInput(tester, '3 Kochschinken');
    expect(inTile('≈'), findsOneWidget);
    expect(inTile('7,77'), findsOneWidget);

    // Unverändert abgehakt: Der Preis ist bestätigt und kommt in die
    // Historie.
    await checkAndClear(tester);
    final history = group.priceHistory();
    expect(history, hasLength(2));
    expect(history.first.cents, 777);
    expect(history.first.quantity, 3);
    await tester.pump(const Duration(seconds: 1)); // verzögertes Speichern
  });

  testWidgets('Seiten mit Beispieldaten ohne Überlauf', (tester) async {
    final state = await AppState.load(MemoryStore(), random: math.Random(1));
    seedSampleData(state);
    await tester.pumpWidget(KonsumApp(state: state));
    await tester.pumpAndSettle();

    expectSingleLine(tester, find.text(Sample.ham));
    expectSingleLine(
      tester,
      find.descendant(
        of: find.byType(CheckboxListTile),
        matching: find.textContaining('€'),
      ),
    );

    // Abhaken und wieder abwählen, Eintragsblatt öffnen und schließen.
    final water = find.ancestor(
      of: find.text(Sample.water),
      matching: find.byType(CheckboxListTile),
    );
    await tester.ensureVisible(water);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: water, matching: find.byTooltip('Bearbeiten')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Speichern', skipOffstage: false), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    for (final page in ['Artikel', 'Käufe', 'Läden', 'Kategorien']) {
      await tester.tap(find.byTooltip('Navigationsmenü öffnen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(page));
      await tester.pumpAndSettle();
      if (page == 'Artikel') {
        await tester.tap(find.text(Sample.milk));
        await tester.pumpAndSettle();
        expect(find.textContaining('Inhalt je'), findsOneWidget);
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
    }
    expect(state.currentGroup!.group.entries(state.currentListId!), isNotEmpty);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Lose Ware: Preis je kg', (tester) async {
    final state = await start(tester);
    await addViaInput(tester, '500 g Hackfleisch');
    await tester.tap(find.byTooltip('Bearbeiten'));
    await tester.pumpAndSettle();
    await tester.enterText(field('€/kg'), '8,99');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Speichern'));
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(inTile('4,50'), findsOneWidget);
    expect(inTile('8,99\u00A0€/kg'), findsOneWidget);
    final e = state.currentGroup!.group.entries(state.currentListId!).single;
    expect(e.unit, Units.gram);
    await tester.pump(const Duration(seconds: 1));
  });
}
