#!/bin/sh
# steamed-noodle: instaleaza un pachet de kernel construit pe PC (linux-oneplus-instantnoodle-*.apk)
# si genereaza /boot/boot.img. NU scrie in partitii: boot.img se scrie in boot_b separat, cu fastboot
# de pe PC, dupa verificare.
#   sudo sh install-kernel.sh /home/gabriel/linux-oneplus-instantnoodle-6.16.7-r7.apk
# Revenire: acelasi script cu pachetul vechi (de ex. -r5.apk), apoi boot.img-ul lui in boot_b.
# Modulele kernelului (/lib/modules) se schimba odata cu pachetul: un kernel cu alta configuratie nu
# le poate incarca pe cele vechi (WiFi, sunet). USB (SSH pe 172.16.42.1) e compilat in kernel, deci
# merge oricum, inclusiv pentru revenire.
set -eu
APK=${1:?folosire: sudo sh install-kernel.sh <fisier.apk>}
[ "$(id -u)" = 0 ] || { echo "OPRIT: ruleaza cu sudo"; exit 1; }
[ -f "$APK" ] || { echo "OPRIT: lipseste $APK"; exit 1; }
case "$(basename "$APK")" in linux-oneplus-instantnoodle-*.apk) ;; *) echo "OPRIT: nu e pachetul de kernel"; exit 1 ;; esac

B=/home/gabriel/kernel-backup-$(date +%Y%m%d-%H%M%S)
echo "== 1. copie de siguranta: /boot si /lib/modules -> $B"
mkdir -p "$B"
cp -a /boot "$B/boot"
cp -a /lib/modules "$B/modules"
apk info -v 2>/dev/null | grep "^linux-oneplus-instantnoodle-" > "$B/pachet.txt"
cat "$B/pachet.txt"

echo "== 2. /boot scriibil (e montat doar citire de op8-tune / fstab)"
mount -o remount,rw /boot
trap 'mount -o remount,ro /boot 2>/dev/null || true' EXIT

echo "== 3. apk add (genereaza si boot.img prin mkinitfs)"
apk add --allow-untrusted "$APK"
sync

echo "== 4. verificare"
apk info -v 2>/dev/null | grep "^linux-oneplus-instantnoodle-"
ls -l /boot/boot.img /boot/vmlinuz /boot/initramfs
K=$(ls /lib/modules | head -1)
echo "module: $K, vermagic: $(modinfo -F vermagic ath11k 2>/dev/null || echo ?)"
grep -E "^CONFIG_(NTSYNC|PREEMPT_DYNAMIC|LRU_GEN|SOFTLOCKUP_DETECTOR)=" /boot/config 2>/dev/null || true
sha256sum /boot/boot.img
echo "== GATA: copiaza /boot/boot.img pe PC si scrie-l in boot_b cu fastboot"
