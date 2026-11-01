#!/bin/sh
# install-decky.sh (armdeck): Decky Loader, the plugin menu of the Steam Deck's Game Mode, for the
# ARM64 Steam in the "steam" container. Decky hooks into Steam's built-in browser through its
# remote debugging port (127.0.0.1:8080), which Steam opens only when
# ~/.local/share/Steam/.cef-enable-remote-debugging exists; this script creates that file.
#
# The binary: upstream's own ARM64 build (SteamDeckHomebrew/decky-loader, official Linux arm64
# builds since v3.3.0, built on ubuntu-26.04-arm with Python 3.14; its bundled libraries need
# glibc 2.42 at most, the container has 2.43). The sha256 below is the one GitHub publishes for
# that asset. Its self-updater fetches the same "PluginLoader-arm64" asset of later releases.
# Before 2026-10-30 this was DroidDeck's ARM64 fork (Droid-Deck/decky-loader,
# "droiddeck-arm64-preview.2", Decky v3.2.9-dev8, sha256 5de85f00...). Its frontend's @decky/ui
# found Steam's Quick Access style module by a class name that a Steam beta update removed, so
# Decky's whole panel failed to render (docs/lessons-learned.md); v3.3.0 has the fix.
# An existing binary is kept as PluginLoader.prev; to go back: mv PluginLoader.prev PluginLoader.
#
# Decky runs as this user, not as root (op8-decky). Plugins that ask for root (TDP, CPU and GPU
# clock plugins, written for the Steam Deck's AMD chip) therefore cannot touch the hardware.
#
# Run as the normal user, in the container (the postmarketOS host has no curl):
#   distrobox enter steam -- sh ~/install-decky.sh
# Then restart the Steam session (systemctl --user restart steam-gs): Steam opens the debugging
# port at start, and steam-in-container.sh starts Decky through op8-decky.
# When Decky was already installed, stopping the running loader is enough: op8-decky starts the
# new binary at once (pkill -f services/PluginLoader).
# To turn Decky off without removing it: touch ~/homebrew/armdeck-decky-off
# To remove it: rm -r ~/homebrew ~/.local/share/Steam/.cef-enable-remote-debugging
set -eu
URL=https://github.com/SteamDeckHomebrew/decky-loader/releases/download/v3.3.1/PluginLoader-arm64
SHA=6320bcf990aacc1c7a8aff67e17c98ece66601d1a7cc3d21d4259c7273adb2bb
TAG=v3.3.1
H=$HOME/homebrew
BIN=$H/services/PluginLoader

mkdir -p "$H/services" "$H/plugins"
TMP=$H/services/PluginLoader.download
if command -v curl >/dev/null 2>&1; then
	curl -fL -o "$TMP" "$URL"
else
	wget -O "$TMP" "$URL"
fi
echo "$SHA  $TMP" | sha256sum -c -
chmod 755 "$TMP"
[ -f "$BIN" ] && cp -p "$BIN" "$BIN.prev"
mv -f "$TMP" "$BIN"
echo "$TAG" > "$H/services/.loader.version"
touch "$HOME/.local/share/Steam/.cef-enable-remote-debugging"
ls -l "$BIN" "$HOME/.local/share/Steam/.cef-enable-remote-debugging"
echo "Decky installed. Restart the Steam session: systemctl --user restart steam-gs"
