import 'package:intl/intl.dart';
import 'package:konsum_core/konsum_core.dart';

const unitLabels = {
  Units.piece: 'Stück',
  Units.gram: 'g',
  Units.kilogram: 'kg',
  Units.millilitre: 'ml',
  Units.litre: 'l',
  Units.pack: 'Packung',
  Units.can: 'Dose',
  Units.bottle: 'Flasche',
  Units.bunch: 'Bund',
};

String unitLabel(String? unit) => unit == null ? '' : unitLabels[unit] ?? unit;

final _number = NumberFormat.decimalPattern('de');
final _money = NumberFormat.currency(locale: 'de', symbol: '€');
final _date = DateFormat('dd.MM.yyyy', 'de');

String formatQuantity(num? quantity, String? unit) {
  if (quantity == null) return unitLabel(unit);
  return [
    _number.format(quantity),
    unitLabel(unit),
  ].where((s) => s.isNotEmpty).join(' ');
}

String formatCents(int cents) => _money.format(cents / 100);

String formatDate(int millis) =>
    _date.format(DateTime.fromMillisecondsSinceEpoch(millis));

/// Liest eine Zahl mit Komma oder Punkt; null bei leerer oder ungültiger Eingabe.
num? parseNumber(String text) {
  final t = text.trim().replaceAll(',', '.');
  if (t.isEmpty) return null;
  final n = num.tryParse(t);
  return n == null || n < 0 ? null : (n == n.roundToDouble() ? n.round() : n);
}

/// Liest einen Betrag in Euro („1,29“, „1.29 €“) als Cent.
int? parseCents(String text) {
  final n = parseNumber(text.replaceAll('€', ''));
  return n == null ? null : (n * 100).round();
}

const _unitAliases = {
  'stk': Units.piece,
  'stück': Units.piece,
  'x': Units.piece,
  'g': Units.gram,
  'kg': Units.kilogram,
  'ml': Units.millilitre,
  'l': Units.litre,
  'pck': Units.pack,
  'packung': Units.pack,
  'dose': Units.can,
  'dosen': Units.can,
  'fl': Units.bottle,
  'flasche': Units.bottle,
  'flaschen': Units.bottle,
  'bund': Units.bunch,
};

/// Schnelleingabe wie „2 kg Mehl“, „3x Joghurt“ oder „Milch“.
({String name, num? quantity, String? unit}) parseQuickAdd(String input) {
  final m = RegExp(r'^(\d+(?:[.,]\d+)?)\s*([a-zA-Zäöüß]+\b)?\s+(.+)$')
      .firstMatch(input.trim());
  if (m == null) return (name: input.trim(), quantity: null, unit: null);
  final unitWord = m.group(2)?.toLowerCase();
  final unit = unitWord == null ? null : _unitAliases[unitWord];
  if (unitWord != null && unit == null) {
    // Kein bekanntes Einheitenwort: gehört zum Namen („2 Zitronen“).
    return (
      name: '${m.group(2)} ${m.group(3)}'.trim(),
      quantity: parseNumber(m.group(1)!),
      unit: null,
    );
  }
  return (
    name: m.group(3)!.trim(),
    quantity: parseNumber(m.group(1)!),
    unit: unit,
  );
}
