# userspace: Steam on the OnePlus 8

Everything that runs on top of the kernel and the postmarketOS image so the phone boots straight
into the Steam interface (Deck mode), with sleep, protected sound, buttons and diagnostic logs.
Tested on hardware since 2026-10-01. Results and the to-do list are in
[`../docs/gaming-stack.md`](../docs/gaming-stack.md) section 9, the audits in
[`../docs/performance-crash-audit.md`](../docs/performance-crash-audit.md) and
[`../docs/compat-perf-audit.md`](../docs/compat-perf-audit.md).

Scripts marked *sudo* run as root on the phone (`sudo sh <script>`); the rest as the normal user.
The usual path: copy the files with `scp` to the phone and run them from there. No script writes
to the phone's partitions, with one explicitly marked exception (`system/format-games.sh`).

## Architecture, in short

```
postmarketOS (musl, systemd)          distrobox container "steam" (Fedora 44, glibc)
├─ gamescope on DSI-1 (DRM)  ───────► Steam ARM64 (steamdeck_publicbeta, -gamepadui -steamos3)
│   steam-gs.service (user)           ├─ Proton 11 ARM64 + FEX for Windows games
├─ PipeWire: "Speakers (protected)"   ├─ dbus-send adapter -> logind (sleep/restart/power off)
├─ op8-powerbtn                       ├─ steamos-session-select adapter ("Switch to Desktop")
├─ op8-standby (instead of s2idle)    ├─ op8-touchmode (touch like on a Deck)
├─ op8-thermal, op8-tune              ├─ op8-buttons (volume, Vol+ + Vol- = Steam button)
└─ op8-log (boot report,              └─ op8-mangoapp (performance overlay)
   samples every 2 s)
```

## Install order

| # | File | What it does | Run as |
|---|---|---|---|
| 1 | `system/stageA1.sh` | podman, distrobox, gamescope, Turnip, `vulkan-tools`; subuid; the user joins the `input` group | sudo |
| 2 | (manual) | `distrobox create --name steam --image registry.fedoraproject.org/fedora:44`, then the packages from `docs/gaming-stack.md` section 9 | user |
| 3 | `steam/stageA_steam.sh 1`, then `2` | Valve's Steam ARM64 client, with verified checksums, then its self-update | user, in the container |
| 4 | `steam/stageA_container_setup.sh` | SteamOS shims (`steamos-update`, `steamos-session-select` etc.) and a registry with first-run setup done | user, in the container |
| 5 | `steam/op8-dbus-send` → `/usr/local/bin/dbus-send`, `steam/op8-priv-write` → `/usr/bin/steamos-polkit-helpers/steamos-priv-write` | sleep/restart/power-off adapter (`...WithFlags`, ignores SSH inhibitor locks) and brightness from Steam | `sudo install` in the container |
| 6 | `system/stageA2.sh <PC-IP>` | udev rules for controllers (hidraw, uinput), SSH over Wi-Fi only from the PC | sudo |
| 7 | `op8-log/install.sh` | bluez, USB and Bluetooth controller rules, the op8-log logger | sudo |
| 8 | `system/install-btaddr.sh` | Bluetooth address at boot (bootmac), without which Bluetooth finds no devices; the Wi-Fi address is left alone | sudo |
| 9 | `power/install-qbootctl.sh` | **required:** marks the A/B slot "successful" at every boot | sudo |
| 10 | `power/install-standby.sh`, `power/install-power2.sh` | polkit rule, `op8-standby` instead of kernel suspend, brightness writable by the `video` group | sudo |
| 11 | `audio/audio-step1.sh` | `pipewire-pulse`, the filter plugins, the UCM link | sudo |
| 12 | `audio/50-op8-speakers.conf` → `~/.config/pipewire/pipewire.conf.d/`, `audio/50-op8-wireplumber.conf` and `audio/51-op8-bluetooth.conf` → `~/.config/wireplumber/wireplumber.conf.d/` | the protected speaker output and the S16LE, no-mmap format; Bluetooth headphones without Hands-Free | user |
| 13 | `steam/*.sh`, `steam/op8-touchmode`, `steam/op8-buttons.py`, `steam/op8-mangoapp`, `power/op8-powerbtn`, `op8-log/op8-top` → `~/`; the `.service` files → `~/.config/systemd/user/` | the Steam session and the user services; `op8-top` is for debugging only (two `top` runs and a `sync` every 2 s), leave its service disabled | user, `systemctl --user enable --now ...` |
| 14 | `system/install-tune.sh` | GPU polling 16 ms, THP `madvise`, `CAP_SYS_NICE` for gamescope, `/boot` read-only, except while apk installs packages (the apk hook `system/armdeck-boot-rw`, so the initramfs trigger does not fail) | sudo |
| 15 | in the container, as root: `dnf install python3-evdev pulseaudio-utils gamescope mangohud` | `op8-buttons.py`: both volume buttons read together, volume on release and repeating while held, Volume Up + Volume Down = Steam button (Shift+Tab, which Steam registers with gamescope), also in games; the GameSir X3 Pro's Home button = Quick Access (Shift+Ctrl+Tab, Steam's QAMKeyboardHotkey). `gamescope` (same version as the host, 3.16.29) for its Vulkan WSI layer, and `mangohud` for its in-game limiter, which applies Steam's Frame Limit (`op8-fpslimit`, gamescope patch 9003) | root in the container |
| 16 | `steam/build-mangoapp-gs.sh` (dependencies in its header) | performance overlay: `mangoapp` from MangoHud 0.8.4 with gamescope 3.16.29's field order (otherwise it does not show in games, gamescope #2430); started by `op8-mangoapp` | user, in the container |
| 17 | `system/install-thermal.sh` | `op8-thermal`: limits the big cores and the GPU by battery temperature (41-44.5 °C), plus a readout of the PM8150B JEITA thresholds to `/var/log/op8/` | sudo |
| 18 | `steam/gamescope/build-gamescope-op8.sh` (in WSL on the PC) → `gamescope-op8` in `~/bin/` on the phone | full screen: gamescope with patch 9001, Xwayland always at 2400x1080 (otherwise Steam picks 1920x1080 and black bars appear); patch 9003 hands Steam's Frame Limit to the in-game MangoHud limiter | user |
| 19 | `steam/install-fex-rootfs.sh` → `~/`, run with `distrobox enter steam -- bash ~/install-fex-rootfs.sh` | native x86 Linux games: FEX's Arch Linux root filesystem with x86 Mesa (freedreno, Turnip) at `/usr/share/guestos/fex-mesa`, where Steam's FEX tool looks for it; 1.3 GB download, 4.4 GB on the games partition | user (sudo in the container) |
| 20 | `audio/armdeck-audio-recover` → `/usr/local/bin/`, its `.service` → `/etc/systemd/system/` | brings the sound card back on the boots where the audio DSP's clock vote fails (about 1 in 5): binds the LPASS pin controller again once the DSP is up (`docs/gaming-stack.md` TODO 16); `systemctl enable armdeck-audio-recover` | sudo |
| 21 | `steam/build-lsfg-vk.sh` → `~/`, run with `podman exec -u gabriel steam bash ~/build-lsfg-vk.sh` after `podman exec -u root steam dnf install -y cmake` | optional frame generation: builds lsfg-vk 2.0.0 for ARM64 as an explicit Vulkan layer, enabled per game from the Launch Options; needs Lossless Scaling from its `lsfg-vk` beta branch (TODO 32) | user, in the container |
| 22 | `steam/install-decky.sh` → `~/`, run with `distrobox enter steam -- sh ~/install-decky.sh`; `steam/op8-decky` → `~/` | optional Decky Loader (the plugin menu in Quick Access), DroidDeck's ARM64 build, run by `op8-decky` as the normal user for as long as the Steam session lives; off switch `~/homebrew/armdeck-decky-off`. Read every plugin before installing it (TODO 31) | user |
| 23 | `decky/armdeck/` (built and copied by `tools/deploy-decky-plugin.sh` on the PC, Node and pnpm needed) | the ARMDeck Decky plugin in Quick Access: frame generation on or off per game, multiplier, flow scale and performance mode while the game runs (TODO 32), the thermal guard level and the battery temperature | PC |

**Keeping the phone in step with the repository:** `deploy-manifest.txt` lists where each of
these files lives on the phone. From the PC, `tools/deploy.sh` compares the phone with the
repository (same, DIFFERENT, missing), and `tools/deploy.sh stage` copies what differs to
`~/armdeck-staging/deploy/` with an `install.sh` that backs up, installs, moves older file names
out of the way and reloads the services (run it on the phone: `sh ~/armdeck-staging/deploy/install.sh`).

Optional: `system/format-games.sh` (**erases** the Android `userdata` partition and makes it ext4
for games, asks for the confirmation `FORMAT`), `system/bind-steamapps.sh` (the Steam library on
that partition), then `system/move-steam-to-games.sh` (the whole Steam folder on that partition,
so Steam sees its free space; with Steam stopped),
`system/ufs-nopm.sh` (historical test for the resets during downloads: it does not help, the
cause was the missing reserved-memory region, fixed in the kernel with patch `0003`; not
installed), `system/hide-venus.sh` / `show-venus.sh` (the hardware video decoder, for Remote Play).

Power measurements: `power/op8-power-test` (battery current in each sleep stage) and
`power/op8-s2idle-test` (a real kernel suspend with RTC wake-up), both through
`sudo systemd-run`, as described in their headers.

On the PC: `pc/op8-live.sh [ip]` saves the phone's live log, the samples and a ping to
`D:\op8-logs\` (Git Bash).

## Safety rules

- **Sound:** the ceiling is the volume of the direct ALSA output ("DIRECT - do not use"),
  **-12 dB** since 2026-10-06, with the average-power limiter of `50-op8-speakers.conf` (the
  speakers, TFA9874, have no speaker protection in the mainline driver; steps and measurements
  in `docs/hardware-safety.md` 4.4). It is not raised without a test. Never use `aplay` on the
  host: there ALSA goes straight to the hardware and bypasses the limiter.
- **Never `apk upgrade --prune` / `--available`** on the phone (they remove the local packages).
- **Sleep:** `op8-standby` does not suspend the kernel (s2idle is still being tested). Wake-up:
  the power button; as a fallback `sudo touch /run/op8-wake`.

## Logs

| What | Where |
|---|---|
| Report at every boot (PON/POFF reasons from the PMIC, charging, pstore) | `/var/log/op8/boot-NNNN-*.txt` |
| Samples every 2 s (battery, temperatures, frequencies, I/O) | `/var/log/op8/current.csv` |
| Sleep, power button | `journalctl -t op8-standby -t op8-powerbtn` |
| Volume buttons, Steam button | `~/op8-buttons.log` |
| Performance overlay | `~/op8-mangoapp.log` |
| Steam's sleep/power-off commands | `~/op8-dbus-send.log` |
| "Switch to Desktop" | `~/op8-session-select.log` |
| Touch mode | `~/op8-touchmode.log` |
| Processes every 2 s (only while `op8-top` runs, for debugging) | `~/op8-top.log` |
| Steam crashes (minidumps) | `python3 op8-log/op8-minidump.py /tmp/dumps/crash_*.dmp`, in the container |
