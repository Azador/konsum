# Konsum – Konzept

Einkaufsliste für Haushalte und Vereine. App-ID: `de.azadoro.konsum`

Stand: 2026-10-29 · Status: **Entwurf** (offene Punkte siehe unten)

## Ziel

Eine gemeinsam genutzte, offline-fähige Einkaufsliste für Haushalte und Vereine,
mit nativen Apps für Android und Linux und einer Web-App für alle anderen
Plattformen (iOS, Windows, …). Synchronisation ohne eigenen, ins Netz gehängten
Server.

## Begriffe

| Begriff        | Bedeutung |
|----------------|-----------|
| **Gruppe**     | Personenkreis, der Daten teilt (z. B. „Familie“, „Verein“). Ein Benutzer kann in mehreren Gruppen sein, die auf unterschiedlichen Servern liegen können. |
| **Artikel**    | Eintrag im Artikelstamm einer Gruppe (z. B. „Spaghetti“). Bleibt erhalten, wenn er von einer Liste entfernt wird. |
| **Barcode**    | Einem Artikel zugeordneter EAN/GTIN. Ein Artikel kann beliebig viele Barcodes haben (Spaghetti von Marke A, B, C). |
| **Liste**      | Eine Einkaufsliste innerhalb einer Gruppe. Eine Gruppe kann mehrere Listen haben. |
| **Listeneintrag** | Artikel auf einer Liste, mit Menge, Einheit, Notizen und Status (offen/abgehakt). |
| **Kategorie**  | Warengruppe eines Artikels (Obst & Gemüse, Kühlregal, …). |
| **Laden**      | Geschäft (Famila, Kaufland, …) mit eigener Reihenfolge der Kategorien. |

## Funktionen

### Version 1
- Mehrere Gruppen, je Gruppe mehrere Listen
- Artikel anlegen, auf Liste setzen, abhaken, abgehakte Einträge entfernen
  („Liste aufräumen“) – der Artikel bleibt im Artikelstamm
- Artikel endgültig aus dem Artikelstamm löschen
- Schnelles Hinzufügen bekannter Artikel (Suche/Vorschläge, sortiert nach Häufigkeit)
- Menge + Einheit (Stück, g, kg, ml, l, Packung, Dose, Flasche, Bund, …)
- Notizen je Listeneintrag: **gemeinsam** (für alle in der Gruppe) und **privat**
  (nur für den aktuellen Benutzer)
- Abgehakte Einträge ein-/ausblenden
- Preise je Eintrag; beim Aufräumen wandern sie mit Menge und Laden in die
  Preishistorie. Schätzung offener Einträge aus dem letzten Preis, Summe der
  Liste. Historie löschbar (einzeln, je Artikel, je Laden, komplett)
- Kategorien; Läden mit eigener Kategorie-Reihenfolge; Liste nach gewähltem Laden sortiert
- Offline-first: alles funktioniert ohne Netz, Abgleich bei Verbindung

### Version 2
- Barcode-Scanner (Kamera) zum Hinzufügen und Abhaken; unbekannter Barcode →
  vorhandenem Artikel zuordnen oder neuen Artikel anlegen
- Produktdaten und Nährwerte über [Open Food Facts](https://world.openfoodfacts.org)
  (Name, Marke, Bild, Nährwerte); Abfrage nur bei Bedarf, Ergebnis lokal gespeichert
- Unter Linux: USB-Handscanner (verhält sich wie eine Tastatur) bzw. manuelle Eingabe

### Später / Ideen
- Kaufhistorie, Statistik, wiederkehrende Artikel
- Weitere Sync-Backends (siehe unten)

## Plattformen und Technik

**Flutter (Dart)** – eine Codebasis für:

| Plattform | Form | Hinweis |
|-----------|------|---------|
| Android   | native App | Hauptplattform Handy |
| Linux     | native App | Desktop |
| Web       | Web-App (Flutter Web, statische Dateien) | für iOS, Windows, macOS, … |
| iOS       | native App möglich | vorbereitet, aber ungetestet; vorerst Web-App |

Lokale Datenhaltung: SQLite (über `drift`), im Web über IndexedDB/WASM.

## Synchronisation

### Anforderungen
- Kein eigener öffentlich erreichbarer Dienst
- Mehrere Benutzer schreiben gleichzeitig, auch offline
- Mehrere Gruppen auf unterschiedlichen Servern
- Private Notizen dürfen nur für den jeweiligen Benutzer sichtbar sein
- Muss auch aus der Web-App heraus funktionieren (CORS)

### Bewertung der vorhandenen Dienste

| Kriterium | Matrix | Nextcloud | Joplin |
|-----------|--------|-----------|--------|
| Mehrbenutzer / Gruppen | ✅ Räume mit Mitgliederverwaltung | ⚠️ Freigaben von Ordnern | ⚠️ Notizbuch-Freigabe nur mit Joplin Server |
| Gleichzeitiges Schreiben | ✅ Ereignisstrom, keine Dateikonflikte | ❌ Dateikonflikte, selbst zu lösen | ❌ wie Nextcloud |
| Echtzeit-Abgleich | ✅ Sync-Long-Polling | ❌ Polling | ❌ Polling |
| Server-übergreifend | ✅ Föderation | ⚠️ Federated Sharing, umständlich | ❌ |
| Ende-zu-Ende-Verschlüsselung | ✅ | ❌ (serverseitig) | ⚠️ |
| Private Daten je Benutzer | ✅ Room Account Data | ✅ eigener Ordner | ⚠️ |
| Web-App (CORS) | ✅ standardmäßig erlaubt | ❌ WebDAV ohne CORS | ❌ |
| Dart-Bibliothek | ✅ `matrix` (FluffyChat) | ⚠️ WebDAV generisch | ❌ |

### Vorschlag: Matrix als erstes Sync-Backend

- **Gruppe = Matrix-Raum** (verschlüsselt). Einladen/Entfernen von Mitgliedern
  über die normale Matrix-Raumverwaltung, auch aus Element o. ä. heraus.
- Änderungen werden als eigene Ereignisse (`de.azadoro.konsum.changes`) in den Raum
  geschrieben: *Objekt-ID, Feld, neuer Wert, Zeitstempel (Hybrid Logical Clock), Gerät*.
- Jeder Client wendet die Ereignisse auf seine lokale Datenbank an.
  Konflikte: **die letzte Änderung gewinnt, pro Feld** – gleichzeitiges Ändern von
  Menge und Notiz desselben Eintrags geht also nicht verloren.
- Regelmäßig wird ein **Schnappschuss** abgelegt, damit neue Geräte nicht die
  komplette Historie abspielen müssen.
- **Private Notizen** liegen in den Room Account Data des Benutzers: nur für ihn
  sichtbar, auf allen seinen Geräten synchron. Achtung: Account Data ist nicht
  Ende-zu-Ende-verschlüsselt, der Server-Admin könnte sie lesen. Alternativ:
  verschlüsselt im eigenen Konto ablegen.
- Das genaue Format steht in [PROTOKOLL.md](PROTOKOLL.md); andere Programme
  können damit dieselben Listen benutzen.
- Die Sync-Schicht wird hinter einer Schnittstelle gekapselt, sodass später
  z. B. ein Nextcloud-Backend ergänzt werden kann.

## Repository-Struktur (geplant)

```
Einkaufsliste/
├── KONZEPT.md
├── LICENSE              GPL-3.0
├── README.md
├── packages/
│   ├── konsum_core/     Datenmodell, Konfliktauflösung, Sync-Schnittstelle (reines Dart, gut testbar)
│   └── konsum_matrix/   Matrix-Backend
├── app/                 Flutter-App (Android, Linux, iOS, Web)
└── deploy/web/          Caddy-Konfiguration + Docker Compose für die Web-App
```

## Lizenz

GPL-3.0. Produktdaten von Open Food Facts stehen unter ODbL – bei Anzeige
Quelle nennen.

## Auslieferung der Web-App

- Die Web-App besteht nur aus statischen Dateien. Sie wird von einem kleinen
  Webserver im lokalen Netz ausgeliefert (eigener Port, kein Zugriff von außen).
  Mitgeliefert wird eine fertige Konfiguration für **Caddy** (Docker Compose).
- Der Webserver wird nur zum **Laden und Aktualisieren** der App gebraucht. Die
  Synchronisation läuft direkt vom Gerät zum Matrix-Server. Als PWA installiert
  funktioniert die App deshalb auch unterwegs.
- **HTTPS ist nötig**, auch im LAN: Service Worker (Offline-Betrieb) und die
  Kryptografie für die Matrix-Verschlüsselung (WebCrypto) gibt es im Browser nur
  in einem sicheren Kontext. Lösung:
  Gewählt: Caddy mit eigener lokaler Zertifizierungsstelle (`tls internal`) für
  den Servernamen `loboci`. Das Stammzertifikat wird einmalig auf jedem Gerät
  installiert.
- **iOS:** Gerät im heimischen WLAN, Seite in Safari öffnen, „Teilen →
  Zum Home-Bildschirm“. Danach läuft die App offline aus dem Cache und
  synchronisiert unterwegs mit dem Matrix-Server. Updates kommen beim nächsten
  Start im Heim-WLAN. Mit lokaler CA: Stammzertifikat als Profil installieren und
  unter „Einstellungen → Allgemein → Info → Zertifikatsvertrauenseinstellungen“
  aktivieren.

## Datensparsamkeit

Stand: 2026-11-03 · Status: **Konzept**, noch nicht umgesetzt

Konsum soll nicht alles für immer speichern: Der Speicher auf dem Handy ist
endlich, und vor allem soll eine Einkaufsliste von heute nicht in Jahren
noch verraten, was jemand einmal kaufen wollte. Grundsatz: Erhalten bleibt,
was die App anzeigt und der Benutzer selbst verwaltet. Was nicht mehr
angezeigt wird oder als ungültig gilt, verschwindet nach festgelegten Regeln.
Speicher, die eine Funktion braucht (z. B. die Käufe für Vorschläge), bleiben
in der Software, werden aber durch definierte Löschaktionen bereinigt.

### Datenklassen

| Klasse | Daten | Aufbewahrung |
|---|---|---|
| **A – aktueller Stand** | Gruppen, Einkaufslisten, Artikel (mit Barcodes, Packungsgröße), Kategorien, Läden (mit Reihenfolge), Einträge, die gerade auf einer Liste stehen (auch abgehakte), private Notizen dazu | unbegrenzt, aber nur der **aktuelle** Wert; frühere Werte werden nicht gebraucht |
| **B – sichtbar, vom Benutzer verwaltet** | Preishistorie | bis der Benutzer löscht; dann wirklich weg (siehe D) |
| **C – unsichtbar, für Funktionen** | Käufe (entstehen beim Aufräumen; sortieren die Vorschläge, später Basis für wiederkehrende Artikel) | Verfall nach der Frist der Gruppe (siehe unten); möglichst knapp (Datum statt Millisekunde); sollen künftig sichtbar und löschbar werden („zuletzt gekauft“, „Kaufhistorie löschen“) |
| **D – gelöscht / erledigt** | gelöschte Preise, aufgeräumte oder weggewischte Einträge, gelöschte Artikel, Listen, Läden, Kategorien, Barcodes | Inhalt **sofort** weg; übrig bleibt höchstens ein leerer Grabstein, der seinerseits verfällt |

### Wo Daten liegen

| Ort | Inhalt | Heute | Ziel |
|---|---|---|---|
| Konsum-Datenstand (lokal, `data/*.json`) | je Feld der letzte Wert mit Zeitstempel | Gelöschtes behält seinen ganzen Inhalt (`_deleted: true`), auch in jedem Schnappschuss | siehe „Lokaler Datenstand“ |
| Datenbank der Matrix-Bibliothek (lokal) | empfangene Ereignisse **entschlüsselt**, dazu Schlüssel, Raumzustand, Sync-Position | Ereignisse werden nie entfernt | siehe „Matrix-Datenbank“ |
| Matrix-Raum (auf **jedem** beteiligten Server, verschlüsselt) | jede Änderung, jeder Schnappschuss | nichts wird entfernt | Aufbewahrungsfrist des Raums |
| Geräte und Clients anderer Mitglieder | wie der Raum | – | außerhalb unseres Einflusses; das Protokoll ist offen, wer mitschreiben will, kann das |
| Android-Sicherung (Google) | gesamte App-Daten | aktiv | **bleibt aktiv** (2026-11-03): Benutzer erwarten, dass eine Sicherung die App wiederherstellt. Eine Matrix-Gruppe holt sich danach den aktuellen Stand aus dem Raum, eine lokale Gruppe kommt mit dem Stand der Sicherung zurück |

### Aufbewahrungsfrist der Gruppe

Pro Gruppe einstellbar: **1–24 Monate** oder **ohne automatisches Löschen**,
Vorgabe **6 Monate** (reicht für Vorschläge und wiederkehrende Artikel).
Dieselbe Frist gilt für

- den Verfall der Käufe (Klasse C) und der Grabsteine (Klasse D) im lokalen
  Datenstand,
- die Ereignisse in der Datenbank der Matrix-Bibliothek (höchstens so lange,
  siehe unten meist viel kürzer),
- bei Matrix-Gruppen die Aufbewahrungsfrist des Raums (`m.room.retention`).

Bei lokalen Gruppen gibt es die Einstellung auch, nur ohne Server-Teil.
Verschwindet etwas unerwartet, lässt sich das mit der Frist erklären und dort
abstellen.

**Verfall statt Löschbefehl:** Jedes Gerät entfernt Käufe und Grabsteine,
die älter als die Frist sind, selbstständig – ohne Grabstein, ohne etwas zu
verschicken. Weil alle Geräte nach demselben Datum entscheiden, kommen sie
von selbst zum selben Stand. Verfallenes gehört in keinen Schnappschuss.

### Matrix-Raum: Aufbewahrungsfrist (Recherche 2026-11-03)

- **Kein Heimatserver:** Jeder Server, auf dem ein Mitglied ein Konto hat,
  hält eine vollständige Kopie des Raums. Die Frist ist eine gemeinsame
  Raumeinstellung, aber **jeder Server setzt sie für seine Kopie selbst um** –
  oder eben nicht. Der Hinweis in der App muss das sagen („gilt nur auf
  Servern, die das unterstützen“).
- **Standard:** MSC1763 („configurable retention periods“), noch nicht Teil
  der Spezifikation. Zustandsereignis `m.room.retention` mit `max_lifetime`
  in Millisekunden; setzen dürfen es Admins/Moderatoren des Raums.
- **Synapse** (u. a. matrix.org): umgesetzt, aber **standardmäßig aus**
  (`retention.enabled` in der Serverkonfiguration). Der Betreiber kann die
  erlaubten Werte begrenzen (`allowed_lifetime_min/max`). Abgelaufene
  Ereignisse werden sofort nicht mehr ausgeliefert und beim nächsten
  Aufräumlauf gelöscht; das letzte Ereignis eines Raums und Zustandsereignisse
  werden nie gelöscht. Ohne Raumeinstellung und ohne Server-Vorgabe wird nie
  gelöscht.
- **Erkennen, ob ein Server es kann:** Seit Synapse 1.156 (Juli 2026) gibt es
  `GET /_matrix/client/unstable/org.matrix.msc1763/retention/configuration`,
  nur wenn Retention **und** `experimental_features.msc1763_enabled` an sind.
  matrix.org antwortet darauf mit `M_UNRECOGNIZED` (geprüft 2026-11-03), dort
  ist es also nicht nutzbar bzw. nicht erkennbar. Fehlt der Endpunkt, zeigt
  die App „vom Server nicht unterstützt“; die Raumeinstellung kann trotzdem
  gesetzt werden, damit fähige Server sie beachten.
- **Andere Server** (Conduit-Familie, Dendrite): in der Dokumentation keine
  Unterstützung gefunden; nicht abschließend geprüft.
- **Für Konsum unkritisch:** Konsum liest die Historie des Raums nie nach,
  neue Geräte bitten um einen Schnappschuss. Löscht ein Server alte
  Ereignisse, geht nichts kaputt.
- Andere Werkzeuge, falls die Frist nicht greift: eigene Ereignisse
  zurückziehen (Redaction; der Inhalt verschwindet auf dem Server, Clients
  verwerfen ihn normalerweise), oder **Umzug** in einen frischen Raum mit dem
  aktuellen Stand und Verlassen des alten (gründlich, aber neue Einladungen
  und Schlüssel). Noch nicht entschieden.

### Matrix-Datenbank (lokal)

Konsum verarbeitet Ereignisse einmal beim Eintreffen (`sdk_transport.dart`),
übernimmt sie in seinen Datenstand und **liest sie nie wieder** aus der
Datenbank. Die Bibliothek speichert sie trotzdem, weil sie für Chat-Apps
gebaut ist. Gebraucht werden aus der Datenbank nur Anmeldung, Schlüssel,
Mitglieder, Raumzustand und Sync-Position.

- Ziel: Konsum-Ereignisse löschen, **sobald sie übernommen sind**; Ereignisse,
  die sich noch nicht entschlüsseln lassen, bleiben bis zur Entschlüsselung
  oder bis die 2-Minuten-Regel einen Schnappschuss auslöst. Obergrenze in
  jedem Fall die Frist der Gruppe.
- Möglichkeiten der Bibliothek (matrix 14.2): `removeEvent(eventId, roomId)`
  löscht ein einzelnes Ereignis samt Verweis in der Timeline;
  `deleteTimelineForRoom` die Timeline-Verweise eines Raums; `clearCache`
  verwirft Räume, Ereignisse und Sync-Position (erzwingt einen vollständigen
  Sync, behält Anmeldung und Schlüssel). Zu beachten: Der Raum merkt sich
  zusätzlich sein letztes Ereignis (`lastEvent`) mit Inhalt.
- Die Datenbank gehört nur zu Matrix (Anmeldung, Schlüssel, Räume aller
  Matrix-Gruppen in **einer** Datei `konsum_matrix.sqlite`); Konsums eigene
  Daten liegen getrennt je Gruppe in `data/group-<id>.json`.
- **Nur mit Anmeldung:** Heute wird die Datei bei jedem Start angelegt, auch
  ohne Matrix. Künftig erst bei der Anmeldung; wer Matrix nicht nutzt, hat
  keine SQLite-Datei.
- **Abmelden:** Die Bibliothek leert heute nur die Tabellen. Künftig wird die
  Datei danach ganz gelöscht (gleichwertig zu Leeren + `VACUUM`).
- **Reste im freien Platz:** Gelöschte Zeilen bleiben in SQLite stehen, bis
  ihr Platz wiederverwendet wird, und sind bis dahin mit forensischen
  Werkzeugen lesbar. Statt `secure_delete` (unverhältnismäßig) schreibt die
  App die Datei gelegentlich mit `VACUUM` neu, z. B. beim Start, wenn seit
  dem letzten Mal genug gelöscht wurde. Kein Knopf, keine Einstellung.
- Raumschlüssel (Megolm) bleiben auf dem Gerät und im Schlüssel-Backup auf
  dem Server. Damit ließe sich alte, auf dem Server noch vorhandene Historie
  entschlüsseln – ein weiterer Grund für die Frist im Raum.

### Lokaler Datenstand

- **Lokale Gruppen:** Gelöschtes wird sofort **vollständig** entfernt; ein
  Grabstein ist unnötig, weil kein anderes Gerät es wiederbeleben kann. Käufe
  verfallen nach der Frist.
- **Matrix-Gruppen:** Beim Löschen bleibt nur der leere Grabstein (Kennung,
  `_deleted`, Zeitstempel) – im Datenstand und in Schnappschüssen. Grabsteine
  und Käufe verfallen nach der Frist.
- **Bestand:** Beim ersten Start einer neuen Version werden vorhandene
  Grabsteine geleert und Abgelaufenes entfernt.
- **Abmelden von Matrix** (2026-11-03): Die App fragt, ob die
  Matrix-Gruppen auf dem Gerät bleiben sollen.
  - *Entfernen:* Datenstand der Gruppen wird gelöscht.
  - *Behalten:* Die Gruppen werden zu **lokalen Gruppen** – ohne Verbindung
    zum Raum, mit den Regeln für lokale Gruppen (Grabsteine entfallen). Beim
    erneuten Anmelden kommen die Gruppen aus dem Konto als **neue**
    Matrix-Gruppen dazu; die lokalen Kopien werden nicht wieder verbunden,
    weil sich beide Seiten inzwischen unabhängig geändert haben können.
    Damit zwei gleichnamige Gruppen unterscheidbar sind, bekommt die lokale
    Kopie einen Zusatz im Namen, z. B. „Zuhause (lokal)“. Ist der Name
    schon vergeben (auch von einer früheren Kopie), wird hochgezählt:
    „Zuhause (lokal 2)“, „Zuhause (lokal 3)“, …
  - Der Dialog sagt das ausdrücklich, etwa: „Die Gruppen bleiben als lokale
    Kopie auf diesem Gerät, werden aber nicht mehr abgeglichen. Änderungen
    daran erreichen die anderen Mitglieder nicht. Wenn du dich wieder
    anmeldest, kommen die Gruppen neu dazu; die lokale Kopie bleibt getrennt
    davon bestehen.“
  - Hat eine Gruppe noch nicht gesendete Änderungen (offline), weist der
    Dialog darauf hin: Sie erreichen die Gruppe nach dem Abmelden nicht mehr.
- **Warteschlange** (noch nicht gesendete Änderungen): leert sich beim
  Senden, nichts zu tun.
- **Knifflig – Gerät länger offline als die Frist:** Es kennt womöglich
  Objekte, deren Grabsteine anderswo schon verfallen sind, und würde sie per
  Schnappschuss wiederbeleben. Vorschlag: Ein solches Gerät verschickt nichts
  aus seinem alten Stand, sondern holt einen frischen Schnappschuss und
  verwirft eigene Objekte, die dort fehlen und älter als die Frist sind.
  Das braucht eine Ergänzung in PROTOKOLL.md.

## Entscheidungen

- Sync-Backend: Matrix (2026-10-29)
- Artikelstamm, Kategorien und Läden gehören zur Gruppe (2026-10-29)
- Web-App wird lokal ausgeliefert, Server-Konfiguration liegt im Repo (2026-10-29)
- Name „Konsum“, App-ID `de.azador.konsum` (2026-10-29); geändert in
  `de.azadoro.konsum`, weil `azador.de` jemand anderem gehört (2026-11-01)
- HTTPS im LAN über Caddy mit lokaler CA (2026-10-29)
- Ein Matrix-Konto pro App-Installation; Gruppen auf anderen Servern über
  Föderation (2026-10-29)
- Ende-zu-Ende-Verschlüsselung in den nativen Apps (Linux, Android) über
  `flutter_vodozemac`; der Build braucht `rustup`. Neue Gruppen werden
  verschlüsselt angelegt, wenn das Gerät verschlüsseln kann. Schlüssel gehen an
  alle Geräte der Mitglieder, auch unverifizierte (`ShareKeysWith.all`), weil
  Konsum noch keine Geräte-Verifizierung hat. Private Notizen liegen in der
  Room Account Data, die Matrix nicht verschlüsselt (2026-10-29)
- Ereignisse, deren Schlüssel nach 2 Minuten noch fehlt, gelten als Lücke und
  werden per Schnappschuss nachgeholt (2026-10-29)
- Das Matrix-SDK (`matrix`, Famedly) steht unter AGPL-3.0. Unser Code bleibt
  GPL-3.0; die ausgelieferte App als Ganzes unterliegt damit zusätzlich den
  AGPL-Bedingungen (GPL-3 §13). Für ein offenes Projekt unproblematisch
  (2026-10-29)

- Anmeldung und neue Konten über die Webseite des Servers (OIDC, MSC2964/
  MSC2966), wo der Server das anbietet (z. B. matrix.org); sonst Passwort.
  Rückweg: Android `de.azadoro.konsum:/oauth`, Linux `http://127.0.0.1:<Port>`.
  Die Client-Adresse muss dazu `https://konsum.azadoro.de` sein (umgekehrtes
  App-Schema); sie wird auf der Anmeldeseite angezeigt (2026-10-29)

- Verschlüsselung auch in der Web-App: vodozemac als WebAssembly
  (`deploy/web/build-vodozemac.sh`, Rust nightly); Caddy liefert dafür mit
  Cross-Origin-Isolation (COOP/COEP) aus (2026-10-29)

- Protokoll für andere Projekte offengelegt: Spezifikation in PROTOKOLL.md,
  Dart-Pakete per Git-Abhängigkeit einbindbar; ein Test hält das Format
  fest (2026-10-30)

- Barcode-Scanner ohne Google-Dienste (für F-Droid): Android/iOS mit
  zxing-cpp über `flutter_zxing`, im Browser `BarcodeDetector` oder
  zxing-wasm, selbst ausgeliefert statt vom CDN. Galerie, Mikrofon- und
  Speicherberechtigung des Kamera-Plugins sind abgeschaltet (2026-11-01)

- Keine Schriften von Google Fonts (Datenschutz): Roboto liegt in der App
  (`app/assets/fonts`, SIL OFL), Ersatzschriften für Emojis und Symbole
  liefert die Web-App selbst aus (`deploy/web/fetch-fonts.sh`). Andere
  Schriftsysteme zeigt die Web-App als Kästchen (2026-11-01)

- Namensraum der Matrix-Ereignisse `de.azadoro.konsum`. Räume mit dem alten
  Namensraum `de.azador.konsum` werden nicht mehr erkannt; die Daten wurden
  von Hand in neue Gruppen übertragen (2026-11-01)

- Keine fertigen Binärdateien im Build (F-Droid): SQLCipher für Linux kommt
  aus dem System statt vorkompiliert von GitHub. Die Linux-App ist dagegen
  gelinkt, die Dart-Seite sucht die Funktionen im Prozess; so hängt das .deb
  nur von `libsqlcipher1` ab. Die Android-App enthält kein SQLite-FFI mehr. Datenbankschlüssel unter
  Linux in KWallet, sonst im Secret Service (2026-11-01)

- Android als eine APK für alle Prozessoren (Versionscode wie bei Google
  Play), damit Änderungshinweise und GitHub-Release für beide Stores gleich
  sind. „Konto löschen“ öffnet die Kontoverwaltung des Matrix-Servers
  (Pflicht bei Google Play, weil die App Konten anlegen kann) (2026-11-01)

## Offene Punkte

- Datensparsamkeit umsetzen (siehe Abschnitt oben), Reihenfolge noch offen
- Web-App: Anmeldung im Browser (OIDC) braucht noch den Rückweg auf die
  eigene Seite; bis dahin nur Passwort
- Geräte-Verifizierung, Schlüssel-Backup
- Unter `https://konsum.azadoro.de` eine kleine Projektseite (wird bei der
  Anmeldung als Adresse der App angezeigt)
- Live-Test der Web-App mit Verschlüsselung (Caddy auf loboci)
- Web-App: localStorage (ca. 5 MB) ggf. durch IndexedDB ersetzen
