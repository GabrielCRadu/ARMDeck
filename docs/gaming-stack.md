# Stack-ul de gaming: cercetare și recomandare (2026-10-01)

Ce am verificat: SteamOS, Bazzite, Armada OS și cele două alternative ARM găsite pe parcurs
(pocknix-os și SteamOS-ARM-Handhelds). Pentru fiecare: dacă se poate instala pe OnePlus 8, ce
putem prelua de la el și ce e periculos în el. Sursele (cod, issue-uri, README-uri) sunt la
final. Telefonul a fost citit doar în mod read-only (RAM, partiții, flag-uri CPU, config kernel).

Termeni folosiți des:
- *FEX* = traducătorul care rulează programe x86 (Steam pentru PC, jocuri Linux x86) pe ARM.
- *Proton* = varianta Valve de Wine, rulează jocuri Windows. Versiunea ARM64 folosește tot FEX
  în interior pentru codul x86 al jocului.
- *DXVK* = traduce DirectX 9/10/11 în Vulkan. Fără el, jocurile Windows DirectX nu merg.
- *Turnip* = driverul Vulkan open source pentru GPU-urile Adreno (al nostru e Adreno 650).
- *gamescope* = compozitorul din "Game Mode" de pe Steam Deck (pornește direct în interfața Steam).
- *glibc / musl* = două biblioteci C de bază. Aproape tot software-ul Linux binar (inclusiv
  Steam) e compilat pentru glibc. postmarketOS folosește musl.
- *ABL* = bootloader-ul Android de pe telefon (cel care face fastboot și pornește `boot.img`).

---

## 1. Pe scurt

1. **Niciuna dintre distribuții nu se instalează pe OnePlus 8 așa cum vine.** SteamOS nu are
   imagine ARM publică, Bazzite e doar x86_64, iar Armada și pocknix pornesc printr-un ABL
   nesemnat (ROCKNIX ABL) care pe telefonul nostru (`secure: yes`) nu ar porni deloc.
2. **Kernelurile lor sunt periculoase pentru telefonul nostru**, din două motive găsite în cod:
   driverul de încărcare cu bug-ul de ~4.87 V și un overclock de GPU la 925 MHz gândit pentru
   console cu ventilator (secțiunea 3).
3. **Vestea bună:** Armada și pocknix rulează deja Steam ARM64 + Proton ARM64 + FEX pe
   **Retroid Pocket 5, care are exact SoC-ul nostru (SM8250)**. Rețeta de userspace e
   dovedită pe siliciul ăsta.
4. **Recomandare:** păstrăm kernelul nostru (verificat pe hardware) și construim deasupra un
   userspace glibc după rețeta pocknix/Armada, în două etape: întâi un test fără niciun flash,
   în postmarketOS-ul actual, apoi un rootfs Arch Linux ARM nativ (secțiunea 6).

---

## 2. Proiectele, unul câte unul

| Proiect | Bază | Ce SoC-uri | Cum pornește | Pe OP8 așa cum e? | Ce luăm de la el |
|---|---|---|---|---|---|
| SteamOS (Valve) | Arch | x86_64 (Deck); ARM doar pe Steam Frame | imagine Valve | Nu: nu există imagine ARM publică | Nimic direct |
| Bazzite | Fedora Atomic | doar x86_64 | UEFI | Nu | Nimic |
| Armada OS | Fedora bootc | SM8250, SM8550, SM8650 etc. (dispozitive ROCKNIX) | ROCKNIX ABL → UEFI → systemd-boot | **Nu**: cere ABL nesemnat | Rețeta: FEX + rootfs Arch, Proton, sesiunea gamescope, inputplumber |
| pocknix-os | Arch Linux ARM | SM8250 (RP5, Flip 2), SM8550 | ROCKNIX ABL (recomandat) sau meniul ABL Retroid | **Nu**: pe OP8 nu există nici ABL ROCKNIX, nici meniul Retroid | Pachetele de userspace (pacman), DXVK 2.7 pentru Adreno 650 |
| SteamOS-ARM-Handhelds | imaginea SteamOS a lui Steam Frame | SM8650, SM8550, SM8750, REDMAGIC 6 (SM8350) | ROCKNIX ABL; pe REDMAGIC 6 ABL-ul stock | Nu direct (nu are SM8250), dar metoda REDMAGIC 6 e aplicabilă | Dovada că un telefon cu ABL stock poate porni SteamOS ARM |
| postmarketOS (ce rulează acum) | Alpine (musl) | instantnoodle, portul nostru | ABL stock, `boot_b` | **Da, rulează** | Kernelul, firmware-ul, procedura de flash |

### 2.1 SteamOS

- Singura versiune ARM oficială e cea de pe **Steam Frame** (lansat 2026-09-18, Snapdragon
  8 Gen 3). Valve nu publică o imagine ARM generică.
- SteamOS-ARM-Handhelds (2.5) repachetează exact imaginea Frame pentru alte console.

### 2.2 Bazzite

- Imagini doar pentru x86_64. Nu are variantă ARM și nu e anunțată una. Iese din discuție.

### 2.3 Armada OS (github.com/armada-os/armada)

- Fedora bootc (sistem de fișiere imutabil, actualizat ca imagine), cu suport de dispozitive
  preluat din ROCKNIX. Kernel 7.2.6. SM8250 testat pe Retroid Pocket 5 / Flip 2.
- Stack: Steam ARM64 (canalul `steamdeck_publicbeta_linuxarm64`), FEX 2609 cu un rootfs Arch
  x86 montat la `/usr/share/guestos/fex-mesa` (locul unde îl caută instrumentul FEX al
  Steam-ului), proton-cachyos 11.0 arm64, Turnip cu patch-uri, gamescope + gamescope-session,
  steamos-manager (cel de pe Steam Frame), inputplumber, Decky cu plugin propriu.
- **Instalarea cere scrierea ROCKNIX ABL în partiția `abl`.** Pe OnePlus 8 bootloader-ul e
  semnat și verificat de cip (`secure: yes` în getvar): un ABL nesemnat nu pornește, telefonul
  ajunge doar în EDL, reparabil numai cu MSM. **Nu se face.**
- Kernelul conține patch-ul `0011-qcom-pm8150b-charger` (issue-urile #534 și #550 încă deschise)
  și overclock-ul de GPU (3.2).

### 2.4 pocknix-os (github.com/shuuri-labs/pocknix-os)

- Arch Linux ARM, actualizări prin `pacman` (inclusiv kernelul), Steam în gamescope + Plasma
  Mobile ca desktop. Suportă oficial Retroid Pocket 5 și Flip 2 (SM8250).
- Descarcă automat Proton 11 ARM64 al lui Valve. **Pe SM8250 înlocuiește DXVK 3 cu DXVK 2.7**
  (pachetul `pocknix-dxvk2-donor`), pentru că DXVK 3 cere o funcție de GPU pe care Adreno 650 nu
  o are (3.4).
- "SM8250 se poate porni fără ROCKNIX ABL" se referă la meniul bootloader-ului **Retroid**
  (Volume - la pornire, boot de pe card SD). OnePlus 8 nu are nici card SD, nici meniul ăsta.
- Kernelul (snapshot ROCKNIX din 2026-07-15) conține driverul de încărcare cu bug și
  overclock-ul de GPU (3.1, 3.2). Implicit are și parolă publică (`pocknix`).

### 2.5 SteamOS-ARM-Handhelds (github.com/hashtagbasit/SteamOS-ARM-Handhelds)

- Port neoficial al imaginii SteamOS de pe Steam Frame. Stabil pe SM8650, beta pe SM8550 și
  SM8750. **Nu are SM8250.** Kernel de la ROCKNIX.
- **Cel mai relevant pentru noi: portul pentru REDMAGIC 6** (telefon, SM8350). Acolo nu există
  ROCKNIX ABL: pornește din bootloader-ul Nubia deblocat, cu kernelul în `boot`, iar rootfs-ul
  SteamOS e scris în `userdata`. Exact modelul pe care l-am folosi și noi.
- Rootfs-ul Frame rulează pe Cortex-X1/A78 (ARMv8.2), aceeași generație de instrucțiuni ca
  Cortex-A77 din telefonul nostru. Deci nu e compilat doar pentru procesoare noi.
- Minusuri pentru noi: imaginea Valve e reglată pentru Adreno 750, nu are dispozitivul nostru,
  actualizările vin ca imagine întreagă, iar redistribuirea imaginii Valve e o zonă gri.

---

## 3. Ce e periculos în kernelurile lor

### 3.1 Driverul de încărcare cu tensiunea greșită (confirmat în cod)

Patch-ul `0011-qcom-pm8150b-charger.patch` din pocknix (și același patch în Armada) calculează
registrul de tensiune maximă cu formula de la alt cip (PMI8998):

```
(voltage_max_design_uv - 3487500) / 7500 + 1
```

Pe PM8150B registrul înseamnă 3.6 V + n × 10 mV. Pentru o baterie de 4.435 V rezultă n = 127,
adică **~4.87 V**. Plus watchdog-ul "mângâiat" la o adresă fără bază (`0x643`) și curentul de
încărcare niciodată setat. ROCKNIX a reparat driverul pe 2026-09-29, dar Armada și pocknix au
snapshot-uri mai vechi. Kernelul nostru nu are deloc driverul (plafonul de 4.37 V îl pune
bootloader-ul la fiecare pornire, verificat pe hardware, `hardware-safety.md` 4.1).

### 3.2 Overclock de GPU la 925 MHz

`9998-gpu-tuning.patch` există identic în ROCKNIX, Armada și pocknix. Adaugă trepte de GPU
până la 925 MHz pe toate dispozitivele SM8250, la nivelul de tensiune `TURBO_L1`. Snapdragon
865 (al nostru, nu 865+) are maximum 587 MHz la OnePlus, deci e **cu ~58% peste specificație**.
Pe console cu ventilator (RP5, AYN Thor Lite) căldura se evacuează; OnePlus 8 se răcește pasiv.
Rezultatul probabil e căldură în plus, throttling și posibil instabilitate. **Nu îl preluăm.**
Kernelul nostru rămâne la 587 MHz (verificat, `hardware-safety.md` 4.9).

### 3.3 ROCKNIX ABL

Recomandat de pocknix, obligatoriu pentru Armada. Pe OnePlus 8 = telefon care nu mai pornește
decât în EDL. Regula există deja (`hardware-safety.md` 3.4), o repet aici pentru că ambele
README-uri îl prezintă ca pas normal.

### 3.4 Ce e doar inutil pentru noi

Patch-urile pentru ventilator (`9997-set-boot-fanspeed`), controlerele Retroid, panourile lor
de ecran: nu se aplică pe OP8, dar nici nu ar strica ceva dacă DTS-ul nostru nu le folosește.

---

## 4. Ce știm că merge pe SM8250 (și deci, probabil, și pe noi)

- **Steam ARM64 + Proton ARM64 + FEX rulează pe Retroid Pocket 5** (Armada și pocknix îl
  suportă oficial). E primul răspuns concret la riscul din `verification-log.md` 7.6.4: FEX-ul
  actual merge pe ARMv8.2. Issue-ul FEX #4120 (ridicarea cerinței la ARMv8.4) rămâne deschis;
  dacă se aplică, fixăm o versiune FEX mai veche (autorul a confirmat că rămân disponibile).
- **Flag-urile CPU ale telefonului** (citite din `/proc/cpuinfo`): `atomics` (LSE) și `lrcpc`
  prezente, `lse2` și `flagm` absente. Exact profilul ARMv8.2 al RP5.
- **DXVK 3 nu merge pe Adreno 650.** DXVK 3 cere `storageBuffer8BitAccess`; în Mesa
  (`freedreno_devices.py`) Turnip activează `storage_8bit` doar pentru familia a7xx. Adreno 650
  e a6xx. Soluția pocknix: DXVK 2.7.1 din Proton 11 pus în locul lui DXVK 3.
- **Clientul Steam ARM64 e compilat pentru glibc.** Pe postmarketOS (musl) nu rulează direct,
  doar într-un container glibc (ghidurile pmOS din `verification-log.md` 7.6.3) sau pe un
  rootfs glibc.

---

## 5. Constrângerile OnePlus 8 (citite de pe telefon azi)

| Ce | Valoare | Ce înseamnă |
|---|---|---|
| Pornire | ABL stock semnat, `boot.img` Android v2 în `boot_b` | Orice sistem trebuie să pornească prin `boot.img`, ca acum |
| RAM | 12 GB (11617 MB) + zram 17 GB | Peste cei 8 GB la care ghidul pmOS raporta OOM |
| `super` | 14 GiB, rootfs-ul pmOS are 13.1 GiB, **11.8 GiB liberi** | Ajunge pentru Steam + FEX + Proton + un joc mic de test |
| `userdata` | 219 GiB | Locul pentru jocuri, vezi decizia de mai jos |
| CPU | Cortex-A77/A55, ARMv8.2 | Ca RP5 |
| GPU | Adreno 650, maxim 587 MHz | DXVK 2.7, nu 3 |
| Kernel | 6.16.7 (Xo666, r5) | `UCLAMP_TASK`, `BPF_SYSCALL`, `UHID`, `JOYSTICK_XPAD`, `HID_PLAYSTATION` prezente; **lipsesc `NTSYNC`, `EROFS_FS` și `sched_ext`** |
| Pachete pe telefon | `gamescope` 3.16.29, `mesa-vulkan-freedreno` 26.2.3 | Disponibile în Alpine edge |

Explicații: *NTSYNC* = mecanism de sincronizare din kernel pe care Proton îl folosește pentru
performanță (fără el merge, dar mai încet). *sched_ext* = planificatoare de CPU încărcabile, de
exemplu `scx_lavd` pe care îl folosește pocknix. Toate trei se pot adăuga într-un kernel r6.

**Decizie de luat înainte de etapa B: `userdata`.** Android e deja șters (`super` a fost
rescris cu pmOS), dar datele vechi din `userdata` sunt încă acolo, criptate de Android.
Probabil se pot recupera doar restaurând Android din backup și deblocând cu PIN-ul vechi.
Formatarea `userdata` pentru jocuri le șterge definitiv. Dacă ai acolo ceva de care ai nevoie,
îl scoatem întâi.

**Controlerul GameSir X3 Pro** ocupă portul USB-C, deci cât e conectat nu mai avem SSH prin
cablu (iar pe WiFi l-am blocat intenționat, `security-audit.md` S2). Pentru teste: un controler
Bluetooth, sau o excepție temporară de firewall doar pentru IP-ul PC-ului. Alimentarea
controlerului de către telefon (modul OTG) nu e încă verificată (`hardware-safety.md` 4.11).

---

## 6. Recomandarea: kernelul nostru + userspace după rețeta pocknix/Armada

### Etapa A: test fără niciun flash (în postmarketOS-ul actual)

Scop: să aflăm dacă GPU-ul, gamescope și Steam ARM64 merg pe telefonul ăsta, înainte să
schimbăm orice partiție. Nu scrie nimic în afara rootfs-ului deja instalat.

1. Vulkan nativ: `vulkaninfo --summary` și un test simplu (`vkcube`) pe Turnip.
2. gamescope pe ecranul telefonului (pachetul Alpine), cu o aplicație de test.
3. Un container glibc (distrobox cu Arch Linux ARM) cu Steam ARM64, FEX și Proton ARM64,
   copiind configurația Armada (rootfs-ul FEX la `/usr/share/guestos/fex-mesa`) și DXVK 2.7 de
   la pocknix.
4. Un joc mic: întâi unul Linux ARM nativ, apoi unul Windows prin Proton.
5. Temperaturile logate tot timpul (pragurile din `hardware-safety.md` 4.8), difuzoarele cu
   volum mic (încă nu avem limitator).

Risc: zero pentru hardware și pentru partiții. Dacă ceva nu merge, ștergem containerul.

### Etapa B: rootfs Arch Linux ARM nativ (scrie pe telefon, doar cu OK explicit)

Dacă etapa A merge, scoatem stratul de container:

- Rootfs Arch Linux ARM cu userspace-ul pocknix (pachete `pacman` pentru aarch64) sau refăcut
  după rețeta Armada. **Fără kernelul lor**: `IgnorePkg` pe pachetele de kernel și firmware.
- Kernelul nostru, cu un initramfs care montează rootfs-ul din `super` sau `userdata`. Flash
  doar în `boot_b` (și partiția aleasă pentru rootfs), ca până acum. Drumul înapoi la stock
  nu se schimbă (backup + MSM, `hardware-safety.md` 3.6).
- Kernel r6: `NTSYNC`, `EROFS_FS`, eventual `sched_ext`, plus opțiunile de securitate din
  `security-audit.md` S3. Mai târziu, mutarea DTS-ului și a celor două patch-uri pe 7.2,
  **fără** driverul de încărcare (până la versiunea reparată de ROCKNIX, verificată de noi) și
  **fără** overclock-ul de GPU.

### De ce nu celelalte variante

- **pmOS + container ca soluție finală:** merge (ghidurile pmOS), dar e un strat în plus:
  Steam își pornește propriul container în containerul distrobox, iar ghidul raportează
  blocări ale `steamwebhelper`. Bun pentru test (etapa A), incomod pentru zi de zi.
- **SteamOS ARM (imaginea Frame) prin metoda REDMAGIC 6:** cea mai apropiată de un SteamOS
  real, dar nu e făcută pentru Adreno 650, nimeni nu a rulat-o pe SM8250 și se actualizează
  ca imagine întreagă. Rămâne un experiment posibil după etapa B, nu punctul de plecare.
- **Armada / pocknix ca imagini:** nu pornesc pe OP8 fără ABL nesemnat (3.3).

---

## 7. Reguli noi (se adaugă la lista din `hardware-safety.md` 3.4)

- Nu instalăm imaginile Armada, pocknix sau SteamOS-ARM-Handhelds ca atare.
- Nu folosim kernelurile lor pe OnePlus 8 (încărcare la ~4.87 V, GPU la 925 MHz).
- Nu preluăm `9998-gpu-tuning.patch` și nici alt tabel de frecvențe GPU peste 587 MHz.
- Nu formatăm `userdata` fără decizia explicită din secțiunea 5.

## 8. Ce rămâne neverificat

- Steam ARM64 + FEX + Proton pe telefonul nostru (dovedit doar pe RP5, același SoC).
- Performanța reală în jocuri și comportamentul termic sub joc susținut.
- Alimentarea controlerului GameSir X3 Pro prin USB-C (OTG).
- Dacă userspace-ul pocknix se poate folosi fără pachetele lor de kernel și dispozitiv
  (`pocknix-device-sm8250` depinde de ele).

## 9. Etapa A pe telefon: ce merge și TODO (2026-10-01)

Tot ce urmează s-a făcut fără niciun flash, doar în rootfs-ul pmOS și în `/home/gabriel`.

### Ce merge

- **GPU:** Turnip Adreno 650, Vulkan 1.3, Mesa 26.2.3, atât pe gazdă cât și în container.
  Confirmat pe hardware: `storageBuffer8BitAccess = false`, deci DXVK 2.7, nu 3.
- **gamescope** (Alpine 3.16.29) direct pe ecran: 1080x2400 la 90 Hz, rotit `right` (corect
  față de controlerul GameSir X3 Pro), touchscreen-ul asociat automat.
- **Container:** distrobox cu Fedora 44 (imaginea oficială), podman fără root, glibc 2.43.
- **Steam ARM64** (canalul `steamdeck_publicbeta`, runtime `steamrt3c` 20260824): descărcat
  direct de la Valve cu sumele de control verificate, auto-actualizat, login făcut, interfața
  Deck rulează pe ecranul telefonului.
- **USB OTG:** telefonul trece singur în modul host și alimentează accesoriul. GameSir X3 Pro
  apare în kernel (`3537:0106`, "Zikway GameSir-X3 Pro", `hid-generic`), un mouse USB merge.
- **Primul joc Windows (2026-10-01 23:15):** Tiny Rails (Unity, AppID 614630) pornit din Steam
  prin Proton 11.0 (ARM64), Wine ARM64 + FEX, în runtime-ul Steam Linux Runtime 4 (arm64).
  Utilizatorul: "mergea chiar ok". De verificat ce randare a folosit (DXVK 2/3 sau wined3d).
- **Biblioteca Steam** e pe `userdata` (ext4 `op8games`, 215 GB, `/home/gabriel/games`), montată
  prin bind în `~/.local/share/Steam/steamapps`; rootfs-ul rămâne pentru sistem.

### Capcane rezolvate (de reținut pentru etapa B)

- Lui Fedora îi lipseau pentru Steam: `at-spi2-atk`, `NetworkManager-libnm`. Steam își aduce
  FFmpeg-ul, dar îl caută ca `libavcodec.so.61` / `libavutil.so.59`, iar `libbz2` ca `.so.1.0`:
  legături simbolice în `~/.local/share/Steam/lib/aarch64-linux-gnu/`.
- pmOS are `KillUserProcesses=true`: la ieșirea din SSH se închide tot. Soluția: `loginctl
  enable-linger` și pornirea ca serviciu al userului (`systemd-run --user --unit=steam-gs`).
- Fără sesiune logată pe ecran, gamescope pornește cu `LIBSEAT_BACKEND=noop` și userul în
  grupul `input`.
- În container nu există `/run/dbus`; magistrala gazdei e la
  `/run/host/run/dbus/system_bus_socket` (`DBUS_SYSTEM_BUS_ADDRESS`).
- Cu `-steamos3`, Steam cheamă `steamos-update`, `steamos-select-branch` și
  `/usr/bin/steamos-polkit-helpers/jupiter-*`: shim-uri după pocknix.
- La repornire se așteaptă oprirea completă a containerului, altfel podman eșuează la
  `/etc/passwd` din overlay.

### Incident: resetare în timpul descărcării unui joc (2026-10-01 ~21:43)

Telefonul s-a resetat singur în timp ce Steam descărca Tiny Rails, în același moment în care
rula `stageA2.sh` (reguli udev + `udevadm trigger` + repornirea nftables).

- **Registrele PON ale PM8150** (PMIC gen2, subtip `0x04`, motivele la `0x08C0`-`0x08CB`, nu la
  `0x0808`-`0x080D` ca la gen1): `WARM_RESET_REASON1 = 0x02` (PS_HOLD), `OFF_REASON = 0x80`
  (secvență normală, nu de eroare), `POFF_REASON1 = 0x02` și `PON_REASON1 = 0x40` (CBL) rămase
  de la oprirea și pornirea de dinainte. `FAULT_REASON1 = 0x40` (UVLO) e vechi: ultima
  secvență nu e de eroare.
- **Concluzie:** reset "warm" cerut de SoC (kernel panic cu `kernel.panic=120` sau watchdog
  hardware după o blocare). **Nicio protecție electrică a PMIC-ului nu s-a declanșat.**
  Registrele de încărcare au rămas 4.37 V / 2.0 A / 1.6 A, temperaturile 38-40 °C.
- **`ramoops` nu ajută:** `/sys/fs/pstore` e gol după reset, nici măcar `console-ramoops`, deci
  bootloader-ul OnePlus nu păstrează zona de memorie. Jurnalul systemd pierde ultimul minut
  (scriere pe disc la 5 minute).
- Cel mai probabil vinovat: WiFi (ath11k + `amss.bin` neverificat) sub trafic mare. De
  reprodus cu jurnalul kernelului transmis live pe PC.
- **Cauza reală, găsită pe 2026-10-02 (TODO 2):** nu WiFi și nu discul, ci o zonă de memorie
  rezervată lipsă din device tree (`removed_mem`). Rezolvat cu patch-ul de kernel `0003`.

### TODO

1. ~~Touch ca pe Steam Deck~~ **rezolvat 2026-10-02**: Steam comută modul touch al gamescope
   (`STEAM_TOUCH_CLICK_MODE`) doar din Steam Input, adică doar cu un controler conectat.
   `op8-touchmode` urmărește `GAMESCOPE_FOCUSED_APP`: interfața Steam (769) = 4 (touch real,
   glisare = scroll), jocurile = 1 (click). Gamescope pornește cu `--default-touch-mode 4`.
2. ~~Resetările din timpul descărcărilor~~ **rezolvat 2026-10-02**: o zonă de memorie
   rezervată lipsea din device tree. Toate reseturile erau reset "warm" prin PS_HOLD, instant,
   fără niciun mesaj în kernel (nici în jurnalul brut `/dev/kmsg` trimis live pe PC).
   - **Cauza:** device tree-ul Xo666 șterge `removed_mem` (0x80b00000) din `sm8250.dtsi` și
     mută zonele firmware-ului mai sus, la 0x8dc00000, dar nu mai adaugă `removed_mem` înapoi.
     Bootloader-ul declară RAM 0x80000000-0xb98fffff, deci Linux folosea ~210 MB din memoria
     lumii sigure (TrustZone/hypervisor) ca RAM obișnuit. Paginile sunt în `ZONE_DMA32`, folosită
     doar după ce zonele de sus se umplu, de aceea resetul apărea doar cu RAM-ul plin: la
     descărcări mari, cache-ul de fișiere umple memoria.
   - **Dovada:** `stress-ng --vm 4 --vm-bytes 8000M` (fără disc) a resetat în 5 s, iar 2000M a
     trecut. Testele de disc care resetau (H3, H8, H9: 8 × 1,5 GB în lucru) depășeau RAM-ul
     liber, iar cele care treceau (H1, H6 cu zerouri, H2, H7b) rămâneau sub ~4 GB.
     Diferența aparentă dintre zerouri și date reale venea din mărimea fișierelor, nu din conținut.
   - **Reparația:** patch-ul `pmaports/linux-oneplus-instantnoodle/0003` (pkgrel 6) readaugă
     `removed_mem` cu 0xcd00000, ca în device tree-urile WuerfelDev și ObiKeahloa pentru OnePlus 8.
     Acoperă și valorile OnePlus (0xAF00000 în Android 11, 0x5300000 în LineageOS 23.2 și în
     `sm8250.dtsi`). Cu el, RAM2 (2 minute cu 150-350 MB liberi, `--verify` curat) și H9
     (72 GB scriși în 3 minute, 404 MB/s în medie) au trecut fără reset.
   - **Testat pe telefon** cu DTB-ul imaginii actuale plus nodul nou (`fdtput`, singura
     diferență), scris în `boot_b`. DTB-ul compilat din sursă cu 0002 + 0003 e identic cu cel
     testat. Pachetul r6 încă nu e construit cu pmbootstrap.
   - **Excluse pe drum** (fiecare cu reset reprodus): power management-ul UFS (`ufs-nopm.sh`),
     coada UFS redusă la o comandă, cablul USB și încărcarea (test pe baterie, prin WiFi),
     tensiunea S8C ridicată la 1,352 V, ca în Android (test cu imaginea în `boot_b`, apoi revenire).
     VCC-ul UFS (2,504 V) e identic cu Android pentru UFS 3.0.
3. ~~Controlerele în Steam~~ **merg**: GameSir X3 Pro și Xbox pe fir, cu regulile udev pentru
   `hidraw`/`uinput`. Conectarea la cald prin `SDL_JOYSTICK_DISABLE_UDEV=1` (evenimentele udev
   nu ajung în containerul fără root). Maparea X3 Pro (`3537:0106`, lipsă din baza SDL) s-a
   făcut din Steam.
4. **Controlere Bluetooth (de testat):** `bluez` instalat și pornit. DualSense
   (`HID_PLAYSTATION`), Xbox Series X prin Bluetooth LE (`HID_MICROSOFT` + `UHID`; în 6.16
   `CONFIG_BT_LE` adaugă doar audio LE, conexiunile LE merg și fără), DualShock 4 (`HID_SONY`).
5. ~~Audio~~ **merge 2026-10-02**, cu plafon. Cauze: lipsea legătura UCM
   `conf.d/sm8250/OnePlus8.conf` (reparat și în pachet), iar amplificatoarele TFA9874 tac dacă
   PCM-ul e deschis S24_LE sau cu mmap (PipeWire forțat pe S16LE, fără mmap). Ieșirea implicită
   "Difuzoare (protejat)" (trece-sus 250 Hz + clamp) trimite în ieșirea directă, al cărei volum
   e plafonul: -30 dB. Butoanele de volum: `op8-buttons.py`. Vezi `userspace/README.md`.
6. **DXVK 2.7** în locul lui DXVK 3 pentru Proton ARM64, după metoda pocknix. (Jocurile testate
   până acum, Unity și 2D, au mers și fără.)
7. ~~Spațiu~~ **rezolvat**: `userdata` formatat ext4 (`op8games`, 215 GB, cu acordul
   utilizatorului), biblioteca Steam montată de acolo.
8. **FEX pentru jocuri Linux x86:** rootfs-ul la `/usr/share/guestos/fex-mesa` (ca la Armada).
   De verificat dacă pe SM8250 (fără LSE2) e nevoie de patch-ul de kernel pentru atomice
   nealiniate pe care îl au pocknix și Armada (`0504` + `1062`).
9. **Performanță și prevenirea crash-urilor:** vezi `performance-crash-audit.md`.
10. **Steam în limba engleză** din registry-ul inițial; se poate schimba din setări.
11. **Remote Play (streaming de pe PC) nu merge.** Clientul `streaming_client` crapă imediat.
    Cu decodorul Venus vizibil (`/dev/video14`), crapă în calea V4L2 (`CV4L2Accel::
    ProcessCompletedOutputBuffers`, scrisă pentru decodorul de pe Steam Frame). Fără Venus, n-are
    decodor deloc: `streamclient.cpp (699) : m_pVideoDecoder`, apoi SIGSEGV la adresa 0x18 (nu
    există decodare software ca rezervă). Încercat și cu `STEAM_GAMESCOPE_HDR_SUPPORTED=0`: tot crapă.
    De încercat: formatul cerut de Steam de la V4L2 față de ce oferă Venus pe SM8250 (NV12 vs
    QC08C/UBWC), H.264 forțat pe PC, un decodor V4L2 stateless. Analizor: `op8-minidump.py`.
12. **Jocurile Linux native (x86)** se închid în sub o secundă (Half-Life, Hue, LIMBO, Terraria):
    Steam le mapează pe unealta `native`. Ocolire: Proton 11.0 (ARM64) forțat din Properties >
    Compatibility (versiunea Windows). Soluția completă: FEX + rootfs la
    `/usr/share/guestos/fex-mesa` (punctul 8).
13. **Muffin Knight:** mici probleme de afișare la text (Proton ARM64).
14. **Full screen (benzi negre pe laterale):** panoul DSI n-are EDID, iar gamescope-ul din Alpine
    nu generează unul. Steam nu vede rezoluția reală (2400x1080) și alege 1920x1080
    (`systemdisplaymanager.txt`: "screen resolution: 1920x1080"; în logul gamescope Xwayland trece
    de la 2400x1080 la 1920x1080 imediat după pornirea Steam). `GAMESCOPE_DISPLAY_EDID_PATH` e doar
    atomul prin care gamescope îi dă lui Steam EDID-ul (scris în `GAMESCOPE_PATCHED_EDID_FILE`,
    cu rotația aplicată), nu o cale de a încărca un EDID. Variante:
    - **B (de încercat întâi):** EDID 1080x2400 (portret) cu timing-urile exacte ale panoului,
      din sursa kernelului Xo666 (driverul panoului `samsung,amb655uv01`), injectat prin debugfs
      `edid_override` pe DSI-1 la pornire, înaintea gamescope. Atenție: modurile din EDID înlocuiesc
      lista panoului; un timing greșit = ecran negru până la repornire. Test manual, apoi permanent.
    - **A:** gamescope recompilat cu patch-ul Armada
      `packages/gamescope/patches/0002-drm-synthesize-edid-for-edidless-internal-panels.patch`
      (+ `0003` pentru profile de display), adaptat la 3.16.29, construit cu pmbootstrap.
    - **C:** `-S fill` / `-S stretch` în gamescope (imagine tăiată sau deformată).
    Referință pentru panouri de telefon 2400x1080: profilul `redmagic6.amoled.lua` din
    SteamOS-ARM-Handhelds (rate dinamice 60/90/120/144 pe un panou fără EDID).
    **Încercat pe 2026-10-02:**
    - **B nu poate merge pe acest panou:** în kernelurile 6.x, `edid_override` se folosește
      doar pe calea de citire a EDID-ului sau dacă driverul nu dă niciun mod; driverul
      `panel-samsung-amb655uv01` dă direct două moduri, deci override-ul e ignorat (conectorul
      rămâne cu EDID 0 octeți).
    - **EDID pentru Steam fără recompilare:** gamescope îi dă lui Steam EDID-ul doar prin
      `GAMESCOPE_PATCHED_EDID_FILE` (lipsea), iar fără EDID de la panou scrie acolo un fișier
      gol. `steam-gamescope.sh` pune acum EDID-ul panoului rotit în landscape
      (`userspace/system/make_edid.py`, 2400x1080 la 90 și 60 Hz, verificat cu `edid-decode`)
      și face din `<cale>.tmp` un director, ca scrierea lui gamescope să eșueze. Merge
      (`GAMESCOPE_DISPLAY_EDID_PATH` arată spre fișierul nostru), dar **nu schimbă nimic**:
      la ecran intern Steam nu citește modurile din EDID (`OnScreenChanged: ... external: 0
      modes: 0`).
    - **Cauza reală:** Steam își pune singur interfața la 1920x1080 (`GAMESCOPE_XWAYLAND_MODE_
      CONTROL`), iar rezoluția „nativă” a jocurilor e cea a interfeței („Using maximum game
      resolution: screen resolution: 1920x1080”). O cerere de 2400x1080 trimisă de noi e
      anulată imediat de Steam. Steam primește de la gamescope dimensiunea fizică a panoului
      **nerotită** (70 x 151 mm pentru o imagine 2400x1080; `wl_output` geometry) și calculează
      o scară absurdă (`UIScaleFromDimensions: 1920 x 1080 : 268mm x 39mm`).
      `GAMESCOPE_FAKE_OUTPUT_MM` nu are efect pe backend-ul DRM în 3.16.29.
    - **Setarea Steam Settings > Display > Scaling:** lista nu are 2400x1080 (are 2040x1080,
      2560x1080); 2560x1080 nu umple ecranul.
    - **Următorul pas:** dimensiunea fizică rotită: patch gamescope (schimbarea între ele a
      `phys_width`/`phys_height` când imaginea e rotită, în `DRMBackend.cpp`, lângă
      `wlserver_set_output_info`) sau, mai simplu, `.width_mm = 151, .height_mm = 70` în
      driverul panoului (kernel r6). Apoi de văzut dacă Steam alege singur 2400x1080; dacă
      nu, patch-ul Armada 0002/0003 (EDID sintetic în gamescope).
15. ~~Ieșire din joc fără controler~~ **rezolvat 2026-10-02**: Volume Up + Volume Down apăsate
    deodată deschid meniul Steam, și în jocuri (vezi mai jos, `op8-buttons.py`).
16. **Sunetul lipsește uneori după pornire:** când DSP-ul audio răspunde cu eroare la pornire
    (`qcom-q6afe ... AFE failed to vote (3)`, uneori și `va_macro ... failed with error -110`),
    placa de sunet nu apare. 5 din 17 porniri pe 2026-10-02, cu imagini diferite, deci nu ține
    de vreo modificare anume. O repornire o rezolvă. De încercat: un serviciu care, dacă
    lipsește `/proc/asound/cards`, reîncarcă driverele audio (`unbind`/`bind`) sau repornește
    DSP-ul (`remoteproc`).
17. **Încărcare prin controler (passthrough, GameSir X3 Pro):** telefonul trebuie să fie gazdă
    USB pentru controler și în același timp să primească curent prin el. De testat cu stiva
    Type-C/PD din kernel (`tcpm`, raportează `PD PD_PPS`). Fără driver de încărcare, PMIC-ul
    încarcă cu limitele lui hardware (verificate: 4,37 V, 2 A). Bateria e uzată (gauge-ul
    estimează 1,9-3,1 Ah din 4,27 Ah), iar o baterie nouă nu e în plan.
    **Încărcătoare USB-C PD (ex. Samsung 45 W): de nefolosit deocamdată.** Conectorul din
    device tree-ul Xo666 declară `sink-pdos` cu `PDO_VAR(5000, 12000, 5000)`, deci telefonul ar
    cere unui încărcător PD 9 V. Pe Android, OnePlus 8 nu folosea PD peste 5 V (încărcarea
    rapidă e Warp, 5 V / 6 A), deci 9 V pe VBUS e netestat pe placa asta. De făcut întâi: patch
    de device tree cu `sink-pdos = <PDO_FIXED(5000, 3000, ...)>` (doar 5 V), apoi un test
    urmărit (`tcpm-source-psy-*/voltage_now` trebuie să arate 5 V). Sigure până atunci: portul
    USB al PC-ului sau un încărcător USB-A de 5 V.
18. **Indicatorul de volum din Steam în colțul stânga jos (opțional):** Steam nu are setare de
    poziție. Variante: Decky Loader + CSS Loader (netestat în containerul ARM) sau un indicator
    propriu într-un overlay gamescope, cu volumul schimbat printr-un etaj de filtru separat
    (atunci Steam nu-și mai arată bara).
19. ~~Protecție termică după temperatura bateriei~~ **făcut 2026-10-02**
    (`userspace/system/op8-thermal`, `install-thermal.sh`). Kernelul protejează doar procesorul
    (frânare la 90 și 95 °C, oprire la 110 °C), iar Android frânează mult mai devreme, după
    carcasă și baterie. Măsurat: Slime Rancher a dus bateria la 46,5 °C (CPU 93 °C), compilarea
    pe 8 nuclee la 46,6 °C. `op8-thermal` (serviciu de sistem, la 5 s) limitează nucleele mari,
    prime și GPU-ul pe 4 niveluri, la 41 / 42 / 43 / 44,5 °C la baterie (cu 1 °C histerezis);
    nucleele mici rămân libere, iar în standby nu atinge nimic. Telefonul n-are senzor de carcasă.
    **JEITA în PM8150B** (citit, doar citire): `0x1090 = 0x00`, deci reducerea automată a
    curentului și a tensiunii la cald e **dezactivată** (în Android o face software-ul OnePlus).
    Rămân doar pragurile hardware (`0x1094`-`0x109f`, trei perechi de coduri ADC ale
    termistorului: soft, oprirea încărcării, oprirea de urgență), netransformate în grade. Deci
    fără driver de încărcare, curentul de încărcare (2,0 A) nu scade la cald: încărcatul în timp
    ce joci încălzește bateria în plus. De urmărit: o scriere a lui `0x1090` (activare JEITA)
    ar cere scriere în registrele PMIC, nefăcută.
20. **Ecran cu zgomot colorat (o dată, cauză necunoscută):** pe 2026-10-02, în Slime Rancher,
    cu overlay-ul pornit, după o schimbare de luminozitate, tot ecranul a devenit zgomot colorat.
    A rămas și după sleep și după repornirea gamescope; a dispărut doar la repornirea telefonului
    (panoul se resetează la întreruperea alimentării). Excluse: luminozitatea singură (10 pași
    lenți, apoi 60 de valori în 2 s, din sysfs, fără zgomot), slider-ul din Steam în interfață,
    fereastra `mangoapp` (era ascunsă). Indicii: Steam pune `GAMESCOPE_DISPLAY_HDR_ENABLED=1` deși
    gamescope raportează `GAMESCOPE_DISPLAY_SUPPORTS_HDR=0`; controlerul de afișaj expune doar
    `CTM` (fără `GAMMA_LUT`), iar în starea normală `CTM` nu e setat (`drm_info`, instantaneu în
    `D:\op8-logs\drm_info-normal-*.txt`). Dacă reapare: `drm_info` înainte de repornire și
    jurnalul proprietăților de culoare (`xprop -root -spy`, filtrat pe `GAMESCOPE_*COLOR/HDR`).
    Măsură de rezervă: gamescope cu `--disable-color-management`.

Rezolvate tot pe 2026-10-02, mai târziu:

- **Spațiul din Steam** (Storage arăta 13,1 GB): Steam calculează spațiul liber pe directorul
  lui de instalare, care era pe partiția de sistem (2,9 GB liberi), nu pe `steamapps`.
  `userspace/system/move-steam-to-games.sh` mută tot directorul Steam pe partiția de jocuri și
  îl montează (bind) la aceeași cale; `steam-gs.service` așteaptă acum acel montaj.
- **Butoanele de volum** (`userspace/steam/op8-buttons.py`, în container, pornit cu sesiunea
  Steam; înlocuiește `op8-volbtn` de pe gazdă):
  - inversate: în landscape, Volume Up fizic e în stânga, iar bara din Steam crește spre dreapta;
  - volumul se schimbă la eliberare, iar la ținere, continuu, după 0,5 s. Butoanele nu trimit
    repetare automată (`EV=3`, fără `EV_REP`), deci ținerea are cronometrul ei;
  - **Volume Up + Volume Down deodată = butonul Steam**, și în jocuri: Steam înregistrează la
    gamescope Shift+Tab ca butonul Steam (`GuideKeyboardHotkey -> [Tab + Shift_L]` în jurnalul
    gamescope), iar gamescope o interceptează înaintea jocului. Se trimite de pe o tastatură
    virtuală permanentă, după eliberarea ambelor butoane: gamescope o declanșează doar dacă
    nicio altă tastă nu e apăsată, iar butoanele de volum sunt și ele tastaturi pentru el.
    Încercări abandonate: un controler Xbox virtual creat la apăsare (Steam afișa „controller
    connected”) și o tastatură creată la fiecare apăsare (gamescope nu apuca să o vadă). Două
    procese `sh`, câte unul pe buton, prindeau combinația cam o dată din trei.
- **Overlay-ul de performanță** (meniul `...` > Performance): gamescope 3.16.29 trimite către
  `mangoapp` câmpurile `app_frametime_ns` și `visible_frametime_ns` în ordine inversă față de
  orice MangoHud (0.7.1 din Alpine, 0.8.4, `master`). `mangoapp` citește atunci mereu „necunoscut”
  ca timp de cadru vizibil, nu iese din pauză și nu apare în jocurile Steam/Proton
  ([gamescope #2430](https://github.com/ValveSoftware/gamescope/issues/2430), aceleași simptome).
  `userspace/steam/build-mangoapp-gs.sh` compilează MangoHud 0.8.4 cu ordinea din gamescope, în
  container (`ipc=host`, deci vede coada de mesaje a lui gamescope); `op8-mangoapp` îl pornește cu
  sesiunea, iar gamescope nu mai primește `--mangoapp`. Steam scrie nivelul în
  `/run/user/10000/mangohud.conf`. Când gamescope revine la ordinea veche, patch-ul trebuie scos.
- **Primul joc 3D:** Slime Rancher (Unity, Proton 11 ARM64) merge, pornit în modul „safe”
  (`-lowGraphics`); fără el se închidea uneori la încărcare.
- **Indicatorul de încărcare care apare și dispare:** de la portul USB al PC-ului telefonul
  primește ~2,5 W (Type-C fără PD). Sub sarcină consumă mai mult, iar starea bateriei trece între
  „Charging” și „Discharging”. Cu un încărcător de priză nu apare.

Rezolvate între timp: SSH pe WiFi doar de la PC (`40_ssh_usb_only.nft`, IP-ul PC-ului),
profilul WiFi dezlegat de adresa MAC (după reset cipul QCA6390 a raportat alt MAC), jurnalul
`op8-log` (raport la pornire, eșantioane la 2 s, `journald` la 2 s, `op8-live.sh` pe PC).

Rezolvate pe 2026-10-02 (scripturile în [`../userspace/`](../userspace/README.md)):

- **Slotul de boot devenise nebootabil** ("the current image (boot/recovery) have been
  destroyed"): bootloader-ul scade contorul de încercări la fiecare pornire, iar nimeni nu
  marca slotul b ca "successful". Reparat cu `fastboot --set-active=b` (din fastboot, intrat cu
  telefonul oprit **fără cablu**: Volume Up + Volume Down + Power), apoi `qbootctl` +
  `qbootctl-systemd` (`qbootctl -m` la fiecare pornire). Pachetul de device depinde acum de
  `qbootctl`. Schimbarea numelui dispozitivului din Steam nu a avut legătură.
- **Sleep** (meniul Steam și butonul de pornire): Steam suspendă cu `dbus-send ... login1
  Suspend`, dar în container nu exista `dbus-send`, polkit cerea parolă ("challenge"), iar
  sesiunile SSH țin `inhibit=sleep` (`/etc/pam.d/sshd`). Acum: regulă polkit, adaptor
  `dbus-send` (`SuspendWithFlags` cu ignorarea blocajelor), `systemd-suspend.service` rulează
  `op8-standby` (fără suspendarea kernelului) și `op8-powerbtn` (scurt = sleep, lung = meniu).
  Restart și oprirea din meniul Steam trec prin același adaptor.
- **Luminozitatea din Steam**: fișierul `brightness` scriibil de grupul `video` (udev) +
  helper `steamos-priv-write` în container.
- **Sesiunea Steam** repornește singură (`Restart=always`) și așteaptă oprirea containerului.

## Surse

- Armada OS: https://github.com/armada-os/armada (`packages/kernel/patches/9998-sm8250-gpu-tuning.patch`,
  `packages/steamos-manager/devices/sm8250.toml`, issue-urile #534 și #550)
- pocknix-os: https://github.com/shuuri-labs/pocknix-os (`README.md`, `kernel/README.md`,
  `kernel/sm8250/patches/20-sm8250/0011-qcom-pm8150b-charger.patch` linia 2298,
  `9998-gpu-tuning.patch`, `packages/soc/pocknix-dxvk2-donor/PKGBUILD`)
- SteamOS-ARM-Handhelds: https://github.com/hashtagbasit/SteamOS-ARM-Handhelds
  (`docs/redmagic6.md`, `docs/HOW-IT-WORKS.md`, `LICENSE`)
- ROCKNIX: https://github.com/ROCKNIX/distribution (`projects/ROCKNIX/devices/SM8250/patches/linux/9998-gpu-tuning.patch`,
  PR-urile #3371 și #3382 pentru driverul de încărcare)
- Mesa: `src/freedreno/common/freedreno_devices.py` (`storage_8bit = True` doar în `a7xx_base`)
- FEX: https://github.com/FEX-Emu/FEX/issues/4120
- Telefonul (read-only, 2026-10-01): `/proc/cpuinfo`, `free`, `df`, partițiile din
  `/sys/class/block`, `/proc/config.gz`, `apk policy`
