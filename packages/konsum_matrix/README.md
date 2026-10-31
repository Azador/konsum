# konsum_matrix

Konsum-Einkaufslisten über Matrix synchronisieren – zum Einbinden in andere
Dart- und Flutter-Projekte. Das Protokoll selbst (für andere Sprachen) steht
in [PROTOKOLL.md](../../PROTOKOLL.md).

## Einbinden

Die Pakete liegen nicht auf pub.dev, sondern werden direkt aus dem
Git-Repository eingebunden. `konsum_core` kommt dabei automatisch mit.

```yaml
dependencies:
  konsum_matrix:
    git:
      url: https://github.com/Azador/konsum.git
      path: packages/konsum_matrix
      ref: main            # oder ein Commit/Tag, um den Stand festzuhalten
  matrix: ^14.2.0
```

Lokal geht auch `path: /pfad/zu/Einkaufsliste/packages/konsum_matrix`.

## Bausteine

| Klasse | Paket | Aufgabe |
|---|---|---|
| `MatrixGroups` | konsum_matrix | Konsum-Räume eines Kontos finden, anlegen, einladen, beitreten, verlassen |
| `MatrixGroupSync` | konsum_matrix | Verbindung einer Gruppe zu ihrem Raum: Changes senden/empfangen, Schnappschüsse, private Daten |
| `Group` | konsum_core | Stand einer Gruppe mit Abfragen (`lists`, `entries`, `articles`, …) und Befehlen (`createList`, `addToList`, `setChecked`, `clearChecked`, …). Befehle liefern die Changes, die verschickt werden müssen. |
| `PrivateData` | konsum_core | private Notizen (`MatrixGroupSync.savePrivate`/`incomingPrivate`) |
| `Outbox` | konsum_core | Warteschlange für Changes, solange das Gerät offline ist |

Das Zusammenspiel zeigt [example/einkaufsliste.dart](example/einkaufsliste.dart);
die Konsum-App macht dasselbe in `app/lib/state/group_session.dart`.

Wichtig:

- Der Matrix-`Client` gehört dem einbindenden Programm (Anmeldung, Datenbank,
  Sync). Für verschlüsselte Gruppen braucht er vodozemac und
  `shareKeysWith: ShareKeysWith.all`, sonst bekommen Konsum-Geräte keine
  Schlüssel (Konsum hat keine Geräte-Verifizierung).
- `HlcClock(node)`: `node` ist eine feste, zufällige Kennung der Installation
  (Konsum: 8 Hex-Zeichen), nicht die Matrix-Geräte-ID.
- Das Matrix-SDK exportiert ebenfalls eine Klasse `Group`. In Dateien, die
  beides brauchen: `import 'package:matrix/matrix.dart' hide Group;`
- Stand (`group.replica.snapshot()`) und Outbox (`outbox.toJson()`) selbst
  speichern und beim Start wieder laden; ohne gespeicherten Stand fordert das
  Gerät bei jedem Start einen Schnappschuss an.

## Lizenz

GPL-3.0 wie das ganze Projekt. Das Matrix-SDK `matrix` steht unter AGPL-3.0.
