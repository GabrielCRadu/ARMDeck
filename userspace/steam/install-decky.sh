#!/bin/sh
# install-decky.sh (armdeck): Decky Loader, the plugin menu of the Steam Deck's Game Mode, for the
# ARM64 Steam in the "steam" container. Decky hooks into Steam's built-in browser through its
# remote debugging port (127.0.0.1:8080), which Steam opens only when
# ~/.local/share/Steam/.cef-enable-remote-debugging exists; this script creates that file.
#
# The binary: upstream (SteamDeckHomebrew/decky-loader) publishes an x86_64 build only. DroidDeck's
# fork (Droid-Deck/decky-loader) adds an ARM64 build to the same CI; its release
# "droiddeck-arm64-preview.2" was built by the fork's "Builder ARM64" workflow from commit
# d67fd162, which is upstream main of 2026-09-25 plus 7 small commits (the ARM64 workflow, an
# ON_ARM64 flag, and the self-updater handing ARM64 updates to DroidDeck, so it never replaces
# itself with the x86_64 build). The sha256 below is the one GitHub publishes for that asset.
#
# Decky runs as this user, not as root (op8-decky). Plugins that ask for root (TDP, CPU and GPU
# clock plugins, written for the Steam Deck's AMD chip) therefore cannot touch the hardware.
#
# Run as the normal user, in the container (the postmarketOS host has no curl):
#   distrobox enter steam -- sh ~/install-decky.sh
# Then restart the Steam session (systemctl --user restart steam-gs): Steam opens the debugging
# port at start, and steam-in-container.sh starts Decky through op8-decky.
# To turn Decky off without removing it: touch ~/homebrew/armdeck-decky-off
# To remove it: rm -r ~/homebrew ~/.local/share/Steam/.cef-enable-remote-debugging
set -eu
URL=https://github.com/Droid-Deck/decky-loader/releases/download/droiddeck-arm64-preview.2/PluginLoader-arm64
SHA=5de85f0018e72b671d71adadd0bf0ab854be42da68d55ae8ff54da83d432df88
TAG=droiddeck-arm64-preview.2
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
mv -f "$TMP" "$BIN"
echo "$TAG" > "$H/services/.loader.version"
touch "$HOME/.local/share/Steam/.cef-enable-remote-debugging"
ls -l "$BIN" "$HOME/.local/share/Steam/.cef-enable-remote-debugging"
echo "Decky installed. Restart the Steam session: systemctl --user restart steam-gs"
