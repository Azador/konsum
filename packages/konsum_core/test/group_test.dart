import 'dart:math' as math;

import 'package:konsum_core/konsum_core.dart';
import 'package:test/test.dart';

/// Zwei Geräte derselben Gruppe mit steuerbarer Uhr.
class Setup {
  Setup() {
    alice = Group(HlcClock('alice', now: () => now), random: math.Random(1));
    bob = Group(HlcClock('bob', now: () => now), random: math.Random(2));
  }

  int now = 1000;
  late final Group alice;
  late final Group bob;

  /// Überträgt Änderungen von einem Gerät auf das andere.
  void send(List<Change> changes, Group to) => to.receive(changes);
}

void main() {
  late Setup s;
  late String listId;
  late String spaghetti;

  setUp(() {
    s = Setup();
    final list = s.alice.createList('Familie');
    final article = s.alice.createArticle('Spaghetti', defaultUnit: Units.pack);
    listId = list.id;
    spaghetti = article.id;
    s.send([...list.changes, ...article.changes], s.bob);
  });

  test('Artikel auf die Liste, abhaken, aufräumen', () {
    s.alice.addToList(listId, spaghetti, quantity: 2);
    expect(s.alice.entries(listId).single.unit, Units.pack);

    s.alice.setChecked(listId, spaghetti, true);
    s.alice.clearChecked(listId);

    expect(s.alice.entries(listId), isEmpty);
    expect(s.alice.article(spaghetti), isNotNull, reason: 'bleibt im Stamm');
    expect(s.alice.purchases.single.articleId, spaghetti);
  });

  test('Erneut hinzugefügter Artikel startet mit frischem Eintrag', () {
    s.alice.addToList(listId, spaghetti, quantity: 3, note: 'Vollkorn');
    s.alice.setChecked(listId, spaghetti, true);
    s.alice.clearChecked(listId);

    s.alice.addToList(listId, spaghetti);
    final entry = s.alice.entries(listId).single;
    expect(entry.quantity, isNull);
    expect(entry.note, isNull);
    expect(entry.checked, isFalse);
  });

  test('Gleichzeitige Änderungen verschiedener Felder bleiben erhalten', () {
    s.send(s.alice.addToList(listId, spaghetti), s.bob);

    final a = s.alice.updateEntry(listId, spaghetti, {'quantity': 4});
    final b = s.bob.updateEntry(listId, spaghetti, {'note': 'die dünnen'});
    s.send(a, s.bob);
    s.send(b, s.alice);

    for (final g in [s.alice, s.bob]) {
      final e = g.entries(listId).single;
      expect(e.quantity, 4);
      expect(e.note, 'die dünnen');
    }
  });

  test('Gleichzeitiges Ändern desselben Feldes: beide Geräte einigen sich', () {
    s.send(s.alice.addToList(listId, spaghetti), s.bob);

    final a = s.alice.updateEntry(listId, spaghetti, {'quantity': 1});
    final b = s.bob.updateEntry(listId, spaghetti, {'quantity': 5});
    s.send(a, s.bob);
    s.send(b, s.alice);

    expect(
      s.alice.entries(listId).single.quantity,
      s.bob.entries(listId).single.quantity,
    );
  });

  test('Gleichzeitiges Hinzufügen erzeugt kein Duplikat', () {
    final a = s.alice.addToList(listId, spaghetti, quantity: 1);
    final b = s.bob.addToList(listId, spaghetti, quantity: 2);
    s.send(a, s.bob);
    s.send(b, s.alice);

    expect(s.alice.entries(listId), hasLength(1));
    expect(s.bob.entries(listId), hasLength(1));
  });

  test('Reihenfolge und Wiederholung beim Empfang spielen keine Rolle', () {
    final changes = [
      ...s.alice.addToList(listId, spaghetti, quantity: 1),
      ...s.alice.updateEntry(listId, spaghetti, {'quantity': 2}),
      ...s.alice.setChecked(listId, spaghetti, true),
    ];
    final carol = Group(HlcClock('carol'));
    carol.receive(s.alice.replica.snapshot().reversed);
    carol.receive(changes.reversed);
    carol.receive(changes);

    final e = carol.entries(listId).single;
    expect(e.quantity, 2);
    expect(e.checked, isTrue);
  });

  test('Barcodes: mehrere pro Artikel, Zuordnung verschiebbar', () {
    final nudeln = s.alice.createArticle('Nudeln').id;
    s.alice.assignBarcode('4000000000001', spaghetti);
    s.alice.assignBarcode('4000000000002', spaghetti);
    expect(s.alice.barcodesOf(spaghetti), hasLength(2));
    expect(s.alice.articleForBarcode('4000000000002')!.id, spaghetti);

    s.alice.assignBarcode('4000000000002', nudeln);
    expect(s.alice.articleForBarcode('4000000000002')!.id, nudeln);
    expect(s.alice.barcodesOf(spaghetti), ['4000000000001']);
  });

  test('Artikel endgültig löschen entfernt Barcodes und Einträge', () {
    s.alice.assignBarcode('4000000000001', spaghetti);
    s.alice.addToList(listId, spaghetti);
    s.send(s.alice.deleteArticle(spaghetti), s.bob);

    expect(s.alice.article(spaghetti), isNull);
    expect(s.alice.articleForBarcode('4000000000001'), isNull);
    expect(s.alice.entries(listId), isEmpty);
    expect(s.bob.article(spaghetti), isNull);
  });

  test('Sortierung nach Ladenlayout', () {
    final obst = s.alice.createCategory('Obst').id;
    final kuehl = s.alice.createCategory('Kühlregal').id;
    final aepfel = s.alice.createArticle('Äpfel', categoryId: obst).id;
    final milch = s.alice.createArticle('Milch', categoryId: kuehl).id;
    s.alice.updateArticle(spaghetti, {'categoryId': null});
    final famila = s.alice.createShop('Famila').id;
    final kaufland = s.alice.createShop('Kaufland').id;
    s.alice.updateShop(famila, categoryOrder: [obst, kuehl]);
    s.alice.updateShop(kaufland, categoryOrder: [kuehl, obst]);
    for (final a in [aepfel, milch, spaghetti]) {
      s.alice.addToList(listId, a);
    }

    List<String> order(String shop) => [
      for (final e in s.alice.entries(listId, shopId: shop))
        s.alice.article(e.articleId)!.name,
    ];
    expect(order(famila), ['Äpfel', 'Milch', 'Spaghetti']);
    expect(order(kaufland), ['Milch', 'Äpfel', 'Spaghetti']);
  });

  test(
    'Vorschläge: häufig gekaufte zuerst, nichts was schon auf der Liste steht',
    () {
      final milch = s.alice.createArticle('Milch').id;
      final mehl = s.alice.createArticle('Mehl').id;
      for (var i = 0; i < 2; i++) {
        s.alice.addToList(listId, milch);
        s.alice.setChecked(listId, milch, true);
        s.alice.clearChecked(listId);
      }
      expect(s.alice.suggestions(listId).map((a) => a.id), [
        milch,
        mehl,
        spaghetti,
      ]);

      s.alice.addToList(listId, milch);
      expect(s.alice.suggestions(listId, query: 'm').map((a) => a.id), [mehl]);
    },
  );

  test('Change überlebt JSON-Rundreise', () {
    final c = s.alice
        .updateShop(s.alice.createShop('Famila').id, categoryOrder: ['x', 'y'])
        .single;
    final back = Change.fromJson(c.toJson());
    expect(back.hlc, c.hlc);
    expect(back.value, ['x', 'y']);
  });
}
