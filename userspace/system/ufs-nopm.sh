#!/bin/sh
# steamed-noodle: test pentru resetarile "warm" din TrustZone. Dezactiveaza managementul de energie
# al UFS (oprirea ceasului, schimbarea frecventei, hibernarea automata a legaturii) la fiecare
# pornire. UFS ramane la frecventa maxima; costa putin consum in plus.
# Anulare: sudo systemctl disable op8-ufs-nopm && sudo reboot
# Rulare: sudo sh /tmp/op8-log/ufs-nopm.sh
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
Description=op8: UFS fara clock gating, clock scaling si auto-hibern8 (test resetari)
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
op8-mark "UFS fara clkgate/clkscale/auto_hibern8 (op8-ufs-nopm)"
sync
echo "== GATA UFS"
