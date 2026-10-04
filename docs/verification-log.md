# Verification Log

Every load-bearing claim in [`Gaming Mainline OnePlus 8.md`](https://github.com/GabrielCRadu/ARMDeck/blob/3560179/Gaming%20Mainline%20OnePlus%208.md),
checked against primary sources. The original document (an early research draft in
Romanian, no longer in the repository tree; the link points to its last version in the git
history) is research output with no citations to working code; this log records what survived
contact with the actual kernel tree, device tree, and package repositories.

**Target device:** OnePlus 8, IN2013 (Europe and Asia), codename `instantnoodle`, SM8250 (kona).
**Intended use:** dedicated Linux handheld. Android wiped. No modem/calls/SMS required.

**All checks performed 2026-08-24.** Anything marked OPEN needs hardware to settle.

> **Read section 9 first (2026-10-01).** A pre-flash audit with the phone in hand found that
> several conclusions below are wrong: both "charger port" patches were inert because neither
> the Xo666 nor the ObiKeahloa tree has a PM8150B charger or fuel-gauge driver; the only
> community driver (WuerfelDev / postmarketOS SM8250) programs about 4.87 V float voltage on
> this battery; and the documented install flow could not have worked. Earlier text is kept
> as the historical record, with this banner as the correction.

Verdict key: **CONFIRMED** · **WRONG** · **PARTIAL** - right in outline, wrong in detail · **OPEN** - undecidable without the device.

---

## 1. Device enablement

### 1.1 `instantnoodle` is supported in postmarketOS - **WRONG**

The doc's install flow ([line 141](https://github.com/GabrielCRadu/ARMDeck/blob/3560179/Gaming%20Mainline%20OnePlus%208.md#L141)) says to run `pmbootstrap init`
and choose codename `instantnoodle`. That fails today: there is no such device package.

pmaports `device/` contains exactly these OnePlus ports:

| Package | Device |
|---|---|
| `device/community/device-oneplus-enchilada` | OnePlus 6 |
| `device/community/device-oneplus-fajita` | OnePlus 6T |
| `device/testing/device-oneplus-bacon` | OnePlus One |
| `device/testing/device-oneplus-billie2` | Nord N100 |
| `device/testing/device-oneplus-guacamole` | OnePlus 7 Pro |
| `device/testing/device-oneplus-instantnoodlep` | **OnePlus 8 Pro** |
| `device/testing/device-oneplus-kebab` | **OnePlus 8T** |

The Pro and the 8T are packaged. The plain OnePlus 8 is not. The doc's parenthetical
- "`instantnoodle` (sau `instantnoodlep` pentru varianta Pro)" - has the support
situation backwards.

*Source:* pmaports GitLab API, `repository/tree?path=device/{main,community,testing}`.

### 1.2 Upstream mainline has an SM8250 OnePlus device tree - **WRONG**

`arch/arm64/boot/dts/qcom` in torvalds/linux master has 628 files. The SM8250 boards
present are: `hdk`, `mtp`, `samsung-r8q`, `samsung-x1q`, `sony-xperia-edo-pdx203`,
`sony-xperia-edo-pdx206`, `xiaomi-elish-{boe,csot}`, `xiaomi-pipa`. **No OnePlus SM8250
board exists upstream at all** - not the 8, not the 8 Pro, not the 8T.

Even postmarketOS's own SM8250 kernel fork (`soc/qualcomm-sm8250/linux`, tag `sm8250-7.1.0`,
described as "Mainline kernel fork for SM8250") carries only `sm8250-oneplus-instantnoodlep.dts`
and `sm8250-oneplus-kebab.dts`.

So "mainline support" for this device means *a fork of mainline*, not mainline. This
distinction runs through the whole document and is the single biggest correction.

*Source:* GitHub contents API on torvalds/linux; pmOS GitLab API on the SM8250 kernel fork.

### 1.3 The device boots mainline anyway - **CONFIRMED**

The postmarketOS wiki page for `oneplus-instantnoodle` reports `booting = yes`,
`packaged = no`, `category = testing`, `pmoskernel = 6.17.0`, and critically
`status_3d = Y`. Maintainers listed: ObiKeahloa, Xiaoou.

The port lives in at least **three** out-of-tree trees, and they do not agree with each other:

- [`github.com/Xo666/mainline-instantnoodle`](https://github.com/Xo666/mainline-instantnoodle) - branch `6.16.7`, pushed 2026-01-14, single branch. **This is the tree audited as `reference/dts/sm8250-oneplus-instantnoodle.dts`.** Authored by `Xiaoou <xo666@postmarketos.org>`.
- [`gitlab.com/ObiKeahloa/linux`](https://gitlab.com/ObiKeahloa/linux/-/tree/sm8250/v6.13-instantnoodle) - branch `sm8250/v6.13-instantnoodle`. Its `instantnoodle`-specific commit ("Initial support & bringup") is dated 2025-10-28 - the oldest of the three. Pulled and saved as `reference/dts/sm8250-oneplus-instantnoodle-obikeahloa.dts`.
- [`gitlab.postmarketos.org/WuerfelDev/linux-sm8250`](https://gitlab.postmarketos.org/WuerfelDev/linux-sm8250/-/tree/6.17.0-instantnoodle) - branch `6.17.0-instantnoodle`, the account's **default branch**, last commit 2025-12-11. **This is the tree the wiki Infobox's `pmoskernel = 6.17.0` actually points to** - not either of the two forks originally treated as "the" sources in this log. Pulled and saved as `reference/dts/sm8250-oneplus-instantnoodle-wuerfeldev.dts`.

**This is the project's foundation, and it's fragmented.** No single tree currently has
everything working - see the divergence table below. Whoever builds this has to pick a tree
knowing what they're trading away, not assume "the mainline fork" is one coherent thing.

#### Fork divergence: what actually works, by tree

Directly diffed all three `reference/dts/` files node by node (Xo666 `6.16.7`, WuerfelDev
`6.17.0-instantnoodle`, ObiKeahloa `sm8250/v6.13-instantnoodle`, all pulled 2026-08-24).

| Feature | Xo666 `6.16.7` | WuerfelDev `6.17.0-instantnoodle` (wiki's tracked kernel) | ObiKeahloa `v6.13-instantnoodle` |
|---|---|---|---|
| **GPU (`&gpu`)** | `status = "okay"`, **zap-shader node configured** with `firmware-name = "qcom/sm8250/OnePlus/a650_zap.mbn"` | **`status = "disabled"`, unconditionally** | `status = "okay"`, but **no zap-shader node at all anywhere in the file** - the mandatory signed-firmware wiring the doc's own §3 calls a hard prerequisite is simply absent |
| **Charger (`&pm8150b_charger`)** | Node does not exist | `status = "okay"`, wired to ADC channels | Board DTS override block says `status = "okay"`, near-identical wiring to WuerfelDev - **but corrected 2026-08-24: this tree's own `pm8150b.dtsi` never defines the `pm8150b_charger`/`pm8150b_fg` labels, so the unmodified tree fails to compile at all (`dtc` "Label or path ... not found"). Text-only read, not compile-checked - see the correction note above and the later "reverse direction" log entry.** |
| **USB-C SBU mux / orientation-switch** | `status` unset (defaults **okay**); has both `mode-switch` and `orientation-switch`; endpoint wired to `pm8150b_typec_sbu_out` | `status = "disabled"`, comment reads "Currently unconfigured"; endpoint is an empty stub | Same as WuerfelDev: `status = "disabled"`, identical "Currently unconfigured" comment - the two trees share this block near-verbatim, suggesting one was based on the other |
| **Fuel gauge chip** | External `ti,bq27411` @ i2c16 addr 0x55, bus `status = "okay"` | External `ti,bq27541` present but bus `status = "disabled"` (vestigial) - real gauge is `&pm8150b_fg` | Same vestigial `bq27541`/disabled-bus pattern as WuerfelDev; real gauge is `&pm8150b_fg`, `status = "okay"` |
| **Firmware path convention** | `qcom/sm8250/OnePlus/<name>.mbn` (capital O, `.mbn`) | Not directly checked (no zap node) | **`qcom/sm8250/oneplus/<name>.mdt`** - lowercase directory, `.mdt` extension instead of `.mbn`. Firmware blobs packaged for the other two trees are not directly usable here without repackaging. |
| **Panel `compatible` string** | `samsung,amb655uv01` | `oneplus,instantnoodle-panel` | `oneplus,instantnoodle-panel` (matches WuerfelDev, not Xo666) |
| **Touchscreen, NFC, flash LED** | All present, matches §2 below | Same nodes present | Same nodes present |

**The practical read: as of 2026-08-24, no tree cleanly has GPU, charging, and clean USB-C
orientation switching all at once - ObiKeahloa comes closest on paper but with an asterisk.**
Xo666 gives you graphics (existential for a gaming project, and the only tree with a *complete*
zap-shader wiring) and a correctly-wired SBU mux, but zero charging support. WuerfelDev and
ObiKeahloa both have working chargers and PMIC fuel gauges, and ObiKeahloa's `&gpu` node is not
disabled - but neither has anything resembling Xo666's zap-shader block, and firmware loading
for the Adreno GPU is a hard, signed-blob prerequisite (§3). Whether the kernel's `msm_gpu`/`a6xx`
driver falls back to a sane default firmware path when the DT omits `firmware-name` is a genuine
unknown, not something this log can resolve by reading device trees - it needs testing on
hardware. Until that's tested, **treat ObiKeahloa's GPU support as unconfirmed, not working**,
despite `status = "okay"`; Xo666 remains the only tree with *demonstrated* graphics. WuerfelDev's
`status_3d = Y` on the wiki, given its DTS has the GPU node hard-disabled, is best read as
describing the device in general (i.e. some tree boots 3D) rather than describing that specific
kernel snapshot - the wiki's per-feature table is not a description of one coherent, buildable
kernel.

**Correction (2026-08-24, added after actually cloning and compiling ObiKeahloa's tree - see the
"reverse direction" entry later in this document, in section 4 of the log's chronological
updates):** the charger/fg half of "ObiKeahloa comes closest on paper" above was itself wrong, not
just the GPU half. This was written from reading the saved `reference/dts/` text, where
`&pm8150b_fg`/`&pm8150b_charger` override blocks do appear with `status = "okay"`. Actually cloning
and building the tree found that ObiKeahloa's own `pm8150b.dtsi` never defines those labels at all
- the unmodified tree fails `make dtbs` outright with "Label or path pm8150b_fg not found" /
"Label or path pm8150b_charger not found". So as shipped, ObiKeahloa's charger support was not
"working," it was not buildable. A patch fixing this (alongside porting Xo666's zap-shader) exists
now at `pmaports/linux-oneplus-instantnoodle-obikeahloa/` - see the later log entry for full
details. The lesson generalizes: this document has now been burned twice by treating a DTS
override block's presence as proof it resolves against something real, instead of compiling to
check.

#### A fourth resource: prebuilt firmware + ALSA package

[`github.com/Xo666/linux-oneplus-instantnoodle`](https://github.com/Xo666/linux-oneplus-instantnoodle)
(same author, separate repo, pushed 2026-01-20) is **not a kernel tree** despite its README
saying "Mainline Kernel, Firmware package, ALSA configs" - it contains only
`firmware-oneplus-instantnoodle/usr/lib/firmware/` and `alsa-oneplus-instantnoodle/usr/lib/`.
The firmware directory actually contains the proprietary signed blobs this log's §3 says must
be extracted from an OxygenOS dump: `a650_zap.mbn`, `adsp.mbn`, `cdsp.mbn`, `slpi.mbn`,
`venus.mbn`, plus the open `a650_gmu.bin`/`a650_sqe.fw`.

Two things worth flagging before using it:

- **Path mismatch.** The repo nests the OnePlus blobs under `qcom/sm8250/OnePlus8/`, but the
  DTS's `firmware-name` properties (confirmed by grepping `reference/dts/`) expect
  `qcom/sm8250/OnePlus/adsp.mbn` etc. - no digit. Copy or symlink `OnePlus8/` to `OnePlus/`, or
  the firmware loader won't find any of it.
- **Provenance.** These are OnePlus/Qualcomm-signed proprietary blobs, redistributed on a public
  GitHub repo with no stated license for that content. Convenient - skips extracting them from
  an OxygenOS image yourself - but treat the legal status as unresolved, same as any other
  redistributed proprietary firmware mirror.

*Source:* postmarketOS wiki (MediaWiki API and full page source supplied by the user);
GitHub API (`gh api`); GitLab API (`gitlab.com` and `gitlab.postmarketos.org`, both via `curl`);
direct diff of both DTS files now checked into `reference/dts/`.

---

## 2. Hardware claims, checked against the device tree

Audited against `reference/dts/sm8250-oneplus-instantnoodle.dts` (Xo666 fork, branch `6.16.7`,
1643 lines). This is the authoritative statement of what the port actually drives.

| Doc claim | Reality | Verdict |
|---|---|---|
| Touchscreen is `goodix` or `synaptics_dsx` over I²C | `samsung,s6sy761` @ 0x48 on i2c13 | **WRONG** |
| Panel over **two** MIPI-DSI lanes | `samsung,amb655uv01`, single link on `mdss_dsi0` | **WRONG** |
| Panel 1080×2400, 90 Hz | Confirmed; wiki notes 60/90 Hz both supported | **CONFIRMED** |
| UFS 3.0 | Corrected 2026-10-01: `jedec,ufs-2.0` is the generic Linux binding name for any UFS host, not the chip version; the OnePlus MSM package ships firmware for UFS 3.0/3.1 parts | **CONFIRMED** (earlier PARTIAL was wrong) |
| Audio via WCD9385 + LPASS/Hexagon | `qcom,wcd9380-codec` present, **plus** 2× `nxp,tfa9874` speaker amps on i2c15 | **PARTIAL** |
| ADSP/CDSP firmware needed | Confirmed - `adsp.mbn`, `cdsp.mbn` both required | **CONFIRMED** |
| Adreno 650 works via Turnip/`msm` | `&gpu status = "okay"` **on the Xo666 tree only**, needs `a650_zap.mbn`. Disabled outright on the wiki's own tracked tree - see §1.4 fork divergence table | **CONFIRMED, tree-dependent** |
| GPU boosts to 670 MHz | 670 MHz is the Snapdragon **865+** clock. Plain 865 tops at 587 MHz | **WRONG** |
| `pm8150b-charger` manages charging | Absent from Xo666 (audited here); present and `okay` on WuerfelDev's tree - the two trees trade this against GPU. See §1.4 | **PARTIAL, tree-dependent** |
| USB-C SuperSpeed orientation quirk | `fcs,fsa4480` SBU mux present; orientation behaviour untested | **OPEN** |

### Update 2026-08-24 (later): full wiki Infobox/feature table obtained

The user supplied the complete `oneplus-instantnoodle` wiki page source (Infobox + feature
tables), not just the summary previously scraped via the MediaWiki API. This resolves one open
question and adds hardware the DTS audit above didn't surface:

- **Charging is explicitly `feature-yes` on the wiki**: "Charger | `qcom,pm8150b-charger` |
  Allows charging at 5W". Fast charging is separately listed and marked `feature-no`:
  "`oplus,stm8s-fastcg` | Enables 5V6A/Warp Charging, currently no driver exists". So base
  charging at 5 W is a confirmed, working feature - not the fully open question §4 originally
  treated it as. Only Warp/fast charging is confirmed absent.
- **This does not contradict the DTS finding above so much as date it.** The wiki's Infobox
  declares `pmoskernel = 6.17.0`, which points at a different, newer kernel tree
  (`gitlab.postmarketos.org/WuerfelDev/linux-sm8250`, tag `6.17.0-instantnoodle`) than the
  `reference/dts/` snapshot audited in this repo (Xo666 fork, branch `6.16.7`). The charger
  node most likely landed between those two trees. Treat `reference/dts/sm8250-oneplus-instantnoodle.dts`
  as one version behind the currently wiki-tracked kernel on this specific point.
- **NFC confirmed working**: `nxp,nxp-nci-i2c` @ 0x28 on i2c1 - **absent from the document
  and from this log entirely until now.**
- **Flash LED confirmed working**: `qcom,spmi-flash-led`, wired through the `pm8150l` PMIC's
  SPMI bus - also previously unmentioned.
- **Audio bus addresses pinned down**: both `nxp,tfa9874` amps sit on i2c15, earpiece at
  0x34 and main speaker at 0x35 - consistent with, and more precise than, the DTS audit above.
- **SBU mux (`fcs,fsa4480`) address given**: 0x42 on i2c15 (the DTS audit only confirmed its
  presence, not its address).
- Full feature matrix from the wiki, for completeness: screen, battery, front camera, GPU,
  WiFi, Bluetooth, USB OTG all **Y**; rear camera **P** (marked partial on the wiki, though the
  DTS audit above found the node absent entirely - treat as effectively non-functional);
  modem, sensors (`slpi` loads unconfigured), haptics all **N**, matching the "known-broken"
  list below.

**Correction to the bullet above (2026-08-24, still later that day):** "not the fully open
question §4 originally treated it as" undersold what pulling the actual WuerfelDev tree turned
up. That same tree, at its current HEAD, has **`&gpu { status = "disabled"; }`** - unconditionally.
The wiki's `status_3d = Y` and this tree's own DTS disagree with each other. Charging at 5 W is
real on *a* tree; that tree does not currently give you a working GPU. See the fork-divergence
table in §1.4 - this is the actual state of play, not the charging-only framing above.

### Additional hardware the doc never mentions

- **`&mdss_dp { status = "okay" }`** - DisplayPort alt-mode over USB-C is enabled. Relevant
  to a docked handheld setup and absent from the document entirely.
- **`&pm8150b_vbus`**, 500 mA-3 A source regulator - the phone can power USB accessories (OTG out).
- **Battery**: `simple-battery`, 16.37 Wh design energy, 4270 mAh, 3.4-4.435 V.
- **Fuel gauge**: `ti,bq27411` - accurate charge reporting.
- **Front camera only** confirmed functional (`sony,imx471`). Rear `imx586` is absent from
  the audited DTS and marked only partial on the wiki.
- **NFC**: `nxp,nxp-nci-i2c` @ 0x28 on i2c1.
- **Flash LED**: `qcom,spmi-flash-led` via the pm8150l PMIC.

### Known-broken, per wiki

Modem (`sdx55m`), sensors (`slpi` loads but is unconfigured), haptics (`awinic,aw8697`),
rear camera. **None of these matter for a dedicated handheld** except haptics, which is
a comfort loss only.

---

## 3. Required firmware blobs

`&gpu` will not probe without its zap shader, so this is a hard prerequisite for the
entire graphics stack. All five are proprietary and must be extracted from an OxygenOS
image into `/lib/firmware/qcom/sm8250/OnePlus/`:

| Blob | Purpose | Consequence if missing |
|---|---|---|
| `a650_zap.mbn` | GPU zap shader (signed) | **No GPU. Project stops.** |
| `adsp.mbn` | Audio DSP | No audio |
| `cdsp.mbn` | Compute DSP | No compute offload |
| `venus.mbn` | Video decode | No hardware video |
| `slpi.mbn` | Sensor DSP | No sensors (already broken) |

Note the vendor subdirectory `.../sm8250/OnePlus/` - the doc says `/lib/firmware/qcom/sm8250/`
([line 39](https://github.com/GabrielCRadu/ARMDeck/blob/3560179/Gaming%20Mainline%20OnePlus%208.md#L39)), which is the wrong path.

Additionally from `linux-firmware` (open, not device-specific): `a650_sqe.fw`, `a650_gmu.bin`,
ath11k QCA6390 WiFi, and QCA Bluetooth firmware.

**These can be sourced without the phone** - an OxygenOS payload dump is enough.

---

## 4. Power and thermals - narrowed, but now entangled with GPU

> **Read §1.4 before this section.** The "confirmed 5 W charging" finding below comes from the
> WuerfelDev `6.17.0-instantnoodle` tree, which currently ships with **the GPU disabled in DTS**.
> The Xo666 tree this whole document otherwise relies on for graphics has the opposite problem:
> working GPU, zero charger node. As of 2026-08-24 you cannot get both from one unmodified tree.
> The numbers below describe the charging-capable tree's power budget, not the build this
> document otherwise recommends.

The document's thermal architecture rests on passthrough power: the GameSir X3 Pro's
Peltier cooler keeps the SoC at 45-52 °C, so the CPU never throttles, and the phone charges
through the controller meanwhile. The cooling half of that is sound - the Peltier draws
10-12 W **from the wall charger, not from the phone**, so active cooling works regardless
of what the phone's charging stack does.

The charging half was flagged OPEN in the first pass of this log, because the wiki's summary
claimed 5 W charging while the Xo666 DTS audited in `reference/dts/` declared no charger node
at all. **The full wiki feature table (obtained later, §2) resolves this**: base charging via
`qcom,pm8150b-charger` is listed as a confirmed, working feature at **5 W**. Only Warp/fast
charging (`oplus,stm8s-fastcg`, 5V/6A) is confirmed absent - "currently no driver exists," per
the wiki itself. The likely explanation for the DTS discrepancy: the wiki's Infobox declares
`pmoskernel = 6.17.0`, a newer kernel snapshot than the `6.16.7` Xo666 branch this repo
audited; the charger node most likely landed in that gap. `pm8150b_typec` (present in the
audited DTS) also declares sink PDOs of `PDO_FIXED(5000, 3000)` (5 V/3 A) plus
`PDO_VAR(5000, 12000, 5000)` (5-12 V variable) and `op-sink-microwatt = <10000000>`.

**What this means practically:** at a system draw of 8-11 W under load against a confirmed
5 W input, net deficit is 3-6 W. On a 16.37 Wh battery that's roughly **2.7-5.5 hours of play
while slowly draining** - narrower and more grounded than the original "maybe it doesn't charge
at all" framing, but still not indefinite. "Plug in and play forever" remains unestablished;
"plug in and roughly double your unplugged session length" is now the reasonable claim.

The doc's remedies are correspondingly unreliable:

- Fixing the PD profile at 5 V/3 A in DTS ([line 36](https://github.com/GabrielCRadu/ARMDeck/blob/3560179/Gaming%20Mainline%20OnePlus%208.md#L36)) -
  the DTS already declares this; no evidence it's the problem.
- `echo 0 > /sys/class/power_supply/battery/charging_enabled`
  ([line 186](https://github.com/GabrielCRadu/ARMDeck/blob/3560179/Gaming%20Mainline%20OnePlus%208.md#L186)) - a **downstream** sysfs node. Mainline
  `power_supply` exposes `charge_control_limit` / `input_current_limit` instead. This command
  will almost certainly fail.

**Still resolve at G3/G7 with hardware** - the 5 W figure and the 3-6 W deficit math are both
still projections, not measurements, taken from a tree (WuerfelDev) that does not currently boot
this device's GPU. The actual top risk is no longer "does charging work" but **"can the
charger node from WuerfelDev be ported onto the Xo666 tree without breaking the GPU or the SBU
mux"** - a merge/patch job nobody has done yet, as far as this log can tell. The Steam ARM64
client plumbing (§5.2) is the next-biggest source of uncertainty after that.

---

## 5. Userspace - better than expected

This is where the document holds up. My initial scepticism about Section 3 was too strong,
and is corrected here.

### 5.1 Proton 11 ARM64 - **CONFIRMED**

Real and shipping. Proton 11.0-1 Beta 3 (May 2026) ships FEX-2604; FEX 2608 landed
August 2026 as the current monthly release. The whole effort is driven by Valve's **Steam
Frame**, a Snapdragon 8 Gen 3 device running SteamOS - an Adreno a6xx-family GPU, the same
Turnip driver lineage as the Adreno 650. Valve publishes ARM64 build instructions for Proton.

The ARM64EC / thunking model the doc describes at
[line 77](https://github.com/GabrielCRadu/ARMDeck/blob/3560179/Gaming%20Mainline%20OnePlus%208.md#L77) matches how this actually works.

*Sources:* GamingOnLinux, Phoronix, ValveSoftware/Proton#7553.

### 5.2 Native ARM64 Steam client - **PARTIAL**

It exists, but it is an unannounced automated build, not the Steam Frame client. Per
Drakulix's [detailed write-up of running it on postmarketOS](https://blog.drakulix.de/taming-the-steam-arm64-client-on-pmos/):

- It is "totally oblivious to being compiled for arm64" and defaults to launching an x86_64 runtime.
- Valve does build SteamLinuxRuntime 4.0 and Proton for arm64, but the client won't fetch either.
- The Proton arm64 depot **ships without a `toolmanifest.vdf`**, so you must write one -
  which **vindicates the doc's step at [line 84](https://github.com/GabrielCRadu/ARMDeck/blob/3560179/Gaming%20Mainline%20OnePlus%208.md#L84)**.
- Making it work requires real plumbing: SteamRT4 arm64 as the client's own runtime, a
  `steam-runtime-launcher-service` on a custom bus name, and a `fexwrap` shim injecting FEX
  and graphics drivers into the pressure-vessel `bwrap` invocation.
- Grab the `steamdeck_stable` arm build rather than `publicbeta` - it carries the Deck-specific behaviour.

Achievable, but hand-rolled and fragile. This is the highest-risk gate in the plan.

### 5.3 Mesa Turnip on Adreno 650 - **CONFIRMED**

Uncontroversial. Turnip is a conformant Vulkan 1.3 driver on a6xx, and the extension set
the doc lists (`VK_EXT_graphics_pipeline_library`, `descriptor_buffer`, `custom_border_color`,
`image_drm_format_modifier`) is standard for current Mesa. The TBDR/GMEM discussion is
accurate, and GMEM on the 650 is indeed **1024 KB**.

### 5.4 `gamescope` as a pmbootstrap UI option - **WRONG**

There is no `postmarketos-ui-gamescope`. The full UI list is: buffyboard, cage, console,
cosmic, fbkeyboard, gnome, gnome-mobile, i3wm, kodi, lomiri, lxqt, mate, moonlight, niri,
openbox, os-installer, phosh, plasma-bigscreen, plasma-desktop, plasma-mobile, retroarch,
shelli, sway, sxmo (×4), weston, windowmaker, xfce4.

The doc's `pmbootstrap init` → "User Interface: gamescope" step does not exist. Gamescope
must be packaged. Nearest shipped gaming UIs are `retroarch` and `moonlight`.

There are also **no `fex`, `proton`, `steam`, or `box64` packages** anywhere in pmaports.
The entire userspace gaming stack is unpackaged work.

*(Partly corrected - see §7.6.1. The missing UI package is real, but "gamescope must be
packaged" is not: Alpine `community` already ships `gamescope` built for `aarch64`, and
pmaports layers on top of Alpine. Only the thin UI wrapper has to be written. The `fex` /
`proton` / `steam` / `box64` half of this paragraph still holds, in Alpine as well as
pmaports.)*

---

## 6. Recovered figures

Every numeric value in the source document was a base64-encoded LaTeX PNG, making the
markdown unreadable as text. All 32 were decoded and inlined by
[`tools/inline-doc-values.py`](../tools/inline-doc-values.py):

GMEM 1024 KB · Prime 2.84 GHz / 512 KB L2 · Gold 2.42 GHz / 256 KB L2 · Silver 1.80 GHz /
128 KB L2 · GPU 587→670 MHz · throttle at 70-75 °C down to 1.40 GHz / 305 MHz · Peltier
10-12 W · cooled junction 45-52 °C · system TDP 8-11 W · input latency < 2 ms.

**Benchmarks are projections, not measurements**, and they assume a 670 MHz GPU the plain
865 does not have - so they are optimistic by roughly 12% before accounting for FEX
translation overhead, which is the larger unknown. Treat the table as an upper bound.

---

## 7. Rewrite status

**Done (2026-08-24), first pass.** [`Gaming Mainline OnePlus 8.md`](https://github.com/GabrielCRadu/ARMDeck/blob/3560179/Gaming%20Mainline%20OnePlus%208.md)
was corrected against every WRONG/PARTIAL/OPEN item logged at that point: the
device-enablement chapter now describes the Xo666/ObiKeahloa forks instead of a fictional
`pmbootstrap init instantnoodle` flow, touchscreen/panel/audio/UFS claims match the DTS,
GPU clock is corrected to 587 MHz, `gamescope` is removed as an install option, the Steam
ARM64 client section covers the Drakulix fexwrap/SteamRT4 plumbing, and the benchmark table
carries an explicit "projection, not measurement" caveat.

**Done (2026-08-24), second pass.** The doc's power/charging section, risk table entry, and
conclusion were updated to the "5 W confirmed, Warp absent" framing, plus NFC and flash LED
were added to the hardware table.

**Follow-up needed (2026-08-24, third pass - current).** Pulling the actual WuerfelDev tree
(rather than trusting the wiki's feature table as description of one coherent kernel) found
that tree ships with **`&gpu` disabled** - so the second pass's charging framing, while
individually accurate, reads as better news than the project's real state supports. The doc
needs a further edit: charging and GPU are not simultaneously available from any known
unmodified tree (§1.4), and that fork-divergence problem - not charging, not Steam ARM64 -
is now the most fundamental open risk. This is a correction to the *previous* correction, not
a reversal of it: 5 W charging is still real, it's just real on a tree without graphics.

## 7.5. Kernel build - CONFIRMED (no hardware needed for this part)

Without a phone available, the highest-value hardware-independent check is: does the Xo666
kernel source actually compile? **Yes.** Verified 2026-08-24:

- Shallow-cloned `github.com/Xo666/mainline-instantnoodle`, branch `6.16.7` (`git clone --depth 1`).
- Host: Ubuntu 24.04 LTS under WSL2 (kernel `5.15.167.4-microsoft-standard-WSL2`), cross-compiling
  with `aarch64-linux-gnu-gcc 13.3.0` (Ubuntu package `gcc-aarch64-linux-gnu`).
- `make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- op8_defconfig` - the OnePlus-8-specific
  defconfig shipped in this fork's `arch/arm64/configs/` - configured cleanly.
- `make -j16 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- Image.gz dtbs` completed in 5m30s
  wall-clock (69m of CPU time across 16 cores), exit code 0.
- Produced artifacts, confirmed on disk: `arch/arm64/boot/Image.gz` (15.2 MB) and
  `arch/arm64/boot/dts/qcom/sm8250-oneplus-instantnoodle.dtb` (134,896 bytes, compiled with no
  `dtc` errors).

This is a real build, not a projection - it's the strongest signal available without hardware
that the reference DTS and kernel source in this repo are internally consistent and buildable.
It does **not** confirm the kernel boots, that the zap-shader firmware actually initializes the
GPU, or any of the runtime claims elsewhere in this log - only that the source compiles clean
with this defconfig and toolchain. Module build (`modules`) and a full `dtbs_install` pass were
not run in this check; only the two artifacts actually needed to test-boot the device were built.

Draft pmaports packaging (based on the packaged `device-oneplus-instantnoodlep` port as a
template) is checked in at `pmaports/` - `device-oneplus-instantnoodle/`,
`linux-oneplus-instantnoodle/`, `firmware-oneplus-instantnoodle/`, and
`alsa-ucm-conf-oneplus-instantnoodle/`. The bootimg flash offsets and super-partition path were
cross-checked against the actual `by-name` partition dump for a real OnePlus 8 the user supplied
earlier and match `instantnoodlep`'s values exactly. The dtbo stub's `qcom,board-id` was pulled
directly from `reference/dts/sm8250-oneplus-instantnoodle.dts` rather than copied from the Pro's
port - it happens to match the Pro's value, which is flagged in that file as unconfirmed, not
silently assumed correct.

### Update 2026-08-24 (same day, later): all four packages built through real abuild/pmbootstrap

The draft above has since been run through the actual packaging pipeline, not just a plain
cross-compile. Set up a full local test rig: shallow-cloned the real `pmaports.git` (120 MB),
dropped the four draft packages into `device/testing/`, ran `pmbootstrap init` pointed at that
local checkout - **it found `instantnoodle` as a valid codename and listed it alongside the
packaged `instantnoodlep`/`kebab` devices**, with no "create new port" prompt, confirming the
draft `deviceinfo`/`APKBUILD` files are structurally valid. Generated real checksums with
`pmbootstrap checksum` (all `sha512sums=""` placeholders now filled in the checked-in files) and
ran `pmbootstrap -y build` on all four packages.

Two real packaging bugs surfaced and were fixed along the way:

- `linux-oneplus-instantnoodle`'s first draft listed a fabricated
  `gcc-aarch64-linux-gnu-cross-toolchain` makedepends that doesn't exist in Alpine/pmaports.
  Switched to `LLVM=1` + `clang`/`lld`/`llvm`, matching the convention the packaged
  `linux-postmarketos-qcom-sm8250` kernel actually uses - this is what ultimately built.
- Passwordless sudo had to be configured for the build user in this WSL environment; without it,
  `pmbootstrap`'s internal `sudo losetup`/mount calls hang indefinitely waiting for a password
  that can never arrive non-interactively. Environment-specific, not a packaging issue, but worth
  recording since it silently hung twice before the cause was found.

All four packages built successfully:

| Package | Result |
|---|---|
| `linux-oneplus-instantnoodle-6.16.7-r0.apk` | 27.6 MB, built via LLVM/clang cross toolchain inside the real pmOS aarch64 buildroot, ~18.5 min |
| `device-oneplus-instantnoodle-0.1-r0.apk` | 3 KB (deviceinfo + dtbo.img) |
| `firmware-oneplus-instantnoodle-{adsp,cdsp,gpu,slpi,venus,wifi}-1-r0.apk` | 6 subpackages, correctly split; `-gpu` (49 KB) is the zap-shader blob |
| `alsa-ucm-conf-oneplus-instantnoodle-1-r0.apk` | 2.2 KB |

This is meaningfully stronger evidence than the raw cross-compile in the paragraph above: it
confirms the *packaging*, not just the *source*, is sound - dependency resolution, checksum
verification, cross-toolchain selection, and firmware subpackage splitting all worked without
manual intervention beyond the two fixes above.

### Update 2026-08-24 (same day, later still): `pmbootstrap install --split` succeeded

Ran the full install flow against the four packages above. First attempt failed at `mkinitfs`
with `only one kernel release/flavor is supported, found: []` - our `linux-oneplus-instantnoodle`
package installed `boot/vmlinuz` and `lib/modules/6.16.7/` correctly, but never wrote
`/usr/share/kernel/<flavor>/kernel.release`, which is what `mkinitfs` actually scans for to
discover installed kernels. Found by diffing our `package()` step against the working
`device/community/linux-postmarketos-qcom-sm8250` APKBUILD, which has this exact line:

```
install -D "$builddir"/include/config/kernel.release \
    "$pkgdir"/usr/share/kernel/$_flavor/kernel.release
```

Added it (plus the `rm -f .../build .../source` cleanup the reference package also does),
bumped `pkgrel`, rebuilt (cache-warm, ~2 min this time), and re-ran install. **It completed
cleanly**: produced `oneplus-instantnoodle-boot.img` (512 MB) and `oneplus-instantnoodle-root.img`
(829 MB), with `pmbootstrap` printing real flash commands (`pmbootstrap flasher flash_dtbo`,
`flash_kernel`, or `pmbootstrap export` to flash outside pmbootstrap).

**This is the practical ceiling of what can be verified without the phone in hand.** The images
exist and are internally consistent (rootfs copied, fstab generated, initramfs built against our
actual kernel), but nothing here proves they boot on real SM8250 silicon, that AVB/vbmeta
verification won't block them, or that the flash offsets in `deviceinfo` are exactly right. A
separate audit is in progress specifically to catch flashing/brick risks not yet covered by
kernel-compiles-successfully-style checks (AVB, dynamic partitions, EDL recovery currency,
device-specific bootloader unlock issues) before any real hardware is touched.

### Update 2026-08-24 (same day, later still): charger/fuel-gauge port attempted - compile-verified only

Section 1.4's fork-divergence problem ("no known tree has both GPU and charging") got an actual
attempt at a fix, not just documentation. The goal: port WuerfelDev's working
`pm8150b_charger`/`pm8150b_fg` device tree nodes onto the Xo666 tree without touching its
zap-shader/GPU wiring.

**What was ported.** Fetched WuerfelDev's `pm8150b.dtsi` and
`sm8250-oneplus-instantnoodle.dts` directly from `gitlab.postmarketos.org` (branch
`6.17.0-instantnoodle`, plain unauthenticated GET against the GitLab API's raw-file endpoint) and
diffed them byte-for-byte against Xo666's equivalents. Applied three changes to
`pm8150b.dtsi`, matching WuerfelDev exactly:

- The `pm8150b_charger: charger@1000` node (`qcom,pm8150b-charger`, 4 interrupts, 2 io-channels,
  `status = "disabled"` at this shared-PMIC-description level, same as WuerfelDev's own).
- Two ADC channel sub-nodes on `pm8150b_adc`: `channel@7` (`usb_in_i_uv`) and `channel@8`
  (`usb_in_v_div_16`). `channel@9` (`ADC5_CHG_TEMP`, label `chg_temp`) already existed in Xo666's
  tree and was reused, not duplicated.
- The `pm8150b_fg: fuel-gauge@4000` node (`qcom,pm8150b-fg`, one interrupt, `status = "disabled"`
  at the shared level).

Then added a board-level override block to `sm8250-oneplus-instantnoodle.dts`, again matching
WuerfelDev's board DTS: `&pm8150b_fg { status = "okay"; monitored-battery = <&battery>;
power-supplies = <&pm8150b_charger>; };` and `&pm8150b_charger { io-channels = <...5 channels...>;
... status = "okay"; };`. Reading WuerfelDev's actual `&pm8150b_adc` override block (rather than
assuming) showed `ADC5_VPH_PWR` needs its own dedicated channel node too, not just
`ADC5_CHG_TEMP` and `ADC5_SBUx` - WuerfelDev declares `channel@83` (`vph_pwr`) and `channel@99`
(`chg_sbux`) at board level. Both were added to Xo666's existing `&pm8150b_adc` override
(which already had one board-specific channel, `channel@4f` for `conn_therm`). Nothing touching
`&gpu`, the zap-shader node, the `fsa4480` SBU mux, or the existing `i2c16`/`bq27411` fuel-gauge
wiring was changed - those already work on Xo666 and this patch does not go near them.

**Compile verification, two layers:**

1. **Raw `dtc` build.** Installed `clang`/`lld`/`llvm` in the same WSL2 Ubuntu 24.04 host used for
   the 7.5 build above (they weren't present yet; `apt-get install -y clang lld llvm`).
   `make ARCH=arm64 LLVM=1 op8_defconfig` then `make ARCH=arm64 LLVM=1 -j16 dtbs` completed with
   exit code 0 and **zero warnings or errors** anywhere in the build log, including for
   `sm8250-oneplus-instantnoodle.dtb` specifically (grepped the full log for the filename plus
   "warning"/"error" - only the expected `DTC` compile line matched, no diagnostics attached to
   it). Decompiling the resulting `.dtb` back to source (`dtc -I dtb -O dts`) confirmed the
   `charger@1000` node resolves with `status = "okay"` and all 5 io-channels correctly cross-
   referenced (`usb_in_i_uv`, `usb_in_v_div_16`, `chg_sbux`, `vph_pwr`, `chg_temp`), the
   `fuel-gauge@4000` node resolves with `status = "okay"` and a valid `monitored-battery` phandle,
   and the `&gpu` node's `zap-shader` sub-node with `firmware-name =
   "qcom/sm8250/OnePlus/a650_zap.mbn"` is present and unchanged - confirming the charger port did
   not disturb the GPU wiring this whole project depends on.
2. **Patch file + real abuild/pmbootstrap pipeline.** Generated `git diff` into
   `pmaports/linux-oneplus-instantnoodle/0001-port-charger-fg-from-wuerfeldev.patch`, verified it
   applies cleanly to a clean checkout (`git stash` the working changes, `git apply --check`, then
   `git apply` - both succeeded with no fuzz or offset warnings). Added it to the APKBUILD's
   `source=` list (picked up automatically by the existing `prepare()`'s `default_prepare` call,
   abuild's documented convention for applying `.patch` files listed in `source=`), bumped
   `pkgrel` from 1 to 2, and generated the real sha512sum. Copied both files into the local
   `~/pmaports/device/testing/linux-oneplus-instantnoodle/` checkout used for the four packages in
   the section above, ran `pmbootstrap checksum linux-oneplus-instantnoodle` (checksum matched
   what was already computed locally - no drift), then `pmbootstrap -y build
   linux-oneplus-instantnoodle`. **Build succeeded**, cache-warm, in about 2m45s, producing
   `linux-oneplus-instantnoodle-6.16.7-r2.apk`. The build log explicitly shows the patch being
   applied ("patching file arch/arm64/boot/dts/qcom/pm8150b.dtsi", "patching file
   arch/arm64/boot/dts/qcom/sm8250-oneplus-instantnoodle.dts") before the kernel and DTBs compile,
   and the `sm8250-oneplus-instantnoodle.dtb` DTC line in that build's log carries no attached
   warnings either.

**What this does NOT prove, stated plainly.** This is a compile-time check only. Nothing here
has been run on a real OnePlus 8. It is not known whether:

- the `pm8150b-charger` and `pm8150b-fg` kernel drivers actually probe successfully against this
  hardware when the DTS says they should (a DTS node parsing and cross-referencing cleanly says
  nothing about whether the PMIC responds correctly at runtime);
- the ADC channel assignments (`channel@7`, `@8`, `@83`, `@99`) read sane voltage/current values
  once probed, or are wired to the right physical pins on this specific board revision;
  WuerfelDev's own board DTS was taken as ground truth here without independent hardware
  confirmation on that tree either;
- adding these nodes has any interaction with the GPU or SBU mux at runtime that a static DTS
  diff cannot reveal - the DTB decompile confirmed the *text* of the zap-shader node is
  unchanged, not that probe-order or power-sequencing interactions are safe;
- charging actually works, at 5 W or any other rate, on a phone built from this patched tree.

This patch is a candidate fix, not a resolution to the fork-divergence problem in section 1.4.
It compiles and packages cleanly through the real pipeline, which is stronger evidence than "it
looks right on paper," but it is not hardware evidence. Section 1.4's practical read - "no tree
cleanly has GPU and charging both confirmed working at once" - still stands until someone flashes
this and checks `power_supply` sysfs on an actual device.

### Update 2026-08-24 (same day, later still): the reverse direction attempted on ObiKeahloa - zap-shader port, plus a correction to the earlier ObiKeahloa assessment

Section 1.4's divergence table describes ObiKeahloa (`sm8250/v6.13-instantnoodle`) as the closest
match on paper: `&gpu { status = "okay"; }` and working-looking `pm8150b_charger`/`pm8150b_fg`
board-DTS override blocks in the same tree, something neither Xo666 nor WuerfelDev has. Its stated
blocker was that `&gpu` had no zap-shader child node, so the GPU's mandatory signed firmware had
nowhere to be declared. This entry documents an attempt to fix exactly that, by porting Xo666's
zap-shader block onto ObiKeahloa's tree - and a real correction to what that same divergence table
claimed about ObiKeahloa's charger/fg support.

**Setup.** Shallow-cloned `gitlab.com/ObiKeahloa/linux`, branch `sm8250/v6.13-instantnoodle`
(`git clone --depth 1`), into the same WSL2 Ubuntu 24.04 host used for every other build in this
project. Confirmed directly in the clone, not just from the saved `reference/dts/` copy, that
`&gpu` really is bare (`arch/arm64/boot/dts/qcom/sm8250-oneplus-instantnoodle.dts`, line 610:
`&gpu { status = "okay"; };`, nothing else). This tree has no OnePlus-8-specific defconfig name -
`arch/arm64/configs/` contains only `defconfig`, `hardening.config`, and `virt.config` - so
`make ARCH=arm64 LLVM=1 defconfig` (kbuild's plain default, which resolves to this fork's own
`arch/arm64/configs/defconfig` file) was used instead of an `op8_defconfig`-style target.

**Zap-shader port.** Before assuming the port would resolve, checked whether the `gpu_mem`
reserved-memory node the zap-shader's `memory-region` references actually exists in ObiKeahloa's
tree. It does: same label, same address and size as Xo666's
(`reg = <0x0 0x8e21a000 0x0 0x2000>;`, deleted from the upstream `sm8250.dtsi` node of the same
name and redefined at board level - both trees follow the identical pattern), just under the unit
name `memory@8e21a000` instead of Xo666's `gpu@8e21a000` (cosmetic - the label the phandle
resolves against is identical). So no reserved-memory node needed to be added; only the
zap-shader child node itself, ported byte-for-byte from
`reference/dts/sm8250-oneplus-instantnoodle.dts` (Xo666, lines 957-970):
```
&gpu {
	status = "okay";

	zap-shader {
		memory-region = <&gpu_mem>;
		firmware-name = "qcom/sm8250/OnePlus/a650_zap.mbn";
	};
};
```

**The correction.** Building `dtbs` at this point (zap-shader added, nothing else touched) failed
- not because of the zap-shader change, but with two pre-existing errors unrelated to it:
```
Error: .../sm8250-oneplus-instantnoodle.dts:848.1-12 Label or path pm8150b_fg not found
Error: .../sm8250-oneplus-instantnoodle.dts:854.1-17 Label or path pm8150b_charger not found
```
Confirmed this predates the zap-shader patch entirely: `git stash`-ing the change and building the
completely unmodified clone's `dtbs` target produces the identical two errors. Checked why:
`grep -rn 'pm8150b-charger\|pm8150b-fg' arch/arm64/boot/dts/qcom/` across the whole directory of
this clone returns nothing. ObiKeahloa's own `pm8150b.dtsi`, in this branch, never defines the
`pm8150b_charger` or `pm8150b_fg` labels its own board DTS's `&pm8150b_fg { ... }` and
`&pm8150b_charger { ... }` override blocks target. Those override blocks are real and do carry
`status = "okay"` in their text - that part of section 1.4's table is accurate as a description of
the board DTS file - but the node definitions they need to attach to simply are not present
anywhere in this kernel tree. dtc rightly refuses to resolve a reference to a label that does not
exist, and refuses to build the whole `dtbs` target as a result.

**This means the earlier fork-divergence table's characterization of ObiKeahloa - "near-identical
wiring to WuerfelDev... `&pm8150b_fg` also 'okay'" - was wrong in a way that matters, not just
imprecise.** That characterization was written from reading the saved `reference/dts/` snapshot's
text, not from compiling the actual kernel source. The board-DTS override text looked complete and
so was assumed to be backed by a working `pm8150b.dtsi`, the same way it is on WuerfelDev. It
is not. Until this session actually cloned and built ObiKeahloa's tree, that gap was invisible -
a pure DTS read cannot distinguish "this override activates a real, present node" from "this
override references a label that does not exist and will hard-fail the build." Compiling caught
it; reading did not. This is exactly the kind of thing this log tries to catch, and in this
instance it did not catch it the first time around.

**The fix applied.** Since ObiKeahloa's `pm8150b.dtsi` turned out to have the same
charger/fg-less shape Xo666's did before its own charger patch (same `channel@6`/`channel@9` ADC
layout, same missing `charger@1000`/`fuel-gauge@4000` nodes), the same content already used in
`pmaports/linux-oneplus-instantnoodle/0001-port-charger-fg-from-wuerfeldev.patch` (originally
sourced from WuerfelDev) was inserted into ObiKeahloa's `pm8150b.dtsi` at the same relative
positions: the `pm8150b_charger` node, `channel@7`/`channel@8` ADC sub-nodes, and the `pm8150b_fg`
node. ObiKeahloa's own board-level override blocks in `sm8250-oneplus-instantnoodle.dts` - which
already declared `channel@83` (`vph_pwr`) and `channel@99` (`chg_sbux`) at board level, and already
had the `&pm8150b_fg`/`&pm8150b_charger` override blocks - were left completely untouched; they
were already correct, they just had nothing to attach to until this fix.

**Compile verification, two layers, same rigor as the Xo666 charger patch:**

1. **Raw `dtc` build.** `make ARCH=arm64 LLVM=1 defconfig` configured cleanly.
   `make ARCH=arm64 LLVM=1 -j16 dtbs` completed with exit code 0 and zero warnings or errors
   anywhere in the build log, `sm8250-oneplus-instantnoodle.dtb` included specifically (grepped
   the full log for "warning"/"error" attached to that target - none). Decompiled the resulting
   `.dtb` (`dtc -I dtb -O dts`) and confirmed all three node types resolve fully with
   `status = "okay"`:
   - `zap-shader` under `&gpu`: `memory-region` phandle resolves to the `gpu_mem` reserved-memory
     node at `0x8e21a000`, `firmware-name = "qcom/sm8250/OnePlus/a650_zap.mbn"` present.
   - `charger@1000`: all 5 io-channels correctly cross-referenced (`usb_in_i_uv`,
     `usb_in_v_div_16`, `chg_sbux`, `vph_pwr`, `chg_temp`), `monitored-battery` phandle resolved.
   - `fuel-gauge@4000`: `monitored-battery` and `power-supplies` phandles both resolved, the
     latter pointing back at the charger node.
   Also checked the SBU mux directly in the decompiled output rather than assuming: `fcs,fsa4480`
   remains `status = "disabled"` on this tree, unchanged by this patch - matching WuerfelDev, as
   section 1.4 already documented. This patch does not touch, and does not claim to fix, USB-C
   orientation switching.
2. **Patch file + real abuild/pmbootstrap pipeline.** Generated `git diff` into
   `pmaports/linux-oneplus-instantnoodle-obikeahloa/0001-port-zap-shader-from-xo666.patch` (new
   package directory, separate from and not modifying
   `pmaports/linux-oneplus-instantnoodle/`), verified it applies cleanly to a clean checkout
   (`git stash`, `git apply --check`, `git apply` - no fuzz or offset warnings). Wrote a new draft
   `APKBUILD` at `pmaports/linux-oneplus-instantnoodle-obikeahloa/APKBUILD`, modeled on the
   existing Xo666 package's APKBUILD (same LLVM cross-build convention, same `kernel.release`
   install-step fix carried over from the start rather than rediscovered), pointing at
   `gitlab.com/ObiKeahloa/linux` branch `sm8250/v6.13-instantnoodle` with `pkgname =
   linux-oneplus-instantnoodle-obikeahloa` - deliberately distinct from the default kernel
   package, not wired into `device-oneplus-instantnoodle` or picked as any kind of default.
   First `pmbootstrap -y build` attempt failed immediately with `ERROR: linux-oneplus-instantnoodle-obikeahloa:
   pkgdesc is too long` - a real, quick packaging bug (abuild's `pkgdesc` field has a length
   limit), fixed by shortening the description. Copied the fixed APKBUILD and patch into
   `~/pmaports/device/testing/linux-oneplus-instantnoodle-obikeahloa/` (the same local pmaports
   checkout used for every package build in this project), ran `pmbootstrap checksum
   linux-oneplus-instantnoodle-obikeahloa` (copied the regenerated checksums back into the
   checked-in APKBUILD), then `pmbootstrap -y build linux-oneplus-instantnoodle-obikeahloa`.
   **This build succeeded**, producing `linux-oneplus-instantnoodle-obikeahloa-6.13.0-r0.apk`
   (43.5 MB), a full cold build (no prior cache for this source tree) that ran about 32 minutes.
   The build log explicitly shows the patch being applied ("patching file
   arch/arm64/boot/dts/qcom/pm8150b.dtsi", "patching file
   arch/arm64/boot/dts/qcom/sm8250-oneplus-instantnoodle.dts") before the kernel and DTBs compile,
   and the `sm8250-oneplus-instantnoodle.dtb` DTC line in that build's log carries no attached
   warnings either.

**Firmware path convention, flagged and not resolved.** Every other `firmware-name` property
already present in ObiKeahloa's tree uses a lowercase, `.mdt`-suffixed path -
`qcom/sm8250/oneplus/adsp.mdt`, `cdsp.mdt`, `slpi.mdt`, `venus.mdt` (confirmed by grepping this
clone directly). The ported zap-shader node keeps Xo666's exact string instead -
`qcom/sm8250/OnePlus/a650_zap.mbn`, capital O, `.mbn` extension - as a faithful port of the one
tree with demonstrated GPU firmware loading, rather than guessing at an unproven `.mdt` rename. A
firmware package built for this specific tree therefore cannot reuse the same lowercase/`.mdt`
layout its other four blobs expect for the zap shader; whether the kernel's remoteproc/mdt loader
would even accept the differently-cased/suffixed file through the same `firmware-name` mechanism
is not verified here. Real open question for anyone packaging firmware for this combination, not
a solved problem - same category of unresolved question as the `OnePlus8`/`OnePlus` path mismatch
already documented in section 1's firmware discussion.

**What this does NOT prove, stated plainly - same caveats as the Xo666 charger patch, plus one
more.** This is compile-time verification only. Nothing here has been run on a real OnePlus 8. Not
known: whether `pm8150b-charger`/`pm8150b-fg` actually probe on this hardware; whether the ADC
channel assignments read sane values; whether the `a6xx`/`msm_gpu` driver actually accepts firmware
through the `.mbn` path on this kernel given the tree's other firmware nodes use `.mdt`; and
whether stacking all three changes (zap-shader plus the charger/fg node-definition port) together
has any runtime interaction a static DTS/DTB diff cannot show.

**Net result.** With both parts of this patch applied, ObiKeahloa's tree compiles clean and its
compiled `.dtb` resolves GPU zap-shader, charger, and fuel-gauge simultaneously, plus packages
successfully through the real `abuild`/`pmbootstrap` pipeline - a combination no single tree in
this project had reached before. It is a better on-paper combination than the WuerfelDev-onto-Xo666
charger port (which left the SBU mux disabled - and so does this: ObiKeahloa's `fcs,fsa4480` was
already `status = "disabled"` before this patch and stays that way). It is still compile-verified
only, on a fork this session found does not even build at HEAD without the charger/fg node
definitions this patch adds - which is itself the most concrete evidence yet that reading device
tree text is not a substitute for compiling it, a lesson this project has now paid for twice.

---

## 7.6. Userspace gaming stack - survey and FEX feasibility audit

Performed 2026-09-02. No hardware involved; everything here is package indexes, upstream
source, upstream issue history, and the Xo666 defconfig.

### 7.6.1 Alpine already ships the native half - partially corrects §5.4

§5.4 concluded that "Gamescope must be packaged" and that there are no `fex`, `proton`,
`steam` or `box64` packages. Both statements were checked against **pmaports only**.
postmarketOS layers its own aports on top of Alpine's repositories, so pmaports being empty
does not mean the package is unavailable.

Pulled the real `APKINDEX` for Alpine edge `aarch64` (`main`, `community`, `testing`, 35976
package entries total) from `dl-cdn.alpinelinux.org` and read it directly:

| Package | Version | Repo | Relevance |
|---|---|---|---|
| `gamescope` | 3.16.24-r1 | community | The SteamOS session compositor. **Already built for aarch64.** |
| `mesa-vulkan-freedreno` | 26.1.6-r1 | main | Turnip, the Vulkan driver for Adreno (§5.3) |
| `vulkan-loader` | 1.4.360-r0 | main | ICD loader |
| `mangohud` | 0.7.1-r2 | community | FPS/thermal overlay |
| `gamemode`, `wlroots0.20`, `seatd`, `libliftoff`, `xwayland` | | community | gamescope's runtime dependencies |
| `distrobox`, `podman`, `docker-engine` | | community | container tooling, see §7.6.3 |
| `squashfs-tools`, `squashfuse`, `erofs-utils` | | main/community | for mounting an x86_64 rootfs |

**So gamescope does not need porting.** What §5.4 got right is that there is no
`postmarketos-ui-gamescope`: the UI package that starts it at boot still has to be written.
That is a wrapper around an existing binary, not a port.

Genuinely absent from **both** Alpine and pmaports: `fex`, `box64`, `box86`, `wine`,
`proton`, and the Steam client itself. Alpine's `steam-devices` is only the udev rules for
controllers, not the client. The postmarketOS `master` `aarch64` repo (1051 packages)
contains none of them either.

*Source:* `APKINDEX.tar.gz` from `dl-cdn.alpinelinux.org/alpine/edge/{main,community,testing}/aarch64/`
and `mirror.postmarketos.org/postmarketos/master/aarch64/`, read locally.

### 7.6.2 FEX on musl - real progress upstream, but untested and unsupported

The question asked: can FEX be built as a native Alpine/musl `aarch64` package?

**Evidence that it is getting closer.** There was an actual musl porting effort. Issue
[#5106](https://github.com/FEX-Emu/FEX/issues/5106) ("FEX Emu fails to build on Alpine Linux
aarch64", opened 2025-12-06) collected the first wave of failures, and a cluster of about ten
follow-up issues filed 2026-05-03 (#5457, #5459, #5461, #5463, #5465, #5467, #5469, #5471,
#5476, plus #5456 and #5513) are all **closed**. Spot-checked two of the specific errors
against current `main` and both are fixed:

- `ThreadManager.h` no longer includes `<bits/types/sigset_t.h>`, a glibc-internal header
  that does not exist on musl. It now uses plain `<signal.h>`.
- `AllocatorHooks.cpp` now includes `<unistd.h>`, which is what made `off_t` undefined.

FEX also carries `FEXCore/Utils/LongJump.h`, a hand-rolled `longjmp` whose own comment says it
exists partly for "a libc implementation that does not implement `std::longjmp`". Somebody
upstream is thinking about non-glibc hosts.

**Evidence that it is still not a supported configuration.**

- **No CI.** FEX's `.github/workflows` contains no Alpine or musl job at all (checked every
  workflow file). The musl fixes landed from bug reports; nothing guards against regression.
- **#5106 is still open**, last updated 2025-12-10. FEX's lead developer (Sonicadvance1)
  commented on 2025-12-07: *"Took a peek at this but there are significantly more compile
  problems than just the things described here. Supporting building on Alpine will take some
  significant work."*
- **A known unfixed blocker in that thread:** FEX's bundled jemalloc ships pre-generated
  headers that assume the GNU `strerror_r` signature, so `External/jemalloc/src/malloc_io.c`
  fails on musl. Sonicadvance1's own diagnosis: *"We would probably need to actually generate
  these headers at cmake configuration time rather than pre-generated."* Not done.
- **FEX's README lists its tested distributions** as Arch, Fedora, openSUSE and Ubuntu
  22.04/24.04/24.10/25.04. No musl distribution appears.
- **The allocator is glibc-shaped by design.** Per `docs/allocator_usage.md`, FEX runs two
  heap allocators, and the second one, `jemalloc_glibc`, *"replaces the host glibc's allocator
  using weak symbol overriding"* and exists to give thunks (`ThunkLibs`, the mechanism that
  forwards guest x86 Vulkan/GL/ALSA calls to the **native ARM64** host libraries) a way to
  tell which heap a pointer came from. `CMakeLists.txt` disables it only for MinGW, and warns
  for every other target: *"jemalloc glibc allocator disabled! This is not a recommended
  configuration! This will very explicitly break thunk execution!"* For a gaming handheld the
  thunks are the whole point, since they are what lets guest x86 Vulkan calls reach native
  Turnip instead of being emulated.

### 7.6.3 What the postmarketOS community actually does: a glibc container

This is the finding that makes §7.6.2 mostly moot. The pmOS wiki has two guides for exactly
this problem, and **neither builds FEX or box64 on musl**. Both run a glibc distribution in a
container on top of postmarketOS:

- **[Steam in FEX](https://wiki.postmarketos.org/wiki/Steam_in_FEX)** - `apk add distrobox`,
  create an Ubuntu 24.04 arm64 container, install FEX from its official Ubuntu PPA inside it,
  fetch an x86_64 rootfs with `FEXRootFSFetcher`. A second variant in the same page builds a
  Fedora container under `docker-engine` and compiles FEX from git inside it, installing
  `gamescope` in the container too.
- **[Steam in box86](https://wiki.postmarketos.org/wiki/Steam_in_box86)** - a Debian container
  with `dpkg --add-architecture armhf`, then box86 and box64 from Ryan Fortner's Debian repo,
  then Valve's own `steam-launcher_latest_all.deb`. Note that box86 ships **SoC-specific
  builds** (`box86-sd845` in the guide), which is a sign that project actively targets older
  Snapdragons.

Every piece of tooling either guide needs is already packaged for Alpine `aarch64`
(`distrobox`, `podman`, `docker-engine`, `squashfuse`, `erofs-utils`), per the table in
§7.6.1. FEX's own issue tracker corroborates that this is the normal path: issue #4111 is
titled *"[Steam]: [Segfault on Ubuntu 24.04, PPA inside Distrobox on postmarketOS]"*.

**Practical constraints stated in the guide, worth recording before anyone plans around them:**

- **At least 4 GB of swap is recommended.** The author reports *"frequent OOM crashes without,
  even on an 8GB RAM device"*. The OnePlus 8 has 8 or 12 GB depending on SKU.
- **Wayland-native games did not work**; Source engine titles needed
  `SDL_VIDEODRIVER=x11 %command%` in the launch options.
- The x86_64 rootfs has to be **extracted, not mounted as SquashFS**, inside distrobox.
- `steamwebhelper` crashes on startup are reported as a recurring, unresolved annoyance.

### 7.6.4 The real risk is the CPU, not the libc - **OPEN, and it is the biggest one**

FEX issue [#4120](https://github.com/FEX-Emu/FEX/issues/4120), *"Preparation plan for
increasing minimum requirements to require FEAT_FLAGM/ARMv8.4-a"*, filed by FEX's lead
developer on 2024-10-15. It proposes raising FEX's minimum from ARMv8.0-a to ARMv8.4-a and
**lists the hardware that would lose support**, verbatim:

> - CPUs: ARM: Cortex-A57 through Cortex-A78
> - SoCs: [...] Qualcomm mobile: Snapdragon 888 and older

The Snapdragon 865 in this phone is Cortex-A77 based. It is on that list twice. The list of
what survives begins at "Snapdragon mobile: Snapdragon 8 Gen 1 and newer".

The same issue also explains why performance on this class of hardware is mediocre even
today, independent of the drop plan: without `FEAT_LRCPC`/`FEAT_LSE2`, *"x86 emulation is
either slow (atomics) or buggy (TSO emulation disabled)"*. TSO is x86's memory ordering model;
emulating it on ARM is expensive, and turning it off is what breaks multithreaded games.

**Current status of the threat, checked against `main` on 2026-09-02:**

- The change has **not happened**. FEX's README still says *"FEX requires ARMv8.0+ hardware"*,
  and `Source/Common/HostFeatures.cpp` still runtime-detects `FlagM`, `LRCPC`, `LSE2` and
  friends, with `SupportsFlagM` codepaths alive in the JIT (`ALUOps.cpp`,
  `OpcodeDispatcher.cpp`).
- The issue is still open, was last updated 2025-04-04, and predicted itself for "the middle
  of 2025". It is more than a year overdue, which is weak evidence it is not imminent.
- Asked directly whether old FEX would remain usable, Sonicadvance1 answered: *"Old FEX will
  always remain available. We're an open source project after all."* So the fallback if this
  lands is pinning a known-good FEX release rather than losing the capability outright.

**One direct positive datapoint on this exact SoC.** In the same issue thread,
CalcProgrammer1 writes: *"I've been experimenting with FEX on postmarketOS devices and quite a
few games are playable on it (SDM845, SM8250)."* SM8250 is this phone's SoC. That is a
second-hand report, not a measurement, and it does not say which device or what framerate, but
it is the only evidence in this log that FEX runs on this silicon at all.

**box86/box64 is not exposed to this risk.** It has no comparable minimum-spec plan and ships
per-SoC builds for older Snapdragons. If #4120 ever lands, box64 becomes the fallback
translator rather than the second choice.

### 7.6.5 Kernel readiness for containers and binfmt - **CONFIRMED, one gap**

Both routes in §7.6.3 depend on kernel features: `binfmt_misc` to auto-dispatch x86 binaries
to the translator, and the usual container primitives. Checked `op8_defconfig` (8647 lines)
from the Xo666 tree, branch `6.16.7`, the same config §7.5 built with:

| Option | Value | Why it matters |
|---|---|---|
| `CONFIG_BINFMT_MISC` | `=y` | **Required** by both FEX and box86/box64 to run x86 binaries transparently |
| `CONFIG_ARM64_4K_PAGES` | `=y` | FEX expects 4 KB pages; 16 KB is not set |
| `CONFIG_ARM64_VA_BITS_48` | `=y` | 48-bit address space, what FEX's VMA allocator is written against |
| `CONFIG_OVERLAY_FS`, `CONFIG_FUSE_FS` | `=y` | container image layers; FUSE also covers `squashfuse`/`erofs-fuse` |
| `CONFIG_NAMESPACES`, `CONFIG_USER_NS`, `CONFIG_PID_NS` | `=y` | distrobox/podman/docker |
| `CONFIG_CGROUPS`, `CONFIG_MEMCG`, `CONFIG_SECCOMP` | `=y` | same |
| `CONFIG_SQUASHFS` | `=y` | FEX rootfs images |
| `CONFIG_SWAP` `=y`, `CONFIG_ZRAM` `=m` | | the 4 GB swapfile the guide insists on is achievable |
| `CONFIG_BRIDGE`, `CONFIG_VETH`, `CONFIG_NF_NAT` | `=m` | docker networking, modules are fine |
| `CONFIG_EROFS_FS` | **not set** | the one gap, see below |

**The only gap is `CONFIG_EROFS_FS`.** Newer FEX rootfs images are distributed as EroFS, and
the Fedora/Docker variant of the pmOS guide installs `erofs-fuse`/`erofs-utils`. With
`CONFIG_FUSE_FS=y` the userspace `erofs-fuse` path still works, and SquashFS rootfs images
remain available, so this is a convenience fix rather than a blocker: one line in the
defconfig if we want it in-kernel.

*Source:* `arch/arm64/configs/op8_defconfig` at `Xo666/mainline-instantnoodle@6.16.7`, fetched
raw and grepped.

### 7.6.6 Verdict

**Do not package FEX for musl.** It is neither supported, tested, nor how anybody actually
runs this. The two documented postmarketOS routes both put a glibc distribution in a container
on top of the musl host, and every container tool needed is already in Alpine `aarch64`. That
turns "port a large C++ emulator to a libc it does not support" into "install a package inside
a container", which is not project work at all.

**The genuinely open risk is FEX issue #4120**, not musl. If FEX raises its minimum to
ARMv8.4-a, this phone's Snapdragon 865 is explicitly on the drop list. It has not happened and
is over a year past its own predicted date, old releases stay available, and box64 is an
unaffected fallback, so this is a risk to track rather than a reason to stop. But it is now
the largest known threat to the Windows-games half of this project, ahead of the Steam client
plumbing in §5.2.

**What this changes for the build order.** The native layer is worth doing first and is mostly
assembly, not porting: a `postmarketos-ui-gamescope`-style UI package wiring Alpine's existing
`gamescope` and `mesa-vulkan-freedreno` into the device port. The container layer needs a
working host compositor and a working Vulkan driver to render into regardless of which
translator ends up inside it, so nothing about §7.6.4's uncertainty argues for doing it in a
different order.

**What is NOT established here.** Nothing in this section was run. No FEX build was attempted
on musl or anywhere else, no container was started, and no game was launched. The kernel
config check is a text check on a defconfig, not a booted kernel. The SM8250 datapoint in
§7.6.4 is one sentence in a GitHub comment by a third party, and the performance figures in §6
remain projections.

---

## 8. Summary

> Corrected by section 9: the "GPU + charger + fg resolved" results below are compile-time
> only and the charger/fg half binds to no driver on either tree.

**Alive, on the Xo666 tree specifically.** The device boots mainline with working 3D on at
least one tree - that was the one thing that could have ended the project, and it's answered,
but not universally: the wiki's own tracked kernel (WuerfelDev) currently ships with the GPU
disabled. Graphics and compatibility chapters are broadly sound for whoever uses Xo666, and
Valve's Steam Frame work is actively pushing exactly this stack forward.

**Rewrite required.** The device-enablement chapter is wrong in its central claim: this is
a fork of mainline maintained by one contributor, not upstream support, and the documented
install flow does not run. *(Addressed - see §7.)*

**Watch.** The project's real bottleneck is **fork fragmentation**: no tree cleanly has GPU,
charging, and clean USB-C orientation switching all working at once (§1.4). Two merge/patch
attempts now exist. The first ports WuerfelDev's charger/fg nodes onto Xo666
(`pmaports/linux-oneplus-instantnoodle/`) - compile-verified through the real packaging
pipeline, but leaves the SBU mux disabled. The second ports Xo666's zap-shader onto ObiKeahloa
(`pmaports/linux-oneplus-instantnoodle-obikeahloa/`) - also compile-verified through the real
packaging pipeline, GPU + charger + fg all confirmed resolved in the compiled `.dtb`, SBU mux
still disabled there too. Doing the second port surfaced a real correction to this log's own
earlier work: ObiKeahloa's charger/fg support, described in §1.4 as "near-identical wiring to
WuerfelDev" based on a DTS text read, turned out not to compile at all at HEAD - its board-DTS
override blocks reference `pm8150b_charger`/`pm8150b_fg` labels that its own `pm8150b.dtsi`
never defines. Reading the device tree text said "working"; compiling it said "does not build."
The zap-shader patch had to grow to include porting those node definitions too, using the same
content already proven on Xo666. **Both patches remain compile-verified only, not hardware-tested
- neither has been flashed to a real OnePlus 8.** Xo666 (unpatched) is still the only tree
demonstrated to boot with 3D on the postmarketOS wiki's own device page; both patches are
candidates layered on top of what compiles cleanly, not confirmations of what boots. The
Steam/FEX plumbing (§5.2) is the next-biggest source of uncertainty after the fork-merge problem.

**New as of 2026-09-02 (§7.6).** Two things moved. The native half of the userspace stack is
in better shape than §5.4 claimed: `gamescope` and `mesa-vulkan-freedreno` are already built
for `aarch64` in Alpine, so that layer is assembly rather than porting, and `op8_defconfig`
already carries `CONFIG_BINFMT_MISC` plus every container primitive the x86 translation layer
needs. The x86 half got a new named risk instead: FEX issue #4120, written by FEX's own lead
developer, plans to raise the minimum CPU requirement to ARMv8.4-a and explicitly lists
"Snapdragon 888 and older" and "Cortex-A57 through Cortex-A78" as hardware that would be
dropped. This phone's Snapdragon 865 is on both lines. The change is over a year past its own
predicted date and old FEX releases stay available, with box64 as an unaffected fallback, so
this is a tracked risk rather than a stop - but it now sits ahead of §5.2 as the largest
threat to running Windows games on this device.

---

## 9. Pre-flash audit with the phone in hand (2026-10-01)

Full code scan of the repo, every claim re-checked against source code rather than reading
device tree text: the Xo666, ObiKeahloa and WuerfelDev trees (GitHub/GitLab APIs, GitHub
code search), pmbootstrap 3.11.1, the postmarketOS initramfs, the official
`device-oneplus-instantnoodlep`/`kebab` packages, the postmarketOS wiki pages for the 8, 8 Pro
and 8T, and the OnePlus 8 vendor kernel/device tree (LineageOS/android_kernel_oneplus_sm8250,
`arch/arm64/boot/dts/vendor/19821` is the OnePlus 8). The user-facing result, with the
preparation checklist and per-component tests, is [`docs/hardware-safety.md`](hardware-safety.md).

### 9.1 Both "charger port" patches were inert - **WRONG fix, removed**

The patches in section 7.5 (Xo666) and the ObiKeahloa entry only added device tree nodes.
Nothing binds to them:

- Xo666 `6.16.7` (head `408762bf`, unchanged since 2026-01-14): `drivers/power/supply` has no
  `qcom_pm8150b_charger.c` and no `qcom_fg.c`. GitHub code search on that repo returns 0 hits
  for `pm8150b-charger` and `pm8150b-fg`, while the same search finds `qcom,pmi8998-charger`
  (so the repo is indexed). `qcom_pmi8998_charger.c` matches only `qcom,pmi8998-charger` and
  `qcom,pm660-charger`, and `CONFIG_CHARGER_QCOM_SMB2` is off in `op8_defconfig` anyway.
- ObiKeahloa `sm8250/v6.13-instantnoodle` (head `79c4d152`, 2025-10-28): same, no driver.
- WuerfelDev `6.17.0-instantnoodle` (head `15f4f0b2`): has `qcom_pm8150b_charger.c`,
  `qcom_fg.c` and `qcom_smbx.c`. So does the official postmarketOS SM8250 kernel
  (`soc/qualcomm-sm8250/linux`, tags `sm8250-6.17.0` through `sm8250-7.2.0`).

"Compiles, and the decompiled DTB shows the nodes with `status = "okay"`" was true and proved
nothing about charging. The patch was removed from `linux-oneplus-instantnoodle` (pkgrel 4);
the ObiKeahloa package is now marked do-not-flash with the correction in its header.

### 9.2 The community PM8150B charger driver is unsafe as written - **NEW, critical**

`qcom_pm8150b_charger.c` (identical in WuerfelDev and in pmOS `sm8250-7.2.0`, 964 lines):

1. **Float voltage on the wrong scale.** `rc = (voltage_max_design_uv - 3487500) / 7500 + 1;`
   written to `FLOAT_VOLTAGE_CFG` (0x70 in the charger block, 0x1070 on the PMIC). That is the
   PMI8998/SMB2 scale (OnePlus vendor `qpnp-smb2.c`: min 3487500, step 7500). PM8150B/SMB5 uses
   3.6 V + 10 mV per step (vendor `qpnp-smb5.c`, `smb5_pm8150b_params.fv`: min 3600000, max
   4790000, step 10000; `smb5-reg.h`: `CHGR_FLOAT_VOLTAGE_CFG_REG = 0x1070`). With this
   battery's 4.435 V the driver writes 127, which PM8150B reads as **4.87 V**, above even the
   chip's documented 4.79 V maximum. Independently confirmed on a Retroid Pocket 5 (SM8250 +
   PM8150B): register 0x1070 read back 0x7a = 4.82 V for a 4.40 V battery
   (armada-os/armada#534, #550; fixed in ROCKNIX by PR #3371/#3382, merged 2026-09-29).
2. **Charge current never set**, leaving the 5.35 A hardware default (same reports).
3. **Watchdog pet without the peripheral base:** `regmap_write(chip->regmap,
   BARK_BITE_WDOG_PET, ...)` writes PMIC address 0x643 instead of 0x1643, i.e. into another
   PMIC peripheral. The same bug in the parent `qcom_smbx` driver was fixed upstream (series by
   Robin Snyders, accepted by Sebastian Reichel 2026-09-09), together with an off-by-one
   "+1" in the float voltage selector.

OnePlus's own limits for this phone (`kona-mtp.dtsi` in `19821`): normal-temperature float
4435 mV, software stop above 4445 mV, battery over-voltage fault at 4550 mV
(`vbatt_hv_thr`), 4130 mV when warm, `fcc-max-ua` 3 A. The community battery node's 4.435 V is
correct; the driver's encoding of it is not.

### 9.3 Speaker amplifier driver: uninitialized boost configuration - **FIXED (patch 0001)**

Xo666 drives both TFA9874 amps with its own `sound/soc/codecs/tfa9872.c`. In
`tfa987x_setup_dcdc()`, `u32 mcc, dcvof, dcvos, dctrip, dctrip2 = 0;` initializes only
`dctrip2`. The board DTS sets none of the optional DC-DC properties and `op8_defconfig` has
`CONFIG_INIT_STACK_NONE=y`, so max coil current, both boost voltages and the first trip level
came from stack garbage. For TFA9874 the driver also wrote DCVOS to register 0x70 instead of
0x76: NXP's field map in the OnePlus vendor kernel
(`techpack/audio/asoc/codecs/tfa98xx-v6/tfa9874_tfafieldnames.h`) gives
`TFA9874_BF_DCVOS = 0x7695` (reg 0x76, bits 14:9), and bits 14:9 of 0x70 hold DCDIS (DC-DC
on/off) and DCIE. DCMCC, DCIE, DCTRIP, DCTRIP2 and DCVOF were checked and match. Patch
`0001-ASoC-tfa9872-fix-uninitialized-DC-DC-config.patch` zero-initializes and fixes the
register. Upstream `tfa9872.c` uses CRLF line endings, so the patch hunks do too; the new
`.gitattributes` keeps git from converting `*.patch` files.

Not fixed and not fixable here: the driver disables the amps' current/voltage sense and runs
no protection algorithm. Per NXP's TFA9874B data sheet, speaker protection for this part runs
on the host DSP using that sense data. Volume limits are in `hardware-safety.md` 4.4.

### 9.4 Regulators compared against the OnePlus vendor DT - **1 deviation, FIXED (patch 0002)**

All 37 RPMh regulators in the Xo666 board DTS were compared, min and max, with
`kona-regulators.dtsi` from `19821`. 36 match or are tighter. The exception, `vreg_l2f_1p2`
(PM8009 LDO2), was 1.2 V where the vendor DT has exactly 1.1 V; the vendor camera DT
(`camera/kona-oem-camera-instantnoodle.dtsi`) uses it as `cam_v_custom2` of the rear main
camera at 1100000 uV, only while that camera is on. In the Xo666 DTS it had no consumer and was
`regulator-always-on`, like all seven PM8009 LDOs, although only L3F and L7F feed anything
(front camera). Across 82 vendor DT files, PM8009 LDOs feed only camera modules. Patch
`0002-arm64-dts-qcom-instantnoodle-match-PM8009-camera-rails-to-OEM.patch` drops
always-on from L1F/L2F/L4F/L5F/L6F and sets L2F to 1.1 V; the front camera's AVDD is a
GPIO-switched fixed regulator with no PM8009 input. Verified by building the DTB and
decompiling it.

**Correction after the first boot on hardware (2026-10-01):** the first version asked for exactly
1100000 uV. L2F is a `pmic5_nldo` (320 mV + n x 8 mV), so 1.100 V is not a valid setting; the
regulator core failed with -ENOTRECOVERABLE and the whole PM8009 regulator device did not probe.
That left the QCA6390 WiFi/BT power unit (supplied by S2F), the front camera and its EEPROM in
deferred probe. Nothing was over-volted; the rails simply stayed off. Fixed to 1104000 uV, the
step the vendor driver rounds 1.1 V up to and the value L1F already uses (kernel pkgrel 5). The
DTB compile check could not catch this: only a boot on the device did.

Also checked against the vendor DT and found fine: flash LED (300 mA torch, 1 A flash,
1.28 s, equal to vendor defaults and below the vendor maxima of 500 mA / 1.5 A); GPU OPP
table (670 MHz is gated by `opp-supported-hw` and the `gpu_speed_bin` fuse, so a plain 865
stays at 587 MHz); CPU thermal trips (90/95 °C passive, 110 °C critical).

### 9.5 The documented install flow could not work - **FIXED in the main doc**

Checked in pmbootstrap 3.11.1:

- `pmbootstrap install --split` cannot be followed by `pmbootstrap flasher flash_rootfs` on
  the `fastboot` method: `pmb/flasher/frontend.py:rootfs()` looks for `<device>.img`, which
  only exists without `--split`, and `print_flash_info()` deliberately omits `flash_rootfs`
  when `split` does not match the flasher's `split` flag. With `--split` the sparse conversion
  is skipped too. The official 8 Pro wiki uses plain `pmbootstrap install`.
- `pmbootstrap flasher flash_boot` does not exist for `fastboot` (only for
  `fastboot-bootpart`); the right action is `flash_kernel`.
- vbmeta was presented as mandatory, citing GSI guides. The official 8 Pro and 8T packages do
  not set a vbmeta partition and their wiki install flows never write it.
- Fastboot key combination: Volume Up + Volume Down + Power (wiki), not Volume Down + Power.
  The "OEM unlocking" developer option was missing.
- The risk table's "`fastboot flash super` corrupts the GPT, hard brick, no fastboot" has no
  mechanism: Qualcomm's reference ABL (`QcomModulePkg/Library/FastbootLib/FastbootCmds.c`)
  rejects an image larger than the partition before writing, for sparse and raw images.

### 9.6 deviceinfo - **FIXED**

- `deviceinfo_super_partitions` is not "read by nothing": not by pmbootstrap, but the
  initramfs runs `setup_dynamic_partitions "${deviceinfo_super_partitions:=}"`
  (`init_2nd.sh`), which calls `make-dynpart-mappings` on each listed partition if that tool
  is installed. With the rootfs written raw over `super` there are no logical partitions, and
  `mount_subpartitions` finds the pmOS image by scanning every partition anyway, so the field
  was removed. The wiki partition dump confirms `super` is `/dev/sda14` on this phone.
- The file no longer matched its sha512sum (the vbmeta line was added after the last build),
  so the package did not build as committed. Checksum regenerated, pkgrel bumped.
- The initramfs never touches the phone's real GPT: `resize_root_partition` only resizes the
  nested table inside the loop-mapped `super`, unless `PMOS_FORCE_PARTITION_RESIZE` is on the
  kernel command line (it is not).

### 9.7 No firmware was ever installed - **FIXED**

`device-oneplus-instantnoodle` depended on `firmware-oneplus-instantnoodle`, whose main
package is empty; the files live in subpackages, which apk never installs on its own, and
pmbootstrap only auto-adds a `device-*-nonfree-firmware` subpackage. So the image had no zap
shader, no DSP firmware and no WiFi firmware. The device package now depends on the adsp,
cdsp, gpu, venus and wifi subpackages (slpi left out: sensors are unsupported). The official
8 Pro and 8T packages have the same pattern.

### 9.8 ALSA UCM package claimed to be alsa-ucm-conf - **FIXED**

It declared `provides="alsa-ucm-conf"` while shipping two files, which lets apk skip the real
package (and with it `ucm2/ucm.conf`). pmaports CI (`.ci/testcases/test_provides.py`) also
requires any alsa-ucm-conf provider to be versioned `0.*`. It now depends on alsa-ucm-conf.

### 9.9 Smaller items

- Kernel sources are pinned by sha512: `pmbootstrap checksum --verify` passed on 2026-10-01 for
  all five packages, so the Xo666 branch tarball is byte-identical to the one built in August.
- A/B slots: pmOS here has no `qbootctl`, so it never marks boots successful. Harmless as long
  as OxygenOS left the active slot marked successful; checked with `fastboot getvar` in
  `hardware-safety.md` 4.2.
- `pcie2` (the SDX55 modem link) is enabled in the DTS but nothing powers the modem, and no
  modem firmware or EFS-writing service is installed.
- `core.autocrlf=true` on the Windows checkout: added `.gitattributes` (`eol=lf`, `*.patch -text`).

---

## 10. First boot on the real phone (2026-10-01)

OnePlus 8 IN2013, OxygenOS 13.1.0.590(EX01) firmware, slot b. Wrote only `dtbo_b`, `boot_b` and
`super` (vbmeta untouched), after a full verified backup of every partition except `userdata`.

- **Kernel r4** booted to the console login on the first try (display, touch, UFS, USB networking).
  Its patch 0002 asked PM8009 L2F for an unrepresentable 1.100 V, so the whole PM8009 regulator
  device failed and WiFi/BT/front camera stayed in deferred probe (section 9.4 correction).
- **Kernel r5** (L2F 1.104 V): `vreg_l2f_1p2: Setting 1104000-1104000uV`, zero deferred probes,
  `wlan0` up with ath11k firmware WLAN.HST.1.0.1.r1-01272 (2022-12-20), `hci0` present (needs
  `linux-firmware-qca`, now a device dependency), front camera EEPROM detected.
- **GPU:** devfreq offers 305-587 MHz (no 670 MHz step: the speed-bin fuse is read correctly);
  SQE/GMU firmware fails at early boot (rootfs not mounted yet) and loads on first open of the
  render node ("Loaded GMU firmware v2.1.8").
- **Battery (bq27411):** 4.356 V at 100%, 27.7 °C, not charging past full. The gauge reports a
  learned full capacity of 3056 mAh against 4270 mAh design, right after the driver rewrote its
  configuration; not trusted as a wear figure yet.
- **Thermal:** all zones 30-33 °C idle, `qcom_tsens` and `qcom_spmi_temp_alarm` loaded.
- **DSPs:** ADSP and CDSP running, SLPI offline (no firmware, intended). The SDX55 modem enumerated
  on PCIe but `mhi-pci-generic` could not power it up; no MHI devices, no rmtfs, so nothing touched
  the EFS partitions.
- **Speaker amps:** both TFA9874 found (rev 0x0c74). Audio is only partial (q6afe vote error,
  va_macro probe -110), matching the wiki's "P".
- **Firewall:** nftables active with input policy drop; port 22 open on all interfaces.
- **Regulators:** all 39 within their DTS limits (which match the OnePlus vendor limits); rear
  camera rails unused and off, front camera L3F/L7F on.

- **Speaker test (later the same evening):** a 1 kHz tone at -30 dBFS (peak 1036/32767, 2 s, fades)
  through `TERT_MI2S_RX Audio Mixer MultiMedia1` on `hw:0,0` played cleanly, no pops. Left channel
  came out of the top (earpiece, TFA9874 @ 0x34), right channel out of the bottom (main speaker,
  @ 0x35), matching the DTS. There is no hardware volume control on this path, so loudness depends
  only on the digital level; any future PipeWire setup needs a limiter before going louder.
- **Firewall hardening applied:** SSH dropped on `wlan*` (`/etc/nftables.d/40_ssh_usb_only.nft`),
  verified unreachable from the LAN and reachable over USB.

- **Charger state read directly from the PMIC** (regmap debugfs `0-02` = PM8150B, read-only):
  `0x1070 = 0x4d` -> float voltage 3.6 V + 77 x 10 mV = **4.37 V**; `0x1061 = 0x28` -> 2.0 A fast
  charge current; `0x1370 = 0x20` -> 1.6 A USB input limit; `0x1006 = 0x45` -> TERMINATE (OnePlus
  `smb5-reg.h` enum: 0 INHIBIT, 1 TRICKLE, 2 PRE, 3 FULLON, 4 TAPER, 5 TERMINATE); `0x1007 = 0x28`,
  BAT_OV clear. With no charger driver in this kernel nothing rewrites these values, so a
  discharge/recharge test is not needed to know the ceiling. The community driver also gets this
  status enum wrong (it starts at TRICKLE = 0, the PMI8998 layout).

- **Cold boot re-check:** after `systemctl poweroff` with USB connected, the bootloader started
  off-mode charging (`androidboot.mode=charger`, `startupmode=dc_charger`), which now boots pmOS
  from `boot_b`. The PM8150B registers read back identical (`1070=4d` 4.37 V, `1061=28` 2.0 A,
  `1370=20` 1.6 A, TERMINATE), so the bootloader sets them at every power-on; they are not
  leftovers from OxygenOS. Bluetooth firmware loaded ("QCA setup on UART is completed").
- Side effect worth knowing: a powered-off phone now boots straight into pmOS when a charger is
  plugged in. To keep it off, unplug first, then power off.
