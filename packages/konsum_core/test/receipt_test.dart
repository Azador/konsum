import 'dart:math' as math;

import 'package:konsum_core/konsum_core.dart';
import 'package:test/test.dart';

// Erfundene Bons, die die Tücken echter OCR-Ausgaben nachbilden.

const _clean = '''
Frischmarkt
Hauptstr. 1
12345 Musterstadt
BIO VOLLMILCH 1L        2,58 € B
  (2 x 1,29 €/ST)
BAR PESTO ROSSO         2,49 € B
GUSTAVO PIZZA 400G      3,99 € B
PFAND 0,25              0,25 € A
Summe                   9,31 €
EC-Cash                 9,31 €
''';

// Preis der Milch unlesbar, Pizza falsch (8,99), Pfand fehlt ganz.
const _broken1 = '''
Frischmarkt
BIO VOLLMILCH 1L        2,M€eB
  (2 x 1,29 €/ST)
BAR PESTO ROSSO         2,49 € B
GUSTAVO PIZZA 400G      8,99€ B
Summe                   9,31 €
''';

// Summe unlesbar, aber Zahlungszeile da; Pizza richtig.
const _broken2 = '''
Frischmarkt
BIO VOLLMILCH 1L        2,58 € B
  (2 x 1,29 €/ST)
BAR PESTO ROSSO         2,49 € B
GUSTAVO PIZZA 400G      3,99 € 8
Sunne                   9,3l €
Geg. EC-Cash EUR        9,31
''';

void main() {
  group('Bon lesen', () {
    test('ein sauberer Lauf', () {
      final r = readReceipt([_clean]);
      expect(
        [for (final l in r.lines) l.text],
        [
          'BIO VOLLMILCH 1L',
          'BAR PESTO ROSSO', // „BAR“ ist hier keine Barzahlung
          'GUSTAVO PIZZA 400G', // „GUSTAVO“ enthält „UST“
          'PFAND 0,25',
        ],
      );
      expect([for (final l in r.lines) l.cents], [258, 249, 399, 25]);
      expect(r.lines.first.quantity, 2);
      expect(r.lines.first.unitCents, 129);
      expect(r.lines.first.check, ReceiptCheck.quantity);
      expect(r.totalCents, 931);
      expect(r.balanced, isTrue);
      expect(r.header, contains('Frischmarkt'));
    });

    test('mehrere fehlerhafte Läufe ergeben zusammen den richtigen Bon', () {
      final r = readReceipt([_broken1, _broken2, _clean]);
      expect(r.balanced, isTrue);
      expect([for (final l in r.lines) l.cents], [258, 249, 399, 25]);
    });

    test('Preis aus Mengenzeile, wenn der Zeilenpreis unlesbar ist', () {
      final r = readReceipt([_broken1]);
      final milk = r.lines.first;
      expect(milk.cents, 258);
      expect(milk.check, ReceiptCheck.computed);
    });

    test('Summenprüfung korrigiert einen Preis, wenn eindeutig', () {
      // Pizza: zweimal 8,99, einmal 3,99 gelesen; nur 3,99 passt zur Summe.
      final wrong = _clean.replaceAll('3,99 € B', '8,99 € B');
      final r = readReceipt([wrong, wrong, _clean]);
      final pizza = r.lines.firstWhere((l) => l.text.startsWith('GUSTAVO'));
      expect(pizza.cents, 399);
      expect(pizza.check, ReceiptCheck.total);
    });

    test('Position, die nur ein Lauf sah, nur wenn sie die Summe schließt', () {
      final r = readReceipt([_broken2, _broken2, _clean]);
      expect(r.lines.map((l) => l.text), contains('PFAND 0,25'));
      expect(r.balanced, isTrue);

      // Ohne Summe gibt es nichts zu schließen: Minderheit fällt weg.
      final noTotal = _clean.replaceAll(RegExp(r'Summe.*\n|EC-Cash.*\n'), '');
      final r2 = readReceipt([
        noTotal,
        noTotal.replaceAll(RegExp(r'PFAND.*\n'), ''),
        noTotal.replaceAll(RegExp(r'PFAND.*\n'), ''),
      ]);
      expect(r2.lines.map((l) => l.text), isNot(contains('PFAND 0,25')));
    });

    test('Steuerkennzeichen als 8 angehängt, Komma verloren', () {
      final r = readReceipt([
        '''
KAESE GERIEBEN          1,598 %
KETCHUP 300ML           229EB
Summe                   3,88 €
''',
      ]);
      expect([for (final l in r.lines) l.cents], [159, 229]);
      expect(r.balanced, isTrue);
    });

    test('Artikelnummer vorn wird entfernt', () {
      final r = readReceipt([
        '''
200719 Video-Kabel, USB-C-          46,99
1 x 18171551410 - KS03
Zu Zahlen                           46,99
''',
      ]);
      expect(r.lines.single.text, 'Video-Kabel, USB-C');
      expect(r.lines.single.cents, 4699);
    });
  });

  group('Zuordnung', () {
    late Group g;
    late Group other;
    late String milk, cheese, pizza, shop;

    setUp(() {
      g = Group(HlcClock('a', now: () => 1000), random: math.Random(1));
      other = Group(HlcClock('b', now: () => 1000), random: math.Random(2));
      final a1 = g.createArticle('Milch');
      final a2 = g.createArticle('old Amsterdam');
      final a3 = g.createArticle('Pizza');
      final s = g.createShop('Frischmarkt');
      milk = a1.id;
      cheese = a2.id;
      pizza = a3.id;
      shop = s.id;
      other.receive([
        ...a1.changes,
        ...a2.changes,
        ...a3.changes,
        ...s.changes,
      ]);
    });

    ReceiptLine line(String text, [int cents = 100]) =>
        ReceiptLine(text: text, cents: cents);

    test('Abkürzung als Wortanfang', () {
      final m = ReceiptMatcher(g, shopId: shop);
      expect(m.match(line('BIO VOLLMILCH 1L')).articleId, milk);
      expect(m.match(line('JT BIO MIL.3,8% 1L')).articleId, milk);
      expect(m.match(line('GUSTAVO PIZZA 400G')).confident, isTrue);
      expect(m.match(line('OA ORIGINAL SCHEIB')).articleId, isNull);
    });

    test('Name des Produkts aus Open Food Facts hilft', () {
      g.assignBarcode('8712345678901', cheese);
      g.setProductInfo(
        '8712345678901',
        const ProductInfo(name: 'Original Scheiben', brand: 'Old Amsterdam'),
      );
      final m = ReceiptMatcher(g, shopId: shop);
      final r = m.match(line('OA ORIGINAL SCHEIB'));
      expect(r.articleId, cheese);
      expect(r.confident, isTrue);
    });

    test('gelernte Zuordnung je Laden, auf allen Geräten gleich', () {
      final c1 = g.learnReceiptName('OA ORIGINAL SCHEIB', cheese, shopId: shop);
      // Das andere Gerät lernt dasselbe mit leicht anderem OCR-Text.
      final c2 = other.learnReceiptName(
        'OA ORIGINAL SCHEIB.',
        cheese,
        shopId: shop,
      );
      g.receive(c2);
      other.receive(c1);
      expect(g.receiptNames().length, 1);
      expect(other.receiptNames().single.id, g.receiptNames().single.id);

      final r = ReceiptMatcher(
        g,
        shopId: shop,
      ).match(line('OA 0RIGINAL SCHEIB'));
      expect(r.articleId, cheese);
      expect(r.learned, isTrue);
    });

    test('gelernt ignorieren', () {
      g.learnReceiptName('PFAND 0,25', null, shopId: shop);
      final r = ReceiptMatcher(g, shopId: shop).match(line('PFAND 0,25'));
      expect(r.ignore, isTrue);
      expect(r.articleId, isNull);
    });

    test('Artikel des Einkaufs werden bevorzugt', () {
      final m = ReceiptMatcher(g, shopId: shop, trip: {pizza});
      expect(m.match(line('STEINOFEN PIZ')).articleId, pizza);
    });

    test('Artikel löschen vergisst seine Bonnamen', () {
      g.learnReceiptName('OA ORIGINAL SCHEIB', cheese, shopId: shop);
      g.deleteArticle(cheese);
      expect(g.receiptNames(), isEmpty);
    });

    test('Laden aus dem Bonkopf', () {
      g.createShop('Kaufmarkt');
      expect(shopFromReceipt(g, 'frischmarkt\nHauptstr. 1')?.id, shop);
      expect(shopFromReceipt(g, 'Anderer Laden'), isNull);
    });
  });

  group('Übernehmen', () {
    var clock = 1000000;
    late Group g;
    late String list, milk, ham, shop;

    setUp(() {
      clock = 1000000;
      g = Group(
        HlcClock('a', now: () => clock),
        random: math.Random(3),
        now: () => DateTime.fromMillisecondsSinceEpoch(clock),
      );
      list = g.createList('Einkauf').id;
      milk = g.createArticle('Milch', defaultUnit: Units.litre).id;
      ham = g.createArticle('Bresaola', defaultUnit: Units.pack).id;
      shop = g.createShop('Frischmarkt').id;
    });

    test('abgehakter Eintrag bekommt Preis und Stückzahl vom Bon', () {
      g.addToList(list, ham, quantity: 1);
      g.setChecked(list, ham, true);
      expect(g.receiptTrip(listId: list), {ham});
      g.applyReceipt(
        [
          const ReceiptAssignment(
            text: 'Ital. Bresaola',
            cents: 602,
            quantity: 2,
            articleId: null,
          ),
          ReceiptAssignment(
            text: 'BRESAOLA',
            cents: 1196,
            quantity: 2,
            articleId: ham,
          ),
        ],
        shopId: shop,
        listId: list,
      );
      final e = g.entries(list).single;
      expect(e.price, 1196);
      expect(e.quantity, 2);
      // Erst beim Aufräumen in die Historie.
      expect(g.priceHistory(), isEmpty);
      g.clearChecked(list, shopId: shop);
      expect(g.lastPrice(ham)!.cents, 1196);
    });

    test(
      'nach dem Aufräumen: geschätzten Preis ersetzen, Menge korrigieren',
      () {
        g.recordPrice(ham, 500, quantity: 1, unit: Units.pack, shopId: shop);
        clock += 7 * 24 * 3600 * 1000;
        g.addToList(list, ham, quantity: 1);
        g.setChecked(list, ham, true);
        g.clearChecked(list, shopId: shop); // schätzt 5,00 €
        expect(g.priceHistory(articleId: ham).length, 2);
        clock += 3600 * 1000;
        g.applyReceipt(
          [
            ReceiptAssignment(
              text: 'BRESAOLA',
              cents: 598,
              quantity: 2,
              articleId: ham,
            ),
          ],
          shopId: shop,
          listId: list,
        );
        final prices = g.priceHistory(articleId: ham);
        expect(prices.length, 2); // alte Woche + Bon, Schätzung weg
        expect(prices.first.cents, 598);
        expect(prices.first.quantity, 2);
        expect(g.purchasesOf(articleId: ham).single.amount!.quantity, 2);
      },
    );

    test('zwei Zeilen desselben Artikels werden zusammengezählt', () {
      g.applyReceipt([
        ReceiptAssignment(
          text: 'Ital. Bresaola',
          cents: 602,
          quantity: 0.09,
          articleId: ham,
        ),
        ReceiptAssignment(
          text: 'Ital. Bresaola',
          cents: 582,
          quantity: 0.087,
          articleId: ham,
        ),
      ], shopId: shop);
      final p = g.lastPrice(ham)!;
      expect(p.cents, 1184);
      expect(p.unit, Units.kilogram);
      expect(p.quantity, closeTo(0.177, 1e-9));
    });

    test('ohne Einkauf: neuer Preis mit Stückzahl, Zuordnung gelernt', () {
      g.applyReceipt([
        ReceiptAssignment(
          text: 'JT BIO MIL.3,8% 1L',
          cents: 270,
          quantity: 2,
          articleId: milk,
        ),
        const ReceiptAssignment(text: 'PFAND', cents: 25, ignore: true),
      ], shopId: shop);
      final p = g.lastPrice(milk)!;
      expect(p.cents, 270);
      expect(p.quantity, 2);
      expect(p.unit, Units.pack); // Liter ist keine Zähleinheit
      expect(p.shopId, shop);
      final names = {for (final n in g.receiptNames()) n.text: n.articleId};
      expect(names, {'JT BIO MIL.3,8% 1L': milk, 'PFAND': null});
    });
  });
}
