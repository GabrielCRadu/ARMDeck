#!/bin/bash
# armdeck, stage A: prepares the "steam" container for Steam in Deck mode.
# Runs in the container as the normal user; sudo here is root only inside the container.
set -euo pipefail

# SteamOS shims (after pocknix-steamos-shim). Steam started with -steamos3 calls them; without
# them the first-time setup stops at "Updater apply error: 2".
sudo tee /usr/local/bin/steamos-update >/dev/null <<'EOF'
#!/bin/bash
# 0 = update available / applied, 7 = no update (Valve's convention)
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
# 0 = no BIOS update
exit 0
EOF
sudo chmod 755 /usr/local/bin/steamos-update /usr/local/bin/steamos-select-branch /usr/local/bin/jupiter-biosupdate
# "Switch to Desktop": no desktop, Steam exits and steam-gs starts it again (see the script)
sudo install -m 755 "$(dirname "$0")/op8-session-select" /usr/local/bin/steamos-session-select

# The Steam registry with the first-time setup marked as done (after pocknix registry.vdf)
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

echo "== check"
ls -l /usr/local/bin/steamos-update /usr/local/bin/steamos-select-branch /usr/local/bin/jupiter-biosupdate
grep -c OOBE "$HOME/.steam/registry.vdf"
echo "== DONE container setup"
