#!/bin/sh
# armdeck: ascunde decodorul/encoderul video hardware Venus de userul normal.
# Clientul Steam Remote Play (facut pentru decodorul de pe Steam Frame, SM8650) crapa cand
# foloseste Venus de pe SM8250 prin V4L2; fara acces, Steam decodeaza software (FFmpeg).
# Reversibil: sterge regula si ruleaza udevadm trigger --subsystem-match=video4linux.
# Rulare: sudo sh /tmp/op8-log/hide-venus.sh
set -eu
mkdir -p /etc/udev/rules.d
cat > /etc/udev/rules.d/71-armdeck-venus.rules <<'EOF'
# armdeck: Venus (decodor/encoder video hardware) doar pentru root, vezi hide-venus.sh
SUBSYSTEM=="video4linux", ATTR{name}=="qcom-venus-decoder", MODE="0600", GROUP="root"
SUBSYSTEM=="video4linux", ATTR{name}=="qcom-venus-encoder", MODE="0600", GROUP="root"
EOF
udevadm control --reload
udevadm trigger --subsystem-match=video4linux
sleep 1
sync
for v in /sys/class/video4linux/video*; do
	case "$(cat "$v/name")" in qcom-venus-*) ls -l "/dev/$(basename "$v")" ;; esac
done
echo "== GATA Venus ascuns"
