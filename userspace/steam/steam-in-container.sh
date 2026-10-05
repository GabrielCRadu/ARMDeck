#!/bin/bash
# armdeck, stage A: starts the ARM64 Steam client in Deck mode, in the "steam" container.
# steam-gamescope.sh (on the host) starts it, as a child process of gamescope.
STEAM="$HOME/.local/share/Steam"
CLIENT_DIR="$STEAM/steamrtarm64"

# Steam looks for bin/vgui2_s.dll relative to the current directory
cd "$CLIENT_DIR" || exit 1

# the ARM64 client with the Deck interface only works on the steamdeck_publicbeta channel
mkdir -p "$STEAM/package"
echo steamdeck_publicbeta > "$STEAM/package/beta"

# Turnip only (the real GPU), not llvmpipe (a GPU emulated on the processor)
export VK_DRIVER_FILES=/usr/share/vulkan/icd.d/freedreno_icd.aarch64.json

# the host's system D-Bus (there is no /run/dbus in the container); Steam in SteamOS mode uses it
# for network, Bluetooth and battery
export DBUS_SYSTEM_BUS_ADDRESS=unix:path=/run/host/run/dbus/system_bus_socket

# Controllers connected after Steam starts: udev events do not reach the rootless container
# (libudev ignores messages whose sender is not root in the namespace), so SDL watches /dev/input
# directly through inotify.
export SDL_JOYSTICK_DISABLE_UDEV=1

# The panel (DSI, no EDID) has no real HDR; gamescope announces it anyway, and Steam asks for an
# HDR (10-bit) stream in Remote Play. Test: SDR. To go back, delete the line.
export STEAM_GAMESCOPE_HDR_SUPPORTED=0

# Diagnosing a game: Proton log in ~/proton-logs/steam-<appid>.log (exceptions, loaded DLLs, DXVK
# messages). Off by default: FEX raises many exceptions, and logging them lowers the FPS.
# For a single game it is better from Properties > Launch Options: PROTON_LOG=1 %command%
#export PROTON_LOG=1
export PROTON_LOG_DIR=/home/gabriel/proton-logs

# Remote Play diagnosis: full SDL3 log (the streaming client uses SDL3 for video, audio and
# rendering). Off by default: it makes the log large and costs CPU time in the client. Uncomment
# only while debugging streaming.
#export SDL_LOGGING='*=verbose'

# the performance overlay: mangoapp-gs runs here, in the container (op8-mangoapp), and Steam
# writes the chosen level (preset) to the shared file created by steam-gamescope.sh. The variables
# are those of ChimeraOS gamescope-session-steam. Without a built mangoapp-gs, Steam does not get
# them. The file is in /tmp so that games in pressure-vessel can read it too (see
# steam-gamescope.sh).
MANGO_CONF="/tmp/armdeck-$(id -u)/mangohud.conf"
if [ -f "$MANGO_CONF" ] && [ -x /home/gabriel/games/build/mangoapp-gs ]; then
	export MANGOHUD_CONFIGFILE="$MANGO_CONF"
	export STEAM_USE_MANGOAPP=1
	export STEAM_MANGOAPP_PRESETS_SUPPORTED=1
	export STEAM_MANGOAPP_HORIZONTAL_SUPPORTED=1
	export STEAM_DISABLE_MANGOAPP_ATOM_WORKAROUND=1
	# started right before "exec steam" (below), so its parent becomes the Steam process
	START_MANGOAPP=1
fi

# Frame Limit from Quick Access for every Vulkan game, without input delay: gamescope-op8 (patch
# 9003) writes Steam's requested limit to $ARMDECK_FPS_LIMIT_FILE instead of enforcing it,
# op8-fpslimit copies it as fps_limit into Steam's MangoHud file, and the MangoHud layer in each
# game (hidden: no_display, preset 0; read_cfg = read that file too) sleeps to that rate. The
# control socket gets a per-process name so games never take mangoapp's. mangoapp itself is
# started without these two variables (below), otherwise no_display would hide the overlay.
if [ -n "${ARMDECK_FPS_LIMIT_FILE:-}" ] && [ -n "${START_MANGOAPP:-}" ]; then
	export MANGOHUD=1
	export MANGOHUD_CONFIG="read_cfg,preset=0,no_display,control=armdeck-game-%p,fps_limit_method=late"
	START_FPSLIMIT=1
fi

# without LANG the X input method (XOpenIM) does not start
export LANG=C.UTF-8

# the client directory first, as in pocknix
export LD_LIBRARY_PATH="$CLIENT_DIR:$STEAM/lib/aarch64-linux-gnu"

# touch as on a Steam Deck, also without a controller (interface = real touch, games = click)
/home/gabriel/op8-touchmode &

[ -n "${START_MANGOAPP:-}" ] && env -u MANGOHUD -u MANGOHUD_CONFIG /home/gabriel/op8-mangoapp &
[ -n "${START_FPSLIMIT:-}" ] && /home/gabriel/op8-fpslimit &

# the volume buttons: volume on release, continuous volume while held, and both together = the
# Steam button (replaces the old op8-volbtn on the host; its service must stay disabled)
/home/gabriel/op8-buttons.py &

# Decky Loader (the plugin menu in Quick Access), if installed with install-decky.sh; it runs as
# this user and stops with Steam (op8-decky)
/home/gabriel/op8-decky &

# No -noshaders: the same Steam mechanism also brings the games' re-encoded videos
# (STEAM_COMPAT_TRANSCODED_MEDIA_PATH). Proton cannot decode H.264, and without them it shows TV
# test bars instead of the videos (Poppy Playtime, Tiny Rails, 2026-10-02).
exec "$CLIENT_DIR/steam" -gamepadui -steamos3 -steampal -steamdeck -noverifyfiles
