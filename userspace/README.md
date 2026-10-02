# userspace: Steam pe OnePlus 8 (etapa A)

Tot ce rulează deasupra kernelului și a imaginii postmarketOS ca telefonul să pornească direct
în interfața Steam (modul Deck), cu sleep, sunet protejat, butoane și jurnal de diagnoză.
Testat pe hardware pe 2026-10-01 și 2026-10-02. Rezultatele și TODO-ul sunt în
[`../docs/gaming-stack.md`](../docs/gaming-stack.md) secțiunea 9, iar auditul în
[`../docs/performance-crash-audit.md`](../docs/performance-crash-audit.md).

Scripturile marcate *sudo* se rulează ca root pe telefon (`sudo sh <script>`); restul ca userul
normal (`gabriel`). Calea tipică: fișierele se copiază cu `scp` în `/tmp/op8-log/` și se rulează
de acolo. Niciun script nu scrie în partițiile telefonului, cu o excepție marcată explicit
(`system/format-games.sh`).

## Arhitectura, pe scurt

```
postmarketOS (musl, systemd)          containerul distrobox "steam" (Fedora 44, glibc)
├─ gamescope pe DSI-1 (DRM)  ───────► Steam ARM64 (steamdeck_publicbeta, -gamepadui -steamos3)
│   steam-gs.service (user)           ├─ Proton 11 ARM64 + FEX pentru jocurile Windows
├─ PipeWire: "Difuzoare (protejat)"   ├─ dbus-send adaptor -> logind (sleep/restart/oprire)
├─ op8-powerbtn                       ├─ op8-touchmode (touch ca pe Deck)
├─ op8-standby (in locul s2idle)      ├─ op8-buttons (volum, Vol+ + Vol- = butonul Steam)
└─ op8-log (raport la pornire,        └─ op8-mangoapp (overlay-ul de performanta)
   esantioane la 2 s)
```

## Ordinea de instalare

| # | Fișier | Ce face | Rulare |
|---|---|---|---|
| 1 | `system/stageA1.sh` | podman, distrobox, gamescope, Turnip, `vulkan-tools`; subuid; userul în grupul `input` | sudo |
| 2 | (manual) | `distrobox create --name steam --image registry.fedoraproject.org/fedora:44`, apoi pachetele din `docs/gaming-stack.md` 9 | user |
| 3 | `steam/stageA_steam.sh 1`, apoi `2` | clientul Steam ARM64 de la Valve, cu sume de control verificate, apoi auto-actualizarea lui | user, în container |
| 4 | `steam/stageA_container_setup.sh` | shim-uri SteamOS (`steamos-update` etc.) și registry cu prima configurare făcută | user, în container |
| 5 | `steam/op8-dbus-send` → `/usr/local/bin/dbus-send`, `steam/op8-priv-write` → `/usr/bin/steamos-polkit-helpers/steamos-priv-write` | adaptor sleep/restart/oprire (`...WithFlags`, ignoră blocajele SSH) și luminozitatea din Steam | `sudo install` în container |
| 6 | `system/stageA2.sh <IP-PC>` | reguli udev pentru controlere (hidraw, uinput), SSH pe WiFi doar de la PC | sudo |
| 7 | `op8-log/install.sh` | bluez, reguli controlere USB + Bluetooth, jurnalul op8-log | sudo |
| 8 | `power/install-qbootctl.sh` | **obligatoriu:** marchează slotul A/B "successful" la fiecare pornire | sudo |
| 9 | `power/install-standby.sh`, `power/install-power2.sh` | regula polkit, `op8-standby` în locul suspendării kernelului, luminozitate scriibilă de grupul `video` | sudo |
| 10 | `audio/audio-step1.sh` | `pipewire-pulse`, blocurile de filtru, legătura UCM | sudo |
| 11 | `audio/50-op8-difuzoare.conf` → `~/.config/pipewire/pipewire.conf.d/`, `audio/50-op8-wireplumber.conf` → `~/.config/wireplumber/wireplumber.conf.d/` | ieșirea protejată și formatul S16LE fără mmap | user |
| 12 | `steam/*.sh`, `steam/op8-touchmode`, `steam/op8-buttons.py`, `steam/op8-mangoapp`, `power/op8-powerbtn`, `op8-log/op8-top` → `~/`; fișierele `.service` → `~/.config/systemd/user/` | sesiunea Steam și serviciile userului | user, `systemctl --user enable --now ...` |
| 13 | `system/install-tune.sh` | polling GPU 16 ms, THP `madvise`, `CAP_SYS_NICE` pentru gamescope, `/boot` doar citire | sudo |
| 14 | în container, ca root: `dnf install python3-evdev pulseaudio-utils` | `op8-buttons.py`: butoanele de volum citite deodată, volum la eliberare și continuu la ținere, Volume Up + Volume Down = butonul Steam (Shift+Tab, pe care Steam îl înregistrează la gamescope), și în jocuri | root în container |
| 15 | `steam/build-mangoapp-gs.sh` (dependențele în antetul lui) | overlay-ul de performanță: `mangoapp` din MangoHud 0.8.4 cu ordinea câmpurilor din gamescope 3.16.29 (altfel nu apare în jocuri, gamescope #2430); îl pornește `op8-mangoapp` | user, în container |
| 16 | `system/install-thermal.sh` | `op8-thermal`: limitează nucleele mari și GPU-ul după temperatura bateriei (41-44,5 °C), plus o citire a pragurilor JEITA din PM8150B în `/var/log/op8/` | sudo |

Opțional: `system/format-games.sh` (**șterge** partiția Android `userdata` și o face ext4 pentru
jocuri, cu confirmare `FORMAT`), `system/bind-steamapps.sh` (biblioteca Steam pe acea partiție),
apoi `system/move-steam-to-games.sh` (tot directorul Steam pe acea partiție, ca Steam să vadă
spațiul ei liber; cu Steam oprit),
`system/ufs-nopm.sh` (test istoric pentru resetările din timpul descărcărilor: nu ajută, cauza
era zona de memorie rezervată lipsă, reparată în kernel cu patch-ul `0003`; nu se instalează),
`system/hide-venus.sh` / `show-venus.sh` (decodorul video hardware, pentru Remote Play).

Pe PC: `pc/op8-live.sh [ip]` salvează live jurnalul telefonului, eșantioanele și un ping în
`D:\op8-logs\` (Git Bash).

## Reguli de siguranță

- **Sunetul:** plafonul e volumul ieșirii ALSA directe ("DIRECT - nu folosi"), **-30 dB**,
  nivelul la care difuzoarele (TFA9874, fără protecție în driverul mainline) au sunat curat.
  Nu se urcă fără test. Nu se folosește `aplay` pe gazdă: acolo ALSA merge direct la hardware,
  ocolind limitatorul.
- **`apk upgrade --prune` / `--available` niciodată** pe telefon (șterg pachetele locale).
- **Sleep:** `op8-standby` nu suspendă kernelul (s2idle netestat). Trezirea: butonul de pornire;
  de rezervă `sudo touch /run/op8-wake`.

## Jurnale

| Ce | Unde |
|---|---|
| Raport la fiecare pornire (motive PON/POFF din PMIC, încărcare, pstore) | `/var/log/op8/boot-NNNN-*.txt` |
| Eșantioane la 2 s (baterie, temperaturi, frecvențe, I/O) | `/var/log/op8/current.csv` |
| Sleep, butonul de pornire | `journalctl -t op8-standby -t op8-powerbtn` |
| Butoanele de volum, butonul Steam | `~/op8-buttons.log` |
| Overlay-ul de performanță | `~/op8-mangoapp.log` |
| Comenzile de sleep/oprire ale Steam | `~/op8-dbus-send.log` |
| Modul touch | `~/op8-touchmode.log` |
| Procese la 2 s | `~/op8-top.log` |
| Crash-uri Steam (minidump) | `python3 op8-log/op8-minidump.py /tmp/dumps/crash_*.dmp`, în container |
