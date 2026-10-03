#!/bin/sh
# armdeck: muta tot directorul Steam pe partitia de jocuri si il monteaza (bind) la aceeasi
# cale (~/.local/share/Steam). Steam calculeaza spatiul liber pe directorul lui de instalare, nu
# pe steamapps: cu doar steamapps montat de pe partitia de jocuri (bind-steamapps.sh), Steam vedea
# partitia de sistem (13 GB, ~3 GB liberi) si putea refuza jocurile mari.
# Se ruleaza dupa bind-steamapps.sh, cu Steam oprit:
#   systemctl --user stop steam-gs; podman stop steam
#   sudo sh /tmp/op8-log/move-steam-to-games.sh
# steamapps.old (descarcari neterminate de dinainte de formatare) nu se copiaza; ramane in
# directorul vechi, care se sterge manual dupa ce Steam merge.
set -eu
die() { echo "OPRIT: $*"; exit 1; }
U=gabriel
G=/home/gabriel/games
S=/home/gabriel/.local/share/Steam
N=$G/Steam
OLD=$S.pe-rootfs

[ "$(id -u)" = 0 ] || die "ruleaza cu sudo"
grep -q " $G " /proc/mounts || die "partitia de jocuri nu e montata"
pgrep -u $U -f "$S/" >/dev/null && die "Steam ruleaza inca (systemctl --user stop steam-gs; podman stop steam)"
[ -e "$N" ] && die "$N exista deja"
[ -e "$OLD" ] && die "$OLD exista deja"
[ -d "$G/steamapps/common" ] || die "$G/steamapps nu arata ca o biblioteca Steam"
grep -q "^$G/steamapps $S/steamapps " /etc/fstab || die "lipseste linia bind steamapps din fstab (alta configuratie?)"

echo "== 1. demontez steamapps (bind)"
if grep -q " $S/steamapps " /proc/mounts; then umount "$S/steamapps"; fi
grep -q " $S/steamapps " /proc/mounts && die "steamapps inca montat"
[ -z "$(ls -A "$S/steamapps")" ] || die "$S/steamapps nu e gol dupa demontare"

echo "== 2. copiez clientul Steam pe partitia de jocuri (fara steamapps si steamapps.old)"
mkdir "$N"
chown $U:$U "$N"
find "$S" -mindepth 1 -maxdepth 1 ! -name steamapps ! -name steamapps.old -exec cp -a {} "$N/" \;
a=$(cd "$S" && find . -path ./steamapps -prune -o -path ./steamapps.old -prune -o -print | wc -l)
b=$(cd "$N" && find . -print | wc -l)
echo "intrari: sursa $a, copie $b"
[ "$a" = "$b" ] || die "numar diferit de intrari; fstab neschimbat, steamapps se remonteaza cu: mount $S/steamapps; $N se poate sterge"
sync

echo "== 3. mut biblioteca in noul director (aceeasi partitie, instantaneu)"
mv "$G/steamapps" "$N/steamapps"

echo "== 4. directorul vechi devine $OLD"
mv "$S" "$OLD"
mkdir "$S"
chown $U:$U "$S"

echo "== 5. fstab: bind pe tot directorul Steam"
cp /etc/fstab /etc/fstab.op8steam2.bak
sed -i "s#^$G/steamapps $S/steamapps .*#$N $S none bind,nofail,x-systemd.requires-mounts-for=$G 0 0#" /etc/fstab
grep -q "^$N $S " /etc/fstab || die "fstab neschimbat (copie in /etc/fstab.op8steam2.bak)"
systemctl daemon-reload
mount "$S"
sync

echo "== verificare"
grep " $S " /proc/mounts | cut -d' ' -f1-3
df -h "$S" | tail -1
ls "$S/steamapps/common"
echo "== GATA. Dupa ce Steam porneste si vede jocurile: sudo rm -rf $OLD (elibereaza ~6.4 GB pe partitia de sistem)"
