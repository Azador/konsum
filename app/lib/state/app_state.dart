import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../storage/store.dart';
import 'group_session.dart';
import 'status_messages.dart';

/// Kategorien, mit denen eine neue Gruppe startet.
const defaultCategories = [
  'Obst & Gemüse',
  'Brot & Backwaren',
  'Kühlregal',
  'Fleisch & Wurst',
  'Tiefkühl',
  'Vorrat',
  'Süßes & Snacks',
  'Getränke',
  'Drogerie',
  'Haushalt',
];

/// Zustand der App auf diesem Gerät: Gruppen, Auswahl, Anzeigeoptionen.
class AppState extends ChangeNotifier {
  AppState._(this._store, this.node, this._random);

  static const _metaKey = 'app';

  /// Kurze Meldungen für die Statuszeile.
  final status = StatusMessages();

  /// Lädt den gespeicherten Zustand. Beim ersten Start wird eine Gruppe mit
  /// einer Liste und Standardkategorien angelegt.
  static Future<AppState> load(
    KeyValueStore store, {
    math.Random? random,
  }) async {
    random ??= math.Random.secure();
    final raw = await store.read(_metaKey);
    final json = raw == null
        ? const <String, Object?>{}
        : jsonDecode(raw) as Map<String, Object?>;
    final state = AppState._(
      store,
      json['node'] as String? ?? _randomId(random, 4),
      random,
    );
    for (final g in (json['groups'] as List? ?? const [])) {
      final info = GroupInfo.fromJson(g as Map<String, Object?>);
      state._add(await GroupSession.load(info, state.node, store));
    }
    state._groupId = json['groupId'] as String?;
    state._listId = json['listId'] as String?;
    state._shops.addAll(
      (json['shops'] as Map? ?? const {}).cast<String, String>(),
    );
    state._showChecked = json['showChecked'] as bool? ?? true;
    state._colors.addAll(
      (json['colors'] as Map? ?? const {}).cast<String, int>(),
    );

    if (state.groups.isEmpty) {
      final s = await state.createGroup('Zuhause');
      state.createList(s, 'Einkaufsliste');
    }
    state._ensureSelection();
    return state;
  }

  final KeyValueStore _store;
  final math.Random _random;

  /// Kennung dieses Geräts für die Zeitstempel.
  final String node;

  final _groups = <GroupSession>[];
  final _shops = <String, String>{};
  final _colors = <String, int>{};
  String? _groupId;
  String? _listId;
  bool _showChecked = true;

  List<GroupSession> get groups => List.unmodifiable(_groups);

  GroupSession? get currentGroup =>
      _groups.where((g) => g.id == _groupId).firstOrNull;

  String? get currentListId => _listId;

  bool get showChecked => _showChecked;

  /// Gewählter Laden einer Gruppe (bestimmt die Sortierung).
  String? shopFor(GroupSession g) {
    final id = _shops[g.id];
    return id != null && g.group.shop(id) != null ? id : null;
  }

  /// Farbschema einer Gruppe als ARGB-Wert, `null` für den Standard. Gilt
  /// nur auf diesem Gerät.
  int? colorFor(GroupSession g) => _colors[g.id];

  void setColor(GroupSession g, int? argb) {
    if (argb == null) {
      _colors.remove(g.id);
    } else {
      _colors[g.id] = argb;
    }
    _changed();
  }

  void selectList(GroupSession g, String listId) {
    _groupId = g.id;
    _listId = listId;
    _changed();
  }

  void selectShop(GroupSession g, String? shopId) {
    if (shopId == null) {
      _shops.remove(g.id);
    } else {
      _shops[g.id] = shopId;
    }
    _changed();
  }

  void toggleShowChecked() {
    _showChecked = !_showChecked;
    _changed();
  }

  Future<GroupSession> createGroup(
    String name, {
    bool withDefaults = true,
    Map<String, Object?>? backend,
  }) async {
    final s = GroupSession.create(
      GroupInfo(id: _randomId(_random, 8), name: name, backend: backend),
      node,
      _store,
    );
    _add(s);
    if (withDefaults) {
      for (final c in defaultCategories) {
        s.apply(s.group.createCategory(c).changes);
      }
    }
    await s.save();
    _groupId ??= s.id;
    _changed();
    return s;
  }

  String createList(GroupSession g, String name) {
    final r = g.group.createList(name);
    g.apply(r.changes);
    selectList(g, r.id);
    return r.id;
  }

  void deleteList(GroupSession g, String listId) {
    g.apply(g.group.deleteList(listId));
    _ensureSelection();
    _changed();
  }

  /// Nach Änderungen an [GroupInfo] (z. B. Sync-Verbindung) speichern.
  void notifyGroupChanged() => _changed();

  void renameGroup(GroupSession g, String name) {
    g.info.name = name;
    _changed();
  }

  /// Behält eine geteilte Gruppe als lokale Kopie, z. B. beim Abmelden. Der
  /// Name bekommt einen Zusatz, damit sie sich von der Gruppe unterscheidet,
  /// die nach erneuter Anmeldung wieder aus dem Konto dazukommt.
  Future<void> keepAsLocal(GroupSession g) async {
    await g.unshare();
    g.info.name = localCopyName(g.info.name);
    _changed();
  }

  /// „Name (lokal)“, bei Bedarf hochgezählt: „Name (lokal 2)“, …
  String localCopyName(String name) {
    final taken = {for (final g in _groups) g.info.name};
    var candidate = '$name (lokal)';
    for (var i = 2; taken.contains(candidate); i++) {
      candidate = '$name (lokal $i)';
    }
    return candidate;
  }

  /// Entfernt die Gruppe von diesem Gerät.
  Future<void> removeGroup(GroupSession g) async {
    _groups.remove(g);
    g.removeListener(_onGroupChanged);
    await g.deleteLocal();
    g.dispose();
    _shops.remove(g.id);
    _colors.remove(g.id);
    _ensureSelection();
    _changed();
  }

  /// Ob [g] nur die beim ersten Start angelegte, unbenutzte Gruppe ist:
  /// nicht geteilt, keine Artikel, Läden, Einkäufe oder Listeneinträge.
  bool isUnused(GroupSession g) =>
      g.info.backend == null &&
      g.group.articles.isEmpty &&
      g.group.shops.isEmpty &&
      g.group.purchases.isEmpty &&
      g.group.lists.every((l) => g.group.entries(l.id).isEmpty);

  /// Entfernt unbenutzte Gruppen ([isUnused]), z. B. wenn nach der Anmeldung
  /// auf einem neuen Gerät die geteilten Gruppen dazukommen.
  Future<void> removeUnusedGroups() async {
    for (final g in [..._groups]) {
      if (isUnused(g)) await removeGroup(g);
    }
  }

  /// Versucht bei allen Gruppen, Ausstehendes zu verschicken.
  Future<void> flushAll() async {
    for (final g in _groups) {
      await g.flush();
    }
  }

  void _add(GroupSession s) {
    _groups.add(s);
    s.addListener(_onGroupChanged);
  }

  void _onGroupChanged() {
    _ensureSelection();
    notifyListeners();
  }

  /// Sorgt dafür, dass eine existierende Liste gewählt ist (falls es eine gibt).
  void _ensureSelection() {
    final g = currentGroup;
    if (g != null &&
        _listId != null &&
        g.group.lists.any((l) => l.id == _listId)) {
      return;
    }
    for (final s in [?g, ..._groups]) {
      final lists = s.group.lists;
      if (lists.isNotEmpty) {
        _groupId = s.id;
        _listId = lists.first.id;
        return;
      }
    }
    _groupId = _groups.firstOrNull?.id;
    _listId = null;
  }

  void _changed() {
    notifyListeners();
    unawaited(_saveMeta());
  }

  Future<void> _saveMeta() => _store.write(
    _metaKey,
    jsonEncode({
      'node': node,
      'groups': [for (final g in _groups) g.info.toJson()],
      'groupId': _groupId,
      'listId': _listId,
      'shops': _shops,
      'showChecked': _showChecked,
      'colors': _colors,
    }),
  );

  static String _randomId(math.Random random, int bytes) => [
    for (var i = 0; i < bytes; i++)
      random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();
}
