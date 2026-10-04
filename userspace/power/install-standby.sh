#!/bin/sh
# armdeck: Steam's sleep becomes op8-standby (without kernel suspend).
# Undo: sudo rm -r /etc/systemd/system/systemd-suspend.service.d/10-op8-standby.conf \
#   /etc/polkit-1/rules.d/50-armdeck-power.rules && sudo systemctl daemon-reload
# Run: sudo sh /tmp/op8-log/install-standby.sh
set -eu
S=$(dirname "$0")
install -m 755 "$S/op8-standby" /usr/local/bin/
mkdir -p /etc/polkit-1/rules.d /etc/systemd/system/systemd-suspend.service.d
install -m 644 "$S/50-armdeck-power.rules" /etc/polkit-1/rules.d/
cat > /etc/systemd/system/systemd-suspend.service.d/10-op8-standby.conf <<'EOF'
# armdeck: a safe standby instead of kernel suspend (s2idle not tested)
[Service]
ExecStart=
ExecStart=/usr/local/bin/op8-standby
EOF
sync
systemctl daemon-reload
systemctl restart polkit
sleep 2
echo "== check"
systemctl cat systemd-suspend.service | grep ExecStart
su gabriel -s /bin/sh -c 'busctl call org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager CanSuspend'
echo "== DONE standby"
