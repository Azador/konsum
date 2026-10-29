import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:konsum/main.dart';
import 'package:konsum/state/app_state.dart';
import 'package:konsum/state/group_session.dart';
import 'package:konsum/storage/store.dart';
import 'package:konsum/ui/article_page.dart';
import 'package:konsum_core/konsum_core.dart';

void main() {
  setUpAll(() => initializeDateFormatting('de'));

  Future<(GroupSession, String)> open(WidgetTester tester) async {
    final state = (await tester.runAsync(
      () => AppState.load(MemoryStore(), random: math.Random(1)),
    ))!;
    final session = state.currentGroup!;
    final article = session.group.createArticle('Nudeln');
    session.apply(article.changes);
    await tester.pumpWidget(KonsumApp(state: state));
    tester
        .state<NavigatorState>(find.byType(Navigator).first)
        .push(
          MaterialPageRoute<void>(
            builder: (_) =>
                ArticlePage(session: session, articleId: article.id),
          ),
        );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Packungsgröße'));
    await tester.pumpAndSettle();
    return (session, article.id);
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
  }

  for (final (input, size, unit) in [
    ('500', 500, Units.gram),
    ('500 g', 500, Units.gram),
    ('1,5 l', 1.5, Units.litre),
  ]) {
    testWidgets('Packungsgröße am Artikel: „$input“', (tester) async {
      final (session, id) = await open(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Inhalt'), input);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      final article = session.group.article(id)!;
      expect(article.packSize, size);
      expect(article.packUnit, unit);
      expect(find.text(input.contains(' ') ? input : '$input g'), findsOne);
      await finish(tester);
    });
  }

  testWidgets('Packungsgröße: Einheit wählen und wieder entfernen', (
    tester,
  ) async {
    final (session, id) = await open(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Inhalt'), '750');
    await tester.tap(find.text('g'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ml').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(session.group.article(id)!.packUnit, Units.millilitre);

    await tester.tap(find.text('Packungsgröße'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keine'));
    await tester.pumpAndSettle();
    expect(session.group.article(id)!.packSize, isNull);
    expect(session.group.article(id)!.packUnit, isNull);
    await finish(tester);
  });
}
