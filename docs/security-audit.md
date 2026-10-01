# Audit de securitate (2026-10-01)

Complementar lui [`hardware-safety.md`](hardware-safety.md), care tratează riscurile fizice.
Aici: ce poate fi exploatat sau poate scăpa (date, acces la telefon, acces la PC). Fiecare
constatare are dovada verificată și măsura recomandată. Ordinea e de la cel mai important.

## S1. Kernel ieșit din suport (ridicat)

- **Dovadă:** kernelul folosit e Xo666 6.16.7 (septembrie 2025, branch neactualizat din ianuarie
  2026). Pe kernel.org, seria 6.16 nu mai există în lista întreținută; acum sunt suportate 7.2,
  6.18 LTS, 6.12 LTS. Lipsesc deci aproximativ un an de corecturi de securitate.
- **De ce contează:** suprafața la distanță e WiFi (`ath11k`), Bluetooth și stiva de rețea; local,
  jocurile rulate prin Proton/FEX sunt cod străin care rulează pe telefon.
- **Măsuri acum:** Bluetooth oprit când nu e folosit, fără rețele WiFi publice/necunoscute,
  firewall-ul activ (vezi S2).
- **Pe termen mediu:** mutarea DTS-ului și a celor două patch-uri pe un kernel întreținut (de
  exemplu kernelul postmarketOS SM8250 7.x), **fără** driverul lui de încărcare până e reparat
  (`hardware-safety.md` 4.1).

## S2. SSH deschis pe toate interfețele, cu parolă (ridicat pe WiFi)

- **Dovadă:** firewall-ul postmarketOS blochează implicit tot ce intră (politica `drop` din
  `nftables.nft` Alpine), dar pachetul `openssh-nftrules` adaugă `tcp dport 22 accept` fără
  restricție de interfață, iar configurația pmOS pentru `sshd` setează doar `UsePAM yes`, deci
  autentificarea cu parolă rămâne activă (implicit OpenSSH).
- **Risc:** pe orice WiFi la care te conectezi, oricine din rețea poate încerca parole pe SSH.
- **Măsuri:**
  1. Parolă lungă la `pmbootstrap install` (e și parola SSH).
  2. Cheie SSH: `pmbootstrap init` se oferă să copieze cheile tale publice. După primul login
     cu cheie, pe telefon: `PasswordAuthentication no` într-un fișier din `/etc/ssh/sshd_config.d/`.
  3. Opțional, SSH doar prin cablu: înlocuiești `/etc/nftables.d/50_sshd.nft` cu o regulă care
     acceptă portul 22 doar pe `usb*`.

## S3. Protecții de kernel dezactivate (mediu)

- **Dovadă** (`op8_defconfig`): active KASLR, `STRICT_KERNEL_RWX`, `STACKPROTECTOR_STRONG`,
  PAC și BTI. **Dezactivate:** `HARDENED_USERCOPY`, `FORTIFY_SOURCE`, `INIT_STACK_ALL_ZERO`
  (de aici a pornit și bug-ul amplificatoarelor), `SLAB_FREELIST_HARDENED`, `SLAB_FREELIST_RANDOM`,
  `LIST_HARDENED`, `SECURITY_YAMA`, `SECURITY_LANDLOCK`, `MODULE_SIG`. Active și `DEBUG_FS`, `KEXEC`.
- **Măsură:** primul boot cu configurația autorului, ca să avem o referință. Apoi, într-o etapă
  separată, activăm pe rând `INIT_STACK_ALL_ZERO`, `SLAB_FREELIST_HARDENED`,
  `SLAB_FREELIST_RANDOM`, `SECURITY_YAMA`, `LIST_HARDENED`, `HARDENED_USERCOPY`,
  `FORTIFY_SOURCE`, cu test după fiecare (ultimele două pot scoate la iveală bug-uri în drivere).

## S4. Bootloader deblocat permanent, date necriptate (mediu)

- Inerent proiectului: cine are telefonul în mână poate porni sau scrie orice. Fără criptare,
  datele din pmOS (inclusiv sesiunea Steam, după ce o adaugi) se pot citi direct.
- **Măsură:** `pmbootstrap install --fde` criptează rootfs-ul. Parola se introduce la fiecare
  pornire pe ecran (tastatura `unl0kr`). Decizia e a ta: siguranță contra comoditate.
- Datele vechi din Android (`userdata`) rămân pe telefon, criptate de Android, neatinse de pmOS.

## S5. Backup-ul conține identitatea telefonului (mediu)

- `D:\backup-op8-20261001` conține EFS-ul modemului (`mdm1m9kefs1/2`, IMEI), `persist`,
  `param` și, în `getvar-all.txt`, seria telefonului. Cu ele se poate clona identitatea
  dispozitivului.
- **Măsuri:** nu-l urca necriptat în cloud. A doua copie într-o arhivă criptată (7-Zip, AES-256,
  cu parolă). În repo, `.gitignore` acoperă acum `backup*/` și `getvar*.txt`.

## S6. Pachetul MSM vine de pe un site terț (mediu)

- MSM Download Tool e un executabil Windows închis, distribuit prin AndroidFileHost, nu de
  OnePlus. Firmware-ul pe care îl scrie e verificat de lanțul de boot semnat al telefonului, dar
  executabilul rulează pe PC-ul tău.
- **Măsuri:** verifici MD5-ul cu cel din thread-ul XDA, îl scanezi pe VirusTotal, îl rulezi doar
  dacă chiar ai nevoie de el.

## S7. sudo fără parolă în WSL (scăzut)

- `/etc/sudoers.d/gabriel-nopasswd` (`gabriel ALL=(ALL) NOPASSWD:ALL`), pus pentru pmbootstrap.
  Orice proces din WSL rulat ca tine devine root fără confirmare.
- **Măsură:** după ce termini build-urile, `sudo rm /etc/sudoers.d/gabriel-nopasswd`.

## S8. Proveniența firmware-ului (scăzut)

- Verificat după amprenta git: firmware-ul GPU nesemnat (`a650_sqe.fw`, `a650_gmu.bin`) și
  `m3.bin` sunt identice cu linux-firmware oficial; `board-2.bin` e versiunea oficială din
  2022-04-23. `amss.bin` (WiFi) nu corespunde niciunei versiuni linux-firmware. Firmware-ul
  DSP și shader-ul zap sunt semnate și verificate de TrustZone. Cipul WiFi accesează memoria
  doar prin SMMU.

## S9. Ce e în regulă

- Istoricul git (16 commit-uri) nu conține seria telefonului, IMEI-uri, chei sau token-uri.
  Singura informație personală e adresa de email a autorului în metadatele commit-urilor (poate
  fi înlocuită cu adresa "noreply" GitHub pentru commit-urile viitoare).
- Toate sursele din APKBUILD-uri vin prin HTTPS și sunt fixate prin sha512 (verificat cu
  `pmbootstrap checksum --verify`).
- Driverele de pe PC (fastboot, Qualcomm 9008) sunt semnate și instalate prin Windows Update.
- Alte porturi deschise implicit de pmOS (`localsend` 53317, `ausweisapp2` 24727, mosh) nu au
  niciun serviciu care să asculte decât dacă instalezi acele aplicații.
