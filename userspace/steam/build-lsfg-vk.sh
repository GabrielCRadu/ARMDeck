#!/bin/bash
# armdeck: lsfg-vk 2.0.0 (Lossless Scaling's frame generation as a Vulkan layer) built for ARM64.
# Upstream (https://lsfg-vk.dev) publishes x86_64 builds only. The code has no x86-only parts: the
# frame generation shaders are read from Lossless Scaling's own lsfg-vk.dll as ready SPIR-V
# resources (no Windows code runs), so the same source builds on aarch64. Checked on 2026-10-05:
# Turnip on the Adreno 650 offers Vulkan 1.3 with vulkanMemoryModel and storage image writes
# without a format, which the shaders need.
#
# lsfg-vk is licensed CC BY-NC-ND 4.0, so ARMDeck ships none of its code or binaries: this script
# downloads the release source (checked against its sha256) and builds it unmodified on the phone.
#
# Needs Lossless Scaling (Steam app 993090) installed from its "lsfg-vk" beta branch, which puts
# lsfg-vk.dll in ~/.local/share/Steam/steamapps/common/Lossless Scaling/, where lsfg-vk looks.
#
# The layer is installed for this user only, as an EXPLICIT layer, which Vulkan loads only when a
# program asks for it. Upstream's manifest makes it an always-on implicit layer, which caused two
# problems here:
#  - every other Vulkan program sharing this home directory would load it, including gamescope on
#    the postmarketOS host (musl: forcing it there crashed the loader);
#  - implicit, it sat above MangoHud in the layer chain, so MangoHud's frame limiter (Steam's
#    Frame Limit, op8-fpslimit) counted the generated frames too: a 30 fps limit gave 15 real
#    frames plus 15 generated ones. As an explicit layer it sits below MangoHud, which then limits
#    only the real frames (30 real + 30 generated = 60).
# Turn it on per game in Steam's Launch Options, e.g.
#   VK_LOADER_LAYERS_ENABLE=VK_LAYER_LSFGVK_frame_generation LSFGVK_ENV=1 LSFGVK_MULTIPLIER=2 \
#       LSFGVK_PERFORMANCE_MODE=1 LSFGVK_FLOW_SCALE=0.5 %command%
# On the Adreno 650 it also needs TU_DEBUG=noubwc for now: lsfg-vk creates the images it shares
# between its Vulkan device and the game's with different usage flags on the two sides, so Turnip
# gives them different memory layouts (UBWC compression on one side only) and refuses the import
# (VK_ERROR_INVALID_EXTERNAL_HANDLE, black screen). See docs/gaming-stack.md TODO 32.
# Cost of the generation on this GPU, without a game: ~/.local/bin/lsfg-vk-cli benchmark -w 2400 -h 1080 -m 2
#
# Runs in the "steam" container (Fedora 44) as the normal user. Build dependency, as root in the
# container (gcc-c++ and ninja-build are already there for mangoapp):
#   podman exec -u root steam dnf install -y cmake
#   podman exec -u gabriel steam bash /home/gabriel/build-lsfg-vk.sh
# Result: ~/.local/lib/lsfg-vk/liblsfg-vk-layer.so, ~/.local/bin/lsfg-vk-cli and
# ~/.local/share/vulkan/explicit_layer.d/VkLayer_LSFGVK_frame_generation.json.
# To remove it: delete those three files.
set -euo pipefail
V=2.0.0
SHA=abb688feac00d50f9e59dabb2476998bc1d3f0290fb971407d49cba26dd44b3b
B=${B:-/home/gabriel/games/build/lsfg-vk}
PREFIX=$HOME/.local
LIB=$PREFIX/lib/lsfg-vk
MANIFEST=$PREFIX/share/vulkan/explicit_layer.d/VkLayer_LSFGVK_frame_generation.json
OLD_MANIFEST=$PREFIX/share/vulkan/implicit_layer.d/VkLayer_LSFGVK_frame_generation.json

mkdir -p "$B"
cd "$B"
[ -f "lsfg-vk-$V.tar.xz" ] || curl -fL -o "lsfg-vk-$V.tar.xz" "https://git.lsfg-vk.dev/lsfg-vk/snapshot/lsfg-vk-$V.tar.xz"
echo "$SHA  lsfg-vk-$V.tar.xz" | sha256sum -c -
rm -rf src build
mkdir src
tar -xf "lsfg-vk-$V.tar.xz" -C src --strip-components=1

echo "== configure"
cmake -S src -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
	-DLSFGVK_BUILD_LAYER=ON -DLSFGVK_BUILD_CLI=ON -DLSFGVK_BUILD_UI=OFF \
	-DLSFGVK_LAYER_LIBRARY_PATH="$LIB/liblsfg-vk-layer.so"
echo "== build (several minutes)"
cmake --build build

echo "== install"
install -D -m 755 build/lsfg-vk-layer/liblsfg-vk-layer.so "$LIB/liblsfg-vk-layer.so"
install -D -m 755 build/lsfg-vk-cli/lsfg-vk-cli "$PREFIX/bin/lsfg-vk-cli"
# upstream's manifest, with the absolute library path, installed as an explicit layer; an implicit
# copy from an earlier version of this script is removed
mkdir -p "$(dirname "$MANIFEST")"
install -m 644 build/lsfg-vk-layer/VkLayer_LSFGVK_frame_generation.json "$MANIFEST"
rm -f "$OLD_MANIFEST"
cat "$MANIFEST"
file "$LIB/liblsfg-vk-layer.so" "$PREFIX/bin/lsfg-vk-cli" 2>/dev/null || ls -l "$LIB/liblsfg-vk-layer.so" "$PREFIX/bin/lsfg-vk-cli"
DLL="$HOME/.local/share/Steam/steamapps/common/Lossless Scaling/lsfg-vk.dll"
if [ -f "$DLL" ]; then
	echo "lsfg-vk.dll found: $DLL"
else
	echo "lsfg-vk.dll NOT found yet: install Lossless Scaling from its \"lsfg-vk\" beta branch in Steam"
fi
echo "== done"
