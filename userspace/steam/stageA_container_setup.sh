#!/bin/bash
# armdeck, etapa A: pregatirea containerului "steam" pentru Steam in modul Deck.
# Ruleaza in container ca userul normal; sudo de aici e root doar in container.
set -euo pipefail

# Shim-uri SteamOS (dupa pocknix-steamos-shim). Steam pornit cu -steamos3 le cheama;
# fara ele, configurarea initiala se blocheaza la "Updater apply error: 2".
sudo tee /usr/local/bin/steamos-update >/dev/null <<'EOF'
#!/bin/bash
# 0 = update disponibil / aplicat, 7 = niciun update (conventia Valve)
for arg in "$@"; do
	case "$arg" in
		--supports-duplicate-detection) exit 0 ;;
		check) exit 7 ;;
	esac
done
exit 0
EOF
sudo tee /usr/local/bin/steamos-select-branch >/dev/null <<'EOF'
#!/bin/bash
case "${1:-}" in
	-l|-c) echo stable ;;
esac
exit 0
EOF
sudo tee /usr/local/bin/jupiter-biosupdate >/dev/null <<'EOF'
#!/bin/bash
# 0 = niciun update de BIOS
exit 0
EOF
sudo chmod 755 /usr/local/bin/steamos-update /usr/local/bin/steamos-select-branch /usr/local/bin/jupiter-biosupdate
# "Switch to Desktop": fara desktop, Steam se inchide si steam-gs il porneste din nou (vezi scriptul)
sudo install -m 755 "$(dirname "$0")/op8-session-select" /usr/local/bin/steamos-session-select

# Registry-ul Steam cu prima configurare marcata ca facuta (dupa pocknix registry.vdf)
cat > "$HOME/.steam/registry.vdf" <<'EOF'
"Registry"
{
	"HKLM"
	{
		"Software"
		{
			"Valve"
			{
				"Steam"
				{
					"SteamPID"		"0"
					"ClientLauncherType"		"0"
					"SteamDeckOOBEComplete"		"1"
				}
			}
		}
	}
	"HKCU"
	{
		"Software"
		{
			"Valve"
			{
				"Steamsteamglobal"
				{
					"language"		"english"
				}
				"Steam"
				{
					"language"		"english"
					"GamescopeEnableAppTargetRefreshRate2"		"1"
					"StartupModeTmpIsValid"		"0"
					"CompletedOOBEStage1"		"1"
					"Rate"		"30000"
					"AlreadyRetriedOfflineMode"		"0"
					"CompletedOOBE"		"1"
				}
			}
		}
	}
}
EOF

echo "== verificare"
ls -l /usr/local/bin/steamos-update /usr/local/bin/steamos-select-branch /usr/local/bin/jupiter-biosupdate
grep -c OOBE "$HOME/.steam/registry.vdf"
echo "== GATA setup container"
