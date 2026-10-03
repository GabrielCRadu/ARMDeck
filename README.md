<p align="center">
  <img src="docs/images/armdeck-banner.png" alt="ARMDeck" width="640">
</p>

<p align="center">
  <b>Turn a Snapdragon phone into a Linux gaming handheld.</b><br>
  Mainline Linux, Steam in Game Mode, Windows games through Proton ARM64. No Android.
</p>

---

## What is ARMDeck

ARMDeck takes a Snapdragon phone, wipes Android, and boots it into a mainline Linux kernel
(postmarketOS) with the Steam ARM64 client running in Game Mode under gamescope, the same
compositor the Steam Deck uses. Windows games run through Proton ARM64 and FEX (an x86
emulator). The phone becomes a dedicated console: no modem, no calls, no Android apps.

The goal is not for one person to port every phone. ARMDeck provides the shared stack and a
strict contribution process so the community can add and maintain support for more devices.

## Supported devices

Each device has a **profile**: its kernel, device tree, firmware packaging and tuning.

| Device | Profile | SoC / GPU | Variants verified | Status |
|---|---|---|---|---|
| OnePlus 8 | `instantnoodle` | SM8250 / Adreno 650 | IN2013 (global) | Daily use: Steam, Proton games, sound, touch, buttons, 5 V charging |

Phones sold under one name often differ by region (different modem, RF board, sometimes
different panels or memory). A profile lists the exact variants that were tested on real
hardware; anything else is unverified until someone reports it.

## What works on the OnePlus 8

- Steam ARM64 in Game Mode, full screen at the native 2400x1080 (patched gamescope).
- Windows games through Proton 11.0-2 ARM64 (DXVK 2.7, Unity and 2D games run well).
- Performance overlay (MangoHud), Steam menu on Volume Up + Volume Down.
- Kernel with NTSYNC, full preemption and MGLRU.
- Sound (behind a fixed volume ceiling for the speaker amplifier), touch, buttons.
- USB-C limited to 5 V input, battery-temperature thermal guard.

Known limits: Proton Experimental ARM64 (DXVK 3) fails on Adreno 650, native x86 Linux
games need a missing x86 Mesa, Remote Play hits a Valve ARM64 client bug, and real deep
sleep is still being worked on. Details in [docs/compat-perf-audit.md](docs/compat-perf-audit.md).

## Read before flashing

This wipes the phone. Read [docs/hardware-safety.md](docs/hardware-safety.md) first. Some
community kernels for these phones contain settings that can damage hardware (for example a
charger driver that programs the battery to about 4.87 V); ARMDeck documents which ones to
avoid and why.

## Contributing

A contribution guide with strict safety rules, device profile templates and a device report
tool is being written. Until then, open an issue with your phone model, exact variant
(for example IN2013) and what you tested.

## How this is built

This project is developed with AI assistance (Claude models) doing research, source
verification, packaging and build work alongside the author. Every non-obvious claim in
[docs/verification-log.md](docs/verification-log.md) is traced to a primary source (a real
file, a real build, a real measurement) so the work can be checked rather than taken on faith.

## Repo layout

- `pmaports/` - postmarketOS packages for the device (kernel with ARMDeck patches, device
  port, firmware, ALSA config). Not part of upstream pmaports.
- `userspace/` - what turns the flashed image into a handheld: Steam session in gamescope,
  buttons, overlay, thermal guard, power tests. Start with `userspace/README.md`.
- `docs/` - safety, build environment, gaming stack research, audits and the verification
  log. Some older documents are in Romanian.
- `reference/dts/` - the three community device trees for the OnePlus 8, kept for comparison.
- `tools/` - helper scripts.
- `Gaming Mainline OnePlus 8.md` - the original research draft (Romanian). It contains errors
  corrected in the verification log; do not treat it as a source of truth.

## License and attribution

This repo's own content (the documents, the verification log, `tools/inline-doc-values.py`,
and the drafted `pmaports/` packaging files, which follow the same MIT convention the real
postmarketOS pmaports project uses for packaging metadata) is MIT licensed - see `LICENSE`.

The three files under `reference/dts/` are not original to this repo. They are device tree
source files pulled verbatim from three independent community kernel forks for this phone,
kept here for side-by-side comparison:

- `sm8250-oneplus-instantnoodle.dts` - from
  [Xo666/mainline-instantnoodle](https://github.com/Xo666/mainline-instantnoodle) (Xiaoou),
  licensed `GPL-2.0 OR BSD-3-Clause`.
- `sm8250-oneplus-instantnoodle-obikeahloa.dts` - from
  [ObiKeahloa/linux](https://gitlab.com/ObiKeahloa/linux), licensed
  `GPL-2.0-only OR BSD-2-Clause`.
- `sm8250-oneplus-instantnoodle-wuerfeldev.dts` - from
  [WuerfelDev/linux-sm8250](https://gitlab.postmarketos.org/WuerfelDev/linux-sm8250),
  licensed `GPL-2.0-only OR BSD-2-Clause`.

Each file carries its own SPDX header and copyright notice; those are not altered here. All
three are dual-licensed with a permissive option, which is why the repo as a whole can stay
MIT rather than being pulled entirely under GPL by their presence - but the credit for
writing them belongs to their respective authors and forks, not to this project.

The firmware referenced (but not included - see `.gitignore`) by
`pmaports/firmware-oneplus-instantnoodle/` is proprietary Qualcomm/OnePlus-signed material
with no clear redistribution license; see `docs/verification-log.md` for the caveat.

## Disclaimer

This is an independent, unofficial research project. It is not affiliated with, endorsed
by, or sponsored by OnePlus, Qualcomm, or any of their partners; not affiliated with the
individual authors or maintainers of the third-party kernel forks or drivers referenced
here; and not affiliated with Valve or Steam. All trademarks belong to their respective
owners.

Everything in this repo is provided as-is, with no warranty of any kind. Flashing a phone
with a custom kernel and bootloader-unlocked firmware carries real risk, including
permanently bricking the device, data loss, and hardware damage. The author and
contributors to this project accept no responsibility or liability for any damage, data
loss, security vulnerability, or other harm, material or otherwise, resulting from using
anything in this repository, whether by following the documented instructions, using the
drafted packages, or otherwise. By using this project to install any of this on a real
device, you accept that risk yourself and agree to this disclaimer.
