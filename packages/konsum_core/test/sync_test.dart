import 'package:konsum_core/konsum_core.dart';
import 'package:test/test.dart';

void main() {
  test('Outbox hält Änderungen, bis Senden klappt', () async {
    final hub = MemoryHub();
    final sender = hub.connect('alice');
    final receiver = hub.connect('bob');
    final group = Group(HlcClock('a'));
    final received = <Change>[];
    receiver.incoming.listen(received.addAll);
    final outbox = Outbox();

    hub.online = false;
    outbox.add(group.createList('Familie').changes);
    expect(await outbox.flush(sender.send), isFalse);
    expect(outbox.pending, isNotEmpty);

    final restored = Outbox.fromJson(outbox.toJson());
    hub.online = true;
    expect(await restored.flush(sender.send), isTrue);
    expect(restored.isEmpty, isTrue);
    expect(received, hasLength(2));
  });

  test('Was während des Sendens hinzukommt, bleibt in der Outbox', () async {
    final group = Group(HlcClock('a'));
    final outbox = Outbox(group.createList('A').changes);
    final flushed = outbox.flush((_) async {
      outbox.add(group.createList('B').changes);
    });
    expect(await flushed, isFalse);
    expect(outbox.pending, hasLength(2));
  });

  test('Private Notizen gleichen sich zwischen eigenen Geräten ab', () async {
    final hub = MemoryHub();
    final phone = hub.connect('alice');
    final laptop = hub.connect('alice');
    final other = hub.connect('bob');
    final onPhone = PrivateData(HlcClock('phone'));
    final onLaptop = PrivateData(HlcClock('laptop'));
    laptop.incomingPrivate.listen(onLaptop.receive);
    var bobGotSomething = false;
    other.incomingPrivate.listen((_) => bobGotSomething = true);

    onPhone.setNote('liste/spaghetti', 'nur Barilla');
    await phone.savePrivate(onPhone.replica.snapshot());

    expect(onLaptop.note('liste/spaghetti'), 'nur Barilla');
    expect(bobGotSomething, isFalse);

    onLaptop.setNote('liste/spaghetti', '');
    expect(onLaptop.note('liste/spaghetti'), isNull);
  });
}
