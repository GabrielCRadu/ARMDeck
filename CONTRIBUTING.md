# Contributing to ARMDeck

ARMDeck grows through the people who use it: someone with a different phone, a game nobody has
tried, a fix for something that annoyed them. Thank you for being one of them.

The rules below are few. They exist so that people can trust what they read here, so that
nobody damages a phone by following this project, and so that everyone gets credit for their
work. They apply to everyone equally, including the maintainer.

## The short version

1. **Be honest about what you tested.** Say what you ran it on and what happened, including
   what failed.
2. **Keep hardware within the manufacturer's limits.** A software bug can be fixed. A burnt
   component cannot.
3. **Credit other people's work** and respect its license.
4. **Say when AI helped you,** and stand behind the result yourself.
5. **Respect the projects we build on,** including their rules.
6. **Protect privacy:** yours and other people's.
7. **Be kind.** The [Code of Conduct](CODE_OF_CONDUCT.md) applies everywhere in this project.

The rest of this page explains each point.

## 1. Honest reports

- Name the exact device: model, variant code (for example `IN2013`) and, for ports, the board
  information described under [Device variants](#device-variants).
- Use these words with these meanings:
  - **Verified:** tested on real hardware. Say by whom, on which variant, and when.
  - **Builds:** it compiles or packages, but has not run on a device.
  - **Untested:** written, not yet built or run.
- Failures and partial results are welcome. "This game does not start, here is the log" helps
  the next person as much as a success does.
- Do not repeat a claim from another project, forum or AI answer as fact without checking it.
  Link the source so others can check it too.

## 2. Hardware safety

Some changes act directly on the hardware: voltages and regulators, charging, thermal limits,
CPU and GPU frequencies, the speaker amplifiers, display timings. For these:

- **Stay within the manufacturer's values.** The reference is the vendor kernel and device tree
  for that phone (for the OnePlus 8, the
  [LineageOS OnePlus SM8250 kernel](https://github.com/LineageOS/android_kernel_oneplus_sm8250)).
  Equal or more conservative is fine. Beyond it (overclocking, higher charge voltage, higher
  volume limits than tested) is not accepted as a default.
- **Show your source and your test.** Link the vendor file or datasheet the value comes from,
  describe how you tested it on the device, and say how to undo it.
- **Safe by default.** Anything with real risk is opt-in, off by default and clearly labelled.
- **Never ask users to switch off a protection** (thermal guard, charge limit, volume limit)
  to make something work. Fix the cause instead.

A reviewer may ask for this evidence before merging. That is not distrust: it is the same
question asked of every change, including the maintainer's own.

## 3. Credit and licenses

- Keep the authorship of work you bring in: the `From:` line of a patch, `Signed-off-by` lines,
  SPDX headers, copyright notices. Link where it came from.
- Your contribution is licensed like the file it goes into: MIT for ARMDeck's own files,
  GPL-2.0 for kernel patches, the original license for anything under `reference/`.
- Sign off your commits (`git commit -s`). The `Signed-off-by` line means you agree to the
  [Developer Certificate of Origin](https://developercertificate.org/): you have the right to
  submit this work under its license.
- Do not add files you have no right to share: proprietary firmware, Steam or game files,
  keys, someone else's work without permission. Firmware is copied from the user's own phone
  at install time and never stored in this repository.

## 4. AI assistance

AI-assisted contributions are welcome here, on the same terms as any other contribution:

- **Disclose it.** Add an `Assisted-by:` line to the commit message naming the tool, as the
  [Linux kernel asks](https://docs.kernel.org/next/process/coding-assistants.html), for example
  `Assisted-by: Claude`. Mention it in the pull request too.
- **You are the author.** Understand every line, test it on real hardware where it matters, and
  answer review questions yourself. An AI tool never signs off a commit; you do.
- ARMDeck itself is built with AI assistance, and says so in the README.

**Other projects have other rules, and we follow them in their spaces.**
[postmarketOS forbids generative AI](https://docs.postmarketos.org/policies-and-processes/development/ai-policy.html)
in its contributions and community. So: do not submit ARMDeck patches, or anything made with AI
help, to postmarketOS; and do not recommend AI tools in postmarketOS channels. If you want to
contribute something to postmarketOS, write it yourself under their rules. The Linux kernel
accepts AI-assisted patches only with the disclosure and review rules linked above.

## 5. Respect the projects we build on

ARMDeck exists because of the projects listed under Thanks in the [README](README.md).

- Report a bug to the project that owns it (Valve, Mesa, FEX, postmarketOS, a kernel fork),
  with a reproduction that does not depend on ARMDeck. Do not file ARMDeck problems on their
  trackers.
- When they are not ARMDeck's problem, say so: "this is a Valve bug" with a link to their issue
  is a good answer.
- Do not imply endorsement. ARMDeck is not affiliated with Valve, OnePlus, Qualcomm or
  postmarketOS, and does not use their logos.

## 6. Privacy

Logs and screenshots can identify a person or a phone. Before you post them, remove:

- IMEI, serial numbers, MAC and Bluetooth addresses
- Wi-Fi names, IP addresses, account and user names
- anything from other people (messages, names, faces)

Never post passwords, tokens or keys. If you posted something by mistake, tell a maintainer and
it will be removed from the issue.

## 7. How to contribute

### Report a game

Open a **Game report** issue: the game, its Steam ID, the Proton version, what works, the frame
rate if you know it, and the launch options you used.

### Report a device or a port

Open a **Device report** issue with the information below. A port needs at least a working
display, input and storage before it can be listed; everything else can come later, marked
honestly in the device table.

### Report a bug

Open a **Bug report** issue: what you did, what you expected, what happened, and the relevant
logs (with private data removed).

### Send a pull request

- One topic per pull request, with a description of what it changes and how you tested it.
- Comments and documentation in English, so everyone can read them.
- Scripts: POSIX `sh` where possible, and the same style as the files around them.
- Hardware-affecting changes: follow [Hardware safety](#2-hardware-safety).

## Device variants

Phones sold under one name are often different inside. The OnePlus 8, for example, exists in
six variants (IN2010 China, IN2011 India, IN2013 Europe and Asia, IN2015 North America, IN2017
T-Mobile, IN2019 Verizon), with different modems and radio bands. A port verified on one variant
is not automatically safe on another.

For a device report, give:

- **Model and variant code**, from the box or Android's *Settings > About phone*.
- **Codename** (for the OnePlus 8: `instantnoodle`).
- **Board information:** the hardware and project entries the bootloader passes to the kernel.
  Under Linux they are in `/proc/cmdline`; under Android, `adb shell getprop | grep ro.boot`.
  On the OnePlus 8 IN2013 they are `androidboot.project_codename=instantnoodle`,
  `prj_version=19821`, `hw_version=15`, `rf_version=14` and `platform_name=SM8250`: the
  hardware and radio board revisions are what tell two units of the same model apart. Remove
  the serial number (`androidboot.serialno`) before posting.
- **Firmware:** the Android or OxygenOS version the phone had before flashing; firmware files
  come from it.

## Decisions

The maintainer reviews contributions and explains every decision. Anyone can be wrong,
including the maintainer: if you disagree, say why, with sources, and the decision will be
reconsidered. ARMDeck is a volunteer project, so answers can take a few days.
