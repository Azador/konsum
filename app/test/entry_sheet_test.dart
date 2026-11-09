import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:konsum/main.dart';
import 'package:konsum/state/app_state.dart';
import 'package:konsum/storage/store.dart';
import 'package:konsum_core/konsum_core.dart';

void main() {
  setUpAll(() => initializeDateFormatting('de'));

  Future<(AppState, String, String)> setUp(WidgetTester tester) async {
    final state = (await tester.runAsync(
      () => AppState.load(MemoryStore(), random: math.Random(1)),
    ))!;
    final session = state.currentGroup!;
    final article = session.group.createArticle('Hack');
    session.apply(article.changes);
    await tester.pumpWidget(KonsumApp(state: state));
    return (state, state.currentListId!, article.id);
  }

  Finder field(String label) => find.widgetWithText(TextField, label);

  String text(WidgetTester tester, String label) =>
      tester.widget<TextField>(field(label)).controller!.text;

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Bearbeiten'));
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  testWidgets('Ohne Menge keine Mengenzeile', (tester) async {
    final (state, listId, hack) = await setUp(tester);
    final session = state.currentGroup!;
    session.apply(session.group.addToList(listId, hack, unit: Units.gram));
    await tester.pump();
    expect(find.text('g'), findsNothing);

    session.apply(session.group.updateEntry(listId, hack, {'quantity': 200}));
    await tester.pump();
    expect(find.text('200 g'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('Preis und Kilopreis rechnen sich gegenseitig um', (
    tester,
  ) async {
    final (state, listId, hack) = await setUp(tester);
    final session = state.currentGroup!;
    session.apply(
      session.group.addToList(listId, hack, quantity: 100, unit: Units.gram),
    );
    await tester.pump();
    await openSheet(tester);

    // Kilopreis eingeben → Preis für 100 g.
    await tester.enterText(field('€/kg'), '9,90');
    expect(text(tester, 'Preis (€)'), '0,99');

    // Menge ändern → Preis über den Kilopreis.
    await tester.enterText(field('Menge'), '200');
    expect(text(tester, 'Preis (€)'), '1,98');

    // Preis ändern → Kilopreis.
    await tester.enterText(field('Preis (€)'), '2,50');
    expect(text(tester, '€/kg'), '12,50');

    // Kilopreis ändern → Preis.
    await tester.enterText(field('€/kg'), '10');
    expect(text(tester, 'Preis (€)'), '2,00');

    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    final e = session.group.entries(listId).single;
    expect(e.quantity, 200);
    expect(e.basePrice, 1000);
    expect(e.totalCents, 200);
    expect(find.text('2,00 €'), findsOneWidget);
    expect(find.text('10,00 €/kg'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('Packungsgröße nachträglich: Preis bleibt beim Tippen', (
    tester,
  ) async {
    final (state, listId, hack) = await setUp(tester);
    final session = state.currentGroup!;
    session.apply(session.group.addToList(listId, hack, quantity: 1));
    session.apply(
      session.group.updateEntry(listId, hack, {'price': 299, 'basePrice': 299}),
    );
    await tester.pump();
    await openSheet(tester);
    expect(text(tester, 'Preis (€)'), '2,99');

    // Zeichen für Zeichen, wie auf der Tastatur.
    for (final typed in ['5', '50', '500']) {
      await tester.enterText(field('Inhalt je Packung'), typed);
      await tester.pump();
      expect(text(tester, 'Preis (€)'), '2,99');
    }
    expect(text(tester, '€/kg'), '5,98');

    // Inhaltseinheit ändern: Preis bleibt, Kilopreis folgt.
    await tester.tap(find.text('g').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('kg').last);
    await tester.pumpAndSettle();
    expect(text(tester, 'Preis (€)'), '2,99');
    expect(text(tester, '€/kg'), '0,01');

    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    final e = session.group.entries(listId).single;
    expect(e.packSize, 500);
    expect(e.packUnit, Units.kilogram);
    expect(e.totalCents, 299);
    await finish(tester);
  });

  testWidgets('Packungsgröße: Preis je kg, Artikel merkt sich die Größe', (
    tester,
  ) async {
    final (state, listId, hack) = await setUp(tester);
    final session = state.currentGroup!;
    session.apply(session.group.addToList(listId, hack, quantity: 2));
    await tester.pump();
    await openSheet(tester);

    // Ohne Einheit gilt Packung, Grundpreis je Packung.
    expect(field('€/Packung'), findsOneWidget);
    await tester.enterText(field('Preis (€)'), '3,98');
    expect(text(tester, '€/Packung'), '1,99');

    // Mit Packungsgröße wird daraus ein Kilopreis, der Preis bleibt.
    await tester.enterText(field('Inhalt je Packung'), '500');
    await tester.pump();
    expect(text(tester, 'Preis (€)'), '3,98');
    expect(text(tester, '€/kg'), '3,98');

    // Menge ändern → Preis über den Kilopreis.
    await tester.enterText(field('Menge'), '3');
    expect(text(tester, 'Preis (€)'), '5,97');

    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    final e = session.group.entries(listId).single;
    expect(e.unit, isNull);
    expect(e.packSize, 500);
    expect(e.packUnit, Units.gram);
    expect(session.group.article(hack)!.packSize, 500);
    expect(find.text('3 Packungen à 500 g'), findsOneWidget);
    expect(find.text('3,98 €/kg'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('Zurück von der Artikelseite landet wieder im Eintrag', (
    tester,
  ) async {
    final (state, listId, hack) = await setUp(tester);
    final session = state.currentGroup!;
    session.apply(session.group.addToList(listId, hack, quantity: 2));
    await tester.pump();
    await openSheet(tester);
    await tester.enterText(field('Notiz für alle'), 'vom Metzger');

    await tester.tap(find.text('Artikel'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Endgültig löschen'), findsOne);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    // Das Blatt ist wieder da, samt ungespeicherter Eingabe.
    expect(text(tester, 'Notiz für alle'), 'vom Metzger');
    await finish(tester);
  });

  testWidgets('Inhalt an der Artikelseite geändert: Speichern überschreibt '
      'ihn nicht', (tester) async {
    final (state, listId, hack) = await setUp(tester);
    final session = state.currentGroup!;
    session.apply(
      session.group.updateArticle(hack, {'packSize': 500, 'packUnit': 'g'}),
    );
    session.apply(session.group.addToList(listId, hack, quantity: 2));
    await tester.pump();
    await openSheet(tester);

    await tester.tap(find.text('Artikel'));
    await tester.pumpAndSettle();
    session.apply(
      session.group.updateArticle(hack, {'packSize': 400, 'packUnit': 'g'}),
    );
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    // Der Eintrag behält seinen Inhalt, der Artikel den neuen.
    expect(text(tester, 'Inhalt je Packung'), '500');

    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(session.group.article(hack)!.packSize, 400);
    await finish(tester);
  });

  testWidgets('Artikel auf der Artikelseite gelöscht: Blatt schließt sich', (
    tester,
  ) async {
    final (state, listId, hack) = await setUp(tester);
    final session = state.currentGroup!;
    session.apply(session.group.addToList(listId, hack, quantity: 2));
    await tester.pump();
    await openSheet(tester);

    await tester.tap(find.text('Artikel'));
    await tester.pumpAndSettle();
    session.apply(session.group.deleteArticle(hack));
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Speichern'), findsNothing);
    await finish(tester);
  });
}
