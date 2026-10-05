# Rules for Claude

## Language

- Talk to the maintainer in Romanian.
- Everything that goes into the repository is in English: documents, code comments, script
  output, commit messages.

## Writing style

1. **Never use the em dash** (U+2014). Use a comma, a colon, parentheses or a plain hyphen `-`
   instead. Avoid the en dash (U+2013) too: for ranges use a plain hyphen, e.g. `45-52 °C`.
   This applies everywhere: chat, markdown files, code comments, commit messages.

2. **No needlessly abstract or niche wording.** The maintainer has real hands-on experience
   (rooting, custom ROMs, flashing) but does not know every piece of specialist jargon. When a
   niche term appears, explain it briefly the first time.

   Examples of terms that need a short explanation:
   - *device tree / DTS* = the file that describes the hardware to the kernel
   - *zap shader* = signed firmware without which the GPU does not start
   - *pressure-vessel* = the container Steam runs games in
   - *remoteproc* = the auxiliary processors in the SoC (audio DSP, sensor DSP)

   Prefer direct wording over academic wording. "The GPU does not start without this file"
   beats "signed firmware dependency is an initialization precondition".

## Hardware safety

A software bug can be fixed; a burnt component cannot. Every change that affects the hardware
(voltages, regulators, charging, thermal limits, frequencies, audio levels, display) is checked
against the vendor sources and the real device before it is handed over, and never goes beyond
the manufacturer's values. Never write to the phone (flash, erase, set slots) without the
maintainer's explicit OK at that moment.

## Working rules (set by the maintainer, 2026-10-04)

1. **Everything that reaches GitHub is in English**: documents, code comments, script output,
   commit messages, file names.
2. **One thing at a time.** Finish the task in progress before starting another. If the
   maintainer starts something new while a task is open, say so and finish or explicitly park
   the open task first.
3. **Every problem is a lesson.** Record each problem met and how it was solved (or why it is
   still open) in [docs/lessons-learned.md](docs/lessons-learned.md), right when it happens.
4. **Goal for games:** almost every game compatible, and squeeze out every bit of performance by
   removing pointless losses (overhead, debug leftovers, bad defaults).
5. **Final goal:** a stable, efficient system where gaming is genuinely pleasant, like a Steam
   Deck, where every menu and option works.
6. **Sources are checked for news at the start of every working session** (set 2026-10-05): every
   outside project we use is listed in [docs/sources.md](docs/sources.md). At the start of each
   session run `python tools/check-sources.py`, without `--if-older-than` (a time threshold once
   skipped a check and missed a day of DroidDeck work), and tell the maintainer, briefly, what is
   relevant to ARMDeck (fixes for our chip, new versions of what we patch, ideas for other
   devices). New sources the maintainer mentions go into that list.

## Project context

See [docs/verification-log.md](docs/verification-log.md) for the verified state of the project.
In short: a OnePlus 8 (IN2013, codename `instantnoodle`) turned into a handheld console with
mainline Linux. The phone is wiped completely: no Android, no modem, no calls. ARMDeck aims to
support more Snapdragon phones through community device ports.
