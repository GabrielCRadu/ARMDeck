#!/bin/sh
# armdeck: test for the "warm" resets from TrustZone. Turns off UFS power management (clock
# gating, frequency scaling, automatic link hibernation) at every boot. UFS stays at its highest
# frequency; it costs a little extra power.
# Undo: sudo systemctl disable op8-ufs-nopm && sudo reboot
# Run: sudo sh /tmp/op8-log/ufs-nopm.sh
set -eu
cat > /usr/local/bin/op8-ufs-nopm <<'EOF'
#!/bin/sh
U=/sys/bus/platform/devices/1d84000.ufshc
echo 0 > "$U/clkgate_enable"
echo 0 > "$U/clkscale_enable"
echo 0 > "$U/auto_hibern8"
echo "op8-ufs-nopm: clkgate=$(cat $U/clkgate_enable) clkscale=$(cat $U/clkscale_enable) auto_hibern8=$(cat $U/auto_hibern8)"
EOF
chmod 755 /usr/local/bin/op8-ufs-nopm
cat > /etc/systemd/system/op8-ufs-nopm.service <<'EOF'
[Unit]
Description=op8: UFS without clock gating, clock scaling and auto-hibern8 (reset test)
After=local-fs.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/op8-ufs-nopm

[Install]
WantedBy=multi-user.target
EOF
sync
systemctl daemon-reload
systemctl enable --now op8-ufs-nopm.service
journalctl -u op8-ufs-nopm -n 1 --no-pager -o cat
op8-mark "UFS without clkgate/clkscale/auto_hibern8 (op8-ufs-nopm)"
sync
echo "== DONE UFS"
