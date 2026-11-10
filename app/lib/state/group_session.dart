import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:konsum_core/konsum_core.dart';

import '../storage/store.dart';

/// Stammdaten einer Gruppe auf diesem Gerät.
class GroupInfo {
  GroupInfo({required this.id, required this.name, this.backend});

  final String id;
  String name;

  /// Verbindung zum Sync-Dienst, z. B. `{type: matrix, roomId: …}`.
  /// Null für Gruppen, die nur lokal existieren.
  Map<String, Object?>? backend;

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'backend': backend};

  factory GroupInfo.fromJson(Map<String, Object?> json) => GroupInfo(
    id: json['id'] as String,
    name: json['name'] as String,
    backend: json['backend'] as Map<String, Object?>?,
  );
}

enum SyncStatus {
  local,
  offline,

  /// War länger getrennt als die Aufbewahrungsfrist und wartet auf den
  /// aktuellen Stand der Gruppe; verschickt bis dahin nichts.
  resyncing,
  pending,
  synced,
}

/// Eine Gruppe auf diesem Gerät: Daten, private Daten, ausstehende Änderungen
/// und (optional) die Verbindung zum Sync-Dienst. Speichert sich selbst.
class GroupSession extends ChangeNotifier {
  GroupSession._(
    this.info,
    this.group,
    this.private,
    this.outbox,
    this._store, {
    required this._privateDirty,
  });

  /// Neue, leere Gruppe.
  factory GroupSession.create(
    GroupInfo info,
    String node,
    KeyValueStore store,
  ) => GroupSession._(
    info,
    Group(HlcClock(node)),
    PrivateData(HlcClock(node)),
    Outbox(),
    store,
    privateDirty: false,
  );

  static Future<GroupSession> load(
    GroupInfo info,
    String node,
    KeyValueStore store,
  ) async {
    final session = GroupSession.create(info, node, store);
    final raw = await store.read(_key(info.id));
    if (raw == null) return session;
    final json = jsonDecode(raw) as Map<String, Object?>;
    session.group.receive(_changes(json['snapshot']));
    session.private.receive(_changes(json['private']));
    session.outbox.add(_changes(json['outbox']));
    session._privateDirty = json['privateDirty'] == true;
    session._lastSync = (json['lastSync'] as num?)?.toInt();
    session._resyncing = json['resyncing'] == true;
    // Ältere Versionen haben Grabsteine lokaler Gruppen behalten.
    if (info.backend == null) session.group.replica.dropTombstones();
    session.group.expire(DateTime.now());
    // Beim Laden verworfener Inhalt (Grabsteine älterer Versionen) soll
    // nicht bis zur nächsten Änderung in der Datei stehen bleiben.
    await session.save();
    return session;
  }

  static String _key(String id) => 'group-$id';

  static List<Change> _changes(Object? json) => [
    for (final c in (json as List? ?? const []))
      Change.fromJson(c as Map<String, Object?>),
  ];

  final GroupInfo info;
  final Group group;
  final PrivateData private;
  final Outbox outbox;
  final KeyValueStore _store;
  bool _privateDirty;

  GroupSync? _sync;
  final _subscriptions = <StreamSubscription<Object?>>[];
  bool _lastFlushFailed = false;

  /// Zeitpunkt (ms) des letzten lückenlosen Syncs mit dem Raum.
  int? _lastSync;

  /// Wartet auf einen vollständigen Schnappschuss, siehe [_startResync].
  bool _resyncing = false;

  /// Seit dem Verbinden einmal lückenlos synchronisiert.
  bool _syncedSinceAttach = false;

  /// Objekte, die während des Wartens geändert wurden.
  final _touched = <(String, String)>{};
  Timer? _saveTimer;

  String get id => info.id;
  bool get isConnected => _sync != null;

  SyncStatus get status {
    if (info.backend == null) return SyncStatus.local;
    if (_sync == null || _lastFlushFailed) return SyncStatus.offline;
    if (_resyncing) return SyncStatus.resyncing;
    if (!outbox.isEmpty || _privateDirty) return SyncStatus.pending;
    return SyncStatus.synced;
  }

  /// Übernimmt lokal erzeugte Änderungen (Ergebnis eines [Group]-Befehls).
  void apply(List<Change> changes) {
    if (changes.isEmpty) return;
    // Rein lokale Gruppen brauchen keine Outbox; beim Teilen wird der
    // vollständige Stand verschickt (siehe [share]).
    if (info.backend != null) outbox.add(changes);
    _cleanUp(changes);
    _changed();
    unawaited(flush());
  }

  /// Übernimmt lokal erzeugte private Änderungen.
  void applyPrivate(List<Change> changes) {
    _privateDirty = true;
    _changed();
    unawaited(flush());
  }

  /// Macht aus einer lokalen Gruppe eine geteilte: Der vollständige Stand
  /// wird zum Verschicken vorgemerkt.
  void share(Map<String, Object?> backend) {
    info.backend = backend;
    outbox.add(group.replica.snapshot());
    _privateDirty = true;
    _changed();
  }

  /// Macht aus einer geteilten Gruppe eine lokale: Verbindung trennen,
  /// Ausstehendes verwerfen (es erreicht die Gruppe nicht mehr).
  Future<void> unshare() async {
    await detach();
    info.backend = null;
    outbox.clear();
    _privateDirty = false;
    // Lokale Gruppen brauchen keine Grabsteine.
    group.replica.dropTombstones();
    _changed();
  }

  /// Verbindet die Gruppe mit einem Sync-Dienst.
  Future<void> attach(GroupSync sync) async {
    await detach();
    _sync = sync;
    _syncedSinceAttach = false;
    sync.snapshotProvider = group.replica.snapshot;
    _subscriptions
      ..add(
        sync.incoming.listen((changes) {
          group.receive(changes);
          if (_resyncing) _touched.addAll(changes.map((c) => (c.type, c.id)));
          _cleanUp(changes);
          _changed();
        }),
      )
      ..add(
        sync.incomingPrivate.listen((changes) {
          private.receive(changes);
          _changed();
        }),
      )
      ..add(sync.synced.listen((_) => _onSynced()))
      ..add(sync.completeSnapshots.listen(_onCompleteSnapshot));
    if (_resyncing || _isStale) _startResync();
    await flush();
  }

  Future<void> detach() async {
    for (final s in _subscriptions) {
      await s.cancel();
    }
    _subscriptions.clear();
    await _sync?.close();
    _sync = null;
    notifyListeners();
  }

  /// Verschickt Ausstehendes, falls verbunden.
  Future<void> flush() async {
    final sync = _sync;
    if (sync == null) return;
    // Veraltet: Nichts verschicken, bis der aktuelle Stand da ist.
    var ok = _resyncing || await outbox.flush(sync.send);
    if (_privateDirty) {
      try {
        await sync.savePrivate(private.replica.snapshot());
        _privateDirty = false;
      } catch (_) {
        ok = false;
      }
    }
    _lastFlushFailed = !ok && (!outbox.isEmpty || _privateDirty);
    _changed();
  }

  /// Räumt nach Änderungen auf: Private Notizen gelöschter Einträge
  /// verschwinden mit ihnen (sonst tauchten sie beim erneuten Hinzufügen
  /// wieder auf), lokale Gruppen brauchen keine Grabsteine.
  void _cleanUp(Iterable<Change> changes) {
    for (final c in changes) {
      if (c.type == Types.entry &&
          c.field == deletedField &&
          c.value == true &&
          group.replica.get(Types.entry, c.id) == null &&
          private.note(c.id) != null) {
        private.setNote(c.id, null);
        _privateDirty = true;
      }
    }
    if (info.backend == null) group.replica.dropTombstones();
    group.expire(DateTime.now());
  }

  /// Setzt fällige wiederkehrende Artikel auf die Liste (siehe
  /// [Group.autoAdd]), falls die Automatik an ist. Geteilte Gruppen erst,
  /// wenn der aktuelle Stand da ist: Ein Gerät mit veraltetem Stand würde
  /// sonst Artikel wieder auf die Liste setzen, die anderswo schon gekauft
  /// wurden.
  void autoAdd() {
    if (!group.automatic) return;
    final current =
        info.backend == null ||
        (_sync != null &&
            _syncedSinceAttach &&
            !_resyncing &&
            !_lastFlushFailed);
    if (current) apply(group.autoAdd());
  }

  /// Lässt Abgelaufenes verfallen (siehe [Group.expire]), z. B. wenn die App
  /// lange offen bleibt.
  void expire() {
    if (group.expire(DateTime.now()) > 0) _changed();
  }

  /// Ob dieses Gerät länger nicht lückenlos synchronisiert hat als die
  /// Aufbewahrungsfrist. Dann kann es Grabsteine verpasst haben, die anderswo
  /// schon verfallen sind; sein Stand würde Gelöschtes wiederbeleben.
  bool get _isStale {
    final last = _lastSync;
    final months = group.retentionMonths;
    if (last == null || months <= 0) return false;
    final now = DateTime.now();
    final cutoff = DateTime(
      now.year,
      now.month - months,
      now.day,
      now.hour,
      now.minute,
    );
    return last < cutoff.millisecondsSinceEpoch;
  }

  void _onSynced() {
    if (_resyncing) return;
    if (_isStale) {
      _startResync();
      return;
    }
    _lastSync = DateTime.now().millisecondsSinceEpoch;
    _syncedSinceAttach = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 300), save);
  }

  /// Veraltet: keine Schnappschüsse verschicken, Ausstehendes zurückhalten
  /// und auf einen vollständigen Schnappschuss eines anderen Geräts warten.
  void _startResync() {
    final sync = _sync;
    if (sync == null) return;
    if (!_resyncing) _touched.clear();
    _resyncing = true;
    sync.answerSnapshots = false;
    unawaited(sync.requestSnapshot());
    _changed();
  }

  /// Der aktuelle Stand ist da: Alles verwerfen, was es dort nicht mehr gibt
  /// – außer seitdem Geändertem und offline neu Angelegtem –, ebenso
  /// ausstehende Änderungen an Verworfenem. Danach wieder normal.
  void _onCompleteSnapshot(List<Change> snapshot) {
    if (!_resyncing) return;
    final keep = {
      for (final c in snapshot) (c.type, c.id),
      ..._touched,
      for (final c in outbox.pending)
        if (c.field == deletedField && c.value == false) (c.type, c.id),
    };
    for (final key in group.replica.keys.difference(keep)) {
      group.replica.drop(key.$1, key.$2);
    }
    outbox.retainWhere((c) => keep.contains((c.type, c.id)));
    _resyncing = false;
    _touched.clear();
    _sync?.answerSnapshots = true;
    _lastSync = DateTime.now().millisecondsSinceEpoch;
    _changed();
    unawaited(flush());
  }

  void _changed() {
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 300), save);
  }

  Future<void> save() async {
    _saveTimer?.cancel();
    await _store.write(
      _key(id),
      jsonEncode({
        'snapshot': [for (final c in group.replica.snapshot()) c.toJson()],
        'private': [for (final c in private.replica.snapshot()) c.toJson()],
        'outbox': outbox.toJson(),
        'privateDirty': _privateDirty,
        'lastSync': _lastSync,
        'resyncing': _resyncing,
      }),
    );
  }

  /// Löscht die lokalen Daten dieser Gruppe.
  Future<void> deleteLocal() async {
    _saveTimer?.cancel();
    await detach();
    await _store.delete(_key(id));
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    for (final s in _subscriptions) {
      s.cancel();
    }
    super.dispose();
  }
}
