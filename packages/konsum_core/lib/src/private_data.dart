import 'hlc.dart';
import 'replica.dart';

/// Private Daten eines Benutzers innerhalb einer Gruppe, z. B. private
/// Notizen zu Listeneinträgen. Sie werden nur zwischen den Geräten desselben
/// Benutzers abgeglichen, mit derselben Konfliktauflösung wie Gruppendaten.
class PrivateData {
  PrivateData(this.clock, {Replica? replica}) : replica = replica ?? Replica();

  static const _note = 'note';

  final HlcClock clock;
  final Replica replica;

  void receive(Iterable<Change> changes) {
    for (final c in changes) {
      clock.observe(c.hlc);
      replica.apply(c);
    }
  }

  /// Private Notiz zum Listeneintrag [entryId] (siehe `ListEntry.id`).
  String? note(String entryId) =>
      replica.get(_note, entryId)?['text'] as String?;

  /// Setzt die private Notiz; leerer Text oder null löscht sie.
  List<Change> setNote(String entryId, String? text) {
    final c = Change(
      type: _note,
      id: entryId,
      field: 'text',
      value: text == null || text.isEmpty ? null : text,
      hlc: clock.tick(),
    );
    replica.apply(c);
    return [c];
  }
}
