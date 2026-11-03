import 'dart:async';

import 'replica.dart';

/// Verbindung einer Gruppe zu einem Sync-Dienst (z. B. ein Matrix-Raum).
///
/// Ein Backend muss Änderungen nicht in Reihenfolge oder genau einmal
/// zustellen: Das Anwenden ist idempotent und reihenfolgeunabhängig.
abstract interface class GroupSync {
  /// Änderungen, die von anderen Geräten eingehen.
  Stream<List<Change>> get incoming;

  /// Private Daten des Benutzers, wenn sie sich auf einem anderen Gerät
  /// geändert haben (vollständiger Stand, wird zusammengeführt).
  Stream<List<Change>> get incomingPrivate;

  /// Verteilt Änderungen an alle Mitglieder. Wirft bei Fehlern (z. B. offline);
  /// die Änderungen bleiben dann im [Outbox].
  Future<void> send(List<Change> changes);

  /// Speichert den vollständigen Stand der privaten Daten.
  Future<void> savePrivate(List<Change> snapshot);

  /// Wird aufgerufen, wenn ein Gerät den vollständigen Stand braucht (neues
  /// Gerät, neues Mitglied). Das Backend ruft das bei Bedarf auf und
  /// verschickt das Ergebnis.
  set snapshotProvider(List<Change> Function() provider);

  Future<void> close();
}

/// Warteschlange noch nicht verschickter Änderungen. Hält Änderungen, solange
/// das Gerät offline ist, und lässt sich als JSON speichern.
class Outbox {
  Outbox([Iterable<Change> pending = const []]) : _pending = [...pending];

  final List<Change> _pending;
  Future<void>? _flushing;

  List<Change> get pending => List.unmodifiable(_pending);
  bool get isEmpty => _pending.isEmpty;

  void add(Iterable<Change> changes) => _pending.addAll(changes);

  /// Verwirft alles Ausstehende, z. B. wenn die Gruppe nicht mehr geteilt ist.
  void clear() => _pending.clear();

  /// Versucht, alles Ausstehende mit [send] zu verschicken. Bei Erfolg wird
  /// das Verschickte entfernt; was währenddessen hinzukommt, bleibt.
  /// Liefert true, wenn danach nichts mehr aussteht.
  Future<bool> flush(Future<void> Function(List<Change>) send) async {
    while (_flushing != null) {
      await _flushing;
    }
    if (_pending.isEmpty) return true;
    final batch = [..._pending];
    final done = Completer<void>();
    _flushing = done.future;
    try {
      await send(batch);
      _pending.removeRange(0, batch.length);
      return _pending.isEmpty;
    } catch (_) {
      return false;
    } finally {
      _flushing = null;
      done.complete();
    }
  }

  List<Object?> toJson() => [for (final c in _pending) c.toJson()];

  factory Outbox.fromJson(List<Object?> json) => Outbox([
    for (final c in json) Change.fromJson(c as Map<String, Object?>),
  ]);
}
