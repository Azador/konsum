import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:konsum/main.dart';
import 'package:konsum/state/app_state.dart';
import 'package:konsum/storage/store.dart';
import 'package:konsum/ui/format.dart';
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

  testWidgets('Lose Ware: ein Feld für den Kilopreis, Gesamtpreis darunter', (
    tester,
  ) async {
    final (state, listId, hack) = await setUp(tester);
    final session = state.currentGroup!;
    session.apply(
      session.group.addToList(listId, hack, quantity: 100, unit: Units.gram),
    );
    await tester.pump();
    await openSheet(tester);

    // Am Regal steht der Kilopreis; ein zweites Feld gibt es nicht.
    expect(find.text('Grundpreis'), findsNothing);
    expect(find.text('100 g: –'), findsOneWidget);
    await tester.enterText(field('€/kg'), '9,90');
    await tester.pump();
    expect(find.text('100 g: ${formatCents(99)}'), findsOneWidget);

    // Menge ändern → Kilopreis bleibt, Gesamtpreis folgt.
    await tester.enterText(field('Menge'), '200');
    await tester.pump();
    expect(text(tester, '€/kg'), '9,90');
    expect(find.text('200 g: ${formatCents(198)}'), findsOneWidget);

    await tester.enterText(field('€/kg'), '10');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    final e = session.group.entries(listId).single;
    expect(e.quantity, 200);
    expect(e.basePrice, 1000);
    expect(e.totalCents, 200);
    expect(find.text(formatCents(200)), findsOneWidget);
    expect(find.text(formatBasePrice(1000, Units.kilogram)), findsOneWidget);
    await finish(tester);
  });

  testWidgets('Packungsgröße nachträglich: Packungspreis bleibt beim Tippen', (
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
    expect(text(tester, '€/Packung'), '2,99');
    expect(find.text('Grundpreis'), findsNothing);

    // Zeichen für Zeichen, wie auf der Tastatur.
    for (final typed in ['5', '50', '500']) {
      await tester.enterText(field('Inhalt je Packung'), typed);
      await tester.pump();
      expect(text(tester, '€/Packung'), '2,99');
    }
    expect(text(tester, '€/kg'), '5,98');

    // Inhaltseinheit ändern: Packungspreis bleibt, Kilopreis folgt.
    await tester.tap(find.text('g').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('kg').last);
    await tester.pumpAndSettle();
    expect(text(tester, '€/Packung'), '2,99');
    expect(text(tester, '€/kg'), '0,01');

    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    final e = session.group.entries(listId).single;
    expect(e.packSize, 500);
    expect(e.packUnit, Units.kilogram);
    expect(e.totalCents, 299);
    await finish(tester);
  });

  testWidgets('Packungsgröße: Preis je Packung und je kg, Artikel merkt sich '
      'die Größe', (tester) async {
    final (state, listId, hack) = await setUp(tester);
    final session = state.currentGroup!;
    session.apply(session.group.addToList(listId, hack, quantity: 2));
    await tester.pump();
    await openSheet(tester);

    // Ohne Einheit gilt Packung; ohne Inhalt ist das der Grundpreis.
    await tester.enterText(field('€/Packung'), '1,99');
    await tester.pump();
    expect(find.text('2 Packungen: ${formatCents(398)}'), findsOneWidget);

    // Mit Packungsgröße kommt der Kilopreis dazu, der Packungspreis bleibt.
    await tester.enterText(field('Inhalt je Packung'), '500');
    await tester.pump();
    expect(text(tester, '€/Packung'), '1,99');
    expect(text(tester, '€/kg'), '3,98');
    expect(find.text('Grundpreis'), findsOneWidget);

    // Menge ändern → nur der Gesamtpreis folgt.
    await tester.enterText(field('Menge'), '3');
    await tester.pump();
    expect(text(tester, '€/Packung'), '1,99');
    expect(find.text('3 Packungen: ${formatCents(597)}'), findsOneWidget);

    // Kilopreis ändern → Packungspreis.
    await tester.enterText(field('€/kg'), '4');
    await tester.pump();
    expect(text(tester, '€/Packung'), '2,00');
    expect(find.text('3 Packungen: ${formatCents(600)}'), findsOneWidget);

    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    final e = session.group.entries(listId).single;
    expect(e.unit, isNull);
    expect(e.packSize, 500);
    expect(e.packUnit, Units.gram);
    expect(e.totalCents, 600);
    expect(session.group.article(hack)!.packSize, 500);
    expect(find.text('3 Packungen à 500 g'), findsOneWidget);
    expect(find.text(formatBasePrice(400, Units.kilogram)), findsOneWidget);
    await finish(tester);
  });

  testWidgets('Letzter Preis als Vorgabe, gespeichert wird er nicht', (
    tester,
  ) async {
    final (state, listId, hack) = await setUp(tester);
    final session = state.currentGroup!;
    final group = session.group;
    const pack = {'packSize': 500, 'packUnit': Units.gram};
    session
      ..apply(group.addToList(listId, hack, quantity: 2))
      ..apply(group.updateEntry(listId, hack, {...pack, 'basePrice': 398}))
      ..apply(group.setChecked(listId, hack, true))
      ..apply(group.clearChecked(listId))
      ..apply(group.addToList(listId, hack, quantity: 3))
      ..apply(group.updateEntry(listId, hack, pack));
    await tester.pump();
    await openSheet(tester);

    String? hint(String label) =>
        tester.widget<TextField>(field(label)).decoration!.hintText;
    expect(text(tester, '€/Packung'), '');
    expect(hint('€/Packung'), '1,99');
    expect(hint('€/kg'), '3,98');
    // Sichtbar, ohne erst hineinzutippen.
    double opacity(String text) => tester
        .widget<AnimatedOpacity>(
          find
              .ancestor(
                of: find.text(text),
                matching: find.byType(AnimatedOpacity),
              )
              .first,
        )
        .opacity;
    expect(opacity('1,99'), 1);
    expect(opacity('3,98'), 1);
    expect(find.text('3 Packungen: ≈ ${formatCents(597)}'), findsOneWidget);

    // Unverändert speichern: Der Eintrag bleibt ohne eigenen Preis.
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(group.entries(listId).single.totalCents, isNull);

    // Eingetippt gilt er als Preis dieses Einkaufs.
    await openSheet(tester);
    await tester.enterText(field('€/Packung'), '1,99');
    await tester.pump();
    expect(find.text('3 Packungen: ${formatCents(597)}'), findsOneWidget);
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(group.entries(listId).single.totalCents, 597);
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
