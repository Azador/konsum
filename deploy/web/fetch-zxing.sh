#!/bin/sh
# Holt zxing-wasm (Barcode-Erkennung im Browser, zxing-cpp als WebAssembly)
# nach app/web/zxing. Feste Version mit Prüfsummen; die Web-App lädt es von
# dort statt von einem CDN. Gebraucht nur in Browsern ohne BarcodeDetector
# (Firefox, Safari).
set -eu
version=3.1.3
base="https://cdn.jsdelivr.net/npm/zxing-wasm@$version/dist"
here="$(cd "$(dirname "$0")" && pwd)"
out="$here/../../app/web/zxing"

check() {
	cd "$out" && sha256sum -c --quiet <<SUMS
98e44c8063b9aa75b31562f6b64b2cead420842ac3e4f57a791c01cd8f450a7a  index.js
2ebda08a93eea3efcd8399cda6b276e6a0b1de4fec60b4d8988a047de4c6d1ba  zxing_reader.wasm
SUMS
}

if [ -d "$out" ] && (check) 2>/dev/null; then
	exit 0
fi
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fsSL -o "$tmp/index.js" "$base/iife/reader/index.js"
curl -fsSL -o "$tmp/zxing_reader.wasm" "$base/reader/zxing_reader.wasm"
rm -rf "$out"
mv "$tmp" "$out"
chmod 755 "$out"
check || {
	rm -rf "$out"
	echo "zxing-wasm: Prüfsumme stimmt nicht" >&2
	exit 1
}
echo "zxing-wasm $version nach app/web/zxing geladen"
