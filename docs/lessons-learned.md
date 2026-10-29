# Lessons learned

Every problem met while building ARMDeck on the OnePlus 8, what caused it and how it was solved
(or why it is still open). Newest first within each section. Details live in the linked documents;
this page is the short version, so the same mistake is not made twice.

## Kernel and boot

- **Random resets during big downloads (solved, kernel patch 0003).** The phone reset with nothing
  in the kernel log once memory filled up. Cause: the device tree deleted a reserved memory region
  (`removed_mem` at 0x80b00000) and never added it back, so Linux wrote into memory owned by the
  secure world. `stress-ng --vm 4 --vm-bytes 8000M` reproduced it in 5 s without any disk activity.
  Lesson: an instant reset with an empty log points at memory the kernel must not touch; check the
  reserved-memory map against the vendor device tree first.
- **Kernel Oops when the USB port switches from device to host (fixed in r12, 2026-10-05).** Kernel
  r12 carries the upstream fix and two follow-ups (patches 0008-0010, 0008 adapted to 6.16's
  goto-based `ncm_bind()` from the 6.12-stable backport). Tested with the gadget active: PC cable,
  then into the X3: `usb0` moved to `/sys/devices/virtual/net/`, `ip link` answered, no Oops; and
  a boot inside the X3 with its charger connected went through cleanly. The gadget-off workaround
  is no longer needed. History: the
  USB network gadget (`usb0`, SSH over the cable) outlives its parent device when the port goes from
  device mode (PC cable, charger) to host mode (GameSir X3). The next program that lists network
  interfaces reads freed memory in `rtnl_fill_ifinfo`, and the Oops keeps the network lock: WiFi,
  podman, the Steam session and even SSH logins hang. Upstream fix in Linux 7.0-rc4 ("usb: gadget:
  Fix net_device lifecycle with device_move"). Workaround: `armdeck-usb-gadget-off` removes the
  gadget at boot, and `op8-tune` sets `panic_on_oops=1`, `panic=10` so an Oops reboots the phone by
  itself. Lesson: a half-alive phone (ping and SSH banner answer, logins hang) means a kernel lock
  is held; look for an Oops first.
- **The hardware reset combination.** Power + Volume Down did not reset the hung phone, although
  the PMIC registers said it should. Power + both volume buttons held about 30 s did. Lesson: test
  recovery paths for real before relying on them; a register read is not a test.
- **Boot slot became "unbootable" (solved).** Without `qbootctl -m` at every boot, the bootloader
  counts down the retries and marks slot b dead after about 7 boots. `install-qbootctl.sh`.
- **`fastboot boot` hangs the OnePlus bootloader; `fastboot flash` can stall at "Sending".** Use
  the menu's "Restart bootloader", replug the cable, check `getvar partition-size:boot_b` first.
- **60 Hz test kernel showed a garbled image (r9, reverted).** Mainline derives the DSI link speed
  from the mode clock, so the 60 Hz mode ran the link at 348 Mbps, far below the 652.8 Mbps the
  vendor always uses. Lesson: for command-mode DSI panels, keep the link at the vendor's rate and
  change refresh through the panel's own commands.
- **A bandwidth without its path breaks the whole GPU frequency table (2026-10-27, avoided).**
  The comparison image `r17a` (r17 without the GPU's memory votes) was made by deleting
  properties from the r17 device tree. Deleting only the GPU's `interconnects` would have left
  an `opp-peak-kBps` in every GPU frequency entry; the OPP core then rejects each entry
  ("Mismatch between opp-peak-kBps and paths", `_read_bw()` in `drivers/opp/of.c`) and the GPU
  would have had no frequencies. Both go together; `r17/mkimg.sh` also checks the DTB difference
  line by line against what is expected. Lesson: read how the kernel parses a property before
  removing half of a pair.

## Display and performance

- **Steam interface slower than it should be (improved).** The DSI link ran at 521 Mbps, so one
  frame barely fit in the 11.1 ms of 90 Hz and missed frames fell to 45 fps. Kernel r11 widens the
  back porch so the link runs at 651.78 Mbps (vendor: 652.8): Quick Access 80 -> 88 fps.
- **The performance overlay cost half a CPU core (solved, mangoapp patch 5).** MangoHud's mangoapp
  never cleared its "new frame" flag and redrew at 90 Hz forever. After the fix it redraws only on
  new frame times, plus a 500 ms refresh for the sensors. Home scrolling 53 -> 60 fps.
- **The overlay vanished after a session restart (solved).** The redraw fix also drew before
  gamescope had sent the screen size, resized the window to 0x0 and hit an X error. Now it draws
  nothing until the size is known. Lesson: test a change through the full start-up path, not only
  by swapping the binary into a running session.
- **Steam's Frame Limit did nothing (solved), then halved the frame rate (open).** The limit is
  applied by gamescope's Vulkan WSI layer inside the game, which was missing from the container
  (`dnf install gamescope`, same version 3.16.29). With it, DXVK's frame pacing on this device
  dropped a 30 fps cap to 15-18 fps; turning that pacing off (`GAMESCOPE_WSI_FRAME_LIMITER_AWARE=0`)
  gave 30 fps but noticeable input delay, because frames queue up. MangoHud's in-game limiter
  (sleep-based, like RTSS: `MANGOHUD=1 MANGOHUD_CONFIG=no_display,fps_limit=30,fps_limit_method=late`,
  with Steam's limit off and `dnf install mangohud` in the container) gave a stable 30 fps with no
  delay the maintainer could feel (Tomb Raider, 2026-10-04). Next: drive it from Steam's slider.
- **Steam's slider driving MangoHud's limiter (solved, 2026-10-05).** gamescope patch 9003 hands the
  requested limit to a file, `op8-fpslimit` copies it into Steam's MangoHud file, and every game
  runs the MangoHud layer hidden with `read_cfg`. The first test showed no limit at all, although
  the chain up to the MangoHud file worked (the log shows 45, 30, 18, 0 following the slider).
  Cause: Proton ARM64 runs games in Steam's runtime container (pressure-vessel,
  `SteamLinuxRuntime_4-arm64`), which shares `/tmp` and the home directory but only the bus,
  PipeWire and Pulse sockets of `/run/user/10000`, so the game never saw `mangohud.conf`. The
  inline test had worked because `fps_limit` was in the environment, not in the file. Found by
  running a command inside the runtime (`SteamLinuxRuntime_4-arm64/run -- ls /run/user/10000`),
  after a headless test (`gamescope --backend headless` + `vkcube --c 300` in the container,
  timed) had shown that MangoHud, the file and the live reload all work. Fix: the file moved to
  `/tmp/armdeck-10000/`. Also, 9003 had stopped gamescope's pacing but still reported the limiter
  as engaged, so the gamescope WSI layer switched games to FIFO and DXVK recreated its swapchain
  at every slider move; the patch now reports it off. Result: Tomb Raider follows the slider
  (30, 18, 45, off) live, with no input delay the maintainer could feel. Lessons: a file shared
  "with the container" is not necessarily shared with the game's container, check from inside
  the runtime; and test a mechanism in isolation before blaming it.
- **"-r 60" held everything at 60 fps while the panel ran at 90 Hz.** In this DRM setup the nested
  refresh option only paces the apps. Removed from `steam-gamescope.sh`.
- **Black bars in every game (solved, gamescope patch 9001).** Steam does not treat the panel as an
  internal screen and asks Xwayland for 16:9 modes; the patch keeps the requested height and gives
  every mode the panel's 20:9 aspect (1280x720 -> 1600x720).

- **Native x86 Linux games closed at once (solved, 2026-10-05).** Steam's FEX tool needs an x86
  system with x86 Mesa at `/usr/share/guestos/fex-mesa`; FEX's own Arch Linux rootfs provides
  it (`install-fex-rootfs.sh`). Half-Life native then ran but slowly with idle CPU and GPU; that
  turned out to be the native Half-Life port itself (same reports on x86 PCs), so it stays on
  Proton. Lesson: before tuning the emulator, check whether the game behaves the same on a
  normal PC (ProtonDB).

## Steam session

- **Remote Play: two causes behind one crash (2026-10-10, solved 2026-10-11, TODO 11).** First, the firewall:
  with an input policy of drop, the PC's discovery replies never arrived and every stream went
  through Valve's relay; the logs said so ("connected via indirect connection") for a week
  before anyone read that line. Second, the crash itself: the coredump showed a run of 16-byte
  entries with a growing counter written across the decoder's own fields, which pointed straight
  at a fixed 16-entry table filled with 18 entries (Venus' minimum). Lessons: read the
  connection log lines, not only the error; and in a crash inside closed code, dump the memory
  around the bad pointer, since a pattern there names the writer faster than disassembly.
  Behind the crash was a third cause, a stall: Venus waits for a source-change handshake the
  client never does; strace showed it in one look (15 752 `QBUF`s, no `DQBUF`), and the
  driver source told exactly which calls it waits for. A preload that does those calls for
  the client fixed it without touching Steam's binary. Lesson: when closed code misuses a
  kernel API, read the driver's state machine; the fix can sit between the two.
  Moving that fix into the driver (patches 0016-0017, 2026-10-11) taught two more things.
  First, read the API's own spec before inventing a rule: V4L2's decoder spec already lets a
  client resume with buffers that fit (Capture Setup, step 6), Venus just never implemented
  it, and Qualcomm's own driver for this phone does the same on a "sufficient" event; spec
  plus vendor driver is the justification, not "it worked in the preload". Second, a
  userspace fix can block the client inside an ioctl and the kernel cannot: the preload held
  the client for 53 ms in its first `QBUF`, while in the driver the client's own 36 ms timer
  keeps running. A driver-side version has to survive the client restarting its queues in
  the middle (the decision is now kept across a `STREAMOFF`/`STREAMON`).
- **Steam interface never appeared after a reboot (solved).** The phone has no usable real-time
  clock, so Steam started with the date at 1970, its TLS connections failed and its web helper
  stalled. `steam-gs.service` now waits for the first time sync (at most 90 s).
- **"Switch to Desktop" froze the interface (solved).** Steam waits for `steamos-session-select` to
  end the session; the `op8-session-select` shim makes Steam restart in Game Mode.
- **Steam loses audio after a PipeWire restart.** Restart the Steam session too.
- **Launch Options are painful to type on a controller.** `op8-launch-options.py` edits them in
  `localconfig.vdf` while Steam is stopped (Steam rewrites that file on exit).
- **Every reboot took 93 s (solved, 2026-10-06).** The helper that stops Decky's plugins
  (`op8-decky`) ran in Steam's process group, so at shutdown it was killed together with Steam
  before it could do its job; the plugins kept gamescope's reaper waiting until systemd's 90 s
  stop timeout. Its own session (`setsid`) and a signal trap fixed it (4 s now). The earlier
  check had only covered a Decky restart, never the "Steam ended" path, whose log line had in
  fact never appeared. Lessons: a cleanup helper must not share the process group of what it
  cleans up after; test every exit path (session restart, shutdown), and look for the log
  line each path should write.

## Power, charging and controllers

- **GameSir X3 Pro pass-through charging (solved, DT `sink-wait-cap-time-ms = <620>`).** The X3
  asks for a power role swap only right after the phone is seated with its charger already
  connected. Its capabilities then arrive 337 ms after the swap, but Linux waited only 310 ms (the
  USB PD minimum), sent a hard reset and came back as a USB device, so the controller vanished;
  the X3 refuses a data role swap in that state. Lesson: capture the USB PD state machine log
  (tcpm, `op8-usbpd-capture`) before guessing.
- **Charging when the charger goes into the X3 after the phone (not possible, 2026-10-05).** The X3
  asks for the power role swap only when the phone is seated; it ignores a swap requested by the
  phone (`echo sink > /sys/class/typec/port0/power_role`: the request is acknowledged, then no
  answer for 60 ms, harmless). A software "re-seat" (port_type sink then dual, which opens the CC
  lines for 100 ms, or repeated for 8 s) made the X3 swap and the phone charged for 2-3 s, then
  the X3 swapped back by itself, and a later swap ended in a hard reset with the controller gone
  until the phone was re-seated. GameSir's own FAQ says the same order problem exists on Android:
  charger into the X3 first, wait for the fan, phone last. Also from the manual: S + D-pad Right
  toggles pass-through charging (saved across restarts), S + D-pad Up/Down sets the cooler power,
  and "Extreme Cold" needs a 9 V / 3 A charger. Lesson: read the accessory's FAQ before
  engineering around it; the limit may be the accessory's.
- **The X3 stuck as a USB host, controller gone (solved by power-cycling the X3, 2026-10-05).**
  After the swap experiments above, every attach ended within 0.6 s: the X3's Request came with
  the data role bit set to DFP (header 0x1062 instead of 0x1042), both ends claimed to be host,
  and tcpm did an error recovery ("Data role mismatch"), forever. The X3 keeps its state while its
  charger powers it, so re-seating the phone did not help; phone and charger out for ~15 s, then
  charger, fan, phone, cleared it. Lesson: when an accessory has its own power, it can carry a bad
  state across re-seats; power-cycle it before suspecting the phone.
- **The battery ran flat during a long PC session (2026-10-06).** The phone stayed in the Steam
  interface while the work happened on the PC, and it shut down at 0% (the gauge's 0%, 3.56 V
  after shutdown, is still above the cell's own cut-off). **Corrected 2026-10-27:** it did not
  shut down. The sampler log shows it kept running at the gauge's 0% for 25 minutes below
  3.25 V and died when the battery cut out at 2.65 V; the 3.56 V was the cell recovering
  afterwards. Nothing on the system turned the phone off on a low battery (now `op8-lowbatt`, see
  below). On the PC's USB port it then charged
  at only ~0.66 A, about 3.3 W, little more than the idle Steam session uses (TODO 33); on a
  45 W charger (PD 5 V / 3 A, patch 0004) the battery got 0.76 A at 0%, the PMIC's default limit
  without a charger driver. Lessons: keep the phone on a wall charger during long sessions,
  stop `steam-gs` when it only needs to charge, and keep checks on a low battery read-only and
  light.
  Afterwards (2026-10-06, 21:32) the gauge reported 1% while charging, at 3.85 V and with
  `charge_now` 526 mAh of `charge_full` 3093 mAh (about 17%): after the full discharge its own
  percentage lost track. The battery itself was fine; the number is only to be trusted again
  after a full charge, and until then the phone stays on the charger (a low percentage on
  battery can trigger the system's low-battery power-off).
  **It came back, worse (2026-10-27, open).** The gauge said 1-3% while charging at 4.1-4.2 V
  (about 4.1 V resting, so most of the charge is there), with `charge_now` 2485 mAh above
  `charge_full` 1234 mAh. The sampler log (`/var/log/op8/sample-*.csv`) shows how it got there:
  in a game the battery gave 3.6-3.8 A and sagged to 3.32 V, below the 3.4 V terminate voltage
  the driver writes from the device tree, and within 20 s the gauge jumped from 48% to 0%; since
  then it counts up from that 0. Its learned full capacity fell from 3056 mAh (2026-10-01) to
  1234 mAh in four weeks, too fast for real wear, so the gauge's learning is suspect as well. The
  sag itself is real: about 0.18 ohm (435 mV over 2.44 A), a worn cell. OnePlus' driver for this
  board (LineageOS `drivers/power/oplus/gauge_ic/oplus_bq27541.c`, DT `vendor/19821/kona-mtp.dtsi`
  with `qcom,modify-soc-smooth`) rewrites three gauge settings at every boot and at shutdown
  (Op Config B, CC dead band, DOD at EOC) and resets the gauge at shutdown when it is at 0% below
  3.3 V; mainline does none of this. The OnePlus 8 Pro (19811) has a different cell and its own
  DT: never take values from it. Lessons: the sampler log is the first place to look for battery
  questions; and a percentage that jumps to 0 under load is the gauge reacting to voltage sag,
  not a battery that is empty.
  Read straight from the gauge the same day (`i2cget -f -y 16 0x55 <reg> w`, standard commands
  only, all readable while sealed per TI SLUUAS7B), at 4.18 V while charging: StateOfCharge 15%
  (what the driver and Steam show), StateOfChargeUnfiltered 62%, NominalAvailable / FullAvailable
  2650 / 3155 mAh (84%, no load), FullChargeCapacityUnfiltered 1317 mAh, StateOfHealth 69%,
  Flags 0x0188 (CHG, OCVTAKEN, BAT_DET; no ITPOR, so the configuration is intact). So the cell
  holds about 3.1 Ah; the gauge expects to deliver only 1.3 Ah of it before 3.4 V at the load it
  assumes; and the shown 15% is the smoothing filter (Op Config B [SMOOTHEN], on by TI default
  and on OnePlus), which after the forced 0% "is not allowed to jump" and only climbs slowly back
  to the real value, converging at full charge. Three things to fix: the terminate voltage
  (3.4 V from the Xo666 DT, while OnePlus powers off at 3.25 V, `vbatt_power_off`), what the
  driver reports, and a clean power-off at low voltage (`sample-0060` ends in NUL bytes: the
  phone lost power without a shutdown).
  **Deep discharges (2026-10-27, fixed with `op8-lowbatt`).** The minimum voltage of every
  sampler log since 2026-10-03: two runs went to 2.65 V (2026-10-06 and 2026-10-12, idle in
  Steam at about 0.38 A, 20-25 minutes below 3.25 V and 7-11 minutes below 3.0 V), both ending in
  a power cut. Short dips under load are normal (2.95 V for one sample at 2.4 A, 3.09 V and
  3.17 V for two samples) and come back within seconds. `userspace/system/op8-lowbatt` now powers
  off cleanly when the battery stays below 3.25 V for 15 s while discharging: OnePlus' rule for
  this phone (`oplus_charger.c`: the gauge's 0% is held at 1% while the battery is above
  `vbatt_power_off`, 3250 mV in `vendor/19821/kona-mtp.dtsi`; below it the level runs down 1%
  every 15 s to the power-off). Lesson: a protection the phone had on Android is not there on
  mainline unless someone adds it; list what the vendor's charger code does, not only its
  drivers.
  **"Stuck at 96%" on the charger (2026-10-27, r16, not a fault).** The PMIC had ended the
  charge by itself: charger state TERMINATE (`0x1006 = 0x45`, OnePlus `smb5-reg.h`), float
  4.37 V (`0x1070 = 0x4d`), recharge only below 4.20 V (VBAT-based, `0x1051 = 0x2c`; threshold
  `0x107e/0x107f = 0x544a`, x 194.637 uV = 4200 mV). The current went from about 0.6 A straight
  to 0 at 4.35 V, with no taper, so the gauge never saw its own end-of-charge condition and
  never reached 100%; resting at 4.26 V the cell holds about 90%. These are the bootloader's
  settings (same values as on 2026-10-01; no charger driver touches them). OnePlus instead
  charges to 4.435 V, ends at 220 mA (`qcom,iterm_ma`) and recharges 100 mV below float. Not
  changed: PMIC charging values stay hands-off (hardware-safety.md 4.1), and a lower full point
  is easier on a worn cell. What 0x1007 = 0x28 means on the PM8150B is not documented in the
  vendor header and was not guessed.
- **PD chargers could ask for 9 V (solved, patch 0004).** The device tree allowed sink PDOs up to
  12 V, while this phone never used PD above 5 V on Android. Now 5 V only.
- **Cameras and modem drew power while unused (solved, patch 0005).** Every camera supply had to be
  turned off, including L3F/L7F (a first version left the front sensor half powered); checked
  against the LineageOS vendor device tree.
- **Bluetooth found no devices (solved).** The QCA6390 reports a default address, so the controller
  stayed "unconfigured". `bootmac` sets an address at boot.
- **X3 Capture button sent Power (solved).** In its blue (HID) mode it sends Volume Down + Power,
  Android's screenshot chord. White mode (DualSense) makes it a normal button for Steam Input.
- **Leftover debugging costs (solved).** `op8-top`, a `sync` every 2 s in the sampler, journald
  syncing every 2 s, SDL verbose logging, and real-time tasks forcing the CPU to its top clock
  (`sched_util_clamp_min_rt_default` now 0, no audio crackles).
- **A sleep fix ruled out by its title (2026-10-27, patch 0019, to measure).** The source check
  of 2026-10-27 found gennro's fix (SteamOS-ARM-Handhelds, Armada `0568`): the CPUs' memory
  (DDR) votes stayed in the "sleep set", the votes the power controller applies while the
  processors are powered down, so the RAM never reached self-refresh. It was parked as "only for
  real suspend (s2idle)", which ARMDeck does not use. Wrong: in our `sm8250.dtsi` the controller
  that applies those votes (`apps_rsc`) sits in the CPU cluster's power domain (`cluster_pd`,
  idle state `cluster_sleep_0`, about 10 ms minimum), so the sleep set is used every time all
  eight cores idle long enough: in `op8-standby` and in quiet moments with the screen on. Armada
  reports about 25% less sleep power on SM8250. Lesson: check where a fix's mechanism triggers in
  our own device tree before ruling it out by its title. Baseline before the test, kernel r16,
  2026-10-27 evening (Steam menu idle, USB unplugged, WiFi on, battery current from the sampler,
  steady minutes only): screen on about 380 mA (about 1.55 W at 4.06 V), screen off about
  255 mA (about 1.05 W at 4.07-4.11 V, 16 minutes before plus 6 minutes in the test). Test image
  `r17a` (0019-0021 without 0022), 2026-10-29, measured the same way: screen on about 395 mA at
  full brightness and about 300 mA once Steam dims the idle screen (both as on r16), screen off
  about 256 mA, so no measurable gain. Why: every core still enters idle about 260 times a
  second (`cpuidle` usage counters over 30 s, read right after the test with the cable back in),
  so a typical idle period is about 3 ms, shorter than the 10 ms the cluster needs before it
  powers down and the sleep set is used. Over the same 30 s the CPUs got about 500 "function
  call" interrupts a second (one CPU asking the others to run something; almost all of them, the
  trace showed, are wake-ups of a task on another core) and about 830 timer interrupts. A 10 s
  kernel trace with the screen off and the cable out (`wake-trace.sh`: trace events for
  interrupts, timers and woken tasks) found about 690 task wake-ups a second, more than half of
  them PipeWire's audio threads running a 94 Hz cycle although nothing was playing. Lesson:
  before measuring a sleep-state fix, check that the system reaches that sleep state at all, and
  note the screen and cable state of every reading. 0019 stays (it is correct and costs nothing);
  the wake-ups are the open problem.

- **Standby kept the audio path and the panel running (2026-10-29, solved).** "Screen off" in the tests above
  is `op8-standby`: the power button makes Steam ask for sleep, the script sets the brightness
  to 0 and freezes Steam, gamescope and the game, while PipeWire keeps running. A logger
  (`audio-wake.sh`, every 2 s: open ALSA streams, PipeWire wake-ups, interrupts, battery
  current) showed an ALSA playback stream opening at the moment of the press and staying open
  for the whole 207 s of standby, PipeWire's audio thread running at 94 Hz: Steam starts a
  sound as it asks for sleep and is frozen in the middle of it, so its stream never stops and
  the audio DSP, codec and amplifiers keep working. After the wake-up Steam finished the sound
  and the device closed by itself within a minute. The logger itself, started with
  `systemd-run --user`, sat in the frozen `app.slice` and wrote nothing during standby (one
  line covering the 210 s at the end); a measurement during standby must run as a system
  service. Suspending the device from outside (`pactl suspend-sink`) would not hold while a
  stream is linked; PipeWire's own `pulse.idle.timeout` pauses a client's stream after N
  seconds without data and plays it again when data comes (`audio/50-op8-pulse-idle.conf`, 5 s,
  the value PipeWire's own configuration uses for speech-dispatcher). The second half of the
  loss was the panel: `op8-standby` only set the brightness to 0, so the display controller
  kept reading the picture from memory (about 3.8 GB/s of DDR votes with the GPU asleep) and the
  panel stayed powered; the sleep-stage test of 2026-10-03 (`op8-power-test`) had already
  measured 275 -> 179 mA for "panel off through gamescope", and that step had never been
  added to `op8-standby`. Now it switches the panel off with `gamescopectl
  drm_sleep_internal_screen 1` before freezing, and back on after the CPU limits and the apps.
  Result over 25 minutes of standby on r17: 160 mA (0.60 W at 3.75 V) against 256-266 mA
  (1.01-1.05 W) before, 0 running ALSA streams 20 s after freezing, the panel back at wake-up.
  With about 2500 mAh usable that is about 15 hours of standby, against 9-10 before. One
  slip: the brightness written right after `drm_sleep_internal_screen 0` failed with "Invalid
  argument" (gamescope switches the panel on asynchronously; Steam set its own brightness a
  moment later); the script now waits for the panel to report On first (checked the same day:
  "leaving standby: panel On", no error). Lesson: when an old
  measurement already shows a big saving, check that it went into the product.

- **Real suspend works, but the SoC never reaches its deep sleep (2026-10-29, open).**
  `op8-s2idle-test 300` on r17 (panel off, apps frozen, `echo freeze > /sys/power/state`, RTC
  wake-up): suspended 302 s, woke by itself, average 107 mA from the battery charge (9 mAh, so
  about +-11%), against 160 mA for the fixed `op8-standby`. The power button is a wake-up source
  (`pm8941_pwrkey`, `power/wakeup` enabled). But `qcom_stats` `aosd`, `cxsd` and `ddr` stayed at
  0: no AOSS sleep, no CX rail collapse, no DDR self-refresh. The test now also saves what is
  still on just before and after the suspend (`.before`/`.after`). Three holders found in the
  power domain summary:
  - `cx` at level 48 (low SVS) held by `a90000.serial`, the debug UART used as the kernel
    console (runtime PM "unsupported"); nobody uses it on a closed phone;
  - `mmcx` at level 64 held by `ad00000.clock-controller`, the camera clock controller, also
    without runtime PM, although the cameras are off (patch 0005);
  - `pcie_0_gdsc` on, `1c00000.pcie` and the WiFi chip (`17cb:1101`, ath11k) active in D0: with a
    device on the link, `pcie-qcom` keeps the controller's resources on through the suspend.
  Side notes: the touch controller (`s6sy761`) fails its resume callback with -19 (it is powered
  with the panel, which is still off at that point) and works anyway afterwards; ath11k logs
  "failed to process regulatory info -22" at resume and WiFi reconnects. "psci: [Firmware Bug]:
  failed to set PC mode: -3" at boot is harmless: the next line is "Initialized CPU PM domain
  topology using OSI mode".
  Reading the 6.16 drivers took two of the three suspects off the list: the geni UART's
  `uart_suspend_port()` path powers the port off (OPP rate 0, interconnect off) in system
  suspend, and genpd votes a power domain off once all its devices are suspended, so the
  console's and the camera clock controller's votes only cost power while awake. The PCIe
  controller has no interconnect votes on SM8250 (no `interconnects` in its node), but
  `qcom_pcie_suspend_noirq()` keeps its clocks, PHY and GDSC on whenever the link is up.
  Experiment (`op8-s2idle-test 300 nowifi`: WiFi device removed from the bus and powered off
  through its pwrctrl before the suspend): 83 mA instead of 107, still 0 in all three
  counters, so PCIe is one holder among others. Costs of that route: ath11k's firmware crashed
  into RDDM during the removal, and 6.16 does not train the link again at resume (WiFi back
  only after a reboot); upstream solved it properly in May 2026 ("PCI: qcom: Add D3cold
  support", 2cc0e7454c78, part of a series). For scale: Armada's `0568` notes that an SM8250
  RP5 slept at about 1.7% an hour before the same CPU-vote fix (about 85 mA of its 5000 mAh)
  and about 25% less after it, so on this SoC the deep states save tens of mA, not hundreds.
  Their `armada_sleep_debug.py` traces clock, regulator and interconnect events across a
  suspend to name what is still on at the end; that is the next tool if we go further.

## Audio

- **Speakers quiet and earpiece quieter.** The TFA9874 amps are protected by a filter chain with a
  ceiling and the earpiece side lowered 3 dB. Never test with a raw `aplay` on the host.
  2026-10-06: an average-power limiter (LSP Compressor Mono, RMS) went into the filter and the
  ceiling from -18 to -12 dB, with the worst-case average power unchanged. The maintainer still
  found it much quieter than Android; a capture of what reached the speakers showed why: the
  video playing came in at -28 to -35 dBFS RMS with peaks at -14 dBFS, far below the limiter,
  so the source itself was quiet. Lessons: measure the signal before judging a volume step by
  ear; test a new filter on a null sink (no speakers) with known tones first, and check that it
  links only there before playing anything.
- **Bluetooth headphones paired but never connected (solved, 2026-10-05).** bluetoothd
  logged "a2dp-sink profile connect failed: Protocol not available": the PipeWire Bluetooth
  plugin (`pipewire-spa-bluez`) was not installed, so nothing offered the audio profiles. After
  `apk add pipewire-spa-bluez` and a WirePlumber restart, Galaxy Buds3 Pro play over A2DP with
  AAC. The kernel has no RFCOMM (`CONFIG_BT_RFCOMM`), so the Hands-Free profile could never
  connect, yet the phone advertised it and the headphones tried it first, so they did not
  connect by themselves. `51-op8-bluetooth.conf` keeps only the audio roles (no Hands-Free; the
  microphone is not wanted): now they connect by themselves when taken out of the case. After a
  "Disconnect" from Steam they stop answering ("Host is down") until they go back in the case;
  the page from the phone gets no answer, so it is the headphones' own behaviour. The delay in
  games is noticeable (AAC, mostly the headphones' buffer). When they disconnect, the default
  output falls back to "Speakers (protected)" by priority (2000; headphones 1010, raw speaker
  100; checked 2026-10-05 with no sound playing), and WirePlumber remembers the headphones as
  the chosen output, so it switches back to them when they reconnect.
  Lesson: a Bluetooth device that pairs but does not connect usually means a missing profile
  provider; read bluetoothd's log first.
- **Know which boot a log line belongs to (2026-10-05).** The op8 boot reports list the kernel
  warnings of the *previous* boot. Counting them as the current boot's put every audio failure
  one boot off; read the section header before correlating.
- **A Vulkan layer in the home directory is also seen by the host (2026-10-05).** The Steam
  container shares `/home` with postmarketOS, so an implicit layer manifest in
  `~/.local/share/vulkan/implicit_layer.d/` is read by the host's Vulkan loader too (gamescope).
  lsfg-vk's manifest is always on; forced on the host, the musl loader crashed on its glibc
  library. Our build makes the layer opt-in (`enable_environment`), checked with
  `VK_LOADER_DEBUG=all` before any game used it.
- **The postmarketOS host has no curl (2026-10-05).** `install-decky.sh` stopped at its download
  when run on the host; BusyBox has `wget` only. Download scripts run in the container, or fall
  back to `wget`.
- **A live config file is not a free control (2026-10-06).** lsfg-vk rebuilds everything on
  each change of its file; a Decky slider that wrote on every step froze the game. Controls that
  write files a running program watches must wait until the user stops moving them.
- **A helper process that outlives Steam blacks out the screen (2026-10-05).** gamescope's reaper
  waits for every process of the session; two Decky plugins that ignored SIGTERM kept
  `steam-gs` in "deactivating" with a black screen. Helpers that start children run them in a
  process group of their own and stop the whole group, by force if needed.
- **Steam's own keyboard shortcuts are in its logs (2026-10-05).** `logs/*.txt` list "Registered
  global hotkey": Shift+Tab for the Steam menu, Shift+Ctrl+Tab for Quick Access. A virtual
  keyboard sending them is all a spare button needs.
- **Software made for SteamOS expects SteamOS's services (2026-10-05).** Decky restarts itself
  through `systemctl restart plugin_loader`; without that service its first restart hung it.
  Check how a SteamOS tool restarts, updates and stops itself before running it elsewhere.
- **Read a Decky plugin before installing it (2026-10-05).** decky-lsfg-vk would have installed
  an x86_64 library as an always-on Vulkan layer in the shared home directory, undoing the
  explicit-layer fix and loading a wrong-architecture library into every Vulkan program.
- **Vulkan layer order decides what a frame limiter counts (2026-10-05).** With lsfg-vk as an
  implicit layer above MangoHud, a 30 fps limit gave 15 real frames: MangoHud limited lsfg-vk's
  output, generated frames included. `VK_LOADER_DEBUG=layer` prints `Insert instance layer`
  from the driver upwards, which shows the chain. Explicit layers enabled from the environment
  are placed closer to the driver than the implicit ones, so lsfg-vk became explicit.
- **A benchmark is not a game (2026-10-05).** lsfg-vk's benchmark ran fine; in a game it failed
  at once, because only a real swapchain shares images between two Vulkan devices, and Turnip
  refused the mismatched import (`VK_ERROR_INVALID_EXTERNAL_HANDLE`). Test the real path early.
- **Mesa can say why a shader is slow (2026-10-05).** `IR3_SHADER_DEBUG=disasm` (with a fresh
  application cache, e.g. `XDG_CACHE_HOME=/tmp/...`, and `MESA_SHADER_CACHE_DISABLE=1`) dumps
  every Turnip shader with its statistics; `stp`/`ldp` instructions are register spills. That
  is how lsfg-vk's quality mode, 20-30 times slower than performance mode, was traced to
  spilling on the Adreno 650.
- **A game stuck on its loading screen can be a bad save, not the platform (2026-10-05).** Hue
  hung because its Steam Cloud save was an empty file; the Unity `Player.log`
  (`~/.config/unity3d/<company>/<game>/Player.log`) said so in plain words. Read the game's own
  log before suspecting FEX, Mesa or the kernel.
- **Old native ports can ignore a controller in-game although their menus see it (2026-10-05).**
  Outlast's Linux port did, with and without Steam Input. When the game's menus react to the pad,
  the platform side (device access, SDL mapping) is fine; try the Windows version through Proton
  before spending more time on the native port.
- **`apk add` failed although the package installed (solved 2026-10-05).** Making `/boot`
  read-only (audit C6) broke the postmarketOS initramfs trigger, which rewrites `/boot` whenever
  kernel, firmware or udev files change. apk then marked `postmarketos-mkinitfs` broken and
  counted it as "1 error" in every later transaction, so commands chained with `&&` never ran.
  Fixed with an apk commit hook (`armdeck-boot-rw`) that makes `/boot` writable only while apk
  works, plus one reinstall of the package. Lessons: a read-only mount needs a plan for every
  program that writes there; read apk's log (`/var/log/apk.log`) for the first failure, not the
  last "1 error"; and before letting a boot tool run, check whether it can flash a partition
  (boot-deploy can, with `flash_kernel_on_update`).
- **Sound card sometimes missing after boot (open, TODO 16).** "AFE failed to vote" in about 5 of
  17 boots; a reboot fixes it. The kernel fix already existed elsewhere: Nova-Deck's `0893` +
  `0895` (Philippe Simons, 2026) show the same log line for line and make `q6afe` wait for the
  DSP. We found it only through the systematic patch scan (docs/patch-scan.md), after working
  out the cause ourselves from 49 boot reports. Lesson: before working an open problem from scratch, search the
  related projects' patch notes for its exact log lines.
- **"Impedance detect ramp error" on the screen at boot (2026-10-10).** The phone has no 3.5 mm
  jack, but the device tree (the file that describes the hardware to the kernel) gives the WCD9380
  codec its headset detection (MBHC) with no USB-C audio switch, so the codec reads the
  unconnected detect pin as "headset plugged in" once when audio starts, tries to measure the
  headphone impedance, reads zeros and logs the error. Checked on the phone: one detection
  interrupt, not a loop; "Headphone Jack" and "Mic Jack" read "on", but the UCM profile (the ALSA
  description of the sound card) has only the speakers and the built-in mic, so output stays on
  the speakers; after detection the driver turns the mic bias off again (only the button-detect
  current source, microamps, stays on). Harmless. Earlier boot reports had up to 59 `wcd938x`
  lines per boot, and the boot report hid them as "a known problem" without anyone writing down
  why. It reached the screen because `quiet` still prints errors on the console;
  `20-armdeck-quiet-console.conf` (sysctl `kernel.printk = 3 4 1 7`) keeps everything below
  "critical" off the screen and in the logs. Lesson: a message hidden as "known" needs its
  cause written down, or the next person to see it starts from zero.

## Tools and workflow

- **A logger started with `nohup ... &` over SSH died with the session (2026-10-29).** The
  first run of `audio-wake.sh` wrote only its header: when the SSH command ended, systemd
  stopped the session's scope and every process left in it, `nohup` or not. Started again with
  `systemd-run --user --unit=... sh script.sh`, it runs as a user service outside the session and
  survives. Use that for anything that must outlive an SSH command, and read the log once before
  asking the maintainer to start a measurement.

- **WiFi does not answer in standby (2026-10-29, explained).** SSH and ping time out while the
  phone is in standby; awake it works again. The cause is NetworkManager, not the screen: Steam's
  sleep request starts systemd's suspend target, NetworkManager takes WiFi down for the sleep
  and reconnects at wake-up ("sleep: wake requested" in the journal, then a new association).
  That saves power and stays. Measurements in standby have to start before it and must not
  depend on the SSH session.

- **A build script that follows someone else's master breaks on its own (2026-10-27).**
  `build-gamescope-op8.sh` fetched Alpine's gamescope files from aports `master`. By the next
  build master had moved to 3.16.31 and 3.17.0 (the script would have stopped on its version
  check), and gitlab.alpinelinux.org did not answer at all (curl exit 28). Now pinned to the
  aports commit of 3.16.29 through the GitHub mirror; the three Alpine patches are
  byte-identical to the ones used on 2026-10-02. Pin every outside source to a commit.

- **The phone's own boot.img is not the image we run (2026-10-27).** `install-kernel.sh` makes
  `/boot/boot.img` with the cmdline from the device package's `kernel-cmdline.conf`, which adds
  `clk_ignore_unused pd_ignore_unused` (unused clocks and power domains stay on). No image we
  ran ever had them: every test image since r7 was repacked on the PC from the previous one's
  header and cmdline (`r14/mkimg.sh`). Writing the phone's boot.img would have changed two
  things at once, one of them untested and costly for the battery. Test images stay repacked
  (`r16/mkimg.sh`: r16 kernel and DTB, r14 ramdisk, header and cmdline, checked byte for byte);
  whether the device package should drop the two options is still open.

- **WSL wipes `/tmp` between calls.** Work under `/mnt/d`.
- **`sed` rewrote CRLF in a patch file.** Patch files are binary-exact: edit them with byte-level
  tools and recompute the APKBUILD checksums.
- **A time threshold skipped the session-start source check (2026-10-05).** The check ran with
  `--if-older-than 20`; the new session began 19.8 h after the last one, so it was skipped, and
  13 new DroidDeck commits (Decky, frame generation, .NET games under FEX) went unseen until the
  maintainer asked. The check now runs at the start of every session, with no threshold.
- **BusyBox tools differ.** No `pgrep -c`, `grep --line-buffered`, `ps -p` or `ls --time-style`;
  check the BusyBox usage text before relying on GNU options.
- **Deployed copies drift from the repository (checked 2026-10-05).** The phone still ran the
  pre-translation copies of 14 scripts and services (Romanian log messages and unit
  descriptions); stripped of strings and comments, the code was identical everywhere, so nothing
  behaved differently. Method: hash every `userspace/` file, find copies on the phone by name,
  then diff without comments and quoted strings. Fixed the same day with
  `userspace/deploy-manifest.txt` and `tools/deploy.sh` (check, then stage + `install.sh` with
  backups): 22 files redeployed, two old-named rules (udev, polkit) moved away, everything "same".
- **Restarting a user service during a kernel lock hang makes it worse.** `systemctl` waits on the
  stuck manager; use `sudo sync && sudo reboot -f`, or the button reset.
