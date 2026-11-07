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

  testWidgets('Plus und Minus im Mengenfeld', (tester) async {
    final (state, listId, hack) = await setUp(tester);
    final session = state.currentGroup!;
    session.apply(
      session.group.addToList(listId, hack, quantity: 2, unit: Units.pack),
    );
    await tester.pump();
    await openSheet(tester);
    await tester.tap(find.byTooltip('Mehr'));
    await tester.pump();
    expect(text(tester, 'Menge'), '3');
    await tester.tap(find.byTooltip('Weniger'));
    await tester.tap(find.byTooltip('Weniger'));
    await tester.pump();
    expect(text(tester, 'Menge'), '1');
    // Unter eine Packung geht es nicht.
    await tester.tap(find.byTooltip('Weniger'));
    await tester.pump();
    expect(text(tester, 'Menge'), '1');
    await finish(tester);
  });

  testWidgets('Automatische Menge getrennt von der eigenen', (tester) async {
    final (state, listId, hack) = await setUp(tester);
    final session = state.currentGroup!;
    final now = DateTime.now().millisecondsSinceEpoch;
    const day = Duration.millisecondsPerDay;
    // Zwei Käufe à 4 kg im Abstand einer Woche, der letzte vor einer Woche.
    session.group.receive([
      for (final (i, ago) in [14, 7].indexed)
        for (final f in {
          'articleId': hack,
          'listId': listId,
          'millis': now - ago * day,
          'quantity': 4,
          'unit': Units.kilogram,
        }.entries)
          Change(
            type: Types.purchase,
            id: 'p$i',
            field: f.key,
            value: f.value,
            hlc: Hlc(now - ago * day, 0, 'bob'),
          ),
    ]);
    state.automatic = true;
    await tester.pump();
    expect(
      find.textContaining('automatisch 4 kg', findRichText: true),
      findsOneWidget,
    );

    await openSheet(tester);
    await tester.tap(find.byTooltip('Mehr'));
    await tester.pump();
    expect(text(tester, 'Menge'), '5');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    // Zwischen beiden steht das Symbol der Automatik.
    expect(
      find.textContaining(
        RegExp('^5 kg · .*automatisch 4 kg'),
        findRichText: true,
      ),
      findsOneWidget,
    );

    state.automatic = false;
    await tester.pump();
    // Keine Menge der Automatik mehr, aber erkennbar, wer den Eintrag
    // gesetzt hat.
    expect(
      find.textContaining('automatisch 4 kg', findRichText: true),
      findsNothing,
    );
    expect(
      find.textContaining('automatisch hinzugefügt', findRichText: true),
      findsOneWidget,
    );
    await finish(tester);
  });
}
