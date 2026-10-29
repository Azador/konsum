# Konsum

Gemeinsame, offline-fähige Einkaufsliste für Haushalte und Vereine.
Synchronisation über Matrix, Apps für Android und Linux, Web-App für alle anderen.

Details: [KONZEPT.md](KONZEPT.md)

## Aufbau

| Verzeichnis | Inhalt |
|---|---|
| `packages/konsum_core` | Datenmodell und Konfliktauflösung (reines Dart) |

## Entwicklung

```bash
cd packages/konsum_core
dart pub get
dart test
```

## Lizenz

GPL-3.0, siehe [LICENSE](LICENSE).
