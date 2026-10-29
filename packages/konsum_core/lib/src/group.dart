import 'dart:math' as math;

import 'hlc.dart';
import 'model.dart';
import 'replica.dart';

/// Daten einer Gruppe (Familie, Verein, …) mit Abfragen und Befehlen.
///
/// Befehle ändern den lokalen Zustand sofort und liefern die erzeugten
/// [Change]s, die das Sync-Backend an die anderen Geräte verteilt.
/// Eingehende Änderungen werden mit [receive] übernommen.
class Group {
  Group(this.clock, {Replica? replica, math.Random? random})
    : replica = replica ?? Replica(),
      _random = random ?? math.Random.secure();

  final HlcClock clock;
  final Replica replica;
  final math.Random _random;

  void receive(Iterable<Change> changes) {
    for (final c in changes) {
      clock.observe(c.hlc);
      replica.apply(c);
    }
  }

  // ---------------------------------------------------------------- Abfragen

  Article? article(String id) => _article(id, replica.get(Types.article, id));

  List<Article> get articles => _sortedByName([
    for (final id in replica.ids(Types.article))
      _article(id, replica.get(Types.article, id))!,
  ], (a) => a.name);

  Article? articleForBarcode(String code) {
    final articleId = replica.get(Types.barcode, code)?['articleId'] as String?;
    return articleId == null ? null : article(articleId);
  }

  List<String> barcodesOf(String articleId) => [
    for (final code in replica.ids(Types.barcode))
      if (replica.get(Types.barcode, code)!['articleId'] == articleId) code,
  ];

  List<Category> get categories => _sortedByName([
    for (final id in replica.ids(Types.category))
      Category(
        id: id,
        name: replica.get(Types.category, id)!['name'] as String? ?? '',
      ),
  ], (c) => c.name);

  List<Shop> get shops => _sortedByName([
    for (final id in replica.ids(Types.shop)) _shop(id)!,
  ], (s) => s.name);

  Shop? shop(String id) => _shop(id);

  List<ShoppingList> get lists => _sortedByName([
    for (final id in replica.ids(Types.list))
      ShoppingList(
        id: id,
        name: replica.get(Types.list, id)!['name'] as String? ?? '',
      ),
  ], (l) => l.name);

  /// Einträge einer Liste. Mit [shopId] in der Kategorie-Reihenfolge des
  /// Ladens (Artikel ohne bzw. mit unbekannter Kategorie am Ende), sonst
  /// alphabetisch.
  List<ListEntry> entries(String listId, {String? shopId}) {
    final result = <ListEntry>[];
    for (final id in replica.ids(Types.entry)) {
      final f = replica.get(Types.entry, id)!;
      if (f['listId'] != listId) continue;
      final articleId = f['articleId'] as String;
      if (article(articleId) == null) continue;
      result.add(
        ListEntry(
          listId: listId,
          articleId: articleId,
          quantity: f['quantity'] as num?,
          unit: f['unit'] as String?,
          note: f['note'] as String?,
          price: f['price'] as int?,
          checked: f['checked'] == true,
        ),
      );
    }
    final order = shopId == null
        ? const <String>[]
        : shop(shopId)?.categoryOrder ?? const <String>[];
    int rank(ListEntry e) {
      final i = order.indexOf(article(e.articleId)?.categoryId ?? '');
      return i < 0 ? order.length : i;
    }

    String name(ListEntry e) => article(e.articleId)!.name.toLowerCase();
    result.sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      return r != 0 ? r : name(a).compareTo(name(b));
    });
    return result;
  }

  List<Purchase> get purchases => [
    for (final id in replica.ids(Types.purchase))
      if (replica.get(Types.purchase, id) case final f?)
        Purchase(
          id: id,
          articleId: f['articleId'] as String,
          listId: f['listId'] as String,
          millis: f['millis'] as int,
          shopId: f['shopId'] as String?,
        ),
  ];

  /// Preishistorie, neueste zuerst; optional nur für einen Artikel und/oder Laden.
  List<PricePoint> priceHistory({String? articleId, String? shopId}) {
    final result = [
      for (final id in replica.ids(Types.price))
        if (replica.get(Types.price, id) case final f?)
          if ((articleId == null || f['articleId'] == articleId) &&
              (shopId == null || f['shopId'] == shopId))
            PricePoint(
              id: id,
              articleId: f['articleId'] as String,
              cents: f['cents'] as int,
              millis: f['millis'] as int,
              quantity: f['quantity'] as num?,
              unit: f['unit'] as String?,
              shopId: f['shopId'] as String?,
            ),
    ];
    result.sort((a, b) => b.millis.compareTo(a.millis));
    return result;
  }

  /// Letzter bekannter Preis, bevorzugt aus dem Laden [shopId].
  PricePoint? lastPrice(String articleId, {String? shopId}) {
    if (shopId != null) {
      final inShop = priceHistory(articleId: articleId, shopId: shopId);
      if (inShop.isNotEmpty) return inShop.first;
    }
    final any = priceHistory(articleId: articleId);
    return any.isEmpty ? null : any.first;
  }

  /// Preis eines Eintrags in Cent: der eingetragene Preis oder, falls keiner
  /// eingetragen ist, eine Schätzung aus dem letzten Preis bei gleicher
  /// Einheit. Null, wenn nichts bekannt ist.
  int? estimatedPrice(ListEntry entry, {String? shopId}) {
    if (entry.price != null) return entry.price;
    final last = lastPrice(entry.articleId, shopId: shopId);
    if (last == null || last.unit != entry.unit) return null;
    return (last.unitCents * (entry.quantity ?? 1)).round();
  }

  /// Summe der (geschätzten) Preise der offenen Einträge einer Liste.
  ({int cents, int unknown}) listTotal(String listId, {String? shopId}) {
    var cents = 0;
    var unknown = 0;
    for (final e in entries(listId).where((e) => !e.checked)) {
      final p = estimatedPrice(e, shopId: shopId);
      if (p == null) {
        unknown++;
      } else {
        cents += p;
      }
    }
    return (cents: cents, unknown: unknown);
  }

  /// Vorschläge zum Hinzufügen: Artikel, die zu [query] passen und noch nicht
  /// auf der Liste stehen, häufig gekaufte zuerst.
  List<Article> suggestions(String listId, {String query = ''}) {
    final q = query.trim().toLowerCase();
    final onList = {for (final e in entries(listId)) e.articleId};
    final counts = <String, int>{};
    for (final p in purchases) {
      counts[p.articleId] = (counts[p.articleId] ?? 0) + 1;
    }
    final result = [
      for (final a in articles)
        if (!onList.contains(a.id) && a.name.toLowerCase().contains(q)) a,
    ];
    result.sort((a, b) {
      final c = (counts[b.id] ?? 0).compareTo(counts[a.id] ?? 0);
      return c != 0 ? c : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return result;
  }

  // ----------------------------------------------------------------- Befehle

  /// Ergebnis eines Befehls, der ein Objekt anlegt.
  ({String id, List<Change> changes}) createArticle(
    String name, {
    String? categoryId,
    String? defaultUnit,
  }) {
    final id = _newId();
    return (
      id: id,
      changes: _write(Types.article, id, {
        'name': name,
        'categoryId': categoryId,
        'defaultUnit': defaultUnit,
        deletedField: false,
      }),
    );
  }

  List<Change> updateArticle(String id, Map<String, Object?> fields) =>
      _write(Types.article, id, fields);

  /// Entfernt den Artikel endgültig, samt Barcodes, Listeneinträgen,
  /// Käufen und Preishistorie.
  List<Change> deleteArticle(String id) => [
    ..._delete(Types.article, id),
    for (final code in barcodesOf(id)) ..._delete(Types.barcode, code),
    for (final type in [Types.entry, Types.purchase])
      for (final objectId in replica.ids(type).toList())
        if (replica.get(type, objectId)!['articleId'] == id)
          ..._delete(type, objectId),
    ...deletePriceHistory(articleId: id),
  ];

  /// Ordnet einen Barcode einem Artikel zu. Ein Barcode gehört immer genau
  /// einem Artikel; eine erneute Zuordnung verschiebt ihn.
  List<Change> assignBarcode(String code, String articleId) => _write(
    Types.barcode,
    code,
    {'articleId': articleId, deletedField: false},
  );

  List<Change> removeBarcode(String code) => _delete(Types.barcode, code);

  ({String id, List<Change> changes}) createCategory(String name) {
    final id = _newId();
    return (
      id: id,
      changes: _write(Types.category, id, {'name': name, deletedField: false}),
    );
  }

  List<Change> renameCategory(String id, String name) =>
      _write(Types.category, id, {'name': name});

  /// Löscht die Kategorie. Artikel behalten den Verweis und werden wie
  /// Artikel ohne Kategorie behandelt.
  List<Change> deleteCategory(String id) => _delete(Types.category, id);

  ({String id, List<Change> changes}) createShop(String name) {
    final id = _newId();
    return (
      id: id,
      changes: _write(Types.shop, id, {
        'name': name,
        'categoryOrder': <String>[],
        deletedField: false,
      }),
    );
  }

  List<Change> updateShop(
    String id, {
    String? name,
    List<String>? categoryOrder,
  }) =>
      _write(Types.shop, id, {'name': ?name, 'categoryOrder': ?categoryOrder});

  List<Change> deleteShop(String id) => _delete(Types.shop, id);

  ({String id, List<Change> changes}) createList(String name) {
    final id = _newId();
    return (
      id: id,
      changes: _write(Types.list, id, {'name': name, deletedField: false}),
    );
  }

  List<Change> renameList(String id, String name) =>
      _write(Types.list, id, {'name': name});

  List<Change> deleteList(String id) => [
    ..._delete(Types.list, id),
    for (final e in entries(id)) ..._delete(Types.entry, e.id),
  ];

  /// Setzt einen Artikel auf die Liste. Steht er schon darauf (oder stand
  /// er früher darauf), wird der Eintrag neu gesetzt.
  List<Change> addToList(
    String listId,
    String articleId, {
    num? quantity,
    String? unit,
    String? note,
  }) => _write(Types.entry, ListEntry.entryId(listId, articleId), {
    'listId': listId,
    'articleId': articleId,
    'quantity': quantity,
    'unit': unit ?? article(articleId)?.defaultUnit,
    'note': note,
    'price': null,
    'checked': false,
    deletedField: false,
  });

  /// Ändert einzelne Felder eines Eintrags (`quantity`, `unit`, `note`,
  /// `price`).
  List<Change> updateEntry(
    String listId,
    String articleId,
    Map<String, Object?> fields,
  ) => _write(Types.entry, ListEntry.entryId(listId, articleId), fields);

  List<Change> setChecked(String listId, String articleId, bool checked) =>
      _write(Types.entry, ListEntry.entryId(listId, articleId), {
        'checked': checked,
      });

  /// Entfernt einen Eintrag ohne ihn als gekauft zu verbuchen.
  List<Change> removeFromList(String listId, String articleId) =>
      _delete(Types.entry, ListEntry.entryId(listId, articleId));

  /// Verbucht alle abgehakten Einträge als Kauf (im Laden [shopId], falls
  /// bekannt) und entfernt sie von der Liste. Eingetragene Preise wandern in
  /// die Preishistorie.
  List<Change> clearChecked(String listId, {String? shopId}) {
    final changes = <Change>[];
    for (final e in entries(listId).where((e) => e.checked)) {
      final millis = clock.tick().millis;
      changes.addAll(
        _write(Types.purchase, _newId(), {
          'articleId': e.articleId,
          'listId': listId,
          'millis': millis,
          'shopId': shopId,
        }),
      );
      if (e.price != null) {
        changes.addAll(
          recordPrice(
            e.articleId,
            e.price!,
            quantity: e.quantity,
            unit: e.unit,
            shopId: shopId,
          ).changes,
        );
      }
      changes.addAll(_delete(Types.entry, e.id));
    }
    return changes;
  }

  /// Trägt einen Preis in die Historie ein.
  ({String id, List<Change> changes}) recordPrice(
    String articleId,
    int cents, {
    num? quantity,
    String? unit,
    String? shopId,
  }) {
    final id = _newId();
    return (
      id: id,
      changes: _write(Types.price, id, {
        'articleId': articleId,
        'cents': cents,
        'quantity': quantity,
        'unit': unit,
        'shopId': shopId,
        'millis': clock.tick().millis,
      }),
    );
  }

  List<Change> deletePrice(String id) => _delete(Types.price, id);

  /// Löscht die Preishistorie, optional nur für einen Artikel und/oder Laden.
  List<Change> deletePriceHistory({String? articleId, String? shopId}) => [
    for (final p in priceHistory(articleId: articleId, shopId: shopId))
      ..._delete(Types.price, p.id),
  ];

  // ------------------------------------------------------------------ intern

  List<Change> _write(String type, String id, Map<String, Object?> fields) {
    final hlc = clock.tick();
    final changes = [
      for (final f in fields.entries)
        Change(type: type, id: id, field: f.key, value: f.value, hlc: hlc),
    ];
    replica.applyAll(changes);
    return changes;
  }

  List<Change> _delete(String type, String id) =>
      _write(type, id, {deletedField: true});

  String _newId() => [
    for (var i = 0; i < 16; i++)
      _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();

  Article? _article(String id, Map<String, Object?>? f) => f == null
      ? null
      : Article(
          id: id,
          name: f['name'] as String? ?? '',
          categoryId: f['categoryId'] as String?,
          defaultUnit: f['defaultUnit'] as String?,
        );

  Shop? _shop(String id) {
    final f = replica.get(Types.shop, id);
    if (f == null) return null;
    return Shop(
      id: id,
      name: f['name'] as String? ?? '',
      categoryOrder: [
        ...(f['categoryOrder'] as List? ?? const []).cast<String>(),
      ],
    );
  }

  static List<T> _sortedByName<T>(List<T> items, String Function(T) name) =>
      items..sort(
        (a, b) => name(a).toLowerCase().compareTo(name(b).toLowerCase()),
      );
}
