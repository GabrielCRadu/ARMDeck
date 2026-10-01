# Audit de performanță și prevenire a crash-urilor (2026-10-01)

Făcut după resetul neașteptat din timpul descărcării unui joc (`gaming-stack.md` 9) și după
instalarea jurnalului `op8-log`. Toate datele sunt citite de pe telefon, doar în mod citire:
`sysfs`, `/proc`, configurația kernelului (`/proc/config.gz`), jurnalul systemd.
Complementar cu [`hardware-safety.md`](hardware-safety.md) (riscuri fizice) și
[`security-audit.md`](security-audit.md).

Termeni:
- *BCL* = limitatorul de curent al bateriei: pe Android încetinește CPU/GPU când tensiunea
  bateriei scade brusc, ca telefonul să nu se oprească.
- *UVLO* = oprirea de protecție a PMIC-ului când tensiunea scade sub prag.
- *detector de blocaj (softlockup/hardlockup)* = cod din kernel care observă un procesor blocat
  și scrie în jurnal ce făcea, în loc ca telefonul să se reseteze fără nicio urmă.
- *NTSYNC* = mecanism din kernel pentru sincronizarea din jocurile Windows; Proton îl folosește
  pentru performanță.
- *preempțiune* = cât de repede poate kernelul întrerupe o sarcină ca să ruleze alta mai
  urgentă (input, audio, compozitor).

## Pe scurt

| # | Constatare | Importanță | Măsură | Unde |
|---|---|---|---|---|
| C1 | Rootfs-ul are 3.7 GB liberi (71% ocupat), Steam ocupă 6.3 GB | ridicată | Biblioteca Steam pe `userdata` (219 GiB) | config, cu OK |
| C2 | Bateria are 71.7% din capacitate (3062 / 4270 mAh), fără BCL în mainline | medie | Limită de frecvență pe nucleele mari pe baterie; urmărit `bat_mv` în `op8-log` | config |
| C3 | Toți detectorii de blocaj sunt dezactivați | ridicată (diagnostic) | Activați în kernelul r6, fără panic | kernel r6 |
| C4 | WiFi: firmware OnePlus din 2022, MAC instabil după reset | medie | Test cu `op8-live.sh`; alternativ firmware-ul din linux-firmware; patch MAC | test, r6 |
| C5 | Modemul 5G (SDX55) e activ pe PCIe, fără driver | scăzută-medie | `pcie2` dezactivat în DTS, după verificare | kernel r6 |
| C6 | `/boot` (ext2, fără jurnal) e montat rw și nu e verificat niciodată | scăzută | `/boot` read-only + o verificare `e2fsck` | config |
| P1 | Lipsește `NTSYNC` | medie | `CONFIG_NTSYNC=y` | kernel r6 |
| P2 | Kernel fără preempțiune (`PREEMPT_NONE`, configurație de server) | medie | `PREEMPT_DYNAMIC` | kernel r6 |
| P3 | GPU-ul își ajustează frecvența la 50 ms | medie | 16-20 ms (frecvențele rămân ≤ 587 MHz) | config |
| P4 | gamescope rulează fără `CAP_SYS_NICE` | medie | `setcap cap_sys_nice+ep` pe gamescope | config |
| P5 | DXVK 3 nu merge pe Adreno 650 | ridicată (jocuri DirectX) | DXVK 2.7 (`gaming-stack.md`) | userspace |
| P6 | Fără `sched_ext` (planificatorul `scx_lavd` de la pocknix) | scăzută | `SCHED_CLASS_EXT` + BTF | kernel r6 |
| P7 | Transparent huge pages pe `always` | scăzută | `madvise` | config |
| P8 | gamescope alege 90 Hz | scăzută | 60 Hz în sesiunile lungi | config |

"config" = setări din rootfs, aplicabile acum cu un script sudo. "kernel r6" = următorul kernel
construit în WSL și scris în `boot_b`.

## Prevenirea crash-urilor

### C1. Spațiu pe rootfs

- **Dovadă:** `df`: 13.1 GB, 8.8 GB folosiți, 3.7 GB liberi; `~/.local/share/Steam` 6.3 GB,
  containerul 206 MB. Rootfs-ul stă în `super` (14 GiB), care nu poate crește.
- **Risc:** la 100%, `journald`, `op8-sampler`, Steam și podman nu mai pot scrie. Urmează
  descărcări corupte, servicii căzute și jurnale pierdute exact când avem nevoie de ele.
- **Măsură:** `userdata` formatat ext4 și montat pentru biblioteca Steam (și eventual pentru
  stocarea containerelor). Utilizatorul a acceptat ștergerea datelor Android vechi; Android
  rămâne reinstalabil prin MSM. Se face doar cu OK explicit la momentul respectiv.

### C2. Baterie uzată și lipsa BCL

- **Dovadă:** `charge_full = 3062000`, `charge_full_design = 4270000` µAh (71.7%). În PMIC,
  `FAULT_REASON1` are bitul UVLO memorat dintr-un eveniment vechi. Kernelul mainline nu are
  driver BCL pentru PM8150B.
- **Risc:** o baterie uzată are rezistență internă mai mare, deci tensiunea scade mai mult la
  vârfuri de curent (CPU + GPU + WiFi + UFS simultan). Fără BCL, nimic nu încetinește sistemul
  înainte de pragul UVLO. **Nu strică hardware-ul**, UVLO e o protecție, dar înseamnă oprire
  bruscă și risc pentru sistemul de fișiere.
- **Notă:** resetul din 2026-10-01 **nu** a fost UVLO: ultima secvență e `POFF_SEQ`, nu
  `FAULT_SEQ` (`gaming-stack.md` 9).
- **Măsuri:** coloana `bat_mv` din `op8-log` arată acum cât scade tensiunea sub sarcină. Dacă
  vedem căderi sub ~3.4 V, limităm nucleul prime (`policy7`, 2.84 GHz) și clusterul mare
  (`policy4`, 2.42 GHz) în sesiunile de joc pe baterie. Sesiunile lungi se joacă la încărcător
  de 5 V. Pe termen lung, o baterie nouă.

### C3. Detectorii de blocaj sunt dezactivați

- **Dovadă:** `# CONFIG_SOFTLOCKUP_DETECTOR`, `# CONFIG_HARDLOCKUP_DETECTOR`,
  `# CONFIG_DETECT_HUNG_TASK`, `# CONFIG_WQ_WATCHDOG` (toate "not set"). `ramoops` e activ în
  kernel, dar bootloader-ul OnePlus nu păstrează memoria la reset (`/sys/fs/pstore` gol, nici
  măcar `console-ramoops`). systemd nu folosește watchdog-ul (`RuntimeWatchdogUSec=0`).
- **Risc:** un procesor blocat duce direct la reset, fără niciun mesaj. Exact situația din
  incident.
- **Măsură (r6):** `SOFTLOCKUP_DETECTOR`, `HARDLOCKUP_DETECTOR` (varianta "buddy", nu are
  nevoie de NMI), `DETECT_HUNG_TASK` și `WQ_WATCHDOG`, **fără** panic automat. Un blocaj lasă
  atunci o urmă în jurnal (scris la 2 s) și în fluxul `op8-live.sh` de pe PC.
- `kernel.panic=120` rămâne așa până aflăm cauza: un îngheț de ~120 s înainte de repornire
  înseamnă panic, unul mai scurt înseamnă watchdog. După diagnoză se poate scădea la 10 s.

### C4. WiFi

- **Dovadă:** `ath11k` rulează firmware-ul OnePlus `WLAN.HST.1.0.1.r1-01272` (build
  2022-12-20), cu proveniență neverificată (`security-audit.md` S8). După reset cipul a raportat
  alt MAC decât `00:03:7F:12:77:C7`, iar NetworkManager a refuzat profilul legat de el.
- **Risc:** suspectul principal al resetului (descărcare mare pe WiFi). Un cip WiFi care nu
  pornește curat după un reset "warm" e un semn în plus.
- **Măsuri:** reproducerea descărcării cu `op8-log` + `op8-live.sh`; dacă se confirmă, test cu
  firmware-ul QCA6390 din linux-firmware. Pentru MAC, pocknix are
  `0014-fix-wifi-and-bt-mac.patch` (de luat în r6). Profilul WiFi nu mai e legat de MAC.

### C5. Modemul 5G e pornit pe PCIe

- **Dovadă:** `0002:01:00.0 vendor=0x17cb device=0x0306` (SDX55), fără driver;
  `mhi-pci-generic` încearcă să-l pornească și eșuează (`-110`, "No firmware image defined").
- **Corectează `hardware-safety.md` 4.13:** legătura PCIe spre modem **se stabilește**. Nimic
  nu scrie în EFS (nu există `rmtfs`, nici firmware de modem), deci riscul pentru IMEI rămâne
  zero. Dar e un dispozitiv alimentat, neadministrat, pe o magistrală a SoC-ului.
- **Măsură (r6):** nodul `pcie2` dezactivat în DTS, după ce verificăm că modemul nu e necesar
  pentru altceva (de exemplu GPS-ul trece prin el pe Android).

### C6. Partiția `/boot`

- **Dovadă:** `/boot` e ext2 (fără jurnal), montat rw, cu `fsck` dezactivat în fstab (pass 0).
  După reset: "mounting unchecked fs, running e2fsck is recommended". Rootfs-ul ext4 a fost
  reparat automat de initramfs (2 inode-uri orfane ale lui `gabriel`, fișiere temporare).
- **Risc:** un reset în timpul unei scrieri în `/boot` (`mkinitfs`) îl poate strica. La pornire
  nu contează, bootloader-ul citește `boot_b`, nu `/boot`.
- **Măsură:** `/boot` read-only în fstab (kernelul îl construim în WSL, nu pe telefon) și o
  verificare `e2fsck -p` cât e demontat.

### Ce e deja în regulă

- **Limitarea termică hardware:** blocul EPSS (`qcom,sm8250-cpufreq-epss`) cu 3 întreruperi
  `dcvsh`, gestionate de `qcom-cpufreq-hw` (inclus în kernel). 0 evenimente până acum.
  Modulul `qcom_lmh` nu se încarcă și nici nu trebuie: e pentru alte SoC-uri. Corectează nuanța
  din `hardware-safety.md` 4.8.
- **Praguri termice:** CPU 90/95 °C (încetinire), 110 °C (oprire); GPU 85/90/110 °C;
  PM8150B 95/115/145 °C.
- **Senzori:** `qcom_tsens`, `qcom_spmi_temp_alarm`, `qcom_spmi_adc_tm5` încărcate.
- **Memorie:** zram zstd de 17 GB, `swappiness=180`, `systemd-oomd` activ, PSI activ.
- **Kernel:** `tainted=0` (niciun WARN sau oops în pornirea curentă).
- **Repaus:** 97% idle, doar servicii de bază.

## Performanță

### P1. NTSYNC

`# CONFIG_NTSYNC is not set`. Proton folosește `/dev/ntsync` când există; fără el revine la
mecanisme mai lente. Armada și SteamOS-ARM-Handhelds îl activează. **r6:** `CONFIG_NTSYNC=y`.

### P2. Preempțiune

`CONFIG_PREEMPT_NONE=y`, `HZ=250`. E configurația pentru servere: o sarcină lungă din kernel
(de exemplu I/O intens) poate întârzia compozitorul, inputul și audio. **r6:**
`PREEMPT_DYNAMIC` (se alege la pornire între `voluntary` și `full`).

### P3. Frecvența GPU

`simple_ondemand`, `polling_interval = 50` ms, frecvențe 305-587 MHz. La 50 ms, GPU-ul
reacționează cu 3 cadre întârziere (la 60 Hz). KONKR/SteamOS-ARM-Handhelds folosesc 16 ms.
**Măsură:** `polling_interval` 16-20 ms, setat la pornire. Fără risc: limitele de frecvență
rămân aceleași.

### P4. Prioritatea lui gamescope

`No CAP_SYS_NICE, falling back to regular-priority compute and threads` (logul gamescope).
**Măsură:** `setcap cap_sys_nice+ep /usr/bin/gamescope`, ca pe SteamOS.

### P5. DXVK

Confirmat pe hardware: `storageBuffer8BitAccess = false` pe Adreno 650. DXVK 3 nu pornește;
trebuie DXVK 2.7 (`gaming-stack.md` TODO 6).

### P6-P8. Mai mici

- **P6:** fără `sched_ext`. pocknix rulează `scx_lavd` pentru ritmul cadrelor; cere
  `SCHED_CLASS_EXT` și BTF (`DEBUG_INFO_BTF`) în r6.
- **P7:** THP pe `always` poate produce sacadări (compactarea memoriei); `madvise` e
  alegerea obișnuită pentru jocuri.
- **P8:** gamescope alege modul de 90 Hz al panoului. 60 Hz înseamnă mai puțină căldură și
  consum în sesiunile lungi.

### Deja bine

`schedutil` pe toate clusterele, frecvențele maxime CPU egale cu cele hardware (1.80 / 2.42 /
2.84 GHz), `mq-deadline` pe UFS cu read-ahead 1 MB, `ENERGY_MODEL`, `SCHED_MC`, `UCLAMP_TASK`,
`BPF_JIT`.

## Ordinea propusă

1. **Acum, fără kernel nou:** C1 (spațiu, cu OK), P3, P4, P7, C6, apoi retestul descărcării cu
   `op8-log` + `op8-live.sh`.
2. **Kernel r6** (un singur build): C3, P1, P2, P6, patch-ul MAC (C4), eventual C5, plus
   opțiunile de securitate din `security-audit.md` S3.
3. **După r6:** DXVK 2.7, FEX pentru jocuri Linux x86, audio cu limitator.
