#!/bin/bash
# op8-log on the PC (armdeck): the phone's live journal, the op8-sampler samples and a ping every
# second, with the PC's clock, in D:\op8-logs\<date>\. Does not depend on the phone's disk.
# The gap between the last sign of life and the return tells the cause of a reset:
# ~120 s frozen = kernel panic (kernel.panic=120), less = watchdog after a hang.
# Usage (Git Bash): bash /d/op8-logs/op8-live.sh [ip]
#   default ip 172.16.42.1 (USB cable); with the phone in the controller: the phone's WiFi IP
H=${1:-172.16.42.1}
OUT=/d/op8-logs/$(date +%Y%m%d-%H%M%S)
mkdir -p "$OUT"
# HostKeyAlias: the same checked phone key, over USB or over WiFi
SSH=(ssh -i ~/.ssh/op8_pmos -o HostKeyAlias=172.16.42.1 -o BatchMode=yes -o ConnectTimeout=5
	-o ServerAliveInterval=2 -o ServerAliveCountMax=2 "gabriel@$H")
echo "log in $OUT (Ctrl+C stops everything)"
trap 'kill 0' EXIT

# a ping every second (the Windows ping; "TTL=" appears only on a real reply)
( while :; do
	if ping -n 1 -w 800 "$H" 2>/dev/null | grep -q "TTL="; then s=ok; else s=FAIL; fi
	echo "$(date +%H:%M:%S) $s"
	sleep 1
done ) > "$OUT/ping.log" &

# the full journal (kernel + services), reconnecting after a reset
( while :; do
	echo "=== connect $(date +%H:%M:%S)"
	"${SSH[@]}" 'journalctl -f -n 30 -o short-monotonic'
	sleep 2
done ) > "$OUT/journal.log" 2>&1 &

# the op8-sampler samples of the current boot
( while :; do
	echo "=== connect $(date +%H:%M:%S)"
	"${SSH[@]}" 'tail -n 1 -F /var/log/op8/current.csv'
	sleep 2
done ) > "$OUT/samples.csv" 2>&1 &

wait
