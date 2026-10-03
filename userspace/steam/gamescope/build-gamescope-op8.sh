#!/bin/bash
# armdeck: gamescope 3.16.29 (pachetul Alpine, aports community/gamescope) plus patch-ul
# 9001 (Xwayland ramane la dimensiunea nativa a panoului, orice ar cere Steam), construit pentru
# aarch64 cu pmbootstrap, in WSL. Rezultat: gamescope-op8, de copiat pe telefon in ~/bin/
# (fara instalare; steam-gamescope.sh il foloseste daca exista, altfel gamescope-ul din sistem).
# Folosire: bash build-gamescope-op8.sh <director de iesire>
# Nota: crossdirect (compilarea incrucisata rapida) a esuat pe 2026-10-02 ("cannot execute cc1"),
# deci build-ul ruleaza sub emulare qemu (--no-cross), ~15 minute pe un PC cu 16 fire.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${1:-$HERE}
PMB="python3 $HOME/pmbootstrap/pmbootstrap.py"
A=https://gitlab.alpinelinux.org/alpine/aports/-/raw/master/community/gamescope
D=~/pmaports/temp/gamescope
rm -rf "$D"
mkdir -p "$D"
for f in APKBUILD 0001-Fix-undefined-type-uint.patch system-deps.patch system-spirv-headers.patch; do
	curl -fsL -o "$D/$f" "$A/$f"
done
grep -q '^pkgver=3.16.29$' "$D/APKBUILD" || { echo "OPRIT: aports are alta versiune de gamescope; verifica patch-ul"; exit 1; }
cp "$HERE/9001-armdeck-force-native-xwayland.patch" "$D/"
sed -i 's/^pkgrel=.*/pkgrel=100/' "$D/APKBUILD"
sed -i 's/^\t0001-Fix-undefined-type-uint.patch$/\t0001-Fix-undefined-type-uint.patch\n\t9001-armdeck-force-native-xwayland.patch/' "$D/APKBUILD"
sed -i 's/^arch=/options="!check"\narch=/' "$D/APKBUILD"
$PMB checksum gamescope
$PMB -y --no-cross build --arch aarch64 --force gamescope
W=$($PMB config work)
T=$(mktemp -d)
tar -xzf "$W/packages/edge/aarch64/gamescope-3.16.29-r100.apk" -C "$T" 2>/dev/null
grep -q GAMESCOPE_FORCE_NATIVE_XWAYLAND "$T/usr/bin/gamescope" || { echo "OPRIT: patch-ul lipseste din binar"; exit 1; }
cp "$T/usr/bin/gamescope" "$OUT/gamescope-op8"
sha256sum "$OUT/gamescope-op8"
