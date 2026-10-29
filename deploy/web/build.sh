#!/bin/sh
# Baut die Web-App für die Auslieferung über Caddy.
# CanvasKit wird mitgeliefert (statt vom Google-CDN geladen), damit die App
# ohne Internet aus dem Cache starten kann.
set -eu
cd "$(dirname "$0")/../../app"
flutter build web --release --no-web-resources-cdn --no-wasm-dry-run
echo "Fertig: app/build/web. Starten mit: cd deploy/web && docker compose up -d"
