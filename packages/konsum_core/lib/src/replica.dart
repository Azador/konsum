import 'hlc.dart';

/// Feldname, mit dem ein Objekt als gelöscht markiert wird (Tombstone).
const deletedField = '_deleted';

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
  bool apply(Change change) {
    final fields = _objects
        .putIfAbsent(change.type, () => {})
        .putIfAbsent(change.id, () => {});
    final current = fields[change.field];
    if (current != null && !(change.hlc > current.hlc)) return false;
    fields[change.field] = _Field(change.value, change.hlc);
    return true;
  }

  void applyAll(Iterable<Change> changes) => changes.forEach(apply);

  /// Felder eines Objekts, oder null wenn es nicht existiert oder gelöscht ist.
  Map<String, Object?>? get(String type, String id) {
    final fields = _objects[type]?[id];
    if (fields == null || fields[deletedField]?.value == true) return null;
    return {
      for (final e in fields.entries)
        if (e.key != deletedField) e.key: e.value.value,
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
