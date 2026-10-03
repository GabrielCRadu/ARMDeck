#!/bin/sh
# armdeck: marcheaza slotul curent (b) ca "successful" la fiecare pornire, ca pe Android.
# Fara asta, bootloader-ul scade contorul de incercari la fiecare boot; dupa ~7 porniri slotul
# devine "unbootable" si apare ecranul "current image (boot/recovery) have been destroyed"
# (s-a intamplat pe 2026-10-02, reparat cu fastboot --set-active=b).
# qbootctl + qbootctl-systemd: aceleasi ca in postmarketOS (qbootctl -m la multi-user.target).
# Rulare: sudo sh /tmp/op8-log/install-qbootctl.sh
set -eu
apk add qbootctl
echo "== inainte"
qbootctl 2>&1 || true
systemctl enable qbootctl.service
qbootctl -m
sync
echo "== dupa"
qbootctl 2>&1 || true
systemctl is-enabled qbootctl.service
echo "== GATA qbootctl"
