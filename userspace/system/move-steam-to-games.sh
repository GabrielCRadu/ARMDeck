#!/bin/sh
# armdeck: moves the whole Steam directory to the games partition and bind-mounts it at the same
# path (~/.local/share/Steam). Steam computes the free space on its install directory, not on
# steamapps: with only steamapps mounted from the games partition (bind-steamapps.sh), Steam saw
# the system partition (13 GB, about 3 GB free) and could refuse big games.
# Run after bind-steamapps.sh, with Steam stopped:
#   systemctl --user stop steam-gs; podman stop steam
#   sudo sh /tmp/op8-log/move-steam-to-games.sh
# steamapps.old (unfinished downloads from before the format) is not copied; it stays in the old
# directory, which is deleted by hand once Steam works.
set -eu
die() { echo "STOPPED: $*"; exit 1; }
U=gabriel
G=/home/gabriel/games
S=/home/gabriel/.local/share/Steam
N=$G/Steam
OLD=$S.pe-rootfs

[ "$(id -u)" = 0 ] || die "run it with sudo"
grep -q " $G " /proc/mounts || die "the games partition is not mounted"
pgrep -u $U -f "$S/" >/dev/null && die "Steam is still running (systemctl --user stop steam-gs; podman stop steam)"
[ -e "$N" ] && die "$N already exists"
[ -e "$OLD" ] && die "$OLD already exists"
[ -d "$G/steamapps/common" ] || die "$G/steamapps does not look like a Steam library"
grep -q "^$G/steamapps $S/steamapps " /etc/fstab || die "the steamapps bind line is missing from fstab (another setup?)"

echo "== 1. unmount steamapps (bind)"
if grep -q " $S/steamapps " /proc/mounts; then umount "$S/steamapps"; fi
grep -q " $S/steamapps " /proc/mounts && die "steamapps is still mounted"
[ -z "$(ls -A "$S/steamapps")" ] || die "$S/steamapps is not empty after unmounting"

echo "== 2. copy the Steam client to the games partition (without steamapps and steamapps.old)"
mkdir "$N"
chown $U:$U "$N"
find "$S" -mindepth 1 -maxdepth 1 ! -name steamapps ! -name steamapps.old -exec cp -a {} "$N/" \;
a=$(cd "$S" && find . -path ./steamapps -prune -o -path ./steamapps.old -prune -o -print | wc -l)
b=$(cd "$N" && find . -print | wc -l)
echo "entries: source $a, copy $b"
[ "$a" = "$b" ] || die "different number of entries; fstab unchanged, remount steamapps with: mount $S/steamapps; $N can be deleted"
sync

echo "== 3. move the library into the new directory (same partition, instant)"
mv "$G/steamapps" "$N/steamapps"

echo "== 4. the old directory becomes $OLD"
mv "$S" "$OLD"
mkdir "$S"
chown $U:$U "$S"

echo "== 5. fstab: bind the whole Steam directory"
cp /etc/fstab /etc/fstab.op8steam2.bak
sed -i "s#^$G/steamapps $S/steamapps .*#$N $S none bind,nofail,x-systemd.requires-mounts-for=$G 0 0#" /etc/fstab
grep -q "^$N $S " /etc/fstab || die "fstab unchanged (copy in /etc/fstab.op8steam2.bak)"
systemctl daemon-reload
mount "$S"
sync

echo "== check"
grep " $S " /proc/mounts | cut -d' ' -f1-3
df -h "$S" | tail -1
ls "$S/steamapps/common"
echo "== DONE. Once Steam starts and sees the games: sudo rm -rf $OLD (frees about 6.4 GB on the system partition)"
