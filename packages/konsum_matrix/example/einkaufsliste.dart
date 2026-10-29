// Beispiel: eine Konsum-Einkaufsliste aus einem anderen Dart-Programm nutzen.
//
// Erwartet einen angemeldeten, synchronisierenden Matrix-Client (Paket
// `matrix`). Für verschlüsselte Gruppen muss der Client verschlüsseln können
// (vodozemac) und Schlüssel an alle Geräte verteilen:
//
//   Client('MeinProjekt', database: …, shareKeysWith: ShareKeysWith.all)
import 'package:konsum_core/konsum_core.dart';
import 'package:konsum_matrix/konsum_matrix.dart';
// `matrix` hat eine eigene Klasse `Group`; nur das Nötige importieren.
import 'package:matrix/matrix.dart' show Client;

/// Verbindet die erste Konsum-Gruppe des Kontos (oder legt eine an), setzt
/// „Milch“ auf die erste Liste und gibt bei jeder Änderung die Liste aus.
Future<void> run(Client client, {required String node}) async {
  final groups = MatrixGroups(client);
  final roomId = switch (groups.groups.where((g) => !g.invited)) {
    final joined when joined.isNotEmpty => joined.first.roomId,
    _ => await groups.create('Haushalt'),
  };

  // Stand der Gruppe und ausstehende Änderungen. Ein echtes Programm
  // speichert beides (`replica.snapshot()`, `outbox.toJson()`) und lädt es
  // beim nächsten Start mit `group.receive(…)` bzw. `Outbox.fromJson(…)`.
  // [node] ist eine feste, zufällige Kennung dieser Installation.
  final group = Group(HlcClock(node));
  final outbox = Outbox();

  final sync = groups.sync(roomId)..snapshotProvider = group.replica.snapshot;
  sync.incoming.listen((changes) {
    group.receive(changes);
    _print(group);
  });

  Future<void> apply(List<Change> changes) async {
    outbox.add(changes);
    await outbox.flush(sync.send); // offline: bleibt in der Outbox
  }

  // Ein leeres Gerät bekommt den Stand per Schnappschuss von einem anderen
  // Mitglied; bis dahin kurz warten, statt eine zweite Liste anzulegen.
  await Future<void>.delayed(const Duration(seconds: 10));

  final listId = group.lists.isNotEmpty
      ? group.lists.first.id
      : await () async {
          final created = group.createList('Einkauf');
          await apply(created.changes);
          return created.id;
        }();

  final milk = group.articles.where((a) => a.name == 'Milch').firstOrNull;
  final articleId =
      milk?.id ??
      await () async {
        final created = group.createArticle('Milch', defaultUnit: Units.litre);
        await apply(created.changes);
        return created.id;
      }();

  await apply(group.addToList(listId, articleId, quantity: 2));
  _print(group);
}

void _print(Group group) {
  for (final list in group.lists) {
    print('${list.name}:');
    for (final e in group.entries(list.id)) {
      final mark = e.checked ? 'x' : ' ';
      final amount = e.quantity == null ? '' : ' ${e.quantity} ${e.unit ?? ''}';
      print('  [$mark] ${group.article(e.articleId)!.name}$amount');
    }
  }
}
