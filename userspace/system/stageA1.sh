#!/bin/sh
# armdeck, stage A, step 1: the packages for the test (GPU, gamescope, containers).
# Only adds new packages. Never run apk upgrade --prune / --available on the phone.
set -eu

apk add podman distrobox gamescope mesa-vulkan-freedreno vulkan-tools fuse-overlayfs shadow-subids

# subordinate IDs for rootless containers (rootless podman)
for f in /etc/subuid /etc/subgid; do
	grep -q '^gabriel:' "$f" 2>/dev/null || echo 'gabriel:100000:65536' >> "$f"
done

# the input group: gamescope started from SSH reads the touchscreen and the controllers directly
addgroup gabriel input

echo "== check"
grep -E '^(input|video):' /etc/group
cat /etc/subuid /etc/subgid
apk info -e podman distrobox gamescope mesa-vulkan-freedreno vulkan-tools fuse-overlayfs shadow-subids
df -h /
echo "== DONE step 1"
