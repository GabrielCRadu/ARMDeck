#!/bin/bash
# steamed-noodle: mangoapp (overlay-ul de performanta MangoHud) compilat pentru gamescope 3.16.29.
#
# De ce: gamescope 3.16.29 trimite in mesajul catre mangoapp campurile app_frametime_ns si
# visible_frametime_ns in ordine inversa fata de MangoHud (0.7.1 din Alpine, 0.8.x, master).
# mangoapp citeste atunci mereu "necunoscut" (~0) ca timp de cadru vizibil, nu iese niciodata din
# pauza si overlay-ul nu apare in jocurile Steam/Proton (gamescope issue #2430). Aici se compileaza
# MangoHud v0.8.4 cu cele doua campuri in ordinea din gamescope 3.16.29 (src/mangoapp.cpp).
# Cand gamescope revine la ordinea veche, patch-ul trebuie scos (overlay-ul ar disparea din nou).
#
# Ruleaza in containerul "steam" (Fedora 44), ca userul normal; dependentele de compilare se
# instaleaza separat, ca root in container:
#   podman exec -u root steam dnf install -y gcc-c++ meson ninja-build glslang python3-mako \
#       pkgconf-pkg-config libX11-devel libxkbcommon-devel glfw-devel glew-devel dbus-devel mesa-libGL-devel \
#       libstdc++-static
#   podman exec -u gabriel steam bash /home/gabriel/build-mangoapp-gs.sh
# Rezultat: /home/gabriel/games/build/mangoapp-gs (pornit de op8-mangoapp din container).
set -euo pipefail
V=0.8.4
SHA=bbe5a2b976313c53f21dc24b98bbed03226589460a0cce20d923cb2c36c9d8b0
B=/home/gabriel/games/build/mangohud
OUT=/home/gabriel/games/build/mangoapp-gs
T=MangoHud-v$V-Source.tar.xz

mkdir -p "$B"
cd "$B"
[ -f "$T" ] || curl -fL --retry 3 -o "$T" "https://github.com/flightlessmango/MangoHud/releases/download/v$V/$T"
echo "$SHA  $T" | sha256sum -c -
rm -rf src
mkdir src
tar -xf "$T" -C src --strip-components=1
cd src

P=src/app/mangoapp_proto.h
[ "$(grep -c 'uint64_t visible_frametime_ns;' $P)" = 1 ] || { echo "OPRIT: visible_frametime_ns neasteptat in $P"; exit 1; }
[ "$(grep -c 'uint64_t app_frametime_ns;' $P)" = 1 ] || { echo "OPRIT: app_frametime_ns neasteptat in $P"; exit 1; }
# schimba intre ele cele doua declaratii (pozitiile raman, numele se inverseaza)
awk '
	/uint64_t visible_frametime_ns;/ { sub(/visible_frametime_ns;/, "app_frametime_ns; /* steamed-noodle: ordinea din gamescope 3.16.29 */"); print; next }
	/uint64_t app_frametime_ns;/ { sub(/app_frametime_ns;/, "visible_frametime_ns;"); print; next }
	{ print }' "$P" > "$P.new"
mv "$P.new" "$P"
echo "== ordinea dupa patch:"
grep -n -E "uint32_t pid;|frametime_ns;|fsrUpscale;|fsrSharpness;" "$P"
# verificare: dupa pid trebuie sa vina app_frametime_ns, iar visible_frametime_ns dupa fsrSharpness
grep -A1 "uint32_t pid;" "$P" | grep -q "app_frametime_ns" || { echo "OPRIT: ordinea nu e cea din gamescope"; exit 1; }
grep -A1 "fsrSharpness;" "$P" | grep -q -E "visible_frametime_ns|For debugging" || true

meson setup build --buildtype=release -Dmangoapp=true -Dmangohudctl=false -Dtests=disabled \
	-Dwith_xnvctrl=disabled -Dwith_nvml=disabled -Dwith_wayland=disabled -Dinclude_doc=false \
	-Dmangoplot=disabled -Dappend_libdir_mangohud=false
meson compile -C build mangoapp
install -m 755 "$(find build -type f -name mangoapp -perm -u+x | head -1)" "$OUT"
echo "== GATA: $OUT"
"$OUT" --help 2>&1 | head -2 || true
