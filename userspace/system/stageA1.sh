#!/bin/sh
# armdeck, etapa A, pasul 1: pachetele pentru test (GPU, gamescope, containere).
# Doar adauga pachete noi. Pe telefon nu se ruleaza niciodata apk upgrade --prune / --available.
set -eu

apk add podman distrobox gamescope mesa-vulkan-freedreno vulkan-tools fuse-overlayfs shadow-subids

# ID-uri subordonate pentru containere fara root (podman rootless)
for f in /etc/subuid /etc/subgid; do
	grep -q '^gabriel:' "$f" 2>/dev/null || echo 'gabriel:100000:65536' >> "$f"
done

# grupul input: gamescope pornit din SSH citeste direct touchscreen-ul si controlerele
addgroup gabriel input

echo "== verificare"
grep -E '^(input|video):' /etc/group
cat /etc/subuid /etc/subgid
apk info -e podman distrobox gamescope mesa-vulkan-freedreno vulkan-tools fuse-overlayfs shadow-subids
df -h /
echo "== GATA pasul 1"
