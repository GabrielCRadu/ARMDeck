#!/bin/sh
# armdeck: protectia termica dupa temperatura bateriei (op8-thermal) si o citire, doar
# citire, a pragurilor JEITA din PMIC-ul PM8150B (incarcarea la cald / la rece, nevazute pana acum).
# Rulare: sudo sh /tmp/op8-log/install-thermal.sh
set -eu
S=$(dirname "$0")

echo "== 1. op8-thermal ca serviciu de sistem"
install -m 755 "$S/op8-thermal" /usr/local/bin/
install -m 644 "$S/op8-thermal.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable op8-thermal.service
systemctl restart op8-thermal.service
sleep 2
systemctl is-active op8-thermal.service
journalctl -t op8-thermal -n 3 --no-pager -o cat

echo "== 2. PM8150B: JEITA si starea temperaturii bateriei (doar citire)"
R=/sys/kernel/debug/regmap/0-02/registers
D=/var/log/op8
mkdir -p "$D"
F="$D/pmic-jeita-$(date +%Y%m%d-%H%M%S).txt"
{
	echo "# PM8150B (regmap 0-02), $(date '+%F %T'), baterie $(cat /sys/class/power_supply/bq27411-0/temp) zecimi de grad"
	echo "# 100d = BATTERY_CHARGER_STATUS_7 (b5 HOT_SOFT, b4 COLD_SOFT, b3 TOO_HOT, b2 TOO_COLD)"
	echo "# 1090 = JEITA_EN_CFG (b3 HOT_SL_FCV, b2 COLD_SL_FCV, b1 HOT_SL_CCC, b0 COLD_SL_CCC)"
	echo "# 1092/1093 = JEITA_CCCOMP_CFG_HOT/COLD; 1094-10a3 = praguri (coduri ADC ale termistorului)"
	echo "# 1606 = TEMP_RANGE_STATUS (b6 THERM_REG_ACTIVE, b5 TLIM, b3 ABOVE, b2 WITHIN, b1 BELOW)"
	echo "# 1061 = curent de incarcare, 1070 = tensiune maxima (pentru context)"
	grep -E '^0*(100d|1061|1070|109[0-9a-f]|10a[0-3]|1606):' "$R"
} > "$F"
cat "$F"
echo "== GATA (copie in $F)"
