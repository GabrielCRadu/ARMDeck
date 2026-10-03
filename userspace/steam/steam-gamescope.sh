#!/bin/sh
# armdeck, etapa A: gamescope pe ecranul telefonului, cu Steam din containerul "steam".
# Ruleaza pe gazda (postmarketOS) ca serviciu al userului:
#   systemd-run --user --unit=steam-gs --collect /bin/sh -c "~/steam-gamescope.sh > ~/steam-gs.log 2>&1"
# Oprire: systemctl --user stop steam-gs
pkill -x gamescope 2>/dev/null
pkill -x gamescope-op8 2>/dev/null

# nimeni nu e logat pe ecran, deci fara logind: acces direct la /dev/dri si /dev/input
export LIBSEAT_BACKEND=noop
unset WAYLAND_DISPLAY

# dimensiunea fizica a ecranului (6.55", 20:9) in landscape, ca interfata Deck sa aiba marimea corecta
export GAMESCOPE_FAKE_OUTPUT_MM=152x68

# overlay-ul de performanta (meniul Steam > Performance): mangoapp (MangoHud) ruleaza in container
# (op8-mangoapp, pornit de steam-in-container.sh), iar Steam scrie nivelul ales in acest fisier,
# vazut si din container (/run/user e comun). Nu se foloseste "gamescope --mangoapp": mangoapp din
# Alpine (0.7.1) nu intelege mesajele lui gamescope 3.16.29 (vezi build-mangoapp-gs.sh).
# "no_display" pana cand Steam scrie primul nivel, ca la ChimeraOS gamescope-session.
export MANGOHUD_CONFIGFILE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/mangohud.conf"
echo no_display > "$MANGOHUD_CONFIGFILE"

# EDID pentru Steam: panoul DSI n-are EDID, iar fara el Steam nu stie rezolutia reala si porneste
# jocurile la 1920x1080 (benzi negre). Gamescope ii da lui Steam EDID-ul doar prin
# GAMESCOPE_PATCHED_EDID_FILE (proprietatea X GAMESCOPE_DISPLAY_EDID_PATH, setata o data la
# pornire), iar fara EDID de la panou scrie acolo un fisier gol. Punem in locul lui EDID-ul
# panoului deja rotit in landscape (2400x1080, 90 si 60 Hz, din make_edid.py); "<cale>.tmp" ca
# director face ca scrierea lui gamescope (fopen .tmp, apoi rename) sa esueze si sa nu-l stearga.
# Calea e sub /run/user, comuna cu containerul Steam.
EDID_SRC=/home/gabriel/op8-edid-landscape.bin
if [ -f "$EDID_SRC" ]; then
	export GAMESCOPE_PATCHED_EDID_FILE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/op8-edid.bin"
	rm -rf "$GAMESCOPE_PATCHED_EDID_FILE.tmp"
	cp "$EDID_SRC" "$GAMESCOPE_PATCHED_EDID_FILE"
	mkdir -p "$GAMESCOPE_PATCHED_EDID_FILE.tmp"
fi

# panoul e 1080x2400 portret; gamescope primeste dimensiunea logica landscape.
# right = orientarea in care controlerul GameSir X3 Pro sta corect fata de imagine.
# touch mode 4 = evenimente touch reale, ca pe Steam Deck (glisare = scroll, fara cursor);
# Steam comuta singur pe 1 (mouse) in jocuri si inapoi pe 4 in interfata
#
# Full screen: Steam nu trateaza panoul ca ecran intern si cere pentru Xwayland 1920x1080 (benzi
# negre, jocuri plafonate la 1920x1080). gamescope-op8 = gamescope 3.16.29 din Alpine plus
# patch-ul 9001 (gamescope/build-gamescope-op8.sh, pmbootstrap): cu GAMESCOPE_FORCE_NATIVE_XWAYLAND, Xwayland
# ramane la dimensiunea nativa, orice ar cere Steam. Fara binar, gamescope-ul din sistem.
GS=gamescope
if [ -x /home/gabriel/bin/gamescope-op8 ]; then
	GS=/home/gabriel/bin/gamescope-op8
	export GAMESCOPE_FORCE_NATIVE_XWAYLAND=1
fi
exec "$GS" -W 2400 -H 1080 -r 60 --xwayland-count 2 --backend drm \
	--force-orientation right --default-touch-mode 4 -e -- \
	distrobox enter steam -- /home/gabriel/steam-in-container.sh
