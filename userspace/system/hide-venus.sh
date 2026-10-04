#!/bin/sh
# armdeck: hides the Venus hardware video decoder/encoder from the normal user.
# The Steam Remote Play client (made for the decoder on Steam Frame, SM8650) crashes when it uses
# Venus on SM8250 through V4L2; without access, Steam decodes in software (FFmpeg).
# Reversible: delete the rule and run udevadm trigger --subsystem-match=video4linux.
# Run: sudo sh /tmp/op8-log/hide-venus.sh
set -eu
mkdir -p /etc/udev/rules.d
cat > /etc/udev/rules.d/71-armdeck-venus.rules <<'EOF'
# armdeck: Venus (hardware video decoder/encoder) for root only, see hide-venus.sh
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
echo "== DONE, Venus hidden"
