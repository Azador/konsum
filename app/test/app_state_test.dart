import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:konsum/state/app_state.dart';
import 'package:konsum/state/group_session.dart';
import 'package:konsum/storage/store.dart';

void main() {
  Future<AppState> load(MemoryStore store) =>
      AppState.load(store, random: math.Random(1));

  test('Geteilte Gruppe als lokale Kopie behalten', () async {
    final store = MemoryStore();
    final state = await load(store);
    final shared = await state.createGroup(
      'Zuhause',
      backend: {'type': 'matrix', 'roomId': '!raum:example.org'},
    );
    final r = shared.group.createArticle('Milch');
    shared.apply(r.changes);
    expect(shared.outbox.isEmpty, isFalse, reason: 'noch nicht verschickt');

    await state.keepAsLocal(shared);

    expect(shared.info.backend, isNull);
    expect(shared.status, SyncStatus.local);
    expect(shared.outbox.isEmpty, isTrue);
    expect(shared.group.articles.single.name, 'Milch', reason: 'Daten bleiben');
    // Die Startgruppe heißt ebenfalls „Zuhause“; die Kopie ist unterscheidbar.
    expect(shared.info.name, 'Zuhause (lokal)');

    await shared.save();
    final again = await load(store);
    final copy = again.groups.firstWhere((g) => g.id == shared.id);
    expect(copy.info.backend, isNull);
    expect(copy.info.name, 'Zuhause (lokal)');
  });

  test('Name der lokalen Kopie wird hochgezählt', () async {
    final state = await load(MemoryStore());
    await state.createGroup('Verein (lokal)');
    await state.createGroup('Verein (lokal 2)');
    expect(state.localCopyName('Verein'), 'Verein (lokal 3)');
    expect(state.localCopyName('Anderes'), 'Anderes (lokal)');
  });
}
