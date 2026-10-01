#!/bin/sh
# steamed-noodle: op8-standby cu jurnal complet + luminozitatea scriibila de grupul video
# (slider-ul de luminozitate din Steam scrie prin steamos-priv-write din container).
# Rulare: sudo sh /tmp/op8-log/install-power2.sh
set -eu
S=$(dirname "$0")
install -m 755 "$S/op8-standby" /usr/local/bin/op8-standby
mkdir -p /etc/udev/rules.d
cat > /etc/udev/rules.d/72-steamed-noodle-backlight.rules <<'EOF'
# steamed-noodle: luminozitatea ecranului scriibila de grupul video (Steam, slider-ul din meniu)
SUBSYSTEM=="backlight", ACTION=="add|change", RUN+="/bin/chgrp video /sys%p/brightness", RUN+="/bin/chmod g+w /sys%p/brightness"
EOF
udevadm control --reload
udevadm trigger --subsystem-match=backlight
sleep 1
sync
echo "== verificare"
ls -l /sys/class/backlight/*/brightness
grep -c "pas 3" /usr/local/bin/op8-standby
echo "== GATA"
