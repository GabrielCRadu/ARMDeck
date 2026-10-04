#!/bin/sh
# armdeck, stage A, step 2: controllers for Steam, and SSH over WiFi from the PC only.
set -eu
# the PC's IP address on the WiFi network (the only one allowed to use SSH over WiFi)
PC_IP=${1:?usage: sudo sh stageA2.sh <the PC IP address>}

# 1. Controllers: Steam (in the container, as the user gabriel, input group) must be able to
#    open the controllers' hidraw devices and create virtual controllers through uinput.
#    On SteamOS steam-devices does this with TAG uaccess, which needs a session on the screen;
#    there is none here, so the input group is used.
mkdir -p /etc/udev/rules.d
cat > /etc/udev/rules.d/70-armdeck-gamepads.rules <<'EOF'
# armdeck: access for the input group to controllers (hidraw) and to uinput
# GameSir (Zikway), Valve, Microsoft, Sony, Nintendo, 8BitDo
KERNEL=="hidraw*", ATTRS{idVendor}=="3537", MODE="0660", GROUP="input"
KERNEL=="hidraw*", ATTRS{idVendor}=="28de", MODE="0660", GROUP="input"
KERNEL=="hidraw*", ATTRS{idVendor}=="045e", MODE="0660", GROUP="input"
KERNEL=="hidraw*", ATTRS{idVendor}=="054c", MODE="0660", GROUP="input"
KERNEL=="hidraw*", ATTRS{idVendor}=="057e", MODE="0660", GROUP="input"
KERNEL=="hidraw*", ATTRS{idVendor}=="2dc8", MODE="0660", GROUP="input"
KERNEL=="uinput", SUBSYSTEM=="misc", MODE="0660", GROUP="input", OPTIONS+="static_node=uinput"
EOF
udevadm control --reload
udevadm trigger --subsystem-match=misc --subsystem-match=hidraw

# 2. SSH over WiFi from the PC only ($PC_IP); the rest of the WiFi network stays blocked (audit S2)
#    The old rule is kept and put back if the new one fails the check.
cp /etc/nftables.d/40_ssh_usb_only.nft /root/40_ssh_usb_only.nft.bak
cat > /etc/nftables.d/40_ssh_usb_only.nft <<EOF
table inet filter {
	chain input {
		iifname "wlan*" ip saddr != $PC_IP tcp dport 22 drop comment "SSH only over USB or from the PC (armdeck security-audit S2)"
		iifname "wlan*" meta nfproto ipv6 tcp dport 22 drop comment "no SSH over IPv6 WiFi"
	}
}
EOF
if ! nft -c -f /etc/nftables.nft; then
	cp /root/40_ssh_usb_only.nft.bak /etc/nftables.d/40_ssh_usb_only.nft
	echo "ERROR: the new rule is not valid, the old one is back in place"
	exit 1
fi
systemctl restart nftables

echo "== check"
ls -l /dev/uinput
cat /etc/udev/rules.d/70-armdeck-gamepads.rules | grep -c MODE
nft list chain inet filter input | grep -E "dport 22"
echo "== DONE step 2"
