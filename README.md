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

## Entwicklung

```bash
cd packages/konsum_core && dart test     # Core-Tests
cd packages/konsum_matrix && dart test   # Matrix-Protokoll-Tests
cd app && flutter test                   # App-Tests
cd app && flutter run -d linux           # Linux-App starten
cd app && flutter run -d chrome          # Web-App starten
```

Lokale Daten der Linux-App: `~/.local/share/de.azadoro.konsum/data/`

## Lizenz

GPL-3.0, siehe [LICENSE](LICENSE).
