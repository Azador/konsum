# Konsum

Gemeinsame, offline-fähige Einkaufsliste für Haushalte und Vereine.
Synchronisation über Matrix, Apps für Android und Linux, Web-App für alle anderen.

Details: [KONZEPT.md](KONZEPT.md)

## Aufbau

| Verzeichnis | Inhalt |
|---|---|
| `packages/konsum_core` | Datenmodell und Konfliktauflösung (reines Dart) |
| `app` | Flutter-App für Android, Linux, iOS und Web |

## Entwicklung

```bash
cd packages/konsum_core && dart test     # Core-Tests
cd app && flutter test                   # App-Tests
cd app && flutter run -d linux           # Linux-App starten
cd app && flutter run -d chrome          # Web-App starten
```

Lokale Daten der Linux-App: `~/.local/share/de.azador.konsum/data/`

## Lizenz

GPL-3.0, siehe [LICENSE](LICENSE).
