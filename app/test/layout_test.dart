import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:konsum/main.dart';
import 'package:konsum/state/app_state.dart';
import 'package:konsum/storage/store.dart';

import 'support/sample_data.dart';

/// Geht die wichtigsten Seiten auf verbreiteten Telefonen mit normaler und
/// großer Schrift durch. Ein Überlauf (gelb-schwarze Streifen) lässt den
/// Test von selbst scheitern; dazu kommen Prüfungen, dass Namen und Preise
/// nicht in schmale Spalten gequetscht werden.
void main() {
  // Ein Tipp, der danebengeht, ist hier ein Fehler, keine Warnung.
  WidgetController.hitTestWarningShouldBeFatal = true;

  setUpAll(() async {
    await initializeDateFormatting('de');
    await loadRoboto();
  });

  for (final device in devices) {
    for (final scale in textScales) {
      testWidgets('${device.name}, Schrift ×$scale', (tester) async {
        tester.view
          ..physicalSize = device.size * device.ratio
          ..devicePixelRatio = device.ratio;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearAllTestValues);

        final state = (await tester.runAsync(
          () => AppState.load(MemoryStore(), random: math.Random(1)),
        ))!;
        seedSampleData(state);
        await tester.pumpWidget(KonsumApp(state: state));
        await tester.pumpAndSettle();

        // Liste: kurze Namen und alle Preise in einer Zeile.
        expectSingleLine(tester, find.text(Sample.ham));
        expectSingleLine(tester, find.text(Sample.salt));
        expectSingleLine(
          tester,
          find.descendant(
            of: find.byType(CheckboxListTile),
            matching: find.textContaining('€'),
          ),
        );

        // Eintragsblatt mit Packungs- und Grundpreis.
        final edit = find.descendant(
          of: find.ancestor(
            of: find.text(Sample.water),
            matching: find.byType(CheckboxListTile),
          ),
          matching: find.byTooltip('Bearbeiten'),
        );
        await tester.ensureVisible(edit);
        await tester.pumpAndSettle();
        await tester.tap(edit);
        await tester.pumpAndSettle();
        // Bei kleinen Geräten mit großer Schrift erst nach Scrollen sichtbar.
        expect(find.text('Speichern', skipOffstage: false), findsOneWidget);
        // Schließen; mit großer Schrift reicht das Blatt bis nach oben.
        Navigator.pop(tester.element(find.byType(BottomSheet)));
        await tester.pumpAndSettle();

        Future<void> drawer(String item) async {
          await tester.tap(find.byTooltip('Navigationsmenü öffnen'));
          await tester.pumpAndSettle();
          await tester.tap(find.text(item));
          await tester.pumpAndSettle();
        }

        Future<void> back() async {
          // pageBack() sucht den englischen Tooltip „Back“.
          await tester.tap(find.byType(BackButton));
          await tester.pumpAndSettle();
        }

        await drawer('Artikel');
        await tester.tap(find.text(Sample.milk));
        await tester.pumpAndSettle();
        await back();
        await back();

        await drawer('Käufe');
        expect(find.text(Sample.ham), findsWidgets);
        await back();

        await drawer('Läden');
        await back();

        await drawer('Kategorien');
        await back();

        await tester.pump(const Duration(seconds: 1)); // verzögertes Speichern
      });
    }
  }

  // Sehr große Schrift (Android erlaubt 200 %) mit langen Namen, auch ohne
  // Leerzeichen: Vorschläge bleiben bei offener Tastatur sichtbar, und
  // nichts läuft über.
  for (final device in [
    ...devices,
    (name: 'große Anzeige', size: const Size(300, 620), ratio: 3.5),
  ]) {
    testWidgets('${device.name}, Schrift ×2,0, lange Namen', (tester) async {
      tester.view
        ..physicalSize = device.size * device.ratio
        ..devicePixelRatio = device.ratio;
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearAllTestValues);

      final state = (await tester.runAsync(
        () => AppState.load(MemoryStore(), random: math.Random(1)),
      ))!;
      seedSampleData(state);
      final session = state.currentGroup!;
      const long = 'Donaudampfschifffahrtsgesellschaftskapitänsmütze';
      const spaced = 'Bio Hafer Barista Drink ungesüßt im Tetrapak 1 Liter';
      for (final name in [long, spaced]) {
        session.apply(session.group.createArticle(name).changes);
      }
      final listed = session.group.createArticle('Rindfleischetikettierung');
      session.apply([
        ...listed.changes,
        ...session.group.addToList(state.currentListId!, listed.id),
        ...session.group.updateEntry(state.currentListId!, listed.id, {
          'basePrice': 1299,
        }),
      ]);
      await tester.pumpWidget(KonsumApp(state: state));
      await tester.pumpAndSettle();

      // Der Name der Liste bleibt in der Kopfzeile zu sehen.
      final title = tester.getSize(find.text('Einkaufsliste'));
      expect(title.width, greaterThan(60));

      // Tastatur offen, gut ein Drittel des Bildschirms.
      await tester.showKeyboard(find.byType(TextField));
      tester.view.viewInsets = FakeViewPadding(
        bottom: device.size.height * 0.42 * device.ratio,
      );
      await tester.pumpAndSettle();
      for (final query in ['do', 'bio']) {
        await tester.enterText(find.byType(TextField), query);
        await tester.pumpAndSettle();
        final chip = find.byType(ActionChip).first;
        expect(
          chip.hitTestable(),
          findsOneWidget,
          reason: 'Vorschlag „$query“',
        );
        // Ganz zu sehen, nicht unter der Kopfzeile abgeschnitten.
        expect(tester.getRect(chip).top, greaterThanOrEqualTo(0));
      }
      await tester.enterText(find.byType(TextField), '');
      tester.view.resetViewInsets();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      // Eintragsblatt: läuft nicht über (sonst schlägt der Test von selbst
      // fehl), und „Speichern“ ist erreichbar.
      final edit = find.byTooltip('Bearbeiten').first;
      await tester.ensureVisible(edit);
      await tester.pumpAndSettle();
      await tester.tap(edit);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Speichern'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      Navigator.pop(tester.element(find.byType(BottomSheet)));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1)); // verzögertes Speichern
    });
  }
}
