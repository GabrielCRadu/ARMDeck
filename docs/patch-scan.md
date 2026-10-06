# Patch scan of the related projects (TODO 30)

Done on 2026-10-06, against what the OnePlus 8 runs today: kernel 6.16.7 (Xo666 tree, our
package `r13`, patches 0001-0011) and gamescope 3.16.29 (patches 9001-9003). Every kernel and
userspace patch set that touches the SM8250 (Snapdragon 865) or our stack was read. For each
patch the questions were: what does it fix, does our 6.16 tree have the bug (checked in the
Xo666 source, not assumed), does it fit the OnePlus 8, and is it safe for the hardware
(checked against the OnePlus/LineageOS vendor kernel where it touches hardware values).

Nothing in this document has been built or flashed yet. The ranking is a proposal.

Short glossary for this page:
- *DSP* = the audio co-processor (ADSP) that runs the sound pipeline; Linux talks to it through
  the `q6afe`/`q6core` drivers.
- *DSI* = the link between the SoC and the panel. Our panel is a *command-mode* panel: it keeps
  its own copy of the picture and only gets new frames when the SoC sends them, timed by the
  panel's *TE* (tearing effect) signal.
- *DCS* = the small commands sent to the panel over DSI (brightness, for example).
- *vblank timestamp* = the time the kernel reports for "the panel just started a new frame";
  gamescope uses it to decide when to send the next frame.
- *ACD* = Adaptive Clock Distribution: the GPU briefly slows its clock when its supply voltage
  dips, so it can run with a smaller voltage safety margin.
- *UBWC* = Qualcomm's lossless framebuffer compression; less memory traffic for the same image.
- *DDR vote* = how much memory bandwidth a device asks for; the memory clock follows the sum of
  the votes.

## What was scanned

| Project | Revision read | What it has for us |
|---|---|---|
| [ROCKNIX](https://github.com/ROCKNIX/distribution) `projects/ROCKNIX/devices/SM8250` | `18aded589851` (kernel 7.2) | 41 kernel patches, kernel config, udev and PipeWire files |
| [pmaports SM8250 kernel](https://gitlab.postmarketos.org/soc/qualcomm-sm8250/linux) | tag `sm8250-7.2.0` (`71f4068cb254`) | 69 commits on top of Linux 7.2, mostly Xiaomi and Lenovo tablets |
| [Armada](https://github.com/armada-os/armada) | `5ea76094a429` (kernel 7.2.6) | 183 kernel patches (with a provenance file), 26 gamescope, 8 MangoHud, 3 Mesa, 2 FEX patches |
| [Nova-Deck os-build](https://github.com/Nova-Deck/os-build) | `325dfde9a380` (kernel 7.2) | 96 kernel patches (with a provenance table), 16 gamescope, 6 MangoHud, 3 FEX patches |
| [pocknix-os](https://github.com/shuuri-labs/pocknix-os) `kernel/sm8250` | `9b8f770862ed` | 46 kernel patches (mostly the ROCKNIX set), gamescope, MangoHud, FEX patches |
| [SteamOS-ARM-Handhelds](https://github.com/hashtagbasit/SteamOS-ARM-Handhelds) | `682281c0d823` | kernel patches for SM8350/8550/8650/8750, gamescope and Mesa patches (first read 2026-10-05) |
| OnePlus 8 kernel forks (WuerfelDev `6.17.0-instantnoodle`, ObiKeahloa `6.17.0`) | branch heads | no change since their last cross-check (December 2025 and January 2026) |
| [DroidDeck](https://github.com/Droid-Deck/DroidDeck) | commits of 2026-10-06 | Android-side changes; the Adreno 6xx one matches what we already do |
| armada-rockchip, miARMa | | the repositories hold only a README; their work is in release images |

## Ranked: worth taking

### Tier 1: small, low risk, and they match problems we have measured

**1. Audio DSP readiness at boot (fixes TODO 16 at the root).**
Nova-Deck `0893-asoc-qdsp6-q6core-only-an-unsupported-get-state-means-assume-up.patch` and
`0895-asoc-qdsp6-q6afe-wait-for-the-dsp-audio-services-before-probing.patch`, written by
Philippe Simons (ROCKNIX) for Nova-Deck issue #94.
- Their log is ours, line for line: `cmd = 0x100f4 returned error = 0x16`, `Unknown cmd 0x100f4`,
  `AFE failed to vote (3)`, then a probe failing with -110. About 1 boot in 5 has no sound here.
- `0895` makes `q6afe` wait until the DSP reports its audio services up (the check the vendor
  audio stack does, "AVS might not be fully up"), and defers otherwise; it also answers the
  error reply to the vote instead of letting the caller time out. `0893` fixes the readiness
  check, which reported "ready" exactly when the DSP did not answer.
- In our 6.16 tree: `q6core_is_adsp_ready()` exists and has no caller, `__q6core_is_adsp_ready()`
  clears `get_state_supported` first, and `q6afe_callback()` logs "Unknown cmd" for the vote
  error. The patches' context lines match our files.
- Hardware safety: no hardware values; it only changes when audio drivers start.
- Our `armdeck-audio-recover` service stays as a safety net.
- Test: about 20 boots; every one must have `/proc/asound/cards` and the new line
  "DSP audio services ready after N ms".

**2. DSI link clocks left alone during panel commands (likely TODO 20).**
Nova-Deck `0420-msm-dsi-keep-link-clocks-up-while-display-active.patch` (Philippe Simons, seen
on the SM8250 Pocket Max).
- Every DCS command (every brightness step) re-set the DSI clock rate and switched the link
  clocks on and off while frames were streaming. That cuts the clock to the DSI serializer
  mid-frame: a FIFO underflow.
- If the brightness command races gamescope's first modeset, the PLL is left in a bad state and
  the panel stays black until a reboot.
- Our TODO 20 is exactly this:
  - `dsi_err_worker: status=4` (`DSI_ERR_STATE_FIFO`) in bursts during Steam's auto-dim;
  - coloured flicker when the brightness slider moves fast;
  - `write .../brightness failed, errno = 110` (the brightness command timed out).
- Our `msm_dsi_host_xfer_prepare()` is the pre-patch code: `link_clk_set_rate()` +
  `link_clk_enable()` on every transfer.
- Hardware safety: clock handling only. The risk is a black screen (a software fault, cleared by
  a reboot), so it is tested as a boot image first, as usual.
- Test: Steam's auto-dim and fast slider moves with frames streaming; no `dsi_err` lines and no
  flicker.

**3. Real vblank timestamps on command-mode panels.**
Armada `0078-drm-msm-dpu-fix-vblank-timestamps-on-command-mode-panels.patch` (PR #629); Nova-Deck
carries the same patch as `0390`.
- On a command-mode panel the scanout position came from `INTF_LINE_COUNT`, the counter of the
  video timing engine, which does not run in command mode. So the position was constant, and
  the vblank timestamp was "now" instead of the panel's last TE.
- Page flip events carry that timestamp, and gamescope paces its frames from it.
- On SM8250 the display controller is DPU 6.0, so our tree takes this path (`has_intf_te` is set
  for every DPU from 5.0 on). Checked in our `dpu_encoder_phys_cmd.c`; the tear-check registers
  the patch reads are already defined in our `dpu_hw_intf.c`.
- This may be part of why gamescope's own frame limiter gave input delay and half the requested
  rate with DXVK (the reason for our patch 9003).
- Hardware safety: it only reads registers.
- Test: `/sys/kernel/debug/dri/0/...` vblank timestamps against TE; frame pacing with MangoHud's
  frame time graph; then retry gamescope's own limiter.

**4. A memory bandwidth vote for the GPU.**
The bandwidth part of ROCKNIX `9998-gpu-tuning.patch`: `interconnects` +
`interconnect-names = "gfx-mem"` on the GPU node and `opp-peak-kBps` on each GPU frequency.
Only the 305-587 MHz steps we already have; **none of its 700-925 MHz overclock steps**.
- In our tree the GPU never asks for memory bandwidth:
  - its node has no interconnect path;
  - the GPU microcontroller sends a single "off" vote for the A650 (`a650_build_bw_table()`,
    "TODO: bus scaling").
- So the memory clock follows only the CPU's votes, which scale with the busiest big core.
  Example: at 1.5 GHz on the big cores, the memory runs at 1017 MHz, half of 2092 MHz.
- In a GPU-bound game with an idle CPU, or when `op8-thermal` caps the big cores, the GPU loses
  memory bandwidth as a side effect. Tomb Raider (GPU at 587 MHz, SoC at 87 °C) is that case.
- Vendor check (LineageOS `kona-gpu.dtsi`, `kona-v2-gpu.dtsi`, speed bin 0):
  - 587 MHz votes bus level 11;
  - 525-441.6 MHz vote level 9;
  - 400 MHz votes level 7;
  - 305 MHz votes level 3.
- For LPDDR4X (the vendor's `ddr7` table; the OnePlus 8 has LPDDR4X, the 8 Pro LPDDR5) those
  levels are 2092, 1555, 1017 and 451 MHz x 4 bytes. That gives 8368000, 6220000, 4068000 and
  1804000 kBps.
- ROCKNIX's numbers are the same values divided by 1.024, and land on the same memory clock
  steps. We would use the vendor's exact values, written like the CPU table in our `sm8250.dtsi`.
- Hardware safety: the votes stay inside the vendor's own table for these frequencies. The
  memory clock cannot go above its own maximum. The cost is power, which the thermal guard
  watches anyway. The memory type is to be confirmed on the phone (read-only) before building.
- Test: Tomb Raider fps, power and temperatures before and after, the same scene and settings;
  `/sys/kernel/debug/interconnect/interconnect_summary` during play.

### Tier 2: worth doing after tier 1, larger or less certain

**5. GPU ACD.**
The ACD part of ROCKNIX `9998-gpu-tuning.patch`: `qcom,opp-acd-level` on each GPU frequency and
`qcom,qmp = <&aoss_qmp>` on the GMU node.
- The values are identical to the vendor's: `0x802b5ffd` for 525 MHz and up, `0xa02b5ffd` below.
- Our tree already has the ACD code (`a6xx_gmu_acd_probe()`).
- Expected gain: less power at the same clocks. Risk: GPU instability (hangs), not damage.
- Done alone, after item 4, so each change is measured on its own.

**6. gamescope: composite with a fragment shader.**
Nova-Deck gamescope `0019-rendervulkan-fragment-shader-composite.patch` (sunshineinabox), already
ported by Nova-Deck to gamescope 3.16.29, our version. Opt-in (`--composite-graphics` or
`GAMESCOPE_COMPOSITE_GRAPHICS=1`).
- Turnip does not allow UBWC on storage images before A7xx. So on our A650, gamescope's compute
  composite writes an uncompressed full-screen image for every frame.
- The fragment-shader path writes a compressed one, and on a tiled GPU like Adreno the rotation
  to our portrait panel comes for free.
- This targets the cost measured in TODO 33 (gamescope and the GPU busy even at the idle UI).
- Userspace only, no hardware risk.

**7. Rotation in the display hardware (SDE rotator).**
ROCKNIX `0201-drm-msm-dpu-sde-rotator-helper.patch` + `0202-drm-msm-dpu-whole-output-plane-rotation.patch`
(Nova-Deck `0385`), plus the SM8250 QoS fixes ROCKNIX/Nova-Deck pair with it (Nova-Deck `0380`,
values from the vendor device tree).
- The SM8250 display has no inline rotator, so today gamescope rotates every frame on the GPU.
- With the offline rotator, a game's frame can go to the screen rotated by the display block.
- On an SM8650 with inline rotation, Nova-Deck measured 0 ms of gamescope GPU time in game
  (21% before) and 834 mW less.
- Large: about 50 KB, written for 7.2 (its signatures follow 7.2's msm), new as of
  2026-09-21. Try item 6 first: it may get most of the gain for little work.

**8. Steam's colour temperature and night mode on ARM64.**
Armada gamescope `0018-steamcompmgr-arm64-virtual-white.patch`, Nova-Deck `0002` (night mode atom)
and `0016` (virtual white).
- The ARM64 Steam client packs the two floats of the white point as one 64-bit element, so
  gamescope reads y = 0 and ignores the slider.
- Not checked on our phone yet. If the sliders do nothing here, this is the fix (final goal 5:
  every menu works).

**9. USB-C power role swap termination (X3 pass-through).**
ROCKNIX `0018-usb-typec-qcom-pmic-typec-switch-termination-on-pr-swap.patch` (Nova-Deck `1050`),
written from the vendor `smb5` swap sequence.
- During a swap from source to sink it keeps the PMIC from seeing a detach (vSafe0V bypass, CC
  termination held).
- Pass-through already works in the "charger into the X3 first" order (TODO 17). This might help
  the other order, where a software re-seat only charged for 2-3 s.
- Touches Type-C registers (no voltage values). Needs a review against `smb5-lib.c` before use.

**10. DPU resource cleanup.**
Armada `0010-msm-resource-cleanup.patch` (seven patches by JS Deck, with Armada's fix for an
uninitialised pointer in the ROCKNIX copy).
- After a failed reservation of display blocks, every later commit could fail.
- Robustness only; worth it if mode changes (60/90 Hz, TODO 21) ever leave a garbled or black
  screen again.

### Tier 3: leads, measure first

- **FEX helpers (TODO 8):** `0504-Enable-64-bit-processes-to-use-compat-input-syscalls.patch`
  and `0505`/`1062-arm64-emulate-unaligned-atomics.patch` (Armada also `0505a`).
  - FEX turns on `PR_SET_COMPAT_INPUT` for 32-bit guests when the kernel has it (checked in
    `FEXInterpreter.cpp`). Without it, a 32-bit x86 game that reads controller events directly
    gets the 64-bit event layout.
  - Only for 32-bit native games with input problems, and for unaligned atomics without LSE2.
    The atomics patch is 71 KB.
- **Audio periods:** ROCKNIX `0012` (smaller q6asm period limits), `0100` (S16 forced only for
  compressed playback), and its `quantum` script that pins PipeWire's quantum to 1024. Only if
  we see underruns.
- **THP for GPU buffers:** Nova-Deck `0220` (Rob Clark, v2 under upstream review, "more than 2x"
  on an allocation-bound benchmark). Probably needs the newer drm shmem huge-page support (after
  6.16); check when we move to a newer base.
- **USB polling override:** `0506-usbcore-add-interrupt-interval-override.patch` (Armada). Only if
  the X3's own polling interval turns out to be slow (gamesir-linux-tools now shows a
  controller's real report rate).
- **Suspend work:** Armada `0204` (tsens lower thresholds masked across suspend) and
  `0523`-`0526` (regulator sleep states for s2idle). Only if we move from `op8-standby` to real
  suspend. The regulator ones need a rail-by-rail vendor review.
- **gamescope:**
  - Armada `0027` (clock-anchored frame limiter), if we go back to gamescope's own limiter after
    item 3.
  - Nova-Deck `0005` (Steam's update dialog never gets focus, black screen for the whole update),
    if we see that.
  - Nova-Deck and Armada `0020`+`0021` (libliftoff plane z-order on msm), with item 7.
- **SSBS for Wine** (DroidDeck #328): Wine's ARM64 signal return leaves speculative store bypass
  disabled; "gain unproven". Research only.

## Rejected

| Patch | Why not |
|---|---|
| GPU frequencies above 587 MHz (ROCKNIX `9998` 700-925 MHz steps, Nova-Deck `1120`) | Our rule ([gaming-stack.md](gaming-stack.md) section 7): no GPU table above the vendor's 587 MHz. Items 4 and 5 take only the vendor-matching parts of `9998`. |
| RTC offset in PMIC memory (ROCKNIX `0102`, Nova-Deck `1130`) | It writes 4 bytes into the PM8150's SDAM 2 at `0xbc`. The vendor kernel lends SDAM 2 to the fuel gauge (`kona-pmic-overlay.dtsi`, `fg_sdam`; `qpnp-fg-gen4.c` keeps cycle counts and learned capacity at `0x81`-`0x98`). Nothing proves `0xbc` is free in OnePlus' firmware, and TODO 24 is already handled (Steam waits for NTP). |
| PM8150B charger driver (ROCKNIX/pocknix `0011` and its follow-ups, pmaports) | Still excluded. Progress noted: the ROCKNIX/pocknix version now uses the PM8150B float-voltage formula (3.6 V + 10 mV per step, clamped to 4.45 V) and sets the charge current, fixing bugs 1 and 2 of hardware-safety.md; it still pets the watchdog at `0x643`. A full audit is a separate task, if faster charging becomes a goal (today the PMIC's default limits give about 0.76-0.9 A into the battery). |
| `0001-msm-dsi-restore-wide_bus-bpp-calculation.patch` | Only changes video-mode panels with wide bus; ours is command mode, and SM8250's DSI has no wide bus. |
| Inline rotation (Armada `0066`, Nova-Deck `0340`), LUTDMA colour patches | SM8550 and newer only; SM8250 has no inline rotator and no LUTDMA block. |

## Already in our tree, or not for 6.16

- msm GPU queue priorities: our `0011` (same fix as Armada `0619` and SteamOS-ARM-Handhelds `0012`).
- MDSS core reset and the DSI `refgen` regulator (pmaports SM8250): already in Xo666's `sm8250.dtsi`.
- ROCKNIX `0505-msm_gem-lock-before-put_iova_spaces.patch`, SteamOS-ARM-Handhelds
  `0009-drm-msm-bound-the-fence-wait-in-vm-close.patch`: fix code from the VM_BIND rework
  (Linux 6.17 and later); our 6.16 `msm_gem_close()` does not have it.
- SteamOS-ARM-Handhelds `0003-drm-msm-a6xx-fix-stale-rpmh-votes-after-suspend.patch`: fixes an
  inverted `GMU_STATUS_FW_START` test that our 6.16 `a6xx_rpmh_stop()` does not have.
- DroidDeck "Adreno 6xx support" (#320): forces DXVK 2.7.1 because Turnip on A6xx lacks
  `storageBuffer8BitAccess`; the same choice as our TODO 6.
- `pocknix`'s mangoapp redraw pacing: our mangoapp patch 5 does the same.

## Suggested order

1. Kernel test image `r14` with items 1, 2 and 3 (all software-only, no hardware values),
   booted with `fastboot boot` before anything is flashed. Measure: sound on every boot, no
   `dsi_err` during brightness changes, frame pacing.
2. Kernel `r15` with item 4 alone (bandwidth votes), Tomb Raider before and after; then item 5
   (ACD) alone.
3. gamescope with item 6 (fragment composite), opt-in, measured at the idle UI and in a game
   (TODO 33).
4. Item 8 after checking whether Steam's colour sliders work here; items 7, 9 and 10 when their
   turn comes.
