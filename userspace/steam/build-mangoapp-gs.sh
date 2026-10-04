#!/bin/bash
# armdeck: mangoapp (the MangoHud performance overlay) built for gamescope 3.16.29, with two patches.
#
# 1. Frame times: gamescope 3.16.29 sends the app_frametime_ns and visible_frametime_ns fields in
#    its message to mangoapp in the opposite order from MangoHud (0.7.1 in Alpine, 0.8.x, master).
#    mangoapp then always reads "unknown" (~0) as the visible frame time, never leaves its pause
#    and the overlay does not show in Steam/Proton games (gamescope issue #2430). Here the two
#    fields are swapped to gamescope 3.16.29's order. When gamescope goes back to the old order,
#    this patch must be removed (the overlay would disappear again).
# 2. Battery: MangoHud only looks for power supplies whose name contains "BAT" (laptops: BAT0).
#    Phone fuel gauges have other names (OnePlus 8: bq27411-0), so the battery percentage, power
#    draw and time left never showed. The patch also accepts any supply whose type is "Battery",
#    except device batteries (a DualSense controller reports one), and takes the percentage and
#    the time left from the gauge's own "capacity", as Steam does.
# 3. GPU: in the rootless container /sys/class/drm has no renderD128 link, so MangoHud found no
#    GPU; and for mainline Adreno ("msm_dpu") it read neither the temperature nor the clock.
# 4. GPU load: the per-process GPU statistics (fdinfo) say "drm-driver: msm" while the device
#    driver is "msm_dpu", so they never matched and the load stayed at 0.
#
# Runs in the "steam" container (Fedora 44) as the normal user; the build dependencies are
# installed separately, as root in the container:
#   podman exec -u root steam dnf install -y gcc-c++ meson ninja-build glslang python3-mako \
#       pkgconf-pkg-config libX11-devel libxkbcommon-devel glfw-devel glew-devel dbus-devel mesa-libGL-devel \
#       libstdc++-static
#   podman exec -u gabriel steam bash /home/gabriel/build-mangoapp-gs.sh
# Result: /home/gabriel/games/build/mangoapp-gs (started by op8-mangoapp in the container).
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

# --- patch 1: frame time field order
P=src/app/mangoapp_proto.h
[ "$(grep -c 'uint64_t visible_frametime_ns;' $P)" = 1 ] || { echo "STOPPED: unexpected visible_frametime_ns in $P"; exit 1; }
[ "$(grep -c 'uint64_t app_frametime_ns;' $P)" = 1 ] || { echo "STOPPED: unexpected app_frametime_ns in $P"; exit 1; }
# swap the two declarations (the positions stay, the names are exchanged)
awk '
	/uint64_t visible_frametime_ns;/ { sub(/visible_frametime_ns;/, "app_frametime_ns; /* armdeck: gamescope 3.16.29 order */"); print; next }
	/uint64_t app_frametime_ns;/ { sub(/app_frametime_ns;/, "visible_frametime_ns;"); print; next }
	{ print }' "$P" > "$P.new"
mv "$P.new" "$P"
echo "== field order after the patch:"
grep -n -E "uint32_t pid;|frametime_ns;|fsrUpscale;|fsrSharpness;" "$P"
# check: app_frametime_ns must come right after pid
grep -A1 "uint32_t pid;" "$P" | grep -q "app_frametime_ns" || { echo "STOPPED: the order is not gamescope's"; exit 1; }

# --- patch 2: batteries not named BAT*
P=src/battery.cpp
OLD='        if (fileName.find("BAT") != std::string::npos) {'
[ "$(grep -cF "$OLD" $P)" = 1 ] || { echo "STOPPED: unexpected battery lookup in $P"; exit 1; }
python3 - "$P" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()

def sub(old, new, text=None):
    global s
    assert s.count(old) == 1, old
    s = s.replace(old, new)

# a) the system battery, whatever its name; not device batteries (controllers, headsets)
sub('        if (fileName.find("BAT") != std::string::npos) {',
    '        if (fileName.find("BAT") != std::string::npos || armdeck_is_battery(p.path())) {')
sub('void BatteryStats::numBattery() {',
    '''// armdeck: phone fuel gauges are not named BAT* (e.g. bq27411-0): accept any supply of type
// Battery, except the batteries of devices (a DualSense controller, a headset), which the kernel
// marks with scope "Device"
static bool armdeck_is_battery(const fs::path& p) {
    std::ifstream t((p / "type").string());
    std::string type, scope;
    if (!std::getline(t, type) || type != "Battery")
        return false;
    std::ifstream sc((p / "scope").string());
    return !(std::getline(sc, scope) && scope == "Device");
}

void BatteryStats::numBattery() {''')

# b) the percentage from "capacity", the gauge's own state of charge (what Steam shows); on the
#    OnePlus 8 gauge charge_now / charge_full disagree with it (81% against 25% measured)
i = s.index('float BatteryStats::getPercent()')
j = s.index('\n}\n', i)
body = s[i:j]
assert body.count('        if (fs::exists(charge_now)) {') == 1
assert body.count('        else if (fs::exists(energy_now)) {') == 1
body = body.replace('        if (fs::exists(charge_now)) {',
                    '        // armdeck: prefer the gauge\'s own percentage when it has one\n'
                    '        if (!fs::exists(capacity) && fs::exists(charge_now)) {')
body = body.replace('        else if (fs::exists(energy_now)) {',
                    '        else if (!fs::exists(capacity) && fs::exists(energy_now)) {')
s = s[:i] + body + s[j:]

# c) the time left from that same percentage of the full charge
i = s.index('float BatteryStats::getTimeRemaining()')
j = s.index('\n}\n', i)
body = s[i:j]
old = '''        if (fs::exists(charge_now)) {
            std::ifstream input(charge_now);
            std::string line;
            if (std::getline(input, line)) {
                charge += stof(line);
            }
        }'''
new = '''        if (fs::exists(syspath + "/capacity") && fs::exists(syspath + "/charge_full")) {
            // armdeck: remaining charge = the gauge's percentage of its full charge
            std::ifstream pct(syspath + "/capacity"), full(syspath + "/charge_full");
            std::string a, b;
            if (std::getline(pct, a) && std::getline(full, b))
                charge += stof(a) / 100.0f * stof(b);
        } else if (fs::exists(charge_now)) {
            std::ifstream input(charge_now);
            std::string line;
            if (std::getline(input, line)) {
                charge += stof(line);
            }
        }'''
assert body.count(old) == 1
s = s[:i] + body.replace(old, new) + s[j:]
open(p, 'w').write(s)
PY
grep -n "armdeck" "$P"

# --- patch 3: Adreno GPU stats (load, clock, temperature) from inside the container
python3 - src/gpu.cpp src/gpu_fdinfo.cpp <<'PY'
import sys
gpu, fdi = sys.argv[1], sys.argv[2]

def patch(path, pairs):
    s = open(path).read()
    for old, new in pairs:
        assert s.count(old) == 1, (path, old)
        s = s.replace(old, new)
    open(path, 'w').write(s)

# In the rootless container, /sys/class/drm lacks the renderD128 link (it exists on the host),
# so MangoHud found no GPU. The same device is reachable as /sys/dev/char/<major>:<minor>.
patch(gpu, [
    ('namespace fs = ghc::filesystem;\n',
     'namespace fs = ghc::filesystem;\n\n'
     '// armdeck: in a rootless container /sys/class/drm can miss the render node link; the same\n'
     '// device is reachable through /sys/dev/char/<major>:<minor>, taken from /dev/dri\n'
     '#include <sys/stat.h>\n#include <sys/sysmacros.h>\n'
     'static std::string armdeck_drm_sys(const std::string& node) {\n'
     '    std::string cls = "/sys/class/drm/" + node;\n'
     '    struct stat st;\n'
     '    if (fs::exists(cls) || stat(("/dev/dri/" + node).c_str(), &st) != 0)\n'
     '        return cls;\n'
     '    return "/sys/dev/char/" + std::to_string(major(st.st_rdev)) + ":" + std::to_string(minor(st.st_rdev));\n'
     '}\n'),
    ('    // Now process the sorted GPU entries\n',
     '    // armdeck: also list render nodes from /dev/dri (see armdeck_drm_sys)\n'
     '    if (fs::exists("/dev/dri"))\n'
     '        for (const auto& entry : fs::directory_iterator("/dev/dri")) {\n'
     '            std::string n = entry.path().filename().string();\n'
     '            if (n.rfind("renderD", 0) == 0 && n.length() > 7 &&\n'
     '                std::all_of(n.begin() + 7, n.end(), ::isdigit))\n'
     '                gpu_entries.insert(n);\n'
     '        }\n\n'
     '    // Now process the sorted GPU entries\n'),
    ('std::string path = "/sys/class/drm/" + node_name;',
     'std::string path = armdeck_drm_sys(node_name);'),
    ('std::string path = "/sys/class/drm/" + node + "/device/driver";',
     'std::string path = armdeck_drm_sys(node) + "/device/driver";'),
])

# Mainline Adreno shows up as "msm_dpu": MangoHud looked for the GPU temperature sensor only for
# "msm", and read no clock at all. The clock comes from the GPU's devfreq node (in Hz).
patch(fdi, [
    ('    if (module == "msm")\n        hwmon = find_hwmon_sensor_dir("gpu");',
     '    if (module == "msm" || module == "msm_dpu")  // armdeck: mainline Adreno is msm_dpu\n'
     '        hwmon = find_hwmon_sensor_dir("gpu");'),
    ('int GPU_fdinfo::get_gpu_clock()\n{\n',
     '// armdeck: Adreno clock in MHz from the GPU devfreq node (cur_freq is in Hz)\n'
     'static int armdeck_msm_gpu_clock() {\n'
     '    if (!fs::exists("/sys/class/devfreq"))\n'
     '        return 0;\n'
     '    for (const auto& e : fs::directory_iterator("/sys/class/devfreq")) {\n'
     '        if (e.path().filename().string().find(".gpu") == std::string::npos)\n'
     '            continue;\n'
     '        std::ifstream f(e.path().string() + "/cur_freq");\n'
     '        std::string s;\n'
     '        if (std::getline(f, s) && !s.empty())\n'
     '            return std::round(std::stoull(s) / 1e6);\n'
     '    }\n'
     '    return 0;\n'
     '}\n\n'
     'int GPU_fdinfo::get_gpu_clock()\n{\n'
     '    if (module == "msm_dpu")\n'
     '        return armdeck_msm_gpu_clock();\n\n'),
])
PY
grep -n "armdeck" src/gpu.cpp src/gpu_fdinfo.cpp

# --- patch 4: Adreno GPU load and memory
# MangoHud matches each process's DRM fdinfo by driver name, but the device driver is "msm_dpu"
# while fdinfo says "drm-driver: msm", so no fd ever matched and the load stayed at 0. The msm
# fdinfo also reports the memory a process holds on the GPU (drm-resident-memory).
python3 - src/gpu_fdinfo.cpp src/gpu_fdinfo.h <<'PY'
import sys
cpp, hdr = sys.argv[1], sys.argv[2]

def patch(path, old, new):
    s = open(path).read()
    assert s.count(old) == 1, (path, old)
    open(path, 'w').write(s.replace(old, new))

patch(cpp, '        if (!driver.empty() && driver == module) {\n',
      '        // armdeck: mainline Adreno: the device driver is msm_dpu, its fdinfo says "msm"\n'
      '        if (module == "msm_dpu" && driver == "msm")\n'
      '            driver = module;\n\n'
      '        if (!driver.empty() && driver == module) {\n')
patch(hdr, '            drm_engine_type = "drm-engine-gpu";\n',
      '            drm_engine_type = "drm-engine-gpu";\n'
      '            drm_memory_type = "drm-resident-memory";  // armdeck: reported by msm (kernel 6.16)\n')
PY
grep -n "armdeck" src/gpu_fdinfo.cpp src/gpu_fdinfo.h | tail -3

meson setup build --buildtype=release -Dmangoapp=true -Dmangohudctl=false -Dtests=disabled \
	-Dwith_xnvctrl=disabled -Dwith_nvml=disabled -Dwith_wayland=disabled -Dinclude_doc=false \
	-Dmangoplot=disabled -Dappend_libdir_mangohud=false
meson compile -C build mangoapp
install -m 755 "$(find build -type f -name mangoapp -perm -u+x | head -1)" "$OUT"
echo "== DONE: $OUT"
"$OUT" --help 2>&1 | head -2 || true
