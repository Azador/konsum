#!/usr/bin/env bash
# Integrationstests auf dem Emulator „konsum_pixel7a“, ohne Netz.
#
# Startet den Emulator, falls er nicht läuft, schaltet ihn in den
# Flugmodus und führt integration_test/ einmal je Schriftgröße aus
# (normal, 1,15 wie auf dem Pixel 7a des Entwicklers, groß).
#
# Aufruf (aus app/): tool/integration_test.sh [weitere flutter-test-Optionen]
#
# Läuft ausschließlich auf dem Emulator: Ein Debug-Build auf einem Telefon
# mit der installierten Release-App würde diese samt Daten ersetzen.
set -euo pipefail

AVD=konsum_pixel7a
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
ADB="$ANDROID_HOME/platform-tools/adb"
EMULATOR="$ANDROID_HOME/emulator/emulator"
FLUTTER="${FLUTTER:-$(command -v flutter || echo "$HOME/git/flutter/bin/flutter")}"
cd "$(dirname "$0")/.."

# Seriennummer des laufenden Emulators mit unserem AVD.
find_serial() {
  for s in $("$ADB" devices | awk '/^emulator-/ {print $1}'); do
    if [ "$("$ADB" -s "$s" emu avd name 2>/dev/null | head -1 | tr -d '\r')" = "$AVD" ]; then
      echo "$s"
      return
    fi
  done
}

serial=$(find_serial)
if [ -z "$serial" ]; then
  echo "Starte Emulator $AVD …"
  "$EMULATOR" -avd "$AVD" -no-snapshot-save -no-audio -no-boot-anim \
    >/dev/null 2>&1 &
  for _ in $(seq 60); do
    sleep 2
    serial=$(find_serial)
    [ -n "$serial" ] && break
  done
  [ -n "$serial" ] || { echo "Emulator startet nicht." >&2; exit 1; }
fi
"$ADB" -s "$serial" wait-for-device
until [ "$("$ADB" -s "$serial" shell getprop sys.boot_completed | tr -d '\r')" = 1 ]; do
  sleep 2
done

# Ohne Netz: Die Tests prüfen nur, was offline funktionieren muss.
"$ADB" -s "$serial" shell cmd connectivity airplane-mode enable

status=0
for scale in 1.0 1.15 1.3; do
  echo "== Schriftgröße $scale =="
  "$ADB" -s "$serial" shell settings put system font_scale "$scale"
  # Nach dem Flugmodus war adb einmal kurz „offline“.
  "$ADB" -s "$serial" wait-for-device
  "$FLUTTER" test integration_test -d "$serial" "$@" || status=1
done
"$ADB" -s "$serial" shell settings put system font_scale 1.0
exit $status
