# Compatibility and performance audit (2026-10-02)

Done once the phone had become stable (resets fixed, full screen, overlay). All data was read
from the phone, read only: the kernel configuration, `sysfs`, `/proc`, `vulkaninfo`, `glxinfo`,
the Steam and Proton files in the container. Raw data: `D:\op8-logs\audit\`. It follows
[`performance-crash-audit.md`](performance-crash-audit.md) (2026-10-01), whose open items are
picked up here.

Terms used:
- *Proton* = Valve's version of Wine, which runs Windows games. On ARM64 it translates x86 code
  with FEX.
- *FEX* = the emulator that runs x86 code on the ARM processor. *TSO* = the strict memory
  ordering of x86, which FEX has to imitate; it is the biggest cost of the emulation.
- *DXVK* = translates Direct3D 9/10/11 to Vulkan. *VKD3D-Proton* = the same for Direct3D 12.
- *Turnip* = Mesa's Vulkan driver for the Adreno GPU. *freedreno* = the OpenGL driver.
- *NTSYNC* = a kernel driver that does Windows thread synchronization directly in the kernel;
  Proton uses it on its own when `/dev/ntsync` exists.
- *PSI* = the kernel's measure of how long processes wait for the CPU, memory or disk.
- *EAS* = the scheduler that keeps small tasks on the little cores, for battery life.

## 1. In short: what is worth doing, in order

| # | What | Gain | Effort | Needs |
|---|---|---|---|---|
| 1 | **Proton 11.0 (ARM64) as the default**, never Proton Experimental (ARM64) for D3D9/10/11 | D3D games no longer fail at start | 1 minute | a Steam setting |
| 2 | `CAP_SYS_NICE` on `~/bin/gamescope-op8` | the compositor back at high priority (less stutter) | 1 command | sudo |
| 3 | **NTSYNC** in kernel r7 + a udev rule | faster CPU-bound Windows games | in r7 | flash |
| 4 | **The `fex-mesa` root filesystem** in the container | native x86 Linux games (Half-Life, Terraria, Hue, LIMBO...) | medium project | the container only |
| 5 | Refresh rate 60/90 Hz on demand | battery (today it is always 90 Hz) | gamescope patch | rebuild |
| 6 | PREEMPT_DYNAMIC + the lockup detectors + MGLRU in r7 | latency, crashes that leave a trace, memory under pressure | in r7 | flash |
| 7 | Thermal guard thresholds, after measurements in games | sustained performance | small | sudo |
| 8 | Removing the x86 Proton (`Proton - Experimental`, 1.5 GB) | space; it cannot run without item 4 | 1 minute | Steam |

## 2. What runs now

| Component | Version / state |
|---|---|
| Kernel | 6.16.7 Xo666 r5 + patches 0001-0003, DTB with USB-C 5 V only (r7 and the patch 0005 DTB since then, see section 6 and 8) |
| CPU | 4x Cortex-A55 1.80 GHz + 3x A77 2.42 GHz + 1x A77 2.84 GHz; `schedutil`, 1 ms; ARMv8.2 (`atomics`, `lrcpc`, `dcpop`, `asimddp`), **no LSE2** |
| GPU | Adreno 650, 305-587 MHz, `simple_ondemand`, polling 16 ms (op8-tune) |
| Memory | 11.4 GiB, zram 17 GiB zstd, `swappiness` 180, THP `madvise`, `vm.max_map_count` 1048576 |
| Mesa (container) | 26.2.3: Turnip Vulkan 1.3.354, freedreno OpenGL 4.6 Compatibility / ES 3.2, Zink available |
| Proton | **11.0 (ARM64)**: DXVK 2.7.1-498, VKD3D-Proton 1.1-5153. **Experimental (ARM64)**: DXVK **3.1.1**, VKD3D-Proton 1.1-5626. **Proton - Experimental** (x86) |
| FEX | the Steam tool `FEX-2607-76`; in Proton ARM64: `libarm64ecfex` (x86-64) and `libwow64fex` (32-bit x86) |
| Display | gamescope-op8 (3.16.29 + patch 9001), 2400x1080 **at 90 Hz** |
| Limits | `nofile` 524288 (hard), enough for esync |

## 3. Compatibility

### C1. Proton Experimental (ARM64) does not work for D3D9/10/11 (critical, easy to avoid)

DXVK 3 requires `storageBuffer8BitAccess`, and Turnip on the Adreno 650 reports it as `false`
(read: `storageBuffer8BitAccess=false`, `uniformAndStorageBuffer8BitAccess=false`). Proton
Experimental (ARM64) ships DXVK **3.1.1**, so a D3D10/11 game fails while creating the adapter.
The Nova-Deck project confirmed the same on an SM8250 (PR #53: they switched to `dxvk-sarek` 1.12
when 8-bit storage is missing). Proton 11.0 (ARM64) ships DXVK 2.7.1-498, which does not need
that feature; Tiny Rails, Slime Rancher, Isaac, Undertale and Geometry Dash run on it.
**To do:** Steam > Settings > Compatibility: Proton 11.0 (ARM64) as the default. Terraria has
`proton_experimental` set per game: change it to 11.0 (ARM64). When Valve moves Proton 11.0 to
DXVK 3, D3D11 games will need DXVK 2.7 swapped into the prefix, or `dxvk-sarek`.

### C2. Native x86 Linux games do not start: `fex-mesa` is missing (the cause of TODO 12)

Steam ARM64 sends x86 Linux games through its FEX tool (`steamapps/common/FEX-Emu`,
`fex-compat-tool`). The script looks for an x86 system with x86 Mesa in
**`/usr/share/guestos/fex-mesa`** (with `graphics_provider.json`), as SteamOS has on the Steam
Frame and as Armada and ROCKNIX set up. In our container the folder does not exist and
`FEX-Emu/rootfs` is empty, so the game has neither the x86 libraries nor a graphics driver: it
closes in under a second (Half-Life, Hue, LIMBO, Terraria).
**To do:** an x86-64 + i386 root filesystem with x86 Mesa built with freedreno/Turnip (or with FEX
"thunks", which forward GL/Vulkan calls to the container's ARM64 Mesa), placed in the container at
that path. It does not touch the phone's system (root only inside the container). First check
what root filesystem `FEXRootFSFetcher` offers and whether it has Mesa for Adreno. Until then:
Proton 11.0 (ARM64) forced on the game's Windows version.

### C3. Direct3D 12: limited by the hardware

Turnip on the Adreno 650 has what basic VKD3D-Proton needs (descriptor indexing, buffer device
address, timeline semaphores, `VK_EXT_mutable_descriptor_type`, robustness2), but **lacks**:
`sparseBinding` / `sparseResidency*` ("tiled" resources, required by D3D12 feature level 12_0),
`shaderFloat64`, mesh shaders, ray tracing, fragment shading rate. Games that need D3D12 12_0 or
Shader Model 6.5+ will not start or will be far too slow. Among the installed ones:
**Subnautica 2** (Unreal Engine 5) almost certainly not. **skate.** to check (anti-cheat, D3D12).

### C4. OpenGL and Vulkan directly

freedreno: OpenGL 4.6 Compatibility, ES 3.2; Zink (OpenGL on top of Turnip) available as a
fallback (`MESA_LOADER_DRIVER_OVERRIDE=zink`). Windows OpenGL games go through Wine to freedreno.
Useful extensions present: `VK_EXT_graphics_pipeline_library` (DXVK compiles without big
stutters), `VK_EXT_descriptor_buffer`, `VK_KHR_present_wait`, `VK_EXT_transform_feedback`,
`VK_KHR_global_priority`.

### C5. 32-bit games and ARM64EC

Proton 11.0 (ARM64) has `wow64` + `libwow64fex` for 32-bit x86 and `libarm64ecfex` for x86-64;
Isaac and Undertale (32-bit) run. The CPU has no LSE2, so unaligned atomics in x86 code take
FEX's slow path (TODO 8: the kernel patches `0504` + `1062` from pocknix and Armada).

### C6. Anti-cheat, Remote Play, controllers

- Kernel-level anti-cheat (EAC, BattlEye, EA Javelin) is not expected to work under Proton
  ARM64. Check ProtonDB before big downloads.
- Remote Play: the ARM64 streaming client has a bug of its own (`gaming-stack.md`, TODO 11); the
  alternative is Moonlight + Sunshine.
- USB controllers: working. Bluetooth: Xbox controller tested on 2026-10-03 (see section 8).

### C7. The installed games: the expected path

| Game | Engine / API (probably) | Path | State |
|---|---|---|---|
| Tiny Rails, Slime Rancher, INSIDE, Firewatch, Hue, The Forest, Subnautica, Content Warning | Unity, D3D11 | Proton 11.0 (ARM64) + DXVK 2.7 | the first two run (Slime Rancher in "safe" mode); the rest untested, The Forest and Subnautica heavy |
| Isaac: Rebirth, Undertale, Geometry Dash, Muffin Knight | 2D, 32-bit | Proton 11.0 (ARM64) | run; Muffin Knight with broken text |
| Half-Life, HL2 (+ episodes, Lost Coast), Portal | GoldSrc / Source | x86 Linux build (C2) or Proton with the Windows version | native: no; with Proton: to test |
| Terraria, LIMBO | XNA / own | same | native: no; with Proton: to test (Terraria: moved to 11.0) |
| A Story About My Uncle, Poppy Playtime | Unreal 3 / 4, D3D11 | Proton 11.0 (ARM64) | untested |
| Subnautica 2 | Unreal 5, D3D12 | VKD3D-Proton | most likely not (C3) |
| skate. | D3D12, anti-cheat | | most likely not (C3, C6) |

## 4. Performance

### P1. gamescope-op8 runs without priority (easy, needs sudo)

`op8-tune` gives `cap_sys_nice` only to `/usr/bin/gamescope` (checked: it has
`cap_sys_nice=ep`); `~/bin/gamescope-op8` has nothing. Without it, gamescope cannot raise its
priority or ask for the high-priority GPU queue (`VK_KHR_global_priority`), so compositing
competes with the game.
**To do:** `sudo setcap cap_sys_nice=eip /home/gabriel/bin/gamescope-op8`, and extend `op8-tune`
to set it there too (or ship gamescope-op8 as an apk package).

### P2. NTSYNC is missing (`# CONFIG_NTSYNC is not set`)

In the kernel since 6.14; Proton 11 uses it on its own when `/dev/ntsync` exists. It matters more
on ARM: synchronization without NTSYNC goes through `wineserver` or esync/fsync, i.e. extra calls
through the emulation. **To do in r7:** `CONFIG_NTSYNC=y`, a udev rule (`/dev/ntsync` readable by
the user's group) and a check that it appears in the container.

### P3. A kernel without preemption (`CONFIG_PREEMPT_NONE=y`)

Good for servers, not for games and audio: a long kernel thread can delay a frame. **In r7:**
`CONFIG_PREEMPT_DYNAMIC=y`, with `preempt=full` or `voluntary` from the command line, compared in
games. Also in r7: the lockup detectors (soft/hard lockup, hung task, from the 10-01 audit),
`CONFIG_LRU_GEN` (MGLRU, a better choice of pages to drop when memory fills up; Android uses it),
`CONFIG_SCHED_CLASS_EXT` only if we want to try schedulers like `scx_lavd` (made for the Steam
Deck; unverified on ARM).

### P4. The display always runs at 90 Hz

The panel driver lists the 90 Hz mode first, and gamescope picks it. Steam receives
`GAMESCOPE_DISPLAY_REFRESH_RATE_FEEDBACK = 90`. 90 Hz costs battery and GPU even when a game
runs at 30-60 fps. Gamescope can switch between 60 and 90 Hz (they are separate panel modes), but
Steam's refresh-rate slider only appears when gamescope knows the panel's rates, and without an
EDID it does not tie them together (Armada has patch `0003` for that). **To do:** extend our
gamescope patch with the 60/90 rates for the DSI connector, or start fixed at 60 Hz as a battery
test.

### P5. The thermal guard cuts a lot of sustained performance

In Slime Rancher the battery reached level 4 (big cores limited to 1.06 / 1.19 GHz, GPU at
305 MHz). That is the right choice for a worn battery, but the thresholds (41 / 42 / 43 / 44.5 °C)
were set without in-game measurements. **To do:** a 20-30 minute session with the overlay on
level 3 and the `op8-thermal` log, then adjusted thresholds (for example 42 / 43 / 44 / 45 °C),
plus the 60 Hz rates from P4, which reduce heat.

### P6. x86 emulation (FEX)

- TSO is the main cost. Steam's FEX tool reads `STEAM_FEX_TSOENABLED` and
  `STEAM_COMPAT_FEX_CONFIG` (`TSOEnabled:0`, `Multiblock:1`), so it can be tried per game for x86
  Linux games (after C2). For Proton ARM64 (`libarm64ecfex`) the FEX settings work differently;
  to document before use. Unity games are usually sensitive to TSO being off.
- Unaligned atomics without LSE2: the kernel patches in C5.
- The FEX tool sets `tu_override_uncached_as_cache_coherent=true` for Turnip on its own.

### P7. Steam started with `-noshaders` (removed, see section 6)

The option stops Steam's background shader pre-compilation (Fossilize). On Turnip, DXVK 2.7 uses
`VK_EXT_graphics_pipeline_library`, so the stutter at a first effect is small. Fossilize would
cost CPU and battery during downloads. **Keep** the option, and reconsider only for a heavy game
that stutters.

### P8. The Steam interface uses power when idle

Idle in the interface: about 8% user + 7% system across the CPU, 13,000 context switches per
second, CPU PSI "some" about 12% (almost all in the Steam container). Probably the interface drawn
at 90 Hz plus EAS keeping small threads on the little cores. It does not affect games, but it
costs battery in the menus: one more argument for 60 Hz (P4).

### P9. What is already fine (no change needed)

- Memory: zram zstd, `swappiness` 180, THP `madvise`, `vm.max_map_count` 1048576 (some games need
  large values; SteamOS uses more, but 1048576 is enough for almost all).
- Disk: `mq-deadline`, read-ahead 1 MB, the ext4 games partition with `noatime`; the write resets
  are fixed (patch 0003).
- CPU: `schedutil` at 1 ms, EAS, `uclamp` built in; minimal Spectre mitigations on the A77.
- GPU: polling 16 ms (from 50); 587 MHz is the correct maximum on the SM8250 (the 925 MHz
  overclock from other kernels stays forbidden).
- The open file limit (524288) is enough for esync.

## 5. The proposed plan

1. **Now, no risk:** C1 (Proton default, Terraria), item 8 of the table (x86 Proton removed), P1
   (`setcap`, one sudo command).
2. **Kernel r7** (a single flash, after testing with the boot image as before): patches 0003 and
   5 V (0004) in the package, NTSYNC + udev rule, PREEMPT_DYNAMIC, lockup detectors, MGLRU.
3. **Gamescope as a package:** patch 9001 + the 60/90 Hz rates (P4) + `cap_sys_nice` from the
   package.
4. **`fex-mesa` in the container** (C2), then Half-Life and Terraria tested natively, with TSO per
   game (P6).
5. **In-game measurements** (P5) and an adjusted thermal guard; the C7 table filled in with the
   real fps from the overlay.

## 6. Results (2026-10-02, evening)

Done in the order of the plan, with tests on the phone after each step.

- **C1 confirmed:** Tiny Rails forced onto Proton Experimental (ARM64) fails: Unity writes
  `d3d11: failed to create factory (80004005)` and `Crash!!!`. The default is now
  `proton_11-arm64` (Proton 11.0-2), and Terraria was moved to it and starts.
- **The x86 Proton and Steam Linux Runtime 4.0 (x86) removed** (with
  `steam://uninstall/<appid>`); runtime 1.0 (scout) stays, Steam keeps it as a dependency.
- **P1 done:** `op8-tune` also sets `cap_sys_nice` on `~/bin/gamescope-op8` (only if the file
  belongs to the user and is not writable by others). The gamescope message "No CAP_SYS_NICE,
  falling back to regular-priority" is gone, and the `gamescope-wl`, `-kms`, `-xwm`, `-wait`, `-pw`
  threads run at nice -20.
- **Files damaged by the resets from before patch 0003:** INSIDE had 234 files full of zeros
  (written at 23:57 on October 1, right before a reset: ext4 had recorded the files, but not their
  contents), hence the crash (`MSVCR100.dll ... failed (error c000012f)`). Fixed with
  `steam://validate/304430`. The x86 runtimes also had thousands of empty files (removed, see
  above). A scan of the whole library for zero-filled files found no others.
- **TV colour bars in in-game videos** (Poppy Playtime, Tiny Rails): Proton's fallback image when
  it has no transcoded video (`STEAM_COMPAT_TRANSCODED_MEDIA_PATH not set`,
  `placeholder-video-used`, `h264-used`). Proton cannot decode H.264, and Steam brings the
  transcoded versions through the same mechanism as the pre-compiled shaders, which `-noshaders`
  turned off. Without the option, Steam downloaded the videos on its own (`CompatVideoTCMediaV1`,
  2.6 GB for Poppy) and the Vulkan shaders; Poppy now has its real video. **P7 is reversed:**
  `-noshaders` removed.
- **Kernel r7** (patches 0001-0004 + `armdeck.config`), installed with
  `userspace/system/install-kernel.sh` and written to `boot_b`: boots cleanly, `Dynamic Preempt:
  full`, `/dev/ntsync` (already `0666`, no udev rule needed), MGLRU `0x0003`, watchdog and hung
  task active, sound, Wi-Fi and services fine, the DTB identical to the tested one (reserved
  memory + 5 V). Proton 11 ARM64 uses NTSYNC on its own ("ntsync: up and running").
- **NTSYNC:** Subnautica hung at start (threads waiting in `ntsync_schedule`, 1% CPU); with
  `PROTON_NO_NTSYNC=1` in the Launch Options it runs. Content Warning and A Story About My Uncle
  run with NTSYNC. It stays on by default, with a per-game opt-out. The FPS did not change
  visibly: the tested games are GPU-bound.
- **Games tested** (Proton 11.0-2 ARM64, MangoHud overlay):

  | Game | Result |
  |---|---|
  | A Story About My Uncle | runs, about 30 FPS |
  | Subnautica | runs, about 26 FPS (only without NTSYNC) |
  | Content Warning | runs, about 20 FPS, slightly unstable |
  | Poppy Playtime | runs, the menu video correct after the transcoded videos were downloaded |
  | INSIDE | runs after the file validation |
  | Terraria | starts |
  | Subnautica 2 | does not start (endless loading, no Unreal log either), as C3 predicted |

- **The Proton log** (`PROTON_LOG=1`) was turned on globally only for the tests: FEX produces many
  exceptions, and logging them lowers the FPS. Off; for one game it goes in the Launch Options.

## 7. To test (from the logs of 2026-10-03)

Every boot ended with a power-off or restart requested from Steam, no crash. The thermal guard
did not step in (A Hat in Time, 4 min: CPU max 83 °C, GPU 67 °C, battery 32 °C).

| Game | What was seen | Cause | To try |
|---|---|---|---|
| Tomb Raider (203160) | closes at once, code 127 | Launch Options `gamescope -w 1280 -h 720 -f -- %command%`: `gamescope` does not exist in the container (127 = command not found). Also, Steam picks the x86 Linux version (C2) | Launch Options cleared, Compatibility on Proton 11.0-2, the resolution from the game |
| Subnautica (264710) | closes after 8 s | Compatibility was on Proton Experimental ARM64 (C1, DXVK 3) | Proton 11.0-2, keep `PROTON_NO_NTSYNC=1` |
| A Hat in Time (278360) | 4 min fine, the second start closed after 8 s | probably a manual exit | check a longer session |

If one still does not start: `PROTON_LOG=1 %command%` in the Launch Options, one start, then the
log in `~/proton-logs/steam-<appid>.log`.

## 8. Results (2026-10-03 and 10-04)

- **Two Proton entries with almost the same name:** both games above were set to "Proton 11.0",
  the **x86** build (`proton_11`), which runs emulated through FEX and the x86 Steam Linux Runtime
  (which Steam downloaded again). The working entry is **"Proton 11.0 (ARM64)"**
  (`proton_11-arm64`). With it, Tomb Raider runs at 2400x1080, 90 Hz, exclusive full screen.
- **Overlay:** MangoHud now shows the GPU load, clock and temperature, the CPU temperature of the
  prime core, the battery percentage, power draw and time left, and the battery temperature
  (four patches in `userspace/steam/build-mangoapp-gs.sh`, levels in
  `userspace/steam/mangohud-presets.conf`). In Subnautica: about 7.7 W from the battery, prime
  core 85 °C, GPU 78 °C; the thermal guard reached level 1 at a 41 °C battery.
- **Lower resolutions on the whole screen:** Proton does not change the real display mode; a
  1280x720 game mode is scaled into a 16:9 area with black bars. Steam's "Maximum game resolution"
  sets the game's Xwayland size, and the gamescope patch 9001 now keeps the requested height with
  the panel's 20:9 aspect ratio (1280x720 becomes 1600x720, full screen, upscaled by gamescope).
- **GameSir X3 Pro modes** (G + S held for 2 s): blue = HID mode (`3537:0106`, generic gamepad
  plus a consumer-control keyboard; the Capture button sends Volume Down + Power, Android's
  screenshot chord), white = **DualSense** (`054c:0ce6`, the kernel's `playstation` driver, with
  gyro and touchpad; Capture is the touchpad click). White mode is the better one: Steam Input
  supports it fully, Capture can be remapped, and with "PlayStation Controller Support: Enabled"
  games get Steam's virtual Xbox controller (Xbox button prompts in most games).

## 9. Interface fps audit (2026-10-04, read only, four parallel reviews)

Symptom: about 80 fps in Quick Access, about 50 fps on Steam Home, whatever the Frame Limit.

**Findings, by likely impact:**

1. **The Home number is partly a measuring artefact.** On a still Home screen Steam draws almost
   nothing; mangoapp only recomputes fps when gamescope sends a new frame time, so the value
   freezes or reads low after short animation bursts. While Steam animated, about 84 frames/s were
   measured. Real check: scroll Home continuously and read the overlay then. Steam's Frame Limit
   never applies to the Steam interface (`window_is_limiter_exempt()` in gamescope).
2. **The overlay itself is the steady cost.** MangoHud 0.8.4's mangoapp sets `new_frame` once and
   never clears it (`src/app/main.cpp`), so it redraws at the full 90 Hz: about 35% of a core,
   plus about 22% in Xwayland and 11-14% in gamescope's X thread, about 13 ms/s of GPU, and it
   forces gamescope to recompose every frame. Fix: a mangoapp patch that renders only when a new
   frame time arrives; until then, keep the overlay off in long sessions.
3. **The panel link leaves almost no time per frame (kernel, inference backed by code).** The
   panel is in command mode (TE-paced). Mainline derives the DSI link speed from the mode: 521 Mbps
   per lane at 90 Hz, so one DSC frame takes at least 9.9 ms of the 11.1 ms period. Each commit
   waits for the transfer, so the next frame has about 1 ms to be queued; a miss costs a whole
   period (22.2 ms, 45 fps). OnePlus runs the link at 652.8 Mbps for both 60 and 90 Hz
   (`qcom,mdss-dsi-panel-clockrate`). Proposed, not applied: widen the horizontal porch so 90 Hz
   uses about 652 Mbps (htotal 1220, transfer about 7.9 ms). The same method gives a correct 60 Hz
   mode (htotal 1471, about 652.6 Mbps, plus DCS `60 00`); the failed r9 test ran the link at
   348 Mbps, 47% below the only speed OnePlus uses.
4. **Every frame is composed on the GPU.** The display plane cannot rotate 90 degrees, so the
   landscape image is rotated by gamescope each frame; Steam's interface also renders at the full
   2400x1080. Possible later test: a smaller size for Steam's own Xwayland (same 20:9).
5. **Leftover debug and power costs:** `SDL_LOGGING='*=verbose'` in `steam-in-container.sh`;
   `op8-top` (two `top` runs and a `sync` every few seconds), the sampler's fsync every 2 s and
   journald `SyncIntervalSec=2s`, all from the reset hunt; `sched_util_clamp_min_rt_default` at
   1024 (realtime tasks push the clock to maximum); the MangoHud `exec=awk` fork every 500 ms
   (a shell builtin version avoids it).
6. **To check:** `STEAM_MULTIPLE_XWAYLANDS=1` (set by ChimeraOS with `--xwayland-count 2`) is
   missing, so games may share Steam's X server. The Steam web helper processes are pinned to
   CPUs 2-6 and ran on the little cores at their lowest clock while idle.

**Not the cause (measured):** the GPU sits at 587 MHz most of the time; no thermal limit was
active; gamescope has CAP_SYS_NICE and its threads run at nice -20; memory and I/O pressure 0;
Chromium uses hardware GL through ANGLE on freedreno; the boot-time `dsi_err_worker: status=5`
lines (timeout + FIFO flags, no underflow) stop before Steam starts.

**Result of finding 3 (kernel r11, 2026-10-04):** patch 0006 widens the 90 Hz back porch to 108
pixels, so the DSI link runs at 651.78 Mbps per lane (OnePlus: 652.8). Measured with the overlay:
Quick Access about 80 -> 88 fps, Home while scrolling about 50 -> 53 fps (peak 58), no visual
artefacts. The `dsi_err_worker` lines at boot dropped from 13 to 1 (the one left comes from
gamescope's first mode set). Home is now limited mainly by Steam drawing its interface at
2400x1080 and by the overlay's own redraws (finding 2, mangoapp patch 5).

**Result of finding 2 (mangoapp patch 5, 2026-10-04):** with preset 2 shown and the interface
still, CPU time over 10 s went from 24.5% to 1.5% of a core for mangoapp, 15.8% to 0.6% for
Xwayland and 12.5% to 1.4% for gamescope (about half a core saved). Home while scrolling went
from about 53 to about 60 fps.

## Sources

- Proton, DXVK, VKD3D-Proton, FEX: read from `steamapps/common` on the phone (`version`, strings
  in the DLLs), `vulkaninfo` (Mesa 26.2.3), `glxinfo`.
- DXVK 3 requires Vulkan 1.4 and `storageBuffer8BitAccess`:
  [Phoronix, DXVK 3.0](https://www.phoronix.com/news/DXVK-3.0-Release),
  [linuxiac](https://linuxiac.com/dxvk-3-0-released-with-new-shader-compiler-and-vulkan-1-4-requirement/).
- Adreno 650 and DXVK 3: [Nova-Deck/os-build PR #53](https://github.com/Nova-Deck/os-build/pull/53).
- NTSYNC in kernel 6.14 and used automatically by Proton:
  [Steam Community](https://steamcommunity.com/app/221410/discussions/0/803472142715854998/),
  [Steam Deck HQ](https://steamdeckhq.com/news/proton-ge-10-9-releases-with-ntsync-support/).
- `fex-mesa` and Steam's FEX tool: the `fex-compat-tool` script on the phone;
  [ROCKNIX, x86 Mesa for FEX](https://github.com/ROCKNIX/distribution/commit/d9a00a4edf407ce940a57196ee6a4cd2d62fbab8).
- GameSir X3 Pro modes and buttons: [the GameSir X3 Pro manual](https://gamesir.com/support/manuals/gamesir-x3-pro).
