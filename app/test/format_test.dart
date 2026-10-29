import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:konsum/ui/format.dart';
import 'package:konsum_core/konsum_core.dart';

void main() {
  setUpAll(() => initializeDateFormatting('de'));

  test('Schnelleingabe', () {
    expect(parseQuickAdd('Milch'), (name: 'Milch', quantity: null, unit: null));
    expect(parseQuickAdd('2 kg Mehl'), (
      name: 'Mehl',
      quantity: 2,
      unit: Units.kilogram,
    ));
    expect(parseQuickAdd('3x Joghurt'), (
      name: 'Joghurt',
      quantity: 3,
      unit: Units.piece,
    ));
    expect(parseQuickAdd('0,5 l Sahne'), (
      name: 'Sahne',
      quantity: 0.5,
      unit: Units.litre,
    ));
    expect(parseQuickAdd('2 Zitronen'), (
      name: 'Zitronen',
      quantity: 2,
      unit: null,
    ));
    expect(parseQuickAdd('4 rote Paprika'), (
      name: 'rote Paprika',
      quantity: 4,
      unit: null,
    ));
  });

  test('Beträge', () {
    expect(parseCents('1,29'), 129);
    expect(parseCents('1.29 €'), 129);
    expect(parseCents('3'), 300);
    expect(parseCents(''), isNull);
    expect(parseCents('abc'), isNull);
    expect(formatCents(129), '1,29\u00a0€');
  });

  test('Mengen', () {
    expect(formatQuantity(2, Units.pack), '2 Packung');
    expect(formatQuantity(0.5, Units.litre), '0,5 l');
    expect(formatQuantity(null, null), '');
  });
}
