#!/bin/bash
# Installiert die Web-App per ssh auf einem anderen Rechner: eigener
# Benutzer, Caddy als systemd-Dienst, HTTPS mit lokaler CA.
#
#   deploy/web/install.sh [benutzer@]rechner
#
# Auf dem Zielrechner nötig: systemd und sudo (oder Anmeldung als root).
# Fehlt Caddy, wird es nach Rückfrage über den Paketmanager installiert.
# Erneut ausführen aktualisiert die Installation; die bisherigen Einstellungen
# sind dann vorbelegt.
set -euo pipefail

if [ $# -ne 1 ] || [[ $1 == -* ]]; then
	echo "Aufruf: $0 [benutzer@]rechner" >&2
	exit 2
fi
target=$1
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"

# Eine ssh-Verbindung für alle Schritte, damit das Passwort nur einmal kommt.
ctl="$(mktemp -d)"
trap 'ssh -o ControlPath="$ctl/ssh" -O exit "$target" 2>/dev/null; rm -rf "$ctl"' EXIT
ssh_() {
	ssh -o ControlMaster=auto -o ControlPath="$ctl/ssh" -o ControlPersist=600 "$@"
}

# Abfrage mit vorbelegtem, editierbarem Wert: ask variable frage vorgabe
ask() {
	local reply
	read -r -e -i "$3" -p "$2: " reply
	printf -v "$1" '%s' "$reply"
}

# Ja/Nein-Frage, Standard Ja.
confirm() {
	local reply
	read -r -p "$1 [J/n] " reply
	[[ -z $reply || $reply == [JjYy]* ]]
}

die() {
	echo "$*" >&2
	exit 1
}

echo "Verbinde mit $target …"
ssh_ -fN "$target"
declare -A r=()
probe="$(
	ssh_ "$target" sh -s <<'EOF'
command -v systemctl >/dev/null && [ -d /run/systemd/system ] && echo systemd=yes
echo caddy="$(command -v caddy)"
for pm in apt-get dnf zypper pacman; do
	command -v $pm >/dev/null && { echo pm=$pm; break; }
done
[ "$(id -u)" = 0 ] && echo root=yes
command -v sudo >/dev/null && echo sudo=yes
u="$(sed -n 's/^User=//p' /etc/systemd/system/konsum-web.service 2>/dev/null)"
if [ -n "$u" ]; then
	echo user="$u"
	sed -n -e 's/^KONSUM_HOST=/host=/p' -e 's/^KONSUM_HTTPS_PORT=/https=/p' \
		-e 's/^KONSUM_HTTP_PORT=/http=/p' "/var/lib/$u/konsum.env" 2>/dev/null
fi
systemctl is-active --quiet konsum-web 2>/dev/null && echo active=yes
echo busy="$(ss -Hltn 2>/dev/null | awk '{n = split($4, a, ":"); print a[n]}' |
	sort -un | tr '\n' ' ')"
EOF
)"
while IFS='=' read -r k v; do r[$k]=$v; done <<<"$probe"

[ "${r[systemd]:-}" = yes ] || die "Auf $target läuft kein systemd."
[ "${r[root]:-}" = yes ] || [ "${r[sudo]:-}" = yes ] ||
	die "Auf $target fehlt sudo; bitte als root anmelden (root@…)."
[ -n "${r[user]:-}" ] && echo "Vorhandene Installation gefunden, Werte sind vorbelegt."

# Port belegt? Die Ports der laufenden Installation zählen nicht.
port_busy() {
	[[ " ${r[busy]:-} " == *" $1 "* ]] || return 1
	! [[ ${r[active]:-} == yes && ($1 == "${r[https]:-}" || $1 == "${r[http]:-}") ]]
}
valid_port() {
	if ! [[ $1 =~ ^[1-9][0-9]{0,4}$ ]] || (($1 > 65535)); then
		echo "  Bitte eine Zahl von 1 bis 65535." >&2
	elif port_busy "$1"; then
		echo "  Port $1 ist auf $target schon belegt." >&2
	else
		return 0
	fi
	return 1
}

while
	ask user "Benutzerkonto für den Server" "${r[user]:-konsum}"
	! [[ $user =~ ^[a-z_][a-z0-9_-]{0,31}$ && $user != root ]]
do
	echo "  Kleinbuchstaben, Ziffern, _ und -; am Anfang ein Buchstabe oder _." >&2
done
while
	ask host "Rechnername in der URL (muss auf allen Geräten auflösbar sein)" \
		"${r[host]:-${target#*@}}"
	! [[ $host =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]]
do
	echo "  Nur Buchstaben, Ziffern, Punkte und Bindestriche." >&2
done
while
	ask https_port "HTTPS-Port (Web-App)" "${r[https]:-8443}"
	! valid_port "$https_port"
do :; done
while
	ask http_port "HTTP-Port (Stammzertifikat zum Herunterladen)" "${r[http]:-8080}"
	! valid_port "$http_port" || [ "$http_port" = "$https_port" ]
do
	[ "$http_port" = "$https_port" ] && echo "  Muss sich vom HTTPS-Port unterscheiden." >&2
done

install_pkg=-
if [ -z "${r[caddy]:-}" ]; then
	[ -n "${r[pm]:-}" ] ||
		die "Caddy fehlt auf $target und kein bekannter Paketmanager gefunden. Siehe https://caddyserver.com/docs/install"
	confirm "Caddy (Webserver) fehlt auf $target. Mit ${r[pm]} installieren?" ||
		die "Abgebrochen."
	install_pkg=${r[pm]}
fi

if [ ! -f "$repo/app/build/web/index.html" ] || confirm "Web-App vorher neu bauen?"; then
	"$here/build.sh"
fi
[ -f "$repo/app/build/web/pkg/vodozemac_bindings_dart_bg.wasm" ] ||
	die "Verschlüsselung (vodozemac) fehlt im Build; bitte deploy/web/build.sh ausführen."

echo "Übertrage Dateien …"
rtmp="$(ssh_ -n "$target" mktemp -d)"
[[ $rtmp =~ ^/[A-Za-z0-9._/-]+$ ]] || die "Unerwartetes Temp-Verzeichnis: $rtmp"
tar -cf - -C "$here" Caddyfile install-remote.sh -C "$repo/app/build" web |
	ssh_ "$target" tar -xf - -C "$rtmp"

sudo=()
[ "${r[root]:-}" = yes ] || sudo=(sudo)
ssh_ -t "$target" "${sudo[@]}" sh "$rtmp/install-remote.sh" \
	"$user" "$host" "$https_port" "$http_port" "$install_pkg" "$rtmp"

echo
echo "Konsum läuft:  https://$host:$https_port"
echo "Stammzertifikat (einmalig je Gerät installieren):"
echo "               http://$host:$http_port/konsum-ca.crt"
