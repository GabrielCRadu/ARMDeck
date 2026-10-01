#!/bin/bash
# op8-log pe PC (steamed-noodle): jurnalul telefonului live, esantioanele op8-sampler si un ping
# la fiecare secunda, cu ora PC-ului, in D:\op8-logs\<data>\. Nu depinde de discul telefonului.
# Pauza dintre ultimul semn de viata si revenire spune cauza unui reset:
# ~120 s de inghet = kernel panic (kernel.panic=120), mai putin = watchdog dupa o blocare.
# Folosire (Git Bash): bash /d/op8-logs/op8-live.sh [ip]
#   ip implicit 172.16.42.1 (cablu USB); cu telefonul in controler: IP-ul WiFi al telefonului
H=${1:-172.16.42.1}
OUT=/d/op8-logs/$(date +%Y%m%d-%H%M%S)
mkdir -p "$OUT"
# HostKeyAlias: aceeasi cheie de telefon verificata, fie pe USB, fie pe WiFi
SSH=(ssh -i ~/.ssh/op8_pmos -o HostKeyAlias=172.16.42.1 -o BatchMode=yes -o ConnectTimeout=5
	-o ServerAliveInterval=2 -o ServerAliveCountMax=2 "gabriel@$H")
echo "log in $OUT (Ctrl+C opreste tot)"
trap 'kill 0' EXIT

# ping la fiecare secunda (ping-ul Windows; "TTL=" apare doar la un raspuns real)
( while :; do
	if ping -n 1 -w 800 "$H" 2>/dev/null | grep -q "TTL="; then s=ok; else s=FAIL; fi
	echo "$(date +%H:%M:%S) $s"
	sleep 1
done ) > "$OUT/ping.log" &

# jurnalul complet (kernel + servicii), cu reconectare dupa reset
( while :; do
	echo "=== conectare $(date +%H:%M:%S)"
	"${SSH[@]}" 'journalctl -f -n 30 -o short-monotonic'
	sleep 2
done ) > "$OUT/journal.log" 2>&1 &

# esantioanele op8-sampler din pornirea curenta
( while :; do
	echo "=== conectare $(date +%H:%M:%S)"
	"${SSH[@]}" 'tail -n 1 -F /var/log/op8/current.csv'
	sleep 2
done ) > "$OUT/samples.csv" 2>&1 &

wait
