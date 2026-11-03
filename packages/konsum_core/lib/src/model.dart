import 'amount.dart';

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

  /// Einstellungen der Gruppe; ein einziges Objekt mit der ID `group`.
  static const settings = 'settings';
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

  /// Gewicht und Volumen; alles andere sind Zähleinheiten.
  static const measures = [gram, kilogram, millilitre, litre];

  static bool isMeasure(String? unit) => measures.contains(unit);

  /// Möglicher Inhalt einer Packung: Gewicht, Volumen oder Stück (z. B. eine
  /// Packung mit 6 Eiern).
  static const packUnits = [...measures, piece];

  /// Ob [packUnit] als Inhalt je [unit] zählt. Stück je Stück ergibt keinen
  /// Sinn und wird ignoriert.
  static bool isPackUnitFor(String? packUnit, String? unit) =>
      isCount(unit) &&
      (isMeasure(packUnit) || (packUnit == piece && unit != piece));

  /// Zähleinheit (Stück, Packung, …), für die eine Packungsgröße passt.
  /// Ohne Einheit gilt Packung.
  static bool isCount(String? unit) => !isMeasure(unit);
}

class Article {
  const Article({
    required this.id,
    required this.name,
    this.categoryId,
    this.defaultUnit,
    this.packSize,
    this.packUnit,
  });

  final String id;
  final String name;
  final String? categoryId;
  final String? defaultUnit;

  /// Übliche Packungsgröße, z. B. 500 g; wird beim Hinzufügen übernommen.
  final num? packSize;
  final String? packUnit;
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
    this.packSize,
    this.packUnit,
    this.note,
    this.price,
    this.basePrice,
    this.checked = false,
  });

  final String listId;
  final String articleId;
  final num? quantity;

  /// Einheit der Menge; ohne Einheit gilt Packung.
  final String? unit;

  /// Inhalt einer Packung (eines Stücks, …) in g/kg/ml/l, nur bei
  /// Zähleinheiten.
  final num? packSize;
  final String? packUnit;

  /// Notiz für alle in der Gruppe. Private Notizen liegen getrennt
  /// beim jeweiligen Benutzer.
  final String? note;

  /// Eingetragener Preis in Cent für die Menge. Gilt nur, solange kein
  /// [basePrice] umgerechnet werden kann, siehe [totalCents].
  final int? price;

  /// Preis in Cent je Grundeinheit (kg, l, Stück, Packung, …).
  final num? basePrice;
  final bool checked;

  String get id => entryId(listId, articleId);

  /// Menge in der Grundeinheit, siehe [baseAmount].
  BaseAmount? get base => baseAmount(
    quantity: quantity,
    unit: unit,
    packSize: Units.isCount(unit) ? packSize : null,
    packUnit: packUnit,
  );

  /// Preis für die Menge: aus dem Grundpreis berechnet, wenn möglich, sonst
  /// der eingetragene Preis.
  int? get totalCents {
    final b = base;
    if (basePrice != null && b != null) return (basePrice! * b.amount).round();
    return price;
  }

  /// Preis je Grundeinheit: eingetragen oder aus dem Preis berechnet.
  num? get basePriceCents {
    if (basePrice != null) return basePrice;
    final p = price;
    return p == null ? null : pricePerBase(p, base);
  }

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
    this.packSize,
    this.packUnit,
    this.shopId,
  });

  final String id;
  final String articleId;

  /// Preis in Cent für [quantity] [unit] (ohne Menge: für eine Einheit).
  final int cents;
  final int millis;
  final num? quantity;
  final String? unit;
  final num? packSize;
  final String? packUnit;
  final String? shopId;

  BaseAmount? get base => baseAmount(
    quantity: quantity,
    unit: unit,
    packSize: Units.isCount(unit) ? packSize : null,
    packUnit: packUnit,
  );

  /// Preis in Cent je Grundeinheit, falls berechenbar.
  double? get basePriceCents => pricePerBase(cents, base);
}

/// Produktdaten zu einem Barcode, z. B. von Open Food Facts.
class ProductInfo {
  const ProductInfo({
    this.name,
    this.brand,
    this.quantity,
    this.imageUrl,
    this.nutriments = const {},
    this.nutriScore,
    this.productType,
  });

  final String? name;
  final String? brand;

  /// Packungsgröße als Text, z. B. „500 g“.
  final String? quantity;
  final String? imageUrl;

  /// Nährwerte je 100 g/ml, Schlüssel wie bei Open Food Facts
  /// (`energy-kcal`, `fat`, `saturated-fat`, `carbohydrates`, `sugars`,
  /// `proteins`, `salt`).
  final Map<String, num> nutriments;
  final String? nutriScore;

  /// Art des Produkts bei Open Food Facts und seinen Schwester-Datenbanken:
  /// `food`, `beauty`, `petfood` oder `product`.
  final String? productType;

  Map<String, Object?> toJson() => {
    'name': name,
    'brand': brand,
    'quantity': quantity,
    'imageUrl': imageUrl,
    'nutriments': nutriments,
    'nutriScore': nutriScore,
    'productType': productType,
  };

  factory ProductInfo.fromJson(Map<String, Object?> json) => ProductInfo(
    name: json['name'] as String?,
    brand: json['brand'] as String?,
    quantity: json['quantity'] as String?,
    imageUrl: json['imageUrl'] as String?,
    nutriments: {
      for (final e in (json['nutriments'] as Map? ?? const {}).entries)
        if (e.value is num) e.key as String: e.value as num,
    },
    nutriScore: json['nutriScore'] as String?,
    productType: json['productType'] as String?,
  );
}
