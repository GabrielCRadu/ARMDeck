#!/bin/sh
# steamed-noodle: face din nou vizibil decodorul video hardware Venus (anuleaza hide-venus.sh).
# Fara Venus, clientul Steam Remote Play ARM64 nu are decodor deloc (m_pVideoDecoder nul).
# Rulare: sudo sh /tmp/op8-log/show-venus.sh
set -eu
rm -f /etc/udev/rules.d/71-steamed-noodle-venus.rules
udevadm control --reload
udevadm trigger --subsystem-match=video4linux
sleep 1
sync
for v in /sys/class/video4linux/video*; do
	case "$(cat "$v/name")" in qcom-venus-*) ls -l "/dev/$(basename "$v")" ;; esac
done
echo "== GATA Venus vizibil"
