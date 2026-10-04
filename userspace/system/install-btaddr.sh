#!/bin/sh
# armdeck: adresa Bluetooth la fiecare pornire (bootmac), ca bluetoothd sa vada controlerul.
# Cipul QCA6390 raporteaza adresa implicita din firmware; driverul (btqca.c) cere atunci adresa
# din device tree (local-bd-address), care lipseste, si lasa controlerul "neconfigurat": hci0
# exista, dar bluetoothctl nu vede niciun controler si nu gaseste dispozitive.
# bootmac (pachetul postmarketOS) calculeaza o adresa fixa din numarul de serie si o seteaza cu
# btmgmt. Regula lui pentru WiFi e mascata: adresa WiFi ramane cea de acum (altfel se poate
# schimba IP-ul primit de la router).
# apk poate raporta o eroare la regenerarea initramfs (/boot e montat doar citire): inofensiv,
# /boot si partitia de boot raman neatinse; kernelul se instaleaza separat (install-kernel.sh).
#   sudo sh install-btaddr.sh
if ! apk info -e bootmac bootmac-systemd >/dev/null; then
	apk add bootmac bootmac-systemd
fi
apk info -e bootmac bootmac-systemd >/dev/null || { echo "bootmac nu s-a instalat, opresc"; exit 1; }
set -e
ln -sf /dev/null /etc/udev/rules.d/90-bootmac-wifi.rules
udevadm control --reload
systemctl start bootmac@bluetooth.service
sleep 2
echo "== verificare"
ls -l /etc/udev/rules.d/90-bootmac-wifi.rules
systemctl --no-pager is-active bootmac@bluetooth.service
journalctl -b -u bootmac@bluetooth.service --no-pager | tail -5
bluetoothctl list
