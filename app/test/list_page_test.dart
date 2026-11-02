import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:konsum/main.dart';
import 'package:konsum/state/app_state.dart';
import 'package:konsum/storage/store.dart';

void main() {
  setUpAll(() => initializeDateFormatting('de'));

  Future<AppState> start(WidgetTester tester) async {
    final state = (await tester.runAsync(
      () => AppState.load(MemoryStore(), random: math.Random(1)),
    ))!;
    await tester.pumpWidget(KonsumApp(state: state));
    return state;
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 1)); // verzögertes Speichern
    await tester.pumpAndSettle();
  }

  testWidgets('Neuer Artikel wird in die Sicht gescrollt', (tester) async {
    final state = await start(tester);
    final session = state.currentGroup!;
    final listId = state.currentListId!;
    for (var i = 0; i < 40; i++) {
      final r = session.group.createArticle('Artikel ${i + 10}');
      session.apply([...r.changes, ...session.group.addToList(listId, r.id)]);
    }
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'Zucker');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Zucker').hitTestable(), findsOneWidget);
    await finish(tester);
  });

  testWidgets('Vorschläge nur mit Fokus, nur so hoch wie nötig', (
    tester,
  ) async {
    final state = await start(tester);
    final session = state.currentGroup!;
    session.apply(session.group.createArticle('Mehl').changes);
    await tester.pump();
    expect(find.widgetWithText(ActionChip, 'Mehl'), findsNothing);

    await tester.tap(find.byType(TextField));
    await tester.pump();
    final chip = find.widgetWithText(ActionChip, 'Mehl');
    expect(chip, findsOneWidget);

    // Eine Zeile Vorschläge: kein leerer Raum darüber.
    final scroll = find
        .ancestor(of: chip, matching: find.byType(SingleChildScrollView))
        .first;
    final panel = find
        .ancestor(of: scroll, matching: find.byType(Container))
        .first;
    final chipHeight = tester.getSize(chip).height;
    expect(tester.getSize(panel).height, lessThan(chipHeight * 1.5));

    // Fokus weg: Vorschläge weg.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(chip, findsNothing);
    await finish(tester);
  });
}
