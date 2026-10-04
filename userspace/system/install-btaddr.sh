#!/bin/sh
# armdeck: the Bluetooth address at every boot (bootmac), so bluetoothd sees the controller.
# The QCA6390 chip reports the firmware's default address; the driver (btqca.c) then asks for the
# address from the device tree (local-bd-address), which is missing, and leaves the controller
# "unconfigured": hci0 exists, but bluetoothctl sees no controller and finds no devices.
# bootmac (the postmarketOS package) derives a fixed address from the serial number and sets it
# with btmgmt. Its WiFi rule is masked: the WiFi address stays as it is now (otherwise the IP
# address from the router could change).
# apk may report an error while regenerating the initramfs (/boot is mounted read-only):
# harmless, /boot and the boot partition stay untouched; the kernel is installed separately
# (install-kernel.sh).
#   sudo sh install-btaddr.sh
if ! apk info -e bootmac bootmac-systemd >/dev/null; then
	apk add bootmac bootmac-systemd
fi
apk info -e bootmac bootmac-systemd >/dev/null || { echo "bootmac did not install, stopping"; exit 1; }
set -e
ln -sf /dev/null /etc/udev/rules.d/90-bootmac-wifi.rules
udevadm control --reload
systemctl start bootmac@bluetooth.service
sleep 2
echo "== check"
ls -l /etc/udev/rules.d/90-bootmac-wifi.rules
systemctl --no-pager is-active bootmac@bluetooth.service
journalctl -b -u bootmac@bluetooth.service --no-pager | tail -5
bluetoothctl list
