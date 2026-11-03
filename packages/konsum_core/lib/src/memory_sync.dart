import 'dart:async';

import 'replica.dart';
import 'sync.dart';

/// Sync im Arbeitsspeicher, für Tests und Vorführungen: Alle über denselben
/// Hub verbundenen Geräte tauschen Änderungen direkt aus.
class MemoryHub {
  final _members = <MemorySync>[];
  final _private = <String, List<Change>>{};

  /// Ist der Hub offline, schlägt jedes Senden fehl.
  bool online = true;

  /// Meldet allen Verbundenen einen lückenlosen Sync.
  void tick() {
    for (final m in [..._members]) {
      m._synced.add(null);
    }
  }

  MemorySync connect(String user) {
    final s = MemorySync._(this, user);
    _members.add(s);
    return s;
  }
}

class MemorySync implements GroupSync {
  MemorySync._(this._hub, this._user);

  final MemoryHub _hub;
  final String _user;
  final _incoming = StreamController<List<Change>>.broadcast(sync: true);
  final _incomingPrivate = StreamController<List<Change>>.broadcast(sync: true);
  final _synced = StreamController<void>.broadcast(sync: true);
  final _completeSnapshots = StreamController<List<Change>>.broadcast(
    sync: true,
  );
  List<Change> Function() _provider = () => const [];
  bool _answer = true;

  /// Ob [requestSnapshot] aufgerufen wurde (für Tests).
  int snapshotRequests = 0;

  @override
  Stream<List<Change>> get incoming => _incoming.stream;

  @override
  Stream<List<Change>> get incomingPrivate => _incomingPrivate.stream;

  @override
  set snapshotProvider(List<Change> Function() provider) =>
      _provider = provider;

  @override
  set answerSnapshots(bool value) => _answer = value;

  @override
  Stream<void> get synced => _synced.stream;

  @override
  Stream<List<Change>> get completeSnapshots => _completeSnapshots.stream;

  /// Das erste andere Gerät, das antworten darf, schickt seinen Stand.
  @override
  Future<void> requestSnapshot() async {
    snapshotRequests++;
    if (!_hub.online) return;
    for (final m in _hub._members) {
      if (m == this || !m._answer) continue;
      final snapshot = m._provider();
      if (snapshot.isEmpty) continue;
      _incoming.add(snapshot);
      _completeSnapshots.add(snapshot);
      return;
    }
  }

  @override
  Future<void> send(List<Change> changes) async {
    if (!_hub.online) throw StateError('offline');
    for (final m in _hub._members) {
      if (m != this) m._incoming.add(changes);
    }
  }

  @override
  Future<void> savePrivate(List<Change> snapshot) async {
    if (!_hub.online) throw StateError('offline');
    _hub._private[_user] = snapshot;
    for (final m in _hub._members) {
      if (m != this && m._user == _user) m._incomingPrivate.add(snapshot);
    }
  }

  @override
  Future<void> close() async {
    _hub._members.remove(this);
    await _incoming.close();
    await _incomingPrivate.close();
    await _synced.close();
    await _completeSnapshots.close();
  }
}
