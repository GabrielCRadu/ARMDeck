#!/bin/sh
# armdeck, performance audit, step 1: the settings that need no new kernel (P3, P4, P7, C6).
# Run: sudo sh /tmp/op8-log/install-tune.sh
set -eu
S=$(dirname "$0")

echo "== 1. libcap-utils (setcap/getcap, new packages only)"
apk add libcap-utils

echo "== 2. op8-tune at every boot (GPU polling 16 ms, THP madvise, CAP_SYS_NICE for gamescope)"
install -m 755 "$S/op8-tune" /usr/local/bin/
install -m 644 "$S/op8-tune.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable op8-tune.service
systemctl restart op8-tune.service
journalctl -u op8-tune -n 1 --no-pager -o cat

echo "== 3. /boot: one e2fsck check, then read-only (C6)"
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
	echo "e2fsck: exit code $rc (0 = clean, 1 = repaired, 4 or more = needs attention)"
	mount /boot
else
	echo "WARNING: /boot is busy, skipping e2fsck and remounting it read-only"
	mount -o remount,ro /boot
fi
awk '$2 == "/boot" { print "mounted: " $1 " " $4 }' /proc/mounts

echo "== DONE performance step"
