#!/bin/bash
# steamed-noodle, etapa A: porneste clientul Steam ARM64 in modul Deck, in containerul "steam".
# Il porneste steam-gamescope.sh (pe gazda), ca proces copil al lui gamescope.
STEAM="$HOME/.local/share/Steam"
CLIENT_DIR="$STEAM/steamrtarm64"

# Steam cauta bin/vgui2_s.dll relativ la directorul curent
cd "$CLIENT_DIR" || exit 1

# clientul ARM64 cu interfata Deck merge doar pe canalul steamdeck_publicbeta
mkdir -p "$STEAM/package"
echo steamdeck_publicbeta > "$STEAM/package/beta"

# doar Turnip (GPU-ul real), nu llvmpipe (GPU emulat pe procesor)
export VK_DRIVER_FILES=/usr/share/vulkan/icd.d/freedreno_icd.aarch64.json

# magistrala D-Bus de sistem a gazdei (in container nu exista /run/dbus); Steam in modul
# SteamOS o foloseste pentru retea, Bluetooth si baterie
export DBUS_SYSTEM_BUS_ADDRESS=unix:path=/run/host/run/dbus/system_bus_socket

# Controlere conectate dupa pornirea Steam: evenimentele udev nu ajung in containerul fara root
# (libudev ignora mesajele al caror expeditor nu e root in namespace), deci SDL urmareste direct
# /dev/input prin inotify.
export SDL_JOYSTICK_DISABLE_UDEV=1

# Panoul (DSI, fara EDID) nu are HDR real; gamescope il anunta totusi, iar Steam cere stream HDR
# (10 biti) in Remote Play. Test: SDR. Pentru a reveni, sterge linia.
export STEAM_GAMESCOPE_HDR_SUPPORTED=0

# Diagnoza unui joc: jurnal Proton in ~/proton-logs/steam-<appid>.log (exceptii, DLL-uri incarcate,
# mesajele DXVK). Oprit implicit: FEX genereaza multe exceptii, iar jurnalizarea lor scade FPS-ul.
# Pentru un singur joc e mai bine din Properties > Launch Options: PROTON_LOG=1 %command%
#export PROTON_LOG=1
export PROTON_LOG_DIR=/home/gabriel/proton-logs

# Diagnoza Remote Play: jurnal SDL3 complet (clientul de streaming foloseste SDL3 pentru video,
# audio si randare). Temporar, face logul mare.
export SDL_LOGGING='*=verbose'

# overlay-ul de performanta: mangoapp-gs ruleaza aici, in container (op8-mangoapp), iar Steam ii
# scrie nivelul ales (preset) in fisierul comun creat de steam-gamescope.sh. Variabilele sunt cele
# din ChimeraOS gamescope-session-steam. Fara mangoapp-gs compilat, Steam nu le primeste.
MANGO_CONF="/run/user/$(id -u)/mangohud.conf"
if [ -f "$MANGO_CONF" ] && [ -x /home/gabriel/games/build/mangoapp-gs ]; then
	export MANGOHUD_CONFIGFILE="$MANGO_CONF"
	export STEAM_USE_MANGOAPP=1
	export STEAM_MANGOAPP_PRESETS_SUPPORTED=1
	export STEAM_MANGOAPP_HORIZONTAL_SUPPORTED=1
	export STEAM_DISABLE_MANGOAPP_ATOM_WORKAROUND=1
	# pornit chiar inainte de "exec steam" (mai jos), ca parintele lui sa devina procesul Steam
	START_MANGOAPP=1
fi

# fara LANG, metoda de input X (XOpenIM) nu porneste
export LANG=C.UTF-8

# directorul clientului primul, ca la pocknix
export LD_LIBRARY_PATH="$CLIENT_DIR:$STEAM/lib/aarch64-linux-gnu"

# touch ca pe Steam Deck si fara controler (interfata = touch real, jocuri = click)
/home/gabriel/op8-touchmode &

[ -n "${START_MANGOAPP:-}" ] && /home/gabriel/op8-mangoapp &

# butoanele de volum: volum la eliberare, volum continuu la tinere, iar ambele deodata = butonul
# Steam (inlocuieste vechiul op8-volbtn de pe gazda; serviciul lui trebuie sa ramana dezactivat)
/home/gabriel/op8-buttons.py &

# Fara -noshaders: acelasi mecanism Steam aduce si video-urile re-codate ale jocurilor
# (STEAM_COMPAT_TRANSCODED_MEDIA_PATH). Proton nu poate decoda H.264, iar fara ele afiseaza
# barele de test TV in locul video-urilor (Poppy Playtime, Tiny Rails, 2026-10-02).
exec "$CLIENT_DIR/steam" -gamepadui -steamos3 -steampal -steamdeck -noverifyfiles
