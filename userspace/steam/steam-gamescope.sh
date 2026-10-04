#!/bin/sh
# armdeck: gamescope on the phone screen, with Steam from the "steam" container.
# Runs on the host (postmarketOS) as a user service (steam-gs.service):
#   systemd-run --user --unit=steam-gs --collect /bin/sh -c "~/steam-gamescope.sh > ~/steam-gs.log 2>&1"
# Stop: systemctl --user stop steam-gs
pkill -x gamescope 2>/dev/null
pkill -x gamescope-op8 2>/dev/null

# nobody is logged in on the screen, so no logind: direct access to /dev/dri and /dev/input
export LIBSEAT_BACKEND=noop
unset WAYLAND_DISPLAY

# the screen's physical size (6.55", 20:9) in landscape, so the Deck interface has the right scale
export GAMESCOPE_FAKE_OUTPUT_MM=152x68

# the performance overlay (Steam menu > Performance): mangoapp (MangoHud) runs in the container
# (op8-mangoapp, started by steam-in-container.sh), and Steam writes the chosen level to this
# file, also visible from the container (/run/user is shared). "gamescope --mangoapp" is not
# used: Alpine's mangoapp (0.7.1) does not understand gamescope 3.16.29's messages (see
# build-mangoapp-gs.sh). "no_display" until Steam writes the first level, as in ChimeraOS
# gamescope-session.
export MANGOHUD_CONFIGFILE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/mangohud.conf"
echo no_display > "$MANGOHUD_CONFIGFILE"

# EDID for Steam: the DSI panel has no EDID, and without one Steam does not know the real
# resolution. Gamescope hands Steam the EDID only through GAMESCOPE_PATCHED_EDID_FILE (the X
# property GAMESCOPE_DISPLAY_EDID_PATH, set once at start), and with no EDID from the panel it
# writes an empty file there. We put the panel's EDID, already rotated to landscape (2400x1080,
# 90 and 60 Hz, from make_edid.py), in its place; "<path>.tmp" as a directory makes gamescope's
# write (fopen .tmp, then rename) fail so it does not replace it. The path is under /run/user,
# shared with the Steam container.
EDID_SRC=/home/gabriel/op8-edid-landscape.bin
if [ -f "$EDID_SRC" ]; then
	export GAMESCOPE_PATCHED_EDID_FILE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/op8-edid.bin"
	rm -rf "$GAMESCOPE_PATCHED_EDID_FILE.tmp"
	cp "$EDID_SRC" "$GAMESCOPE_PATCHED_EDID_FILE"
	mkdir -p "$GAMESCOPE_PATCHED_EDID_FILE.tmp"
fi

# The panel is 1080x2400 portrait; gamescope gets the landscape logical size.
# right = the orientation in which the GameSir X3 Pro sits the right way up relative to the image.
# touch mode 4 = real touch events, as on a Steam Deck (swipe = scroll, no cursor); op8-touchmode
# switches it to 1 (mouse click) in games and back to 4 in the interface.
#
# Full screen: Steam does not treat the panel as an internal screen and asks Xwayland for 16:9
# modes (black bars). gamescope-op8 = Alpine's gamescope 3.16.29 plus patch 9001
# (gamescope/build-gamescope-op8.sh, pmbootstrap): with GAMESCOPE_FORCE_NATIVE_XWAYLAND, every
# Xwayland mode keeps its height and gets the panel's aspect ratio (1920x1080 -> 2400x1080,
# "Maximum game resolution" 1280x720 -> 1600x720). Without that binary, the system gamescope.
#
# No -r (--nested-refresh): in this DRM mode it does not set the panel's rate, but it does pace
# Steam and the games, so "-r 60" held everything at 60 fps while the panel scans out at 90 Hz.
# Without it, gamescope uses the panel's real rate; Steam's Frame Limit (Quick Access >
# Performance) caps games at 30 or 45 fps for battery.
#
# --xwayland-count 2: Steam gets one Xwayland and games a second one. With -e and more than one
# Xwayland, gamescope itself exports STEAM_MULTIPLE_XWAYLANDS=1 to Steam (UpdateCompatEnvVars()
# in gamescope's main.cpp; ChimeraOS sets it too), so it is not set here or in the container.
GS=gamescope
if [ -x /home/gabriel/bin/gamescope-op8 ]; then
	GS=/home/gabriel/bin/gamescope-op8
	export GAMESCOPE_FORCE_NATIVE_XWAYLAND=1
fi
exec "$GS" -W 2400 -H 1080 --xwayland-count 2 --backend drm \
	--force-orientation right --default-touch-mode 4 -e -- \
	distrobox enter steam -- /home/gabriel/steam-in-container.sh
