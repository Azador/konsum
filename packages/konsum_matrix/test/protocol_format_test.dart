import 'dart:convert';

import 'package:konsum_core/konsum_core.dart';
import 'package:konsum_matrix/konsum_matrix.dart';
import 'package:test/test.dart';

/// Hält das Format fest, das PROTOKOLL.md beschreibt. Schlägt ein Test hier
/// fehl, ist das eine Protokolländerung: PROTOKOLL.md anpassen und prüfen,
/// ob `KonsumEvents.version` steigen muss.
void main() {
  test('Namen der Ereignistypen', () {
    expect(KonsumEvents.roomType, 'de.azadoro.konsum.group');
    expect(KonsumEvents.changes, 'de.azadoro.konsum.changes');
    expect(KonsumEvents.snapshotRequest, 'de.azadoro.konsum.snapshot_request');
    expect(KonsumEvents.private, 'de.azadoro.konsum.private');
    expect(KonsumEvents.version, 1);
  });

  test('Beispiel „Milch auf die Liste“', () {
    final group = Group(HlcClock('5a1b9c2d', now: () => 1761800000000));
    final list = group.createList('Einkauf');
    final article = group.createArticle('Milch', defaultUnit: Units.litre);
    final entry = group.addToList(list.id, article.id, quantity: 2);

    final content = jsonDecode(
      jsonEncode(
        encodeChanges([
          ...article.changes,
          ...entry,
        ], device: 'ABCDEFGHIJ').single,
      ),
    ) as Map<String, Object?>;
    expect(content.keys, ['v', 'device', 'changes']);
    expect(content['v'], 1);
    expect(content['device'], 'ABCDEFGHIJ');

    final changes = (content['changes'] as List).cast<Map<String, Object?>>();
    expect(changes.first.keys, ['type', 'id', 'field', 'value', 'hlc']);
    expect(article.id, matches(RegExp(r'^[0-9a-f]{32}$')));

    final articleFields = {
      for (final c in changes)
        if (c['type'] == 'article') c['field']: c['value'],
    };
    expect(articleFields, {
      'name': 'Milch',
      'categoryId': null,
      'defaultUnit': 'l',
      'packSize': null,
      'packUnit': null,
      '_deleted': false,
    });

    final entryChanges = changes.where((c) => c['type'] == 'entry').toList();
    expect(entryChanges.map((c) => c['id']).toSet(), {
      '${list.id}/${article.id}',
    });
    expect(
      {for (final c in entryChanges) c['field']: c['value']},
      {
        'listId': list.id,
        'articleId': article.id,
        'quantity': 2,
        'unit': 'l',
        'packSize': null,
        'packUnit': null,
        'note': null,
        'price': null,
        'basePrice': null,
        'checked': false,
        '_deleted': false,
      },
    );

    // Ein Befehl = ein Zeitstempel; die Liste kam vorher (Zähler 0).
    expect(articleFields.length, 6);
    expect(
      changes.where((c) => c['type'] == 'article').map((c) => c['hlc']).toSet(),
      {'1761800000000-1-5a1b9c2d'},
    );
    expect(entryChanges.map((c) => c['hlc']).toSet(), {
      '1761800000000-2-5a1b9c2d',
    });

    final checked = group.setChecked(list.id, article.id, true).single;
    expect(checked.toJson(), {
      'type': 'entry',
      'id': '${list.id}/${article.id}',
      'field': 'checked',
      'value': true,
      'hlc': '1761800000000-3-5a1b9c2d',
    });
  });

  test('Schnappschuss markiert, Anfrage ohne Changes', () {
    final c = Change(
      type: 'list',
      id: 'a',
      field: 'name',
      value: 'x',
      hlc: Hlc.parse('1-0-n'),
    );
    expect(
      encodeChanges([c], device: 'D', snapshot: true).single['snapshot'],
      true,
    );
    expect(
      encodeChanges([c], device: 'D').single.containsKey('snapshot'),
      isFalse,
    );
  });

  test('HLC: Ordnung und Textform', () {
    expect(Hlc.parse('10-0-b') > Hlc.parse('9-5-z'), isTrue);
    expect(Hlc.parse('10-1-a') > Hlc.parse('10-0-z'), isTrue);
    expect(Hlc.parse('10-1-b') > Hlc.parse('10-1-a'), isTrue);
    expect(Hlc.parse('10-1-node-mit-strich').node, 'node-mit-strich');
  });

  test('Unbekannte Typen und Felder bleiben im Schnappschuss', () {
    final hlc = Hlc.parse('5-0-fremd');
    final group = Group(HlcClock('eigen'))
      ..receive(
        decodeChanges({
          'v': 1,
          'device': 'X',
          'changes': [
            {
              'type': 'x.projekt.rezept',
              'id': 'r1',
              'field': 'titel',
              'value': 'Pfannkuchen',
              'hlc': '$hlc',
            },
            {'type': 'entry', 'id': 'kaputt'},
          ],
        }),
      );
    expect(group.replica.snapshot().map((c) => c.toJson()), [
      {
        'type': 'x.projekt.rezept',
        'id': 'r1',
        'field': 'titel',
        'value': 'Pfannkuchen',
        'hlc': '5-0-fremd',
      },
    ]);
  });
}
