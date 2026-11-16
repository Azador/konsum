/// Bonzeilen den Artikeln einer Gruppe zuordnen.
///
/// Bons kürzen stark ab („OA ORIGINAL SCHEIB“ für old Amsterdam), deshalb
/// reicht der Name allein selten. Signale, stärkstes zuerst:
/// 1. gelernte Zuordnung desselben Ladens ([Group.receiptNames]),
/// 2. Name des Artikels und der Produkte seiner Barcodes (Open Food Facts
///    hat meist den langen Namen samt Marke), als Wort oder Wortanfang,
/// 3. Artikel dieses Einkaufs (abgehakt oder gerade gekauft),
/// 4. Preis passt zum zuletzt bezahlten.
library;

import 'group.dart';
import 'model.dart';
import 'receipt.dart';
import 'replica.dart';

/// Vorschlag für eine Bonzeile.
class ReceiptMatch {
  const ReceiptMatch({
    this.articleId,
    this.score = 0,
    this.learned = false,
    this.ignore = false,
  });

  /// Vorgeschlagener Artikel; null, wenn nichts passt (oder [ignore]).
  final String? articleId;
  final double score;

  /// Aus einer gelernten Zuordnung.
  final bool learned;

  /// Gelernt: diese Zeile ignorieren (Pfand, Tüte, …).
  final bool ignore;

  /// Ab hier gilt ein Vorschlag als sicher genug, um ihn vorzubelegen.
  static const threshold = 0.6;

  bool get confident => learned || score >= threshold;
}

/// Großbuchstaben und Ziffern, Umlaute ausgeschrieben.
String normalizeReceiptText(String s) =>
    _fold(s.toUpperCase()).replaceAll(RegExp(r'[^A-Z0-9]'), '');

String _fold(String s) => s
    .replaceAll('Ä', 'AE')
    .replaceAll('Ö', 'OE')
    .replaceAll('Ü', 'UE')
    .replaceAll('ä', 'ae')
    .replaceAll('ö', 'oe')
    .replaceAll('ü', 'ue')
    .replaceAll('ß', 'ss')
    .replaceAll(RegExp('[èéê]'), 'e')
    .replaceAll(RegExp('[ÈÉÊ]'), 'E');

List<String> _words(String s) =>
    _fold(s.toLowerCase())
        .split(RegExp(r'[^a-z0-9]+'))
        .where((w) => w.isNotEmpty)
        .toList();

/// Wörter, die auf vielen Produkten stehen und nichts unterscheiden.
const _generic = {
  'bio',
  'classic',
  'klassik',
  'frisch',
  'fein',
  'extra',
  'mit',
  'und',
  'ohne',
  'der',
  'die',
  'das',
  'von',
  'aus',
  'nach',
  'art',
  'premium',
  'natur',
  'pack',
  'stueck',
};

/// Anteil der Wörter von [name], die auf der Bonzeile als Wort oder als
/// Wortanfang vorkommen (MIL → Milch, SCHEI → Scheiben).
double receiptNameScore(String line, String name) {
  final bw = [
    for (final w in _words(line))
      if (!RegExp(r'^\d+$').hasMatch(w)) w,
  ];
  final aw = [
    for (final w in _words(name))
      if (w.length > 1 && !_generic.contains(w)) w,
  ];
  if (aw.isEmpty || bw.isEmpty) return 0;
  var hit = 0.0;
  for (final a in aw) {
    var best = 0.0;
    for (final b in bw) {
      double s;
      if (a == b) {
        s = 1;
      } else if (b.length >= 3 && a.startsWith(b)) {
        s = 0.6 + 0.4 * b.length / a.length;
      } else if (a.length >= 4 && b.startsWith(a)) {
        s = 0.9;
      } else if (a.length >= 5 && b.contains(a)) {
        s = 0.7;
      } else {
        s = 0;
      }
      if (s > best) best = s;
    }
    hit += best;
  }
  return hit / aw.length;
}

/// Ordnet Bonzeilen Artikeln zu.
class ReceiptMatcher {
  ReceiptMatcher(this.group, {this.shopId, this.trip = const {}})
    : _learned = group.receiptNames(shopId: shopId),
      _learnedElsewhere = shopId == null
          ? const []
          : group.receiptNames().where((n) => n.shopId != shopId).toList();

  final Group group;
  final String? shopId;

  /// Artikel dieses Einkaufs (abgehakt oder gerade gekauft).
  final Set<String> trip;

  final List<ReceiptName> _learned;
  final List<ReceiptName> _learnedElsewhere;

  late final Map<String, List<String>> _texts = {
    for (final a in group.articles)
      a.id: [
        a.name,
        for (final code in group.barcodesOf(a.id))
          if (group.productInfo(code) case final p?) ...[
            if (p.name != null) p.name!,
            if (p.name != null && p.brand != null) '${p.brand} ${p.name}',
          ],
      ],
  };

  ReceiptMatch match(ReceiptLine line) {
    final learned = _lookup(line.text);
    if (learned != null) {
      final id = learned.articleId;
      if (id == null) return const ReceiptMatch(learned: true, ignore: true);
      if (group.article(id) != null) {
        return ReceiptMatch(articleId: id, score: 2, learned: true);
      }
    }
    String? best;
    var bestScore = 0.0;
    for (final e in _texts.entries) {
      final s = score(line, e.key, e.value);
      if (s > bestScore) {
        best = e.key;
        bestScore = s;
      }
    }
    return bestScore < 0.3
        ? const ReceiptMatch()
        : ReceiptMatch(articleId: best, score: bestScore);
  }

  /// Punkte für Artikel [articleId] mit den Namen [texts].
  double score(ReceiptLine line, String articleId, List<String> texts) {
    var s = 0.0;
    for (final t in texts) {
      final n = receiptNameScore(line.text, t);
      if (n > s) s = n;
    }
    final inTrip = trip.contains(articleId);
    if (inTrip) s += 0.3;
    // Der Preis allein trifft zu oft zufällig; er zählt nur als Bestätigung.
    if (s > 0.2 && line.cents != null) {
      final last = group.lastPrice(articleId, shopId: shopId);
      if (last != null) {
        final lastUnit = last.cents / (last.quantity ?? 1);
        final unit = line.unitCents ?? line.cents! / (line.count ?? 1);
        final ratio = unit / (lastUnit == 0 ? 1 : lastUnit);
        if (ratio >= 0.85 && ratio <= 1.18) s += 0.2;
      }
    }
    return s;
  }

  ReceiptName? _lookup(String text) {
    ReceiptName? find(List<ReceiptName> names, double min) {
      ReceiptName? best;
      var bestSim = min;
      final norm = normalizeReceiptText(text);
      for (final n in names) {
        final sim = textSimilarity(norm, normalizeReceiptText(n.text));
        if (sim >= bestSim) {
          best = n;
          bestSim = sim;
        }
      }
      return best;
    }

    return find(_learned, 0.85) ?? find(_learnedElsewhere, 0.92);
  }
}

/// Laden, dessen Name im Kopf des Bons steht. Unscharf, weil Logos oft
/// schlecht gelesen werden („famila“ → „fanila“).
Shop? shopFromReceipt(Group group, String header) {
  final words = [
    for (final w in header.split(RegExp(r'\s+')))
      if (normalizeReceiptText(w) case final n when n.length >= 3) n,
  ];
  final joined = normalizeReceiptText(header);
  Shop? best;
  var bestSim = 0.0;
  for (final s in group.shops) {
    final n = normalizeReceiptText(s.name);
    if (n.length < 3) continue;
    var sim = joined.contains(n) ? 1.0 : 0.0;
    for (final w in words) {
      final x = textSimilarity(w, n);
      if (x > sim) sim = x;
    }
    if (sim >= 0.8 && sim > bestSim) {
      best = s;
      bestSim = sim;
    }
  }
  return best;
}

/// Eine geprüfte Bonzeile zum Übernehmen.
class ReceiptAssignment {
  const ReceiptAssignment({
    required this.text,
    required this.cents,
    this.articleId,
    this.quantity,
    this.ignore = false,
  });

  factory ReceiptAssignment.of(
    ReceiptLine line, {
    String? articleId,
    bool ignore = false,
  }) => ReceiptAssignment(
    text: line.text,
    cents: line.cents ?? 0,
    articleId: articleId,
    quantity: line.quantity,
    ignore: ignore,
  );

  final String text;
  final int cents;

  /// Zugeordneter Artikel; null: nichts übernehmen.
  final String? articleId;

  /// Menge laut Bon: ganze Zahl = Stück, sonst Gewicht in kg.
  final num? quantity;

  /// Diese Zeile künftig ignorieren (Pfand, Tüte, …).
  final bool ignore;
}

/// Kassenbon auf die Daten der Gruppe anwenden.
extension ReceiptGroup on Group {
  /// Wie lange nach dem Aufräumen ein Kauf noch zum Bon gehört.
  static const tripWindow = Duration(hours: 12);

  /// Artikel dieses Einkaufs: abgehakt auf [listId] oder gerade gekauft.
  Set<String> receiptTrip({String? listId}) {
    final since = now().subtract(tripWindow).millisecondsSinceEpoch;
    return {
      if (listId != null)
        for (final e in entries(listId))
          if (e.checked) e.articleId,
      for (final p in purchases)
        if (p.millis >= since) p.articleId,
    };
  }

  /// Übernimmt die Preise und lernt die Zuordnungen (siehe [ReceiptMatcher]).
  List<Change> applyReceipt(
    List<ReceiptAssignment> lines, {
    String? shopId,
    String? listId,
  }) {
    final changes = <Change>[];
    // Lernen, auch was ignoriert werden soll.
    for (final l in lines) {
      if (l.articleId != null || l.ignore) {
        changes.addAll(
          learnReceiptName(
            l.text,
            l.ignore ? null : l.articleId,
            shopId: shopId,
          ),
        );
      }
    }
    // Je Artikel zusammenzählen (dieselbe Ware in zwei Zeilen).
    final byArticle = <String, List<ReceiptAssignment>>{};
    for (final l in lines) {
      if (!l.ignore && l.articleId != null && article(l.articleId!) != null) {
        byArticle.putIfAbsent(l.articleId!, () => []).add(l);
      }
    }
    final since = now().subtract(tripWindow).millisecondsSinceEpoch;
    for (final MapEntry(key: articleId, value: ls) in byArticle.entries) {
      final cents = ls.fold(0, (s, l) => s + l.cents);
      final qs = [for (final l in ls) l.quantity];
      final allCounts = qs.every((q) => q != null && q == q.roundToDouble());
      final count = allCounts
          ? qs.fold<num>(0, (s, q) => s + q!).round()
          : null;
      final weightKg = !allCounts && qs.every((q) => q != null)
          ? qs.fold<num>(0, (s, q) => s + q!)
          : null;

      final entry = listId == null
          ? null
          : entries(listId)
                .where((e) => e.articleId == articleId && e.checked)
                .firstOrNull;
      if (entry != null) {
        final unit = entry.unit ?? Units.pack;
        changes.addAll(
          updateEntry(listId!, articleId, {
            'price': cents,
            'basePrice': null,
            if (count != null && Units.isCount(unit)) 'quantity': count,
          }),
        );
        continue;
      }

      final bought = purchasesOf(articleId: articleId)
          .where((p) => p.millis >= since)
          .toList();
      if (bought.isNotEmpty) {
        final p = bought.first; // neuester
        // Den beim Aufräumen geschätzten Preis ersetzen.
        for (final old in priceHistory(articleId: articleId)) {
          if (old.millis >= p.millis - 60 * 1000) {
            changes.addAll(deletePrice(old.id));
          }
        }
        var amount = p.amount ?? const Amount();
        final unit = amount.unit ?? Units.pack;
        if (count != null && Units.isCount(unit) && amount.quantity != count) {
          amount = Amount(
            quantity: count,
            unit: unit,
            packSize: amount.packSize,
            packUnit: amount.packUnit,
          );
          changes.addAll(updatePurchase(p.id, amount));
        }
        changes.addAll(
          recordPrice(
            articleId,
            cents,
            quantity: amount.quantity,
            unit: amount.unit,
            packSize: amount.packSize,
            packUnit: amount.packUnit,
            shopId: shopId ?? p.shopId,
          ).changes,
        );
        continue;
      }

      final a = article(articleId)!;
      final countUnit = Units.isCount(a.defaultUnit)
          ? a.defaultUnit ?? Units.pack
          : Units.pack;
      changes.addAll(
        recordPrice(
          articleId,
          cents,
          quantity: count ?? weightKg,
          unit: count != null
              ? countUnit
              : weightKg != null
              ? Units.kilogram
              : null,
          packSize: count != null ? a.packSize : null,
          packUnit: count != null ? a.packUnit : null,
          shopId: shopId,
        ).changes,
      );
    }
    return changes;
  }
}
