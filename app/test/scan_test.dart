import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:konsum/main.dart';
import 'package:konsum/services/open_food_facts.dart';
import 'package:konsum/state/app_state.dart';
import 'package:konsum/storage/store.dart';

void main() {
  setUpAll(() => initializeDateFormatting('de'));

  group('Open Food Facts', () {
    test('liest Name, Marke und Nährwerte', () async {
      late Uri requested;
      final off = OpenFoodFacts(
        client: MockClient((req) async {
          requested = req.url;
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'status': 1,
                'product': {
                  'product_name': 'Spaghetti n.5',
                  'product_name_de': '',
                  'brands': 'Barilla',
                  'quantity': '500 g',
                  'nutriscore_grade': 'a',
                  'nutriments': {
                    'energy-kcal_100g': 359,
                    'proteins_100g': 12.5,
                    'salt_100g': 0.013,
                    'energy-kcal_serving': 300,
                  },
                },
              }),
            ),
            200,
          );
        }),
      );
      final info = (await off.lookup('8076800195057'))!;
      expect(requested.path, '/api/v2/product/8076800195057.json');
      expect(info.name, 'Spaghetti n.5', reason: 'leerer DE-Name zählt nicht');
      expect(info.brand, 'Barilla');
      expect(info.nutriments, {
        'energy-kcal': 359,
        'proteins': 12.5,
        'salt': 0.013,
      });
    });

    test('unbekanntes Produkt und ungültiger Code', () async {
      var calls = 0;
      final off = OpenFoodFacts(
        client: MockClient((_) async {
          calls++;
          return http.Response('{"status":0}', 404);
        }),
      );
      expect(await off.lookup('4000000000001'), isNull);
      expect(await off.lookup('Milch'), isNull);
      expect(calls, 1);
    });
  });

  testWidgets('Handscanner: bekannter Barcode hakt ab bzw. fügt hinzu', (
    tester,
  ) async {
    final state = (await tester.runAsync(
      () => AppState.load(MemoryStore(), random: math.Random(1)),
    ))!;
    final session = state.currentGroup!;
    final listId = state.currentListId!;
    final milch = session.group.createArticle('Milch');
    session.apply([
      ...milch.changes,
      ...session.group.assignBarcode('4000000000001', milch.id),
    ]);
    await tester.pumpWidget(KonsumApp(state: state));

    // Nicht auf der Liste → hinzufügen.
    await tester.enterText(find.byType(TextField), '4000000000001');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Milch hinzugefügt'), findsOneWidget);
    expect(session.group.entries(listId).single.checked, isFalse);

    // Offen auf der Liste → abhaken.
    await tester.enterText(find.byType(TextField), '4000000000001');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(session.group.entries(listId).single.checked, isTrue);
    expect(session.group.articles, hasLength(1));

    // Snackbars und verzögertes Speichern ablaufen lassen.
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
  });
}
