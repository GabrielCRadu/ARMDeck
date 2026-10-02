# Audit de compatibilitate și performanță (2026-10-02)

Făcut după ce telefonul a devenit stabil (reseturile rezolvate, full screen, overlay). Toate datele
sunt citite de pe telefon, doar citire: configurația kernelului, `sysfs`, `/proc`, `vulkaninfo`,
`glxinfo`, fișierele Steam și Proton din container. Datele brute: `D:\op8-logs\audit\`. Completează
[`performance-crash-audit.md`](performance-crash-audit.md) (2026-10-01), ale cărui puncte rămase
deschise sunt reluate aici.

Termeni folosiți:
- *Proton* = varianta Valve de Wine, care rulează jocurile Windows. Pe ARM64 traduce codul x86 cu
  FEX.
- *FEX* = emulatorul care rulează cod x86 pe procesorul ARM. *TSO* = ordinea strictă a accesului
  la memorie de pe x86, pe care FEX trebuie să o imite; e cel mai mare cost al emulării.
- *DXVK* = traduce Direct3D 9/10/11 în Vulkan. *VKD3D-Proton* = la fel pentru Direct3D 12.
- *Turnip* = driverul Vulkan din Mesa pentru GPU-ul Adreno. *freedreno* = driverul OpenGL.
- *NTSYNC* = driver de kernel care face sincronizarea firelor de execuție Windows direct în
  kernel; Proton îl folosește singur dacă există `/dev/ntsync`.
- *PSI* = măsura kernelului pentru cât timp așteaptă procesele după procesor, memorie sau disc.
- *EAS* = planificatorul care ține sarcinile mici pe nucleele mici, pentru baterie.

## 1. Pe scurt: ce merită făcut, în ordine

| # | Ce | Câștig | Efort | Cere |
|---|---|---|---|---|
| 1 | **Proton 11.0 (ARM64) ca implicit**, niciodată Proton Experimental (ARM64) pentru D3D9/10/11 | jocurile D3D nu mai pică la pornire | 1 minut | setare în Steam |
| 2 | `CAP_SYS_NICE` pe `~/bin/gamescope-op8` | compozitorul înapoi la prioritate mare (mai puțin sacadat) | 1 comandă | sudo |
| 3 | **NTSYNC** în kernelul r7 + regulă udev | jocuri Windows limitate de procesor mai rapide | în r7 | flash |
| 4 | **Rootfs `fex-mesa`** în container | jocurile Linux x86 native (Half-Life, Terraria, Hue, LIMBO...) | proiect mediu | doar containerul |
| 5 | Rata de reîmprospătare 60/90 Hz la alegere | baterie (azi e mereu 90 Hz) | patch gamescope | rebuild |
| 6 | PREEMPT_DYNAMIC + detectoarele de blocaj + MGLRU în r7 | latență, crash-uri cu urmă, memorie sub presiune | în r7 | flash |
| 7 | Pragurile protecției termice, după măsurători în jocuri | performanță susținută | mic | sudo |
| 8 | Ștergerea Proton x86 (`Proton - Experimental`, 1,5 GB) | spațiu; nu poate rula fără punctul 4 | 1 minut | Steam |

## 2. Ce rulează acum

| Componentă | Versiune / stare |
|---|---|
| Kernel | 6.16.7 Xo666 r5 + patch-urile 0001-0003, DTB cu USB-C doar 5 V |
| Procesor | 4x Cortex-A55 1,80 GHz + 3x A77 2,42 GHz + 1x A77 2,84 GHz; `schedutil`, 1 ms; ARMv8.2 (`atomics`, `lrcpc`, `dcpop`, `asimddp`), **fără LSE2** |
| GPU | Adreno 650, 305-587 MHz, `simple_ondemand`, polling 16 ms (op8-tune) |
| Memorie | 11,4 GiB, zram 17 GiB zstd, `swappiness` 180, THP `madvise`, `vm.max_map_count` 1048576 |
| Mesa (container) | 26.2.3: Turnip Vulkan 1.3.354, freedreno OpenGL 4.6 Compatibility / ES 3.2, Zink disponibil |
| Proton | **11.0 (ARM64)**: DXVK 2.7.1-498, VKD3D-Proton 1.1-5153. **Experimental (ARM64)**: DXVK **3.1.1**, VKD3D-Proton 1.1-5626. **Proton - Experimental** (x86) |
| FEX | unealta Steam `FEX-2607-76`; în Proton ARM64: `libarm64ecfex` (x86-64) și `libwow64fex` (x86 pe 32 de biți) |
| Afișaj | gamescope-op8 (3.16.29 + patch 9001), 2400x1080 **la 90 Hz** |
| Limite | `nofile` 524288 (hard), suficient pentru esync |

## 3. Compatibilitate

### C1. Proton Experimental (ARM64) nu merge pentru D3D9/10/11 (critic, ușor de evitat)

DXVK 3 cere `storageBuffer8BitAccess`, iar Turnip pe Adreno 650 îl raportează `false` (citit:
`storageBuffer8BitAccess=false`, `uniformAndStorageBuffer8BitAccess=false`). Proton Experimental
(ARM64) are DXVK **3.1.1**, deci un joc D3D10/11 pică la inițializarea adaptorului. Același lucru
l-a confirmat proiectul Nova-Deck pe un SM8250 (PR #53: au trecut pe `dxvk-sarek` 1.12 când lipsește
8-bit storage). Proton 11.0 (ARM64) are DXVK 2.7.1-498, care nu cere funcția asta; pe el merg
Tiny Rails, Slime Rancher, Isaac, Undertale, Geometry Dash.
**De făcut:** Steam > Settings > Compatibility: Proton 11.0 (ARM64) ca implicit. Terraria are acum
`proton_experimental` setat pe joc: de schimbat pe 11.0 (ARM64). Când Valve mută Proton 11.0 pe
DXVK 3, pentru jocurile D3D11 rămâne varianta cu DXVK 2.7 înlocuit în prefix sau `dxvk-sarek`.

### C2. Jocurile Linux x86 native nu pornesc: lipsește `fex-mesa` (cauza TODO 12)

Steam ARM64 trimite jocurile Linux x86 prin unealta lui FEX (`steamapps/common/FEX-Emu`,
`fex-compat-tool`). Scriptul caută un sistem x86 cu Mesa x86 în **`/usr/share/guestos/fex-mesa`**
(cu `graphics_provider.json`), cum are SteamOS pe Steam Frame și cum pun Armada și ROCKNIX. În
containerul nostru folderul nu există, iar `FEX-Emu/rootfs` e gol, deci jocul nu are nici
bibliotecile x86, nici driver grafic: se închide în sub o secundă (Half-Life, Hue, LIMBO, Terraria).
**De făcut:** un rootfs x86-64 + i386 cu Mesa x86 compilată cu freedreno/Turnip (sau cu „thunks”
FEX, care trimit apelurile GL/Vulkan la Mesa ARM64 a containerului), pus în container la acea cale.
Nu atinge sistemul telefonului (root doar în container). De verificat întâi ce rootfs oferă
`FEXRootFSFetcher` și dacă are Mesa pentru Adreno. Până atunci: Proton 11.0 (ARM64) forțat pe
versiunea Windows a jocului.

### C3. Direct3D 12: limitat de hardware

Turnip pe Adreno 650 are ce cere VKD3D-Proton de bază (descriptor indexing, buffer device address,
timeline semaphores, `VK_EXT_mutable_descriptor_type`, robustness2), dar **n-are**: `sparseBinding`
/ `sparseResidency*` (resurse „tiled”, cerute de nivelul de funcții D3D12 12_0), `shaderFloat64`,
mesh shaders, ray tracing, fragment shading rate. Jocurile care cer D3D12 12_0 sau Shader Model 6.5+
nu vor porni sau vor fi mult prea lente. Printre cele instalate: **Subnautica 2** (Unreal Engine 5)
aproape sigur nu. **skate.** de verificat (anti-cheat, D3D12).

### C4. OpenGL și Vulkan direct

freedreno: OpenGL 4.6 Compatibility, ES 3.2; Zink (OpenGL peste Turnip) disponibil ca rezervă
(`MESA_LOADER_DRIVER_OVERRIDE=zink`). Jocurile Windows OpenGL trec prin Wine la freedreno.
Extensii utile prezente: `VK_EXT_graphics_pipeline_library` (DXVK compilează fără sacadări mari),
`VK_EXT_descriptor_buffer`, `VK_KHR_present_wait`, `VK_EXT_transform_feedback`,
`VK_KHR_global_priority`.

### C5. Jocuri pe 32 de biți și ARM64EC

Proton 11.0 (ARM64) are `wow64` + `libwow64fex` pentru x86 pe 32 de biți și `libarm64ecfex` pentru
x86-64; Isaac și Undertale (32 de biți) merg. Procesorul n-are LSE2, deci atomicele nealiniate din
codul x86 trec prin calea lentă a FEX (TODO 8: patch-urile de kernel `0504` + `1062` din pocknix
și Armada).

### C6. Anti-cheat, Remote Play, controlere

- Anti-cheat la nivel de kernel (EAC, BattlEye, EA Javelin) nu e de așteptat să meargă sub Proton
  ARM64. De verificat pe ProtonDB înainte de descărcări mari.
- Remote Play: clientul ARM64 de streaming are un bug propriu (`gaming-stack.md`, TODO 11);
  alternativa e Moonlight + Sunshine.
- Controlere USB: merg. Bluetooth (DualSense, Xbox BLE, DS4): netestate (TODO 4).

### C7. Jocurile instalate: drumul așteptat

| Joc | Motor / API (probabil) | Drum | Stare |
|---|---|---|---|
| Tiny Rails, Slime Rancher, INSIDE, Firewatch, Hue, The Forest, Subnautica, Content Warning | Unity, D3D11 | Proton 11.0 (ARM64) + DXVK 2.7 | primele două merg (Slime Rancher în modul „safe”); restul netestate, The Forest și Subnautica grele |
| Isaac: Rebirth, Undertale, Geometry Dash, Muffin Knight | 2D, 32 de biți | Proton 11.0 (ARM64) | merg; Muffin Knight cu text greșit |
| Half-Life, HL2 (+ episoade, Lost Coast), Portal | GoldSrc / Source | build Linux x86 (C2) sau Proton cu versiunea Windows | nativ: nu; cu Proton: de testat |
| Terraria, LIMBO | XNA / propriu | idem | nativ: nu; cu Proton: de testat (Terraria: schimbat pe 11.0) |
| A Story About My Uncle, Poppy Playtime | Unreal 3 / 4, D3D11 | Proton 11.0 (ARM64) | netestate |
| Subnautica 2 | Unreal 5, D3D12 | VKD3D-Proton | foarte probabil nu (C3) |
| skate. | D3D12, anti-cheat | | foarte probabil nu (C3, C6) |

## 4. Performanță

### P1. gamescope-op8 rulează fără prioritate (ușor, cere sudo)

`op8-tune` pune `cap_sys_nice` doar pe `/usr/bin/gamescope` (verificat: are `cap_sys_nice=ep`);
`~/bin/gamescope-op8` n-are nimic. Fără ea, gamescope nu-și poate ridica prioritatea și nu poate
cere coada GPU de prioritate mare (`VK_KHR_global_priority`), deci compunerea concurează cu jocul.
**De făcut:** `sudo setcap cap_sys_nice=eip /home/gabriel/bin/gamescope-op8` și extins `op8-tune`
să o pună și acolo (sau gamescope-op8 ca pachet apk).

### P2. NTSYNC lipsește (`# CONFIG_NTSYNC is not set`)

În kernel de la 6.14; Proton 11 îl folosește singur dacă există `/dev/ntsync`. Contează mai mult
pe ARM: sincronizarea fără NTSYNC trece prin `wineserver` sau esync/fsync, adică apeluri în plus
prin emulare. **De făcut în r7:** `CONFIG_NTSYNC=y`, regulă udev (`/dev/ntsync` citibil de grupul
utilizatorului) și verificat că apare în container.

### P3. Kernel fără preempțiune (`CONFIG_PREEMPT_NONE=y`)

Bun pentru servere, nu pentru jocuri și audio: un fir de kernel lung poate întârzia cadrul. **În
r7:** `CONFIG_PREEMPT_DYNAMIC=y`, cu `preempt=full` sau `voluntary` din linia de comandă, comparat
în jocuri. Tot în r7: detectoarele de blocaj (soft/hard lockup, hung task, din auditul din 10-01),
`CONFIG_LRU_GEN` (MGLRU, alegere mai bună a paginilor de aruncat când memoria se umple; Android îl
folosește), `CONFIG_SCHED_CLASS_EXT` doar dacă vrem să încercăm planificatoare ca `scx_lavd`
(făcut pentru Steam Deck; pe ARM neverificat).

### P4. Afișajul merge mereu la 90 Hz

Driverul panoului dă modul de 90 Hz primul, iar gamescope îl alege. Steam primește
`GAMESCOPE_DISPLAY_REFRESH_RATE_FEEDBACK = 90`. 90 Hz costă baterie și GPU chiar când jocul face
30-60 fps. Gamescope poate schimba între 60 și 90 Hz (sunt moduri separate ale panoului), dar
glisorul de rată al Steam apare doar dacă gamescope cunoaște ratele panoului, iar fără EDID nu le
asociază (Armada are pentru asta patch-ul `0003`). **De făcut:** extins patch-ul nostru gamescope
cu ratele 60/90 pentru conectorul DSI, sau pornire fixă la 60 Hz ca test de baterie.

### P5. Protecția termică taie mult din performanța susținută

În Slime Rancher bateria a ajuns la nivelul 4 (nucleele mari limitate la 1,06 / 1,19 GHz, GPU la
305 MHz). E alegerea corectă pentru o baterie uzată, dar pragurile (41 / 42 / 43 / 44,5 °C) sunt
puse fără măsurători în joc. **De făcut:** o sesiune de 20-30 de minute cu overlay-ul pe nivelul 3
și jurnalul `op8-thermal`, apoi pragurile ajustate (de exemplu 42 / 43 / 44 / 45 °C), plus ratele
de 60 Hz din P4, care scad căldura.

### P6. Emularea x86 (FEX)

- TSO e costul principal. Unealta FEX a Steam citește `STEAM_FEX_TSOENABLED` și
  `STEAM_COMPAT_FEX_CONFIG` (`TSOEnabled:0`, `Multiblock:1`), deci se poate încerca per joc pentru
  jocurile Linux x86 (după C2). Pentru Proton ARM64 (`libarm64ecfex`) setările FEX merg altfel; de
  documentat înainte de folosire. Jocurile Unity sunt de obicei sensibile la TSO oprit.
- Atomice nealiniate fără LSE2: patch-urile de kernel din C5.
- Unealta FEX pune singură `tu_override_uncached_as_cache_coherent=true` pentru Turnip.

### P7. Steam pornea cu `-noshaders` (scos, vezi secțiunea 6)

Opțiunea oprește pre-compilarea shaderelor Steam (Fossilize) în fundal. Pe Turnip, DXVK 2.7
folosește `VK_EXT_graphics_pipeline_library`, deci sacadarea la primul efect e mică. Fossilize ar
costa procesor și baterie la descărcări. **De păstrat** opțiunea, de reevaluat doar pentru un joc
greu care sacadează.

### P8. Interfața Steam consumă la repaus

La repaus, în interfață: ~8 % user + 7 % sistem pe tot procesorul, 13 000 schimbări de context pe
secundă, PSI CPU „some” ~12 % (aproape tot în containerul Steam). Probabil interfața desenată la
90 Hz plus EAS, care ține firele mici pe nucleele mici. Nu afectează jocurile, dar consumă baterie
în meniuri: încă un argument pentru 60 Hz (P4).

### P9. Ce e deja bine (nu necesită schimbări)

- Memorie: zram zstd, `swappiness` 180, THP `madvise`, `vm.max_map_count` 1048576 (unele jocuri
  au nevoie de valori mari; SteamOS folosește mai mult, dar 1048576 ajunge pentru aproape toate).
- Disc: `mq-deadline`, read-ahead 1 MB, partiția de jocuri ext4 `noatime`; reseturile de scriere
  sunt rezolvate (patch 0003).
- Procesor: `schedutil` cu 1 ms, EAS, `uclamp` compilat; atenuările Spectre minime pe A77.
- GPU: polling 16 ms (din 50); 587 MHz e maximul corect pe SM8250 (overclock-ul de 925 MHz din
  alte kerneluri rămâne interzis).
- Limita de fișiere deschise (524288) e suficientă pentru esync.

## 5. Planul propus

1. **Acum, fără risc:** C1 (Proton implicit, Terraria), punctul 8 din tabel (Proton x86 șters),
   P1 (`setcap`, o comandă sudo).
2. **Kernel r7** (un singur flash, după testul cu imaginea de boot ca până acum): patch-urile 0003
   și 5 V (0004) în pachet, NTSYNC + regulă udev, PREEMPT_DYNAMIC, detectoare de blocaj, MGLRU.
3. **Gamescope ca pachet:** patch-ul 9001 + ratele 60/90 Hz (P4) + `cap_sys_nice` din pachet.
4. **`fex-mesa` în container** (C2), apoi testat Half-Life și Terraria nativ, cu TSO per joc (P6).
5. **Măsurători în jocuri** (P5) și ajustat protecția termică; tabelul C7 completat cu fps-ul real
   din overlay.

## 6. Rezultate (2026-10-02, seara)

Făcute în ordinea planului, cu teste pe telefon după fiecare pas.

- **C1 confirmat:** Tiny Rails forțat pe Proton Experimental (ARM64) pică: Unity scrie
  `d3d11: failed to create factory (80004005)` și `Crash!!!`. Implicitul e acum
  `proton_11-arm64` (Proton 11.0-2), iar Terraria e mutat pe el și pornește.
- **Proton x86 și Steam Linux Runtime 4.0 (x86) șterse** (prin `steam://uninstall/<appid>`);
  runtime-ul 1.0 (scout) rămâne, Steam îl ține ca dependență.
- **P1 făcut:** `op8-tune` pune `cap_sys_nice` și pe `~/bin/gamescope-op8` (doar dacă fișierul e al
  userului și nu e scriibil de alții). Mesajul gamescope „No CAP_SYS_NICE, falling back to
  regular-priority” a dispărut, iar firele `gamescope-wl`, `-kms`, `-xwm`, `-wait`, `-pw` rulează la
  nice −20.
- **Fișiere stricate de reseturile de dinainte de patch-ul 0003:** INSIDE avea 234 de fișiere numai
  cu zerouri (scrise la 23:57 pe 1 octombrie, chiar înainte de un reset: ext4 notase fișierele, dar
  nu și conținutul), de unde crash-ul (`MSVCR100.dll ... failed (error c000012f)`). Reparat cu
  `steam://validate/304430`. Și runtime-urile x86 aveau mii de fișiere goale (șterse, vezi mai sus).
  Scanarea întregii biblioteci după fișiere numai cu zerouri nu a mai găsit altele.
- **Barele colorate de TV în video-urile din jocuri** (Poppy Playtime, Tiny Rails): imaginea de
  rezervă a Proton când nu are video-ul re-codat (`STEAM_COMPAT_TRANSCODED_MEDIA_PATH not set`,
  `placeholder-video-used`, `h264-used`). Proton nu poate decoda H.264, iar Steam aduce versiunile
  re-codate prin același mecanism ca shaderele pre-compilate, oprit de `-noshaders`. Fără opțiune,
  Steam a descărcat singur video-urile (`CompatVideoTCMediaV1`, 2,6 GB la Poppy) și shaderele
  Vulkan; Poppy are acum video-ul real. **P7 se inversează:** `-noshaders` scos.
- **Kernel r7** (patch-urile 0001-0004 + `steamed-noodle.config`), instalat cu
  `userspace/system/install-kernel.sh` și scris în `boot_b`: pornește curat, `Dynamic Preempt:
  full`, `/dev/ntsync` (deja `0666`, fără regulă udev), MGLRU `0x0003`, watchdog și hung task
  active, sunet, WiFi și serviciile în regulă, DTB-ul identic cu cel testat (memorie rezervată +
  5 V). Proton 11 ARM64 folosește NTSYNC singur („ntsync: up and running”).
- **NTSYNC:** Subnautica s-a blocat la pornire (firele așteptau în `ntsync_schedule`, 1% procesor);
  cu `PROTON_NO_NTSYNC=1` în Launch Options merge. Content Warning și A Story About My Uncle merg
  cu NTSYNC. Rămâne pornit implicit, cu dezactivare per joc. FPS-ul nu s-a schimbat vizibil:
  jocurile testate sunt limitate de GPU.
- **Jocuri testate** (Proton 11.0-2 ARM64, overlay MangoHud):

  | Joc | Rezultat |
  |---|---|
  | A Story About My Uncle | merge, ~30 FPS |
  | Subnautica | merge, ~26 FPS (doar fără NTSYNC) |
  | Content Warning | merge, ~20 FPS, ușor instabil |
  | Poppy Playtime | merge, video-ul din meniu corect după descărcarea video-urilor re-codate |
  | INSIDE | merge după verificarea fișierelor |
  | Terraria | pornește |
  | Subnautica 2 | nu pornește (încărcare infinită, nici jurnal Unreal), cum anticipa C3 |

- **Jurnalul Proton** (`PROTON_LOG=1`) a fost pornit global doar pentru teste: FEX produce multe
  excepții, iar jurnalizarea lor scade FPS-ul. Oprit; pentru un joc se pune din Launch Options.

## Surse

- Proton, DXVK, VKD3D-Proton, FEX: citite din `steamapps/common` pe telefon (`version`, șiruri din
  DLL-uri), `vulkaninfo` (Mesa 26.2.3), `glxinfo`.
- DXVK 3 cere Vulkan 1.4 și `storageBuffer8BitAccess`:
  [Phoronix, DXVK 3.0](https://www.phoronix.com/news/DXVK-3.0-Release),
  [linuxiac](https://linuxiac.com/dxvk-3-0-released-with-new-shader-compiler-and-vulkan-1-4-requirement/).
- Adreno 650 și DXVK 3: [Nova-Deck/os-build PR #53](https://github.com/Nova-Deck/os-build/pull/53).
- NTSYNC în kernel 6.14 și folosit automat de Proton:
  [Steam Community](https://steamcommunity.com/app/221410/discussions/0/803472142715854998/),
  [Steam Deck HQ](https://steamdeckhq.com/news/proton-ge-10-9-releases-with-ntsync-support/).
- `fex-mesa` și unealta FEX a Steam: scriptul `fex-compat-tool` de pe telefon;
  [ROCKNIX, Mesa x86 pentru FEX](https://github.com/ROCKNIX/distribution/commit/d9a00a4edf407ce940a57196ee6a4cd2d62fbab8).
