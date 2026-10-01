#!/bin/sh
# steamed-noodle: formateaza partitia Android "userdata" (219 GiB) ca ext4 pentru jocuri si o
# monteaza in /home/gabriel/games. STERGE DEFINITIV datele Android vechi din userdata.
# Android ramane reinstalabil prin MSM (rescrie tot, inclusiv userdata).
# Rulare: sudo sh /tmp/op8-log/format-games.sh
set -eu
die() { echo "OPRIT: $*"; exit 1; }

P=/dev/disk/by-partlabel/userdata
MNT=/home/gabriel/games

# 1. verificari: partitia corecta, unica, marimea asteptata, nefolosita
[ "$(ls /dev/disk/by-partlabel/ | grep -cx userdata)" = 1 ] || die "nu exista exact o partitie userdata"
[ -b "$P" ] || die "$P nu e dispozitiv bloc"
DEV=$(readlink -f "$P")
[ "$DEV" = /dev/sda23 ] || die "userdata e $DEV, nu /dev/sda23 cum am verificat"
B=$(basename "$DEV")
grep -qx "PARTNAME=userdata" "/sys/class/block/$B/uevent" || die "PARTNAME nu e userdata"
GIB=$(( $(cat "/sys/class/block/$B/size") * 512 / 1073741824 ))
[ "$GIB" -ge 210 ] && [ "$GIB" -le 230 ] || die "marime neasteptata: $GIB GiB"
[ "$(cat "/sys/class/block/$B/ro")" = 0 ] || die "partitia e read-only"
[ -z "$(ls "/sys/class/block/$B/holders")" ] || die "partitia e folosita de alt dispozitiv"
grep -q "^$DEV " /proc/mounts && die "partitia e montata"
grep -q "$MNT" /etc/fstab && die "$MNT exista deja in fstab"

echo "Partitia: $DEV (PARTNAME=userdata, $GIB GiB, nemontata, nefolosita)"
echo "Se va formata ext4 cu eticheta op8games. Datele Android vechi se pierd definitiv."
printf 'Scrie FORMAT ca sa continui: '
read -r ans
[ "$ans" = FORMAT ] || die "anulat, nu s-a scris nimic"

# 2. formatare (mke2fs face si TRIM pe toata partitia, normal pe UFS)
mkfs.ext4 -F -L op8games -m 1 "$DEV"
UUID=$(blkid -s UUID -o value "$DEV")
[ -n "$UUID" ] || die "nu gasesc UUID-ul noului sistem de fisiere"

# 3. montare permanenta; nofail = daca lipseste vreodata, telefonul porneste normal fara ea
cp /etc/fstab /etc/fstab.op8games.bak
echo "UUID=$UUID $MNT ext4 defaults,noatime,nofail,x-systemd.device-timeout=10s 0 2" >> /etc/fstab
systemctl daemon-reload
mkdir -p "$MNT"
mount "$MNT"
chown gabriel:gabriel "$MNT"
mkdir -p "$MNT/SteamLibrary"
chown gabriel:gabriel "$MNT/SteamLibrary"

echo "== verificare"
grep " $MNT " /etc/fstab
df -h "$MNT" | tail -1
ls -la "$MNT"
echo "== GATA formatare"
