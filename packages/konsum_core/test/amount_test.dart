import 'package:konsum_core/konsum_core.dart';
import 'package:test/test.dart';

void main() {
  test('Gewicht und Volumen in kg bzw. l', () {
    expect(baseAmount(quantity: 250, unit: Units.gram), (
      amount: 0.25,
      unit: Units.kilogram,
    ));
    expect(baseAmount(quantity: 2, unit: Units.kilogram), (
      amount: 2,
      unit: Units.kilogram,
    ));
    expect(baseAmount(quantity: 330, unit: Units.millilitre), (
      amount: 0.33,
      unit: Units.litre,
    ));
    expect(baseAmount(unit: Units.gram), isNull);
  });

  test('Zähleinheiten, mit und ohne Packungsgröße', () {
    expect(baseAmount(quantity: 3, unit: Units.can), (
      amount: 3,
      unit: Units.can,
    ));
    expect(baseAmount(), (amount: 1, unit: Units.pack));
    expect(
      baseAmount(
        quantity: 6,
        unit: Units.bottle,
        packSize: 1.5,
        packUnit: Units.litre,
      ),
      (amount: 9, unit: Units.litre),
    );
    expect(baseAmount(packSize: 500, packUnit: Units.gram), (
      amount: 0.5,
      unit: Units.kilogram,
    ));
    // Packung mit 6 Stück: Preis je Stück.
    expect(baseAmount(quantity: 2, packSize: 6, packUnit: Units.piece), (
      amount: 12,
      unit: Units.piece,
    ));
    // Stück je Stück ergibt keinen Sinn und zählt nicht.
    expect(
      baseAmount(
        quantity: 3,
        unit: Units.piece,
        packSize: 6,
        packUnit: Units.piece,
      ),
      (amount: 3, unit: Units.piece),
    );
    // Kiste mit 20 Flaschen: Preis je Flasche.
    expect(
      baseAmount(
        quantity: 2,
        unit: Units.crate,
        packSize: 20,
        packUnit: Units.bottle,
      ),
      (amount: 40, unit: Units.bottle),
    );
    // Flasche je Flasche zählt nicht.
    expect(
      baseAmount(
        quantity: 3,
        unit: Units.bottle,
        packSize: 6,
        packUnit: Units.bottle,
      ),
      (amount: 3, unit: Units.bottle),
    );
    // Andere Zähleinheiten als Inhalt zählen nicht.
    expect(baseAmount(quantity: 2, packSize: 6, packUnit: Units.can), (
      amount: 2,
      unit: Units.pack,
    ));
  });

  test('Preis je Grundeinheit', () {
    expect(pricePerBase(129, (amount: 0.5, unit: Units.kilogram)), 258);
    expect(pricePerBase(129, (amount: 0, unit: Units.kilogram)), isNull);
    expect(pricePerBase(129, null), isNull);
  });
}
