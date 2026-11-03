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

enum SyncStatus { local, offline, pending, synced }

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
    // Ältere Versionen haben Grabsteine lokaler Gruppen behalten.
    if (info.backend == null) session.group.replica.dropTombstones();
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
  Timer? _saveTimer;

  String get id => info.id;
  bool get isConnected => _sync != null;

  SyncStatus get status {
    if (info.backend == null) return SyncStatus.local;
    if (_sync == null || _lastFlushFailed) return SyncStatus.offline;
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
    _changed();
  }

  /// Verbindet die Gruppe mit einem Sync-Dienst.
  Future<void> attach(GroupSync sync) async {
    await detach();
    _sync = sync;
    sync.snapshotProvider = group.replica.snapshot;
    _subscriptions
      ..add(
        sync.incoming.listen((changes) {
          group.receive(changes);
          _cleanUp(changes);
          _changed();
        }),
      )
      ..add(
        sync.incomingPrivate.listen((changes) {
          private.receive(changes);
          _changed();
        }),
      );
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
    var ok = await outbox.flush(sync.send);
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
