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

# Diagnoza Remote Play: jurnal SDL3 complet (clientul de streaming foloseste SDL3 pentru video,
# audio si randare). Temporar, face logul mare.
export SDL_LOGGING='*=verbose'

# fara LANG, metoda de input X (XOpenIM) nu porneste
export LANG=C.UTF-8

# directorul clientului primul, ca la pocknix
export LD_LIBRARY_PATH="$CLIENT_DIR:$STEAM/lib/aarch64-linux-gnu"

# touch ca pe Steam Deck si fara controler (interfata = touch real, jocuri = click)
/home/gabriel/op8-touchmode &

exec "$CLIENT_DIR/steam" -gamepadui -steamos3 -steampal -steamdeck -noverifyfiles -noshaders
