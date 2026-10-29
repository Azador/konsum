import 'model.dart';

/// Menge in einer Grundeinheit: kg, l oder eine Zähleinheit (Stück,
/// Packung, …). Grundlage für Preise je kg/l/Stück.
typedef BaseAmount = ({num amount, String unit});

/// Rechnet eine Menge in ihre Grundeinheit um.
///
/// - Gewicht und Volumen: g → kg, ml → l. Ohne Menge: null.
/// - Zähleinheiten (Stück, Packung, …; ohne Einheit gilt Packung): mit
///   Packungsgröße in g/kg/ml/l wird über das Gewicht bzw. Volumen
///   gerechnet, sonst in der Zähleinheit. Ohne Menge gilt 1.
BaseAmount? baseAmount({
  num? quantity,
  String? unit,
  num? packSize,
  String? packUnit,
}) {
  final u = unit ?? Units.pack;
  if (Units.isMeasure(u)) {
    if (quantity == null) return null;
    return switch (u) {
      Units.gram => (amount: quantity / 1000, unit: Units.kilogram),
      Units.millilitre => (amount: quantity / 1000, unit: Units.litre),
      _ => (amount: quantity, unit: u),
    };
  }
  final count = quantity ?? 1;
  if (packSize != null && packSize > 0 && Units.isMeasure(packUnit)) {
    final pack = baseAmount(quantity: packSize, unit: packUnit);
    if (pack != null) return (amount: count * pack.amount, unit: pack.unit);
  }
  return (amount: count, unit: u);
}

/// Preis in Cent je Grundeinheit, oder null, wenn die Menge 0 ist.
double? pricePerBase(int cents, BaseAmount? base) =>
    base == null || base.amount == 0 ? null : cents / base.amount;
