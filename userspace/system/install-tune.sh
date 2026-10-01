#!/bin/sh
# steamed-noodle, audit de performanta, pasul 1: setarile fara kernel nou (P3, P4, P7, C6).
# Rulare: sudo sh /tmp/op8-log/install-tune.sh
set -eu
S=$(dirname "$0")

echo "== 1. libcap-utils (setcap/getcap, doar pachete noi)"
apk add libcap-utils

echo "== 2. op8-tune la fiecare pornire (polling GPU 16 ms, THP madvise, CAP_SYS_NICE gamescope)"
install -m 755 "$S/op8-tune" /usr/local/bin/
install -m 644 "$S/op8-tune.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable op8-tune.service
systemctl restart op8-tune.service
journalctl -u op8-tune -n 1 --no-pager -o cat

echo "== 3. /boot: o verificare e2fsck si apoi doar citire (C6)"
cp /etc/fstab /etc/fstab.op8.bak
awk 'BEGIN { OFS = " " }
	$2 == "/boot" && $4 !~ /(^|,)ro(,|$)/ { $4 = "ro," $4 }
	{ print }' /etc/fstab.op8.bak > /etc/fstab
grep " /boot " /etc/fstab
systemctl daemon-reload
DEV=$(awk '$2 == "/boot" { print $1 }' /proc/mounts)
if umount /boot; then
	rc=0
	e2fsck -p "$DEV" || rc=$?
	echo "e2fsck: cod $rc (0 = curat, 1 = reparat, 4 sau mai mare = are nevoie de atentie)"
	mount /boot
else
	echo "ATENTIE: /boot e ocupat, sar peste e2fsck si il remontez doar pentru citire"
	mount -o remount,ro /boot
fi
awk '$2 == "/boot" { print "montat: " $1 " " $4 }' /proc/mounts

echo "== GATA pasul de performanta"
