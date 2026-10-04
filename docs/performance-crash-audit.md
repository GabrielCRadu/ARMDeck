# Performance and crash-prevention audit (2026-10-01)

Done after the unexpected reset during a game download (`gaming-stack.md` 9) and after the
`op8-log` logger was installed. All data was read from the phone, read only: `sysfs`, `/proc`,
the kernel configuration (`/proc/config.gz`), the systemd journal. It complements
[`hardware-safety.md`](hardware-safety.md) (physical risks) and
[`security-audit.md`](security-audit.md).

**Update 2026-10-02:** the cause of the resets was found, and it is none of the suspects below
(Wi-Fi, power, lockup detectors). The Xo666 device tree did not reserve the `removed_mem` memory
region (0x80b00000, about 210 MB), so Linux wrote into secure-world memory once RAM filled up.
Fixed with kernel patch `0003`. Details and tests in `gaming-stack.md` 9, TODO 2. The rest of
the audit stays valid as a list of improvements; items that were done since are marked.

Terms:
- *BCL* = the battery current limiter: on Android it slows the CPU/GPU when the battery voltage
  drops suddenly, so the phone does not shut down.
- *UVLO* = the PMIC's protective shutdown when the voltage falls below a threshold.
- *lockup detector (softlockup/hardlockup)* = kernel code that notices a stuck CPU and logs what
  it was doing, instead of the phone resetting without a trace.
- *NTSYNC* = a kernel mechanism for the synchronization in Windows games; Proton uses it for
  performance.
- *preemption* = how quickly the kernel can interrupt one task to run a more urgent one (input,
  audio, compositor).

## In short

| # | Finding | Importance | Measure | Where |
|---|---|---|---|---|
| C1 | The root filesystem has 3.7 GB free (71% used), Steam takes 6.3 GB | high | Steam library on `userdata` (219 GiB) | config, with OK (done) |
| C2 | The battery has 71.7% of its capacity (3062 / 4270 mAh), no BCL in mainline | medium | Frequency limit on the big cores on battery; watch `bat_mv` in `op8-log` | config (thermal guard done) |
| C3 | All lockup detectors are disabled | high (diagnostics) | Enabled in the next kernel, without panic | kernel (done in r7) |
| C4 | Wi-Fi: OnePlus firmware from 2022, unstable MAC after a reset | medium | Test with `op8-live.sh`; alternatively the linux-firmware version; MAC patch | test, kernel |
| C5 | The 5G modem (SDX55) is active on PCIe, with no driver | low-medium | `pcie2` disabled in the DTS, after checking | kernel (done in patch 0005) |
| C6 | `/boot` (ext2, no journal) is mounted rw and never checked | low | `/boot` read-only + an `e2fsck` check | config (done) |
| P1 | `NTSYNC` is missing | medium | `CONFIG_NTSYNC=y` | kernel (done in r7) |
| P2 | Kernel without preemption (`PREEMPT_NONE`, a server configuration) | medium | `PREEMPT_DYNAMIC` | kernel (done in r7) |
| P3 | The GPU adjusts its frequency every 50 ms | medium | 16-20 ms (frequencies stay at or below 587 MHz) | config (done) |
| P4 | gamescope runs without `CAP_SYS_NICE` | medium | `setcap cap_sys_nice+ep` on gamescope | config (done) |
| P5 | DXVK 3 does not work on the Adreno 650 | high (DirectX games) | DXVK 2.7 (`gaming-stack.md`) | userspace (Proton 11.0 ARM64 ships it) |
| P6 | No `sched_ext` (pocknix's `scx_lavd` scheduler) | low | `SCHED_CLASS_EXT` + BTF | kernel |
| P7 | Transparent huge pages on `always` | low | `madvise` | config (done) |
| P8 | gamescope picks 90 Hz | low | 60 Hz in long sessions | config |

"config" = settings in the root filesystem, applicable now with a sudo script. "kernel" = the
next kernel built in WSL and written to `boot_b`.

## Crash prevention

### C1. Space on the root filesystem

- **Evidence:** `df`: 13.1 GB, 8.8 GB used, 3.7 GB free; `~/.local/share/Steam` 6.3 GB, the
  container 206 MB. The root filesystem lives in `super` (14 GiB), which cannot grow.
- **Risk:** at 100%, `journald`, `op8-sampler`, Steam and podman can no longer write. Corrupted
  downloads, failed services and lost logs follow, exactly when we need them.
- **Measure:** `userdata` formatted as ext4 and mounted for the Steam library (and possibly for
  the container storage). The user accepted erasing the old Android data; Android stays
  reinstallable through MSM. Done only with an explicit OK at that moment.

### C2. A worn battery and no BCL

- **Evidence:** `charge_full = 3062000`, `charge_full_design = 4270000` µAh (71.7%). In the PMIC,
  `FAULT_REASON1` has the UVLO bit stored from an old event. The mainline kernel has no BCL driver
  for the PM8150B.
- **Risk:** a worn battery has a higher internal resistance, so the voltage drops more at current
  peaks (CPU + GPU + Wi-Fi + UFS at once). Without BCL, nothing slows the system before the UVLO
  threshold. **It does not damage the hardware**, UVLO is a protection, but it means a sudden
  shutdown and a risk for the filesystem.
- **Note:** the 2026-10-01 reset was **not** UVLO: the last sequence is `POFF_SEQ`, not
  `FAULT_SEQ` (`gaming-stack.md` 9).
- **Measures:** the `bat_mv` column in `op8-log` now shows how far the voltage drops under load.
  If we see drops below about 3.4 V, we limit the prime core (`policy7`, 2.84 GHz) and the big
  cluster (`policy4`, 2.42 GHz) in gaming sessions on battery. Long sessions are played on a 5 V
  charger. In the long run, a new battery.

### C3. The lockup detectors are disabled

- **Evidence:** `# CONFIG_SOFTLOCKUP_DETECTOR`, `# CONFIG_HARDLOCKUP_DETECTOR`,
  `# CONFIG_DETECT_HUNG_TASK`, `# CONFIG_WQ_WATCHDOG` (all "not set"). `ramoops` is active in the
  kernel, but the OnePlus bootloader does not keep the memory across a reset (`/sys/fs/pstore`
  empty, not even `console-ramoops`). systemd does not use the watchdog (`RuntimeWatchdogUSec=0`).
- **Risk:** a stuck CPU leads straight to a reset, with no message at all. Exactly the situation
  of the incident.
- **Measure:** `SOFTLOCKUP_DETECTOR`, `HARDLOCKUP_DETECTOR` (the "buddy" variant, which needs no
  NMI), `DETECT_HUNG_TASK` and `WQ_WATCHDOG`, **without** automatic panic. A lockup then leaves a
  trace in the journal (written every 2 s) and in the `op8-live.sh` stream on the PC.
- `kernel.panic=120` stays as is until the cause is known: a freeze of about 120 s before the
  reboot means a panic, a shorter one means the watchdog. After the diagnosis it can go down to
  10 s.

### C4. Wi-Fi

- **Evidence:** `ath11k` runs the OnePlus firmware `WLAN.HST.1.0.1.r1-01272` (built 2022-12-20),
  of unverified origin (`security-audit.md` S8). After the reset the chip reported a different MAC
  address, and NetworkManager refused the profile tied to it.
- **Risk:** the main suspect for the reset (a big download over Wi-Fi). A Wi-Fi chip that does not
  start cleanly after a "warm" reset is one more sign.
- **Measures:** reproduce the download with `op8-log` + `op8-live.sh`; if confirmed, test with the
  QCA6390 firmware from linux-firmware. For the MAC, pocknix has `0014-fix-wifi-and-bt-mac.patch`.
  The Wi-Fi profile is no longer tied to the MAC.

### C5. The 5G modem is powered on PCIe

- **Evidence:** `0002:01:00.0 vendor=0x17cb device=0x0306` (SDX55), with no driver;
  `mhi-pci-generic` tries to start it and fails (`-110`, "No firmware image defined").
- **Corrects `hardware-safety.md` 4.13 (at the time):** the PCIe link to the modem **does come
  up**. Nothing writes to EFS (there is no `rmtfs`, no modem firmware), so the IMEI risk stays
  zero. But it is a powered, unmanaged device on an SoC bus.
- **Measure:** the `pcie2` node disabled in the DTS, after checking that the modem is not needed
  for anything else (for example, GPS goes through it on Android). Done in kernel patch 0005
  (2026-10-03), together with the cameras: about 50 mA less in every power state.

### C6. The `/boot` partition

- **Evidence:** `/boot` is ext2 (no journal), mounted rw, with `fsck` disabled in fstab (pass 0).
  After the reset: "mounting unchecked fs, running e2fsck is recommended". The ext4 root
  filesystem was repaired automatically by the initramfs (2 orphan inodes of the user, temporary
  files).
- **Risk:** a reset during a write to `/boot` (`mkinitfs`) can corrupt it. It does not matter for
  booting, the bootloader reads `boot_b`, not `/boot`.
- **Measure:** `/boot` read-only in fstab (the kernel is built in WSL, not on the phone) and an
  `e2fsck -p` check while it is unmounted.

### What is already fine

- **Hardware thermal limiting:** the EPSS block (`qcom,sm8250-cpufreq-epss`) with 3 `dcvsh`
  interrupts, handled by `qcom-cpufreq-hw` (built into the kernel). 0 events so far. The
  `qcom_lmh` module does not load and does not need to: it is for other SoCs. This refines
  `hardware-safety.md` 4.8.
- **Thermal thresholds:** CPU 90/95 °C (throttling), 110 °C (shutdown); GPU 85/90/110 °C;
  PM8150B 95/115/145 °C.
- **Sensors:** `qcom_tsens`, `qcom_spmi_temp_alarm`, `qcom_spmi_adc_tm5` loaded.
- **Memory:** a 17 GB zstd zram, `swappiness=180`, `systemd-oomd` active, PSI active.
- **Kernel:** `tainted=0` (no WARN or oops in the current boot).
- **Idle:** 97% idle, only basic services.

## Performance

### P1. NTSYNC

`# CONFIG_NTSYNC is not set`. Proton uses `/dev/ntsync` when it exists; without it, it falls
back to slower mechanisms. Armada and SteamOS-ARM-Handhelds enable it. **Kernel:**
`CONFIG_NTSYNC=y` (done in r7).

### P2. Preemption

`CONFIG_PREEMPT_NONE=y`, `HZ=250`. That is the server configuration: a long kernel task (for
example heavy I/O) can delay the compositor, input and audio. **Kernel:** `PREEMPT_DYNAMIC`
(chosen at boot between `voluntary` and `full`; done in r7, default `full`).

### P3. GPU frequency

`simple_ondemand`, `polling_interval = 50` ms, frequencies 305-587 MHz. At 50 ms, the GPU reacts
3 frames late (at 60 Hz). KONKR/SteamOS-ARM-Handhelds use 16 ms. **Measure:** `polling_interval`
16-20 ms, set at boot. No risk: the frequency limits stay the same.

### P4. gamescope's priority

`No CAP_SYS_NICE, falling back to regular-priority compute and threads` (the gamescope log).
**Measure:** `setcap cap_sys_nice+ep /usr/bin/gamescope`, as on SteamOS.

### P5. DXVK

Confirmed on hardware: `storageBuffer8BitAccess = false` on the Adreno 650. DXVK 3 does not start;
DXVK 2.7 is needed (`gaming-stack.md` TODO 6).

### P6-P8. Smaller

- **P6:** no `sched_ext`. pocknix runs `scx_lavd` for frame pacing; it needs `SCHED_CLASS_EXT`
  and BTF (`DEBUG_INFO_BTF`) in the kernel.
- **P7:** THP on `always` can cause stutters (memory compaction); `madvise` is the usual choice
  for games.
- **P8:** gamescope picks the panel's 90 Hz mode. 60 Hz means less heat and power in long
  sessions.

### Already fine

`schedutil` on all clusters, maximum CPU frequencies equal to the hardware ones (1.80 / 2.42 /
2.84 GHz), `mq-deadline` on UFS with 1 MB read-ahead, `ENERGY_MODEL`, `SCHED_MC`, `UCLAMP_TASK`,
`BPF_JIT`.

## The proposed order

1. **Now, without a new kernel:** C1 (space, with OK), P3, P4, P7, C6, then the download retest
   with `op8-log` + `op8-live.sh`.
2. **Next kernel** (a single build): C3, P1, P2, P6, the MAC patch (C4), possibly C5, plus the
   security options from `security-audit.md` S3.
3. **After that:** DXVK 2.7, FEX for x86 Linux games, audio with a limiter.
