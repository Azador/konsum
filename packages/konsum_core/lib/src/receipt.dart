/// Kassenbon: Text aus mehreren OCR-Läufen in Positionen zerlegen, die Läufe
/// gegeneinander abstimmen und mit den Prüfsummen des Bons plausibilisieren.
///
/// Ein einzelner Tesseract-Lauf liest etwa 90 % der Preise richtig, aber
/// jeder Lauf (andere Vorbearbeitung) irrt sich an anderen Stellen. Deshalb:
/// alle Läufe zerlegen, Positionen über die Läufe hinweg einander zuordnen
/// ([_align]), je Feld die Mehrheit nehmen und danach prüfen:
/// Menge × Einzelpreis = Zeilenpreis, Summe der Zeilen = Bonsumme.
library;

import 'dart:math' as math;

/// Eine Position des Bons.
class ReceiptLine {
  ReceiptLine({
    required this.text,
    required this.cents,
    this.quantity,
    this.unitCents,
    this.check = ReceiptCheck.none,
    this.votes = 1,
    this.prices = const {},
  });

  /// Bezeichnung, wie sie auf dem Bon steht (OCR, nach Mehrheit).
  final String text;

  /// Zeilenpreis in Cent; null, wenn nicht lesbar.
  int? cents;

  /// Menge und Einzelpreis aus einer Mengenzeile („2 x 1,35 €/ST“).
  final num? quantity;
  final int? unitCents;

  /// Wodurch der Preis abgesichert ist.
  ReceiptCheck check;

  /// In wie vielen Läufen die Position gefunden wurde.
  final int votes;

  /// Gelesene Preise mit Anzahl der Läufe.
  final Map<int, int> prices;

  /// Ganzzahlige Menge (Stück) aus der Mengenzeile, sonst null.
  int? get count =>
      quantity != null && quantity == quantity!.roundToDouble() && quantity! > 0
      ? quantity!.round()
      : null;
}

enum ReceiptCheck {
  /// Nur Mehrheit der Läufe.
  none,

  /// Menge × Einzelpreis ergibt den Zeilenpreis.
  quantity,

  /// Aus Menge × Einzelpreis berechnet (Zeilenpreis unlesbar).
  computed,

  /// Durch die Bonsumme korrigiert oder ergänzt.
  total,
}

/// Ergebnis der Auswertung.
class Receipt {
  Receipt({required this.lines, required this.totalCents, this.header = ''});

  final List<ReceiptLine> lines;

  /// Summe laut Bon (Summenzeile oder Zahlungszeile); null, wenn unlesbar.
  final int? totalCents;

  /// Kopf des Bons (Zeilen vor der ersten Position), z. B. für den Laden.
  final String header;

  int get sumCents => lines.fold(0, (s, l) => s + (l.cents ?? 0));

  /// Ob die Positionen genau die Bonsumme ergeben.
  bool get balanced => totalCents != null && sumCents == totalCents;
}

/// Zerlegt die Texte mehrerer OCR-Läufe desselben Bons und führt sie zusammen.
Receipt readReceipt(List<String> runs) {
  final parsed = [for (final r in runs) _parse(r)];
  final groups = _merge(parsed);
  final totals = <int, int>{};
  for (final p in parsed) {
    if (p.total != null) totals[p.total!] = (totals[p.total!] ?? 0) + 1;
  }
  final headers = parsed.map((p) => p.header).toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  return _resolve(
    groups,
    _mostCommon(totals),
    (parsed.length + 1) ~/ 2,
    headers.isEmpty ? '' : headers.first,
  );
}

// --------------------------------------------------------------- Zerlegen

// Häufige OCR-Verwechslungen in Preisfeldern.
const _digit = {
  'O': '0',
  'o': '0',
  'D': '0',
  'I': '1',
  'l': '1',
  '|': '1',
  'Z': '2',
  'S': '5',
  'B': '8',
  'G': '6',
};

String _digits(String s) => s.split('').map((c) => _digit[c] ?? c).join();

final _price = RegExp(r'(-?\d{1,4})\s?[,.]\s?(\d{2})(?!\d)');
// Notlösungen für kaputte Preise: Steuerkennzeichen B als 8 angehängt
// („3,988“) oder Komma verloren („229EB“).
final _priceTax = RegExp(r'(\d{1,3})\s?[,.]\s?(\d{2})8(?!\d)');
final _priceNoSep = RegExp(r'(?<![\d,.])(\d{1,2})(\d{2})\s?[€E&]');
final _end = RegExp(
  r'\b(summe|zu zahlen|zwischensumme|total|gesamt)\b',
  caseSensitive: false,
);
final _pay = RegExp(
  r'(c-?\s?cash|lastschrift|girocard|kartenzahlung|^ge[gs]\.|^bar\s*(eur|€)?\s*\d)',
  caseSensitive: false,
);
// Spätestens hier ist der Positionsteil vorbei, auch wenn Summe und
// Zahlung unlesbar waren.
final _stop = RegExp(
  r'(kundenbeleg|datum|uhrzeit|beleg-?nr|trace|mwst|netto|brutto|={3,})',
  caseSensitive: false,
);
final _skip = RegExp(
  r'\b(mwst|netto|brutto|teile:|ec-|lastschrift|rückgeld|kundenbeleg|uid|ust|ust-id|tel\.|datum|uhrzeit)',
  caseSensitive: false,
);
// (2 x 1,35 €/ST) | 2 Stk x 0,85 | (0,090 ST x 66,90 €/ST)
final _qty = RegExp(
  r'^\W*(\d+(?:[,.]\d+)?)\s*(?:stk|st)?\s*[x×]\s*(\d+[,.]\s?\d{2})(?!\d)',
  caseSensitive: false,
);
final _letters = RegExp(r'[A-Za-zÄÖÜäöü]');

int _cents(RegExpMatch m) {
  final euros = m.group(1)!;
  final c = int.parse(m.group(2)!);
  return int.parse(euros) * 100 + (euros.startsWith('-') ? -c : c);
}

num _num(String s) => num.parse(s.replaceAll(' ', '').replaceAll(',', '.'));

class _Item {
  _Item(this.name, this.cents);
  final String name;
  final int? cents;
  num? qty;
  int? unit;
}

class _Parsed {
  _Parsed(this.items, this.total, this.header);
  final List<_Item> items;
  final int? total;
  final String header;
}

String _strip(String s) {
  const chars = ' |_—-~.:;';
  var a = 0, b = s.length;
  while (a < b && chars.contains(s[a])) {
    a++;
  }
  while (b > a && chars.contains(s[b - 1])) {
    b--;
  }
  return s.substring(a, b);
}

_Parsed _parse(String text) {
  final items = <_Item>[];
  final header = StringBuffer();
  int? total;
  _Item? pending;
  for (final raw in text.split('\n')) {
    final line = _strip(raw.trim());
    if (line.isEmpty) continue;
    if (items.isEmpty) header.writeln(line);
    if (items.isNotEmpty && _stop.hasMatch(line) && !_end.hasMatch(line)) {
      break;
    }
    if (items.isNotEmpty && (_end.hasMatch(line) || _pay.hasMatch(line))) {
      final m = _price.allMatches(_digits(line)).toList();
      if (m.isNotEmpty) {
        total = _cents(m.last);
        break;
      }
      continue;
    }
    final q = _qty.firstMatch(line);
    if (q != null) {
      final target = pending ?? (items.isEmpty ? null : items.last);
      if (target != null) {
        target.qty = _num(q.group(1)!);
        target.unit = (_num(q.group(2)!) * 100).round();
        if (pending != null) {
          items.add(pending);
          pending = null;
        }
      }
      continue;
    }
    if (_skip.hasMatch(line)) continue;
    if (_looksLikeTotal(line, items)) {
      total = _cents(_price.allMatches(_digits(line)).last);
      break;
    }
    // Preis am Zeilenende (vor Steuerkennzeichen und €).
    final cut = math.max(0, line.length - 14);
    final tail = _digits(line.substring(cut));
    var m = _price.allMatches(tail).toList();
    if (m.isEmpty) m = _priceTax.allMatches(tail).toList();
    if (m.isEmpty) m = _priceNoSep.allMatches(line.substring(cut)).toList();
    var name = m.isEmpty ? line : line.substring(0, cut + m.last.start);
    name = name
        .replaceAll(RegExp(r'[^\w%.,/ \-ÄÖÜäöüß]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
    name = _strip(name.trim()).replaceFirst(
      RegExp(r'^(?:\S{1,3}\s+)?\d{5,}\s+'),
      '', // Artikelnummer vorn (Elektronikmärkte)
    );
    pending = null;
    if (_letters.allMatches(name).length < 3) continue;
    final item = _Item(name, m.isEmpty ? null : _cents(m.last));
    if (m.isNotEmpty) {
      items.add(item);
    } else {
      pending = item; // zählt nur, wenn eine Mengenzeile folgt
    }
  }
  return _Parsed(items, total, header.toString());
}

/// Falsch gelesene Summenzeile („Sunne 9,3l“): erstes Wort ähnlich wie
/// „Summe“ und Betrag mindestens so groß wie alle Positionen bis hier –
/// sonst wäre auch „SUPPE 1,99“ eine Summe.
bool _looksLikeTotal(String line, List<_Item> items) {
  if (items.length < 2) return false;
  final word = line.split(RegExp(r'\s+')).first;
  if (textSimilarity(word, 'SUMME') < 0.6) return false;
  final m = _price.allMatches(_digits(line)).toList();
  if (m.isEmpty) return false;
  final sum = items.fold(0, (s, i) => s + (i.cents ?? 0));
  return _cents(m.last) >= sum;
}

// ---------------------------------------------------------- Zusammenführen

/// Ähnlichkeit zweier Texte zwischen 0 und 1 (2 × LCS / Gesamtlänge), ohne
/// Groß-/Kleinschreibung.
double textSimilarity(String a, String b) {
  a = a.toUpperCase();
  b = b.toUpperCase();
  if (a.isEmpty && b.isEmpty) return 1;
  var prev = List<int>.filled(b.length + 1, 0);
  for (var i = 0; i < a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0);
    for (var j = 0; j < b.length; j++) {
      cur[j + 1] = a.codeUnitAt(i) == b.codeUnitAt(j)
          ? prev[j] + 1
          : math.max(prev[j + 1], cur[j]);
    }
    prev = cur;
  }
  return 2 * prev[b.length] / (a.length + b.length);
}

const _sameItem = 0.55;

/// Monotone Zuordnung zweier Positionslisten (Needleman-Wunsch): Paare
/// (Index in [a], Index in [b]).
List<(int, int)> _align(List<String> a, List<String> b) {
  final n = a.length, m = b.length;
  final sim = [
    for (var i = 0; i < n; i++)
      [for (var j = 0; j < m; j++) textSimilarity(a[i], b[j])],
  ];
  double gain(int i, int j) => sim[i][j] > _sameItem ? sim[i][j] : -1;
  final s = List.generate(n + 1, (_) => List<double>.filled(m + 1, 0));
  for (var i = 0; i < n; i++) {
    for (var j = 0; j < m; j++) {
      s[i + 1][j + 1] = math.max(
        math.max(s[i][j + 1], s[i + 1][j]),
        s[i][j] + gain(i, j),
      );
    }
  }
  final pairs = <(int, int)>[];
  var i = n, j = m;
  while (i > 0 && j > 0) {
    if (sim[i - 1][j - 1] > _sameItem &&
        s[i][j] == s[i - 1][j - 1] + sim[i - 1][j - 1]) {
      pairs.add((i - 1, j - 1));
      i--;
      j--;
    } else if (s[i][j] == s[i - 1][j]) {
      i--;
    } else {
      j--;
    }
  }
  return pairs.reversed.toList();
}

List<List<_Item>> _merge(List<_Parsed> runs) {
  final groups = <List<_Item>>[];
  for (final run in runs) {
    final items = run.items;
    final pairs = {
      for (final (gi, j) in _align(
        [for (final g in groups) g.first.name],
        [for (final it in items) it.name],
      ))
        j: gi,
    };
    final fresh = <(int, int, _Item)>[];
    for (var j = 0; j < items.length; j++) {
      final gi = pairs[j];
      if (gi != null) {
        groups[gi].add(items[j]);
      } else {
        // hinter der zuletzt zugeordneten Gruppe einfügen
        var prev = -1;
        for (final e in pairs.entries) {
          if (e.key < j && e.value > prev) prev = e.value;
        }
        fresh.add((prev, j, items[j]));
      }
    }
    fresh.sort((x, y) {
      final c = y.$1.compareTo(x.$1);
      return c != 0 ? c : y.$2.compareTo(x.$2);
    });
    for (final (prev, _, it) in fresh) {
      groups.insert(prev + 1, [it]);
    }
  }
  return groups;
}

K? _mostCommon<K>(Map<K, int> counts) {
  K? best;
  var n = 0;
  for (final e in counts.entries) {
    if (e.value > n) {
      best = e.key;
      n = e.value;
    }
  }
  return best;
}

Map<K, int> _count<K>(Iterable<K> xs) {
  final r = <K, int>{};
  for (final x in xs) {
    r[x] = (r[x] ?? 0) + 1;
  }
  return r;
}

Receipt _resolve(
  List<List<_Item>> groups,
  int? total,
  int need,
  String header,
) {
  final core = <ReceiptLine>[];
  final minor = <ReceiptLine>[];
  final all = <ReceiptLine>[];
  for (final cands in groups) {
    final prices = _count(cands.map((c) => c.cents).whereType<int>());
    final qtys = _count(
      cands.where((c) => c.qty != null).map((c) => (c.qty!, c.unit!)),
    );
    final q = _mostCommon(qtys);
    final line = ReceiptLine(
      text: _mostCommon(_count(cands.map((c) => c.name)))!,
      cents: null,
      quantity: q?.$1,
      unitCents: q?.$2,
      votes: cands.length,
      prices: prices,
    );
    _choosePrice(line);
    all.add(line);
    (cands.length >= need ? core : minor).add(line);
  }
  final taken = {...core};
  var sum = core.fold(0, (s, l) => s + (l.cents ?? 0));
  if (total != null && sum != total) {
    // Lücke schließen: eine Kernposition auf einen anderen gelesenen Preis
    // setzen und/oder Positionen aufnehmen, die nur eine Minderheit der
    // Läufe sah. Nur eine eindeutige Lösung wird übernommen.
    final usable = minor.where((l) => l.cents != null).toList();
    final swaps = <(ReceiptLine?, int)>[
      (null, 0),
      for (final l in core)
        for (final p in l.prices.keys)
          if (p != l.cents) (l, p - (l.cents ?? 0)),
    ];
    final found = <(List<ReceiptLine>, ReceiptLine?, int)>[];
    for (var k = 0; k <= math.min(usable.length, 4) && found.isEmpty; k++) {
      for (final extra in _combinations(usable, k)) {
        final add = extra.fold(0, (s, l) => s + l.cents!);
        for (final (l, d) in swaps) {
          if (sum + add + d == total) found.add((extra, l, d));
        }
      }
    }
    if (found.length == 1) {
      final (extra, l, d) = found.single;
      for (final e in extra) {
        e.check = ReceiptCheck.total;
        taken.add(e);
      }
      if (l != null) {
        l.cents = l.cents! + d;
        l.check = ReceiptCheck.total;
      }
    }
  }
  return Receipt(
    lines: [
      for (final l in all)
        if (taken.contains(l)) l,
    ],
    totalCents: total,
    header: header,
  );
}

void _choosePrice(ReceiptLine l) {
  final q = l.quantity, u = l.unitCents;
  if (q != null && u != null) {
    final expected = (q * u).round();
    if (l.prices.containsKey(expected)) {
      l.cents = expected;
      l.check = ReceiptCheck.quantity;
      return;
    }
    final n = l.count;
    if (n != null && l.prices.isNotEmpty) {
      // Einzelpreis vielleicht falsch gelesen: passt ein Kandidat zu n × x?
      final ok = {
        for (final e in l.prices.entries)
          if (e.key % n == 0) e.key: e.value,
      };
      if (ok.isNotEmpty) {
        l.cents = _mostCommon(ok);
        l.check = ReceiptCheck.quantity;
        return;
      }
    }
    if (l.prices.isEmpty) {
      l.cents = expected;
      l.check = ReceiptCheck.computed;
      return;
    }
  }
  l.cents = _mostCommon(l.prices);
}

Iterable<List<T>> _combinations<T>(List<T> xs, int k, [int start = 0]) sync* {
  if (k == 0) {
    yield [];
    return;
  }
  for (var i = start; i <= xs.length - k; i++) {
    for (final rest in _combinations(xs, k - 1, i + 1)) {
      yield [xs[i], ...rest];
    }
  }
}
