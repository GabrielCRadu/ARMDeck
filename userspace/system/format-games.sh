#!/bin/sh
# armdeck: formats the Android "userdata" partition (219 GiB) as ext4 for games and mounts it at
# /home/gabriel/games. PERMANENTLY ERASES the old Android data in userdata.
# Android can still be reinstalled with MSM (it rewrites everything, userdata included).
# Run: sudo sh /tmp/op8-log/format-games.sh
set -eu
die() { echo "STOPPED: $*"; exit 1; }

P=/dev/disk/by-partlabel/userdata
MNT=/home/gabriel/games

# 1. checks: the right partition, only one, the expected size, not in use
[ "$(ls /dev/disk/by-partlabel/ | grep -cx userdata)" = 1 ] || die "there is not exactly one userdata partition"
[ -b "$P" ] || die "$P is not a block device"
DEV=$(readlink -f "$P")
[ "$DEV" = /dev/sda23 ] || die "userdata is $DEV, not /dev/sda23 as checked"
B=$(basename "$DEV")
grep -qx "PARTNAME=userdata" "/sys/class/block/$B/uevent" || die "PARTNAME is not userdata"
GIB=$(( $(cat "/sys/class/block/$B/size") * 512 / 1073741824 ))
[ "$GIB" -ge 210 ] && [ "$GIB" -le 230 ] || die "unexpected size: $GIB GiB"
[ "$(cat "/sys/class/block/$B/ro")" = 0 ] || die "the partition is read-only"
[ -z "$(ls "/sys/class/block/$B/holders")" ] || die "the partition is used by another device"
grep -q "^$DEV " /proc/mounts && die "the partition is mounted"
grep -q "$MNT" /etc/fstab && die "$MNT is already in fstab"

echo "Partition: $DEV (PARTNAME=userdata, $GIB GiB, not mounted, not in use)"
echo "It will be formatted as ext4 with the label op8games. The old Android data is lost for good."
printf 'Type FORMAT to continue: '
read -r ans
[ "$ans" = FORMAT ] || die "cancelled, nothing was written"

# 2. format (mke2fs also TRIMs the whole partition, normal on UFS)
mkfs.ext4 -F -L op8games -m 1 "$DEV"
UUID=$(blkid -s UUID -o value "$DEV")
[ -n "$UUID" ] || die "cannot find the UUID of the new file system"

# 3. permanent mount; nofail = if it is ever missing, the phone still boots normally without it
cp /etc/fstab /etc/fstab.op8games.bak
echo "UUID=$UUID $MNT ext4 defaults,noatime,nofail,x-systemd.device-timeout=10s 0 2" >> /etc/fstab
systemctl daemon-reload
mkdir -p "$MNT"
mount "$MNT"
chown gabriel:gabriel "$MNT"
mkdir -p "$MNT/SteamLibrary"
chown gabriel:gabriel "$MNT/SteamLibrary"

echo "== check"
grep " $MNT " /etc/fstab
df -h "$MNT" | tail -1
ls -la "$MNT"
echo "== DONE formatting"
