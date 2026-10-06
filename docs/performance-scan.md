# Performance scan: where the frame rate goes (2026-10-06)

Asked by the maintainer: find the major performance losses, module by module, with the goal of
at least doubling the frame rate, as other handhelds with the same chip (Snapdragon 865 / SM8250)
appear to do. Nothing in this document was changed on the phone: the data comes from the
sampler logs (`/var/log/op8/`), read-only checks of `sysfs` and `/proc`, our configuration files,
and the code and documentation of the related projects (`docs/sources.md`).

Short glossary for this page:
- *GPU-bound* = the GPU is the limit (it runs at its top clock while the CPU waits); a faster CPU
  changes nothing. *CPU-bound* = the opposite.
- *DDR vote* = how much memory bandwidth a device asks for; the memory clock follows the largest
  votes. The GPU reads and writes most of its data in memory, so a slow memory clock slows it down
  even at its top GPU clock.
- *TSO* = the strict memory ordering of x86 code, which FEX has to imitate on ARM; its biggest
  single cost.
- *Internal resolution* = the resolution the game renders at; gamescope then scales the image to
  the panel (2400x1080).
- *FIFO / mailbox* = Vulkan presentation modes: FIFO waits for the next screen refresh (vsync),
  mailbox replaces the waiting image with the newest one.

## 1. What the measurements show

**Game sessions of 2026-10-05** (sampler log, one sample every 2 s, 5-minute averages):

- **GPU-bound with an idle CPU.** The GPU sat at its top clock (587 MHz) for whole windows. The
  big cores were mostly at 0.7-1.6 GHz and the prime core at its 845 MHz minimum.
- **So the memory clock was low.** Our GPU makes no DDR vote at all (see 3.2): the memory clock
  follows the CPU's votes, which come from our `sm8250.dtsi` CPU tables (4068000-5412000 kBps
  for the big cores at 1.3-1.7 GHz, 2188000 for the prime core at 845 MHz). That puts the memory
  at roughly 1017-1353 MHz, while OnePlus' Android kernel votes the top level (2092 MHz on
  LPDDR4X) for the GPU at 587 MHz. Inferred from the tables, not measured: the measurement needs
  root (`/sys/kernel/debug/interconnect/interconnect_summary`) and is step 1 of the plan.
- **Heat.** CPU 87-94 °C, GPU 79-83 °C, battery up to 42.5 °C. At a 41 °C battery `op8-thermal`
  is at level 1, at 42 °C level 2 (GPU capped at 525 MHz), and at 44.5 °C level 4 (GPU at
  305 MHz, about half). In Slime Rancher it reached level 4 (`compat-perf-audit.md` P5).
- **Resolution.** Games render at the panel's 2400x1080 unless set otherwise (Tomb Raider did,
  `compat-perf-audit.md` section 8): 2.6 million pixels per frame. The Steam Deck renders
  1280x800 (1.0 million) on a faster GPU; the Snapdragon guides for Winlator and GameHub suggest
  854x480 or 720p.

**The idle interface (r14, 57 min after boot, mostly in Steam's interface):**

- The GPU spent **92% of the time at 587 MHz** (2240 of about 2440 s, `trans_stat`): it barely
  leaves its top clock, even in menus.
- The CPU is about 24% busy (about two cores): `steamwebhelper` (Steam's interface), mangoapp,
  Xwayland and gamescope.
- This is heat and battery spent before the game starts, so the thermal guard steps in earlier
  (TODO 33).

## 2. Why other SM8250 handhelds get more

From the related projects' code and the Snapdragon guides:

1. **A lower internal resolution.** 720p or 480p on 1080p panels (Retroid Pocket 5: 1920x1080),
   upscaled.
2. **A GPU overclock and memory votes.** ROCKNIX and Armada run SM8250 with `9998-gpu-tuning`:
   - GPU steps up to 925 MHz (+57% over 587);
   - the GPU memory bandwidth vote;
   - ACD.

   Retroid and AYN devices also have fans. **We do not overclock** (`gaming-stack.md` section 7);
   the memory vote and ACD we can take with OnePlus' values.
3. **FEX presets without TSO.** DroidDeck, Nova-Deck and GameHub/Winlator offer a "performance"
   preset per game; Nova-Deck calls TSO "the largest single cost in the translation".
4. **Proton CachyOS ARM64.** Armada's default Proton on SM8250. It is based on a newer Proton
   Experimental and carries dxvk-sarek (DXVK for older GPUs, with asynchronous shader
   compilation).
5. **Android's own GPU driver.** On Android, KGSL scales the memory with the GPU load (bus levels
   tied to each GPU step), which our mainline kernel does not do yet (item 3.2).

So part of the "double" comes from the overclock, which stays out. The rest is within reach.

## 3. Module by module, ranked by expected gain

| # | Module | Loss found | Expected gain | Risk | Effort |
|---|---|---|---|---|---|
| 3.1 | Resolution (Steam, gamescope) | games render at native 2400x1080 | up to about 2x in GPU-bound games | none | settings |
| 3.2 | Kernel: GPU memory | no DDR vote from the GPU; memory follows the idle CPU | 10-40% in heavy scenes (to measure) | low, vendor values | kernel r15 |
| 3.3 | Heat | GPU at max even in menus; guard levels 2-4 cut the GPU to 525-305 MHz | keeps the 587 MHz in long sessions (avoids 0.5x) | none | mixed |
| 3.4 | FEX (x86 emulation) | TSO emulated in every game | up to 1.5-2x in CPU-bound games | crashes in some games | per game |
| 3.5 | Frame pacing at 90 Hz | FIFO rounds down to 45 / 30 fps | a game that can do 40 shows 40, not 30 | small | per game |
| 3.6 | Proton build | Valve's 11.0 (ARM64) only | newer FEX, dxvk-sarek async, fewer stutters | per game | compat tool |
| 3.7 | gamescope composition | rotation every frame on the GPU, uncompressed (A6xx) | 5-15% GPU time | low | userspace build |
| 3.8 | Kernel: GPU ACD | not enabled | lower power, so later throttling | low, vendor values | kernel |
| 3.9 | Native x86 games | x86 Mesa emulated under FEX | large for OpenGL games (Half-Life 34 fps) | medium | project |
| 3.10 | CPU placement | game threads may run on little cores | 5-20% in CPU-bound games | low | script |

### 3.1 Resolution (the biggest lever)

At 587 MHz the Adreno 650 has about 1.2 TFLOPS. A GPU-bound game scales almost with the pixel
count:

| Internal resolution | Pixels | vs. 2400x1080 |
|---|---|---|
| 2400x1080 (native) | 2.59 M | 1.0x |
| 1600x720 (Steam's 1280x720 with patch 9001) | 1.15 M | 2.25x fewer |
| 1200x540 (Steam's 960x540) | 0.65 M | 4x fewer |

What to do:
- Per game: Steam > the game > Properties > Game Resolution, plus Quick Access > Scaling Filter
  (FSR). gamescope already rotates and scales every frame, so the upscale costs little extra.
- Later, a default for every game, so a game never starts at native resolution.
- **SGSR instead of FSR** (Armada gamescope `0026`): Qualcomm's upscaler, built for Adreno and
  cheaper there. gamescope 3.16.29 already contains SGSR.

### 3.2 GPU memory bandwidth (kernel r15)

`patch-scan.md` item 4. The vendor values for our speed bin: 587 MHz votes 8368000 kBps (DDR
2092 MHz), 525-441.6 MHz 6220000, 400 MHz 4068000, 305 MHz 1804000. First measure the memory
clock during a GPU-bound game on r14, then compare r15 in the same scene.

### 3.3 Heat (sustained clocks)

- **The idle GPU** (TODO 33): 92% of the time at 587 MHz in menus. To find out: Steam's interface
  redrawing all the time, or `simple_ondemand` thresholds; then a lower idle clock (for example
  `min_freq`, or the governor's up threshold).
- **The X3's cooler at full power.** GameSir's manual: "Extreme Cold" needs a 9 V / 3 A charger
  plugged into the X3. Our 5 V limit (patch 0004) is only between the X3 and the phone, so the
  phone side does not change.
- **60 Hz for games under 60 fps** (TODO 21): less panel and composition work, and smoother
  30 fps.
- **The guard thresholds** (41/42/43/44.5 °C battery) were set without in-game measurements; to
  review with the logs of a long session once the above are in place.

### 3.4 FEX presets per game

The Windows FEX inside Proton ARM64 reads `FEX_*` environment variables (checked in FEX's
`Source/Windows/ARM64EC/Module.cpp`: `LoadConfig(..., _environ)`), so a preset goes in a game's
Launch Options. DroidDeck's presets (`FexPreset.kt`):

- **Performance:** `FEX_TSOENABLED=0 FEX_VECTORTSOENABLED=0 FEX_MEMCPYSETTSOENABLED=0
  FEX_HALFBARRIERTSOENABLED=0 FEX_X87REDUCEDPRECISION=1 FEX_MULTIBLOCK=1`.
- **Performance + TSO:** the same with `FEX_TSOENABLED=1`, the safer middle step.
- **.NET (CoreCLR) games:** they need the Stability preset (full TSO, `FEX_MULTIBLOCK=0`).

Nova-Deck notes `STEAM_FEX_TSOENABLED=0` as Proton's own switch. Only CPU-bound games gain (high
CPU use, GPU below its top clock); a GPU-bound game gains nothing. The decky plugin could offer
the presets per game, like the frame generation switch.

### 3.5 Frame pacing at 90 Hz

With FIFO on a 90 Hz panel a frame waits for the next refresh: a game that renders at 40 fps
shows frames every 2 or 3 refreshes, 45 or 30 fps, often 30. Per game:
`MESA_VK_WSI_PRESENT_MODE=mailbox %command%` (gamescope composes the newest frame, so no
tearing), or the game's own vsync off. Together with the 60 Hz mode (3.3) and the frame limit
(TODO 25), this gives an even 30, 40 or 60.

### 3.6 Proton CachyOS ARM64

`cachyos-11.0-20261005-slr` has an `arm64` build, based on Proton Experimental 11.0-20261001
(newer FEX than Proton 11.0-2), with dxvk-sarek (1.x line, which does not need
`storageBuffer8BitAccess`, with asynchronous shader compilation) and the low-latency DXVK/VKD3D
forks. dxvk-sarek is chosen per game with `PROTON_DXVK_SAREK=1` (its README: for GPUs without
proper Vulkan 1.3 support; it is the `async` branch, so not for games with anti-cheat or
multiplayer). Armada instead patches the DXVK probe so that a GPU without
`storageBuffer8BitAccess` (ours) gets the older DXVK on its own
(`build_files/patch-proton-cachyos-dxvk-probe.py`). Installed as a compatibility tool in the
container (`~/.local/share/Steam/compatibilitytools.d/`), per game, nothing in the system
changes.

### 3.7 gamescope composition

Every frame is rotated on the GPU (the SM8250 display has no inline rotator). On A6xx Turnip
refuses UBWC for storage images, so gamescope's compute composite writes an uncompressed
full-screen image each frame. Nova-Deck's `0019` (fragment-shader composite, ported to 3.16.29)
keeps it compressed and makes the rotation free on a tiled GPU. Later: the SDE rotator
(`patch-scan.md` item 7) for no composition at all in full-screen games.

### 3.8 GPU ACD

`patch-scan.md` item 5, vendor values. Less power at the same clocks, so less heat in long
sessions.

### 3.9 Native x86 Linux games

They run with an x86 Mesa emulated by FEX (`/run/gfx`). Every OpenGL call goes through the
emulator: Half-Life ran at about 34 fps with low CPU and GPU use. Nova-Deck uses FEX's thunks,
which hand the graphics calls to the real ARM64 drivers. A separate project; the Windows build
through Proton ARM64 is the workaround meanwhile.

### 3.10 CPU placement

The prime core (2.84 GHz) is about 1.2x a big core and 3-4x a little core. Nova-Deck pins games
or gamescope per game (`cores`, `nice`), SteamOS-ARM-Handhelds raises `uclamp.min` for game
threads; both are open questions for EAS on this chip. Only for CPU-bound games.

### Checked, no major loss

- **Kernel configuration:** no KASAN, lockdep or similar costly debug options. PAC and BTI are not
  used by the Cortex-A77. KPTI is off on this core. `HZ=250`, full preemption, NTSYNC and MGLRU
  are in place. The Spectre-BHB mitigation (`Mitigation: CSV2, BHB`) costs a little per system
  call; not worth giving up.
- **Mesa:** 26.2.3 (Fedora 44), recent.
- **CPU and GPU governors:** `schedutil` at 1 ms, GPU polling 16 ms, `sched_util_clamp_min_rt_default`
  0.
- **System cache (LLCC):** its driver is bound (`9200000.system-cache-controller`), and our GPU
  sits behind an MMU-500, the path where mainline gives it its cache slices.
- **Memory:** 11.4 GiB and 17 GiB of zram. One spike, 102 MB free and 4.3 GB in swap, on
  2026-10-05 at 23:45; not a constant limit.

## 4. The plan: one test game, one change at a time

Tomb Raider (2013), the same scene, MangoHud's frame time log on (average and 1% lows),
battery and temperatures from the sampler:

1. **Baseline on r14:** native resolution, Low preset. During play, one root read of
   `interconnect_summary` to see the memory clock (this tests the 3.2 inference).
2. **Resolution:** 1600x720, then 1200x540, with FSR (3.1).
3. **Kernel r15** (memory votes) at the best resolution of step 2 (3.2).
4. **The X3 cooler** at full power, on a 9 V charger into the X3 (3.3).
5. **Present mode** mailbox, and 60 Hz once TODO 21 allows it (3.5).
6. **Proton CachyOS ARM64** (3.6), then a CPU-bound game (a Unity or Unreal title with the
   CPU high) with the FEX presets (3.4).
7. **gamescope with the fragment composite and SGSR** (3.7), then ACD (3.8).

Each step is kept only if it measures better, and its numbers go into `gaming-stack.md`.

There is no clean Tomb Raider baseline yet: the numbers of 2026-10-05 (about 25 fps on Medium,
35-45 on Low) were taken with frame generation on, which costs GPU time and counts generated
frames. Rough estimate: about 2x from the resolution alone (1600x720) if the game stays
GPU-bound. The memory votes, the cooler and the composite should then keep that rate up in long
sessions, where it now falls. These are estimates; the measurements decide.

## Sources

- Sampler log `sample-0050` (2026-10-05) and read-only checks on r14 (2026-10-06).
- Vendor GPU bus table: LineageOS `android_kernel_oneplus_sm8250`, `kona-gpu.dtsi`,
  `kona-v2-gpu.dtsi`.
- DroidDeck FEX presets: `app/src/main/java/com/droiddeck/launcher/core/FexPreset.kt`.
- FEX environment config in the Windows build: `Source/Windows/ARM64EC/Module.cpp`,
  `Source/Common/Config.cpp` (FEX-Emu/FEX).
- Nova-Deck: `docs/windows-games-fex.md`, `docs/per-game-perf.md`, gamescope patch `0019` and its
  notes.
- Armada: `system_files/usr/libexec/armada/device-env` (Proton CachyOS default on SM8250),
  `build_files/patch-proton-cachyos-dxvk-probe.py`, gamescope `0026` (SGSR).
- [Proton CachyOS releases](https://github.com/CachyOS/proton-cachyos/releases)
  (`cachyos-11.0-20261005-slr`, arm64 build).
- Snapdragon guides: [Winlator settings](https://gamehelptech.com/setup-winlator-for-maximum-fps/),
  [GameHub settings](https://gamehelptech.com/gamehub-windows-emulator-setup-and-best-settings/).
- GameSir X3 Pro cooler and charger: [manual](https://gamesir.com/support/manuals/gamesir-x3-pro).
