# steamed-noodle

Research and build notes for turning a OnePlus 8 (codename `instantnoodle`, Qualcomm
SM8250) into a dedicated Linux gaming handheld, running a mainline-adjacent kernel instead
of Android.

## How this is built

This project is developed with AI assistance, using models including Claude Sonnet 5 and
Claude Opus 5, doing the research, source verification, packaging, and build work
alongside the author. Every non-obvious claim in `docs/verification-log.md` is traced to a
primary source (a real file, a real build, a real API response) specifically so the work
can be checked rather than taken on faith - that's the point of that file existing at all.
If you think AI involvement automatically makes a project worthless, this isn't the repo
for you; no need to spend your time on it.

## Status

Nothing has been flashed to real hardware yet. The kernel source compiles, the full device
package set builds through the real postmarketOS packaging pipeline, and a bootable image
has been assembled. None of that proves the phone actually boots it.

A pre-flash audit on 2026-10-01 (phone in hand) found and fixed real problems before
anything touched the device: a broken install procedure, firmware that never made it into
the image, a speaker-amplifier driver configured from uninitialized memory, camera power
rails forced on (one above the OnePlus voltage), and "charger support" patches that could not
work because no driver existed for them. It also found that the only community charger
driver for this PMIC programs the battery to about 4.87 V. Read
`docs/hardware-safety.md` before flashing anything; the audit trail is in
`docs/verification-log.md` section 9.

## Why this exists

Mainline Linux support for this exact phone does not exist upstream, and is not
officially packaged in postmarketOS. It only exists as unofficial, mutually incompatible
community kernel forks. This repo tracks what was actually checked against those forks
and the real toolchain, as opposed to a first-draft research document whose numeric
claims turned out to only be partially correct.

## Repo layout

- `Gaming Mainline OnePlus 8.md` - the main architecture and how-to document (in
  Romanian). Covers the kernel/device tree situation, the Vulkan/Mesa graphics stack,
  Proton/FEX for running Windows games, power and thermal behavior, and the install flow.
- `docs/verification-log.md` - the actual audit trail. Every claim in the main document,
  checked against pmaports, the kernel forks, and a real build, with sources. This is
  the file to read if you want to know what is actually confirmed versus assumed.
- `docs/hardware-safety.md` - preparation, backups, the exact flashing procedure, and a
  component-by-component list of what the Linux kernel touches on this phone, what could
  physically go wrong, and how to test it (in Romanian).
- `docs/build-environment.md` - how to set up a machine to build this (WSL2/Ubuntu, the
  toolchain, the recorded traps) and how to reproduce the verified package and image builds.
  Also has the current work queue and the list of things that must not be done yet.
- `reference/dts/` - the three known community device trees for this phone (from three
  different forks), pulled for direct comparison. They disagree with each other on
  several points, including which one has a working GPU versus a working battery
  charger.
- `pmaports/` - draft postmarketOS packages (kernel, device port, firmware, ALSA config)
  for this phone. Not part of upstream pmaports. Built and verified locally through the
  real `abuild`/`pmbootstrap` pipeline.
- `tools/inline-doc-values.py` - a one-off script used to recover numeric values that had
  been embedded as images in the original source document.
- `CLAUDE.md` - writing-style rules used while working on this repo with an AI assistant.

## Key finding so far

No single kernel fork currently has a working GPU, battery charging, and clean USB-C
orientation switching all at the same time. Only the WuerfelDev tree (and the official
postmarketOS SM8250 kernel) has a PM8150B charger driver at all, and that driver currently
programs an unsafe float voltage. The default kernel here is Xo666 (working GPU) with no
charger driver, so charging is left to the PMIC hardware defaults. Details and sources are
in `docs/verification-log.md` and `docs/hardware-safety.md`.

## Target device

OnePlus 8, global variant (IN2013/IN2010), codename `instantnoodle`. Android is wiped
entirely. No modem, calls, or SMS.

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
