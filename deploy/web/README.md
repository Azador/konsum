# Web-App im lokalen Netz

Caddy liefert die gebaute Web-App per HTTPS aus, mit einer eigenen lokalen
Zertifizierungsstelle (CA). Es werden nur statische Dateien ausgeliefert; die
Synchronisation läuft direkt vom Gerät zum Matrix-Server.

## Bauen und starten

```bash
deploy/web/build.sh                      # baut app/build/web
cd deploy/web && docker compose up -d    # startet Caddy
```

`build.sh` baut zuerst die Matrix-Verschlüsselung (vodozemac) als
WebAssembly nach `app/web/pkg` (`build-vodozemac.sh`, nur wenn sich die
Version geändert hat). Einmalig nötig, alles ohne root:

```bash
rustup toolchain install nightly --component rust-src
rustup target add wasm32-unknown-unknown --toolchain nightly
cargo install flutter_rust_bridge_codegen --version 2.13.0 --locked
cargo install wasm-pack --locked
```

Die Version von `flutter_rust_bridge_codegen` muss zu vodozemac passen; das
Skript prüft das und nennt sonst die richtige.

Standard: Host `loboci`, HTTPS-Port 8443, HTTP-Port 8080. Anpassen per
Umgebungsvariablen oder `.env`-Datei neben `compose.yaml`:

```
KONSUM_HOST=loboci
KONSUM_HTTPS_PORT=8443
KONSUM_HTTP_PORT=8080
```

Nach einem Update der App reicht `build.sh`; Caddy liefert die neuen Dateien
sofort aus (das Verzeichnis ist eingebunden, kein Neustart nötig).

## Stammzertifikat auf den Geräten installieren

Einmalig pro Gerät. Das Zertifikat liegt unter
`http://loboci:8080/konsum-ca.crt` (bewusst über HTTP, weil das Gerät dem
HTTPS-Zertifikat vorher noch nicht vertraut).

Das Zertifikat bleibt gültig, solange das Docker-Volume `caddy_data` erhalten
bleibt. **Volume nicht löschen**, sonst entsteht eine neue CA und alle Geräte
brauchen das neue Zertifikat.

### iPhone / iPad
1. In Safari `http://loboci:8080/konsum-ca.crt` öffnen, „Zulassen“.
2. Einstellungen → „Profil geladen“ → Installieren.
3. Einstellungen → Allgemein → Info → Zertifikatsvertrauenseinstellungen →
   „Caddy Local Authority“ aktivieren.
4. `https://loboci:8443` in Safari öffnen → Teilen → „Zum Home-Bildschirm“.

### Android (für die Web-App; die native App braucht das nicht)
Einstellungen → Sicherheit → Verschlüsselung & Anmeldedaten → Zertifikat
installieren → CA-Zertifikat → heruntergeladene Datei wählen. Die genaue
Menüführung hängt vom Hersteller ab.

### Linux / Windows / macOS
Zertifikat herunterladen und in den Browser bzw. das System importieren
(Firefox: Einstellungen → Datenschutz & Sicherheit → Zertifikate → Importieren).

## Offline-Betrieb

Ein eigener Service Worker (`app/web/konsum_sw.js`) hält die App vor: Im
Heim-WLAN wird immer die aktuelle Version geladen, unterwegs startet die App
aus dem Cache. Die Daten liegen ohnehin lokal und gleichen sich über Matrix
ab, sobald Internet da ist.

## Hinweise

- Caddy schickt `Cross-Origin-Opener-Policy`/`Cross-Origin-Embedder-Policy`.
  Die Verschlüsselung braucht diese Isolation (gemeinsamer Speicher für
  WebAssembly). Folge: Fremde Dateien lädt der Browser nur, wenn der
  fremde Server sie freigibt; unpkg, Google Fonts, Open Food Facts und
  Matrix-Server tun das.
- In der Web-App gibt es nur die Anmeldung mit Passwort. Ein neues Konto
  legst du in der Android- oder Linux-App an.

- `loboci` muss auf allen Geräten auflösbar sein (DNS im Router o. ä.).
  Mobilgeräte lösen reine Hostnamen ohne Domain teils nicht auf; dann
  `KONSUM_HOST` auf einen auflösbaren Namen setzen (z. B. `loboci.fritz.box`).
- Der Kamera-Scanner im Browser lädt die Bibliothek ZXing von `unpkg.com`.
- Schriften (Roboto) lädt Flutter Web von Google Fonts; ohne Internet wird
  eine Systemschrift verwendet.
