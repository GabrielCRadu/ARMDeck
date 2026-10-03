#!/bin/sh
# armdeck, etapa A, pasul 3: Bluetooth (bluez), reguli controlere USB + Bluetooth, op8-log.
# Rulare: sudo sh /tmp/op8-log/install.sh
set -eu
S=$(dirname "$0")

echo "== 0. WiFi: profilul nu mai e legat de adresa MAC a cipului"
# Dupa resetul din 2026-10-01 cipul QCA6390 a raportat alta adresa MAC decat 00:03:7F:12:77:C7,
# iar NetworkManager refuza profilul legat de ea. Fara WiFi nu se poate instala bluez.
for c in $(nmcli -t -f UUID,TYPE con show | grep ':802-11-wireless$' | cut -d: -f1); do
	nmcli con modify "$c" 802-11-wireless.mac-address ""
	nmcli con up "$c" || echo "ATENTIE: conectarea la WiFi a esuat"
done
ip -4 -o addr show wlan0

echo "== 1. bluez (doar pachete noi)"
apk add bluez
systemctl enable --now bluetooth

echo "== 2. reguli udev pentru controlere (USB si Bluetooth)"
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

echo "== verificare"
systemctl is-active bluetooth op8-sampler
ls -l /var/log/op8/
grep -hE "^(PON_REASON1|WARM_RESET1|OFF_REASON|FAULT_REASON1)|tensiune maxima|ATENTIE" /var/log/op8/boot-*.txt | tail -6
echo "== GATA pasul 3"
