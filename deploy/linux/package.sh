#!/bin/sh
# Packt die gebaute Linux-App als .tar.gz und .deb.
#
#   (cd app && flutter build linux --release)
#   deploy/linux/package.sh [ausgabeverzeichnis]
#
# Standard-Ausgabe: app/build/packages. Für das .deb werden dpkg-deb und
# dpkg-shlibdeps (Paket dpkg-dev) gebraucht; die Abhängigkeiten (GTK,
# SQLCipher, …) ermittelt dpkg-shlibdeps aus den Programmdateien.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
app="$(cd "$here/../../app" && pwd)"
bundle="$app/build/linux/x64/release/bundle"
out="${1:-$app/build/packages}"

[ -x "$bundle/konsum" ] || {
	echo "Erst bauen: (cd app && flutter build linux --release)" >&2
	exit 1
}
version="$(sed -n 's/^version: *\([^+]*\).*/\1/p' "$app/pubspec.yaml")"
arch="$(dpkg --print-architecture 2>/dev/null || echo amd64)"
mkdir -p "$out"
out="$(cd "$out" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Dateien für das Desktop-Menü unter $1 (…/share).
install_desktop() {
	install -Dm644 "$here/de.azadoro.konsum.desktop" \
		"$1/applications/de.azadoro.konsum.desktop"
	install -Dm644 "$app/web/icons/Icon-512.png" \
		"$1/icons/hicolor/512x512/apps/de.azadoro.konsum.png"
	install -Dm644 "$app/web/icons/Icon-192.png" \
		"$1/icons/hicolor/192x192/apps/de.azadoro.konsum.png"
}

# --- .tar.gz: Programmordner zum Auspacken, Start mit ./konsum ---
tar_dir="$work/konsum-$version"
cp -r "$bundle" "$tar_dir"
install_desktop "$tar_dir/share"
cat >"$tar_dir/LIESMICH.txt" <<EOF
Konsum $version – gemeinsame Einkaufsliste
https://konsum.azadoro.de

Starten: ./konsum

Voraussetzungen: GTK 3 und SQLCipher
(Debian/Ubuntu: sudo apt install libgtk-3-0 libsqlcipher1)
sowie ein Schlüsselbund (KWallet, GNOME-Schlüsselbund, KeePassXC …).

Für das Startmenü: share/ nach ~/.local/share kopieren und in
~/.local/share/applications/de.azadoro.konsum.desktop bei Exec den
vollständigen Pfad zu konsum eintragen.
EOF
cp "$app/../LICENSE" "$tar_dir/LICENSE"
tarball="$out/konsum-$version-linux-x64.tar.gz"
tar -C "$work" --owner=0 --group=0 -czf "$tarball" "konsum-$version"
echo "Fertig: $tarball"

# --- .deb: Programm unter /opt/konsum, Aufruf über /usr/bin/konsum ---
command -v dpkg-deb >/dev/null || {
	echo "dpkg-deb fehlt – kein .deb gebaut" >&2
	exit 0
}
# dpkg-shlibdeps erkennt Bibliotheken des Pakets selbst nur unter
# debian/<paket>/, deshalb diese Struktur.
root="$work/deb/debian/konsum"
mkdir -p "$root/opt" "$root/usr/bin" "$root/DEBIAN"
cp -r "$bundle" "$root/opt/konsum"
ln -s /opt/konsum/konsum "$root/usr/bin/konsum"
install_desktop "$root/usr/share"
install -Dm644 "$app/../LICENSE" "$root/usr/share/doc/konsum/copyright"

printf 'Source: konsum\n\nPackage: konsum\nArchitecture: any\n' \
	>"$work/deb/debian/control"
depends="$(cd "$work/deb" && dpkg-shlibdeps -O \
	-l"$root/opt/konsum/lib" \
	"$root/opt/konsum/konsum" "$root"/opt/konsum/lib/*.so 2>/dev/null |
	sed -n 's/^shlibs:Depends=//p')"
[ -n "$depends" ] || {
	echo "dpkg-shlibdeps hat keine Abhängigkeiten ermittelt" >&2
	exit 1
}

cat >"$root/DEBIAN/control" <<EOF
Package: konsum
Version: $version
Architecture: $arch
Maintainer: Azadoro <konsum@azadoro.de>
Depends: $depends
Recommends: gnome-keyring | kwalletmanager | keepassxc
Section: utils
Priority: optional
Homepage: https://konsum.azadoro.de
Description: Gemeinsame Einkaufsliste für Haushalte und Vereine
 Offline-fähige Einkaufsliste, die mehrere Leute gemeinsam benutzen.
 Der Abgleich läuft Ende-zu-Ende-verschlüsselt über einen Matrix-Server
 deiner Wahl.
EOF
deb="$out/konsum_${version}_$arch.deb"
dpkg-deb --root-owner-group -Zxz --build "$root" "$deb" >/dev/null
echo "Fertig: $deb"
