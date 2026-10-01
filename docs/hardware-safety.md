# Siguranță hardware și pregătire înainte de flash (OnePlus 8, `instantnoodle`)

Scris pe 2026-10-01, după un audit complet al proiectului, cu telefonul disponibil fizic.
Toate afirmațiile de mai jos au sursa citată la final sau sunt verificate direct în cod
(kernelul Xo666, pmbootstrap 3.11.1, initramfs-ul postmarketOS, DT-ul OnePlus din kernelul
LineageOS). Ce nu s-a putut verifica fără telefon e marcat explicit **NEVERIFICAT**.

**Despre "100% sigur".** Nimeni nu poate garanta asta pentru un port neoficial: kernelul
Xo666 nu are rapoarte publice de instalare de la alți utilizatori. Ce se poate face, și ce
face documentul ăsta: (1) separăm ce poate produce **daune fizice** de ce produce doar "nu
pornește"; (2) pentru fiecare risc fizic avem o măsură concretă (fix în cod, componentă
oprită, limită) și un test precis; (3) nu scriem nimic pe telefon până nu avem backup
complet și verificat.

Termeni folosiți des:
- *PMIC* = cipul care generează toate tensiunile din telefon și încarcă bateria (aici:
  PM8150, PM8150B pentru încărcare, PM8150L, PM8009 pentru camere).
- *regulator / LDO* = o ieșire de tensiune a PMIC-ului care alimentează o componentă.
- *float voltage* = tensiunea maximă la care încărcătorul ține bateria când e plină.
- *EDL* = modul de urgență Qualcomm (9008), funcționează chiar dacă bootloader-ul e distrus.
- *slot A/B* = telefonul are două copii ale partițiilor de boot (`boot_a`/`boot_b` etc.) și
  pornește din slotul "activ".
- *EFS* = partițiile cu IMEI și calibrarea modemului (`modemst1/2`, `fsg`, `fsc`, `mdm1m9kefs*`).

---

## 0. Pe scurt: ce poate strica efectiv ceva

| # | Risc | Consecință | Stare în proiect | Cum verifici |
|---|---|---|---|---|
| 1 | Re-blocarea bootloader-ului cu software modificat pe telefon | Telefon care nu mai pornește, doar EDL/MSM îl mai repară | Regulă de procedură | Nu rulezi niciodată `fastboot flashing lock` (secțiunea 3.4) |
| 2 | Driverul comunitar de încărcare PM8150B (`qcom_pm8150b_charger.c`) | Bateria împinsă spre ~4.87 V în loc de 4.435 V: degradare, umflare, risc de incendiu | **Nu există în kernelul nostru.** Patch-ul care pregătea terenul pentru el a fost scos | 4.1, testul de încărcare |
| 3 | Difuzoare fără protecție | Difuzor (mai ales cel din cască) ars la volum mare susținut | Bug de configurare reparat (patch 0001); protecția lipsește în continuare | 4.4, limită de volum |
| 4 | Regulator de cameră peste tensiunea OnePlus, pornit permanent | Stres electric continuu pe modulul camerei spate | Reparat (patch 0002) | 4.6, `regulator_summary` |
| 5 | Scriere în partiții greșite | De la "Android nu mai pornește" până la IMEI pierdut | Proceduri de flash corectate, initramfs verificat | 2 și 3 |
| 6 | Supraîncălzire | Throttling, oprire de protecție; risc mic de daune | Zonele termice există; de testat | 4.8 |

Tot restul (ecran, GPU, WiFi, DSP-uri, USB) poate cel mult să nu funcționeze, fără mecanism
plauzibil de daună fizică, cu condițiile din secțiunea 4.

---

## 1. Ce îți trebuie înainte de orice

1. **Modelul exact.** Setări > Despre telefon. Trebuie să fie IN2013 (Europa), IN2015 (SUA,
   deblocat), IN2011 (India) sau IN2010 (China). **IN2017 (T-Mobile)** cere token de
   deblocare de la OnePlus după deblocarea SIM. **IN2019 (Verizon)** nu se poate debloca
   oficial: dacă ai IN2019, te oprești aici.
2. **Versiunea OxygenOS exactă** (Setări > Despre telefon > Versiune). Notează și codul de
   regiune din build (ex. `IN21AA` global, `IN21BA` Europa, `IN21DA` India).
3. **De descărcat pe PC (Windows), înainte de deblocare:**
   - Google *platform-tools* (adb + fastboot, versiunea curentă).
   - Driverele USB Qualcomm (pentru EDL/MSM) și driverul Google USB pentru fastboot.
   - **Pachetul MSM Download Tool pentru regiunea ta** (thread-ul XDA "[OP8][OOS 21AA/BA/DA]
     Unbrick tool"). E plasa de siguranță finală: rescrie tot telefonul prin EDL.
   - Pachetul complet de update (*full OTA zip*) pentru versiunea OxygenOS pe care o ai acum.
     Din el se pot extrage imagini originale (`boot`, `dtbo`, `vbmeta`) cu `payload-dumper-go`.
   - Pentru backup: imaginea TWRP pentru instantnoodle (3.7.0 pentru Android 13) **sau**
     aplicația Magisk (varianta B din secțiunea 2.4).
4. **Spațiu pe PC:** minim 15 GB liberi doar pentru backup, ideal pe două discuri diferite.
5. **Cablu USB-C de date bun**, port USB direct pe placa de bază (nu hub).
6. **Baterie peste 60%** înainte de fiecare sesiune de flash.
7. Opțional, dar recomandat pentru testele de la secțiunea 4: un **tester USB-C** (afișează
   tensiunea și curentul pe cablu, ~10-15 EUR) și un încărcător simplu de 5 V (USB-A) cu
   cablu USB-A la USB-C.

---

## 2. Backup, în ordinea asta

### 2.1 Datele personale

Deblocarea bootloader-ului **șterge tot** (poze, aplicații, conturi). Copiază ce te
interesează înainte. Asta e singura pierdere sigură din tot procesul.

### 2.2 Starea telefonului, înainte de orice modificare

Pornește în fastboot: telefon oprit, ține **Volum Sus + Volum Jos + Power** (conform wiki-ului
postmarketOS). Atenție: dacă ții doar volumele cu cablul USB conectat și telefonul oprit,
poate intra în EDL (ecran negru, Windows vede "QDLoader 9008"); în cazul ăsta ține Power
~10 secunde ca să iasă.

```
fastboot getvar all 2> getvar-inainte.txt
```

Din fișier notează: `product`, `variant`, `unlocked`, `current-slot`,
`slot-successful:a/b`, `slot-unbootable:a/b`, `slot-retry-count:a/b`,
`partition-size:super`, `max-download-size`, versiunea bootloader-ului.

### 2.3 Deblocarea bootloader-ului

1. Setări > Despre telefon > atingi de 7 ori pe *Număr versiune* (activează Opțiuni dezvoltator).
2. Opțiuni dezvoltator: activezi **Deblocare OEM** și **Depanare USB**.
3. `adb reboot bootloader`, apoi `fastboot flashing unlock`, confirmi pe telefon cu tastele de volum.
4. Telefonul se șterge și repornește în Android. Faci configurarea minimă.

Deblocarea nu atinge `persist`, EFS sau `super` (doar `userdata`), deci backup-ul de mai jos
prinde încă toate partițiile originale.

### 2.4 Backup la toate partițiile (fără `userdata`)

Wiki-ul postmarketOS pentru OnePlus 8 și 8 Pro cere explicit backup la `super` înainte de
orice flash. Noi luăm **tot**, pentru că printre partiții sunt unele unice per telefon care
nu există în niciun pachet de update: `persist` (calibrări senzori, amprentă), `modemst1`,
`modemst2`, `fsg`, `fsc`, `mdm1m9kefs1/2/3/c` (EFS/IMEI pentru modemul 5G extern),
`mdm_oem_dycnvbk`, `mdm_oem_stanvbk`, `param`, `devinfo` și altele.

**Varianta A: TWRP pornit temporar (nimic nu se scrie pe telefon)**

```
fastboot boot twrp-instantnoodle.img
```

Dacă TWRP întreabă dacă păstrează sistemul *read-only*, **păstrezi read-only** (nu glisezi
"Allow modifications"). Nu instalezi TWRP, nu formatezi, nu "repari" nimic din el. Apoi, din
Git Bash pe Windows (cu platform-tools în PATH; `adb` din WSL nu vede USB-ul):

```
mkdir backup-op8 && cd backup-op8
adb shell ls -l /dev/block/by-name/ > partitii.txt
for p in $(adb shell ls /dev/block/by-name/ | tr -d '\r'); do
  case "$p" in userdata|reserve_a|reserve_b) continue ;; esac
  adb pull "/dev/block/by-name/$p" "$p.img"
done
```

(`reserve_a/b` sunt linkuri spre un fișier din `userdata`, deci se sar.)

**Varianta B: root temporar cu Magisk (tot fără scriere permanentă)**

Extragi `boot.img` din full OTA-ul versiunii tale, îl patch-uiești în aplicația Magisk, apoi
`fastboot boot magisk_patched.img`. Cu Android pornit:

```
adb exec-out su -c "cat /dev/block/by-name/persist" > persist.img
```

repetat pentru fiecare partiție din lista `ls /dev/block/by-name/`.

**NEVERIFICAT:** dacă bootloader-ul tău (după OxygenOS 13) acceptă `fastboot boot`.
Rapoartele XDA pentru instantnoodle spun că da. Dacă refuză, **nu** flash-ui TWRP/Magisk
permanent ca să ocolești: întreabă întâi, există variante (inclusiv citire prin EDL cu
`bkerler/edl`, care nici nu cere bootloader deblocat).

### 2.5 Verificarea backup-ului (obligatorie)

Pentru partițiile critice compari hash-ul de pe telefon cu cel de pe PC:

```
adb shell "cd /dev/block/by-name && sha256sum persist modemst1 modemst2 fsg fsc mdm1m9kefs1 mdm1m9kefs2 mdm1m9kefs3 mdm1m9kefsc mdm_oem_dycnvbk mdm_oem_stanvbk param super"
sha256sum persist.img modemst1.img modemst2.img fsg.img fsc.img mdm1m9kefs1.img mdm1m9kefs2.img mdm1m9kefs3.img mdm1m9kefsc.img mdm_oem_dycnvbk.img mdm_oem_stanvbk.img param.img super.img
```

În varianta B, prima comandă se rulează ca `adb shell su -c "..."`. Toate hash-urile trebuie
să coincidă. Apoi copiezi folderul pe al doilea disc.

---

## 3. Instalarea, pas cu pas, cu scrieri minime

### 3.1 Ce se scrie și ce nu

pmbootstrap scrie **doar** în: `dtbo` și `boot` (din slotul activ), `super` (comun) și,
opțional, `vbmeta` (slotul activ). Nimic altceva. Bootloader-ele (`xbl`, `abl`), TrustZone,
`persist`, EFS și GPT-ul (tabela de partiții) nu sunt atinse. În implementarea de referință
Qualcomm a bootloader-ului (ABL, pe care se bazează și cel OnePlus), o imagine mai mare decât
partiția e refuzată **înainte** de orice scriere ("Image is too large for the partition",
`QcomModulePkg/Library/FastbootLib/FastbootCmds.c`, atât pentru imagini sparse cât și brute).
Deci un `fastboot flash super` greșit nu se poate revărsa în GPT sau în alte partiții.

Pe telefon, initramfs-ul postmarketOS redimensionează doar tabela de partiții **din interiorul**
imaginii scrise în `super`, niciodată GPT-ul real (verificat în `init_functions_2nd.sh`), cu
excepția cazului în care pui `PMOS_FORCE_PARTITION_RESIZE` în linia de comandă a kernelului.
Nu-l pune.

### 3.2 Construirea imaginilor (în WSL)

Parola aleasă la `pmbootstrap install` e și parola SSH: alege una serioasă. Orice imagine
construită cu o parolă de test trebuie reconstruită înainte de flash.

```
pmbootstrap install              # FĂRĂ --split, cu parola ta
pmbootstrap export               # pune linkuri în /tmp/postmarketOS-export
cp -L /tmp/postmarketOS-export/{boot.img,dtbo.img,oneplus-instantnoodle.img} /mnt/c/op8-flash/
```

`oneplus-instantnoodle.img` e rootfs-ul cu partițiile interioare `pmOS_boot` și `pmOS_root`,
deja în format *sparse* (formatul comprimat pe care îl înțelege fastboot).

Flash-ul îl faci din Windows cu `fastboot.exe`, pentru că WSL2 nu vede direct USB-ul
(alternativa e `usbipd-win`, dar telefonul se reconectează la fiecare repornire).

### 3.3 Flash

Cu telefonul în fastboot:

```
fastboot getvar current-slot                 # notează: a sau b
fastboot getvar partition-size:super         # trebuie să fie mai mare decât imaginea
fastboot flash dtbo dtbo.img
fastboot flash boot boot.img
fastboot flash super oneplus-instantnoodle.img
fastboot reboot
```

**vbmeta e opțional.** Porturile oficiale 8 Pro și 8T nu îl scriu și pornesc cu bootloader-ul
deblocat. Îl folosești doar dacă bootloader-ul refuză imaginea de boot:

```
fastboot --disable-verity --disable-verification flash vbmeta vbmeta_X.img   # X = slotul activ, din backup
```

Primul boot: logo postmarketOS, apoi pe USB apare o placă de rețea, telefonul are IP
`172.16.42.1`, te conectezi cu `ssh user@172.16.42.1`.

### 3.4 Ce nu faci niciodată

- `fastboot flashing lock` / `fastboot oem lock` cu altceva decât OxygenOS original pe telefon.
- `fastboot erase ...`, `fastboot -w`, `fastboot flash` pe orice altă partiție decât cele de
  la 3.3, `fastboot flashing unlock_critical` (nu e necesar).
- `fastboot --set-active=...` (vezi testul de sloturi de la 4.2), decât la restaurare.
- Din Linux: `dd`, `parted`, `gparted`, `mkfs` pe `/dev/sda*`, `/dev/sdb*`... Singura partiție
  a pmOS e cea mapată din `/dev/sda14` (`super`).
- Kernelul WuerfelDev, kernelul oficial pmOS SM8250 sau driverul lor de încărcare (secțiunea 4.1).
- Pe telefon: `apk upgrade --prune` sau `apk upgrade --available`. Kernelul, firmware-ul și pachetul
  de dispozitiv sunt construite local și nu există în depozitele online, iar aceste opțiuni le pot
  șterge sau înlocui. `apk upgrade` simplu e în regulă. Un kernel nou instalat pe telefon ajunge doar
  în `/boot`; partiția `boot_b` se actualizează tot prin fastboot de pe PC.

### 3.5 Întoarcerea la Android

1. `img2simg super.img super-s.img`, apoi `fastboot flash super super-s.img`.
2. `fastboot flash boot boot_X.img`, `fastboot flash dtbo dtbo_X.img` (și `vbmeta` dacă l-ai
   modificat), unde X e slotul notat la 3.3, din backup.
3. Dacă ceva nu merge: MSM Download Tool cu pachetul regiunii tale (EDL).

### 3.6 Verificare: drumul înapoi la stock, pe fiecare scenariu (2026-10-01)

Fluxul nostru nu scrie niciodată în bootloader (`xbl`, `abl`), deci fastboot nu poate fi
pierdut prin el. Singurele căi spre un telefon fără fastboot sunt re-blocarea bootloader-ului
cu software modificat sau scrieri manuale în alte partiții, ambele interzise la 3.4.

| Scenariu | Drumul înapoi | Ce trebuie să existe | Stare |
|---|---|---|---|
| pmOS nu pornește, ecran negru, bootloop | Power ~10-15 s (reset hardware), apoi Volum Sus + Volum Jos + Power, apoi restaurare din backup (mai jos) | backup verificat, fastboot pe PC, driver fastboot | fastboot 34.0.5 găsit pe PC (nu e în PATH); backup și driver: de verificat cu telefonul conectat |
| Telefonul a trecut pe celălalt slot | `fastboot --set-active=X`, apoi ca mai sus | slotul original notat | se notează la backup |
| Fastboot inaccesibil | EDL + MSM Download Tool | pachetul MSM al regiunii, driverul Qualcomm 9008, test de intrare în EDL | **lipsesc** pachetul MSM și driverul 9008 pe acest PC |
| IMEI, amprentă sau senzori afectați | `fastboot flash <partiție>` sau `dd` cu root, din backup | backup verificat | se face |
| Backup-ul lui `super` e incomplet sau corupt | test dus-întors `img2simg` / `simg2img` cu hash identic, dimensiune egală cu `partition-size:super` | `img2simg` | instalat în WSL |
| Baterie descărcată complet sub pmOS | încărcare hardware cu telefonul oprit sau în fastboot | nimic | doar de evitat sub ~15% |

Restaurare completă, cu nume explicite de slot ca să nu se scrie în slotul greșit (X = slotul
notat la backup):

```
fastboot flash boot_X boot_X.img
fastboot flash dtbo_X dtbo_X.img
fastboot flash vbmeta_X vbmeta_X.img
img2simg super.img super-s.img          # în WSL
fastboot flash super super-s.img
fastboot --set-active=X                 # doar dacă slotul s-a schimbat
fastboot reboot
```

Backup-ul conține `boot` cu Magisk, deci restaurarea readuce telefonul exact în starea de
acum (OxygenOS oficial cu root). **Nu se flash-uiește pmOS până nu sunt toate rândurile
verzi**, inclusiv testul EDL.

---

## 4. Inventar hardware: ce atinge Linux-ul și cum testăm

Pentru fiecare componentă: ce face kernelul Xo666 (cu patch-urile noastre), ce poate merge
rău fizic, ce s-a verificat deja și testul precis de făcut pe telefon.

### 4.1 Baterie și încărcare (PMIC PM8150B, partea SMB5)

- **Ce face kernelul:** nimic. Kernelul Xo666 nu are driver pentru `qcom,pm8150b-charger`
  (verificat: lipsesc `qcom_pm8150b_charger.c` și `qcom_fg.c`). Încărcarea rămâne pe
  setările lăsate de bootloader în PMIC, cu protecțiile hardware ale PMIC-ului (inclusiv
  oprirea la temperatură) și cu circuitul de protecție din pachetul bateriei.
- **Riscul real e driverul comunitar**, prezent în fork-ul WuerfelDev și în kernelul oficial
  postmarketOS SM8250 (inclusiv tag-ul `sm8250-7.2.0`, 2026-08-29). Are trei bug-uri confirmate:
  1. Scrie tensiunea maximă de încărcare cu formula cipului vechi PMI8998
     (`(uV - 3487500) / 7500 + 1`). PM8150B folosește 3.6 V + 10 mV pe pas (driverul
     OnePlus `qpnp-smb5.c`: `smb5_pm8150b_params.fv`). Pentru bateria noastră (4.435 V)
     rezultă valoarea 127, adică **~4.87 V**. Confirmat independent pe Retroid Pocket 5
     (tot SM8250 + PM8150B): registrul `0x1070` citit înapoi `0x7a` = 4.82 V pentru o
     baterie de 4.40 V.
  2. Nu setează curentul de încărcare (rămâne valoarea hardware de 5.35 A).
  3. "Hrănește" watchdog-ul încărcătorului la adresa `0x643` în loc de `0x1643`, adică scrie
     în alt periferic al PMIC-ului (același bug a fost reparat în kernelul oficial Linux pe
     2026-09-09 pentru driverul-părinte `qcom_smbx`).
  Pentru comparație, OnePlus ține bateria la 4.435 V la temperatură normală, oprește
  încărcarea software peste 4.445 V și consideră defect orice peste **4.55 V**
  (`kona-mtp.dtsi`: `temp_normal_vfloat_mv = 4435`, `vbatt_hv_thr = 4550`). La cald coboară
  la 4.13 V; kernelul mainline nu face asta.
- **Ce s-a schimbat în proiect:** patch-ul care adăuga doar nodurile de device tree pentru
  charger a fost scos (nu făcea nimic fără driver, dar ar fi activat bug-ul de mai sus în
  momentul în care cineva adăuga driverul).
- **Test (primele sesiuni de încărcare):** încărcător de 5 V simplu, telefon în repaus, ecran
  stins. Din SSH:
  ```
  while true; do date +%T; cat /sys/class/power_supply/*/voltage_now /sys/class/power_supply/*/temp 2>/dev/null; sleep 10; done | tee incarcare.log
  ```
  Tensiunea bateriei (în µV) **nu are voie să treacă de 4450000**. Temperatura bateriei
  (zecimi de grad) ar trebui să rămână sub 400. Dacă depășește oricare: scoți cablul și te oprești.
  Repeți testul o dată de la ~90% până la plin, ca să vezi unde se oprește.
  **NEVERIFICAT:** ce valoare lasă bootloader-ul în registrul de float voltage când nu există
  driver; testul de mai sus o măsoară indirect.

### 4.2 Bootloader, sloturi A/B, vbmeta, fuzibile

- **Ce face kernelul:** nimic cu bootloader-ul. Nimic din Linux-ul mainline nu arde fuzibile
  (*qfuses*, biți scriși o singură dată în SoC). Anti-rollback-ul hardware introdus de OnePlus
  în 2026 a venit pe OnePlus 13/13T/15, nu pe OnePlus 8; oricum noi nu scriem bootloader-e.
- **Sloturi:** bootloader-ul Qualcomm scade un contor de încercări la fiecare pornire dacă
  slotul nu e marcat "successful" și, la zero, trece pe celălalt slot (care are Android-ul
  vechi, fără `super` valid, deci nu pornește). OxygenOS a marcat deja slotul activ ca
  reușit, iar pmOS nu are aici serviciul `qbootctl` care să scrie în GPT, deci starea rămâne
  cum e. Nu e brick (fastboot rămâne disponibil), dar e derutant.
- **Test:** după primele 3-4 porniri pmOS, intră în fastboot și compară cu `getvar-inainte.txt`:
  ```
  fastboot getvar slot-successful:X
  fastboot getvar slot-retry-count:X
  fastboot getvar current-slot
  ```
  Trebuie să rămână `yes`, același contor, același slot.

### 4.3 Fuel gauge (`ti,bq27411`, I2C 0x55)

- **Ce face kernelul:** driverul `bq27xxx` citește nivelul bateriei și, pentru că nodul are
  `monitored-battery`, scrie la pornire în memoria RAM a cipului capacitatea (4270 mAh),
  energia (16.37 Wh) și tensiunea de terminare (3.4 V). Configurația din RAM se pierde doar
  la deconectarea bateriei. Nu controlează încărcarea, afectează doar procentul raportat.
- **Risc:** procent afișat greșit, nimic fizic.
- **Test:** `cat /sys/class/power_supply/bq27411-0/uevent`; tensiunea trebuie să fie
  plauzibilă (3.4-4.45 V) și să crească la încărcare.

### 4.4 Difuzoare (2x NXP TFA9874 pe I2C15: 0x34 cască, 0x35 difuzor principal)

- **Ce face kernelul:** driverul `tfa9872.c` din Xo666 pornește amplificatoarele fără
  algoritmul de protecție NXP și dezactivează explicit senzorii de curent și tensiune.
  Conform datasheet-ului, la TFA9874 protecția difuzorului (termică și mecanică) rulează pe
  DSP-ul gazdă, pe baza acelor senzori; pe Android o face OnePlus. Aici nu o face nimeni.
  Configurația UCM nu definește nici control de volum hardware.
- **Bug reparat (patch 0001):** funcția care configurează convertorul boost al
  amplificatoarelor citea patru valori din variabile neinițializate (kernelul are
  `CONFIG_INIT_STACK_NONE=y`), deci curentul maxim prin bobină și tensiunea boost depindeau
  de ce rămăsese pe stivă. Plus o scriere în registrul greșit. Acum folosesc valorile
  implicite ale cipului.
- **Risc rămas:** difuzor supraîncălzit sau deteriorat mecanic la volum mare susținut, mai
  ales cel din cască (e mic și pe Android primește puțin semnal).
- **Măsuri:** primele teste la volum 20-30% (`wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.25`).
  Atenție: `wpctl` nu are o limită permanentă (opțiunea `-l` limitează doar comanda
  respectivă). O limită reală se face cu un limitator în PipeWire (*filter-chain*), de
  configurat după ce sunetul funcționează. Până atunci: nu urca peste ~50%, iar pentru jocuri
  folosește căști (USB-C sau Bluetooth). Dacă auzi distorsiuni, scazi imediat.
- **Test:** `dmesg | grep -i tfa` trebuie să arate două cipuri cu revizia `0x0c74`.
- **Rezultat 2026-10-01:** ton de 1 kHz la -30 dBFS, curat, fără pocnituri; canalul stâng iese
  sus (cască), dreptul jos (difuzorul principal). Pe această cale nu există control de volum
  hardware, deci nivelul depinde doar de semnalul digital. Difuzorul de sus e cel mai mic și mai
  vulnerabil: la configurarea PipeWire, limitator obligatoriu înainte de volume mari.

### 4.5 Regulatoare (PM8150, PM8150L, PM8009 prin RPMh)

- **Verificat:** limitele min/max ale celor 37 de regulatoare din DTS-ul Xo666 au fost comparate
  cu `kona-regulators.dtsi` din DT-ul OnePlus 8 (proiectul `19821`). 36 identice sau mai
  stricte. Singura abatere: L2F (vezi 4.6), reparată.
- **Test:** `cat /sys/kernel/debug/regulator/regulator_summary`. Nicio tensiune peste ce e în DTS.

### 4.6 Camere (PMIC PM8009)

- **Problema găsită:** Xo666 forța pornite permanent toate cele 7 LDO-uri ale PMIC-ului de
  camere, deși doar L3F și L7F au consumator (camera frontală IMX471). L2F era la 1.2 V; OnePlus
  îl folosește la exact 1.1 V, doar cât e pornită camera spate principală
  (`kona-oem-camera-instantnoodle.dtsi`). În tot DT-ul OnePlus 8 (82 de fișiere), LDO-urile
  PM8009 alimentează doar camere.
- **Reparat (patch 0002):** L1F, L2F, L4F, L5F, L6F nu mai sunt forțate pornite; L2F la 1.104 V.
  Prima variantă a patch-ului cerea exact 1.100 V, valoare imposibilă pentru acest tip de
  regulator (pași de 8 mV de la 320 mV). La primul boot tot grupul PM8009 a eșuat și au
  rămas fără alimentare WiFi/Bluetooth (cipul lor de putere depinde de S2F) și camera frontală.
  Nimic periculos (linii oprite, nu supra-alimentate), dar o verificare la compilare nu prinde
  asta: se vede doar pe telefon. 1.104 V e pasul la care driverul OnePlus rotunjește 1.1 V.
  Camera frontală păstrează L3F și L7F.
- **Test:** `dmesg | grep -i regulators-2` nu trebuie să arate erori, iar `dmesg | grep "deferred probe pending"`
  nu trebuie să mai listeze `qca6390-pmu`, WiFi sau camera. În `regulator_summary`, `vreg_l2f_1p2`
  apare oprit (sau la 1104 mV).
  Camera frontală trebuie să funcționeze în continuare (dacă nu, raportezi, nu repornești
  regulatoarele de mână).

### 4.7 Ecran AMOLED (`samsung,amb655uv01`, DSI)

- **Ce face kernelul:** driverul de panou trimite secvența de inițializare; alimentările
  panoului trec prin regulatoarele verificate la 4.5.
- **Risc:** ecran negru (nu fizic). Uzură AMOLED (*burn-in*) la imagini statice luminoase
  ore întregi: temă întunecată, stingere automată, luminozitate moderată.

### 4.8 Termic (TSENS, LMh, zone termice)

- **Ce face kernelul:** zonele termice și limitările CPU/GPU vin din `sm8250.dtsi`.
  Atenție: `QCOM_TSENS`, `QCOM_SPMI_TEMP_ALARM` și `QCOM_LMH` sunt **module**, deci protecția
  termică software există doar după ce se încarcă din rootfs. Independent de OS, SoC-ul are
  resetare hardware la temperatură critică.
- **Test:**
  ```
  lsmod | grep -E "tsens|lmh|temp_alarm"
  for z in /sys/class/thermal/thermal_zone*; do echo "$(cat $z/type) $(cat $z/temp)"; done
  ```
  Apoi un test de stres de 2 minute (`stress-ng --cpu 8 --timeout 120`) cu temperaturile
  logate. Pragurile din `sm8250.dtsi`: încetinire de la 90 °C, mai puternică la 95 °C,
  oprire de protecție la 110 °C. Frecvențele trebuie să scadă când zonele CPU ajung la 90 °C;
  dacă trec de 95 °C fără să scadă, oprești testul.

### 4.9 GPU (Adreno 650)

- **Ce face kernelul:** încarcă shader-ul semnat `a650_zap.mbn` (firmware fără de care GPU-ul
  nu pornește). Treapta de 670 MHz a lui 865+ e activată doar dacă fuzibilele cipului spun
  că e 865+ (`opp-supported-hw` + `gpu_speed_bin`), deci pe 865 simplu maximul rămâne 587 MHz.
- **Test:** `cat /sys/class/devfreq/3d00000.gpu/available_frequencies` (maxim 587000000 pe
  865 simplu) și `dmesg | grep -iE "zap|a6xx|adreno"`.

### 4.10 CPU

- Frecvențele vin din tabelul hardware al SoC-ului (*cpufreq-hw*), kernelul nu poate depăși
  ce permite cipul. Risc fizic: niciunul identificat.

### 4.11 USB-C, Power Delivery, OTG, DisplayPort

- **Ce face kernelul:** controlerul Type-C din PM8150B negociază PD. DTS-ul acceptă ca
  receptor 5 V fix și 5-12 V variabil, deci cu un încărcător PD telefonul poate cere peste 5 V.
  Fără driver de încărcare, nimeni nu a testat ce face PMIC-ul cu 9-12 V la intrare.
  Wiki-ul 8 Pro mai notează că PMIC-ul poate rămâne cu tensiune pe pinul CC după restart cu
  hub alimentat conectat.
- **Măsură:** la început doar încărcător de 5 V cu cablu USB-A la USB-C (fără PD).
- **Test:** tester USB-C pe cablu: tensiunea trebuie să fie ~5 V.

### 4.12 Bliț LED (PM8150L)

- **Verificat:** 300 mA lanternă, 1000 mA bliț, maxim 1.28 s. Identic cu valorile implicite
  OnePlus și sub maximele lor (500 mA / 1500 mA). Risc: niciunul la aceste valori.

### 4.13 Modem 5G (SDX55) și partițiile EFS

- **Ce face kernelul:** legătura PCIe spre modem e activată în DTS, dar nimic nu pornește
  modemul, deci nu se stabilește. Nu se instalează firmware de modem și nu rulează niciun
  serviciu care să scrie în partițiile EFS. (Pe 8T cineva a pornit SDX55 sub mainline, cu
  servicii care scriu în EFS: motiv în plus pentru backup și pentru a nu activa modemul.)
- **Test:** `ls /sys/bus/mhi/devices/` gol și `pgrep -a rmtfs` fără rezultat.

### 4.14 WiFi și Bluetooth (QCA6390)

- Setează țara: `iw reg set RO`. Risc fizic: niciunul identificat.
- **Proveniența firmware-ului** (comparat după amprenta git cu linux-firmware oficial):
  `a650_gmu.bin`, `a650_sqe.fw` (GPU, nesemnate) și `m3.bin` sunt identice cu linux-firmware;
  `board-2.bin` e versiunea oficială din 2022-04-23; `amss.bin` (firmware-ul cipului WiFi)
  nu corespunde niciunei versiuni linux-firmware, deci probabil e extras din OxygenOS.
  Cipul WiFi accesează memoria doar prin SMMU (unitatea care limitează ce memorie poate
  atinge un dispozitiv PCIe), deci riscul e limitat, dar proveniența lui nu e verificată.

### 4.15 DSP-uri (ADSP, CDSP, Venus; SLPI oprit)

- Firmware semnat de OnePlus, verificat de TrustZone. Firmware greșit = DSP-ul nu pornește.
  SLPI (senzori) nu primește firmware în build-ul nostru, rămâne oprit. Risc fizic: niciunul.

### 4.16 NFC, touchscreen, cameră frontală, haptice

- NFC și touch: risc fizic niciunul identificat. Vibrația (`awinic,aw8697`) nu e în DTS-ul
  Xo666, deci nu e acționată.

### 4.17 Accesoriul GameSir X3 Pro (Peltier)

- Răcitorul se alimentează separat. Risc teoretic (neconfirmat pentru acest produs): un element
  Peltier care răcește sub punctul de rouă poate produce condens. Nu-l folosi în încăperi
  umede, șterge spatele telefonului după sesiuni lungi.

---

## 5. Ce rămâne neverificat

- Dacă `fastboot boot` merge pe bootloader-ul tău actual.
- Ce face PMIC-ul cu încărcarea fără driver (testul de la 4.1 răspunde).
- Pragul exact la care difuzoarele se deteriorează fără protecție.
- Comportamentul termic sub joc susținut.
- Kernelul Xo666 nu are rapoarte publice de instalare de la alți utilizatori.

## Surse

- Wiki postmarketOS: [OnePlus 8](https://wiki.postmarketos.org/wiki/OnePlus_8_(oneplus-instantnoodle)),
  [OnePlus 8 Pro](https://wiki.postmarketos.org/wiki/OnePlus_8_Pro_(oneplus-instantnoodlep)),
  [OnePlus 8T](https://wiki.postmarketos.org/wiki/OnePlus_8T_(oneplus-kebab))
- DT și drivere OnePlus 8: [LineageOS/android_kernel_oneplus_sm8250](https://github.com/LineageOS/android_kernel_oneplus_sm8250)
  (`arch/arm64/boot/dts/vendor/19821/`, `drivers/power/supply/qcom/qpnp-smb5.c`,
  `techpack/audio/asoc/codecs/tfa98xx-v6/tfa9874_tfafieldnames.h`)
- Bug-ul de float voltage: [armada-os/armada#534](https://github.com/armada-os/armada/issues/534),
  [armada-os/armada#550](https://github.com/armada-os/armada/issues/550),
  [ROCKNIX/distribution#3371](https://github.com/ROCKNIX/distribution/pull/3371),
  [ROCKNIX/distribution#3382](https://github.com/ROCKNIX/distribution/pull/3382),
  [seria qcom_smbx din linux-pm](https://ratatoskr.run/linux-pm/2026/08/17399196/t)
- [Datasheet NXP TFA9874B](https://www.mouser.com/datasheet/2/302/TFA9874B_SDS-1517291.pdf)
- [MSM Download Tool OnePlus 8, XDA](https://xdaforums.com/t/op8-oos-21aa-ba-da-unbrick-tool-to-restore-your-device-to-oxygenos.4085877/)
- [Anti-rollback OnePlus 2026](https://www.gsmgotech.com/2026/01/oneplus-quietly-adds-anti-rollback.html)
- [Qualcomm ABL, FastbootCmds.c (CodeLinaro, implementarea de referință)](https://git.codelinaro.org/clo/le/abl/tianocore/edk2/-/blob/LU.UM.3.5.1.r1-00700-QCS6490.0/QcomModulePkg/Library/FastbootLib/FastbootCmds.c)
- Cod verificat: pmbootstrap 3.11.1 (`pmb/config/__init__.py`, `pmb/flasher/frontend.py`,
  `pmb/install/_install.py`), pmaports `main/postmarketos-initramfs`
  (`init_2nd.sh`, `init_functions.sh`, `init_functions_2nd.sh`)
