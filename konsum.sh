#!/bin/sh
# Startet die Linux-App. Baut sie vorher neu, wenn sich der Quelltext seit
# dem letzten Bau geändert hat (oder mit --build immer).
#
#   ./konsum.sh [--build]
set -eu
repo="$(cd "$(dirname "$0")" && pwd)"
app="$repo/app"
bin="$app/build/linux/x64/release/bundle/konsum"

if [ "${1:-}" = --build ] || [ ! -x "$bin" ] ||
	[ -n "$(find "$app/lib" "$app/linux" "$app/pubspec.yaml" "$repo/packages" \
		-newer "$bin" -type f -print -quit)" ]; then
	PATH="$HOME/git/flutter/bin:$PATH"
	echo "Baue Konsum für Linux …"
	(cd "$app" && flutter build linux --release)
fi
exec "$bin"
