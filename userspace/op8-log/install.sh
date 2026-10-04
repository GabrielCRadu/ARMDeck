#!/bin/sh
# armdeck, stage A, step 3: Bluetooth (bluez), rules for USB + Bluetooth controllers, op8-log.
# Run: sudo sh /tmp/op8-log/install.sh
set -eu
S=$(dirname "$0")

echo "== 0. WiFi: the profile is no longer tied to the chip's MAC address"
# After the reset of 2026-10-01 the QCA6390 chip reported a MAC address other than
# 00:03:7F:12:77:C7, and NetworkManager refused the profile tied to it. Without WiFi bluez cannot
# be installed.
for c in $(nmcli -t -f UUID,TYPE con show | grep ':802-11-wireless$' | cut -d: -f1); do
	nmcli con modify "$c" 802-11-wireless.mac-address ""
	nmcli con up "$c" || echo "WARNING: connecting to WiFi failed"
done
ip -4 -o addr show wlan0

echo "== 1. bluez (new packages only)"
apk add bluez
systemctl enable --now bluetooth

echo "== 2. udev rules for controllers (USB and Bluetooth)"
mkdir -p /etc/udev/rules.d
install -m 644 "$S/70-armdeck-gamepads.rules" /etc/udev/rules.d/
udevadm control --reload
udevadm trigger --subsystem-match=hidraw

echo "== 3. op8-log"
mkdir -p /usr/local/bin /var/log/op8 /etc/systemd/journald.conf.d
install -m 755 "$S/op8-bootreport" "$S/op8-sampler" "$S/op8-mark" /usr/local/bin/
install -m 644 "$S/op8-bootreport.service" "$S/op8-sampler.service" /etc/systemd/system/
install -m 644 "$S/50-op8-journald.conf" /etc/systemd/journald.conf.d/
systemctl restart systemd-journald
systemctl daemon-reload
systemctl enable op8-bootreport.service op8-sampler.service
systemctl start op8-sampler.service
systemctl start op8-bootreport.service

echo "== check"
systemctl is-active bluetooth op8-sampler
ls -l /var/log/op8/
grep -hE "^(PON_REASON1|WARM_RESET1|OFF_REASON|FAULT_REASON1)|float voltage|WARNING" /var/log/op8/boot-*.txt | tail -6
echo "== DONE step 3"
