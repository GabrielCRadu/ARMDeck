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
  after shutdown, is still above the cell's own cut-off). On the PC's USB port it then charged
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

## Tools and workflow

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
