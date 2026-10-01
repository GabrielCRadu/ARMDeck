#!/bin/sh
# steamed-noodle: biblioteca Steam (steamapps) sta pe partitia de jocuri si e montata (bind) in
# locul ei vechi, ca Steam sa vada exact aceeasi cale. Rulare: sudo sh /tmp/op8-log/bind-steamapps.sh
set -eu
die() { echo "OPRIT: $*"; exit 1; }
SRC=/home/gabriel/games/steamapps
DST=/home/gabriel/.local/share/Steam/steamapps

grep -q " /home/gabriel/games " /proc/mounts || die "partitia de jocuri nu e montata"
[ -d "$SRC/common" ] || die "$SRC nu arata ca o biblioteca Steam"
[ -d "$DST" ] || die "$DST lipseste"
[ -z "$(ls -A "$DST")" ] || die "$DST nu e gol"
grep -q " $DST " /etc/fstab && die "$DST exista deja in fstab"

cp /etc/fstab /etc/fstab.op8steam.bak
echo "$SRC $DST none bind,nofail,x-systemd.requires-mounts-for=/home/gabriel/games 0 0" >> /etc/fstab
systemctl daemon-reload
mount "$DST"

echo "== verificare"
grep " $DST " /etc/fstab
grep " $DST " /proc/mounts | cut -d' ' -f1-3
ls "$DST/common"
df -h "$DST" | tail -1
echo "== GATA biblioteca Steam"
