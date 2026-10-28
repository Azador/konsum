# Konsum – Konzept

Einkaufsliste für Haushalte und Vereine. App-ID: `de.azador.konsum`

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
- Änderungen werden als eigene Ereignisse (`de.einkaufsliste.change`) in den Raum
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
- Die Sync-Schicht wird hinter einer Schnittstelle gekapselt, sodass später
  z. B. ein Nextcloud-Backend ergänzt werden kann.

## Repository-Struktur (geplant)

```
Einkaufsliste/
├── KONZEPT.md
├── LICENSE              GPL-3.0
├── README.md
├── packages/
│   └── core/            Datenmodell, Konfliktauflösung, Sync-Schnittstelle (reines Dart, gut testbar)
│   └── sync_matrix/     Matrix-Backend
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

## Entscheidungen

- Sync-Backend: Matrix (2026-10-29)
- Artikelstamm, Kategorien und Läden gehören zur Gruppe (2026-10-29)
- Web-App wird lokal ausgeliefert, Server-Konfiguration liegt im Repo (2026-10-29)
- Name „Konsum“, App-ID `de.azador.konsum` (2026-10-29)
- HTTPS im LAN über Caddy mit lokaler CA (2026-10-29)

## Offene Punkte

- keine
