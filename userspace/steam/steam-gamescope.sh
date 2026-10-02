#!/bin/sh
# steamed-noodle, etapa A: gamescope pe ecranul telefonului, cu Steam din containerul "steam".
# Ruleaza pe gazda (postmarketOS) ca serviciu al userului:
#   systemd-run --user --unit=steam-gs --collect /bin/sh -c "~/steam-gamescope.sh > ~/steam-gs.log 2>&1"
# Oprire: systemctl --user stop steam-gs
pkill -x gamescope 2>/dev/null

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

# panoul e 1080x2400 portret; gamescope primeste dimensiunea logica landscape.
# right = orientarea in care controlerul GameSir X3 Pro sta corect fata de imagine.
# touch mode 4 = evenimente touch reale, ca pe Steam Deck (glisare = scroll, fara cursor);
# Steam comuta singur pe 1 (mouse) in jocuri si inapoi pe 4 in interfata
exec gamescope -W 2400 -H 1080 -r 60 --xwayland-count 2 --backend drm \
	--force-orientation right --default-touch-mode 4 -e -- \
	distrobox enter steam -- /home/gabriel/steam-in-container.sh
