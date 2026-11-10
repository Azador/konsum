import 'dart:math' as math;

import 'package:konsum_core/konsum_core.dart';
import 'package:test/test.dart';

const day = Duration.millisecondsPerDay;

void main() {
  late int now;
  late Group g;
  late String listId;
  late String milk;

  /// Kauft [quantity] [unit] Milch am Tag [atDay].
  void buy(
    num atDay, {
    num? quantity = 4,
    String? unit = Units.litre,
    num? packSize,
    String? packUnit,
  }) {
    now = (atDay * day).round();
    g.addToList(listId, milk, quantity: quantity, unit: unit);
    if (packSize != null) {
      g.updateEntry(listId, milk, {'packSize': packSize, 'packUnit': packUnit});
    }
    g.setChecked(listId, milk, true);
    g.clearChecked(listId);
  }

  ListEntry? entry() =>
      g.entries(listId).where((e) => e.articleId == milk).firstOrNull;

  setUp(() {
    now = 0;
    g = Group(
      HlcClock('alice', now: () => now),
      random: math.Random(1),
      now: () => DateTime.fromMillisecondsSinceEpoch(now),
    )..automatic = true;
    listId = g.createList('Einkauf').id;
    milk = g.createArticle('Milch', defaultUnit: Units.litre).id;
  });

  test('Kauf speichert die Menge', () {
    buy(0);
    final p = g.purchases.single;
    expect(p.amount?.quantity, 4);
    expect(p.amount?.unit, Units.litre);
  });

  test('Verbrauch seit dem letzten Kauf, nicht ein ganzer Kauf', () {
    buy(0);
    buy(7);
    buy(14);
    now = (17.5 * day).round();
    final auto = g.autoAmountFor(milk)!;
    expect(auto.quantity, 2);
    expect(auto.unit, Units.litre);
    now = 21 * day;
    expect(g.autoAmountFor(milk)!.quantity, 4);
  });

  test('nie mehr als der größte bisherige Kauf', () {
    buy(0);
    buy(7);
    now = 100 * day;
    expect(g.autoAmountFor(milk)!.quantity, 4);
  });

  test('zu wenig Käufe: keine Automatik', () {
    buy(0);
    now = 5 * day;
    expect(g.autoAmountFor(milk), isNull);
    expect(g.autoAdd(), isEmpty);
  });

  test('Zähleinheiten auf ganze gerundet, über die Packungsgröße', () {
    // Je Woche 6 Packungen à 1 l.
    buy(0, quantity: 6, unit: Units.pack, packSize: 1, packUnit: Units.litre);
    buy(7, quantity: 6, unit: Units.pack, packSize: 1, packUnit: Units.litre);
    now = (10.5 * day).round();
    final auto = g.autoAmountFor(milk)!;
    expect(auto.quantity, 3);
    expect(auto.unit, Units.pack);
    expect(auto.packSize, 1);
    expect(auto.packUnit, Units.litre);
  });

  test('aus, ausgenommen oder alte Käufe ohne Menge: nichts', () {
    buy(0);
    buy(7);
    now = 10 * day;
    g.automatic = false;
    expect(g.autoAmountFor(milk), isNull);
    expect(entry(), isNull);
    g.automatic = true;
    g.updateArticle(milk, {'autoExcluded': true});
    expect(g.autoAmountFor(milk), isNull);
    expect(g.autoAdd(), isEmpty);

    // Käufe älterer Versionen ohne Einheit zählen nicht.
    final old = Group(HlcClock('bob'))..automatic = true;
    old.receive([
      for (final (i, millis) in [0, 7 * day].indexed)
        for (final f in {
          'articleId': milk,
          'listId': listId,
          'millis': millis,
        }.entries)
          Change(
            type: Types.purchase,
            id: 'p$i',
            field: f.key,
            value: f.value,
            hlc: Hlc(millis, 0, 'bob'),
          ),
    ]);
    expect(old.purchases.every((p) => p.amount == null), isTrue);
    expect(old.consumption(milk), isNull);
  });

  test('fällige Artikel kommen von selbst auf die Liste', () {
    buy(0);
    buy(7);
    now = 8 * day;
    expect(g.autoAdd(), isEmpty, reason: 'erst 0,6 l verbraucht');
    now = (10.5 * day).round();
    expect(g.autoAdd(), isNotEmpty);
    final e = entry()!;
    expect(e.autoAdded, isTrue);
    expect(e.quantity, isNull);
    expect(e.autoAmount?.quantity, 2);
    expect(e.effectiveAmount.quantity, 2);
    // Steht schon drauf: nicht noch einmal.
    expect(g.autoAdd(), isEmpty);
    // Von Hand neu gesetzt: nicht mehr automatisch.
    g.addToList(listId, milk);
    expect(entry()!.autoAdded, isFalse);
    g.removeFromList(listId, milk);
    g.autoAdd();
    // Die Menge wächst mit der Zeit.
    now = 12 * day;
    expect(entry()!.autoAmount?.quantity, closeTo(2.9, 1e-9));
  });

  test('von Hand: getrennte Mengen, die von Hand gilt', () {
    buy(0);
    buy(7);
    now = (10.5 * day).round();
    g.autoAdd();
    g.updateEntry(listId, milk, {'quantity': 3, 'basePrice': 100});
    var e = entry()!;
    expect(e.quantity, 3);
    expect(e.autoAmount?.quantity, 2);
    expect(e.effectiveAmount.quantity, 3);
    expect(e.totalCents, 300);

    // Weniger als die Automatik: Es gilt trotzdem die Menge von Hand.
    g.updateEntry(listId, milk, {'quantity': 1});
    e = entry()!;
    expect(e.effectiveAmount.quantity, 1);
    expect(e.totalCents, 100);
    g.setChecked(listId, milk, true);
    g.clearChecked(listId);
    expect(g.purchasesOf(articleId: milk).first.amount?.quantity, 1);
  });

  test('Ohne Menge von Hand gilt die der Automatik', () {
    buy(0);
    buy(7);
    now = (10.5 * day).round();
    g.autoAdd();
    g.updateEntry(listId, milk, {'basePrice': 100});
    expect(entry()!.totalCents, 200);
    g.setChecked(listId, milk, true);
    g.clearChecked(listId);
    final last = g.purchasesOf(articleId: milk).first;
    expect(last.amount?.quantity, 2);
    expect(last.amount?.unit, Units.litre);
  });

  test('Median: Ausreißer zählen kaum', () {
    // Montags KW 30–36: Reise in KW 32, Vereinstreffen in KW 36.
    for (final (week, litres) in [3, 3, 1, 4, 3, 3, 6].indexed) {
      buy(week * 7, quantity: litres);
    }
    final c = g.consumption(milk)!;
    expect(c.perDay * 7, closeTo(3, 1e-9));
    expect(c.typical, 3);
    expect(c.interval, const Duration(days: 7));
    // Montag KW 37.
    now = 7 * 7 * day;
    expect(g.autoAmountFor(milk)!.quantity, 3);
  });

  test('Käufe am selben Tag zählen als einer', () {
    buy(0, quantity: 2);
    buy(0.2, quantity: 2);
    buy(7);
    now = 14 * day;
    expect(g.consumption(milk)!.perDay * 7, closeTo(4, 1e-9));
    expect(g.autoAmountFor(milk)!.quantity, 4);
  });

  test('Kaufmenge nachträglich korrigieren', () {
    buy(0);
    buy(7);
    final first = g.purchasesOf(articleId: milk).last;
    g.updatePurchase(first.id, const Amount(quantity: 2, unit: Units.litre));
    expect(g.purchasesOf(articleId: milk).last.amount?.quantity, 2);
    now = 14 * day;
    expect(g.autoAmountFor(milk)!.quantity, 2);
  });

  test('weggenommen: erst nach einem üblichen Abstand wieder', () {
    buy(0);
    buy(7);
    now = (10.5 * day).round();
    g.autoAdd();
    g.removeFromList(listId, milk);
    now = 12 * day;
    expect(g.autoAdd(), isEmpty);
    now = (17.5 * day).round();
    expect(g.autoAdd(), isNotEmpty);
    expect(entry()!.autoAdded, isTrue);
  });

  test('von Hand gesetzte Einträge sind nicht automatisch', () {
    buy(0);
    buy(7);
    now = 10 * day;
    g.addToList(listId, milk);
    expect(entry()!.autoAdded, isFalse);
    expect(entry()!.autoAmount, isNotNull);
    g.removeFromList(listId, milk);
    // Kein Merken: Die Automatik darf ihn setzen, sobald er fällig ist.
    now = 11 * day;
    expect(g.autoAdd(), isNotEmpty);
  });

  test('Liste des letzten Kaufs gelöscht: erste vorhandene Liste', () {
    buy(0);
    buy(7);
    g.deleteList(listId);
    final other = g.createList('Andere').id;
    now = 11 * day;
    g.autoAdd();
    expect(g.entries(other).single.articleId, milk);
  });

  test('Käufe löschen', () {
    buy(0);
    buy(7);
    now = 8 * day;
    final bread = g.createArticle('Brot').id;
    g.addToList(listId, bread);
    g.setChecked(listId, bread, true);
    g.clearChecked(listId);
    expect(g.purchasesOf().length, 3);
    expect(g.purchasesOf().first.articleId, bread, reason: 'neueste zuerst');

    g.deletePurchase(g.purchasesOf(articleId: milk).first.id);
    expect(g.purchasesOf(articleId: milk).length, 1);
    g.deletePurchases(articleId: milk);
    expect(g.purchasesOf(articleId: milk), isEmpty);
    expect(g.purchasesOf().single.articleId, bread);
    g.deletePurchases();
    expect(g.purchases, isEmpty);
  });
}
