import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:konsum/state/app_state.dart';
import 'package:konsum_core/konsum_core.dart';

/// Verbreitete Telefone in logischen Pixeln (dp/pt), für Layout-Prüfungen.
const devices = <({String name, Size size, double ratio})>[
  (name: 'Pixel 7a', size: Size(411.4, 914.3), ratio: 2.625),
  (name: 'Galaxy S24', size: Size(360, 780), ratio: 3),
  (name: 'Galaxy A55', size: Size(384, 832), ratio: 2.8125),
  (name: 'iPhone 15', size: Size(393, 852), ratio: 3),
];

/// Schriftgrößen: normal, die des Pixels (Android „etwas größer“) und groß.
const textScales = [1.0, 1.15, 1.3];

/// Lädt Roboto, damit Texte so breit sind wie auf dem Gerät; die
/// Testschrift von flutter_test hat breitere Zeichen.
Future<void> loadRoboto() async {
  final loader = FontLoader('Roboto')
    ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Roboto-Medium.ttf'));
  await loader.load();
}

/// Namen der Beispielartikel, die in der Liste stehen.
abstract final class Sample {
  static const ham = 'Kochschinken';
  static const water = 'Mineralwasser Medium';
  static const beer = 'Pils';
  static const milk = 'Bio Vollmilch 3,8 % länger haltbar';
  static const mince = 'Hackfleisch gemischt';
  static const salt = 'Salz grobkörnig';
  static const tomatoes = 'Tomaten gehackt';
}

/// Füllt die aktuelle Gruppe mit einer Liste, die die engen Stellen der
/// Oberfläche ausreizt: lange Namen, Notizen, Preise je Packung, lose Ware,
/// geschätzte Preise aus der Historie, ein abgehakter Eintrag, Käufe.
void seedSampleData(AppState state) {
  final session = state.currentGroup!;
  final g = session.group;
  final listId = state.currentListId!;
  final categories = g.categories;

  final famila = g.createShop('Famila');
  session.apply(famila.changes);

  String article(
    String name, {
    String? unit,
    num? packSize,
    String? packUnit,
    int category = 0,
  }) {
    final a = g.createArticle(
      name,
      categoryId: categories[category % categories.length].id,
      defaultUnit: unit,
      packSize: packSize,
      packUnit: packUnit,
    );
    session.apply(a.changes);
    return a.id;
  }

  void add(
    String id, {
    num? quantity,
    String? unit,
    Map<String, Object?>? set,
  }) {
    session.apply([
      ...g.addToList(listId, id, quantity: quantity, unit: unit),
      if (set != null) ...g.updateEntry(listId, id, set),
    ]);
  }

  final ham = article(
    Sample.ham,
    unit: Units.pack,
    packSize: 100,
    packUnit: Units.gram,
    category: 1,
  );
  // Früherer Kauf mit Preis: Käufe-Seite und Schätzung „≈“.
  add(ham, quantity: 1, set: {'price': 259, 'checked': true});
  session.apply(g.clearChecked(listId, shopId: famila.id));
  add(ham, quantity: 2);

  final water = article(
    Sample.water,
    unit: Units.bottle,
    packSize: 750,
    packUnit: Units.millilitre,
    category: 2,
  );
  add(water, quantity: 6, set: {'basePrice': 65});

  final beer = article(
    Sample.beer,
    unit: Units.crate,
    packSize: 20,
    packUnit: Units.bottle,
    category: 2,
  );
  add(beer, quantity: 2, set: {'basePrice': 85});

  final milk = article(
    Sample.milk,
    unit: Units.pack,
    packSize: 1,
    packUnit: Units.litre,
    category: 3,
  );
  add(
    milk,
    quantity: 3,
    set: {
      'basePrice': 119,
      'note': 'die mit dem blauen Deckel, nicht die H-Milch',
    },
  );

  final mince = article(Sample.mince, unit: Units.gram, category: 1);
  add(mince, quantity: 500, set: {'basePrice': 899});

  add(article(Sample.salt, unit: Units.pack, category: 4), quantity: 1);

  final tomatoes = article(
    Sample.tomatoes,
    unit: Units.can,
    packSize: 400,
    packUnit: Units.gram,
    category: 4,
  );
  add(tomatoes, quantity: 2, set: {'basePrice': 197.5, 'checked': true});

  state.selectShop(session, famila.id);
}

/// Prüft, dass jeder Text unter [finder] in eine Zeile passt.
void expectSingleLine(WidgetTester tester, Finder finder, {String? reason}) {
  for (final element in finder.evaluate()) {
    final paragraph = element.renderObject;
    if (paragraph is! RenderParagraph) continue;
    final line = paragraph.getFullHeightForCaret(const TextPosition(offset: 0));
    expect(
      paragraph.size.height,
      lessThan(line * 1.5),
      reason:
          '„${paragraph.text.toPlainText()}“ bricht um'
          '${reason == null ? '' : ' ($reason)'}',
    );
  }
}
