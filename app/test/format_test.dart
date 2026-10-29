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
    expect(formatQuantity(2, Units.pack), '2 Packungen');
    expect(formatQuantity(1, Units.pack), '1 Packung');
    expect(formatQuantity(3, Units.piece), '3 Stück');
    expect(formatQuantity(0.5, Units.litre), '0,5 l');
    expect(formatQuantity(null, null), '');
  });

  test('Menge mit Packungsgröße', () {
    expect(formatAmount(), isNull);
    expect(formatAmount(unit: Units.gram, packSize: 5), isNull);
    expect(formatAmount(quantity: 200, unit: Units.gram), '200 g');
    expect(formatAmount(quantity: 2), '2 Packungen');
    expect(
      formatAmount(quantity: 3, packSize: 500, packUnit: Units.gram),
      '3 Packungen à 500 g',
    );
    // Packungsgröße nur bei Zähleinheiten.
    expect(
      formatAmount(
        quantity: 200,
        unit: Units.gram,
        packSize: 500,
        packUnit: Units.gram,
      ),
      '200 g',
    );
  });

  test('Packungsgröße aus Text', () {
    expect(parseAmount('500 g'), (size: 500, unit: 'g'));
    expect(parseAmount('1,5 L'), (size: 1.5, unit: 'l'));
    expect(parseAmount('6 x 0.33l'), (size: 0.33, unit: 'l'));
    expect(parseAmount('2 Stück'), isNull);
    expect(parseAmount(''), isNull);
  });

  test('Grundpreis', () {
    expect(formatBasePrice(258, Units.kilogram), '2,58\u00a0€/kg');
    expect(formatBasePrice(99.5, Units.pack), '1,00\u00a0€/Packung');
    expect(formatCentsInput(249), '2,49');
  });
}
