import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:konsum_core/konsum_core.dart';
import 'package:konsum_matrix/konsum_matrix.dart';
import 'package:test/test.dart';

/// Simulierter Matrix-Raum: verteilt Ereignisse an alle verbundenen Geräte
/// (auch an den Absender, wie ein echter Sync) und hält Account Data je Benutzer.
class FakeRoom {
  final _devices = <FakeTransport>[];
  final _accountData = <String, Map<String, Map<String, Object?>>>{};
  final sent = <RoomEvent>[];
  bool online = true;

  FakeTransport connect(String user, String device) {
    final t = FakeTransport(this, user, device);
    _devices.add(t);
    return t;
  }

  void deliver(RoomEvent e) {
    sent.add(e);
    for (final d in _devices) {
      d._events.add(e);
    }
  }
}

class FakeTransport implements RoomTransport {
  FakeTransport(this._room, this.userId, this.deviceId);

  final FakeRoom _room;
  @override
  final String userId;
  @override
  final String deviceId;
  final _events = StreamController<RoomEvent>.broadcast(sync: true);
  final gapController = StreamController<void>.broadcast(sync: true);
  final _accountUpdates =
      StreamController<(String, Map<String, Object?>)>.broadcast(sync: true);

  @override
  Stream<RoomEvent> get events => _events.stream;

  @override
  Stream<void> get gaps => gapController.stream;

  @override
  Future<void> send(String type, Map<String, Object?> content) async {
    if (!_room.online) throw StateError('offline');
    // Wie über das Netz: Inhalt einmal durch JSON.
    final copy = jsonDecode(jsonEncode(content)) as Map<String, Object?>;
    _room.deliver(RoomEvent(type: type, senderId: userId, content: copy));
  }

  @override
  Map<String, Object?>? accountData(String type) =>
      _room._accountData[userId]?[type];

  @override
  Stream<(String, Map<String, Object?>)> get accountDataUpdates =>
      _accountUpdates.stream;

  @override
  Future<void> setAccountData(String type, Map<String, Object?> content) async {
    if (!_room.online) throw StateError('offline');
    final copy = jsonDecode(jsonEncode(content)) as Map<String, Object?>;
    _room._accountData.putIfAbsent(userId, () => {})[type] = copy;
    for (final d in _room._devices.where((d) => d.userId == userId)) {
      d._accountUpdates.add((type, copy));
    }
  }

  @override
  Future<void> close() async => _room._devices.remove(this);
}

/// Ein Gerät mit Gruppe und Sync, wie die App es zusammensteckt.
class Device {
  Device(
    FakeRoom room,
    String user,
    String device, {
    int seed = 0,
    Duration retryDelay = const Duration(minutes: 1),
  }) : this._(room.connect(user, device), device, seed, retryDelay);

  Device._(this.transport, String device, int seed, Duration retryDelay)
    : group = Group(HlcClock(device)),
      private = PrivateData(HlcClock(device)),
      sync = MatrixGroupSync(
        transport,
        random: math.Random(seed),
        maxReplyDelay: const Duration(milliseconds: 50),
        retryDelay: retryDelay,
        maxRetryDelay: retryDelay * 2,
      ) {
    sync.incoming.listen(group.receive);
    sync.incomingPrivate.listen(private.receive);
    sync.snapshotProvider = group.replica.snapshot;
  }

  final FakeTransport transport;
  final Group group;
  final PrivateData private;
  final MatrixGroupSync sync;

  Future<void> run(List<Change> changes) => sync.send(changes);
}

Future<void> settle() =>
    Future<void>.delayed(const Duration(milliseconds: 120));

void main() {
  test('Aufteilen in Ereignisse unter der Größengrenze', () {
    final g = Group(HlcClock('a'));
    final changes = [
      for (var i = 0; i < 200; i++) ...g.createArticle('Artikel $i').changes,
    ];
    final chunks = encodeChanges(changes, device: 'd', maxBytes: 4000);
    expect(chunks.length, greaterThan(1));
    for (final c in chunks) {
      expect(utf8.encode(jsonEncode(c)).length, lessThan(4500));
    }
    expect(chunks.expand(decodeChanges).length, changes.length);
  });

  test('Unbekannte Version wird ignoriert', () {
    expect(decodeChanges({'v': 99, 'changes': []}), isEmpty);
  });

  test('Änderungen kommen bei den anderen an, nicht als Echo zurück', () async {
    final room = FakeRoom();
    final alice = Device(room, '@alice:x', 'A1');
    final bob = Device(room, '@bob:x', 'B1');
    await settle();

    final list = alice.group.createList('Familie');
    await alice.run(list.changes);
    expect(bob.group.lists.single.name, 'Familie');

    var echoes = 0;
    alice.sync.incoming.listen((_) => echoes++);
    await alice.run(alice.group.renameList(list.id, 'Zuhause'));
    expect(echoes, 0);
    expect(bob.group.lists.single.name, 'Zuhause');
  });

  test('Neues Gerät ohne Daten bekommt den vollständigen Stand', () async {
    final room = FakeRoom();
    final alice = Device(room, '@alice:x', 'A1', seed: 1);
    final bob = Device(room, '@bob:x', 'B1', seed: 2);
    await settle();
    await alice.run(alice.group.createList('Familie').changes);
    await alice.run(alice.group.createArticle('Milch').changes);
    room.sent.clear();

    final laptop = Device(room, '@alice:x', 'A2', seed: 3);
    await settle();

    expect(laptop.group.lists.single.name, 'Familie');
    expect(laptop.group.articles.single.name, 'Milch');
    final snapshots = room.sent.where((e) => e.content['snapshot'] == true);
    expect(
      snapshots.map((e) => e.senderId).toSet(),
      hasLength(1),
      reason: 'nur einer antwortet',
    );
    expect(bob.group.articles, hasLength(1));
  });

  test('Beitritt eines Mitglieds löst Schnappschuss aus', () async {
    final room = FakeRoom();
    final alice = Device(room, '@alice:x', 'A1');
    await settle();
    await alice.run(alice.group.createList('Verein').changes);
    room.sent.clear();

    room.deliver(
      const RoomEvent(
        type: 'm.room.member',
        senderId: '@carol:x',
        stateKey: '@carol:x',
        content: {'membership': 'join'},
      ),
    );
    await settle();
    expect(room.sent.where((e) => e.content['snapshot'] == true), isNotEmpty);
  });

  test('Private Daten nur zwischen eigenen Geräten', () async {
    final room = FakeRoom();
    final phone = Device(room, '@alice:x', 'A1');
    final laptop = Device(room, '@alice:x', 'A2');
    final bob = Device(room, '@bob:x', 'B1');
    await settle();

    phone.private.setNote('l/a', 'nur Bio');
    await phone.sync.savePrivate(phone.private.replica.snapshot());
    expect(laptop.private.note('l/a'), 'nur Bio');
    expect(bob.private.note('l/a'), isNull);

    // Ein später gestartetes Gerät liest die gespeicherten Daten.
    final tablet = Device(room, '@alice:x', 'A3');
    await settle();
    expect(tablet.private.note('l/a'), 'nur Bio');
  });

  test('Lücke nach Offline-Zeit: Gerät holt den vollständigen Stand', () async {
    final room = FakeRoom();
    final alice = Device(room, '@alice:x', 'A1', seed: 1);
    final bob = Device(room, '@bob:x', 'B1', seed: 2);
    await settle();
    await alice.run(alice.group.createList('Familie').changes);

    // Änderung, die Bob „verpasst“ (nicht zugestellt).
    final missed = alice.group.createArticle('Brot').changes;
    expect(bob.group.articles, isEmpty);

    bob.transport.gapController.add(null);
    await settle();
    expect(bob.group.articles.single.name, 'Brot');
    expect(missed, isNotEmpty);
  });

  test('Offline: Senden wirft, Outbox behält die Änderungen', () async {
    final room = FakeRoom();
    final alice = Device(room, '@alice:x', 'A1');
    final bob = Device(room, '@bob:x', 'B1');
    await settle();
    final outbox = Outbox(alice.group.createList('Familie').changes);

    room.online = false;
    expect(await outbox.flush(alice.sync.send), isFalse);
    room.online = true;
    expect(await outbox.flush(alice.sync.send), isTrue);
    expect(bob.group.lists, hasLength(1));
  });

  test('Unbeantwortete Bitte wird wiederholt, bis Daten da sind', () async {
    final room = FakeRoom();
    const retry = Duration(milliseconds: 300);
    final phone = Device(room, '@a:x', 'P', retryDelay: retry);
    await settle();
    int requests() =>
        room.sent.where((e) => e.type == KonsumEvents.snapshotRequest).length;
    expect(requests(), 1); // niemand online, der antworten könnte

    // Ein Gerät mit Daten kommt später online.
    final laptop = Device(room, '@a:x', 'L', seed: 1, retryDelay: retry);
    laptop.group.createList('Einkauf');
    expect(phone.group.lists, isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(phone.group.lists.map((l) => l.name), ['Einkauf']);

    // Danach keine weiteren Bitten mehr.
    final after = requests();
    await Future<void>.delayed(const Duration(milliseconds: 1000));
    expect(requests(), after);
  });
}
