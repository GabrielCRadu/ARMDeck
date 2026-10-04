#!/bin/bash
# armdeck: gamescope 3.16.29 (the Alpine package, aports community/gamescope) plus patch 9001
# (every Xwayland mode keeps its height but gets the panel's 20:9 aspect ratio, so Steam's
# 1920x1080 becomes the native 2400x1080 and a 1280x720 "Maximum game resolution" becomes
# 1600x720, full screen), built for aarch64 with pmbootstrap, in WSL. Result: gamescope-op8, to
# copy to the phone in ~/bin/ (not installed; steam-gamescope.sh uses it when it exists,
# otherwise the system gamescope).
# Usage: bash build-gamescope-op8.sh <output directory>
# Note: crossdirect (the fast cross compile) failed on 2026-10-02 ("cannot execute cc1"), so the
# build runs under qemu emulation (--no-cross), about 15 minutes on a PC with 16 threads.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${1:-$HERE}
PATCH=9001-armdeck-xwayland-panel-aspect.patch
PMB="python3 $HOME/pmbootstrap/pmbootstrap.py"
A=https://gitlab.alpinelinux.org/alpine/aports/-/raw/master/community/gamescope
D=~/pmaports/temp/gamescope
rm -rf "$D"
mkdir -p "$D"
for f in APKBUILD 0001-Fix-undefined-type-uint.patch system-deps.patch system-spirv-headers.patch; do
	curl -fsL -o "$D/$f" "$A/$f"
done
grep -q '^pkgver=3.16.29$' "$D/APKBUILD" || { echo "STOPPED: aports has another gamescope version; check the patch"; exit 1; }
cp "$HERE/$PATCH" "$D/"
sed -i 's/^pkgrel=.*/pkgrel=100/' "$D/APKBUILD"
sed -i "s/^\t0001-Fix-undefined-type-uint.patch\$/\t0001-Fix-undefined-type-uint.patch\n\t$PATCH/" "$D/APKBUILD"
grep -q "$PATCH" "$D/APKBUILD" || { echo "STOPPED: the patch was not added to the APKBUILD"; exit 1; }
sed -i 's/^arch=/options="!check"\narch=/' "$D/APKBUILD"
$PMB checksum gamescope
$PMB -y --no-cross build --arch aarch64 --force gamescope
W=$($PMB config work)
T=$(mktemp -d)
tar -xzf "$W/packages/edge/aarch64/gamescope-3.16.29-r100.apk" -C "$T" 2>/dev/null
grep -q "panel aspect ratio" "$T/usr/bin/gamescope" || { echo "STOPPED: the patch is missing from the binary"; exit 1; }
cp "$T/usr/bin/gamescope" "$OUT/gamescope-op8"
sha256sum "$OUT/gamescope-op8"
