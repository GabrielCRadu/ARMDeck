#!/bin/bash
# install-fex-rootfs.sh (armdeck): the x86 system that native x86 Linux games need (Half-Life,
# Terraria, LIMBO, Hue...). Run inside the Steam container:
#   distrobox enter steam -- bash /home/gabriel/install-fex-rootfs.sh
#
# Steam ARM64 runs x86 Linux games through its FEX tool (steamapps/common/FEX-Emu,
# fex-compat-tool). That tool takes its x86 libraries and graphics driver from a fixed path,
# /usr/share/guestos/fex-mesa, which must hold an x86-64 + i386 system with x86 Mesa and a
# graphics_provider.json (pressure-vessel imports the drivers from there). SteamOS for the Steam
# Frame ships one; here it was missing, so those games closed in under a second (TODO 12).
#
# This installs FEX's own Arch Linux root filesystem (rootfs.fex-emu.gg, the image
# FEXRootFSFetcher offers; pocknix-os uses the same one). It is built with Mesa 26.2 for x86_64
# and i386 including freedreno (OpenGL) and Turnip (Vulkan), the drivers for the Adreno 650
# (FEX-Emu/RootFS, Scripts/Arch/build_install_mesa.sh). The image is checked against the size
# and XXH3 hash FEX publishes, unpacked on the games partition (not the 13 GB system partition)
# and linked into the container. Nothing on the phone's system changes. Re-running it resumes a
# broken download and skips the steps already done.
set -euo pipefail
NAME=ArchLinux
DATE=2026-08-11
URL=https://rootfs.fex-emu.gg/$NAME/$DATE/$NAME.sqsh
SIZE=1359826944
XXH3=23350f949fc1413d                     # from https://rootfs.fex-emu.gg/RootFS_links.json
DIR=/home/gabriel/games/fex-rootfs
SQSH=$DIR/$NAME-$DATE.sqsh
ROOT=$DIR/$NAME-$DATE
LINK=/usr/share/guestos/fex-mesa

need=
command -v unsquashfs > /dev/null || need="$need squashfs-tools"
command -v xxhsum > /dev/null || need="$need xxhash"
[ -z "$need" ] || sudo dnf install -y $need

mkdir -p "$DIR"
if [ ! -d "$ROOT" ]; then
	if [ "$(stat -c %s "$SQSH" 2>/dev/null || echo 0)" != "$SIZE" ]; then
		echo "== downloading $URL ($((SIZE / 1048576)) MiB, resumes if interrupted)"
		curl -fL --retry 5 -C - -o "$SQSH" "$URL"
	fi
	[ "$(stat -c %s "$SQSH")" = "$SIZE" ] || { echo "STOPPED: wrong size, delete $SQSH and run again"; exit 1; }
	echo "== checking the XXH3 hash"
	got=$(xxhsum -H3 "$SQSH" | awk '{print $1}' | sed 's/^XXH3_//; s/^0*//')
	[ "$got" = "$(echo "$XXH3" | sed "s/^0*//")" ] || { echo "STOPPED: hash $got, expected $XXH3; delete $SQSH and run again"; exit 1; }
	echo "== unpacking into $ROOT"
	rm -rf "$ROOT.tmp"
	# as a normal user: no ownership changes, no extended attributes (not needed to read the files)
	unsquashfs -no-xattrs -q -d "$ROOT.tmp" "$SQSH" || echo "(unsquashfs reported problems, checking the result)"
	for f in usr/lib/libc.so.6 usr/lib32/libc.so.6 usr/share/vulkan/icd.d; do
		[ -e "$ROOT.tmp/$f" ] || { echo "STOPPED: $f missing from the unpacked image"; exit 1; }
	done
	mv "$ROOT.tmp" "$ROOT"
fi

# the manifest pressure-vessel reads; FEX's image normally carries it at its top level
if [ ! -f "$ROOT/graphics_provider.json" ]; then
	echo "== adding graphics_provider.json (the one from FEX-Emu/RootFS, Scripts/Arch)"
	cat > "$ROOT/graphics_provider.json" <<'JSON'
{
  "graphics_provider_v0": {
    "root": "./",
    "locales": false,
    "va_api": false,
    "vdpau": false,
    "architectures": {
      "x86_64-linux-gnu": {
        "dri": "/usr/lib/dri",
        "fallback_library_paths": ["/usr/lib"],
        "gconv": "/usr/lib/gconv"
      },
      "i386-linux-gnu": {
        "dri": "/usr/lib32/dri",
        "fallback_library_paths": ["/usr/lib32"],
        "gconv": "/usr/lib32/gconv"
      }
    }
  }
}
JSON
fi

sudo mkdir -p "$(dirname "$LINK")"
sudo ln -sfn "$ROOT" "$LINK"

echo "== result"
ls -l "$LINK"
du -sh "$ROOT"
ls "$ROOT"/usr/share/vulkan/icd.d/ | grep -i freedreno || echo "WARNING: no Turnip ICD for x86"
ls "$ROOT"/usr/lib/dri "$ROOT"/usr/lib32/dri 2>/dev/null | grep -i -E "msm|kgsl|freedreno" | sort -u | head -4
echo "== DONE. Native x86 Linux games can now be started from Steam (no restart needed)."
