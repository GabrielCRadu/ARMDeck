# Hardware safety and preparation before flashing (OnePlus 8, `instantnoodle`)

First written on 2026-10-01 after a full project audit with the phone in hand, and updated as
the project moved on. Every claim below has its source listed at the end or was checked
directly in code (the Xo666 kernel, pmbootstrap 3.11.1, the postmarketOS initramfs, the OnePlus
device tree in the LineageOS kernel). What could not be checked without the phone is marked
**UNVERIFIED**.

**About "100% safe".** Nobody can guarantee that for an unofficial port: the Xo666 kernel has
no public install reports from other users. What can be done, and what this document does:
(1) separate what can cause **physical damage** from what only causes "does not boot"; (2) for
every physical risk, have a concrete measure (a code fix, a component switched off, a limit)
and a precise test; (3) write nothing to the phone before a complete, verified backup exists.

Terms used often:
- *PMIC* = the chip that makes all the voltages in the phone and charges the battery (here:
  PM8150, PM8150B for charging, PM8150L, PM8009 for the cameras).
- *regulator / LDO* = one voltage output of a PMIC, feeding one component.
- *float voltage* = the maximum voltage the charger holds the battery at when it is full.
- *EDL* = Qualcomm's emergency mode (9008); it works even if the bootloader is destroyed.
- *A/B slot* = the phone has two copies of the boot partitions (`boot_a`/`boot_b` etc.) and
  boots from the "active" slot.
- *EFS* = the partitions with the IMEI and the modem calibration (`modemst1/2`, `fsg`, `fsc`,
  `mdm1m9kefs*`).

---

## 0. In short: what can actually break something

| # | Risk | Consequence | State in the project | How to check |
|---|---|---|---|---|
| 1 | Re-locking the bootloader with modified software on the phone | A phone that no longer boots; only EDL/MSM can fix it | Procedure rule | Never run `fastboot flashing lock` (section 3.4) |
| 2 | The community PM8150B charger driver (`qcom_pm8150b_charger.c`) | Battery pushed toward ~4.87 V instead of 4.435 V: wear, swelling, fire risk | **Not in our kernel.** The patch that prepared the ground for it was removed | 4.1, the charging test |
| 3 | Speakers without protection | A speaker (especially the earpiece) burnt at sustained high volume | Configuration bug fixed (patch 0001); protection is still missing, a volume ceiling replaces it | 4.4 |
| 4 | Camera regulators above the OnePlus voltage, permanently on | Continuous electrical stress on the camera modules | Fixed (patches 0002 and 0005) | 4.6, `regulator_summary` |
| 5 | Writing to the wrong partitions | From "Android no longer boots" to a lost IMEI | Flash procedures corrected, initramfs checked | 2 and 3 |
| 6 | Overheating | Throttling, protective shutdown; small risk of damage | Thermal zones present, plus the ARMDeck battery-temperature guard | 4.8 |
| 7 | USB PD chargers asking for more than 5 V | Untested input voltage on a board with no charger driver | Fixed (patch 0004): the phone asks only for 5 V | 4.11 |

Everything else (display, GPU, Wi-Fi, DSPs, USB) can at worst not work, with no plausible
mechanism for physical damage, under the conditions in section 4.

---

## 1. What you need before anything else

1. **The exact model.** Settings > About phone. It must be IN2013 (Europe), IN2015 (USA,
   unlocked), IN2011 (India) or IN2010 (China). **IN2017 (T-Mobile)** needs an unlock token
   from OnePlus after the SIM unlock. **IN2019 (Verizon)** cannot be unlocked officially: if you
   have an IN2019, stop here. Only IN2013 has been tested with ARMDeck so far.
2. **The exact OxygenOS version** (Settings > About phone > Version). Note the region code in
   the build too (e.g. `IN21AA` global, `IN21BA` Europe, `IN21DA` India).
3. **To download on the PC (Windows), before unlocking:**
   - Google *platform-tools* (adb + fastboot, current version).
   - The Qualcomm USB drivers (for EDL/MSM) and the Google USB driver for fastboot.
   - **The MSM Download Tool package for your region** (the XDA thread "[OP8][OOS 21AA/BA/DA]
     Unbrick tool"). It is the final safety net: it rewrites the whole phone through EDL.
   - The full update package (*full OTA zip*) for the OxygenOS version you have now. Original
     images (`boot`, `dtbo`, `vbmeta`) can be extracted from it with `payload-dumper-go`.
   - For the backup: the TWRP image for instantnoodle (3.7.0 for Android 13) **or** the Magisk
     app (option B in section 2.4).
4. **Space on the PC:** at least 15 GB free just for the backup, ideally on two different disks.
5. **A good USB-C data cable**, in a USB port directly on the motherboard (not a hub).
6. **Battery above 60%** before every flashing session.
7. Optional, but recommended for the tests in section 4: a **USB-C tester** (shows the voltage
   and current on the cable, about 10-15 EUR) and a plain 5 V charger (USB-A) with a USB-A to
   USB-C cable.

---

## 2. Backup, in this order

### 2.1 Personal data

Unlocking the bootloader **erases everything** (photos, apps, accounts). Copy what you care
about first. This is the only certain loss in the whole process.

### 2.2 The phone's state, before any change

Boot into fastboot: phone off, hold **Volume Up + Volume Down + Power** (per the postmarketOS
wiki). Careful: if you hold only the volume buttons with the USB cable connected and the phone
off, it can enter EDL (black screen, Windows sees "QDLoader 9008"); in that case unplug the
cable and hold Power for about 10-20 seconds to leave it.

```
fastboot getvar all 2> getvar-before.txt
```

From the file, note: `product`, `variant`, `unlocked`, `current-slot`,
`slot-successful:a/b`, `slot-unbootable:a/b`, `slot-retry-count:a/b`,
`partition-size:super`, `max-download-size`, the bootloader version.

### 2.3 Unlocking the bootloader

1. Settings > About phone > tap *Build number* 7 times (enables Developer options).
2. Developer options: enable **OEM unlocking** and **USB debugging**.
3. `adb reboot bootloader`, then `fastboot flashing unlock`, confirm on the phone with the
   volume keys.
4. The phone wipes itself and reboots into Android. Do the minimal setup.

Unlocking does not touch `persist`, EFS or `super` (only `userdata`), so the backup below still
captures all the original partitions.

### 2.4 Backing up every partition (except `userdata`)

The postmarketOS wiki for the OnePlus 8 and 8 Pro explicitly asks for a backup of `super`
before any flashing. We take **everything**, because some partitions are unique to each phone
and exist in no update package: `persist` (sensor and fingerprint calibration), `modemst1`,
`modemst2`, `fsg`, `fsc`, `mdm1m9kefs1/2/3/c` (EFS/IMEI for the external 5G modem),
`mdm_oem_dycnvbk`, `mdm_oem_stanvbk`, `param`, `devinfo` and others.

**Option A: TWRP booted temporarily (nothing is written to the phone)**

```
fastboot boot twrp-instantnoodle.img
```

If TWRP asks whether to keep the system *read-only*, **keep it read-only** (do not swipe
"Allow modifications"). Do not install TWRP, do not format, do not "repair" anything from it.
Then, from Git Bash on Windows (with platform-tools in the PATH; `adb` from WSL does not see
USB):

```
mkdir backup-op8 && cd backup-op8
adb shell ls -l /dev/block/by-name/ > partitions.txt
for p in $(adb shell ls /dev/block/by-name/ | tr -d '\r'); do
  case "$p" in userdata|reserve_a|reserve_b) continue ;; esac
  adb pull "/dev/block/by-name/$p" "$p.img"
done
```

(`reserve_a/b` are links to a file inside `userdata`, so they are skipped.)

**Option B: temporary root with Magisk (still no permanent write)**

Extract `boot.img` from your version's full OTA, patch it in the Magisk app, then
`fastboot boot magisk_patched.img`. With Android running:

```
adb exec-out su -c "cat /dev/block/by-name/persist" > persist.img
```

repeated for each partition in the `ls /dev/block/by-name/` list.

**UNVERIFIED:** whether your bootloader (after OxygenOS 13) accepts `fastboot boot`. XDA
reports for instantnoodle say it does. If it refuses, **do not** flash TWRP/Magisk permanently
to get around it: ask first, there are other options (including reading through EDL with
`bkerler/edl`, which does not even need an unlocked bootloader).

### 2.5 Verifying the backup (required)

For the critical partitions, compare the hash on the phone with the one on the PC:

```
adb shell "cd /dev/block/by-name && sha256sum persist modemst1 modemst2 fsg fsc mdm1m9kefs1 mdm1m9kefs2 mdm1m9kefs3 mdm1m9kefsc mdm_oem_dycnvbk mdm_oem_stanvbk param super"
sha256sum persist.img modemst1.img modemst2.img fsg.img fsc.img mdm1m9kefs1.img mdm1m9kefs2.img mdm1m9kefs3.img mdm1m9kefsc.img mdm_oem_dycnvbk.img mdm_oem_stanvbk.img param.img super.img
```

With option B, run the first command as `adb shell su -c "..."`. All hashes must match. Then
copy the folder to the second disk.

---

## 3. Installing, step by step, with minimal writes

### 3.1 What is written and what is not

pmbootstrap writes **only** to: `dtbo` and `boot` (of the active slot), `super` (shared) and,
optionally, `vbmeta` (active slot). Nothing else. The bootloaders (`xbl`, `abl`), TrustZone,
`persist`, EFS and the GPT (the partition table) are not touched. In Qualcomm's reference
bootloader (ABL, which the OnePlus one is based on), an image larger than its partition is
refused **before** any write ("Image is too large for the partition",
`QcomModulePkg/Library/FastbootLib/FastbootCmds.c`, for both sparse and raw images). So a
wrong `fastboot flash super` cannot spill over into the GPT or other partitions.

On the phone, the postmarketOS initramfs only resizes the partition table **inside** the image
written to `super`, never the real GPT (checked in `init_functions_2nd.sh`), unless you put
`PMOS_FORCE_PARTITION_RESIZE` on the kernel command line. Do not.

### 3.2 Building the images (in WSL)

The password chosen at `pmbootstrap install` is also the SSH password: pick a serious one. Any
image built with a test password must be rebuilt before flashing.

```
pmbootstrap install              # WITHOUT --split, with your password
pmbootstrap export               # puts links in /tmp/postmarketOS-export
cp -L /tmp/postmarketOS-export/{boot.img,dtbo.img,oneplus-instantnoodle.img} /mnt/c/op8-flash/
```

`oneplus-instantnoodle.img` is the root filesystem with the inner partitions `pmOS_boot` and
`pmOS_root`, already in *sparse* format (the compressed format fastboot understands).

Flash from Windows with `fastboot.exe`, because WSL2 does not see USB directly (the
alternative is `usbipd-win`, but the phone reconnects at every reboot).

### 3.3 Flashing

With the phone in fastboot:

```
fastboot getvar current-slot                 # note it: a or b
fastboot getvar partition-size:super         # must be larger than the image
fastboot flash dtbo dtbo.img
fastboot flash boot boot.img
fastboot flash super oneplus-instantnoodle.img
fastboot reboot
```

**vbmeta is optional.** The official 8 Pro and 8T ports do not write it and boot with the
bootloader unlocked. Use it only if the bootloader refuses the boot image:

```
fastboot --disable-verity --disable-verification flash vbmeta vbmeta_X.img   # X = the active slot, from the backup
```

First boot: the postmarketOS logo, then a network adapter appears over USB, the phone has the
IP `172.16.42.1`, and you connect with `ssh user@172.16.42.1`.

### 3.4 What you never do

- `fastboot flashing lock` / `fastboot oem lock` with anything other than original OxygenOS on
  the phone.
- `fastboot erase ...`, `fastboot -w`, `fastboot flash` to any partition other than those in
  3.3, `fastboot flashing unlock_critical` (not needed).
- `fastboot --set-active=...` (see the slot test in 4.2), except when restoring.
- From Linux: `dd`, `parted`, `gparted`, `mkfs` on `/dev/sda*`, `/dev/sdb*`... The only pmOS
  partition is the one mapped from `/dev/sda14` (`super`). The exceptions are ARMDeck's own
  scripts that say so explicitly (`format-games.sh`).
- The WuerfelDev kernel, the official pmOS SM8250 kernel or their charger driver (section 4.1).
- On the phone: `apk upgrade --prune` or `apk upgrade --available`. The kernel, the firmware and
  the device package are built locally and do not exist in the online repositories, and these
  options can remove or replace them. A plain `apk upgrade` is fine. A new kernel installed on
  the phone only reaches `/boot`; the `boot_b` partition is still updated from the PC.

### 3.5 Going back to Android

1. `img2simg super.img super-s.img`, then `fastboot flash super super-s.img`.
2. `fastboot flash boot boot_X.img`, `fastboot flash dtbo dtbo_X.img` (and `vbmeta` if you
   changed it), where X is the slot noted in 3.3, from the backup.
3. If something does not work: the MSM Download Tool with your region's package (EDL).

### 3.6 Check: the way back to stock, for each scenario (2026-10-01)

Our flow never writes to the bootloader (`xbl`, `abl`), so fastboot cannot be lost through it.
The only paths to a phone without fastboot are re-locking the bootloader with modified software
or manual writes to other partitions, both forbidden in 3.4.

| Scenario | The way back | What must exist | State |
|---|---|---|---|
| pmOS does not boot, black screen, boot loop | Power + Volume Down for about 12-15 s (hardware reset from the PMIC), then Volume Up + Volume Down + Power, then restore from the backup (below) | a verified backup, fastboot on the PC, the fastboot driver | verified on hardware |
| The phone switched to the other slot | `fastboot --set-active=X`, then as above | the original slot, noted | noted at backup time |
| Fastboot unreachable | EDL + MSM Download Tool | your region's MSM package, the Qualcomm 9008 driver, a tested EDL entry | to prepare before flashing |
| IMEI, fingerprint or sensors affected | `fastboot flash <partition>` or `dd` with root, from the backup | a verified backup | done |
| The `super` backup is incomplete or corrupt | a round-trip `img2simg` / `simg2img` test with an identical hash, size equal to `partition-size:super` | `img2simg` | installed in WSL |
| Battery fully drained under pmOS | hardware charging with the phone off or in fastboot | nothing | best avoided below about 15% |

Full restore, with explicit slot names so nothing is written to the wrong slot (X = the slot
noted at backup time):

```
fastboot flash boot_X boot_X.img
fastboot flash dtbo_X dtbo_X.img
fastboot flash vbmeta_X vbmeta_X.img
img2simg super.img super-s.img          # in WSL
fastboot flash super super-s.img
fastboot --set-active=X                 # only if the slot changed
fastboot reboot
```

If the backup's `boot` contains Magisk, the restore brings the phone back exactly to its
earlier state (official OxygenOS with root). **Do not flash pmOS until every row is green**,
including the EDL test.

---

## 4. Hardware inventory: what Linux touches and how we test it

For each component: what the Xo666 kernel does (with ARMDeck's patches), what can go wrong
physically, what has been checked, and the precise test to run on the phone.

### 4.1 Battery and charging (PMIC PM8150B, the SMB5 part)

- **What the kernel does:** nothing. The Xo666 kernel has no driver for
  `qcom,pm8150b-charger` (checked: `qcom_pm8150b_charger.c` and `qcom_fg.c` are missing).
  Charging stays on the settings the bootloader leaves in the PMIC, with the PMIC's hardware
  protections (including the temperature cut-off) and the protection circuit in the battery
  pack.
- **The real risk is the community driver** in the WuerfelDev fork and in the official
  postmarketOS SM8250 kernel (including the `sm8250-7.2.0` tag, 2026-08-29). It has four
  confirmed bugs:
  1. It writes the maximum charge voltage with the formula of the older PMI8998 chip
     (`(uV - 3487500) / 7500 + 1`). The PM8150B uses 3.6 V + 10 mV per step (the OnePlus
     driver `qpnp-smb5.c`: `smb5_pm8150b_params.fv`). For our battery (4.435 V) that gives the
     value 127, i.e. **about 4.87 V**. Confirmed independently on the Retroid Pocket 5 (also
     SM8250 + PM8150B): register `0x1070` read back `0x7a` = 4.82 V for a 4.40 V battery.
  2. It does not set the charge current (it stays at the hardware value of 5.35 A).
  3. It "feeds" the charger watchdog at address `0x643` instead of `0x1643`, i.e. it writes to
     another PMIC peripheral (the same bug was fixed in the official Linux kernel on 2026-09-09
     for the parent driver `qcom_smbx`).
  4. It numbers the charger states wrongly: it puts TRICKLE at 0, but on the PM8150B state 0
     is INHIBIT (OnePlus `smb5-reg.h`), so it reports the wrong state.
  For comparison, OnePlus holds the battery at 4.435 V at normal temperature, stops charging in
  software above 4.445 V and treats anything above **4.55 V** as a fault (`kona-mtp.dtsi`:
  `temp_normal_vfloat_mv = 4435`, `vbatt_hv_thr = 4550`). When warm it goes down to 4.13 V; the
  mainline kernel does not.
- **What changed in the project:** the patch that only added the device tree nodes for the
  charger was removed (it did nothing without a driver, but it would have enabled the bug above
  the moment someone added the driver).
- **Test (first charging sessions):** a plain 5 V charger, phone idle, screen off. Over SSH:
  ```
  while true; do date +%T; cat /sys/class/power_supply/*/voltage_now /sys/class/power_supply/*/temp 2>/dev/null; sleep 10; done | tee charging.log
  ```
  The battery voltage (in µV) **must not exceed 4450000**. The battery temperature (tenths of a
  degree) should stay below 400. If either is exceeded: unplug and stop. Repeat once from about
  90% to full, to see where it stops.
  **Verified 2026-10-01** by reading the PMIC directly (regmap debugfs `0-02`, read only):
  `0x1070 = 0x4d` = **4.37 V** maximum voltage, `0x1061 = 0x28` = 2.0 A charge current,
  `0x1370 = 0x20` = 1.6 A input limit, state TERMINATE (full), no BAT_OV bit. With our kernel (no
  charger driver) nothing changes these values. Repeated after a cold boot: identical values,
  so the bootloader sets them at every boot.

### 4.2 Bootloader, A/B slots, vbmeta, fuses

- **What the kernel does:** nothing with the bootloader. Nothing in mainline Linux blows fuses
  (*qfuses*, write-once bits in the SoC). The hardware anti-rollback OnePlus introduced in 2026
  came to the OnePlus 13/13T/15, not the OnePlus 8; and ARMDeck does not write bootloaders.
- **Slots:** the Qualcomm bootloader decrements a retry counter at every boot if the slot is not
  marked "successful" and, at zero, switches to the other slot (which has the old Android and
  no valid `super`, so it does not boot). ARMDeck installs `qbootctl`
  (`userspace/power/install-qbootctl.sh`), which marks the active slot successful at every
  boot, as Android does.
- **Test:** after the first 3-4 pmOS boots, enter fastboot and compare with `getvar-before.txt`:
  ```
  fastboot getvar slot-successful:X
  fastboot getvar slot-retry-count:X
  fastboot getvar current-slot
  ```
  They must stay `yes`, the same counter, the same slot.

### 4.3 Fuel gauge (`ti,bq27411`, I2C 0x55)

- **What the kernel does:** the `bq27xxx` driver reads the battery level and, because the node
  has `monitored-battery`, writes the capacity (4270 mAh), energy (16.37 Wh) and termination
  voltage (3.4 V) to the chip's RAM at boot. The RAM configuration is lost only when the battery
  is disconnected. It does not control charging, it only affects the reported percentage.
- **Risk:** a wrong percentage, nothing physical.
- **Test:** `cat /sys/class/power_supply/bq27411-0/uevent`; the voltage must be plausible
  (3.4-4.45 V) and rise while charging.

### 4.4 Speakers (2x NXP TFA9874 on I2C15: 0x34 earpiece, 0x35 main speaker)

- **What the kernel does:** the Xo666 `tfa9872.c` driver starts the amplifiers without NXP's
  protection algorithm and explicitly disables the current and voltage sensing. Per the data
  sheet, on the TFA9874 speaker protection (thermal and mechanical) runs on the host DSP, based
  on that sensing; on Android OnePlus does it. Here nothing does. The amplifier gain stays at
  the chip default and the driver exposes no volume control.
- **Bug fixed (patch 0001):** the function that configures the amplifiers' boost converter read
  four values from uninitialized variables (the kernel has `CONFIG_INIT_STACK_NONE=y`), so the
  maximum coil current and the boost voltage depended on whatever was left on the stack. Plus a
  write to the wrong register. They now use the chip's default values.
- **Remaining risk:** a speaker overheated or mechanically damaged at sustained high volume,
  especially the earpiece (it is small and gets little signal on Android).
- **Measures:** all sound goes through the "Speakers (protected)" PipeWire filter
  (`userspace/audio/50-op8-speakers.conf`): a 250 Hz high-pass (protects the small drivers from
  bass excursion), a clamp at 0 dBFS, and 3 dB less for the earpiece. The volume of the direct
  ALSA output is the ceiling for everything that goes through PipeWire. Never play with `aplay`
  on the host: that bypasses PipeWire.
- **The ceiling, step by step:** -30 dB tested clean on 2026-10-01 (1 kHz tone, no clicks;
  the left channel comes out of the top earpiece, the right one out of the bottom speaker).
  -24 dB and then -18 dB on 2026-10-03, each step listened to. The amplifier delivers up to
  5.6 W into 8 Ω (data sheet); at -18 dB a full-scale tone gives at most about 89 mW on the
  bottom speaker and 45 mW on the earpiece, far below what a phone speaker takes. Going higher
  needs an average-power limiter first (a slow RMS compressor in the filter).
- **Test:** `dmesg | grep -i tfa` must show two chips with revision `0x0c74`.

### 4.5 Regulators (PM8150, PM8150L, PM8009 through RPMh)

- **Checked:** the min/max limits of the 37 regulators in the Xo666 DTS were compared with
  `kona-regulators.dtsi` from the OnePlus 8 DT (project `19821`). 36 identical or stricter. The
  only deviation: L2F (see 4.6), fixed.
- **Test:** `cat /sys/kernel/debug/regulator/regulator_summary`. No voltage above what the DTS
  says.

### 4.6 Cameras (PMIC PM8009 and GPIO supplies)

- **Problem found (2026-10-01):** Xo666 forced all seven LDOs of the camera PMIC on
  permanently, although only L3F and L7F have a consumer (the front IMX471 camera). L2F was at
  1.2 V; OnePlus uses it at exactly 1.1 V, only while the rear main camera is on
  (`kona-oem-camera-instantnoodle.dtsi`). Across the OnePlus 8 DT (82 files), the PM8009 LDOs
  feed only cameras.
- **Fixed (patch 0002):** L1F, L2F, L4F, L5F, L6F are no longer forced on; L2F at 1.104 V. The
  first version of the patch asked for exactly 1.100 V, a value this kind of regulator cannot
  produce (8 mV steps from 320 mV). On the first boot the whole PM8009 group failed and Wi-Fi/
  Bluetooth (their power chip depends on S2F) and the front camera were left without power.
  Nothing dangerous (rails off, not overvolted), but a compile check cannot catch that: it only
  shows on the phone. 1.104 V is the step the OnePlus driver rounds 1.1 V up to.
- **Cameras off completely (patch 0005, 2026-10-03):** ARMDeck has no use for cameras, and the
  camera kept parts of the SoC awake. Every camera supply lost `regulator-always-on`: the GPIO
  supplies 24 (front), 26 and 156 (rear main), L7C (autofocus motor), L3F and L7F (front
  sensor). `camss`, `cci0` and `cci1` are disabled. The cameras end up as on Android with the
  camera app closed: no supply on, no voltage changed. Checked against the OnePlus camera DT
  (GPIO 24, 26 and 156 are camera supplies only; L7C appears only as a camera supply) and on the
  phone (none of these supplies had any other consumer).
- **Test:** no `qcom_camss` or `imx471` in `lsmod`; `cam_*` regulators `disabled` in
  `/sys/class/regulator/*/state`.

### 4.7 AMOLED display (`samsung,amb655uv01`, DSI)

- **What the kernel does:** the panel driver sends the initialization sequence; the panel
  supplies go through the regulators checked in 4.5.
- **Risk:** a black screen (not physical). AMOLED wear (*burn-in*) from bright static images
  for hours: dark theme, automatic screen-off, moderate brightness.

### 4.8 Thermal (TSENS, LMh, thermal zones)

- **What the kernel does:** the thermal zones and the CPU/GPU throttling come from
  `sm8250.dtsi`. Careful: `QCOM_TSENS`, `QCOM_SPMI_TEMP_ALARM` and `QCOM_LMH` are **modules**, so
  the software thermal protection exists only once they load from the root filesystem.
  Independently of the OS, the SoC resets itself in hardware at a critical temperature.
  ARMDeck adds `op8-thermal`, which limits the big CPU cores and the GPU by battery temperature
  (41-44.5 °C).
- **Test:**
  ```
  lsmod | grep -E "tsens|lmh|temp_alarm"
  for z in /sys/class/thermal/thermal_zone*; do echo "$(cat $z/type) $(cat $z/temp)"; done
  ```
  Then a 2-minute stress test (`stress-ng --cpu 8 --timeout 120`) with the temperatures
  logged. The thresholds in `sm8250.dtsi`: throttling from 90 °C, stronger at 95 °C, protective
  shutdown at 110 °C. The frequencies must drop when the CPU zones reach 90 °C; if they pass
  95 °C without dropping, stop the test.

### 4.9 GPU (Adreno 650)

- **What the kernel does:** loads the signed `a650_zap.mbn` shader (firmware without which the
  GPU does not start). The 865+'s 670 MHz step is enabled only if the chip's fuses say it is an
  865+ (`opp-supported-hw` + `gpu_speed_bin`), so on a plain 865 the maximum stays at 587 MHz.
- **Test:** `cat /sys/class/devfreq/3d00000.gpu/available_frequencies` (maximum 587000000 on a
  plain 865) and `dmesg | grep -iE "zap|a6xx|adreno"`.

### 4.10 CPU

- The frequencies come from the SoC's hardware table (*cpufreq-hw*); the kernel cannot exceed
  what the chip allows. Physical risk: none identified.

### 4.11 USB-C, Power Delivery, OTG, DisplayPort

- **What the kernel does:** the Type-C controller in the PM8150B negotiates USB PD. The Xo666
  DTS accepted 5 V fixed and 5-12 V variable as a sink, so with a PD charger the phone could ask
  for more than 5 V; without a charger driver, nobody had tested what the PMIC does with 9-12 V
  at its input. On Android the OnePlus 8 never used PD above 5 V (its fast charging is Warp,
  5 V / 6 A). The 8 Pro wiki also notes that the PMIC can keep a voltage on the CC pin after a
  restart with a powered hub connected.
- **Fixed (patch 0004, 2026-10-02):** the phone advertises only 5 V / 3 A. Tested with a Samsung
  45 W charger (5 / 9 / 15 / 20 V and PPS): it negotiated USB PD at 5 V / 3 A.
- **Test:** `cat /sys/class/power_supply/tcpm-source-psy-*/voltage_now` (about 5000000), or a
  USB-C tester on the cable.

### 4.12 LED flash (PM8150L)

- **Checked:** 300 mA torch, 1000 mA flash, at most 1.28 s. Identical to the OnePlus defaults
  and below their maximums (500 mA / 1500 mA). Risk: none at these values.

### 4.13 5G modem (SDX55) and the EFS partitions

- **What the kernel does:** since patch 0005 (2026-10-03) the modem's PCIe link (`pcie2`) is
  disabled, so the AP side never talks to the modem. No modem firmware is installed and no
  service writes to the EFS partitions. (On the 8T someone started the SDX55 under mainline,
  with services that write to EFS: one more reason for the backup and for leaving the modem
  off.)
- **Test:** no `17cb:0306` device in `/sys/bus/pci/devices/*/device`, and `pgrep -a rmtfs`
  returns nothing.

### 4.14 Wi-Fi and Bluetooth (QCA6390)

- Set the country: `iw reg set RO` (your country code). Physical risk: none identified.
- **Bluetooth address:** the chip reports the default address from its firmware, so the kernel
  leaves the controller "unconfigured" and BlueZ ignores it. `userspace/system/install-btaddr.sh`
  installs `bootmac`, which sets a fixed address derived from the serial number at every boot;
  its Wi-Fi rule is masked, so the Wi-Fi address does not change.
- **Firmware origin** (compared by git hash with the official linux-firmware):
  `a650_gmu.bin`, `a650_sqe.fw` (GPU, unsigned) and `m3.bin` are identical to linux-firmware;
  `board-2.bin` is the official 2022-04-23 version; `amss.bin` (the Wi-Fi chip firmware) matches
  no linux-firmware version, so it was probably extracted from OxygenOS. The Wi-Fi chip reaches
  memory only through the SMMU (the unit that limits which memory a PCIe device can touch), so
  the risk is limited, but its origin is not verified.

### 4.15 DSPs (ADSP, CDSP, Venus; SLPI off)

- Firmware signed by OnePlus and checked by TrustZone. Wrong firmware = the DSP does not start.
  SLPI (sensors) gets no firmware in our build and stays off. Physical risk: none.

### 4.16 NFC, touchscreen, haptics

- NFC and touch: no physical risk identified. The vibration motor (`awinic,aw8697`) is not in
  the Xo666 DTS, so it is never driven.

### 4.17 The GameSir X3 Pro accessory (Peltier)

- The cooler has its own power supply. Theoretical risk (not confirmed for this product): a
  Peltier element that cools below the dew point can cause condensation. Do not use it in damp
  rooms, and wipe the back of the phone after long sessions.

---

## 5. What remains unverified

- Whether `fastboot boot` works on every bootloader version.
- The exact level at which the speakers get damaged without protection, and the speakers'
  power rating (not published by OnePlus).
- Thermal behaviour under long gaming sessions.
- The Xo666 kernel has no public install reports from other users.

## Sources

- postmarketOS wiki: [OnePlus 8](https://wiki.postmarketos.org/wiki/OnePlus_8_(oneplus-instantnoodle)),
  [OnePlus 8 Pro](https://wiki.postmarketos.org/wiki/OnePlus_8_Pro_(oneplus-instantnoodlep)),
  [OnePlus 8T](https://wiki.postmarketos.org/wiki/OnePlus_8T_(oneplus-kebab))
- OnePlus 8 DT and drivers: [LineageOS/android_kernel_oneplus_sm8250](https://github.com/LineageOS/android_kernel_oneplus_sm8250)
  (`arch/arm64/boot/dts/vendor/oplus/instantnoodle/`, earlier `vendor/19821/`;
  `drivers/power/supply/qcom/qpnp-smb5.c`,
  `techpack/audio/asoc/codecs/tfa98xx-v6/tfa9874_tfafieldnames.h`)
- The float voltage bug: [armada-os/armada#534](https://github.com/armada-os/armada/issues/534),
  [armada-os/armada#550](https://github.com/armada-os/armada/issues/550),
  [ROCKNIX/distribution#3371](https://github.com/ROCKNIX/distribution/pull/3371),
  [ROCKNIX/distribution#3382](https://github.com/ROCKNIX/distribution/pull/3382),
  [the qcom_smbx series on linux-pm](https://ratatoskr.run/linux-pm/2026/08/17399196/t)
- [NXP TFA9874B data sheet](https://www.mouser.com/datasheet/2/302/TFA9874B_SDS-1517291.pdf),
  [Goodix TFA9874](https://www.goodix.com/en/product/audio/smart_amplifier/tfa9874)
- [MSM Download Tool for the OnePlus 8, XDA](https://xdaforums.com/t/op8-oos-21aa-ba-da-unbrick-tool-to-restore-your-device-to-oxygenos.4085877/)
- [OnePlus anti-rollback, 2026](https://www.gsmgotech.com/2026/01/oneplus-quietly-adds-anti-rollback.html)
- [Qualcomm ABL, FastbootCmds.c (CodeLinaro, the reference implementation)](https://git.codelinaro.org/clo/le/abl/tianocore/edk2/-/blob/LU.UM.3.5.1.r1-00700-QCS6490.0/QcomModulePkg/Library/FastbootLib/FastbootCmds.c)
- Code checked: pmbootstrap 3.11.1 (`pmb/config/__init__.py`, `pmb/flasher/frontend.py`,
  `pmb/install/_install.py`), pmaports `main/postmarketos-initramfs`
  (`init_2nd.sh`, `init_functions.sh`, `init_functions_2nd.sh`)
