# Sources we follow

Every outside project ARMDeck builds on, copies from or learns from, with what to watch in it.
They are checked for news at least once a day while the project is active:

```
python tools/check-sources.py                      # check everything, show what changed
python tools/check-sources.py --if-older-than 20   # same, but only if the last check is older than 20 h
```

The script reads the tables below, asks each project what is new since the last check (the state
is kept in `tools/.sources-state.json`, not committed) and prints the new commits, branches, tags
or releases. The first run only records where every source stands.

**Watch** column (several items are separated by `;`):

- `commits` - new commits on the default branch; `commits: <path>` only those touching that path
  (for very active projects where only one device or package matters);
- `heads` - new or moved branches (kernel forks keep one branch per kernel version);
  `heads: <regex>` only branches whose name matches;
- `tags` / `tags: <regex>` - new tags;
- `releases` - new GitHub releases.

To add a source, add a row; to stop following one, delete its row.

## OnePlus 8 kernel, firmware and device

| Source | Watch | Why we follow it |
|---|---|---|
| [Xo666/mainline-instantnoodle](https://github.com/Xo666/mainline-instantnoodle) | `heads` | The kernel tree our `linux-oneplus-instantnoodle` package builds from (branch `6.16.7`). A new branch means a newer base to move to. |
| [Xo666/linux-oneplus-instantnoodle](https://github.com/Xo666/linux-oneplus-instantnoodle) | `commits` | The firmware blobs and ALSA mixer paths our firmware and UCM packages download by commit. |
| [ObiKeahloa/linux (GitLab)](https://gitlab.com/ObiKeahloa/linux) | `heads: instantnoodle` | Second OnePlus 8 kernel fork (`sm8250/v6.13-instantnoodle`), our alternative kernel package. |
| [ObiKeahloa/linux (postmarketOS GitLab)](https://gitlab.postmarketos.org/ObiKeahloa/linux) | `heads` | The same author's newer SM8250 branches (`6.17.0`). |
| [WuerfelDev/linux-sm8250](https://gitlab.postmarketos.org/WuerfelDev/linux-sm8250) | `heads` | Third OnePlus 8 kernel fork (`6.17.0-instantnoodle`), cross-checked for device tree values. |
| [pmaports: SM8250 kernel](https://gitlab.postmarketos.org/postmarketOS/pmaports) | `commits: device/testing/linux-postmarketos-qcom-sm8250` | postmarketOS' shared mainline kernel for SM8250 phones (7.2.0 on 2026-08-30); patches and version bumps worth taking. |
| [pmaports: OnePlus 8 Pro](https://gitlab.postmarketos.org/postmarketOS/pmaports) | `commits: device/testing/device-oneplus-instantnoodlep` | The OnePlus 8 Pro port, the closest relative of our phone in postmarketOS. |
| [LineageOS kernel for SM8250 OnePlus phones](https://github.com/LineageOS/android_kernel_oneplus_sm8250) | `commits` | The vendor (Android) kernel: the reference for every hardware value we set (voltages, charging, display, audio). |
| [neutrino kernel for SM8250 OnePlus phones](https://github.com/0ctobot/neutrino_kernel_oneplus_sm8250) | `releases` | A tuned Android kernel for the same phones; reference for performance settings. |
| [qbootctl](https://github.com/linux-msm/qbootctl) | `commits` | Marks the boot slot as good at every boot (without it the slot becomes unbootable). |
| [bootmac](https://gitlab.postmarketos.org/postmarketOS/bootmac) | `commits` | Gives the WiFi and Bluetooth chip a MAC address at boot. |

## Similar projects (ideas, fixes, other devices)

| Source | Watch | Why we follow it |
|---|---|---|
| [ROCKNIX: SM8250 devices](https://github.com/ROCKNIX/distribution) | `commits: projects/ROCKNIX/devices/SM8250` | Linux for handhelds with the same chip (Retroid Pocket 5, Mini and Flip 2, AYN Thor Lite, Mangmi Air Y Pro and Pocket Max); GPU tuning, audio and charger fixes. |
| [ROCKNIX releases](https://github.com/ROCKNIX/distribution) | `releases` | Their release notes summarise fixes across all their devices. |
| [Armada OS](https://github.com/armada-os/armada) | `commits; releases` | SteamOS-like Fedora image with ARM64 Steam, FEX and Proton; SM8250 GPU tuning and steamos-manager device files. |
| [Armada for Rockchip](https://github.com/lualiliu/armada-rockchip) | `commits; releases` | Armada on Rockchip handhelds (RK3576); how the same stack is carried to another chip family. |
| [pocknix-os](https://github.com/shuuri-labs/pocknix-os) | `commits; releases` | Steam ARM64 + Proton ARM64 + FEX on SM8250 handhelds; charger, GPU and DXVK experience. |
| [SteamOS-ARM-Handhelds](https://github.com/hashtagbasit/SteamOS-ARM-Handhelds) | `commits; releases` | Valve's SteamOS ARM (Steam Frame build) on SM8350, SM8550, SM8650 and SM8750 devices. Not a direct fit for our kernel, but useful for extending ARMDeck to other devices, plus Valve's newer gamescope, an msm GPU priority fix and session settings. |
| [miARMa](https://github.com/darkplace/miarma) | `commits; releases` | Arch Linux ARM gaming image for the AYN Odin 3 (SM8750); another reference for other devices. |
| [Nova-Deck os-build](https://github.com/Nova-Deck/os-build) | `commits` | Another SM8250 Steam build; they confirmed the DXVK limits of the Adreno 650. |
| [DroidDeck](https://github.com/Droid-Deck/DroidDeck) | `commits` | Steam on Android handhelds; the model for the Steam-first experience. |
| [ChimeraOS gamescope-session-steam](https://github.com/ChimeraOS/gamescope-session-steam) | `commits` | The reference Steam Game Mode session (environment variables, overlay, start-up). |

## Gaming stack we build, patch or depend on

| Source | Watch | Why we follow it |
|---|---|---|
| [gamescope](https://github.com/ValveSoftware/gamescope) | `tags` | We patch 3.16.29 (patches 9001, 9003); a new version means re-checking both patches. |
| [Alpine aports: gamescope](https://gitlab.alpinelinux.org/alpine/aports) | `commits: community/gamescope` | `build-gamescope-op8.sh` fetches this APKBUILD and stops if the version changes. |
| [MangoHud](https://github.com/flightlessmango/MangoHud) | `releases` | `mangoapp` is built with our patches (`build-mangoapp-gs.sh`), and the in-game limiter is MangoHud's. |
| [FEX](https://github.com/FEX-Emu/FEX) | `releases` | Runs x86 games on ARM; every release changes compatibility and speed. |
| [Proton](https://github.com/ValveSoftware/Proton) | `releases` | Proton ARM64 comes through Steam; the release notes say what changed. |
| [DXVK](https://github.com/doitsujin/dxvk) | `releases` | Direct3D 9-11 on Vulkan; DXVK 3 needs features the Adreno 650 lacks. |
| [VKD3D-Proton](https://github.com/HansKristian-Work/vkd3d-proton) | `releases` | Direct3D 12 on Vulkan. |
| [Mesa](https://gitlab.freedesktop.org/mesa/mesa) | `tags: ^mesa-[0-9]+\.[0-9]+\.[0-9]+$` | Turnip, the Vulkan driver for our GPU. |
| [Box64](https://github.com/ptitSeb/box64) | `releases` | The other x86 translator, in case FEX drops the Snapdragon 865. |
| [Proton-GE](https://github.com/GloriousEggroll/proton-ge-custom) | `releases` | Extra game fixes and features (ntsync) that later reach Proton. |
| [distrobox](https://github.com/89luca89/distrobox) | `releases` | Runs the Fedora container Steam lives in. |
| [Podman](https://github.com/containers/podman) | `releases` | The container engine under distrobox. |
| [PipeWire](https://gitlab.freedesktop.org/pipewire/pipewire) | `tags: ^[0-9]+\.[0-9]+\.[0-9]+$` | Audio server, including the filter chain that protects the speakers. |
| [WirePlumber](https://gitlab.freedesktop.org/pipewire/wireplumber) | `tags: ^[0-9]+\.[0-9]+\.[0-9]+$` | Audio session manager (routing, volume). |
| [gamesir-linux-tools](https://github.com/broroeror/gamesir-linux-tools) | `commits` | Linux configuration of GameSir controllers through their vendor HID protocol (G7 Pro, T4 today); watch for GameSir X3 Pro support (fan, pass-through charging). |
| [SDL GameSir driver](https://github.com/libsdl-org/SDL) | `commits: src/joystick/hidapi/SDL_hidapi_gamesir.c` | SDL's GameSir support (G7 Pro 8K, Tarantula 8K so far); the X3 Pro may be added. |
| [GalaxyBudsClient](https://github.com/timschneeb/GalaxyBudsClient) | `releases` | Implements the Galaxy Buds' own control protocol, including the low-latency Gaming mode we want to switch on (TODO 27). |

Not followed automatically: single articles, issue threads and mailing list patches (for example
the upstream USB gadget fix, merged for Linux 7.0-rc4). They are listed where they are used, in
the other documents.
