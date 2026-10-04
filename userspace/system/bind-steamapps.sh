#!/bin/sh
# armdeck: the Steam library (steamapps) lives on the games partition and is bind-mounted in its
# old place, so Steam sees exactly the same path. Run: sudo sh /tmp/op8-log/bind-steamapps.sh
set -eu
die() { echo "STOPPED: $*"; exit 1; }
SRC=/home/gabriel/games/steamapps
DST=/home/gabriel/.local/share/Steam/steamapps

grep -q " /home/gabriel/games " /proc/mounts || die "the games partition is not mounted"
[ -d "$SRC/common" ] || die "$SRC does not look like a Steam library"
[ -d "$DST" ] || die "$DST is missing"
[ -z "$(ls -A "$DST")" ] || die "$DST is not empty"
grep -q " $DST " /etc/fstab && die "$DST is already in fstab"

cp /etc/fstab /etc/fstab.op8steam.bak
echo "$SRC $DST none bind,nofail,x-systemd.requires-mounts-for=/home/gabriel/games 0 0" >> /etc/fstab
systemctl daemon-reload
mount "$DST"

echo "== check"
grep " $DST " /etc/fstab
grep " $DST " /proc/mounts | cut -d' ' -f1-3
ls "$DST/common"
df -h "$DST" | tail -1
echo "== DONE Steam library"
