#!/bin/sh
# armdeck: installs a kernel package built on the PC (linux-oneplus-instantnoodle-*.apk) and
# generates /boot/boot.img. Does NOT write to partitions: boot.img goes to boot_b separately, with
# fastboot from the PC, after it is checked.
#   sudo sh install-kernel.sh /home/gabriel/linux-oneplus-instantnoodle-6.16.7-r7.apk
# Going back: the same script with the old package (e.g. -r5.apk), then its boot.img in boot_b.
# The kernel modules (/lib/modules) change together with the package: a kernel with another
# configuration cannot load the old ones (WiFi, sound). USB (SSH on 172.16.42.1) is built into the
# kernel, so it works anyway, also for going back.
set -eu
APK=${1:?usage: sudo sh install-kernel.sh <file.apk>}
[ "$(id -u)" = 0 ] || { echo "STOPPED: run it with sudo"; exit 1; }
[ -f "$APK" ] || { echo "STOPPED: $APK is missing"; exit 1; }
case "$(basename "$APK")" in linux-oneplus-instantnoodle-*.apk) ;; *) echo "STOPPED: not the kernel package"; exit 1 ;; esac

B=/home/gabriel/kernel-backup-$(date +%Y%m%d-%H%M%S)
echo "== 1. backup: /boot and /lib/modules -> $B"
mkdir -p "$B"
cp -a /boot "$B/boot"
cp -a /lib/modules "$B/modules"
apk info -v 2>/dev/null | grep "^linux-oneplus-instantnoodle-" > "$B/package.txt"
cat "$B/package.txt"

echo "== 2. /boot writable (op8-tune / fstab mount it read-only)"
mount -o remount,rw /boot
trap 'mount -o remount,ro /boot 2>/dev/null || true' EXIT

echo "== 3. apk add (also generates boot.img through mkinitfs)"
apk add --allow-untrusted "$APK"
sync

echo "== 4. check"
apk info -v 2>/dev/null | grep "^linux-oneplus-instantnoodle-"
ls -l /boot/boot.img /boot/vmlinuz /boot/initramfs
K=$(ls /lib/modules | head -1)
echo "modules: $K, vermagic: $(modinfo -F vermagic ath11k 2>/dev/null || echo ?)"
grep -E "^CONFIG_(NTSYNC|PREEMPT_DYNAMIC|LRU_GEN|SOFTLOCKUP_DETECTOR)=" /boot/config 2>/dev/null || true
sha256sum /boot/boot.img
echo "== DONE: copy /boot/boot.img to the PC and write it to boot_b with fastboot"
