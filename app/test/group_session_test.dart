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
}
