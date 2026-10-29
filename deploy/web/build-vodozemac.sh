#!/bin/sh
# Baut vodozemac (Matrix-Verschlüsselung) als WebAssembly nach app/web/pkg.
#
# Quelle sind die Pakete flutter_vodozemac (Rust) und vodozemac (Dart) aus dem
# Pub-Cache, also genau die Versionen aus app/pubspec.lock. Gebaut wird nur,
# wenn sich die Version geändert hat.
#
# Voraussetzungen (einmalig, ohne root):
#   rustup toolchain install nightly --component rust-src
#   rustup target add wasm32-unknown-unknown --toolchain nightly
#   cargo install flutter_rust_bridge_codegen --version <siehe unten> --locked
#   cargo install wasm-pack --locked
set -eu
app="$(cd "$(dirname "$0")/../../app" && pwd)"
out="$app/web/pkg"
export PATH="$HOME/.cargo/bin:$PATH"

cd "$app"
flutter pub get >/dev/null

# Pfad eines Pakets aus .dart_tool/package_config.json.
package_dir() {
	grep -A1 "\"name\": \"$1\"" .dart_tool/package_config.json |
		sed -n 's|.*"rootUri": "file://\(.*\)".*|\1|p'
}
rust_pkg="$(package_dir flutter_vodozemac)"
dart_pkg="$(package_dir vodozemac)"
[ -d "$rust_pkg/rust" ] && [ -d "$dart_pkg/lib" ] || {
	echo "flutter_vodozemac/vodozemac nicht gefunden" >&2
	exit 1
}

stamp="$(basename "$rust_pkg") $(basename "$dart_pkg")"
if [ -f "$out/.konsum-stamp" ] && [ "$(cat "$out/.konsum-stamp")" = "$stamp" ]; then
	echo "vodozemac (WASM) ist aktuell: $stamp"
	exit 0
fi

# Rust und Dart müssen aus demselben Codegen-Lauf stammen.
hash_rust="$(sed -n 's/.*CONTENT_HASH: i32 = \(-\{0,1\}[0-9]*\);/\1/p' "$rust_pkg/rust/src/frb_generated.rs")"
hash_dart="$(sed -n 's/.*rustContentHash => \(-\{0,1\}[0-9]*\);/\1/p' "$dart_pkg/lib/src/generated/frb_generated.dart")"
if [ -z "$hash_rust" ] || [ "$hash_rust" != "$hash_dart" ]; then
	echo "Rust- und Dart-Teil von vodozemac passen nicht zusammen ($hash_rust/$hash_dart)" >&2
	exit 1
fi
frb="$(sed -n "s/.*codegenVersion => '\(.*\)';/\1/p" "$dart_pkg/lib/src/generated/frb_generated.dart")"
have="$(flutter_rust_bridge_codegen --version 2>/dev/null | awk '{print $2}')"
if [ "$have" != "$frb" ]; then
	echo "Benötigt flutter_rust_bridge_codegen $frb (installiert: ${have:-keins}):" >&2
	echo "  cargo install flutter_rust_bridge_codegen --version $frb --locked" >&2
	exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cp -r "$dart_pkg" "$work/dart"
cp -r "$rust_pkg/rust" "$work/rust"
chmod -R u+w "$work"

echo "Baue vodozemac als WASM ($stamp) …"
(cd "$work/dart" && dart pub get >/dev/null)
(cd "$work" && flutter_rust_bridge_codegen build-web \
	--dart-root dart --rust-root "$work/rust" --release)

rm -rf "$out"
mkdir -p "$out"
cp "$work/dart/web/pkg/vodozemac_bindings_dart.js" \
	"$work/dart/web/pkg/vodozemac_bindings_dart_bg.wasm" "$out/"
echo "$stamp" >"$out/.konsum-stamp"
echo "Fertig: $out"
