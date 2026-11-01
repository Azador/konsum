# Konsum

Gemeinsame, offline-fähige Einkaufsliste für Haushalte und Vereine.
Synchronisation über Matrix, Apps für Android und Linux, Web-App für alle anderen.

Details: [KONZEPT.md](KONZEPT.md)

Eigene Programme können geteilte Listen mitbenutzen: Das Matrix-Protokoll
steht in [PROTOKOLL.md](PROTOKOLL.md), Dart-Projekte binden
[`packages/konsum_matrix`](packages/konsum_matrix/README.md) direkt ein.

## Aufbau

| Verzeichnis | Inhalt |
|---|---|
| `packages/konsum_core` | Datenmodell und Konfliktauflösung (reines Dart) |
| `packages/konsum_matrix` | Matrix als Sync-Backend |
| `app` | Flutter-App für Android, Linux, iOS und Web |
| `deploy/web` | Caddy für die Web-App im lokalen Netz, siehe [README](deploy/web/README.md) |
| `docs` | Projektseite und Datenschutzerklärung (GitHub Pages, https://konsum.azadoro.de) |

## Entwicklung

```bash
cd packages/konsum_core && dart test     # Core-Tests
cd packages/konsum_matrix && dart test   # Matrix-Protokoll-Tests
cd app && flutter test                   # App-Tests
cd app && flutter run -d linux           # Linux-App starten
cd app && flutter run -d chrome          # Web-App starten
```

Lokale Daten der Linux-App: `~/.local/share/de.azadoro.konsum/data/`

Die Linux-App wird gegen SQLCipher aus dem System gebaut
(Debian/Ubuntu: `sudo apt install libsqlcipher-dev`, Fedora: `sqlcipher-devel`,
Arch: `sqlcipher`) und braucht einen Schlüsselbund (KWallet,
GNOME-Schlüsselbund, KeePassXC …) für den Datenbankschlüssel.

Installationspakete für Linux (`.deb`, `.tar.gz`):

```bash
(cd app && flutter build linux --release) && deploy/linux/package.sh
```

## Versionen und Branches

Änderungen an `main` laufen nur über Pull Requests.

Die Version in `app/pubspec.yaml` (`version: X.Y.Z+N`) ändert sich nur für
Releases, nicht mit jedem PR. Auf `main` steht die Version des nächsten
geplanten Releases: Nach einem Release erhöht der erste PR auf die nächste
Patch-Version, vor dem Release wird sie bei Bedarf angepasst – Minor bei neuen
Funktionen, Major bei inkompatiblen Änderungen (vor 1.0: Minor). Die
Build-Nummer `+N` ist der Android-Versionscode; sie muss bei jedem Upload zu
Google Play neu sein, auch für Testversionen. Die Pakete
`packages/konsum_core` und `packages/konsum_matrix` bekommen eine neue
Version, wenn sie sich ändern.

Ein Release ist ein Tag `vX.Y.Z` auf `main` mit GitHub-Release; F-Droid baut
anhand der Tags, Google Play bekommt das App-Bundle desselben Stands.

## Automatischer Build

`.github/workflows/build.yml` läuft bei jedem PR und Push auf `main`: Tests
und Analyse, danach Android (APK, mit Signier-Secrets auch AAB), Linux
(`.deb`, `.tar.gz`) und Web (`.tar.gz`). Die Pakete hängen als Artefakte am
Lauf. Der Job „Ergebnis“ ist nur grün, wenn alles geklappt hat.

## Veröffentlichung

| Verzeichnis | Inhalt |
|---|---|
| `fastlane/metadata/android` | Store-Texte, Icon, Änderungshinweise (F-Droid liest sie direkt, für Google Play zum Kopieren) |
| `fdroid/de.azadoro.konsum.yml` | Bauanleitung für F-Droid (Vorlage für fdroiddata) |

Signaturschlüssel (nicht im Repo):

- `app/android/key.properties` → `konsum-release.jks`: signiert APKs (GitHub-Releases). Derselbe Schlüssel ist bei Google Play als App-Signaturschlüssel hinterlegt, Updates gehen also zwischen beiden Quellen.
- `app/android/upload.properties` → `konsum-upload.jks`: Upload-Schlüssel für Google Play.
  App-Bundle bauen: `KONSUM_KEY_PROPERTIES=upload.properties flutter build appbundle`

## Lizenz

GPL-3.0, siehe [LICENSE](LICENSE).
