# Konsum – Matrix-Protokoll

Stand: 2026-10-30 · Protokollversion **1**

Diese Beschreibung reicht, um eine Konsum-Einkaufsliste aus einem anderen
Programm heraus zu lesen und zu bearbeiten – in jeder Sprache, mit jeder
Matrix-Bibliothek. Wer Dart verwendet, kann stattdessen die fertigen Pakete
einbinden, siehe [packages/konsum_matrix/README.md](packages/konsum_matrix/README.md).

Die Referenzumsetzung steht in `packages/konsum_core` (Datenmodell,
Konfliktauflösung) und `packages/konsum_matrix` (Matrix-Anbindung). Bei
Widersprüchen gilt der Code; bitte dann diese Datei korrigieren.

## Überblick

- Eine **Gruppe** (Haushalt, Verein) ist ein Matrix-Raum. Mitglieder werden
  über die normale Raumverwaltung eingeladen und entfernt.
- Der Inhalt der Gruppe (Listen, Artikel, Einträge, …) ist eine Menge von
  **Objekten** mit **Feldern**. Jede Änderung eines Feldes ist ein
  **Change** mit einem Zeitstempel (Hybrid Logical Clock, HLC).
- Changes werden gebündelt als Timeline-Ereignisse in den Raum geschrieben.
  Jedes Gerät wendet alle Changes auf seinen lokalen Stand an. Pro Feld
  gewinnt der größte Zeitstempel. Dadurch spielt weder die Reihenfolge noch
  doppelte Zustellung eine Rolle, und alle Geräte kommen zum selben Stand.
- Wer neu ist (neues Gerät, neues Mitglied, Lücke in der Timeline), bittet um
  einen **Schnappschuss**: Ein anderes Gerät schickt seinen vollständigen
  Stand als Changes.
- **Private Daten** (private Notizen) liegen in der Room Account Data des
  Benutzers.

## Raum

Eine Gruppe ist ein Raum, dessen `m.room.create`-Ereignis den Raumtyp trägt:

```json
{ "type": "de.azadoro.konsum.group" }
```

Konsum legt Räume so an:

| Einstellung | Wert |
|---|---|
| `preset` | `private_chat` (nur Eingeladene können beitreten) |
| `creation_content.type` | `de.azadoro.konsum.group` |
| `m.room.history_visibility` | `shared` |
| `m.room.encryption` | `m.megolm.v1.aes-sha2`, wenn der Client verschlüsseln kann |
| `m.room.name` | Name der Gruppe |
| `m.room.retention` | `{max_lifetime: <ms>}` aus `settings.retentionMonths` (Monate × 31 Tage), ohne `max_lifetime` bei `0`; siehe unten |

**Aufbewahrungsfrist im Raum** (MSC1763, noch nicht in der Spezifikation):
Jedes Gerät, das den Zustand `m.room.retention` setzen darf, gleicht ihn mit
`settings.retentionMonths` ab. Jeder beteiligte Server setzt die Frist für
seine Kopie des Raums selbst um – oder nicht. Konsum braucht die Historie des
Raums nicht (neue Geräte bekommen einen Schnappschuss), gelöschte Ereignisse
schaden also nicht.

Ein Client erkennt Konsum-Gruppen ausschließlich am Raumtyp. Räume ohne
diesen Typ sind keine Konsum-Gruppen.


**Verschlüsselung:** Gruppen sind normalerweise Ende-zu-Ende-verschlüsselt.
Ein Client, der Megolm nicht kann, sieht in solchen Räumen nur
`m.room.encrypted` und kann nicht teilnehmen. Konsum verschickt Raumschlüssel
an alle Geräte der Mitglieder, auch an unverifizierte. Damit ein fremder
Client Schlüssel von Konsum-Geräten bekommt, braucht er also keine
Verifizierung; umgekehrt sollte er seine Schlüssel ebenfalls an
unverifizierte Geräte verteilen, sonst können Konsum-Geräte seine Ereignisse
nicht lesen.

## Ereignisse

Alle Inhalte sind JSON-Objekte mit dem Feld `v` (Protokollversion, derzeit
`1`). Inhalte mit einer anderen Version werden ignoriert.

### `de.azadoro.konsum.changes` (Timeline)

Änderungen an den Gruppendaten.

```json
{
  "v": 1,
  "device": "ABCDEFGHIJ",
  "snapshot": true,
  "changes": [ <Change>, … ]
}
```

| Feld | Bedeutung |
|---|---|
| `device` | Matrix-Geräte-ID des Absenders. Damit erkennt ein Gerät seine eigenen Ereignisse. |
| `snapshot` | Nur vorhanden (`true`), wenn das Ereignis Teil eines Schnappschusses ist. |
| `changes` | Liste von Changes, siehe unten. |

**Größe:** Der JSON-Text der Changes eines Ereignisses bleibt unter 24 KiB
(Matrix erlaubt 64 KiB je Ereignis; Verschlüsselung und Base64 vergrößern
den Inhalt). Mehr Changes werden auf mehrere Ereignisse verteilt. Die
Aufteilung hat keine Bedeutung; Empfänger behandeln jedes Ereignis für sich.

### `de.azadoro.konsum.snapshot_request` (Timeline)

Bitte um den vollständigen Stand.

```json
{ "v": 1, "device": "ABCDEFGHIJ" }
```

### `de.azadoro.konsum.private` (Room Account Data)

Private Daten des Benutzers in dieser Gruppe, als **vollständiger Stand**
(nicht als Änderung). Gleicher Aufbau wie `de.azadoro.konsum.changes`, ohne
`snapshot`, immer als ein einziges Objekt:

```json
{ "v": 1, "device": "ABCDEFGHIJ", "changes": [ <Change>, … ] }
```

Room Account Data ist **nicht** Ende-zu-Ende-verschlüsselt; der Server kann
sie lesen.

## Change

Ein Change setzt ein Feld eines Objekts:

```json
{
  "type": "entry",
  "id": "3f9c…/a41e…",
  "field": "checked",
  "value": true,
  "hlc": "1761800000000-0-5a1b9c2d"
}
```

| Feld | Bedeutung |
|---|---|
| `type` | Objekttyp, siehe [Datenmodell](#datenmodell) |
| `id` | Objekt-ID innerhalb des Typs |
| `field` | Feldname |
| `value` | Beliebiger JSON-Wert, auch `null` |
| `hlc` | Zeitstempel als Text, siehe [Zeitstempel](#zeitstempel-hlc) |

### Anwenden (Konfliktauflösung)

Jedes Gerät hält für jedes Feld `(type, id, field)` den Wert und den
Zeitstempel des zuletzt gewonnenen Changes. Ein eingehender Change wird
übernommen, **wenn das Feld noch keinen Wert hat oder sein Zeitstempel
echt größer ist** als der gespeicherte. Sonst wird er verworfen.

Dieses Anwenden ist idempotent und reihenfolgeunabhängig. Changes dürfen also
mehrfach, verspätet und in beliebiger Reihenfolge eintreffen.

### Löschen

Gelöscht wird nicht, sondern markiert: Das Feld `_deleted` mit Wert `true`
(Tombstone). Ein Objekt **existiert**, wenn es mindestens ein Feld hat und
`_deleted` nicht `true` ist. `_deleted` und `_purged` gehören nicht zu den
Daten des Objekts. Beim Anlegen setzt Konsum `_deleted` auf
`false`; so kann ein Objekt nach dem Löschen wieder angelegt werden (z. B.
ein Artikel, der erneut auf die Liste kommt).

Tombstones bleiben im Stand und gehören in jeden Schnappschuss, sonst würden
gelöschte Objekte durch ältere Geräte wiederbelebt.

**Kein Inhalt in Tombstones** (Datensparsamkeit): Wer einen Tombstone
anwendet, setzt zusätzlich das Feld `_purged` (Wert `true`) mit dem
Zeitstempel des Tombstones, sofern das neuer ist als ein vorhandenes
`_purged`. Ein Gerät verwirft alle Felder eines Objekts (außer `_deleted` und
`_purged`), deren Zeitstempel **kleiner oder gleich** dem von `_purged` ist,
und nimmt solche Changes auch später nicht mehr an – auch nachdem das Objekt
wieder angelegt wurde. Neuere Felder (gleichzeitige Bearbeitung, erneutes
Anlegen) bleiben. `_purged` gehört wie jedes Feld in Schnappschüsse; so
verwirft auch ein Gerät, das das Löschen verpasst hat, denselben Inhalt.

Das Ergebnis hängt nicht von der Reihenfolge ab. Clients, die `_purged` nicht
kennen, bewahren es als unbekanntes Feld und geben es weiter; schicken sie
Tombstones mit Inhalt, wird dieser beim Empfang verworfen. Wer ein Objekt
wieder anlegt, schreibt alle Felder neu, die es haben soll.

### Unbekanntes bewahren

Ein Client muss Changes mit unbekanntem `type` oder `field` genauso speichern
und in Schnappschüssen weitergeben wie bekannte. Nur so gehen Daten neuerer
oder anderer Clients nicht verloren, wenn ein Gerät dieses Clients einen
Schnappschuss liefert. Kaputte einzelne Changes (fehlende Felder, ungültiger
`hlc`) werden übersprungen, der Rest des Ereignisses gilt.

## Zeitstempel (HLC)

Textform: `<millis>-<counter>-<node>`, z. B. `1761800000000-0-5a1b9c2d`.

| Teil | Bedeutung |
|---|---|
| `millis` | Unix-Zeit in Millisekunden (ganze Zahl ≥ 0) |
| `counter` | Zähler (ganze Zahl ≥ 0) für mehrere Zeitstempel in derselben Millisekunde |
| `node` | Kennung der Installation, eindeutig über alle Geräte der Gruppe. Konsum verwendet 8 zufällige Hex-Zeichen. Darf `-` enthalten (der Text wird nur an den ersten beiden `-` getrennt), sollte aber aus `[0-9a-z]` bestehen. |

**Ordnung:** zuerst `millis`, dann `counter` (beide numerisch), dann `node`
(Text, zeichenweise nach UTF-16-Codeeinheiten; bei `[0-9a-z]` einfach alphabetisch).

**Uhr eines Geräts:** Das Gerät merkt sich den letzten Zeitstempel
`(m, c)`.

- *Lokale Änderung:* `m' = max(m, jetzt)`; `c' = c + 1`, falls `m' = m`,
  sonst `0`.
- *Empfang eines Changes mit `(mr, cr)`:* `m' = max(jetzt, m, mr)`;
  `c'` = `max(c, cr) + 1`, falls `m' = m = mr`; `c + 1`, falls nur `m' = m`;
  `cr + 1`, falls nur `m' = mr`; sonst `0`.

Beim Start stellt das Gerät seine Uhr nach dem größten Zeitstempel in seinem
gespeicherten Stand. Alle Felder, die ein Befehl gemeinsam schreibt (z. B.
alle Felder eines neuen Artikels), bekommen denselben Zeitstempel.

## Ablauf

### Senden

Jede lokale Änderung erzeugt Changes, die sofort lokal angewendet und dann als
`de.azadoro.konsum.changes` verschickt werden. Ist das Gerät offline, bleiben
sie in einer Warteschlange und gehen später raus. Ein Gerät sendet nur
Changes, die es selbst erzeugt hat – außer im Schnappschuss.

### Empfangen

- `de.azadoro.konsum.changes`: Ereignisse des **eigenen Geräts** (Absender =
  eigenes Konto **und** `device` = eigene Geräte-ID) überspringen; alle
  anderen anwenden. Andere Geräte desselben Kontos werden also ganz normal
  behandelt.
- Hat ein Gerät einen Schnappschuss-Versand geplant (siehe unten) und kommt
  ein Ereignis mit `snapshot: true` von einem anderen Gerät, verzichtet es auf
  seinen eigenen Versand.

### Schnappschuss anfordern

Ein Gerät sendet `de.azadoro.konsum.snapshot_request`,

- wenn es eine Gruppe öffnet und lokal noch keine Daten dazu hat,
- wenn der Server nach längerer Offline-Zeit nicht alle Ereignisse liefert
  (`limited: true` in der Timeline des Sync),
- wenn sich ein verschlüsseltes Ereignis 2 Minuten lang nicht entschlüsseln
  lässt (fehlender Raumschlüssel).

Neue Geräte und neue Mitglieder können ältere verschlüsselte Ereignisse meist
nicht entschlüsseln; deshalb wird die Historie nicht nachgelesen, sondern der
Stand neu verteilt.

### Schnappschuss liefern

Ein Gerät plant einen Versand, wenn es

- eine `snapshot_request` von einem anderen Gerät sieht, oder
- sieht, dass ein **anderer** Benutzer dem Raum beitritt
  (`m.room.member` mit `membership: join`).

Es wartet eine zufällige Zeit zwischen 0 und 3 Sekunden. Ist bis dahin kein
Schnappschuss eines anderen Geräts eingetroffen und ist der eigene Stand nicht
leer, schickt es seinen **vollständigen Stand** (alle Felder aller Objekte,
inklusive Tombstones und unbekannter Typen, jeweils mit ihrem gespeicherten
Zeitstempel) als `de.azadoro.konsum.changes` mit `snapshot: true`, aufgeteilt
nach der Größengrenze. Mehrere gleichzeitige Schnappschüsse schaden nicht,
sie kosten nur Platz.

Jeder Teil eines Schnappschusses trägt zusätzlich `snapshotId` (zufälliger
Text, gleich für alle Teile), `part` (ab 0) und `parts` (Anzahl). Damit
erkennt ein Empfänger, wann er einen **vollständigen** Schnappschuss hat.
Ältere Clients ignorieren die Felder.

### Veraltetes Gerät

Ein Gerät merkt sich je Gruppe, wann es zuletzt **lückenlos** mit dem Raum
synchronisiert hat (ein Sync ohne `limited: true` für diesen Raum). Liegt das
länger zurück als die Aufbewahrungsfrist (`settings.retentionMonths`), kann es
Tombstones verpasst haben, die auf den anderen Geräten schon verfallen sind.
Sein Stand würde dort gelöschte Objekte wiederbeleben. Ein solches Gerät

1. verschickt keine Schnappschüsse und hält seine ausstehenden Changes
   zurück,
2. sendet `snapshot_request` und wiederholt das in wachsenden Abständen, bis
   ein **vollständiger** Schnappschuss eines anderen Geräts eingetroffen ist
   (die Changes wendet es wie immer an),
3. entfernt dann alle Objekte, die weder im Schnappschuss stehen noch seit
   der Anfrage durch eingehende Changes berührt wurden noch von ihm selbst
   (ausstehend) neu angelegt wurden (`_deleted: false` in der Warteschlange),
4. verwirft ausstehende Changes an entfernten Objekten, verschickt den Rest
   und verhält sich wieder normal.

Mit `retentionMonths: 0` (ohne automatisches Löschen) ist kein Gerät veraltet.

### Private Daten

Beim Öffnen liest das Gerät `de.azadoro.konsum.private` aus der Room Account
Data und wendet die Changes an. Nach einer lokalen Änderung schreibt es den
**vollständigen** privaten Stand zurück. Kommt über den Sync eine neue Fassung
(von einem anderen eigenen Gerät), wird sie mit derselben Regel wie oben
zusammengeführt, nicht ersetzt. Private Daten haben eine eigene Uhr mit
derselben `node`.

## Datenmodell

Objekt-IDs sind, wo nicht anders angegeben, 32 zufällige Hex-Zeichen
(16 Byte). Felder, die fehlen oder `null` sind, gelten als nicht gesetzt.
Geldbeträge sind ganze **Cent** bzw. Cent je Grundeinheit.

### `list` – Einkaufsliste

| Feld | Typ | |
|---|---|---|
| `name` | Text | |
| `_deleted` | bool | |

Beim Löschen einer Liste werden auch ihre Einträge gelöscht.

### `article` – Artikel (Artikelstamm der Gruppe)

| Feld | Typ | |
|---|---|---|
| `name` | Text | |
| `categoryId` | ID \| null | `category` |
| `defaultUnit` | Einheit \| null | Vorgabe beim Hinzufügen |
| `packSize` | Zahl \| null | übliche Packungsgröße, z. B. `500` … |
| `packUnit` | Einheit \| null | … `g`; nur `g`, `kg`, `ml`, `l`, `pcs` |
| `_deleted` | bool | |

Ein Artikel bleibt bestehen, wenn er von einer Liste genommen wird. Beim
endgültigen Löschen werden auch seine Barcodes, Einträge, Käufe und Preise
gelöscht.

### `entry` – Artikel auf einer Liste

ID: `<listId>/<articleId>`. Jeder Artikel steht also höchstens einmal auf
einer Liste; setzen zwei Personen gleichzeitig denselben Artikel auf die
Liste, entsteht kein Duplikat.

| Feld | Typ | |
|---|---|---|
| `listId` | ID | |
| `articleId` | ID | |
| `quantity` | Zahl \| null | Menge |
| `unit` | Einheit \| null | ohne Einheit gilt `pack` |
| `packSize` | Zahl \| null | Inhalt je Stück/Packung; ohne Wert gilt der des Artikels |
| `packUnit` | Einheit \| null | |
| `note` | Text \| null | gemeinsame Notiz |
| `checked` | bool | abgehakt |
| `price` | Ganzzahl \| null | Preis in Cent für die Menge |
| `basePrice` | Zahl \| null | Preis in Cent je Grundeinheit (kg, l, Stück, …); hat Vorrang vor `price` |
| `_deleted` | bool | |

Einträge, deren Artikel nicht existiert, werden nicht angezeigt. Wer einen
Eintrag anlegt, legt also vorher (oder im selben Ereignis) den Artikel an.

**Hinzufügen** schreibt alle Felder: `listId`, `articleId`, `quantity`,
`unit` (Vorgabe: `defaultUnit` des Artikels), `packSize`/`packUnit` (vom
Artikel), `note`, `price: null`, `basePrice: null`, `checked: false`,
`_deleted: false`.

**Aufräumen** („abgehakte entfernen“): für jeden abgehakten Eintrag einen
`purchase` anlegen, bei bekanntem Preis einen `price` anlegen, den Eintrag
löschen.

### `category` – Warengruppe

| Feld | Typ |
|---|---|
| `name` | Text |
| `_deleted` | bool |

### `shop` – Laden

| Feld | Typ | |
|---|---|---|
| `name` | Text | |
| `categoryOrder` | Liste von IDs | Reihenfolge der Kategorien im Laden |
| `_deleted` | bool | |

Mit gewähltem Laden werden Einträge nach dieser Reihenfolge sortiert (Artikel
ohne oder mit fehlender Kategorie am Ende), sonst alphabetisch.

### `barcode` – EAN/GTIN eines Artikels

ID: der Barcode selbst (z. B. `4006040012345`). Ein Barcode gehört genau
einem Artikel.

| Feld | Typ | |
|---|---|---|
| `articleId` | ID | |
| `product` | Objekt \| null | Produktdaten, z. B. von Open Food Facts: `name`, `brand`, `quantity` (Text, „500 g“), `imageUrl`, `nutriments` (je 100 g/ml, Schlüssel wie bei Open Food Facts), `nutriScore`, `productType` |
| `_deleted` | bool | |

### `purchase` – abgeschlossener Kauf (nur anlegen, nie ändern)

| Feld | Typ | |
|---|---|---|
| `articleId` | ID | |
| `listId` | ID | |
| `millis` | Ganzzahl | Zeitpunkt (Unix-Millisekunden) |
| `shopId` | ID \| null | |

Grundlage für Vorschläge (häufig gekaufte Artikel zuerst).
Käufe verfallen nach der Aufbewahrungsfrist (siehe `settings`).

### `price` – Preishistorie (nur anlegen oder löschen)

| Feld | Typ | |
|---|---|---|
| `articleId` | ID | |
| `cents` | Ganzzahl | Preis für `quantity` `unit` |
| `quantity`, `unit`, `packSize`, `packUnit` | wie bei `entry` | |
| `shopId` | ID \| null | |
| `millis` | Ganzzahl | Zeitpunkt |

### `settings` – Einstellungen der Gruppe

Ein einziges Objekt mit der ID `group`.

| Feld | Typ | |
|---|---|---|
| `retentionMonths` | Ganzzahl \| null | Aufbewahrungsfrist in Monaten; `0` = ohne automatisches Löschen; fehlt der Wert, gelten **6** |

**Verfall:** Jedes Gerät entfernt selbstständig `purchase`-Objekte, deren
`millis` älter ist als die Frist, und Tombstones, deren `_deleted`-Zeitstempel
älter ist – vollständig, ohne Tombstone und ohne etwas zu verschicken.
Verfallenes gehört in keinen Schnappschuss; trifft es (von einem Gerät, das
noch nicht aufgeräumt hat) erneut ein, wird es beim nächsten Verfall wieder
entfernt. Die Frist wird kalendarisch berechnet (heute minus N Monate).

### Einheiten

`pcs` (Stück), `g`, `kg`, `ml`, `l`, `pack` (Packung), `can` (Dose),
`bottle` (Flasche), `bunch` (Bund), `crate` (Kiste). `g`, `kg`, `ml`, `l`
sind Maße, der Rest Zähleinheiten. Grundeinheiten für Preise: `kg` für
Gewicht, `l` für Volumen, sonst die Zähleinheit; bei Zähleinheiten mit
`packSize` in einem Maß wird über das Maß gerechnet, mit `packSize` in `pcs`
oder `bottle` (z. B. Packung mit 6 Stück, Kiste mit 20 Flaschen) über deren
Anzahl mit Grundeinheit `pcs` bzw. `bottle`. Eine Einheit je derselben
Einheit (`pcs` je `pcs`, `bottle` je `bottle`) wird ignoriert. Ältere
Clients kennen `pcs` bzw. `bottle` als `packUnit` nicht und rechnen dann in
der Zähleinheit. Unbekannte Einheiten anderer Clients bitte als Text
anzeigen.

### Private Daten: `note`

In `de.azadoro.konsum.private`. ID: die ID des Listeneintrags
(`<listId>/<articleId>`).

| Feld | Typ |
|---|---|
| `text` | Text \| null (null = keine Notiz) |

## Beispiel: „Milch“ auf die Liste setzen

Die Liste `0a1b…` existiert, der Artikel noch nicht. Ein Ereignis
`de.azadoro.konsum.changes`:

```json
{
  "v": 1,
  "device": "ABCDEFGHIJ",
  "changes": [
    {"type": "article", "id": "c0ffee00c0ffee00c0ffee00c0ffee00", "field": "name",        "value": "Milch", "hlc": "1761800000000-0-5a1b9c2d"},
    {"type": "article", "id": "c0ffee00c0ffee00c0ffee00c0ffee00", "field": "categoryId",  "value": null,    "hlc": "1761800000000-0-5a1b9c2d"},
    {"type": "article", "id": "c0ffee00c0ffee00c0ffee00c0ffee00", "field": "defaultUnit", "value": "l",     "hlc": "1761800000000-0-5a1b9c2d"},
    {"type": "article", "id": "c0ffee00c0ffee00c0ffee00c0ffee00", "field": "packSize",    "value": null,    "hlc": "1761800000000-0-5a1b9c2d"},
    {"type": "article", "id": "c0ffee00c0ffee00c0ffee00c0ffee00", "field": "packUnit",    "value": null,    "hlc": "1761800000000-0-5a1b9c2d"},
    {"type": "article", "id": "c0ffee00c0ffee00c0ffee00c0ffee00", "field": "_deleted",    "value": false,   "hlc": "1761800000000-0-5a1b9c2d"},
    {"type": "entry", "id": "0a1b…/c0ffee00c0ffee00c0ffee00c0ffee00", "field": "listId",    "value": "0a1b…", "hlc": "1761800000000-1-5a1b9c2d"},
    {"type": "entry", "id": "0a1b…/c0ffee00c0ffee00c0ffee00c0ffee00", "field": "articleId", "value": "c0ffee00c0ffee00c0ffee00c0ffee00", "hlc": "1761800000000-1-5a1b9c2d"},
    {"type": "entry", "id": "0a1b…/c0ffee00c0ffee00c0ffee00c0ffee00", "field": "quantity",  "value": 2,     "hlc": "1761800000000-1-5a1b9c2d"},
    {"type": "entry", "id": "0a1b…/c0ffee00c0ffee00c0ffee00c0ffee00", "field": "unit",      "value": "l",   "hlc": "1761800000000-1-5a1b9c2d"},
    {"type": "entry", "id": "0a1b…/c0ffee00c0ffee00c0ffee00c0ffee00", "field": "packSize",  "value": null,  "hlc": "1761800000000-1-5a1b9c2d"},
    {"type": "entry", "id": "0a1b…/c0ffee00c0ffee00c0ffee00c0ffee00", "field": "packUnit",  "value": null,  "hlc": "1761800000000-1-5a1b9c2d"},
    {"type": "entry", "id": "0a1b…/c0ffee00c0ffee00c0ffee00c0ffee00", "field": "note",      "value": null,  "hlc": "1761800000000-1-5a1b9c2d"},
    {"type": "entry", "id": "0a1b…/c0ffee00c0ffee00c0ffee00c0ffee00", "field": "price",     "value": null,  "hlc": "1761800000000-1-5a1b9c2d"},
    {"type": "entry", "id": "0a1b…/c0ffee00c0ffee00c0ffee00c0ffee00", "field": "basePrice", "value": null,  "hlc": "1761800000000-1-5a1b9c2d"},
    {"type": "entry", "id": "0a1b…/c0ffee00c0ffee00c0ffee00c0ffee00", "field": "checked",   "value": false, "hlc": "1761800000000-1-5a1b9c2d"},
    {"type": "entry", "id": "0a1b…/c0ffee00c0ffee00c0ffee00c0ffee00", "field": "_deleted",  "value": false, "hlc": "1761800000000-1-5a1b9c2d"}
  ]
}
```

Abhaken ist danach ein einzelner Change:

```json
{"type": "entry", "id": "0a1b…/c0ffee00c0ffee00c0ffee00c0ffee00", "field": "checked", "value": true, "hlc": "1761800005000-0-5a1b9c2d"}
```

## Kompatibilität

- Neue Objekttypen und neue Felder sind ohne neue Protokollversion möglich;
  ältere Clients bewahren sie (siehe [Unbekanntes bewahren](#unbekanntes-bewahren)).
- Eigene Typen und Felder fremder Clients sollten einen Präfix tragen
  (z. B. `x.meinprojekt.foo`), damit sie nicht mit späteren Konsum-Namen
  zusammenstoßen.
- Änderungen an der Bedeutung bestehender Felder, an der Konfliktauflösung
  oder am Format erhöhen `v`.

## Sicherheit

- Jedes Mitglied des Raums kann alles ändern und löschen; es gibt keine
  Rechte unterhalb der Raummitgliedschaft.
- Private Notizen liegen unverschlüsselt in der Room Account Data.
- Konsum hat keine Geräte-Verifizierung; Raumschlüssel gehen auch an
  unverifizierte Geräte der Mitglieder.
