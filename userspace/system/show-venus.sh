#!/bin/sh
# armdeck: makes the Venus hardware video decoder visible again (undoes hide-venus.sh).
# Without Venus, the ARM64 Steam Remote Play client has no decoder at all (m_pVideoDecoder null).
# Run: sudo sh /tmp/op8-log/show-venus.sh
set -eu
rm -f /etc/udev/rules.d/71-armdeck-venus.rules
udevadm control --reload
udevadm trigger --subsystem-match=video4linux
sleep 1
sync
for v in /sys/class/video4linux/video*; do
	case "$(cat "$v/name")" in qcom-venus-*) ls -l "/dev/$(basename "$v")" ;; esac
done
echo "== DONE, Venus visible"
