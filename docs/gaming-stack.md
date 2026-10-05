# The gaming stack: research and recommendation (2026-10-01)

What was checked: SteamOS, Bazzite, Armada OS and the two ARM alternatives found along the way
(pocknix-os and SteamOS-ARM-Handhelds). For each one: whether it installs on the OnePlus 8, what we
can take from it and what is dangerous in it. The sources (code, issues, READMEs) are at the end.
The phone was only read, never written (RAM, partitions, CPU flags, kernel config).

Terms used often:
- *FEX* = the translator that runs x86 programs (Steam for PC, x86 Linux games) on ARM.
- *Proton* = Valve's version of Wine, runs Windows games. The ARM64 build also uses FEX inside for
  the game's x86 code.
- *DXVK* = translates DirectX 9/10/11 to Vulkan. Without it, Windows DirectX games do not run.
- *Turnip* = the open source Vulkan driver for Adreno GPUs (ours is an Adreno 650).
- *gamescope* = the compositor of the Steam Deck's "Game Mode" (it boots straight into the Steam
  interface).
- *glibc / musl* = two base C libraries. Almost all binary Linux software (Steam included) is built
  for glibc. postmarketOS uses musl.
- *ABL* = the phone's Android bootloader (the one that does fastboot and starts `boot.img`).

---

## 1. In short

1. **None of the distributions installs on the OnePlus 8 as shipped.** SteamOS has no public ARM
   image, Bazzite is x86_64 only, and Armada and pocknix boot through an unsigned ABL (the ROCKNIX
   ABL), which would not start at all on our phone (`secure: yes`).
2. **Their kernels are dangerous for our phone**, for two reasons found in the code: the charger
   driver with the ~4.87 V bug, and a GPU overclock to 925 MHz meant for consoles with a fan
   (section 3).
3. **The good news:** Armada and pocknix already run Steam ARM64 + Proton ARM64 + FEX on the
   **Retroid Pocket 5, which has exactly our SoC (SM8250)**. The userspace recipe is proven on this
   silicon.
4. **Recommendation:** keep our kernel (checked on the hardware) and build a glibc userspace on top
   of it after the pocknix/Armada recipe, in two stages: first a test without any flashing, in the
   current postmarketOS, then a native Arch Linux ARM rootfs (section 6).

---

## 2. The projects, one by one

| Project | Base | SoCs | How it boots | On the OP8 as it is? | What we take from it |
|---|---|---|---|---|---|
| SteamOS (Valve) | Arch | x86_64 (Deck); ARM only on Steam Frame | Valve image | No: there is no public ARM image | Nothing directly |
| Bazzite | Fedora Atomic | x86_64 only | UEFI | No | Nothing |
| Armada OS | Fedora bootc | SM8250, SM8550, SM8650 etc. (ROCKNIX devices) | ROCKNIX ABL -> UEFI -> systemd-boot | **No**: needs an unsigned ABL | The recipe: FEX + Arch rootfs, Proton, the gamescope session, inputplumber |
| pocknix-os | Arch Linux ARM | SM8250 (RP5, Flip 2), SM8550 | ROCKNIX ABL (recommended) or the Retroid ABL menu | **No**: the OP8 has neither the ROCKNIX ABL nor the Retroid menu | The userspace packages (pacman), DXVK 2.7 for the Adreno 650 |
| SteamOS-ARM-Handhelds | Steam Frame's SteamOS image | SM8650, SM8550, SM8750, REDMAGIC 6 (SM8350) | ROCKNIX ABL; the stock ABL on the REDMAGIC 6 | Not directly (no SM8250), but the REDMAGIC 6 method applies | Proof that a phone with a stock ABL can boot SteamOS ARM |
| postmarketOS (what runs now) | Alpine (musl) | instantnoodle, our port | stock ABL, `boot_b` | **Yes, it runs** | The kernel, the firmware, the flashing procedure |

### 2.1 SteamOS

- The only official ARM version is the one on the **Steam Frame** (released 2026-09-18,
  Snapdragon 8 Gen 3). Valve does not publish a generic ARM image.
- SteamOS-ARM-Handhelds (2.5) repackages exactly the Frame image for other consoles.

### 2.2 Bazzite

- Images for x86_64 only. There is no ARM variant and none is announced. Out of the question.

### 2.3 Armada OS (github.com/armada-os/armada)

- Fedora bootc (an immutable file system, updated as an image), with device support taken from
  ROCKNIX. Kernel 7.2.6. SM8250 tested on the Retroid Pocket 5 / Flip 2.
- Stack: Steam ARM64 (the `steamdeck_publicbeta_linuxarm64` channel), FEX 2609 with an x86 Arch
  rootfs mounted at `/usr/share/guestos/fex-mesa` (where Steam's FEX tool looks for it),
  proton-cachyos 11.0 arm64, patched Turnip, gamescope + gamescope-session, steamos-manager (the
  Steam Frame one), inputplumber, Decky with its own plugin.
- **Installing it requires writing the ROCKNIX ABL to the `abl` partition.** On the OnePlus 8 the
  bootloader is signed and checked by the chip (`secure: yes` in getvar): an unsigned ABL does not
  boot, and the phone only reaches EDL, repairable with MSM alone. **Not done.**
- The kernel has the `0011-qcom-pm8150b-charger` patch (issues #534 and #550 still open) and the
  GPU overclock (3.2).

### 2.4 pocknix-os (github.com/shuuri-labs/pocknix-os)

- Arch Linux ARM, updated through `pacman` (kernel included), Steam in gamescope + Plasma Mobile as
  the desktop. Officially supports the Retroid Pocket 5 and Flip 2 (SM8250).
- Downloads Valve's Proton 11 ARM64 by itself. **On SM8250 it replaces DXVK 3 with DXVK 2.7**
  (the `pocknix-dxvk2-donor` package), because DXVK 3 needs a GPU feature the Adreno 650 lacks
  (3.4).
- "SM8250 can boot without the ROCKNIX ABL" refers to the **Retroid** bootloader menu (Volume - at
  power-on, boot from the SD card). The OnePlus 8 has neither an SD card nor that menu.
- The kernel (a ROCKNIX snapshot from 2026-07-15) has the buggy charger driver and the GPU
  overclock (3.1, 3.2). It also ships a public password by default (`pocknix`).

### 2.5 SteamOS-ARM-Handhelds (github.com/hashtagbasit/SteamOS-ARM-Handhelds)

- An unofficial port of the Steam Frame's SteamOS image. Stable on SM8650, beta on SM8550 and
  SM8750. **No SM8250.** Kernel from ROCKNIX.
- **The most relevant for us: the REDMAGIC 6 port** (a phone, SM8350). There is no ROCKNIX ABL
  there: it boots from the unlocked Nubia bootloader, with the kernel in `boot`, and the SteamOS
  rootfs is written to `userdata`. Exactly the model we would use too.
- The Frame rootfs runs on Cortex-X1/A78 (ARMv8.2), the same instruction generation as the
  Cortex-A77 in our phone. So it is not built only for new processors.
- The downsides for us: Valve's image is tuned for the Adreno 750, does not include our device,
  updates come as a whole image, and redistributing Valve's image is a grey area.

---

## 3. What is dangerous in their kernels

### 3.1 The charger driver with the wrong voltage (confirmed in the code)

The `0011-qcom-pm8150b-charger.patch` from pocknix (and the same patch in Armada) computes the
float voltage register with the formula of another chip (PMI8998):

```
(voltage_max_design_uv - 3487500) / 7500 + 1
```

On the PM8150B the register means 3.6 V + n x 10 mV. For a 4.435 V battery this gives n = 127, that
is **about 4.87 V**. Add a watchdog "petted" at an address without a base (`0x643`) and a charge
current that is never set. ROCKNIX fixed the driver on 2026-09-29, but Armada and pocknix carry
older snapshots. Our kernel has no such driver at all (the bootloader sets the 4.37 V ceiling at
every boot, checked on the hardware, `hardware-safety.md` 4.1).

### 3.2 GPU overclock to 925 MHz

`9998-gpu-tuning.patch` is identical in ROCKNIX, Armada and pocknix. It adds GPU steps up to
925 MHz on every SM8250 device, at the `TURBO_L1` voltage level. The Snapdragon 865 (ours, not the
865+) tops out at 587 MHz on OnePlus, so this is **about 58% above the specification**. On consoles
with a fan (RP5, AYN Thor Lite) the heat is carried away; the OnePlus 8 is cooled passively. The
likely result is extra heat, throttling and possibly instability. **We do not take it.** Our kernel
stays at 587 MHz (checked, `hardware-safety.md` 4.9).

### 3.3 The ROCKNIX ABL

Recommended by pocknix, required by Armada. On the OnePlus 8 = a phone that only boots into EDL.
The rule already exists (`hardware-safety.md` 3.4); it is repeated here because both READMEs
present it as a normal step.

### 3.4 What is merely useless for us

The fan patches (`9997-set-boot-fanspeed`), the Retroid controllers, their screen panels: they do
not apply to the OP8, but they would not break anything if our DTS does not use them.

---

## 4. What we know works on SM8250 (and so, probably, on our phone)

- **Steam ARM64 + Proton ARM64 + FEX run on the Retroid Pocket 5** (Armada and pocknix support it
  officially). This is the first concrete answer to the risk in `verification-log.md` 7.6.4: the
  current FEX works on ARMv8.2. FEX issue #4120 (raising the requirement to ARMv8.4) is still open;
  if it lands, we pin an older FEX version (the author confirmed they stay available).
- **The phone's CPU flags** (read from `/proc/cpuinfo`): `atomics` (LSE) and `lrcpc` present,
  `lse2` and `flagm` absent. Exactly the RP5's ARMv8.2 profile.
- **DXVK 3 does not work on the Adreno 650.** DXVK 3 needs `storageBuffer8BitAccess`; in Mesa
  (`freedreno_devices.py`) Turnip enables `storage_8bit` only for the a7xx family. The Adreno 650
  is a6xx. The pocknix solution: DXVK 2.7.1 from Proton 11 put in place of DXVK 3.
- **The ARM64 Steam client is built for glibc.** On postmarketOS (musl) it does not run directly,
  only in a glibc container (the pmOS guides in `verification-log.md` 7.6.3) or on a glibc rootfs.

---

## 5. The OnePlus 8 constraints (read from the phone today)

| What | Value | What it means |
|---|---|---|
| Boot | signed stock ABL, Android v2 `boot.img` in `boot_b` | Any system must boot through `boot.img`, as now |
| RAM | 12 GB (11617 MB) + 17 GB zram | Above the 8 GB at which the pmOS guide reported OOM |
| `super` | 14 GiB, the pmOS rootfs is 13.1 GiB, **11.8 GiB free** | Enough for Steam + FEX + Proton + a small test game |
| `userdata` | 219 GiB | The place for games, see the decision below |
| CPU | Cortex-A77/A55, ARMv8.2 | Like the RP5 |
| GPU | Adreno 650, 587 MHz maximum | DXVK 2.7, not 3 |
| Kernel | 6.16.7 (Xo666, r5) | `UCLAMP_TASK`, `BPF_SYSCALL`, `UHID`, `JOYSTICK_XPAD`, `HID_PLAYSTATION` present; **`NTSYNC`, `EROFS_FS` and `sched_ext` missing** |
| Packages on the phone | `gamescope` 3.16.29, `mesa-vulkan-freedreno` 26.2.3 | Available in Alpine edge |

Explanations: *NTSYNC* = a kernel synchronisation mechanism Proton uses for performance (it works
without it, but slower). *sched_ext* = loadable CPU schedulers, for example the `scx_lavd` pocknix
uses. All three can be added in a kernel r6.

**Decision needed before stage B: `userdata`.** Android is already wiped (`super` was rewritten
with pmOS), but the old data in `userdata` is still there, encrypted by Android. It can probably be
recovered only by restoring Android from the backup and unlocking with the old PIN. Formatting
`userdata` for games erases it for good. If there is anything you need there, we take it out first.

**The GameSir X3 Pro controller** takes the USB-C port, so while it is connected there is no SSH
over the cable (and over WiFi it is blocked on purpose, `security-audit.md` S2). For tests: a
Bluetooth controller, or a temporary firewall exception for the PC's IP only. Powering the
controller from the phone (OTG mode) is not checked yet (`hardware-safety.md` 4.11).

---

## 6. The recommendation: our kernel + a userspace after the pocknix/Armada recipe

### Stage A: a test without any flashing (in the current postmarketOS)

Goal: find out whether the GPU, gamescope and Steam ARM64 work on this phone before changing any
partition. Writes nothing outside the rootfs already installed.

1. Native Vulkan: `vulkaninfo --summary` and a simple test (`vkcube`) on Turnip.
2. gamescope on the phone screen (the Alpine package), with a test application.
3. A glibc container (distrobox with Arch Linux ARM) with Steam ARM64, FEX and Proton ARM64,
   copying the Armada configuration (the FEX rootfs at `/usr/share/guestos/fex-mesa`) and DXVK 2.7
   from pocknix.
4. A small game: first a native ARM Linux one, then a Windows one through Proton.
5. Temperatures logged all the time (the thresholds in `hardware-safety.md` 4.8), the speakers at
   a low volume (no limiter yet).

Risk: zero for the hardware and for the partitions. If something does not work, we delete the
container.

### Stage B: a native Arch Linux ARM rootfs (writes to the phone, only with an explicit OK)

If stage A works, we remove the container layer:

- An Arch Linux ARM rootfs with the pocknix userspace (aarch64 `pacman` packages) or rebuilt after
  the Armada recipe. **Without their kernel**: `IgnorePkg` on the kernel and firmware packages.
- Our kernel, with an initramfs that mounts the rootfs from `super` or `userdata`. Flashing only
  `boot_b` (and the partition chosen for the rootfs), as so far. The way back to stock does not
  change (backup + MSM, `hardware-safety.md` 3.6).
- Kernel r6: `NTSYNC`, `EROFS_FS`, maybe `sched_ext`, plus the security options from
  `security-audit.md` S3. Later, moving the DTS and the two patches to 7.2, **without** the charger
  driver (until the version fixed by ROCKNIX, checked by us) and **without** the GPU overclock.

### Why not the other options

- **pmOS + container as the final solution:** it works (the pmOS guides), but it is one more
  layer: Steam starts its own container inside the distrobox container, and the guide reports
  `steamwebhelper` hangs. Good for the test (stage A), awkward for every day.
- **SteamOS ARM (the Frame image) through the REDMAGIC 6 method:** the closest to a real SteamOS,
  but it is not made for the Adreno 650, nobody has run it on SM8250, and it updates as a whole
  image. It stays a possible experiment after stage B, not the starting point.
- **Armada / pocknix as images:** they do not boot on the OP8 without an unsigned ABL (3.3).

---

## 7. New rules (added to the list in `hardware-safety.md` 3.4)

- We do not install the Armada, pocknix or SteamOS-ARM-Handhelds images as they are.
- We do not use their kernels on the OnePlus 8 (charging at ~4.87 V, the GPU at 925 MHz).
- We do not take `9998-gpu-tuning.patch` or any other GPU frequency table above 587 MHz.
- We do not format `userdata` without the explicit decision in section 5.

## 8. What is still unchecked

- Steam ARM64 + FEX + Proton on our phone (proven only on the RP5, the same SoC).
- Real game performance and the thermal behaviour under sustained play.
- Powering the GameSir X3 Pro controller over USB-C (OTG).
- Whether the pocknix userspace can be used without their kernel and device packages
  (`pocknix-device-sm8250` depends on them).

## 9. Stage A on the phone: what works and TODO (2026-10-01)

Everything below was done without any flashing, only in the pmOS rootfs and in `/home/gabriel`.

### What works

- **GPU:** Turnip on the Adreno 650, Vulkan 1.3, Mesa 26.2.3, both on the host and in the
  container. Confirmed on the hardware: `storageBuffer8BitAccess = false`, so DXVK 2.7, not 3.
- **gamescope** (Alpine 3.16.29) straight on the screen: 1080x2400 at 90 Hz, rotated `right`
  (correct relative to the GameSir X3 Pro controller), the touchscreen associated automatically.
- **Container:** distrobox with Fedora 44 (the official image), rootless podman, glibc 2.43.
- **Steam ARM64** (the `steamdeck_publicbeta` channel, runtime `steamrt3c` 20260824): downloaded
  directly from Valve with the checksums verified, self-updated, logged in, the Deck interface
  runs on the phone screen.
- **USB OTG:** the phone switches to host mode by itself and powers the accessory. The GameSir X3
  Pro shows up in the kernel (`3537:0106`, "Zikway GameSir-X3 Pro", `hid-generic`); a USB mouse
  works.
- **The first Windows game (2026-10-01 23:15):** Tiny Rails (Unity, AppID 614630) started from
  Steam through Proton 11.0 (ARM64), Wine ARM64 + FEX, in the Steam Linux Runtime 4 (arm64). The
  maintainer: "it ran quite well". To check which renderer it used (DXVK 2/3 or wined3d).
- **The Steam library** is on `userdata` (ext4 `op8games`, 215 GB, `/home/gabriel/games`),
  bind-mounted into `~/.local/share/Steam/steamapps`; the rootfs stays for the system.

### Pitfalls solved (to remember for stage B)

- Fedora was missing, for Steam: `at-spi2-atk`, `NetworkManager-libnm`. Steam brings its own
  FFmpeg, but looks for it as `libavcodec.so.61` / `libavutil.so.59`, and for `libbz2` as
  `.so.1.0`: symbolic links in `~/.local/share/Steam/lib/aarch64-linux-gnu/`.
- pmOS has `KillUserProcesses=true`: leaving SSH closes everything. The fix: `loginctl
  enable-linger` and starting as a user service (`systemd-run --user --unit=steam-gs`).
- With no session logged in on the screen, gamescope starts with `LIBSEAT_BACKEND=noop` and the
  user in the `input` group.
- There is no `/run/dbus` in the container; the host's bus is at
  `/run/host/run/dbus/system_bus_socket` (`DBUS_SYSTEM_BUS_ADDRESS`).
- With `-steamos3`, Steam calls `steamos-update`, `steamos-select-branch` and
  `/usr/bin/steamos-polkit-helpers/jupiter-*`: shims after pocknix.
- On a restart, wait for the container to stop completely, otherwise podman fails on
  `/etc/passwd` in the overlay.

### Incident: a reset while a game was downloading (2026-10-01 ~21:43)

The phone reset by itself while Steam was downloading Tiny Rails, at the same moment `stageA2.sh`
was running (udev rules + `udevadm trigger` + restarting nftables).

- **The PM8150 PON registers** (PMIC gen2, subtype `0x04`, the reasons at `0x08C0`-`0x08CB`, not at
  `0x0808`-`0x080D` as on gen1): `WARM_RESET_REASON1 = 0x02` (PS_HOLD), `OFF_REASON = 0x80` (a
  normal sequence, not a fault one), `POFF_REASON1 = 0x02` and `PON_REASON1 = 0x40` (CBL) left over
  from the power-off and power-on before. `FAULT_REASON1 = 0x40` (UVLO) is old: the last sequence
  is not a fault.
- **Conclusion:** a "warm" reset requested by the SoC (a kernel panic with `kernel.panic=120` or a
  hardware watchdog after a hang). **No electrical protection of the PMIC was triggered.** The
  charger registers stayed at 4.37 V / 2.0 A / 1.6 A, temperatures 38-40 °C.
- **`ramoops` does not help:** `/sys/fs/pstore` is empty after the reset, not even
  `console-ramoops`, so the OnePlus bootloader does not keep that memory area. The systemd journal
  loses the last minute (written to disk every 5 minutes).
- Most likely culprit at the time: WiFi (ath11k + the unchecked `amss.bin`) under heavy traffic.
  To reproduce with the kernel log streamed live to the PC.
- **The real cause, found on 2026-10-02 (TODO 2):** neither WiFi nor the disk, but a reserved
  memory region missing from the device tree (`removed_mem`). Fixed with kernel patch `0003`.

### TODO

1. ~~Touch as on a Steam Deck~~ **solved 2026-10-02**: Steam switches gamescope's touch mode
   (`STEAM_TOUCH_CLICK_MODE`) only from Steam Input, that is only with a controller connected.
   `op8-touchmode` follows `GAMESCOPE_FOCUSED_APP`: the Steam interface (769) = 4 (real touch,
   swipe = scroll), games = 1 (click). gamescope starts with `--default-touch-mode 4`.
2. ~~The resets during downloads~~ **solved 2026-10-02**: a reserved memory region was missing
   from the device tree. All the resets were "warm" PS_HOLD resets, instant, with no kernel message
   at all (not even in the raw `/dev/kmsg` stream sent live to the PC).
   - **The cause:** the Xo666 device tree deletes `removed_mem` (0x80b00000) from `sm8250.dtsi`
     and moves the firmware regions higher, to 0x8dc00000, but never adds `removed_mem` back. The
     bootloader declares RAM 0x80000000-0xb98fffff, so Linux used ~210 MB of the secure world's
     memory (TrustZone/hypervisor) as normal RAM. Those pages are in `ZONE_DMA32`, used only once
     the higher zones fill up, which is why the reset appeared only with RAM full: during big
     downloads the file cache fills the memory.
   - **The proof:** `stress-ng --vm 4 --vm-bytes 8000M` (no disk) reset in 5 s, while 2000M
     passed. The disk tests that reset (H3, H8, H9: 8 x 1.5 GB in flight) went beyond the free RAM,
     and those that passed (H1, H6 with zeros, H2, H7b) stayed below ~4 GB. The apparent
     difference between zeros and real data came from the file sizes, not from the content.
   - **The fix:** patch `pmaports/linux-oneplus-instantnoodle/0003` (pkgrel 6) adds
     `removed_mem` back with 0xcd00000, as in the WuerfelDev and ObiKeahloa device trees for the
     OnePlus 8. It also covers the OnePlus values (0xAF00000 in Android 11, 0x5300000 in
     LineageOS 23.2 and in `sm8250.dtsi`). With it, RAM2 (2 minutes with 150-350 MB free,
     `--verify` clean) and H9 (72 GB written in 3 minutes, 404 MB/s on average) passed without a
     reset.
   - **Tested on the phone** with the current image's DTB plus the new node (`fdtput`, the only
     difference), written to `boot_b`. The DTB built from source with 0002 + 0003 is identical to
     the tested one. The r6 package was not built with pmbootstrap yet at the time.
   - **Ruled out along the way** (each with a reproduced reset): UFS power management
     (`ufs-nopm.sh`), the UFS queue cut to one command, the USB cable and charging (test on
     battery, over WiFi), the S8C voltage raised to 1.352 V as on Android (test with the image in
     `boot_b`, then back). The UFS VCC (2.504 V) is the same as on Android for UFS 3.0.
3. ~~Controllers in Steam~~ **work**: the GameSir X3 Pro and an Xbox pad over the cable, with the
   udev rules for `hidraw`/`uinput`. Hotplug through `SDL_JOYSTICK_DISABLE_UDEV=1` (udev events do
   not reach the rootless container). The X3 Pro mapping (`3537:0106`, missing from the SDL
   database) was done in Steam.
4. **Bluetooth controllers (to test):** `bluez` installed and running. DualSense
   (`HID_PLAYSTATION`), Xbox Series X over Bluetooth LE (`HID_MICROSOFT` + `UHID`; in 6.16
   `CONFIG_BT_LE` only adds LE audio, LE connections work without it), DualShock 4 (`HID_SONY`).
   (2026-10-04: Bluetooth fixed with `bootmac`, an Xbox controller works.)
5. ~~Audio~~ **works since 2026-10-02**, with a ceiling. Causes: the UCM link
   `conf.d/sm8250/OnePlus8.conf` was missing (fixed in the package too), and the TFA9874 amps stay
   silent if the PCM is opened as S24_LE or with mmap (PipeWire forced to S16LE, no mmap). The
   default output (the protected speaker filter: 250 Hz high-pass + clamp) feeds the direct output,
   whose volume is the ceiling (now -18 dB). The volume buttons: `op8-buttons.py`. See
   `userspace/README.md`.
6. **DXVK 2.7** in place of DXVK 3 for Proton ARM64, after the pocknix method. (The games tested
   so far, Unity and 2D, ran without it.)
7. ~~Space~~ **solved**: `userdata` formatted as ext4 (`op8games`, 215 GB, with the maintainer's
   agreement), the Steam library mounted from there.
8. **FEX for x86 Linux games:** the rootfs at `/usr/share/guestos/fex-mesa` (as in Armada). To
   check whether SM8250 (no LSE2) needs the kernel patch for unaligned atomics that pocknix and
   Armada carry (`0504` + `1062`).
9. **Performance and crash prevention:** see `performance-crash-audit.md`.
10. **Steam in English** from the initial registry; it can be changed in the settings.
11. **Remote Play (streaming from the PC) does not work.** The `streaming_client` crashes at once.
    With the Venus decoder visible (`/dev/video14`), it crashes in the V4L2 path
    (`CV4L2Accel::ProcessCompletedOutputBuffers`, written for the Steam Frame's decoder). Without
    Venus it has no decoder at all: `streamclient.cpp (699) : m_pVideoDecoder`, then SIGSEGV at
    address 0x18 (there is no software decoding fallback). Also tried with
    `STEAM_GAMESCOPE_HDR_SUPPORTED=0`: it still crashes. To try: the format Steam asks V4L2 for
    versus what Venus offers on SM8250 (NV12 vs QC08C/UBWC), H.264 forced on the PC, a stateless
    V4L2 decoder. Reader: `op8-minidump.py`.
    **Investigated 2026-10-02 (strace + gdb on `streaming_client`):**
    - The ARM64 client has only two decoders: `CV4L2Accel` (hardware V4L2) and Pyrowave, but the
      Pyrowave library exists only for x86 (`steamrt64/libpyrowave-shared.so.0`). It has no
      software decoding (no libavcodec, unlike the x86 client). Steam on the PC can encode
      Pyrowave (`libpyrowave-shared-0.dll`).
    - Venus (`/dev/video14`): H.264 / HEVC / VP8 / VP9 / MPEG-2 in, NV12 and Q08C out. The
      client's steps all succeed: `S_FMT` H.264 1920x1088, `REQBUFS` OUTPUT 16 (MMAP), CAPTURE
      NV12 `REQBUFS` DMABUF 16 => 18 (the Venus minimum), 18 DRM dumb buffers, `STREAMON` on both
      queues, 18 CAPTURE `QBUF`. Then the decoding thread does `G_FMT` on OUTPUT and crashes
      (SIGSEGV) **before the first `QBUF` with data**, while looking for a free buffer in its own
      list of OUTPUT buffers (object + 712: pointer, + 728: number of 16-byte elements). The
      pointer is corrupt (`0xffff00000048`, another time `0xaaab00000054`).
    - `STEAMLINK_V4L2_BUFFER_COUNT=18` (a variable the client reads) reached the client, but the
      crash is identical. Removed again.
    - The same V4L2 code is broken on other Qualcomm devices too: on the Ayn Odin 2 Portal
      (SM8550, Iris) it sends empty frames and shows a green screen (steam-for-linux #13428, open
      since July 2026, no answer from Valve).
    - The connection went through the SDR relay (`--transport k_EStreamTransportSDR`, 40 ms
      ping), not directly over the LAN: probably because of the phone's firewall (nft, SSH from
      the PC only).
    - **The proposed alternative:** Moonlight in the container (added as a non-Steam game) +
      Sunshine or Apollo on the PC (NVENC on an RTX 3060). Software decoding (FFmpeg) or Venus
      through `h264_v4l2m2m`. Postponed at the maintainer's request.
12. **Native (x86) Linux games** close in under a second (Half-Life, Hue, LIMBO, Terraria): Steam
    maps them to the `native` tool. Workaround: Proton 11.0 (ARM64) forced in Properties >
    Compatibility (the Windows version). The full solution: FEX + the rootfs at
    `/usr/share/guestos/fex-mesa` (item 8).
    **2026-10-05: they start now.** `userspace/steam/install-fex-rootfs.sh` installs FEX's Arch
    Linux root filesystem (Mesa 26.2 for x86_64 and i386 with freedreno and Turnip, checked
    against FEX's XXH3 hash) on the games partition and links it at that path in the container.
    Half-Life native then runs, but at about 34 fps with low CPU and GPU use and a laggy feel;
    ProtonDB reports the same for the native Half-Life on ordinary x86 PCs (30-40 fps, low
    utilisation), so Half-Life stays on Proton 11.0 (ARM64). Not working yet for native x86
    games: FEX's GL thunks (`STEAM_COMPAT_FEX_CONFIG=ThunksDB_GL:1` reached FEX, but the game still
    loaded the emulated i386 Mesa from pressure-vessel's `/run/gfx`), and the Frame Limit slider
    (our MangoHud layer is ARM64 Vulkan; these games would need x86 MangoHud in the rootfs). To
    test: Terraria, LIMBO, Hue natively. Half-Life on Proton 11.0 (ARM64) is just as slow, and
    kernel r13 (GPU queue priorities) did not change it, so the likely common cause is 32-bit
    OpenGL through emulation: GoldSrc draws in immediate mode, thousands of GL calls per frame,
    each one crossing FEX (and Wine's WoW64 on Proton). Old 32-bit OpenGL games may all suffer from
    it. Half-Life itself could run natively through Xash3D FWGS (open source GoldSrc engine with
    ARM64 builds, plus hlsdk-portable built for ARM64, using the Steam game files); not pursued,
    the goal is the platform, not one game.
    Lead from DroidDeck (commit 9cc40246, 2026-10-04): Windows .NET (CoreCLR) games crash under FEX
    unless memory ordering is fully emulated and multiblock is off (`FEX_TSOENABLED=1`,
    `FEX_VECTORTSOENABLED=1`, `FEX_MEMCPYSETTSOENABLED=1`, `FEX_HALFBARRIERTSOENABLED=1`,
    `FEX_MULTIBLOCK=0`); they set it automatically when `coreclr.dll` sits next to the game, and
    start Godot games with `--rendering-driver vulkan`. Worth trying if a .NET game (or native
    Terraria, which runs on Mono) crashes.
    **Tests on 2026-10-05 (kernel r13, FEX rootfs, games through `fex-compat-tool` and the scout
    runtime, OpenGL from the emulated x86_64 Mesa in `/run/gfx`):**
    - LIMBO: works fully, 90 fps (the panel's rate), 23% CPU, 32% GPU, 4.3 W, sound and
      controller fine.
    - Hue (Unity 5.3): stuck on its first loading screen. Not an ARMDeck problem: its Steam Cloud
      save `cloudsave.bin` is 0 bytes (also in the cloud, since 2026-04-18), the game fails to read
      it ("Failed to read past end of stream"), loads scene -1 and throws a NullReferenceException.
      Moving the empty file away should let it start a new save; not done, the maintainer moved on.
    - Outlast (Unreal Engine 3, its own SDL2 from 2013): 25-30 fps with the maintainer's settings;
      the controller works in the menus but not in the game, with Steam Input (virtual pad
      `28de:11ff`) and without it (X3 in Xbox mode). An `SDL_GAMECONTROLLERCONFIG` mapping for the
      virtual pad changed nothing, since its SDL already sees the pad (the menus react). Parked;
      next idea: the Windows version through Proton 11.0 (ARM64), where the game uses XInput.
    - Firewatch (Unity 2017.4, OpenGL 4.6 on the emulated x86_64 Mesa): runs well, by the
      maintainer's report ("merge foarte ok"); numbers not taken yet.
    - Half-Life 2 (Source, native): runs, "not very well" (maintainer's own test on 2026-10-04);
      to measure.
13. **Muffin Knight:** small display glitches in text (Proton ARM64).
14. ~~Full screen~~ **solved 2026-10-02**, with a modified gamescope (see "Also solved on
    2026-10-02" below). The history of the investigation: the DSI panel has no EDID, and Alpine's
    gamescope does not make one up. Steam does not see the real resolution (2400x1080) and picks
    1920x1080 (`systemdisplaymanager.txt`: "screen resolution: 1920x1080"; in the gamescope log
    Xwayland goes from 2400x1080 to 1920x1080 right after Steam starts).
    `GAMESCOPE_DISPLAY_EDID_PATH` is only the atom through which gamescope gives Steam the EDID
    (written to `GAMESCOPE_PATCHED_EDID_FILE`, with the rotation applied), not a way to load an
    EDID. Options:
    - **B (to try first):** an EDID for 1080x2400 (portrait) with the panel's exact timings, from
      the Xo666 kernel source (the `samsung,amb655uv01` panel driver), injected through the
      debugfs `edid_override` on DSI-1 at boot, before gamescope. Careful: the EDID modes replace
      the panel's list; a wrong timing = a black screen until reboot. Manual test first, then
      permanent.
    - **A:** gamescope rebuilt with the Armada patch
      `packages/gamescope/patches/0002-drm-synthesize-edid-for-edidless-internal-panels.patch`
      (+ `0003` for display profiles), adapted to 3.16.29, built with pmbootstrap.
    - **C:** `-S fill` / `-S stretch` in gamescope (a cropped or stretched image).
    Reference for 2400x1080 phone panels: the `redmagic6.amoled.lua` profile in
    SteamOS-ARM-Handhelds (dynamic rates 60/90/120/144 on a panel without EDID).
    **Tried on 2026-10-02:**
    - **B cannot work on this panel:** in 6.x kernels `edid_override` is used only on the EDID
      read path or when the driver gives no mode; the `panel-samsung-amb655uv01` driver gives two
      modes directly, so the override is ignored (the connector keeps a 0-byte EDID).
    - **An EDID for Steam without rebuilding:** gamescope gives Steam the EDID only through
      `GAMESCOPE_PATCHED_EDID_FILE` (which was missing), and with no EDID from the panel it writes
      an empty file there. `steam-gamescope.sh` now puts the panel's EDID, rotated to landscape
      (`userspace/system/make_edid.py`, 2400x1080 at 90 and 60 Hz, checked with `edid-decode`),
      in place, and makes `<path>.tmp` a directory so gamescope's write fails. It works
      (`GAMESCOPE_DISPLAY_EDID_PATH` points at our file), but **changes nothing**: for an internal
      screen Steam does not read the modes from the EDID (`OnScreenChanged: ... external: 0 modes:
      0`).
    - **The real cause:** Steam sets its own interface to 1920x1080
      (`GAMESCOPE_XWAYLAND_MODE_CONTROL`), and the games' "native" resolution is the interface's
      ("Using maximum game resolution: screen resolution: 1920x1080"). A 2400x1080 request sent by
      us is cancelled by Steam at once. Steam gets from gamescope the panel's physical size
      **unrotated** (70 x 151 mm for a 2400x1080 image; `wl_output` geometry) and computes an
      absurd scale (`UIScaleFromDimensions: 1920 x 1080 : 268mm x 39mm`).
      `GAMESCOPE_FAKE_OUTPUT_MM` has no effect on the DRM backend in 3.16.29.
    - **Steam Settings > Display > Scaling:** the list has no 2400x1080 (it has 2040x1080,
      2560x1080); 2560x1080 does not fill the screen.
    - **The next step at the time:** the rotated physical size: a gamescope patch (swapping
      `phys_width`/`phys_height` when the image is rotated, in `DRMBackend.cpp`, near
      `wlserver_set_output_info`) or, simpler, `.width_mm = 151, .height_mm = 70` in the panel
      driver (kernel r6). Then see whether Steam picks 2400x1080 by itself; if not, the Armada
      patch 0002/0003 (a synthetic EDID in gamescope).
15. ~~Leaving a game without a controller~~ **solved 2026-10-02**: Volume Up + Volume Down pressed
    together open the Steam menu, also in games (see below, `op8-buttons.py`).
16. **Sound sometimes missing after boot:** when the audio DSP answers with an error at boot
    (`qcom-q6afe ... AFE failed to vote (3)`, sometimes also `va_macro ... failed with error
    -110`), the sound card does not appear. 5 of 17 boots on 2026-10-02, with different images, so
    it is not tied to any one change. A reboot fixes it. To try: a service that, if
    `/proc/asound/cards` is missing, reloads the audio drivers (`unbind`/`bind`) or restarts the
    DSP (`remoteproc`).
    **Cause found on 2026-10-05**, from the 49 boot reports in `/var/log/op8/` (each report holds the
    kernel warnings of the boot *before* it, so the failed boots are 8, 14, 20-22, 24, 31, 34, 39
    and 48: 10 of 49, about 1 in 5). It does not follow the start mode (power key, charger,
    reset), charging, battery level or temperature (21-47 °C). Every failed boot has the same
    sequence:
    1. at about 8.3 s the kernel asks the audio DSP to switch on the codec clocks (q6afe command
       `0x100f4`, `AFE_CMD_REMOTE_LPASS_CORE_HW_VOTE_REQUEST`); the DSP, not ready yet, answers
       with error `0x16`;
    2. `q6afe_callback()` has no case for an error answer to that command ("Unknown cmd 0x100f4"),
       so it never wakes the waiting caller, which times out 3 s later: "AFE failed to vote (3)"
       (3 = `LPASS_HW_DCODEC_VOTE`);
    3. the LPASS pin controller (`33c0000.pinctrl`) then cannot enable its clocks and gives up
       with -110 (not a "try again later" error, so the kernel never retries), and every audio
       device that waits for it (rx/tx macros, SoundWire, the sound card) stays deferred.
    The same symptom was reported upstream on a Fairphone 5 (SC7280) on 2026-01-20, in reply to
    "arm64: dts: qcom: kodiak: Add missing clock votes for lpass_tlmm", with no answer; mainline's
    `q6afe_callback()` is unchanged. Two possible fixes: (a) a boot service that, when the card
    is missing, unbinds and binds `33c0000.pinctrl` so the vote is sent again once the DSP is up
    (the card then starts exactly as on a good boot, same levels); (b) a kernel patch so q6afe
    passes the error back and the vote is retried after a short wait. (a) first, tested on a boot
    where the card is missing: written as `userspace/audio/armdeck-audio-recover` and its service
    (not installed yet; it waits 30 s for the card, and only if `33c0000.pinctrl` is left
    unbound does it bind it again, up to three times).
17. **Charging through the controller (pass-through, GameSir X3 Pro):** the phone must be the USB
    host for the controller and receive power through it at the same time. To test with the
    kernel's Type-C/PD stack (`tcpm`, it reports `PD PD_PPS`). Without a charger driver the PMIC
    charges with its hardware limits (checked: 4.37 V, 2 A). The battery is worn (the gauge
    estimates 1.9-3.1 Ah out of 4.27 Ah), and a new battery is not planned.
    **USB-C PD chargers (e.g. Samsung 45 W): not to be used for now.** The connector in the Xo666
    device tree declares `sink-pdos` with `PDO_VAR(5000, 12000, 5000)`, so the phone would ask a
    PD charger for 9 V. On Android the OnePlus 8 never used PD above 5 V (its fast charging is
    Warp, 5 V / 6 A), so 9 V on VBUS is untested on this board. First: a device tree patch with
    `sink-pdos = <PDO_FIXED(5000, 3000, ...)>` (5 V only), then a watched test
    (`tcpm-source-psy-*/voltage_now` must read 5 V). Safe until then: the PC's USB port or a 5 V
    USB-A charger.
    **Done and tested 2026-10-02:** the DTB in `boot_b` now has `sink-pdos = <0x2601912c>` (5 V /
    3 A only; `fdtput` on the image with `removed_mem`, written by the maintainer). The Samsung
    45 W charger offers 5 / 9 / 15 / 20 V and PPS 3.3-21 V; the phone negotiated PD **5 V / 3 A**
    (`power_operation_mode = usb_power_delivery`). The battery gets ~0.9 A with Steam running
    (the PC port: ~0.35 A). The real limit is the PMIC's input current limit (1.6 A at 5 V,
    ~8 W). Now kernel patch `0004` (r7).
    **Pass-through works (2026-10-04, test image r8w):** the X3 asks for a power role swap
    (PR_SWAP) only in the first seconds after the phone is plugged in, and only if its own
    charger is already connected; plugging the charger in later does nothing until the phone is
    re-seated. After the swap the X3 sends its Source_Capabilities 337 ms after PS_RDY, but tcpm
    gives up after 310 ms (the USB PD tTypeCSinkWaitCap minimum; the connector is `self-powered`,
    so tcpm goes straight to a hard reset). The hard reset re-attached the phone as sink and USB
    device, so the controller vanished, and the X3 rejects a DR_SWAP in that state. Fix:
    `sink-wait-cap-time-ms = <620>` on the connector (the USB PD maximum; OnePlus' downstream
    policy engine uses 500 ms). Result: the phone stays USB host and gets PD 5 V / 2 A from the X3
    (the X3 also offers 9 V / 1.5 A, refused by the 5 V-only sink PDOs); the controller and the
    X3 fan work, and the battery gains about 0.1 A in the Steam interface. Use: charger into the
    X3 first, then the phone. Now kernel patch 0007 (r11). The other order (charger after the
    phone) cannot be fixed from the phone: the X3 ignores a swap the phone asks for, and a
    software re-seat only charged for 2-3 s (2026-10-05, see lessons-learned.md); GameSir's FAQ
    gives the same order for Android.
18. **Steam's volume indicator in the bottom-left corner (optional):** Steam has no position
    setting. Options: Decky Loader + CSS Loader (untested in the ARM container) or our own
    indicator in a gamescope overlay, with the volume changed through a separate filter stage
    (then Steam no longer shows its bar).
19. ~~Thermal protection by battery temperature~~ **done 2026-10-02**
    (`userspace/system/op8-thermal`, `install-thermal.sh`). The kernel only protects the processor
    (throttling at 90 and 95 °C, shutdown at 110 °C), while Android throttles much earlier, by case
    and battery temperature. Measured: Slime Rancher took the battery to 46.5 °C (CPU 93 °C), a
    build on 8 cores to 46.6 °C. `op8-thermal` (a system service, every 5 s) limits the big cores,
    the prime core and the GPU in 4 levels, at 41 / 42 / 43 / 44.5 °C battery temperature (1 °C
    hysteresis); the little cores stay free, and in standby it touches nothing. The phone has no
    case sensor.
    **JEITA in the PM8150B** (read only): `0x1090 = 0x00`, so the automatic reduction of the charge
    current and voltage when hot is **disabled** (on Android the OnePlus software does it). Only
    the hardware thresholds remain (`0x1094`-`0x109f`, three pairs of thermistor ADC codes: soft,
    charge stop, emergency stop), not converted to degrees. So without a charger driver the charge
    current (2.0 A) does not drop when hot: charging while playing heats the battery further. To
    follow: enabling JEITA through `0x1090` would need a PMIC register write, not done.
20. **Screen full of coloured noise (cause not fully known):** on 2026-10-02, in Slime Rancher,
    with the overlay on, after a brightness change, the whole screen turned to coloured noise. It
    stayed after sleep and after restarting gamescope; it went away only when the phone rebooted
    (the panel resets when its power is cut). Ruled out: brightness alone (10 slow steps, then 60
    values in 2 s, from sysfs, no noise), Steam's slider in the interface, the `mangoapp` window
    (it was hidden). Clues: Steam sets `GAMESCOPE_DISPLAY_HDR_ENABLED=1` although gamescope reports
    `GAMESCOPE_DISPLAY_SUPPORTS_HDR=0`; the display controller only exposes `CTM` (no `GAMMA_LUT`),
    and in the normal state `CTM` is not set (`drm_info`, snapshot in
    `D:\op8-logs\drm_info-normal-*.txt`). If it comes back: `drm_info` before rebooting and the log
    of the colour properties (`xprop -root -spy`, filtered on `GAMESCOPE_*COLOR/HDR`). Fallback:
    gamescope with `--disable-color-management`.
    **2026-10-04:** it came back for about 13 minutes on kernel r8, with bursts of
    `dsi_err_worker: status=5` (DSI transfer timeouts), and `gamescopectl
    drm_sleep_internal_screen 1`, 2 s, then `0` cleared it without a reboot. The DSI link was too
    slow for 90 Hz (521 Mbps per lane); kernel r11 runs it at the vendor rate (651.78 Mbps) and the
    boot-time `dsi_err_worker` lines dropped from 13 to 1. Not seen on r11 so far.
    **2026-10-05, r11 (parked by the maintainer, to fix later):** coloured flicker linked to
    brightness changes. Steam's auto-dim gave 17 s of bursts of `dsi_err_worker: status=4`
    (`DSI_ERR_STATE_FIFO` in 6.16's `dsi_host.c`; status 5 = FIFO + timeout), and moving the
    brightness slider fast gives a slight coloured flicker (no new `dsi_err` lines that time).
    Earlier, `steam-gs.log` had `write /sys/class/backlight/ae94000.dsi.0/brightness failed,
    errno = 110` (the panel's brightness command timed out). 109 `dsi_err` lines in 4.6 h,
    the first ones 35 s after boot. Leads: how the panel driver sends the brightness command
    (low-power or high-speed mode, versus the vendor driver) while frames stream; coalescing
    Steam's many small brightness steps. Workaround meanwhile: turn off Steam's screen dimming.
21. **Refresh rate the user can change (60 / 90 Hz).** Kernel patch 0006 of r9 ran the panel at
    60 Hz by default, with 90 Hz only through the boot option
    `panel_samsung_amb655uv01.refresh=90`. Wanted: switching from Steam (the refresh-rate slider
    in Quick Access > Performance), so a game that reaches 90 fps can use it. Needed:
    - the panel driver offers both modes again and sends the matching DCS command when the mode
      changes, as OnePlus does with `qcom,mdss-dsi-timing-switch-command` (`F0 5A 5A`,
      `60 00` or `60 10`, `F0 A5 A5`; 16 ms wait after it when going to 60 Hz);
    - gamescope patch 9002 (the preferred mode is looked up with the rotated size too) and
      Steam's dynamic refresh list: gamescope only offers the rates of an internal panel when
      it finds several modes of the same size; Steam reported `modes: 0`.
    - **Tried on 2026-10-04 and reverted:** kernel r9 (patch 0006: only the 60 Hz mode, DCS
      `60 00`) gave a garbled image (coloured patterns, repeated Steam logos) and many
      `dsi_err_worker: status=5`. The mainline DSI host lowers the link clock with the mode's
      pixel clock (348 Mbps at 60 Hz), while the vendor keeps 652.8 Mbps for both rates. A 60 Hz
      mode must keep the link at the vendor rate, as r11 does for 90 Hz (wider porch).
    - Meanwhile gamescope runs without `-r 60` (it held Steam and games at 60 fps while the panel
      scanned out at 90 Hz); games are capped from Steam's Frame Limit.
22. **Thermal guard level in the MangoHud overlay.** Show which `op8-thermal` level is active
    (0 = none, 1-4 = big cores and GPU limited) next to the battery temperature, to see at once
    when performance drops because of heat. Idea: `op8-thermal` writes the current level to a
    small file in `/run` (the container sees the host's `/run` as `/run/host/run`), and an
    `exec` line in `mangohud-presets.conf` reads it.
23. **Kernel Oops when the USB port switches from device to host (2026-10-04).** Seen twice: once
    when the phone booted inside the X3 with its charger connected (the port then flips between
    device and host about twice a second from boot), once when the phone moved from the PC cable
    into the X3. The NCM gadget's network interface (`usb0`, used for SSH over USB) outlives its
    parent gadget device, and the next program that lists network interfaces (Steam's web helper,
    the game) hits freed memory in `rtnl_fill_ifinfo`. The Oops happens with the network lock
    held, so everything that touches networking hangs: NetworkManager, WiFi, podman ("crun: fail
    startup"), the systemd user manager, and SSH logins. Recovery: `sudo sync && sudo reboot -f`
    if a shell still works, otherwise Power + both volume buttons held about 30 s. Known upstream
    bug, fixed in Linux 7.0-rc4 by the series "usb: gadget: Fix net_device lifecycle with
    device_move" (v2, March 2026), missing from 6.16.7. Workaround in place:
    `armdeck-usb-gadget-off` removes the gadget at boot, and `op8-tune` sets `panic_on_oops=1`,
    `panic=10`. **Fixed in kernel r12 (2026-10-05, test image on boot_b):** patches 0008-0010
    backport the fix and two follow-ups; with the gadget active again
    (`armdeck-usb-gadget-off` disabled for the test), PC cable then into the X3 gave no Oops and
    `usb0` moved to `/sys/devices/virtual/net/`. Booting inside the X3 with its charger connected
    (the other trigger) also passed: one boot, no Oops, charging and the controller working, the
    Steam interface up. The gadget-off workaround is not needed from r12 on (left disabled, so SSH
    over the USB cable works again); `panic_on_oops` stays as a safety net. Still to do: install
    the r12 package into `/boot` (the kernel runs from the test image on boot_b), and capture why
    the port flips at boot inside the X3 (tcpm log).
24. **Steam started before the clock was set.** The phone has no usable real-time clock, so the
    date is 1970 until NTP answers (about 40 s after boot on WiFi). Steam started then fails its
    TLS connections and its interface may never appear. Fixed in `steam-gs.service`: it waits
    for the first time sync (at most 90 s, then starts anyway for offline use).
25. **A frame limit set from Quick Access, for every game, without input delay.** Steam's own
    limiter is applied by gamescope's Vulkan WSI layer inside the game (it was missing from the
    container: `dnf install gamescope`, the same 3.16.29). With it, a 30 fps cap gave 15-18 fps in
    Tomb Raider (DXVK's frame pacing misses every other slot on this device), and turning that
    pacing off (`GAMESCOPE_WSI_FRAME_LIMITER_AWARE=0`) gave 30 fps with noticeable input delay.
    MangoHud's in-game limiter (`dnf install mangohud` in the container, then
    `MANGOHUD=1 MANGOHUD_CONFIG=no_display,fps_limit=30,fps_limit_method=late %command%`, Steam's
    limit off) gave a stable 30 fps with no delay the maintainer could feel. **Solved on
    2026-10-05**: Steam's Frame Limit slider now drives MangoHud's limiter in every Vulkan game.
    `gamescope-op8` with patch 9003 (`ARMDECK_FPS_LIMIT_FILE`) no longer enforces the limit nor
    reports its limiter as engaged (no forced FIFO), and writes the requested rate to a file;
    `op8-fpslimit` copies it as `fps_limit` into Steam's MangoHud file, now in
    `/tmp/armdeck-10000/` because Proton games run in pressure-vessel, which does not see
    `/run/user/10000`; every game runs the MangoHud layer hidden (`MANGOHUD=1`,
    `MANGOHUD_CONFIG=read_cfg,preset=0,no_display,...`, set in `steam-in-container.sh`), which
    reloads the file when it changes. Tested in Tomb Raider: 30, 18, 45 and off follow the slider
    live, with no felt input delay. At 30 fps the frame time graph is almost flat (small spikes at
    a regular interval, source not yet known) and the phone draws 6.4 W, against more than 8 W at
    about 35 fps uncapped.
26. **Picture on a TV or monitor through a USB-C to HDMI dongle (to test).** First find out which
    kind of dongle it is. A plain USB-C to HDMI adapter needs DisplayPort over USB-C (alt mode):
    the OnePlus 8 never offered video out on Android, so check whether the board wires it and
    whether the mainline device tree has the DisplayPort controller enabled before expecting a
    picture. A DisplayLink adapter (a USB graphics chip) needs the `evdi` kernel module and
    DisplayLink's closed driver instead. Then: does gamescope pick up the second output, and does
    the X3 still charge and work at the same time.
27. **Bluetooth headphones (Galaxy Buds3 Pro): done on 2026-10-05.** Needed
    `pipewire-spa-bluez` (now in `audio-step1.sh`) and `51-op8-bluetooth.conf` (no Hands-Free
    profile, which the kernel cannot serve without RFCOMM and which stopped the headphones from
    connecting by themselves). A2DP with AAC; they connect by themselves when taken out of the
    case; after a "Disconnect" from Steam they need a trip to the case. Microphone not wanted.
    Optional, later: the delay in games is noticeable (mostly the headphones' own buffer). With
    `CONFIG_BT_RFCOMM=m` in a later kernel, try Samsung's low-latency "Gaming mode":
    it is switched on the headphones through their serial (SPP) protocol, which
    [GalaxyBudsClient](https://github.com/timschneeb/GalaxyBudsClient) implements for the Buds3
    Pro (`Features.GamingMode`, message `GAME_MODE = 135`); a small script could send that one
    message. Not yet known whether it lowers the delay with a non-Samsung phone.
28. **`postmarketos-mkinitfs` stuck in an apk error state (solved 2026-10-05).** Every `apk add`
    reported "1 error" and exited non-zero. Cause: `install-tune.sh` mounts `/boot` read-only
    (audit C6); on 2026-10-03 `apk add bootmac` changed udev files, the mkinitfs trigger tried to
    rewrite `/boot/initramfs` and got "Read-only file system", and apk marked the package broken
    (`f:s` in `/lib/apk/db/installed`). apk 3 counts every installed package marked broken as one
    error in each transaction, and only a reinstall clears the mark. Fix: the apk commit hook
    `userspace/system/armdeck-boot-rw` makes `/boot` writable before an apk transaction and
    read-only again after its triggers; then `apk add` of the r13 kernel package (so `/boot` and
    `/lib/modules` now match the running kernel) and `apk fix postmarketos-mkinitfs`. Checked
    first: mkinitfs and boot-deploy only write files in `/boot` here; they would flash the boot
    partition only with `deviceinfo_flash_kernel_on_update="true"`, which this device does not set.
29. **Undervolting (research only, suggested by the maintainer 2026-10-05).** Lower voltages at the
    same clocks would mean less heat, so op8-thermal would limit later and less. Open questions
    before anything is tried: on SM8250 the CPU voltages come from the clock firmware's tables
    (qcom-cpufreq-hw, with hardware CPR adjusting them per chip) and the GPU picks power levels
    through RPMh, so Linux may not be able to set a voltage at all; what Android kernels for this
    chip (and ROCKNIX/Armada) do, if anything; and how to test stability without risking data.
    Hardware rule: nothing outside the vendor's tables, and only after checking the sources.
30. **Full scan of the related projects' patches (asked by the maintainer 2026-10-05).** Go through
    every kernel and userspace patch in the projects of [sources.md](sources.md) that touch the
    SM8250 or our stack (ROCKNIX SM8250, pmaports' SM8250 kernel, Armada, pocknix,
    SteamOS-ARM-Handhelds, the OnePlus 8 kernel forks), note what each fixes, whether 6.16 has the
    bug and whether it fits the OnePlus 8, with a hardware-safety check; rank the useful ones.
    The msm GPU priority fix (kernel patch 0011) came out of exactly this kind of reading.
31. **Decky Loader (asked by the maintainer 2026-10-05).** Decky is the plugin system of the Steam
    Deck's Game Mode: it adds a plugin menu to Steam's quick access panel by hooking into Steam's
    built-in browser (CEF, through its remote debugging port, enabled by the file
    `~/.local/share/Steam/.cef-enable-remote-debugging`). Upstream publishes only an x86_64
    `PluginLoader`. Two working ARM64 routes seen on 2026-10-05: Nova-Deck runs that x86_64 binary
    through FEX (binfmt), and DroidDeck builds a native `PluginLoader-arm64` in its fork
    (Droid-Deck/decky-loader, preview releases of 2026-09-25). To check: which plugins are useful
    here (themes, per-game profiles, frame generation settings) and which ones ship x86-only
    programs or expect AMD hardware (TDP and clock plugins are built for the Deck's APU and must not
    be used on the SM8250 without a hardware review).
    **Working since 2026-10-05.** `userspace/steam/install-decky.sh` installs DroidDeck's ARM64
    build (release `droiddeck-arm64-preview.2`, sha256 checked; it reports itself as v3.2.9-dev8)
    in `~/homebrew/services/PluginLoader` and creates Steam's `.cef-enable-remote-debugging`;
    `op8-decky`, started by `steam-in-container.sh`, runs it in the container for as long as the
    Steam session lives, **as the normal user, not root** ("decky is running as an unprivileged
    user, this is not officially supported"). So plugins that want root (TDP, CPU and GPU clocks)
    cannot touch the hardware. Steam's debugging port (8080) and Decky's server (1337) listen on
    127.0.0.1 only. The plugin icon appears in Quick Access.
    Decky restarts itself with `systemctl restart plugin_loader` (after some settings changes, or
    its Restart button); here that service does not exist, so the first restart left Decky
    waiting with its menu half loaded. `op8-decky` now puts `decky-systemctl` first in Decky's
    PATH: "restart" and "stop" end the loader and `op8-decky` starts it again. Its own updater does
    nothing on ARM64 (DroidDeck's fork leaves updates to an outside installer); updates go through
    `install-decky.sh`.
    Second problem, the same evening: after a Steam session restart the screen stayed black.
    Two plugin processes (Decky LSFG-VK, CSS Loader) ignored SIGTERM and outlived the loader;
    gamescope's reaper waits for every process of the session, so `steam-gs` hung in
    "deactivating". `op8-decky` now starts Decky with `setsid`, so the loader and all its plugins
    share one process group, and stops the whole group (SIGTERM, then SIGKILL after 3 s) when
    Steam ends or the loader restarts. Checked: a restart through `decky-systemctl` leaves no
    process behind and Decky is back in 8 s.
    Plugins in use (read before use, 2026-10-05): CSS Loader 2.1.2 (themes), Game Theme Music
    1.7.1-1 (uses yt-dlp, a Python script, not an x86 program), SteamGridDB 1.7.1, ProtonDB Badges
    1.2.0 (ratings from x86 PCs, a hint only here). Decky LSFG-VK is to be removed (see above).
    Later the same night: Decky LSFG-VK and ProtonDB Badges were removed by hand (Decky's own
    uninstall of LSFG-VK looped in its hot reload, "already loaded and has requested to not be
    re-loaded"; ProtonDB Badges 1.2.0, the store's version, threw an error on every game page).
    To remove a plugin by hand: delete `~/homebrew/plugins/<name>` and its `settings`, `data` and
    `logs` folders, then restart Decky; killing only a plugin's process left the loader unable to
    stop, and it needed SIGKILL.
    **ARMDeck's own plugin (2026-10-06).** `userspace/decky/armdeck` (TypeScript panel, Python
    backend, built and copied by `tools/deploy-decky-plugin.sh`), in Quick Access:
    - Frame generation for the running game: the switch adds or removes the plugin's part of the
      game's Launch Options (`TU_DEBUG=noubwc VK_LOADER_LAYERS_ENABLE=VK_LAYER_LSFGVK_frame_generation
      LSFGVK_PROFILE=armdeck-<appid>`, other options kept; applies at the next start); multiplier,
      flow scale and performance mode go to the game's profile in `~/.config/lsfg-vk/conf.toml`,
      which lsfg-vk applies while the game runs.
    - System: the `op8-thermal` level (`/run/op8-thermal.level`) and the battery temperature.
    Tested in Tomb Raider: the switch, the live multiplier and flow changes all work. Moving a
    slider first wrote the file 12 times in 3 s, and the rebuilds in a row froze the game (idle
    process, no GPU hang in the kernel log); the panel now writes once, 0.8 s after the slider
    stops, and skips unchanged values. Quality mode (performance mode off) at 4x gave 15 fps with
    heavy warping, as the benchmark predicted. The maintainer's verdict on Tomb Raider: not a game
    for frame generation (it already fills the GPU).
    Every plugin is read before it is installed: plugins run with this user's rights and can drop
    files where every Vulkan program looks. **decky-lsfg-vk (v0.14.4) must not be installed:** it
    downloads lsfg-vk's x86_64 build into `~/.local/lib` and registers it as an implicit layer in
    `~/.local/share/vulkan/implicit_layer.d`, which every Vulkan program reads, the host's
    gamescope included; on ARM64 that library cannot load, and its layer has the same name as our
    explicit one. The frame generation control (TODO 32) is better done as a small ARMDeck plugin
    that edits `~/.config/lsfg-vk/conf.toml` (which lsfg-vk reloads live) and could also show the
    thermal guard level (TODO 22) and the real frame rate.
32. **Frame generation (asked by the maintainer 2026-10-05).** Generated frames in between the
    real ones, for a smoother picture at the same GPU load. Candidates: lsfg-vk (Lossless
    Scaling's frame generation as a Vulkan layer on Linux; needs the Windows app bought on Steam,
    since it uses its shaders) and the frame generation built into some games (FSR 3). To check:
    whether lsfg-vk works on ARM64 with Turnip, its GPU cost on the Adreno 650, the extra input
    lag, and how it fits with the 90 Hz panel and the frame limiter (it needs a steady base rate,
    e.g. 45 fps shown as 90). Seen on 2026-10-05: DroidDeck runs Lossless Scaling's frame
    generation on Adreno phones inside its own compositor (code in `app/src/main/cpp/framegen/lsfg`,
    from lsfg-vk via the Eden emulator), plus a simpler built-in "Win-FG". Its notes say the 25
    shaders come out as SPIR-V 1.6, so the GPU driver must offer Vulkan 1.3 (or the SPIR-V 1.4 and
    memory model extensions) and storage-image writes without a format; Turnip on the Adreno 650
    should, to be checked with `vulkaninfo`. lsfg-vk publishes x86_64 builds only, so on ARM64 it
    would be built from source.
    **2026-10-05: built and benchmarked on the phone.** `userspace/steam/build-lsfg-vk.sh` builds
    lsfg-vk 2.0.0 unmodified in the container (its licence, CC BY-NC-ND 4.0, rules out shipping
    its code or binaries) and installs the layer for the user only, as an explicit layer (see
    the layer order below), so the host's gamescope and other Vulkan programs never load it.
    Turnip 26.2.3 offers Vulkan 1.3, `vulkanMemoryModel` and storage image writes without a format.
    The shaders come from Lossless Scaling's `lsfg-vk` beta branch (`lsfg-vk.dll`).
    `lsfg-vk-cli benchmark`, time per real frame (the GPU clock moved between 305 and 587 MHz in
    these runs, so the numbers vary by about 30% between runs):

    | Input | Mode | Multiplier | Time per real frame |
    |---|---|---|---|
    | 2400x1080 | quality | 2 | 1606 ms (2048 ms without FP16) |
    | 1200x540 | quality | 2 | 468 ms |
    | 2400x1080 | performance | 2 | 53 ms |
    | 2400x1080 | performance, flow 0.5 | 2 | 20-28 ms (39 ms without FP16) |
    | 2400x1080 | performance, flow 0.25 | 2 | 10.6 ms |
    | 1920x864 | performance, flow 0.5 | 2 | 22.6 ms |
    | 1600x720 | performance, flow 0.5 | 2 | 9.1 ms |
    | 1600x720 | performance, flow 0.5 | 3 | 22.3 ms |
    | 1200x540 | performance | 2 | 16 ms |

    Quality mode is unusable here: Mesa's shader dump (`IR3_SHADER_DEBUG=disasm`) shows its five
    largest compute shaders (about 12,000 instructions each) spilling registers to memory, about
    1,100 `stp` stores and 380 `ldp` loads each, 5,864 and 2,101 in total, against 9 and 14 in
    performance mode. The Adreno 650 runs out of registers for them. Performance mode with a
    reduced flow scale is the only practical setting, and it still takes 10-25 ms of GPU time per
    real frame, time the game itself then lacks. So it can only pay off in games that leave the GPU
    idle part of the time (limited by the CPU or by a frame cap).
    Loading checks (2026-10-05, `VK_LOADER_DEBUG`, first install as an implicit layer made opt-in
    with `enable_environment`): without `ENABLE_LSFGVK=1` neither the host nor
    the container loads the library. With it and a profile (`LSFGVK_ENV=1 LSFGVK_MULTIPLIER=2`) it
    loads in the container and inside Steam Linux Runtime 4 (arm64), where pressure-vessel
    imports it as `00-aarch64-linux-gnu.json`. Forced on the host, the musl loader crashed
    (segmentation fault) loading this glibc library: an always-on layer in the shared home
    directory would have taken down gamescope at its next start. Without a profile the layer
    turns itself off (the loader then prints "Failed to find 'vkGetInstanceProcAddr'" and skips
    it). With the layer on, `vulkaninfo` prints 401 loader errors "Exhausted the unknown device
    function array", with both Fedora's loader (1.4.341) and the runtime's (1.4.309), and still
    finishes; to watch for in a game.
    **First game test (Tomb Raider, Proton 11 ARM64, 2026-10-05): black screen.** lsfg-vk's log:
    "An error occured while initializing the lsfg-vk swapchain: vk::Device::allocateMemoryUnique:
    -1000072003" (`VK_ERROR_INVALID_EXTERNAL_HANDLE`). lsfg-vk shares two images between its own
    Vulkan device and the game's through opaque file descriptors, but creates them with different
    usage flags on the two sides: storage, sampled and transfer where it exports
    (`lsfg-vk-pipeline/src/pipeline.cpp`), transfer only where it imports
    (`lsfg-vk-layer/src/wrapper.cpp`, `importImage`). Turnip picks the memory layout from the
    usage (UBWC compression for a transfer-only image, none with storage), so the two layouts
    differ and the import is refused. Desktop drivers tolerate the mismatch. Workaround to test:
    `TU_DEBUG=noubwc` (no UBWC in the game, so both sides match, at some GPU cost). Real fix:
    identical usage on both sides, a one-line change in lsfg-vk; its licence forbids publishing
    modified code, so it goes to the author as a report.
    **Result with `TU_DEBUG=noubwc`:** the picture comes back and lsfg-vk runs without errors, but
    the game shows about 25 fps whatever the Frame Limit, and feels no smoother than that, with
    more input lag. The GPU sat at its top clock (587 MHz) and the SoC at 87 °C: Tomb Raider
    already fills the GPU, so frame generation's 20-28 ms per real frame (plus the lost UBWC
    compression) halves the real frames and the generated ones only bring the total back.
    Part of that was the layer order: with the Frame Limit at 30 the game felt like 15 fps. The
    loader log (`Insert instance layer`, listed from the driver up) showed the implicit lsfg-vk
    layer above MangoHud, so MangoHud's limiter counted the generated frames too: 15 real plus
    15 generated. Moving its manifest to a later search path changed nothing; installed as an
    **explicit** layer and enabled with `VK_LOADER_LAYERS_ENABLE=VK_LAYER_LSFGVK_frame_generation`,
    it sits below MangoHud (driver, lsfg-vk, device_select, MangoHud, game), and the limit then
    applies to the real frames only. That also means it is never loaded unless asked for, on the
    host or in the container. Result on Low settings: the overlay (gamescope's count, which
    includes the generated frames) reached about 45 fps at most, against 35 with the old order;
    the GPU is still the limit. The maintainer's verdict: good progress.
    Launch options used: `TU_DEBUG=noubwc VK_LOADER_LAYERS_ENABLE=VK_LAYER_LSFGVK_frame_generation
    LSFGVK_ENV=1 LSFGVK_MULTIPLIER=2 LSFGVK_PERFORMANCE_MODE=1 LSFGVK_FLOW_SCALE=0.5 %command%`.
    Next: a second overlay line with the real frame rate next to the total (asked by the
    maintainer; the in-game MangoHud now sees only real frames), the report to lsfg-vk's author
    about the usage mismatch, and the control described below.
    **Wanted by the maintainer (2026-10-05):** a frame generation control next to Steam's Frame
    Limit, for every kind of game. Routes: Decky (TODO 31) with the decky-lsfg-vk plugin, or an
    unused Steam control mapped to `~/.config/lsfg-vk/conf.toml` (multiplier, flow scale and
    performance mode reload live), as `op8-fpslimit` does for the Frame Limit. lsfg-vk only sees
    Vulkan games: OpenGL games would go through Zink (OpenGL on Vulkan), and native x86 games
    under FEX would need the official x86_64 layer in the FEX root filesystem. Frame generation
    inside gamescope (as DroidDeck does in its own compositor) would cover everything, but is a
    large project.
33. **GPU runtime suspend cost (lead from Nova-Deck, 2026-10-05).** On the Adreno 750, a GPU suspend
    that starts shortly after a resume busy-waits a full second in `a6xx_gmu_wait_for_idle()`;
    Nova-Deck raised the autosuspend delay from 66 to 200 ms (kernel patch 0240) and idle
    kworker CPU fell from 18% to 6%. Our Adreno 650 uses the same a6xx driver and is at the 66 ms
    default (`/sys/devices/platform/soc@0/3d00000.gpu/power/autosuspend_delay_ms`). To check:
    kworker CPU at idle in the Steam UI and how long GPU suspends take here; the delay can be
    tried at runtime through sysfs before any kernel change.
    **Measured 2026-10-05 (Steam UI, no game, screen on, performance overlay at level 2,
    charging):** the GPU never suspended in 60 s (status `active` in all 1,075 samples, no
    transition), so Nova-Deck's suspend/resume cycle cannot happen here and kworker CPU stayed
    around 1%. The real idle cost is elsewhere: something redraws all the time. Over 30 s,
    mangoapp used 31% of a core, Xwayland 25%, gamescope 18%, Steam's web helper about 40%, and
    all CPUs together were 20-24% busy (about 1.7 cores). Next: the same measurement with the
    overlay off, then on another Steam UI page, to find who keeps redrawing (Steam UI animation
    or the overlay); a still screen should let the GPU sleep.
34. **sched_ext with scx_lavd (lead from Nova-Deck, 2026-10-05).** A CPU scheduler loaded from user
    space, built for games and for big and little cores; Valve's Steam Frame (ARM) ships it with
    `--pinned-slice-us 500 --dd-max-wait-us 0`, and Nova-Deck builds it from Valve's tree. Our
    kernel does not have `CONFIG_SCHED_CLASS_EXT` (it also needs BPF and BTF), so it means a
    kernel rebuild plus the scx tools in the root filesystem. To check: what it gains on the
    SM8250's 1+3+4 cores against the default scheduler, measured in a real game.

Also solved on 2026-10-02, later:

- **Steam's free space** (Storage showed 13.1 GB): Steam computes the free space on its install
  directory, which was on the system partition (2.9 GB free), not on `steamapps`.
  `userspace/system/move-steam-to-games.sh` moves the whole Steam directory to the games partition
  and bind-mounts it at the same path; `steam-gs.service` now waits for that mount.
- **The volume buttons** (`userspace/steam/op8-buttons.py`, in the container, started with the
  Steam session; replaces `op8-volbtn` on the host):
  - swapped: in landscape the physical Volume Up is on the left, and Steam's bar grows to the
    right;
  - the volume changes on release, and while held, continuously, after 0.5 s. The buttons send no
    automatic repeat (`EV=3`, no `EV_REP`), so holding has its own timer;
  - **Volume Up + Volume Down together = the Steam button**, also in games: Steam registers
    Shift+Tab with gamescope as the Steam button (`GuideKeyboardHotkey -> [Tab + Shift_L]` in the
    gamescope log), and gamescope catches it before the game. It is sent from a permanent virtual
    keyboard, after both buttons are released: gamescope triggers it only when no other key is
    down, and the volume buttons are keyboards to it too. Abandoned attempts: a virtual Xbox
    controller created on press (Steam showed "controller connected") and a keyboard created at
    every press (gamescope had no time to see it). Two `sh` processes, one per button, caught the
    combination about one time in three.
- **The performance overlay** (the `...` menu > Performance): gamescope 3.16.29 sends `mangoapp`
  the fields `app_frametime_ns` and `visible_frametime_ns` in the reverse order of every MangoHud
  (0.7.1 from Alpine, 0.8.4, `master`). `mangoapp` then always reads "unknown" as the visible frame
  time, never leaves pause and does not show in Steam/Proton games
  ([gamescope #2430](https://github.com/ValveSoftware/gamescope/issues/2430), the same symptoms).
  `userspace/steam/build-mangoapp-gs.sh` builds MangoHud 0.8.4 with gamescope's order, in the
  container (`ipc=host`, so it sees gamescope's message queue); `op8-mangoapp` starts it with the
  session, and gamescope no longer gets `--mangoapp`. Steam writes the level to
  `/tmp/armdeck-10000/mangohud.conf` (until 2026-10-05 `/run/user/10000/mangohud.conf`, which
  games in pressure-vessel cannot see). When gamescope goes back to the old order, the patch must
  go.
- **Full screen** (no black bars, games at 2400x1080): Steam stores the panel in its configuration
  as an **external** screen (`config.vdf`: `IsExternalDisplay 1`, "External: OnePlus 8"), although
  gamescope announces it as internal, and at every start asks for Xwayland at 1920x1080
  (`GAMESCOPE_XWAYLAND_MODE_CONTROL = 0, 1920, 1080, 0`); a 2400x1080 request sent from outside is
  cancelled at once. The solution: Alpine's gamescope 3.16.29 plus a patch in
  `userspace/steam/gamescope/`: with `GAMESCOPE_FORCE_NATIVE_XWAYLAND`, every Xwayland mode request
  became the native size (since 2026-10-04, `9001-armdeck-xwayland-panel-aspect.patch` keeps the
  requested height and gives every mode the panel's 20:9 aspect, so "Maximum game resolution"
  1280x720 becomes 1600x720). Built with `build-gamescope-op8.sh` (pmbootstrap, under qemu:
  crossdirect failed with "cannot execute cc1"), run from `~/bin/gamescope-op8` without
  installing; `steam-gamescope.sh` uses it when present. Checked: Steam asks for 1920x1080 five
  times at start, then stops (no loop), and for Tiny Rails the log shows "Using maximum game
  resolution: screen resolution: 2400x1080". Limits: a resolution chosen per game in Steam is
  ignored. To do: an apk package, rebuilt at every gamescope update.
- **Charging in sleep:** in standby the phone no longer answers over WiFi (ping and SSH), so
  remote checks need the phone awake or on the cable.
- **The first 3D game:** Slime Rancher (Unity, Proton 11 ARM64) works, started in "safe" mode
  (`-lowGraphics`); without it it sometimes closed while loading.
- **The charging indicator that comes and goes:** from the PC's USB port the phone gets ~2.5 W
  (Type-C without PD). Under load it uses more, and the battery state switches between "Charging"
  and "Discharging". With a wall charger it does not happen.

Solved in the meantime: SSH over WiFi from the PC only (`40_ssh_usb_only.nft`, the PC's IP), the
WiFi profile untied from the MAC address (after a reset the QCA6390 chip reported another MAC),
the `op8-log` logging (a report at boot, samples every 2 s, `journald` every 2 s, `op8-live.sh` on
the PC; the 2 s syncs were turned off on 2026-10-04).

Solved on 2026-10-02 (the scripts in [`../userspace/`](../userspace/README.md)):

- **The boot slot had become unbootable** ("the current image (boot/recovery) have been
  destroyed"): the bootloader lowers the retry counter at every boot, and nothing marked slot b as
  "successful". Fixed with `fastboot --set-active=b` (from fastboot, entered with the phone off
  **without a cable**: Volume Up + Volume Down + Power), then `qbootctl` + `qbootctl-systemd`
  (`qbootctl -m` at every boot). The device package now depends on `qbootctl`. Renaming the device
  in Steam had nothing to do with it.
- **Sleep** (the Steam menu and the power button): Steam suspends with `dbus-send ... login1
  Suspend`, but there was no `dbus-send` in the container, polkit asked for a password
  ("challenge"), and the SSH sessions hold `inhibit=sleep` (`/etc/pam.d/sshd`). Now: a polkit
  rule, a `dbus-send` adapter (`SuspendWithFlags` ignoring the inhibitors),
  `systemd-suspend.service` runs `op8-standby` (no kernel suspend) and `op8-powerbtn` (short =
  sleep, long = menu). Restart and power-off from the Steam menu go through the same adapter.
- **Brightness from Steam**: the `brightness` file writable by the `video` group (udev) + a
  `steamos-priv-write` helper in the container.
- **The Steam session** restarts by itself (`Restart=always`) and waits for the container to stop.

## Sources

- Armada OS: https://github.com/armada-os/armada (`packages/kernel/patches/9998-sm8250-gpu-tuning.patch`,
  `packages/steamos-manager/devices/sm8250.toml`, issues #534 and #550)
- pocknix-os: https://github.com/shuuri-labs/pocknix-os (`README.md`, `kernel/README.md`,
  `kernel/sm8250/patches/20-sm8250/0011-qcom-pm8150b-charger.patch` line 2298,
  `9998-gpu-tuning.patch`, `packages/soc/pocknix-dxvk2-donor/PKGBUILD`)
- SteamOS-ARM-Handhelds: https://github.com/hashtagbasit/SteamOS-ARM-Handhelds
  (`docs/redmagic6.md`, `docs/HOW-IT-WORKS.md`, `LICENSE`)
- ROCKNIX: https://github.com/ROCKNIX/distribution (`projects/ROCKNIX/devices/SM8250/patches/linux/9998-gpu-tuning.patch`,
  PRs #3371 and #3382 for the charger driver)
- Mesa: `src/freedreno/common/freedreno_devices.py` (`storage_8bit = True` only in `a7xx_base`)
- FEX: https://github.com/FEX-Emu/FEX/issues/4120
- The phone (read only, 2026-10-01): `/proc/cpuinfo`, `free`, `df`, the partitions in
  `/sys/class/block`, `/proc/config.gz`, `apk policy`
- USB gadget fix: "usb: gadget: Fix net_device lifecycle with device_move" v2,
  https://lkml.iu.edu/2603.1/01502.html (merged for Linux 7.0-rc4)
