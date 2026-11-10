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
  Units.crate: 'Kiste',
};

const _pluralLabels = {
  Units.pack: 'Packungen',
  Units.can: 'Dosen',
  Units.bottle: 'Flaschen',
  Units.crate: 'Kisten',
};

String unitLabel(String? unit) => unit == null ? '' : unitLabels[unit] ?? unit;

/// Einheit passend zur Menge: „1 Packung“, „2 Packungen“.
String unitLabelFor(String? unit, num? quantity) =>
    quantity != null && quantity != 1
    ? _pluralLabels[unit] ?? unitLabel(unit)
    : unitLabel(unit);

final _number = NumberFormat.decimalPattern('de');
final _money = NumberFormat.currency(locale: 'de', symbol: '€');
final _date = DateFormat('dd.MM.yyyy', 'de');

String formatQuantity(num? quantity, String? unit) {
  if (quantity == null) return unitLabel(unit);
  return [
    _number.format(quantity),
    unitLabelFor(unit, quantity),
  ].where((s) => s.isNotEmpty).join(' ');
}

/// Menge mit Packungsgröße, z. B. „3 Packungen à 500 g“ oder „200 g“.
/// Ohne Menge: null. Ohne Einheit gilt Packung.
String? formatAmount({
  num? quantity,
  String? unit,
  num? packSize,
  String? packUnit,
}) {
  if (quantity == null) return null;
  final text = formatQuantity(quantity, unit ?? Units.pack);
  if (packSize != null && Units.isPackUnitFor(packUnit, unit ?? Units.pack)) {
    return '$text à ${formatQuantity(packSize, packUnit)}';
  }
  return text;
}

/// [formatAmount] für eine [Amount].
String? formatAmountOf(Amount a) => formatAmount(
  quantity: a.quantity,
  unit: a.unit,
  packSize: a.packSize,
  packUnit: a.packUnit,
);

String formatCents(int cents) => _money.format(cents / 100);

/// Preis je Grundeinheit, z. B. „2,58 €/kg“ oder „0,99 €/Packung“.
String formatBasePrice(num cents, String baseUnit) =>
    '${_money.format(cents / 100)}/${unitLabel(baseUnit)}';

/// Liest eine Packungsgröße wie „500 g“, „1,5 l“, „0.75L“ oder „6 Stück“.
/// Gewicht und Volumen gehen vor („6 Stück à 60 g“ → 60 g). Null, wenn
/// nichts Passendes darin steht.
({num size, String unit})? parseAmount(String text) {
  final m =
      RegExp(
        r'(\d+(?:[.,]\d+)?)\s*(kg|kilo|g|gr|gramm|ml|l|ltr|liter)\b',
        caseSensitive: false,
      ).firstMatch(text) ??
      RegExp(
        r'(\d+(?:[.,]\d+)?)\s*(stück|stueck|stk|st)(?![\wäöüß])',
        caseSensitive: false,
      ).firstMatch(text);
  if (m == null) return null;
  final size = parseNumber(m.group(1)!);
  if (size == null || size == 0) return null;
  final unit = switch (m.group(2)!.toLowerCase()) {
    'kilo' => Units.kilogram,
    'gr' || 'gramm' => Units.gram,
    'ltr' || 'liter' => Units.litre,
    'stück' || 'stueck' || 'stk' || 'st' => Units.piece,
    final u => u,
  };
  return (size: size, unit: unit);
}

/// Betrag für Eingabefelder: „2,58“.
String formatCentsInput(num cents) =>
    (cents / 100).toStringAsFixed(2).replaceAll('.', ',');

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
  'kiste': Units.crate,
  'kisten': Units.crate,
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
