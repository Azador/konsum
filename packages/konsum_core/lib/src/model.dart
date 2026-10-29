/// Objekttypen, wie sie in [Change.type] stehen.
abstract final class Types {
  static const article = 'article';
  static const barcode = 'barcode';
  static const category = 'category';
  static const shop = 'shop';
  static const list = 'list';
  static const entry = 'entry';
  static const purchase = 'purchase';
  static const price = 'price';
}

/// Mengeneinheiten. Die Codes werden gespeichert, die Anzeigenamen liefert die App.
abstract final class Units {
  static const piece = 'pcs';
  static const gram = 'g';
  static const kilogram = 'kg';
  static const millilitre = 'ml';
  static const litre = 'l';
  static const pack = 'pack';
  static const can = 'can';
  static const bottle = 'bottle';
  static const bunch = 'bunch';

  static const all = [
    piece,
    gram,
    kilogram,
    millilitre,
    litre,
    pack,
    can,
    bottle,
    bunch,
  ];
}

class Article {
  const Article({
    required this.id,
    required this.name,
    this.categoryId,
    this.defaultUnit,
  });

  final String id;
  final String name;
  final String? categoryId;
  final String? defaultUnit;
}

class Category {
  const Category({required this.id, required this.name});

  final String id;
  final String name;
}

/// Laden mit eigener Reihenfolge der Kategorien.
class Shop {
  const Shop({
    required this.id,
    required this.name,
    required this.categoryOrder,
  });

  final String id;
  final String name;
  final List<String> categoryOrder;
}

class ShoppingList {
  const ShoppingList({required this.id, required this.name});

  final String id;
  final String name;
}

/// Ein Artikel auf einer Liste. Jeder Artikel steht höchstens einmal auf
/// einer Liste; die ID ist daher `listId/articleId`. Fügen zwei Personen
/// gleichzeitig denselben Artikel hinzu, entsteht so kein Duplikat.
class ListEntry {
  const ListEntry({
    required this.listId,
    required this.articleId,
    this.quantity,
    this.unit,
    this.note,
    this.price,
    this.checked = false,
  });

  final String listId;
  final String articleId;
  final num? quantity;
  final String? unit;

  /// Notiz für alle in der Gruppe. Private Notizen liegen getrennt
  /// beim jeweiligen Benutzer.
  final String? note;

  /// Preis für diesen Eintrag in Cent (für die eingetragene Menge).
  final int? price;
  final bool checked;

  String get id => entryId(listId, articleId);

  static String entryId(String listId, String articleId) =>
      '$listId/$articleId';
}

/// Ein abgeschlossener Kauf; Grundlage für Vorschläge und spätere Statistik.
/// Käufe werden nur angelegt, nie geändert.
class Purchase {
  const Purchase({
    required this.id,
    required this.articleId,
    required this.listId,
    required this.millis,
    this.shopId,
  });

  final String id;
  final String articleId;
  final String listId;
  final int millis;
  final String? shopId;
}

/// Ein beobachteter Preis eines Artikels, optional mit Menge und Laden.
/// Preise werden nur angelegt und gelöscht, nie geändert.
class PricePoint {
  const PricePoint({
    required this.id,
    required this.articleId,
    required this.cents,
    required this.millis,
    this.quantity,
    this.unit,
    this.shopId,
  });

  final String id;
  final String articleId;

  /// Preis in Cent für [quantity] [unit] (ohne Menge: für eine Einheit).
  final int cents;
  final int millis;
  final num? quantity;
  final String? unit;
  final String? shopId;

  /// Preis für eine Einheit [unit].
  double get unitCents =>
      cents / (quantity == null || quantity == 0 ? 1 : quantity!);
}
