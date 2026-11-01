#!/bin/sh
# Holt die Ersatzschriften (Noto) für Emojis und Symbole nach
# app/web/fonts/fallback. Flutter Web lädt Zeichen, die Roboto nicht hat,
# sonst von fonts.gstatic.com; die Web-App liefert diese Schriften selbst aus
# (fontFallbackBaseUrl in flutter_bootstrap.js). Andere Schriftsysteme
# (z. B. Chinesisch, Arabisch) fehlen dann und erscheinen als Kästchen.
#
# Dateinamen und Versionen stehen im Flutter-SDK und ändern sich mit ihm,
# deshalb wird die Liste beim Bauen daraus gelesen.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
out="$here/../../app/web/fonts/fallback"
flutter_root="$(dirname "$(dirname "$(readlink -f "$(command -v flutter)")")")"
data="$flutter_root/engine/src/flutter/lib/web_ui/lib/src/engine/font_fallback_data.dart"
[ -f "$data" ] || { echo "Schriftliste fehlt: $data" >&2; exit 1; }

paths="$(python3 -I - "$data" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
wanted = re.compile(r"Noto (Color Emoji|Sans Symbols|Sans Symbols 2|Sans Math)( \d+)?")
for name, url in re.findall(r"NotoFont\(\s*'([^']+)',\s*'([^']+)'", text):
    if wanted.fullmatch(name) and re.fullmatch(r"[a-z0-9]+/v\d+/[A-Za-z0-9_.-]+\.woff2", url):
        print(url)
PY
)"
[ -n "$paths" ] || { echo "Keine Ersatzschriften in $data gefunden" >&2; exit 1; }

# Nicht mehr gebrauchte Dateien (ältere Flutter-Version) entfernen.
if [ -d "$out" ]; then
	find "$out" -name '*.woff2' | while read -r f; do
		echo "$paths" | grep -qxF "${f#"$out"/}" || rm -f "$f"
	done
fi
n=0
for p in $paths; do
	[ -s "$out/$p" ] && continue
	mkdir -p "$out/$(dirname "$p")"
	curl -fsSL -o "$out/$p.tmp" "https://fonts.gstatic.com/s/$p"
	mv "$out/$p.tmp" "$out/$p"
	n=$((n + 1))
done
[ "$n" = 0 ] || echo "$n Ersatzschriften nach app/web/fonts/fallback geladen"
