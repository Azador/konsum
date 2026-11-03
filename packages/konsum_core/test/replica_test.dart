import 'dart:math' as math;

import 'package:konsum_core/konsum_core.dart';
import 'package:test/test.dart';

Change c(String field, Object? value, int millis) => Change(
  type: 'entry',
  id: 'e',
  field: field,
  value: value,
  hlc: Hlc(millis, 0, 'n'),
);

/// Felder des Objekts im Schnappschuss (auch eines Grabsteins), sortiert.
Map<String, Object?> stored(Replica r) => {
  for (final ch in r.snapshot()..sort((a, b) => a.field.compareTo(b.field)))
    ch.field: ch.value,
};

void main() {
  test('Grabstein behält keinen Inhalt', () {
    final r = Replica()
      ..applyAll([
        c(deletedField, false, 1),
        c('note', 'Buch über …', 1),
        c('quantity', 2, 2),
        c(deletedField, true, 3),
      ]);
    expect(r.get('entry', 'e'), isNull);
    expect(stored(r), {deletedField: true, purgedField: true});
  });

  test('Ältere Änderungen erreichen einen Grabstein nicht mehr', () {
    final r = Replica()
      ..apply(c(deletedField, true, 5))
      ..apply(c('note', 'verspätet', 4));
    expect(stored(r), {deletedField: true, purgedField: true});
  });

  test('Wieder angelegt: nur Felder ab dem neuen Anlegen', () {
    final r = Replica()
      ..applyAll([
        c(deletedField, false, 1),
        c('note', 'alt', 1),
        c('extra', 'alt', 2), // unbekanntes Feld, beim Neuanlegen nicht gesetzt
        c(deletedField, true, 3),
        c(deletedField, false, 4),
        c('note', 'neu', 4),
      ]);
    expect(r.get('entry', 'e'), {'note': 'neu'});
  });

  test('Ergebnis hängt nicht von der Reihenfolge ab', () {
    final changes = [
      c(deletedField, false, 1),
      c('note', 'a', 1),
      c('quantity', 1, 1),
      c('note', 'b', 2),
      c(deletedField, true, 3),
      c('note', 'nach dem Löschen', 4), // gleichzeitige Bearbeitung
      c(deletedField, false, 5),
      c('note', 'c', 5),
      c('quantity', 3, 6),
      c('extra', 'x', 2),
    ];
    final expected = stored(Replica()..applyAll(changes));
    expect(expected, {
      deletedField: false,
      purgedField: true,
      'note': 'c',
      'quantity': 3,
    });
    final random = math.Random(7);
    for (var i = 0; i < 200; i++) {
      final shuffled = [...changes]..shuffle(random);
      expect(stored(Replica()..applyAll(shuffled)), expected);
    }
  });

  test('Gerät hat das Löschen verpasst: Markierung im Schnappschuss', () {
    final before = [c(deletedField, false, 1), c('note', 'alt', 1)];
    final offline = Replica()..applyAll(before);
    final online = Replica()
      ..applyAll(before)
      ..apply(c(deletedField, true, 2))
      ..applyAll([c(deletedField, false, 3), c('quantity', 1, 3)]);
    offline.applyAll(online.snapshot());
    expect(offline.get('entry', 'e'), {'quantity': 1});
    expect(stored(offline), stored(online));
  });

  test('Ohne Löschen bleiben ältere Felder beim Neuanlegen erhalten', () {
    // z. B. Produktdaten an einem Barcode, der neu zugeordnet wird
    final r = Replica()
      ..applyAll([
        c('product', 'Spaghetti n.5', 1),
        c(deletedField, false, 2),
        c('articleId', 'a', 2),
        c(deletedField, false, 3),
        c('articleId', 'b', 3),
      ]);
    expect(r.get('entry', 'e'), {'product': 'Spaghetti n.5', 'articleId': 'b'});
  });

  test('Lokal: Grabsteine ganz entfernen', () {
    final r = Replica()
      ..applyAll([c(deletedField, false, 1), c(deletedField, true, 2)])
      ..apply(
        Change(
          type: 'entry',
          id: 'f',
          field: 'note',
          value: 'bleibt',
          hlc: const Hlc(1, 0, 'n'),
        ),
      )
      ..dropTombstones();
    expect(r.snapshot().map((ch) => ch.id), ['f']);
  });
}
