# Security audit (2026-10-01)

Complements [`hardware-safety.md`](hardware-safety.md), which covers the physical risks. Here:
what can be exploited or can leak (data, access to the phone, access to the PC). Each finding
has its verified evidence and the recommended measure. Ordered from most to least important.

## S1. A kernel out of support (high)

- **Evidence:** the kernel in use is Xo666 6.16.7 (September 2025, a branch not updated since
  January 2026). On kernel.org, the 6.16 series is no longer in the maintained list; 7.2, 6.18
  LTS and 6.12 LTS are supported now. So about a year of security fixes is missing.
- **Why it matters:** the remote attack surface is Wi-Fi (`ath11k`), Bluetooth and the network
  stack; locally, games run through Proton/FEX are foreign code running on the phone.
- **Measures now:** Bluetooth off when not in use, no public or unknown Wi-Fi networks, the
  firewall active (see S2).
- **In the medium term:** moving the DTS and the ARMDeck patches to a maintained kernel (for
  example the postmarketOS SM8250 7.x kernel), **without** its charger driver until it is fixed
  (`hardware-safety.md` 4.1).

## S2. SSH open on every interface, with a password (high on Wi-Fi)

- **Evidence:** the postmarketOS firewall drops all incoming traffic by default (the `drop`
  policy in Alpine's `nftables.nft`), but the `openssh-nftrules` package adds
  `tcp dport 22 accept` with no interface restriction, and the pmOS configuration for `sshd` only
  sets `UsePAM yes`, so password authentication stays on (the OpenSSH default).
- **Risk:** on any Wi-Fi you join, anyone on the network can try passwords on SSH.
- **Measures:**
  1. A long password at `pmbootstrap install` (it is also the SSH password).
  2. An SSH key: `pmbootstrap init` offers to copy your public keys. After the first login with
     the key, on the phone: `PasswordAuthentication no` in a file in `/etc/ssh/sshd_config.d/`.
  3. Optionally, SSH only over the cable: replace `/etc/nftables.d/50_sshd.nft` with a rule that
     accepts port 22 only on `usb*`.

**Applied on the phone (2026-10-01):** `/etc/nftables.d/40_ssh_usb_only.nft` drops SSH traffic
arriving on `wlan*` before the rule that accepts it. Checked: from the PC, port 22 on the
phone's Wi-Fi IP no longer answers, while SSH over the USB cable works. The file belongs to no
package, so it survives updates. Logins are done with an SSH key. Later
(`userspace/system/stageA2.sh`) SSH over Wi-Fi was allowed from the PC's IP address only.

## S3. Kernel protections disabled (medium)

- **Evidence** (`op8_defconfig`): enabled: KASLR, `STRICT_KERNEL_RWX`, `STACKPROTECTOR_STRONG`,
  PAC and BTI. **Disabled:** `HARDENED_USERCOPY`, `FORTIFY_SOURCE`, `INIT_STACK_ALL_ZERO` (the
  amplifier bug started there), `SLAB_FREELIST_HARDENED`, `SLAB_FREELIST_RANDOM`, `LIST_HARDENED`,
  `SECURITY_YAMA`, `SECURITY_LANDLOCK`, `MODULE_SIG`. `DEBUG_FS` and `KEXEC` are enabled.
- **Measure:** first boot with the author's configuration, as a reference. Then, in a separate
  step, enable one at a time `INIT_STACK_ALL_ZERO`, `SLAB_FREELIST_HARDENED`,
  `SLAB_FREELIST_RANDOM`, `SECURITY_YAMA`, `LIST_HARDENED`, `HARDENED_USERCOPY`, `FORTIFY_SOURCE`,
  with a test after each (the last two can expose bugs in drivers).

## S4. A permanently unlocked bootloader, unencrypted data (medium)

- Inherent to the project: whoever holds the phone can boot or write anything. Without
  encryption, the data in pmOS (including the Steam session, once you add it) can be read
  directly.
- **Measure:** `pmbootstrap install --fde` encrypts the root filesystem. The password is entered
  at every boot on the screen (the `unl0kr` keyboard). The choice is yours: security versus
  convenience.
- The old Android data (`userdata`) stays on the phone, encrypted by Android, untouched by pmOS
  (unless you reformat it for games, `userspace/system/format-games.sh`).

## S5. The backup contains the phone's identity (medium)

- The partition backup contains the modem EFS (`mdm1m9kefs1/2`, IMEI), `persist`, `param` and,
  in `getvar-all.txt`, the phone's serial number. They can be used to clone the device's
  identity.
- **Measures:** do not upload it unencrypted to the cloud. Keep the second copy in an encrypted
  archive (7-Zip, AES-256, with a password). In the repository, `.gitignore` covers `backup*/` and
  `getvar*.txt`.

## S6. The MSM package comes from a third-party site (medium)

- The MSM Download Tool is a closed Windows executable, distributed through AndroidFileHost, not
  by OnePlus. The firmware it writes is checked by the phone's signed boot chain, but the
  executable runs on your PC.
- **Measures:** check the MD5 against the one in the XDA thread, scan it on VirusTotal, and run it
  only if you really need it.

## S7. Passwordless sudo in WSL (low)

- A file in `/etc/sudoers.d/` with `NOPASSWD:ALL` for your user, set up for pmbootstrap. Any
  process in WSL running as you becomes root without confirmation.
- **Measure:** once the builds are done, remove that file.

## S8. Firmware origin (low)

- Checked by git hash: the unsigned GPU firmware (`a650_sqe.fw`, `a650_gmu.bin`) and `m3.bin`
  are identical to the official linux-firmware; `board-2.bin` is the official 2022-04-23
  version. `amss.bin` (Wi-Fi) matches no linux-firmware version. The DSP firmware and the zap
  shader are signed and checked by TrustZone. The Wi-Fi chip reaches memory only through the
  SMMU.

## S8b. The package repositories use HTTP (low)

- `/etc/apk/repositories` on the phone uses `http://` (the postmarketOS/Alpine default), and
  `mirror.postmarketos.org` redirects to `http://mirror.nura.eco`. Packages and the index are
  cryptographically signed, so they cannot be modified on the way. Only which packages you
  download is exposed, plus the possibility of being served an older index.
- **Measure:** `https://` for `dl-cdn.alpinelinux.org` (it supports HTTPS). For the pmOS mirror,
  check first whether it serves HTTPS.

## S9. What is fine

- The git history contains no phone serial number, IMEI, keys or tokens. The only personal
  information is the author's email address in the commit metadata (it can be replaced with the
  GitHub "noreply" address for future commits).
- All sources in the APKBUILDs come over HTTPS and are pinned by sha512 (checked with
  `pmbootstrap checksum --verify`).
- The drivers on the PC (fastboot, Qualcomm 9008) are signed and installed through Windows
  Update.
- Other ports pmOS opens by default (`localsend` 53317, `ausweisapp2` 24727, mosh) have no
  service listening unless you install those apps.
