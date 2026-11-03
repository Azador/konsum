import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:konsum/state/group_session.dart';
import 'package:konsum/storage/store.dart';
import 'package:konsum_core/konsum_core.dart';

void main() {
  test('Lokale Gruppe teilen: zweites Gerät erhält den Stand', () async {
    final hub = MemoryHub();
    final store = MemoryStore();
    final phone = GroupSession.create(
      GroupInfo(id: 'g', name: 'Familie'),
      'phone',
      store,
    );
    final list = phone.group.createList('Einkauf');
    phone.apply(list.changes);
    final milch = phone.group.createArticle('Milch');
    phone.apply([
      ...milch.changes,
      ...phone.group.addToList(list.id, milch.id),
    ]);
    expect(phone.outbox.isEmpty, isTrue, reason: 'noch lokal');

    final laptop = GroupSession.create(
      GroupInfo(id: 'g', name: 'Familie', backend: {'type': 'test'}),
      'laptop',
      MemoryStore(),
    );
    await laptop.attach(hub.connect('alice'));

    phone.share({'type': 'test'});
    await phone.attach(hub.connect('alice'));

    expect(phone.outbox.isEmpty, isTrue);
    expect(phone.status, SyncStatus.synced);
    expect(laptop.group.entries(list.id).single.articleId, milch.id);

    // Und zurück.
    laptop.apply(laptop.group.setChecked(list.id, milch.id, true));
    await Future<void>.delayed(Duration.zero);
    expect(phone.group.entries(list.id).single.checked, isTrue);

    await phone.save();
    await laptop.save();
  });

  test('Offline: Status und spätere Übertragung', () async {
    final hub = MemoryHub()..online = false;
    final a = GroupSession.create(
      GroupInfo(id: 'g', name: 'Verein', backend: {'type': 'test'}),
      'a',
      MemoryStore(),
    );
    final b = GroupSession.create(
      GroupInfo(id: 'g', name: 'Verein', backend: {'type': 'test'}),
      'b',
      MemoryStore(),
    );
    await a.attach(hub.connect('alice'));
    await b.attach(hub.connect('bob'));

    a.apply(a.group.createList('Grillfest').changes);
    await Future<void>.delayed(Duration.zero);
    expect(a.status, SyncStatus.offline);
    expect(b.group.lists, isEmpty);

    hub.online = true;
    await a.flush();
    expect(a.status, SyncStatus.synced);
    expect(b.group.lists.single.name, 'Grillfest');

    await a.save();
    await b.save();
  });

  test('Gelöschtes behält keinen Inhalt, private Notiz geht mit', () async {
    final hub = MemoryHub();
    final store = MemoryStore();
    final a = GroupSession.create(
      GroupInfo(id: 'g', name: 'Verein', backend: {'type': 'test'}),
      'a',
      store,
    );
    final b = GroupSession.create(
      GroupInfo(id: 'g', name: 'Verein', backend: {'type': 'test'}),
      'b',
      MemoryStore(),
    );
    await a.attach(hub.connect('alice'));
    await b.attach(hub.connect('alice'));
    final list = a.group.createList('Einkauf');
    final buch = a.group.createArticle('Buch');
    a.apply([
      ...list.changes,
      ...buch.changes,
      ...a.group.addToList(list.id, buch.id, note: 'gemeinsam'),
    ]);
    final entryId = '${list.id}/${buch.id}';
    a.applyPrivate(a.private.setNote(entryId, 'geheim'));
    b.applyPrivate(b.private.setNote(entryId, 'auch geheim'));
    await Future<void>.delayed(Duration.zero);

    a.apply(a.group.removeFromList(list.id, buch.id));
    await Future<void>.delayed(Duration.zero);

    for (final s in [a, b]) {
      expect(s.private.note(entryId), isNull);
      final entry = s.group.replica.snapshot().where(
        (c) => c.type == Types.entry && c.id == entryId,
      );
      expect(entry.map((c) => c.field).toSet(), {
        deletedField,
        purgedField,
      }, reason: 'nur Grabstein');
    }

    // Wieder hinzugefügt: keine alten Notizen.
    a.apply(a.group.addToList(list.id, buch.id));
    expect(a.group.entries(list.id).single.note, isNull);
    expect(a.private.note(entryId), isNull);
    await a.save();
    await b.save();
  });

  test('Lokale Gruppe: Gelöschtes verschwindet ganz', () async {
    final store = MemoryStore();
    final s = GroupSession.create(
      GroupInfo(id: 'g', name: 'Allein'),
      'a',
      store,
    );
    final list = s.group.createList('Einkauf');
    final buch = s.group.createArticle('Buch');
    s.apply([...list.changes, ...buch.changes]);
    s.apply(s.group.addToList(list.id, buch.id, note: 'weg damit'));
    s.apply(s.group.removeFromList(list.id, buch.id));
    s.apply(s.group.deleteArticle(buch.id));
    final ids = s.group.replica.snapshot().map((c) => c.id).toSet();
    expect(ids, {list.id});
    await s.save();
  });

  test('Veraltetes Gerät belebt Gelöschtes nicht wieder', () async {
    final hub = MemoryHub();
    final storeB = MemoryStore();
    GroupInfo info() =>
        GroupInfo(id: 'g', name: 'Verein', backend: {'type': 'test'});
    final a = GroupSession.create(info(), 'a', MemoryStore());
    var b = GroupSession.create(info(), 'b', storeB);
    await a.attach(hub.connect('alice'));
    await b.attach(hub.connect('bob'));
    a.apply(a.group.setRetentionMonths(1));
    final x = a.group.createArticle('Buch');
    a.apply(x.changes);
    await Future<void>.delayed(Duration.zero);
    hub.tick();
    expect(b.group.article(x.id), isNotNull);

    // B ist lange weg: zuletzt vor zwei Monaten synchronisiert.
    await b.detach();
    await b.save();
    final json = jsonDecode(storeB.values['group-g']!) as Map<String, Object?>;
    json['lastSync'] = DateTime.now()
        .subtract(const Duration(days: 62))
        .millisecondsSinceEpoch;
    storeB.values['group-g'] = jsonEncode(json);
    b = await GroupSession.load(info(), 'b', storeB);

    // Offline auf B: neuer Artikel, Bearbeitung des (anderswo gelöschten) X.
    final y = b.group.createArticle('Neu');
    b.apply([
      ...y.changes,
      ...b.group.updateArticle(x.id, {'name': 'Buch 2'}),
    ]);

    // A löscht X; der Grabstein ist inzwischen verfallen.
    a.apply(a.group.deleteArticle(x.id));
    a.group.replica.dropTombstonesBefore(
      DateTime.now().millisecondsSinceEpoch + 1,
    );

    final syncB = hub.connect('bob');
    await b.attach(syncB);
    await Future<void>.delayed(Duration.zero);

    expect(syncB.snapshotRequests, 1, reason: 'B fragt nach dem Stand');
    expect(b.status, isNot(SyncStatus.resyncing), reason: 'A hat geantwortet');
    expect(b.group.article(x.id), isNull, reason: 'X bleibt gelöscht');
    expect(b.group.article(y.id)?.name, 'Neu');
    expect(a.group.article(y.id)?.name, 'Neu', reason: 'B schickt Neues');
    expect(a.group.article(x.id), isNull, reason: 'keine Wiederbelebung');
    expect(
      a.group.replica.keys.contains((Types.article, x.id)),
      isFalse,
      reason: 'auch kein Rest von X bei A',
    );
    await a.save();
    await b.save();
  });
}
