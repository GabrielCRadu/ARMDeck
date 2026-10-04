#!/bin/sh
# armdeck: op8-standby with a full log + the brightness writable by the video group
# (Steam's brightness slider writes through steamos-priv-write in the container).
# Run: sudo sh /tmp/op8-log/install-power2.sh
set -eu
S=$(dirname "$0")
install -m 755 "$S/op8-standby" /usr/local/bin/op8-standby
mkdir -p /etc/udev/rules.d
cat > /etc/udev/rules.d/72-armdeck-backlight.rules <<'EOF'
# armdeck: the screen brightness writable by the video group (Steam, the menu slider)
SUBSYSTEM=="backlight", ACTION=="add|change", RUN+="/bin/chgrp video /sys%p/brightness", RUN+="/bin/chmod g+w /sys%p/brightness"
EOF
udevadm control --reload
udevadm trigger --subsystem-match=backlight
sleep 1
sync
echo "== check"
ls -l /sys/class/backlight/*/brightness
grep -c "step 3" /usr/local/bin/op8-standby
echo "== DONE"
