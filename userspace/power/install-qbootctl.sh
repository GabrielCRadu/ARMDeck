#!/bin/sh
# armdeck: marks the current slot (b) as "successful" at every boot, as Android does.
# Without it the bootloader lowers the retry counter at every boot; after about 7 boots the slot
# becomes "unbootable" and the screen "current image (boot/recovery) have been destroyed" appears
# (happened on 2026-10-02, fixed with fastboot --set-active=b).
# qbootctl + qbootctl-systemd: the same as in postmarketOS (qbootctl -m at multi-user.target).
# Run: sudo sh /tmp/op8-log/install-qbootctl.sh
set -eu
apk add qbootctl
echo "== before"
qbootctl 2>&1 || true
systemctl enable qbootctl.service
qbootctl -m
sync
echo "== after"
qbootctl 2>&1 || true
systemctl is-enabled qbootctl.service
echo "== DONE qbootctl"
