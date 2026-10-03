#!/bin/sh
# armdeck, etapa A, pasul 2: controlere pentru Steam si SSH pe WiFi doar de la PC.
set -eu
# IP-ul PC-ului din reteaua WiFi (singurul de la care SSH-ul pe WiFi e permis)
PC_IP=${1:?folosire: sudo sh stageA2.sh <IP-ul PC-ului>}

# 1. Controlere: Steam (din container, ca userul gabriel, grupul input) trebuie sa poata
#    deschide hidraw-ul controlerelor si sa creeze controlere virtuale prin uinput.
#    Pe SteamOS face asta steam-devices cu TAG uaccess, care cere o sesiune pe ecran; aici
#    nu exista, deci folosim grupul input.
mkdir -p /etc/udev/rules.d
cat > /etc/udev/rules.d/70-armdeck-gamepads.rules <<'EOF'
# armdeck: acces pentru grupul input la controlere (hidraw) si la uinput
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

# 2. SSH pe WiFi doar de la PC ($PC_IP); restul retelei WiFi ramane blocat (audit S2)
#    Regula veche se pastreaza si se pune la loc daca cea noua nu trece verificarea.
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
	echo "EROARE: regula noua nu e valida, am pus-o la loc pe cea veche"
	exit 1
fi
systemctl restart nftables

echo "== verificare"
ls -l /dev/uinput
cat /etc/udev/rules.d/70-armdeck-gamepads.rules | grep -c MODE
nft list chain inet filter input | grep -E "dport 22"
echo "== GATA pasul 2"
