# Build environment and handoff

How to set up a machine for this project and get back to the state
[`verification-log.md`](verification-log.md) describes, plus what the next piece of work is.

Everything here has been done at least once, on Ubuntu 24.04 under WSL2. Where a step is a
recorded trap rather than a normal instruction, it says so.

**Nothing in this document flashes a phone.** See [Do not do this yet](#do-not-do-this-yet)
at the bottom before you get ideas.

---

## 0. What you need

- A Linux host. Ubuntu 24.04 is what every verified build in the log used. WSL2 counts.
- About **40 GB of free disk**. The kernel source, the pmbootstrap chroots and the generated
  images add up faster than you expect.
- No phone. Everything in sections 1 to 6 is hardware-independent.

---

## 1. WSL2 on Windows

Skip this section on a real Linux host.

### The trap

`wsl --install -d Ubuntu-24.04` on a clean Windows 11 machine can fail with:

```
Downloading: Windows Subsystem for Linux 2.7.12
Installing: Windows Subsystem for Linux 2.7.12
Catastrophic failure
```

That message is just `E_UNEXPECTED` and tells you nothing. The actual state on the machine
where this happened (Windows 11 Pro 26200, Ryzen 7 5700U):

```
VirtualMachinePlatform             disabled
Microsoft-Windows-Subsystem-Linux  disabled
HypervisorPlatform                 disabled
HypervisorPresent                  False
VirtualizationFirmwareEnabled      True     <- CPU/BIOS were fine
```

WSL 2.7.x installs itself as a Store package (MSIX) and had failed at that step without ever
enabling the Windows features it depends on. `VirtualMachinePlatform` is the virtualization
layer WSL2 runs its Linux kernel on top of, as a very thin virtual machine. Without it there
is nothing for WSL2 to run on.

### The fix

Enable the features by hand first, which is the documented manual route. In **PowerShell as
Administrator**:

```powershell
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
```

Both must answer `The operation completed successfully.`

**Reboot.** The hypervisor only loads at boot; skipping this makes the next step fail again.

Then install WSL on its own, before adding any distribution, so that a failure tells you which
half broke:

```powershell
wsl --install --no-distribution
wsl --install -d Ubuntu-24.04
```

Check it:

```powershell
wsl -l -v
```

You want `Ubuntu-24.04` at `VERSION 2`.

### If it still fails

Get the real error instead of guessing, as Administrator:

```powershell
Get-WinEvent -LogName Microsoft-Windows-AppXDeploymentServer/Operational -MaxEvents 30 |
  Where-Object { $_.LevelDisplayName -ne 'Information' } |
  Select-Object TimeCreated, Id, LevelDisplayName, Message | Format-List
```

You can also read feature state without Administrator rights, which is how the diagnosis above
was made:

```powershell
Get-CimInstance Win32_OptionalFeature |
  Where-Object { $_.Name -match 'Linux|VirtualMachine|Hyper-V|HypervisorPlatform' } |
  Select-Object Name, InstallState
```

`InstallState` is `1` for enabled, `2` for disabled.

---

## 2. Host packages

Inside Ubuntu:

```bash
sudo apt update
sudo apt install -y build-essential git clang lld llvm pipx \
                    gcc-aarch64-linux-gnu flex bison libssl-dev bc
pipx install pmbootstrap
pipx ensurepath
```

Then reopen the shell so `pmbootstrap` is on `PATH`.

Why both toolchains: the standalone kernel sanity build in section 6 uses the GCC cross
compiler (`gcc-aarch64-linux-gnu`), while `linux-oneplus-instantnoodle`'s APKBUILD builds with
`ARCH=arm64 LLVM=1`, matching the convention the packaged `linux-postmarketos-qcom-sm8250`
kernel uses. Both paths have been verified; keep both installed.

---

## 3. Passwordless sudo

**This is a recorded trap, not a preference.** Without it, `pmbootstrap`'s internal
`sudo losetup` and mount calls hang forever waiting for a password prompt that can never be
answered, with no error message. It silently hung twice before the cause was found.

```bash
echo "$USER ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/pmbootstrap
sudo chmod 0440 /etc/sudoers.d/pmbootstrap
```

---

## 4. Do not build on `/mnt/c`

WSL reaches the Windows drive through a translation layer that is several times slower for the
many-small-files workload a kernel build is. Keep the kernel clone, the pmaports checkout and
the pmbootstrap work directory in the Linux filesystem, under `~/`.

Editing this repo from the Windows side is fine. Building in it is not.

---

## 5. Rebuilding the verified state

This reproduces what [`verification-log.md` §7.5](verification-log.md) recorded.

### 5.1 Get the sources

```bash
cd ~
git clone https://github.com/GabrielCRadu/steamed-noodle.git
git clone --depth 1 https://gitlab.postmarketos.org/postmarketOS/pmaports.git
```

### 5.2 Drop the draft packages into pmaports

The four packages in this repo's `pmaports/` are not part of upstream pmaports. They have to be
copied into a local pmaports checkout for `pmbootstrap` to see them:

```bash
cp -r ~/steamed-noodle/pmaports/* ~/pmaports/device/testing/
```

### 5.3 Initialize pmbootstrap against that checkout

```bash
pmbootstrap init
```

Point it at `~/pmaports` when it asks for the aports path. Then answer:

- vendor: `oneplus`
- codename: `instantnoodle`
- user interface: `none` for now, see section 7

If the packages were copied correctly, `instantnoodle` appears as a valid codename alongside
the officially packaged `instantnoodlep` and `kebab`, with **no** "create new port" prompt.
If it offers to create a new port instead, the copy in 5.2 did not land where pmbootstrap
looks.

### 5.4 Checksums and build

```bash
pmbootstrap checksum linux-oneplus-instantnoodle
pmbootstrap -y build linux-oneplus-instantnoodle
pmbootstrap -y build device-oneplus-instantnoodle
pmbootstrap -y build firmware-oneplus-instantnoodle
pmbootstrap -y build alsa-ucm-conf-oneplus-instantnoodle
```

Expect roughly 18 to 20 minutes for the kernel on a cold cache, a few seconds for the rest.
The firmware package downloads the proprietary blobs from
`github.com/Xo666/linux-oneplus-instantnoodle` by commit hash; you do not need to extract them
from an OxygenOS image yourself. See the licensing caveat in that APKBUILD's header.

### 5.5 Build the images

```bash
pmbootstrap install          # NOT --split, see below
pmbootstrap export           # links boot.img, dtbo.img, oneplus-instantnoodle.img in /tmp/postmarketOS-export
```

Corrected 2026-10-01: an earlier version of this section used `pmbootstrap install --split`.
With the `fastboot` flash method that cannot be followed by `pmbootstrap flasher flash_rootfs`
(it looks for `<device>.img`, which only exists without `--split`) and it also skips the sparse
conversion. The plain install produced a 1.3 GiB rootfs (sparse, about 640 MB) that was flashed
to a real phone on 2026-10-01; the exact procedure is in `docs/hardware-safety.md` section 3.

---

## 6. Optional: standalone kernel sanity build

Useful when you want to check a device tree change quickly without going through packaging.

```bash
cd ~
git clone --depth 1 -b 6.16.7 https://github.com/Xo666/mainline-instantnoodle.git
cd mainline-instantnoodle
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- op8_defconfig
make -j"$(nproc)" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- Image.gz dtbs
```

About 5m30s on 16 cores. Produces `arch/arm64/boot/Image.gz` and
`arch/arm64/boot/dts/qcom/sm8250-oneplus-instantnoodle.dtb`.

To inspect a device tree change, decompile the result and read it back:

```bash
dtc -I dtb -O dts arch/arm64/boot/dts/qcom/sm8250-oneplus-instantnoodle.dtb | less
```

That is how the charger port in §7.5 was verified not to disturb the zap-shader node. (That
port was later removed: the Xo666 kernel has no driver for those nodes, see
`docs/verification-log.md` section 9.1.)

---

## 7. What to do next

The work queue, in order, per [`verification-log.md` §7.6](verification-log.md).

### 7.1 The native layer, first

Write a UI package that starts `gamescope` at boot for this device port, in the shape of the
existing `postmarketos-ui-*` packages in `~/pmaports/main/`.

This is assembly, not porting. Alpine `aarch64` already ships everything it needs:

| Package | Version checked | Repo |
|---|---|---|
| `gamescope` | 3.16.24-r1 | community |
| `mesa-vulkan-freedreno` (Turnip) | 26.1.6-r1 | main |
| `vulkan-loader` | 1.4.360-r0 | main |
| `seatd`, `wlroots0.20`, `libliftoff`, `xwayland`, `mangohud` | | community |

Then rebuild the image from section 5.5 with that UI selected in `pmbootstrap init` and confirm
the packages resolve and install. That is as far as it can be verified without hardware.

### 7.2 The x86 translation layer, second

**Do not package FEX for musl.** §7.6.2 and §7.6.6 explain why at length. The short version:
it is not a supported configuration upstream, there is no CI for it, and nobody runs it that
way. Both documented postmarketOS routes put a glibc distribution in a container on top of the
musl host:

- `apk add distrobox`, Ubuntu 24.04 container, FEX from its Ubuntu PPA
- or a Debian container with box86/box64

Every container tool needed is already in Alpine `aarch64` (`distrobox`, `podman`,
`docker-engine`, `squashfuse`, `erofs-utils`), and `op8_defconfig` already has
`CONFIG_BINFMT_MISC` plus every container primitive. The one kernel gap is `CONFIG_EROFS_FS`,
which `erofs-fuse` covers in userspace.

Track FEX issue [#4120](https://github.com/FEX-Emu/FEX/issues/4120) while doing this. If it
lands, the Snapdragon 865 is on its published drop list, and box64 becomes the translator
rather than FEX.

---

## Do not do this yet

**Superseded on 2026-10-01.** The phone was flashed that day, after a full verified backup,
following `docs/hardware-safety.md`. Several items that used to be listed here were wrong
when checked against source code: vbmeta is optional on this phone family (the official 8 Pro
and 8T ports never write it), `deviceinfo_super_partitions` is read by the initramfs (it was
removed as unnecessary), and the charger patch was inert. Details in
`docs/verification-log.md` sections 9 and 10.

What still must not be done:

- Do not use the WuerfelDev kernel or the official postmarketOS SM8250 kernel's
  `qcom_pm8150b_charger.c` on this phone as they are: it programs about 4.87 V float voltage.
- Do not run `fastboot flashing lock` with anything but stock OxygenOS on the phone.
- Do not run `apk upgrade --prune` or `apk upgrade --available` on the phone: the kernel,
  firmware and device packages are local builds that no online repository carries.
- Do not raise the speaker volume before a limiter is set up (`docs/hardware-safety.md` 4.4).
