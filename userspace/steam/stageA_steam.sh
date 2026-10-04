#!/bin/bash
# armdeck, stage A: the native ARM64 Steam client, in the distrobox container "steam".
# The same method as pocknix-os (packages/shared/pocknix-steam/pocknix-steam-install), plus
# checksum verification. Runs as the normal user, in the container, without sudo.
#   phase 1: download and verify the runtime and the client
#   phase 2: let the client update itself under Xvfb (a virtual screen)
set -euo pipefail

STEAM="$HOME/.local/share/Steam"
STEAM_DOT="$HOME/.steam"
CHANNEL=steamdeck_publicbeta
MANIFEST="steam_client_${CHANNEL}_linuxarm64"
RT_BASE=https://repo.steampowered.com/steamrt3c/images/latest-public-beta
CDN=https://client-update.steamstatic.com

mkdir -p "$STEAM"
cd "$STEAM"

phase1() {
	# the Steam runtime for ARM64 (steamrt3c)
	if [ ! -d steam-runtime-steamrt-arm64 ]; then
		wget -c --tries=20 -O steam-runtime-steamrt-arm64.tar.xz \
			"$RT_BASE/steam-runtime-steamrt-arm64.tar.xz"
		curl -fsSL -o SHA256SUMS.rt "$RT_BASE/SHA256SUMS"
		grep ' \*steam-runtime-steamrt-arm64.tar.xz$' SHA256SUMS.rt | sha256sum -c -
		tar xf steam-runtime-steamrt-arm64.tar.xz
		rm -f steam-runtime-steamrt-arm64.tar.xz SHA256SUMS.rt
		target=$(ls steam-runtime-steamrt-arm64/steamrt3c_platform_*/files/lib/aarch64-linux-gnu/libibus-1.0.so.5.* | head -n1)
		mkdir -p lib/aarch64-linux-gnu
		# relative, as in pocknix: steamwebhelper needs libibus
		ln -sfn "../../$target" lib/aarch64-linux-gnu/libibus-1.0.so.5
	fi

	# the ARM64 Steam client; the archive name ends with its SHA1
	if [ ! -d steamrtarm64 ]; then
		f=$(curl -fsSL "$CDN/$MANIFEST" | tr -c '[:print:]' '\n' \
			| grep -oE 'bins_linuxarm64_linuxarm64\.zip\.[0-9a-f]{40}' | head -n1)
		[ -n "$f" ] || { echo "ERROR: the client archive is not in the manifest"; exit 1; }
		wget -c --tries=20 -O linuxarm64.zip "$CDN/$f"
		want=${f##*.}
		got=$(sha1sum linuxarm64.zip | cut -d' ' -f1)
		echo "sha1 expected $want"
		echo "sha1 got      $got"
		[ "$want" = "$got" ] || { echo "ERROR: SHA1 differs, not continuing"; exit 1; }
		unzip -o -q linuxarm64.zip
		rm -f linuxarm64.zip
		chmod +x steamrtarm64/steam
		mkdir -p package
		echo "$CHANNEL" > package/beta
		mkdir -p "$STEAM_DOT"
		ln -sfn ../.local/share/Steam             "$STEAM_DOT/steam"
		ln -sfn ../.local/share/Steam             "$STEAM_DOT/root"
		ln -sfn ../.local/share/Steam/linux32     "$STEAM_DOT/sdk32"
		ln -sfn ../.local/share/Steam/linux64     "$STEAM_DOT/sdk64"
		ln -sfn ../.local/share/Steam/linuxarm64  "$STEAM_DOT/sdkarm64"
		ln -sfn ../.local/share/Steam/ubuntu12_32 "$STEAM_DOT/bin32"
		ln -sfn ../.local/share/Steam/ubuntu12_64 "$STEAM_DOT/bin64"
	fi
	echo "== DONE phase 1"
	du -sh "$STEAM"
}

phase2() {
	command -v xvfb-run >/dev/null || { echo "ERROR: xvfb-run is missing"; exit 1; }
	# steamrtarm64 first in LD_LIBRARY_PATH, as in pocknix
	LD_LIBRARY_PATH="$STEAM/steamrtarm64:$STEAM/lib/aarch64-linux-gnu" \
		timeout 570 xvfb-run -a "$STEAM/steamrtarm64/steam" -steamdeck -exitsteam \
		> "$HOME/steam-bootstrap.log" 2>&1 || echo "steam exited with code $?"
	if [ -f "package/$MANIFEST.installed" ] && [ -f steamrtarm64/steamui.so ]; then
		echo "== BOOTSTRAP OK"
	else
		echo "== BOOTSTRAP INCOMPLETE (see ~/steam-bootstrap.log)"
	fi
	du -sh "$STEAM"
}

case "${1:-}" in
	1) phase1 ;;
	2) phase2 ;;
	*) echo "usage: $0 1|2"; exit 2 ;;
esac
