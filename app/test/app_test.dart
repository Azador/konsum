import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:konsum/main.dart';
import 'package:konsum/state/app_state.dart';
import 'package:konsum/storage/store.dart';

void main() {
  setUpAll(() => initializeDateFormatting('de'));

  Future<(AppState, MemoryStore)> start(WidgetTester tester) async {
    final store = MemoryStore();
    final state = (await tester.runAsync(
      () => AppState.load(store, random: math.Random(1)),
    ))!;
    await tester.pumpWidget(KonsumApp(state: state));
    return (state, store);
  }

  testWidgets('Erster Start legt Gruppe, Liste und Kategorien an', (
    tester,
  ) async {
    final (state, _) = await start(tester);
    expect(find.text('Einkaufsliste'), findsOneWidget);
    expect(find.text('Die Liste ist leer.'), findsOneWidget);
    expect(state.currentGroup!.group.categories, hasLength(10));
  });

  testWidgets('Hinzufügen, abhaken, aufräumen, wieder vorschlagen', (
    tester,
  ) async {
    final (state, _) = await start(tester);
    final group = state.currentGroup!.group;

    await tester.enterText(find.byType(TextField), '2 kg Mehl');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.text('Mehl'), findsOneWidget);
    expect(find.text('2 kg'), findsOneWidget);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.byTooltip('Abgehakte entfernen'));
    await tester.pump();
    expect(find.text('Die Liste ist leer.'), findsOneWidget);
    expect(group.purchases, hasLength(1));

    // Eingabefeld fokussieren: Mehl wird vorgeschlagen.
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.tap(find.widgetWithText(ActionChip, 'Mehl'));
    await tester.pump();
    expect(group.entries(state.currentListId!), hasLength(1));
    expect(group.articles, hasLength(1), reason: 'kein doppelter Artikel');
    await tester.pump(const Duration(seconds: 1)); // verzögertes Speichern
  });

  testWidgets('Zustand überlebt einen Neustart', (tester) async {
    final (state, store) = await start(tester);
    final session = state.currentGroup!;
    final r = session.group.createArticle('Milch');
    session.apply([
      ...r.changes,
      ...session.group.addToList(state.currentListId!, r.id),
    ]);
    session.applyPrivate(
      session.private.setNote('${state.currentListId}/${r.id}', 'laktosefrei'),
    );
    await tester.runAsync(session.save);

    final again = (await tester.runAsync(() => AppState.load(store)))!;
    expect(again.node, state.node);
    final g = again.currentGroup!;
    expect(g.group.entries(again.currentListId!).single.articleId, r.id);
    expect(g.private.note('${again.currentListId}/${r.id}'), 'laktosefrei');
    expect(g.outbox.pending, isEmpty, reason: 'lokale Gruppe, keine Outbox');
  });

  testWidgets('Farbschema pro Gruppe wirkt aufs Theme und bleibt erhalten', (
    tester,
  ) async {
    final (state, store) = await start(tester);
    final session = state.currentGroup!;
    Color primary() =>
        Theme.of(tester.element(find.byType(Scaffold).first))
            .colorScheme
            .primary;
    final green = primary();

    state.setColor(session, Colors.blue.toARGB32());
    await tester.pump();
    await tester.pump(const Duration(seconds: 1)); // Theme-Animation
    expect(primary(), isNot(green));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));

    final again = (await tester.runAsync(() => AppState.load(store)))!;
    expect(again.colorFor(again.currentGroup!), Colors.blue.toARGB32());

    state.setColor(session, null);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(primary(), green);
  });

  testWidgets('Aufbewahrung in den Gruppeneinstellungen', (tester) async {
    final (state, _) = await start(tester);
    final group = state.currentGroup!.group;
    await tester.tap(find.byTooltip('Navigationsmenü öffnen'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Gruppe verwalten'));
    await tester.pumpAndSettle();
    expect(find.textContaining('6 Monate (Vorgabe)'), findsOneWidget);

    await tester.tap(find.text('Aufbewahrung'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nicht automatisch löschen'));
    await tester.pump();
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    expect(group.retentionMonths, 0);
    expect(find.textContaining('Ohne automatisches Löschen'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1)); // verzögertes Speichern
  });
}
