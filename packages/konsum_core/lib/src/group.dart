import 'dart:math' as math;

import 'amount.dart';
import 'hlc.dart';
import 'model.dart';
import 'replica.dart';

/// Daten einer Gruppe (Familie, Verein, …) mit Abfragen und Befehlen.
///
/// Befehle ändern den lokalen Zustand sofort und liefern die erzeugten
/// [Change]s, die das Sync-Backend an die anderen Geräte verteilt.
/// Eingehende Änderungen werden mit [receive] übernommen.
class Group {
  Group(
    this.clock, {
    Replica? replica,
    math.Random? random,
    DateTime Function()? now,
  }) : replica = replica ?? Replica(),
       _random = random ?? math.Random.secure(),
       now = now ?? DateTime.now;

  final HlcClock clock;
  final Replica replica;
  final math.Random _random;

  /// Uhr für die Automatik; in Tests ersetzbar.
  final DateTime Function() now;

  /// Automatik für wiederkehrende Artikel an (eine Einstellung des Geräts,
  /// nicht der Gruppe): Einträge bekommen eine [ListEntry.autoAmount],
  /// [autoAdd] setzt fällige Artikel auf die Liste.
  bool automatic = false;

  void receive(Iterable<Change> changes) {
    for (final c in changes) {
      clock.observe(c.hlc);
      replica.apply(c);
    }
  }

  // ----------------------------------------------------------- Aufbewahrung

  /// Vorgabe für [retentionMonths].
  static const defaultRetentionMonths = 6;

  static const _settingsId = 'group';

  /// Wie viele Monate Käufe und Grabsteine aufbewahrt werden; 0 = ohne
  /// automatisches Löschen. Gilt für alle Geräte der Gruppe.
  int get retentionMonths =>
      (replica.get(Types.settings, _settingsId)?['retentionMonths'] as num?)
          ?.toInt() ??
      defaultRetentionMonths;

  List<Change> setRetentionMonths(int months) =>
      _write(Types.settings, _settingsId, {'retentionMonths': months});

  /// Lässt Käufe und Grabsteine verfallen, die älter sind als
  /// [retentionMonths]. Jedes Gerät tut das selbst und verschickt nichts;
  /// weil alle nach demselben Datum entscheiden, kommen sie zum selben Stand.
  /// Liefert die Anzahl entfernter Objekte.
  int expire(DateTime now) {
    final months = retentionMonths;
    if (months <= 0) return 0;
    final cutoff = DateTime(
      now.year,
      now.month - months,
      now.day,
      now.hour,
      now.minute,
    ).millisecondsSinceEpoch;
    var count = 0;
    for (final p in purchases) {
      if (p.millis < cutoff) {
        replica.drop(Types.purchase, p.id);
        count++;
      }
    }
    return count + replica.dropTombstonesBefore(cutoff);
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

  /// Gespeicherte Produktdaten zu einem Barcode.
  ProductInfo? productInfo(String code) {
    final json = replica.get(Types.barcode, code)?['product'];
    return json is Map
        ? ProductInfo.fromJson(json.cast<String, Object?>())
        : null;
  }

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
    final bought = automatic ? _purchasesByArticle() : null;
    final at = now().millisecondsSinceEpoch;
    for (final id in replica.ids(Types.entry)) {
      final f = replica.get(Types.entry, id)!;
      if (f['listId'] != listId) continue;
      final articleId = f['articleId'] as String;
      final a = article(articleId);
      if (a == null) continue;
      // Ohne eigene Packungsgröße gilt die des Artikels, auch wenn sie erst
      // nach dem Hinzufügen eingetragen wurde.
      final ownPack = f['packSize'] as num?;
      result.add(
        ListEntry(
          listId: listId,
          articleId: articleId,
          quantity: f['quantity'] as num?,
          unit: f['unit'] as String?,
          packSize: ownPack ?? a.packSize,
          packUnit: ownPack != null ? f['packUnit'] as String? : a.packUnit,
          note: f['note'] as String?,
          price: f['price'] as int?,
          basePrice: f['basePrice'] as num?,
          checked: f['checked'] == true,
          autoAdded: f['autoAdded'] == true,
          autoAmount: bought == null || a.autoExcluded
              ? null
              : _consumption(bought[articleId])?.needed(at),
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

  /// Käufe, neueste zuerst; optional nur für einen Artikel.
  List<Purchase> purchasesOf({String? articleId}) {
    final result = [
      for (final p in purchases)
        if (articleId == null || p.articleId == articleId) p,
    ];
    result.sort((a, b) => b.millis.compareTo(a.millis));
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
          // Ältere Versionen haben keine Menge gespeichert, auch keine
          // Einheit; seitdem steht die Einheit immer da.
          amount: f['unit'] is String
              ? Amount(
                  quantity: f['quantity'] as num?,
                  unit: f['unit'] as String,
                  packSize: f['packSize'] as num?,
                  packUnit: f['packUnit'] as String?,
                )
              : null,
        ),
  ];

  // ------------------------------------------------- wiederkehrende Artikel

  /// Verbrauch eines Artikels aus seinen Käufen mit bekannter Menge, oder
  /// null, wenn es dafür (noch) zu wenige gibt.
  Consumption? consumption(String articleId) =>
      _consumption(_purchasesByArticle()[articleId]);

  /// Was die Automatik für den Artikel jetzt vorschlägt: der Verbrauch seit
  /// dem letzten Kauf. Null, wenn sie aus ist, der Artikel ausgenommen ist
  /// oder nichts bekannt ist.
  Amount? autoAmountFor(String articleId) {
    if (!automatic || (article(articleId)?.autoExcluded ?? true)) return null;
    return consumption(articleId)?.needed(now().millisecondsSinceEpoch);
  }

  /// Setzt fällige wiederkehrende Artikel auf eine Liste (die ihres letzten
  /// Kaufs), sofern sie auf keiner Liste stehen. Ein Artikel ist fällig,
  /// wenn seit dem letzten Kauf die Hälfte eines üblichen Kaufs verbraucht
  /// ist. Hat jemand einen automatisch gesetzten Eintrag von der
  /// Liste genommen, kommt der Artikel erst nach dem nächsten Kauf oder
  /// einem üblichen Abstand zwischen zwei Käufen wieder.
  ///
  /// Die Menge bleibt leer: Sie wird bei jeder Abfrage neu berechnet und
  /// wächst so mit der Zeit mit.
  List<Change> autoAdd() {
    if (!automatic) return const [];
    final listIds = {for (final l in lists) l.id};
    if (listIds.isEmpty) return const [];
    final onList = {
      for (final id in replica.ids(Types.entry))
        replica.get(Types.entry, id)!['articleId'],
    };
    final at = now().millisecondsSinceEpoch;
    final changes = <Change>[];
    for (final MapEntry(key: articleId, value: bought)
        in _purchasesByArticle().entries) {
      final a = article(articleId);
      if (a == null || a.autoExcluded || onList.contains(articleId)) continue;
      final c = _consumption(bought);
      final needed = c?.needed(at);
      if (c == null || needed == null || !c.isDue(at)) continue;
      final dismissed =
          (replica.get(Types.article, articleId)!['autoDismissed'] as num?)
              ?.toInt();
      if (dismissed != null &&
          dismissed > c.last.millis &&
          at - dismissed < c.interval.inMilliseconds) {
        continue;
      }
      final listId =
          bought.map((p) => p.listId).where(listIds.contains).lastOrNull ??
          lists.first.id;
      changes.addAll(
        _write(Types.entry, ListEntry.entryId(listId, articleId), {
          'listId': listId,
          'articleId': articleId,
          'quantity': null,
          'unit': needed.unit,
          'packSize': needed.packSize,
          'packUnit': needed.packUnit,
          'note': null,
          'price': null,
          'basePrice': null,
          'checked': false,
          'autoAdded': true,
          deletedField: false,
        }),
      );
    }
    return changes;
  }

  /// Käufe je Artikel, älteste zuerst.
  Map<String, List<Purchase>> _purchasesByArticle() {
    final result = <String, List<Purchase>>{};
    for (final p in purchases) {
      (result[p.articleId] ??= []).add(p);
    }
    for (final list in result.values) {
      list.sort((a, b) => a.millis.compareTo(b.millis));
    }
    return result;
  }

  /// Berechnet den Verbrauch aus Käufen (älteste zuerst). Zählt nur Käufe
  /// in der Grundeinheit des letzten Kaufs; Käufe, die weniger als einen Tag
  /// auseinanderliegen, gelten als einer.
  ///
  /// Je Abstand zwischen zwei Käufen gilt das zuerst Gekaufte bis zum
  /// nächsten Kauf als verbraucht. Der Verbrauch ist der **Median** dieser
  /// Werte, damit einzelne Ausreißer (Reise, Einkauf für ein Fest) kaum
  /// zählen.
  static Consumption? _consumption(List<Purchase>? bought) {
    if (bought == null) return null;
    final known = [
      for (final p in bought)
        if (p.amount?.base case final base? when base.amount > 0)
          (purchase: p, base: base),
    ];
    if (known.isEmpty) return null;
    final unit = known.last.base.unit;
    final buys = <({int millis, double amount})>[];
    for (final k in known.where((k) => k.base.unit == unit)) {
      final amount = k.base.amount.toDouble();
      final previous = buys.lastOrNull;
      if (previous != null &&
          k.purchase.millis - previous.millis < Duration.millisecondsPerDay) {
        // Der Abstand zählt ab dem ersten davon.
        buys.last = (millis: previous.millis, amount: previous.amount + amount);
      } else {
        buys.add((millis: k.purchase.millis, amount: amount));
      }
    }
    if (buys.length < 2) return null;
    final perDay = <double>[];
    final intervals = <double>[];
    for (var i = 0; i < buys.length - 1; i++) {
      final days =
          (buys[i + 1].millis - buys[i].millis) / Duration.millisecondsPerDay;
      perDay.add(buys[i].amount / days);
      intervals.add(days);
    }
    final amounts = [for (final b in buys) b.amount];
    return Consumption(
      last: known.last.purchase,
      unit: unit,
      perDay: _median(perDay),
      typical: _median(amounts),
      largest: amounts.reduce(math.max),
      interval: Duration(
        milliseconds: (_median(intervals) * Duration.millisecondsPerDay)
            .round(),
      ),
    );
  }

  static double _median(List<double> values) {
    final sorted = [...values]..sort();
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[mid]
        : (sorted[mid - 1] + sorted[mid]) / 2;
  }

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
              packSize: f['packSize'] as num?,
              packUnit: f['packUnit'] as String?,
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

  /// Preis eines Eintrags in Cent: der eingetragene bzw. umgerechnete Preis
  /// oder, falls keiner eingetragen ist, eine Schätzung aus dem letzten
  /// Preis je Grundeinheit (kg, l, Stück, …). Null, wenn nichts bekannt ist.
  int? estimatedPrice(ListEntry entry, {String? shopId}) {
    final own = entry.totalCents;
    if (own != null) return own;
    final last = lastPrice(entry.articleId, shopId: shopId);
    final lastBase = last?.basePriceCents;
    final base = entry.effectiveBase;
    if (lastBase == null || base == null || last!.base!.unit != base.unit) {
      return null;
    }
    return (lastBase * base.amount).round();
  }

  /// Summe der (geschätzten) Preise aller Einträge einer Liste, abgehakte
  /// eingeschlossen: beim Einkaufen zählt der ganze Einkauf. [open] ist der
  /// Teil davon, der auf noch nicht abgehakte Einträge entfällt; [unknown]
  /// zählt die Einträge ohne Preis.
  ({int cents, int open, int unknown}) listTotal(
    String listId, {
    String? shopId,
  }) {
    var cents = 0;
    var open = 0;
    var unknown = 0;
    for (final e in entries(listId)) {
      final p = estimatedPrice(e, shopId: shopId);
      if (p == null) {
        unknown++;
      } else {
        cents += p;
        if (!e.checked) open += p;
      }
    }
    return (cents: cents, open: open, unknown: unknown);
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
    num? packSize,
    String? packUnit,
  }) {
    final id = _newId();
    return (
      id: id,
      changes: _write(Types.article, id, {
        'name': name,
        'categoryId': categoryId,
        'defaultUnit': defaultUnit,
        'packSize': packSize,
        'packUnit': packUnit,
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

  /// Speichert Produktdaten (z. B. von Open Food Facts) zu einem Barcode.
  List<Change> setProductInfo(String code, ProductInfo info) =>
      _write(Types.barcode, code, {'product': info.toJson()});

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
  /// er früher darauf), wird der Eintrag neu gesetzt. Einheit und
  /// Packungsgröße kommen, wenn nicht angegeben, vom Artikel.
  List<Change> addToList(
    String listId,
    String articleId, {
    num? quantity,
    String? unit,
    String? note,
  }) {
    final a = article(articleId);
    final id = ListEntry.entryId(listId, articleId);
    // Nur wenn nötig, damit das Format für andere Clients gleich bleibt.
    final wasAuto = replica.get(Types.entry, id)?['autoAdded'] == true;
    return _write(Types.entry, id, {
      'listId': listId,
      'articleId': articleId,
      'quantity': quantity,
      'unit': unit ?? a?.defaultUnit,
      'packSize': a?.packSize,
      'packUnit': a?.packUnit,
      'note': note,
      'price': null,
      'basePrice': null,
      'checked': false,
      if (wasAuto) 'autoAdded': false,
      deletedField: false,
    });
  }

  /// Ändert einzelne Felder eines Eintrags (`quantity`, `unit`, `packSize`,
  /// `packUnit`, `note`, `price`, `basePrice`).
  List<Change> updateEntry(
    String listId,
    String articleId,
    Map<String, Object?> fields,
  ) => _write(Types.entry, ListEntry.entryId(listId, articleId), fields);

  List<Change> setChecked(String listId, String articleId, bool checked) =>
      _write(Types.entry, ListEntry.entryId(listId, articleId), {
        'checked': checked,
      });

  /// Entfernt einen Eintrag ohne ihn als gekauft zu verbuchen. War er
  /// automatisch gesetzt, merkt sich der Artikel das, damit die Automatik
  /// ihn nicht gleich wieder auf die Liste setzt (siehe [autoAdd]).
  List<Change> removeFromList(String listId, String articleId) {
    final id = ListEntry.entryId(listId, articleId);
    final auto = replica.get(Types.entry, id)?['autoAdded'] == true;
    return [
      if (auto && article(articleId) != null)
        ..._write(Types.article, articleId, {
          'autoDismissed': now().millisecondsSinceEpoch,
        }),
      ..._delete(Types.entry, id),
    ];
  }

  /// Verbucht alle abgehakten Einträge als Kauf (im Laden [shopId], falls
  /// bekannt) mit der geltenden Menge ([ListEntry.effectiveAmount]) und
  /// entfernt sie von der Liste. Eingetragene Preise wandern in die
  /// Preishistorie.
  List<Change> clearChecked(String listId, {String? shopId}) {
    final changes = <Change>[];
    for (final e in entries(listId).where((e) => e.checked)) {
      final millis = clock.tick().millis;
      final amount = e.effectiveAmount;
      final unit = amount.unit ?? Units.pack;
      final count = Units.isCount(unit);
      changes.addAll(
        _write(Types.purchase, _newId(), {
          'articleId': e.articleId,
          'listId': listId,
          'millis': millis,
          'shopId': shopId,
          'quantity': amount.quantity,
          'unit': unit,
          'packSize': count ? amount.packSize : null,
          'packUnit': count && amount.packSize != null ? amount.packUnit : null,
        }),
      );
      if (e.totalCents case final cents?) {
        changes.addAll(
          recordPrice(
            e.articleId,
            cents,
            quantity: amount.quantity,
            unit: amount.unit,
            packSize: count ? amount.packSize : null,
            packUnit: count ? amount.packUnit : null,
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
    num? packSize,
    String? packUnit,
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
        'packSize': packSize,
        'packUnit': packUnit,
        'shopId': shopId,
        'millis': clock.tick().millis,
      }),
    );
  }

  List<Change> deletePrice(String id) => _delete(Types.price, id);

  List<Change> deletePurchase(String id) => _delete(Types.purchase, id);

  /// Korrigiert die gekaufte Menge, z. B. wenn es weniger war als auf der
  /// Liste stand.
  List<Change> updatePurchase(String id, Amount amount) {
    final unit = amount.unit ?? Units.pack;
    final count = Units.isCount(unit);
    return _write(Types.purchase, id, {
      'quantity': amount.quantity,
      'unit': unit,
      'packSize': count ? amount.packSize : null,
      'packUnit': count && amount.packSize != null ? amount.packUnit : null,
    });
  }

  /// Löscht die Kaufhistorie, optional nur für einen Artikel.
  List<Change> deletePurchases({String? articleId}) => [
    for (final p in purchasesOf(articleId: articleId))
      ..._delete(Types.purchase, p.id),
  ];

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
          packSize: f['packSize'] as num?,
          packUnit: f['packUnit'] as String?,
          autoExcluded: f['autoExcluded'] == true,
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

/// Verbrauch eines Artikels, geschätzt aus seinen Käufen: Was gekauft
/// wurde, gilt bis zum nächsten Kauf als verbraucht.
class Consumption {
  const Consumption({
    required this.last,
    required this.unit,
    required this.perDay,
    required this.typical,
    required this.largest,
    required this.interval,
  });

  /// Letzter Kauf; nach ihm gilt der Vorrat als aufgefüllt.
  final Purchase last;

  /// Grundeinheit (kg, l, Stück, …) der Mengen.
  final String unit;

  /// Verbrauch je Tag in [unit] (Median über die Abstände der Käufe).
  final double perDay;

  /// Übliche Menge eines Kaufs in [unit] (Median).
  final double typical;

  /// Größte Menge eines Kaufs in [unit]. Mehr schlägt die Automatik nie
  /// vor, auch nach langer Pause nicht: Mehr Vorrat hatte man nie.
  final double largest;

  /// Üblicher Abstand zwischen zwei Käufen (Median).
  final Duration interval;

  /// Verbrauch seit dem letzten Kauf bis [millis] in [unit], höchstens
  /// [largest].
  double neededBase(int millis) => math.min(
    largest,
    math.max(0, millis - last.millis) / Duration.millisecondsPerDay * perDay,
  );

  /// Fällig: Seit dem letzten Kauf ist mindestens die Hälfte eines üblichen
  /// Kaufs verbraucht.
  bool isDue(int millis) => neededBase(millis) >= typical / 2;

  /// [neededBase] in der Einheit des letzten Kaufs, gerundet: Zähleinheiten
  /// auf ganze, kg/l auf Zehntel, g/ml auf zehn. Null, wenn das 0 ergibt.
  Amount? needed(int millis) {
    final template = last.amount!;
    final unit = template.unit ?? Units.pack;
    final perUnit = baseAmount(
      quantity: 1,
      unit: unit,
      packSize: Units.isCount(unit) ? template.packSize : null,
      packUnit: template.packUnit,
    )!.amount;
    final raw = neededBase(millis) / perUnit;
    final num quantity = switch (unit) {
      Units.kilogram || Units.litre => (raw * 10).round() / 10,
      Units.gram || Units.millilitre => (raw / 10).round() * 10,
      _ => raw.round(),
    };
    if (quantity <= 0) return null;
    return Amount(
      quantity: quantity,
      unit: unit,
      packSize: Units.isCount(unit) ? template.packSize : null,
      packUnit: Units.isCount(unit) && template.packSize != null
          ? template.packUnit
          : null,
    );
  }
}
