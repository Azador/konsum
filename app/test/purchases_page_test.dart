import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:konsum/main.dart';
import 'package:konsum/state/app_state.dart';
import 'package:konsum/storage/store.dart';
import 'package:konsum/ui/purchases_page.dart';
import 'package:konsum_core/konsum_core.dart';

void main() {
  setUpAll(() => initializeDateFormatting('de'));

  testWidgets('Kaufmenge korrigieren und Kauf löschen', (tester) async {
    final state = (await tester.runAsync(
      () => AppState.load(MemoryStore(), random: math.Random(1)),
    ))!;
    final session = state.currentGroup!;
    final group = session.group;
    final listId = state.currentListId!;
    final milk = group.createArticle('Milch');
    session
      ..apply(milk.changes)
      ..apply(group.addToList(listId, milk.id, quantity: 3, unit: Units.litre))
      ..apply(group.setChecked(listId, milk.id, true))
      ..apply(group.clearChecked(listId));
    await tester.pumpWidget(KonsumApp(state: state));
    tester
        .state<NavigatorState>(find.byType(Navigator).first)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => PurchasesPage(session: session),
          ),
        );
    await tester.pumpAndSettle();
    expect(find.text('Milch'), findsOneWidget);
    expect(find.textContaining('3 l'), findsOneWidget);

    await tester.tap(find.byTooltip('Menge korrigieren'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Weniger'));
    await tester.pump();
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(group.purchases.single.amount?.quantity, 2);
    expect(find.textContaining('2 l'), findsOneWidget);

    await tester.tap(find.byTooltip('Kauf löschen'));
    await tester.pumpAndSettle();
    expect(group.purchases, isEmpty);
    expect(find.text('Noch keine Käufe.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });
}
