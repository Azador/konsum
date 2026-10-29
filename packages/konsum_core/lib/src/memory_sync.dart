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

  @override
  Stream<List<Change>> get incoming => _incoming.stream;

  @override
  Stream<List<Change>> get incomingPrivate => _incomingPrivate.stream;

  @override
  set snapshotProvider(List<Change> Function() provider) {}

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
  }
}
