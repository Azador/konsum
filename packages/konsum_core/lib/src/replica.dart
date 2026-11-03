import 'hlc.dart';

/// Feldname, mit dem ein Objekt als gelöscht markiert wird (Tombstone).
const deletedField = '_deleted';

/// Bis zu welchem Zeitpunkt der Inhalt eines Objekts gelöscht ist (Zeitstempel
/// des letzten Grabsteins). Siehe [Replica.apply].
const purgedField = '_purged';

/// Änderung eines einzelnen Feldes eines Objekts. Das ist die Einheit, die
/// zwischen Geräten ausgetauscht wird.
class Change {
  const Change({
    required this.type,
    required this.id,
    required this.field,
    required this.value,
    required this.hlc,
  });

  final String type;
  final String id;
  final String field;

  /// JSON-kompatibler Wert (null, bool, num, String, List, Map).
  final Object? value;
  final Hlc hlc;

  Map<String, Object?> toJson() => {
    'type': type,
    'id': id,
    'field': field,
    'value': value,
    'hlc': hlc.toString(),
  };

  factory Change.fromJson(Map<String, Object?> json) => Change(
    type: json['type'] as String,
    id: json['id'] as String,
    field: json['field'] as String,
    value: json['value'],
    hlc: Hlc.parse(json['hlc'] as String),
  );

  @override
  String toString() => 'Change($type/$id.$field = $value @ $hlc)';
}

class _Field {
  const _Field(this.value, this.hlc);
  final Object? value;
  final Hlc hlc;
}

/// Zustand aller Objekte einer Gruppe.
///
/// Konfliktauflösung: Pro Feld gewinnt die Änderung mit dem größten
/// Zeitstempel ("last write wins"). Das Anwenden von Änderungen ist
/// idempotent und unabhängig von der Reihenfolge, sodass alle Geräte nach
/// Austausch derselben Änderungen denselben Zustand haben.
class Replica {
  final _objects = <String, Map<String, Map<String, _Field>>>{};

  /// Wendet [change] an. Liefert true, wenn sich der Zustand geändert hat.
  ///
  /// Gelöschte Objekte behalten keinen Inhalt: Ein Grabstein
  /// (`_deleted: true`) setzt die Markierung [purgedField] auf seinen
  /// Zeitpunkt. Alle Felder, die nicht neuer sind als die Markierung,
  /// verschwinden und werden auch später nicht mehr angenommen – auch wenn
  /// das Objekt wieder angelegt wird. Die Markierung wandert in Schnappschüssen
  /// mit, sodass Geräte, die das Löschen verpasst haben, dasselbe verwerfen.
  /// Das Ergebnis hängt nicht von der Reihenfolge ab.
  bool apply(Change change) {
    final fields = _objects
        .putIfAbsent(change.type, () => {})
        .putIfAbsent(change.id, () => {});
    final changed = _set(fields, change.field, change.value, change.hlc);
    if (change.field == deletedField && change.value == true) {
      _set(fields, purgedField, true, change.hlc);
    }
    return changed;
  }

  bool _set(Map<String, _Field> fields, String name, Object? value, Hlc hlc) {
    final current = fields[name];
    if (current != null && !(hlc > current.hlc)) return false;
    if (name == purgedField) {
      fields[purgedField] = _Field(value, hlc);
      fields.removeWhere((n, f) => !_meta.contains(n) && !(f.hlc > hlc));
      return true;
    }
    final purged = fields[purgedField];
    if (!_meta.contains(name) && purged != null && !(hlc > purged.hlc)) {
      return false;
    }
    fields[name] = _Field(value, hlc);
    return true;
  }

  static const _meta = {deletedField, purgedField};

  /// Alle Objekte als (Typ, ID), auch Grabsteine.
  Set<(String, String)> get keys => {
    for (final t in _objects.entries)
      for (final id in t.value.keys) (t.key, id),
  };

  /// Entfernt ein Objekt vollständig, ohne Grabstein und ohne Änderung, die
  /// verschickt würde (Verfall, den jedes Gerät selbst vornimmt).
  void drop(String type, String id) => _objects[type]?.remove(id);

  /// Entfernt Grabsteine, die vor [millis] (Unix-Zeit in ms) gesetzt wurden.
  /// Liefert die Anzahl.
  int dropTombstonesBefore(int millis) {
    var count = 0;
    for (final objects in _objects.values) {
      objects.removeWhere((_, f) {
        final d = f[deletedField];
        final old = d != null && d.value == true && d.hlc.millis < millis;
        if (old) count++;
        return old;
      });
    }
    return count;
  }

  /// Entfernt gelöschte Objekte samt Grabstein. Nur für Daten, die kein
  /// anderes Gerät hat (lokale Gruppen): Dort kann nichts ein gelöschtes
  /// Objekt wiederbeleben.
  void dropTombstones() {
    for (final objects in _objects.values) {
      objects.removeWhere((_, f) => f[deletedField]?.value == true);
    }
  }

  void applyAll(Iterable<Change> changes) => changes.forEach(apply);

  /// Felder eines Objekts, oder null wenn es nicht existiert oder gelöscht ist.
  Map<String, Object?>? get(String type, String id) {
    final fields = _objects[type]?[id];
    if (fields == null || fields[deletedField]?.value == true) return null;
    return {
      for (final e in fields.entries)
        if (!_meta.contains(e.key)) e.key: e.value.value,
    };
  }

  /// IDs aller nicht gelöschten Objekte eines Typs.
  Iterable<String> ids(String type) =>
      (_objects[type]?.keys ?? const <String>[]).where(
        (id) => get(type, id) != null,
      );

  /// Gesamter Zustand als Änderungen, z. B. als Schnappschuss für neue Geräte.
  /// Enthält auch Tombstones, damit Löschungen erhalten bleiben.
  List<Change> snapshot() => [
    for (final t in _objects.entries)
      for (final o in t.value.entries)
        for (final f in o.value.entries)
          Change(
            type: t.key,
            id: o.key,
            field: f.key,
            value: f.value.value,
            hlc: f.value.hlc,
          ),
  ];

  /// Größter bekannter Zeitstempel, um die eigene Uhr danach zu stellen.
  Hlc? get latest {
    Hlc? max;
    for (final t in _objects.values) {
      for (final o in t.values) {
        for (final f in o.values) {
          if (max == null || f.hlc > max) max = f.hlc;
        }
      }
    }
    return max;
  }
}
