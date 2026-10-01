# **Arhitectura și Implementarea unui Stack de Gaming Mainline Linux pe OnePlus 8 (SM8250)**

> **Notă de verificare:** acest document a fost verificat pe 2026-08-24 față de sursele reale
> (pmaports, kernelul mainline, fork-urile comunității pentru SM8250, wiki-ul postmarketOS).
> Corecturile sunt marcate inline. Detaliile complete, cu surse, sunt în
> [`docs/verification-log.md`](docs/verification-log.md). Cea mai importantă corecție:
> "suport mainline" pentru acest telefon nu înseamnă kernel.org - înseamnă un fork întreținut
> de un singur contributor, care nu e nici măcar împachetat oficial în postmarketOS.
>
> **Corecturi 2026-10-01 (audit cu telefonul disponibil):** patch-urile de încărcare din
> acest document **nu activează încărcarea** (niciun fork, în afară de WuerfelDev, nu are
> driverul), iar driverul de încărcare din WuerfelDev și din kernelul oficial pmOS SM8250
> programează bateria la ~4.87 V. Fluxul de instalare din Secțiunea 5 a fost rescris.
> Detalii: [`docs/hardware-safety.md`](docs/hardware-safety.md) și
> [`docs/verification-log.md`](docs/verification-log.md) §9.

Transformarea unui smartphone comercial bazat pe platforma Qualcomm Snapdragon 865 (SM8250, nume de cod *kona*; codul specific de dispozitiv pentru OnePlus 8 este *instantnoodle*) într-o consolă portabilă de gaming sub un sistem de operare Linux reprezintă o lucrare de inginerie de sistem de o complexitate remarcabilă. Această tranziție implică decuplarea completă a dispozitivului de stiva proprietară Android - compusă din runtime-ul ART, serverul SurfaceFlinger, subsistemul IPC Binder, HAL-urile închise și nucleul downstream de tip CAF 4.19 - și reconstruirea mediului de execuție pe baza unui kernel Linux 6.x, pornind de la un fork comunitar dedicat SM8250 (nu de la kernelul upstream nemodificat; vezi Secțiunea 1).
Configurația hardware a terminalului OnePlus 8 include 8 GB sau 12 GB memorie RAM LPDDR5, stocare UFS 3.0, un panou Fluid AMOLED de 1080x2400 pixeli la 90 Hz și unitatea de procesare grafică Adreno 650, furnizând o bază computațională capabilă să susțină sarcini grafice complexe. Interfațarea acestui hardware cu un periferic hibrid precum GameSir X3 Pro, care asociază transportul de date USB-C Human Interface Device (HID) cu un modul activ de răcire termoelectrică Peltier, permite eliminarea plafonărilor termice severe și stabilizarea frecvențelor maxime de calcul - însă alimentarea telefonului însuși în timpul sesiunii rămâne un risc nerezolvat (Secțiunea 4).
La nivel de software, arhitectura propusă se sprijină pe driverul grafic complet open-source Mesa Turnip (Vulkan 1.3) și un lanț de execuție hibrid format din Proton 11 ARM64 și emulatorul usermode FEX-Emu, permițând rularea titlurilor Windows x86/x86_64 pe arhitectura AArch64. Compositorul folosit pentru sesiunea de gaming nu poate fi "Gamescope" ca opțiune de instalare în pmbootstrap - acel pachet nu există (Secțiunea 5); trebuie compilat separat.

## **1\. Starea Suportului de Kernel pentru SM8250 pe instantnoodle**

Suportul pentru platforma Qualcomm SM8250 există în kernelul Linux mainline (versiunile 6.6-6.17+) doar pentru o mână de plăci de referință și telefoane Xiaomi/Sony/Samsung - lista completă din `arch/arm64/boot/dts/qcom` la data verificării era `hdk`, `mtp`, `samsung-r8q`, `samsung-x1q`, `sony-xperia-edo-pdx203`, `sony-xperia-edo-pdx206`, `xiaomi-elish-{boe,csot}`, `xiaomi-pipa`. **Niciun device tree OnePlus SM8250 nu există în kernel.org**, nici pentru OnePlus 8, nici pentru 8 Pro, nici pentru 8T.

Suportul real pentru `instantnoodle` (codul OnePlus 8 standard) trăiește în cel puțin **trei**
fork-uri neoficiale, în afara pmaports și a kernelului postmarketOS oficial - și nu sunt de
acord unele cu altele:

- [`github.com/Xo666/mainline-instantnoodle`](https://github.com/Xo666/mainline-instantnoodle) (branch `6.16.7`), care conține `sm8250-oneplus-instantnoodle.dts` - acesta e device tree-ul folosit ca referință principală în acest document (vezi `reference/dts/`), pentru că e **singurul cu GPU dovedit funcțional** (zap-shader complet configurat).
- [`gitlab.com/ObiKeahloa/linux`](https://gitlab.com/ObiKeahloa/linux/-/tree/sm8250/v6.13-instantnoodle) (branch `sm8250/v6.13-instantnoodle`) - DTS-ul are `&gpu status = "okay"` **și** blocuri de override pentru `pm8150b_charger`/`pm8150b_fg` care arată `"okay"` în text, combinația cea mai apropiată de ideal pe hârtie. Dar DTS-ul **nu conține deloc un nod zap-shader** - firmware-ul semnat obligatoriu pentru GPU (Secțiunea 1, tabelul de firmware) nu are unde să fie declarat. **Mai mult, verificat 2026-08-24 prin compilare directă a sursei (nu doar citire de DTS): fork-ul, așa cum e livrat, nu se compilează deloc** - `pm8150b.dtsi` din acest fork nu definește etichetele `pm8150b_charger`/`pm8150b_fg` pe care propriile blocuri de override le țintesc, deci "încărcare funcțională" era o concluzie greșită, trasă doar din text. Un patch care rezolvă atât zap-shader-ul cât și acest gol de definiții există acum (`pmaports/linux-oneplus-instantnoodle-obikeahloa/`), compile-verificat - vezi caseta de mai jos și `docs/verification-log.md`.
- [`gitlab.postmarketos.org/WuerfelDev/linux-sm8250`](https://gitlab.postmarketos.org/WuerfelDev/linux-sm8250/-/tree/6.17.0-instantnoodle) (branch implicit `6.17.0-instantnoodle`) - acesta e fork-ul spre care indică efectiv câmpul `pmoskernel = 6.17.0` de pe wiki-ul postmarketOS, nu cele de mai sus. Are încărcare funcțională, dar **GPU-ul e dezactivat explicit în DTS** (`&gpu { status = "disabled"; }`) - vezi caseta de mai jos.

> **Cel mai important lucru de reținut din toată Secțiunea 1:** niciun fork, la data verificării,
> nu are simultan GPU dovedit funcțional, încărcare funcțională, și comutare corectă de orientare
> USB-C. Xo666 (folosit ca referință aici) are GPU dovedit și USB-C funcționale, dar zero
> încărcare. WuerfelDev și ObiKeahloa au încărcare funcțională, dar WuerfelDev are GPU dezactivat
> explicit, iar ObiKeahloa are GPU activat dar fără firmware-ul semnat declarat (deci neconfirmat).
> Cine construiește acest proiect trebuie fie să accepte lipsa de încărcare pe Xo666, fie să
> porteze manual nodurile de charger peste DTS-ul Xo666, fie să testeze dacă GPU-ul de pe
> ObiKeahloa chiar pornește. **Actualizare 2026-08-24:** prima dintre aceste opțiuni de portare
> a fost încercată - nodurile `pm8150b_charger`/`pm8150b_fg` din WuerfelDev au fost portate peste
> DTS-ul Xo666 și verificate ca se compilează curat, atât cu `dtc` direct, cât și prin pipeline-ul
> real `abuild`/`pmbootstrap` (patch la `pmaports/linux-oneplus-instantnoodle/`, detalii în
> `docs/verification-log.md`). **Asta e o verificare de compilare, nu una pe hardware real** -
> nimeni n-a confirmat încă, pe un telefon fizic, că încărcarea sau fuel gauge-ul chiar funcționează
> cu acest patch aplicat.
>
> **Corectură 2026-10-01:** nu are cum să funcționeze. Kernelul Xo666 nu conține driver pentru
> `qcom,pm8150b-charger` sau `qcom,pm8150b-fg` (verificat în arborele sursă), deci nodurile
> portate nu sunt folosite de nimic. Patch-ul a fost scos din pachetul de kernel. Același lucru
> e valabil pentru ObiKeahloa, mai jos.
>
> **Actualizare 2026-08-24 (mai târziu, aceeași zi): și direcția inversă a fost încercată, pe
> ObiKeahloa.** S-a portat zap-shader-ul de la Xo666 peste DTS-ul ObiKeahloa, ca să rezolve
> blocajul GPU-ului de acolo. La verificare prin compilare (nu doar citire de text) a ieșit la
> iveală o problemă reală, nesesizată înainte: blocurile de override `&pm8150b_fg`/`&pm8150b_charger`
> din DTS-ul ObiKeahloa există în text și arată `status = "okay"`, dar `pm8150b.dtsi` din acest
> fork **nu definește deloc** etichetele `pm8150b_charger`/`pm8150b_fg` la care se referă acele
> blocuri - fork-ul, așa cum e livrat, nu se compilează deloc (`dtc` raportează
> "Label or path pm8150b_fg not found"). Deci evaluarea de mai devreme din acest document, "are
> simultan GPU activat și încărcare funcțională", era greșită pe jumătate de încărcare, nu doar
> pe jumătatea de GPU - crezută corectă pe baza citirii textului DTS, infirmată de compilarea
> reală. Patch-ul rezultat (`pmaports/linux-oneplus-instantnoodle-obikeahloa/0001-port-zap-shader-from-xo666.patch`)
> a crescut ca să porteze și definițiile lipsă ale nodurilor de charger/fg (aceleași folosite deja
> la portarea pe Xo666), nu doar zap-shader-ul. **Rezultat: se compilează curat, atât cu `dtc`
> direct cât și prin `abuild`/`pmbootstrap` real, iar DTB-ul compilat confirmă toate trei
> - GPU zap-shader, charger, fuel gauge - rezolvate cu `status = "okay"` simultan.** Mux-ul SBU
> rămâne dezactivat pe acest fork, la fel ca pe WuerfelDev - patch-ul nu rezolvă orientarea USB-C.
> **Tot netestat pe hardware real.** Detalii complete în `docs/verification-log.md`. Acest pachet
> e experimental, un candidat suplimentar, nu kernelul implicit al proiectului - fluxul de
> instalare din Secțiunea 5 rămâne indexat pe Xo666.

Wiki-ul postmarketOS confirmă că dispozitivul boot-ează (`booting = yes`) cu 3D funcțional (`status_3d = Y`), dar îl marchează `packaged = no` și `category = testing` - adică **nu există un pachet `device-oneplus-instantnoodle` în pmaports**. Pachetele OnePlus care chiar există sunt `device-oneplus-enchilada` (6), `device-oneplus-fajita` (6T), `device-oneplus-bacon` (One), `device-oneplus-billie2` (Nord N100), `device-oneplus-guacamole` (7 Pro), `device-oneplus-instantnoodlep` (**8 Pro**) și `device-oneplus-kebab` (**8T**). OnePlus 8 standard nu e printre ele. Fluxul de instalare din Secțiunea 5 trebuie tratat ca instalare dintr-un fork, nu ca `pmbootstrap init` standard.

| Subsistem Hardware | Stare Reală (verificată pe DTS Xo666) | Modul Kernel / Arhitectură Driver | Observații Tehnice & Cerințe DTS |
| :---- | :---- | :---- | :---- |
| **Display (DSI/KMS)** | Funcțional | msm_drm, panel `samsung,amb655uv01` | O singură bandă MIPI-DSI (`mdss_dsi0`), nu două. 1080x2400 la 60/90 Hz confirmat. |
| **Touchscreen** | Funcțional | `samsung,s6sy761` la adresa 0x48 pe i2c13 | Nu e goodix și nu e synaptics_dsx - e un controller Samsung dedicat. |
| **Stocare UFS** | Funcțional | ufs_qcom | UFS 3.0 (corectat 2026-10-01: `jedec,ufs-2.0` din DTS e doar numele generic al driverului, nu versiunea cipului; pachetul MSM OnePlus conține firmware pentru cipuri UFS 3.0/3.1). |
| **USB-C OTG / USB 3.0** | Funcțional, cu quirk | qcom-pmic-typec / dwc3-qcom | Mux `fcs,fsa4480` @ 0x42 pe i2c15; comportamentul de orientare e neverificat pe hardware. |
| **USB-PD (Power Delivery) / Încărcare** | **5 W confirmată, dar doar pe fork-ul fără GPU** | `qcom,pm8150b-charger` | Nod absent complet din DTS-ul Xo666 (folosit peste tot în acest document); prezent și funcțional doar pe fork-ul WuerfelDev, care are GPU-ul dezactivat. Vezi Secțiunea 4. |
| **Audio ALSA/PipeWire** | Funcțional Condiționat | qcom-lpass / `qcom,wcd9380-codec` | Codec e WCD9380, nu WCD9385; plus 2x amplificatoare de difuzor `nxp,tfa9874` pe i2c15 (0x34 cască internă, 0x35 difuzor principal), absente din doc inițial. |
| **NFC** | Funcțional | `nxp,nxp-nci-i2c` @ 0x28 pe i2c1 | Absent complet din documentul original. |
| **Flash LED** | Funcțional | `qcom,spmi-flash-led` | Conectat prin magistrala SPMI a PMIC-ului pm8150l; absent din documentul original. |

Hardware suplimentar prezent în DTS/wiki și absent din documentul inițial: **DisplayPort alt-mode** activ pe USB-C (`&mdss_dp`), regulator `pm8150b_vbus` care poate alimenta accesorii USB (OTG sursă, 500 mA-3 A), baterie `simple-battery` de 16.37 Wh / 4270 mAh / 3.4-4.435 V, fuel gauge `ti,bq27411` pentru raportare exactă a încărcării, NFC și flash LED (ambele de mai sus). Camera frontală (`sony,imx471`) e prezentă; **camera spate (imx586) lipsește din DTS-ul auditat și e marcată doar parțial pe wiki**.

> **Notă despre versiuni de kernel:** device tree-ul auditat local (`reference/dts/`, fork Xo666, branch `6.16.7`) nu conținea niciun nod de charger, ceea ce a dus inițial la concluzia greșită "încărcarea nu e confirmată". Wiki-ul postmarketOS declară însă `pmoskernel = 6.17.0` - un snapshot de kernel mai nou (fork WuerfelDev), care evident include nodul de charger. Tratați `reference/dts/` ca fiind cu o versiune în urmă față de ce rulează efectiv wiki-ul pe acest punct.

Cunoscute ca nefuncționale, conform wiki-ului: modem (`sdx55m`), senzori (nodul `slpi` se încarcă dar nu e configurat), haptice (`awinic,aw8697`), camera spate. Pentru un handheld dedicat, niciuna dintre acestea nu contează, cu excepția hapticelor - o pierdere de confort, nu una funcțională.

### **Subsistemul de Afișare DRM/KMS și Panoul MIPI-DSI**

Afișajul AMOLED al dispozitivului OnePlus 8 este conectat printr-o **singură** bandă MIPI-DSI (`mdss_dsi0`) la unitatea DPU (Display Processing Unit) din cadrul nucleului DRM MSM - documentul original vorbea greșit de două benzi. Panoul declarat în DTS este `samsung,amb655uv01`. În timp ce infrastructura generică DRM/KMS gestionează operațiunile atomice de comutare a modului grafic, panoul fizic impune declararea în Device Tree a secvențelor exacte de inițializare DCS (Display Command Set), extrase din ramurile CAF sau firmware-ul OxygenOS.
Fără aceste tabele de comenzi, regulatorii de tensiune LDO asociați panoului nu pot stabili timpii de sincronizare corecți la trecerea dinspre bootloader-ul ABL către kernel. În plus, configurarea modului de 90 Hz necesită setarea explicită a frecvențelor ceasului de bit DSI și a parametrilor Display Stream Compression (DSC), ocolind limitările de lățime de bandă ale interfeței fizice. Rezoluția 1080x2400 la 60/90 Hz e confirmată atât în DTS, cât și pe wiki.

### **Touchscreen și Stocare UFS**

Digitizorul tactil nu folosește driverele goodix sau synaptics presupuse inițial. Device tree-ul verificat declară un controller **`samsung,s6sy761`** pe magistrala I²C13, la adresa 0x48, expunând fluxurile de coordonate prin nodurile /dev/input/eventX standard.
Subsistemul de stocare este gestionat prin driverul ufs\_qcom. Stocarea e UFS 3.0, cum spune și fișa tehnică. Corectat 2026-10-01: o versiune anterioară a acestui document afirma "UFS 2.0" pe baza textului `jedec,ufs-2.0` din DTS, care e doar numele generic al driverului Linux pentru orice versiune UFS; pachetul MSM OnePlus pentru acest telefon conține firmware pentru cipuri UFS 3.0 și 3.1.

### **Limitări Hardware Critice pe USB-C și Power Delivery**

Managementul portului USB Type-C pe OnePlus 8 prezintă riscuri structurale în contextul andocării controllerului de joc:

> 1. Quirk-ul de multiplexare SuperSpeed: pe placă există un mux dedicat `fcs,fsa4480` (adresa 0x42, pe i2c15) pentru liniile SBU, prezent în DTS. Comportamentul lui exact la orientare inversă a conectorului nu a fost testat pe hardware real (marcat **OPEN** în log-ul de verificare) - tratați presupunerea de mai jos ca ipoteză, nu ca fapt confirmat: liniile USB 3.0 (5 Gbps) s-ar activa exclusiv dacă orientarea raportată în /sys/class/typec/port0/orientation indică starea normală (*normal*), iar la inserare inversă subsistemul ar cădea în USB 2.0 (480 Mbps). Lățimea de bandă USB 2.0 e oricum suficientă pentru HID.
> 2. **Nodul de charger lipsește pe fork-ul folosit pentru GPU.** `qcom,pm8150b-charger` funcționează, confirmat, la 5 W - dar pe fork-ul WuerfelDev, care are GPU-ul dezactivat. Pe Xo666 (referința acestui document), nodul nu există deloc. Presupunerea documentului original, că problema ar fi o "mașină de stări instabilă" la comutarea sink/source, nu are confirmare pe niciun fork - problema reală, acolo unde încărcarea există, e alta: 5 W e sub consumul de sistem în joc (8-11 W), nu o eroare de negociere. Încărcarea rapidă Warp (`oplus,stm8s-fastcg`) rămâne neimplementată peste tot. `pm8150b_typec` (prezent pe Xo666) declară PDO-uri de sink de 5V/3A fix plus 5-12V variabil, fără driver de charger în spate. Analiza completă e în Secțiunea 4.

### **Arhitectura Audio: DSP Hexagon, ALSA și PipeWire**

Codecul audio declarat în DTS este **`qcom,wcd9380-codec`**, nu WCD9385 cum spunea documentul original, plus **două amplificatoare de difuzor `nxp,tfa9874`** pe i2c15 - componentă absentă complet din varianta inițială a documentului. Rutarea fluxurilor audio digitale se bazează pe subsistemul LPASS (Low Power Audio Subsystem) și pe procesorul de semnal digital Hexagon (ADSP). Funcționarea stabilă a stivei audio impune plasarea imaginilor de firmware proprietare extrase (`adsp.mbn`, `cdsp.mbn`) în directorul de sistem **`/lib/firmware/qcom/sm8250/OnePlus/`** - documentul original omitea subdirectorul `OnePlus/`, iar fără el firmware loader-ul din kernel nu găsește fișierele.
La nivelul spațiului utilizator, este obligatorie definirea profilelor ALSA UCM2 (Use Case Manager), care descriu căile corecte ale mixerului hardware. Fără aceste fișiere UCM2, serverul de sunet PipeWire nu poate deschide rutele către difuzoarele stereo sau interfața jack/USB-C, generând blocaje în fluxul audio al jocurilor rulate sub Proton.

### **Firmware Proprietar Necesar**

GPU-ul (`&gpu`) nu se inițializează fără shader-ul lui semnat, deci acesta e o precondiție dură pentru întregul stack grafic. Toate cele cinci blob-uri trebuie extrase dintr-o imagine OxygenOS și plasate în `/lib/firmware/qcom/sm8250/OnePlus/`:

> **Scurtătură posibilă:** [`github.com/Xo666/linux-oneplus-instantnoodle`](https://github.com/Xo666/linux-oneplus-instantnoodle)
> (un alt repo al aceluiași autor, separat de fork-ul de kernel) conține exact aceste blob-uri
> deja extrase, plus profile ALSA UCM2. Două atenționări înainte de a-l folosi: fișierele sunt
> puse sub `qcom/sm8250/OnePlus8/` (cu cifră), dar DTS-ul le caută la `qcom/sm8250/OnePlus/`
> (fără cifră) - trebuie redenumit sau simlink-uit directorul; și sunt blob-uri proprietare
> Qualcomm/OnePlus redistribuite pe un repo public fără licență declarată - statutul legal e
> neclar, chiar dacă practic e mai simplu decât extragerea manuală dintr-un dump OxygenOS.

| Blob | Rol | Consecință dacă lipsește |
| :---- | :---- | :---- |
| `a650_zap.mbn` | Zap shader GPU (semnat) | **Fără GPU. Proiectul se oprește aici.** |
| `adsp.mbn` | DSP audio | Fără sunet |
| `cdsp.mbn` | DSP de calcul | Fără offload de calcul |
| `venus.mbn` | Decodare video | Fără decodare video hardware |
| `slpi.mbn` | DSP senzori | Fără senzori (oricum nefuncțional) |

În plus, din `linux-firmware` (deschis, nu specific dispozitivului): `a650_sqe.fw`, `a650_gmu.bin`, firmware WiFi ath11k QCA6390 și firmware Bluetooth QCA. Toate acestea pot fi obținute fără a avea telefonul la îndemână - un dump al pachetului de update OxygenOS e suficient.

## **2\. Arhitectura Grafică & Drivere Vulkan (Adreno 650\)**

Arhitectura grafică a dispozitivului se sprijină integral pe driverul open-source Vulkan **Mesa Turnip**, asociat compilatorului de shadere freedreno/ir3 și driverului de kernel Direct Rendering Manager msm17. Această stivă asigură o implementare complet conformă a standardului Vulkan 1.3, ocolind în totalitate limitările driverului proprietar Qualcomm11.

### **Compatibilitate Vulkan 1.3 și Extensii Fundamentale**

Pentru a susține translatarea dinamică a straturilor Direct3D către Vulkan și compunerea cadrelor la nivel de display server, Turnip implementează un set critic de extensii17:

* VK\_EXT\_custom\_border\_color: Necesară pentru emulatorul DXVK în vederea reproducerii fidele a modurilor de adresare a texturilor și a eșantionării specifice API-urilor D3D9 și D3D1117.  
* VK\_EXT\_graphics\_pipeline\_library (GPL): Permite compilarea modulară și asincronă a stărilor de pipeline grafic (vertex input, pre-rasterization, fragment output), eliminând aproape în totalitate fenomenul de micro-întrerupere (*shader stutter*) specific jocurilor PC la prima încărcare a activelor11.  
* VK\_EXT\_descriptor\_buffer și VK\_KHR\_dynamic\_rendering: Elimină structurile rigide de tip *descriptor sets* și *render passes*, aliniind stiva Vulkan direct la modelul de execuție D3D12 gestionat de VKD3D-Proton18.  
* VK\_EXT\_image\_drm\_format\_modifier: Punctul structural central pentru integrarea cu un compositor Wayland care face scanout direct. Această extensie permite crearea de imagini Vulkan asociate cu modificatori liniari sau compresați (UBWC \- Universal Bandwidth Compression), facilitând exportul direct de buffere DMABUF către planurile hardware ale afișajului prin modul *Direct Display Scanout*, fără copieri redundante în memoria de sistem.

### **Microarhitectura TBDR: Tiled GMEM vs. Sysmem Rendering**

GPU-ul Adreno 650 este construit în jurul unei arhitecturi TBDR (*Tile-Based Deferred Rendering*)21. Procesorul conține o memorie SRAM internă ultra-rapidă denumită **GMEM**, cu o capacitate fizică de 1024 KB21.  
În modul implicit bazat pe GMEM, cadrul grafic este divizat în blocuri spațiale (*tiles*), iar rasterizarea și operațiunile de adâncime/amestecare (*depth/blending*) sunt executate exclusiv în memoria locală de pe cip, minimizând tranzacțiile de date cu memoria RAM LPDDR521.  
Tranziția către modul direct (*Sysmem Rendering*), în care geometria este randată direct în memoria principală de sistem, devine necesară în scene complexe cu tehnici masive de iluminare amânată (*Deferred Shading*), ray-marching sau treceri computaționale frecvente ce invalidează datele din GMEM21.  
Deși forțarea modului direct prin variabila de mediu TU\_DEBUG=sysmem poate fi utilă pentru depanare, cele mai recente versiuni de Mesa utilizează un subsistem euristic de autotuning care comută dinamic între GMEM și Sysmem la nivel de *render pass*, maximizând rata de cadre11.

### **Compilarea Shaderelor și Optimizările IR3**

Procesul de transformare a instrucțiunilor grafice parcurge un lanț multistadial structurat:

> 1. Formatul intermediar original (DirectX Shader Bytecode \- DXBC sau DXIL) este interceptat de DXVK sau VKD3D-Proton și convertit în reprezentare standardizată SPIR-V.  
> 2. Compilatorul din Mesa Turnip parsează codul SPIR-V și îl transpune în reprezentarea intermediară proprie Mesa (NIR), unde se aplică optimizări algebrice, eliminarea instrucțiunilor moarte și simplificarea fluxului de control17.  
> 3. Backend-ul freedreno/ir3 transformă instrucțiunile NIR în cod mașină optimizat pentru arhitectura ISA Adreno 6xx, alocând registrele fizice și generând pachetele de instrucțiuni executabile pe unitățile ALUs ale GPU-ului17.

Pentru a preveni degradarea performanței cauzată de recompilările frecvente, sistemul trebuie configurat cu MESA\_SHADER\_CACHE\_DISABLE=false și MESA\_SHADER\_CACHE\_MAX\_SIZE=512MB, stocând binarele IR3 compilate direct pe discul UFS21.  
Asocierea acestor setări cu opțiunea dxvk.enableAsync \= true permite delegarea sarcinilor de compilare către nucleele de eficiență Cortex-A55, eliberând nucleele mari Cortex-A77 pentru logica jocului și emularea CPU2.

## **3\. Integrarea Proton 11 ARM64 & FEX-Emu**

> **Confirmat:** Proton 11 ARM64 e real și livrat public. Proton 11.0-1 Beta 3 (mai 2026) vine cu
> FEX-2604, iar FEX 2608 a apărut ca release lunar curent în august 2026. Tot efortul e împins
> de **Steam Frame**, dispozitivul Valve cu Snapdragon 8 Gen 3 și SteamOS - un GPU din aceeași
> familie Adreno a6xx, cu același driver Turnip ca pe Adreno 650. Valve publică și instrucțiuni
> oficiale de build ARM64 pentru Proton.

Tranziția de la platformele x86\_64 tradiționale la arhitectura ARM64 pentru jocuri Windows complexe este asigurată de **Proton 11 ARM64**, care integrează nativ recompilatorul binar usermode **FEX-Emu**9.

### **Modelul de Execuție Hibrid: ARM64EC și Redirecționarea (Thunking)**

Spre deosebire de tehnicile brute de virtualizare completă, care emulează întregul sistem de operare inducând pierderi masive de performanță, Proton 11 folosește modelul de interoperabilitate **ARM64EC** (*Emulation Compatible*)9. Această abordare permite combinarea codului nativ AArch64 cu segmente de cod x86/x86\_64 translatate în interiorul aceluiași spațiu de adrese al procesului10.  
Recompilatorul FEX-Emu preia exclusiv instrucțiunile mașină x86/x86\_64 ale jocului și le traduce în instrucțiuni AArch64 prin intermediul unui motor JIT (*Just-In-Time*)10. FEX utilizează o reprezentare intermediară ce gestionează eficient vectorizarea registrelor SSE/AVX și emulează semantica de memorie TSO (*Total Store Ordering*), obligatorie pentru sincronizarea firelor de execuție în jocurile concepute pentru procesoare Intel/AMD10.  
În paralel, bibliotecile fundamentale Wine, apelurile Win32, subsistemul de gestionare a memoriei și translatatoarele DXVK/VKD3D sunt compilate complet nativ pentru arhitectura ARM6410.  
Prin intermediul tehnologiei de redirecționare (*Vulkan Thunking*), apelurile interceptate la nivel de vulkan-1.dll ocolesc complet motorul de emulare CPU și sunt transmise direct către driverul nativ din sistemul gazdă (libvulkan\_freedreno.so)10. În acest mod, instrucțiunile de randare și încărcare a texturilor se execută la viteză nativă pe GPU-ul Adreno 65010.

### **Etape de Configurare în Steam Client ARM64**

Pentru activarea stivei de compatibilitate în clientul oficial Steam ARM64, este necesară respectarea unei succesiuni riguroase de configurare29:

> 1. **Amplasarea Structurii Proton:** Lanțul de binare Proton 11 ARM64 trebuie extras sau compilat în directorul utilizator dedicat:\~/.local/share/Steam/compatibilitytools.d/proton\_11\_arm64/  
>    \[cite: 29, 30\]  
> 2. **Declararea Fișierului toolmanifest.vdf:** Clientul Steam citește manifestul de compatibilitate pentru a determina containerul de execuție (*Pressure-Vessel* / *SteamRT4*)25:  
>    Fragment de cod  
>    "manifest"  
>    {  
>      "commandline" "/proton run"  
>      "version" "11.0-arm64"  
>      "use\_steam\_runtime" "1"  
>      "compatmanager\_layer\_name" "proton\_arm64"  
>    }

> 3. **Setarea Variabilelor de Mediu Globale:** Pentru a preveni coliziunea driverelor și a forța încărcarea corectă a bibliotecilor grafice native, se exportă următorii parametri:  
   * VK\_ICD\_FILENAMES=/usr/share/vulkan/icd.d/freedreno\_icd.aarch64.json: Asigură utilizarea exclusivă a driverului Mesa Turnip22.  
   * FEX\_CONFIG\_JSON=/etc/fex-emu/Config.json: Definește opțiunile de recompilare JIT, permițând dezactivarea emulării stricte a coprocesorului matematic x87 pe 80 de biți pentru a obține un spor de până la 15% în jocurile pe 32 de biți10.  
   * PRESSURE\_VESSEL\_SHARE\_HOME=1: Permite containerului Steam să acceseze driverele și socket-urile DRM/Wayland din sistemul de operare gazdă.

> **Ce lipsește din pașii de mai sus:** clientul Steam ARM64 nu e produsul finit "client Steam Frame" -
> e un build automat, nepromovat, pe care Valve nu îl anunță oficial. Conform investigației
> detaliate a lui Drakulix pe postmarketOS, clientul e "total inconștient" că rulează pe ARM64 și
> încearcă implicit să lanseze un runtime x86_64. SteamLinuxRuntime 4.0 și Proton pentru arm64
> chiar există ca build-uri Valve, dar clientul nu le descarcă automat. Depozitul Proton arm64
> **nu conține `toolmanifest.vdf`** - de aceea pasul 2 de mai sus e necesar, nu opțional. Ca să
> funcționeze cu adevărat, mai trebuie: SteamRT4 arm64 folosit ca runtime propriu al clientului,
> un `steam-runtime-launcher-service` pornit pe un nume de bus dedicat, și un shim `fexwrap` care
> injectează FEX și driverele grafice în invocarea `bwrap` a pressure-vessel. Recomandat: build-ul
> `steamdeck_stable`, nu `publicbeta` - primul păstrează comportamentul specific Deck. E fezabil,
> dar e muncă manuală de asamblare, nu o instalare standard - cel mai probabil loc unde proiectul
> se poate bloca.

## **4\. Managementul Termic, Energetic și Subsistemul de Input**

Sarcina combinată de recompilare binară continuă (FEX-Emu), translatare Direct3D-Vulkan (DXVK) și randare grafică 3D generează o putere disipată susținută între 8 W și 11 W, o valoare ce depășește capacitatea de disipare pasivă a carcasei OnePlus 87.

### **Topologia SM8250 și Comportamentul la Throttling**

SoC-ul Qualcomm Snapdragon 865 integrează o arhitectură tri-cluster pe 64 de biți1:

* **1x Kryo 585 Prime (Cortex-A77)** tactat până la 2.84 GHz cu 512 KB L2 cache1.  
* **3x Kryo 585 Gold (Cortex-A77)** tactate până la 2.42 GHz cu câte 256 KB L2 cache1.  
* **4x Kryo 585 Silver (Cortex-A55)** tactate până la 1.80 GHz cu câte 128 KB L2 cache1.  
* **GPU Adreno 650** tactat la maximum **587 MHz**. Documentul original dădea 670 MHz ca treaptă de boost -
  acela e ceasul GPU-ului de pe Snapdragon **865+**, nu de pe 865-ul simplu din acest telefon. Diferența
  contează: toate estimările de performanță din Secțiunea 5 care presupun 670 MHz sunt optimiste cu
  aproximativ 12% față de ce poate acest chip.

În regim pasiv, acumularea termică declanșează intervenția driverului de kernel qcom-spmi-temp-alarm la depășirea temperaturii de 70-75 °C pe senzorii joncțiunii de siliciu. Mecanismul de throttling reduce sever frecvența nucleului Prime sub 1.40 GHz, iar GPU-ul coboară la 305 MHz, prăbușind frecvența de cadre și generând blocaje masive.

### **Răcirea Activă Peltier (GameSir X3 Pro)**

Modulul termoelectric integrat în GameSir X3 Pro aplică o celulă Peltier (TEC) direct pe suprafața din sticlă a panoului posterior, disipând căldura printr-un radiator de aluminiu ventilat la turație înaltă7.  
La un consum exterior de aproximativ 10-12 W dedicat exclusiv răcirii, temperatura joncțiunii de siliciu sub sarcină maximă scade și se stabilizează în intervalul 45-52 °C7.  
Această extracție continuă de căldură modifică radical comportamentul guvernatorului de frecvență CPU (schedutil sau performance):

* Nucleele Kryo 585 Prime (2.84 GHz) și Gold (2.42 GHz) își mențin frecvențele maxime fără întrerupere pe parcursul sesiunilor prelungite de joc1.  
* Planificatorul de procese din kernel nu mai este forțat să migreze firele intensive de execuție ale FEX-Emu către nucleele lente Cortex-A55, păstrând latența de execuție la un nivel minim.  
* GPU-ul Adreno 650 rămâne blocat la ceasul lui maxim real de 587 MHz, eliminând variațiile bruște de frametime cauzate de limitarea termică a alimentării.

Important: coolerul Peltier trage cei 10-12 W direct de la încărcătorul de perete, nu din bateria
telefonului - deci jumătatea de răcire a acestui argument rămâne validă indiferent de ce se
întâmplă cu stiva de încărcare a telefonului. Jumătatea de alimentare e altă poveste, tratată
separat mai jos.

### **Alimentare în timpul sesiunii: rezolvată pe hârtie, dar pe fork-ul greșit**

Documentul original presupunea că telefonul se încarcă prin controller (*pass-through power*) cât
timp Peltier-ul răcește, susținând sesiuni "nelimitate". Nodul de charger chiar există și
funcționează - dar nu pe fork-ul (Xo666) folosit ca referință în restul acestui document pentru că
e singurul cu GPU confirmat. Există pe **WuerfelDev**, fork-ul spre care indică efectiv wiki-ul
postmarketOS - și care are GPU-ul dezactivat explicit în DTS. Detaliile:

* **Încărcarea de bază funcționează, confirmat, la 5 W**, prin `qcom,pm8150b-charger` - dar doar pe
  device tree-ul WuerfelDev (`6.17.0-instantnoodle`), unde nodul are `status = "okay"` și e conectat
  la canalele ADC corecte. **Pe Xo666, acest nod nu există deloc.**
* **Doar încărcarea rapidă Warp e confirmat absentă, pe ambele fork-uri**: `oplus,stm8s-fastcg`
  (5V/6A) - "currently no driver exists", per wiki; nodul apare, dezactivat, și pe WuerfelDev.
* **Fork-ul cu încărcare are GPU-ul dezactivat.** `&gpu { status = "disabled"; }` în DTS-ul
  WuerfelDev, necondiționat - ceea ce contrazice direct `status_3d = Y` de pe wiki. Practic:
  telefonul care se încarcă, momentan, nu randează nimic pe acel kernel. Nu se știe dacă e o stare
  temporară (kernel în lucru, cineva a dezactivat GPU-ul pentru depanare) sau o regresie permanentă.
* La un consum de sistem de 8-11 W sub sarcină, contra unei intrări de 5 W (pe fork-ul care oferă
  ambele), deficitul net ar fi de 3-6 W. Pe o baterie de 16.37 Wh, calculul ar da aproximativ
  **2.7-5.5 ore de joc cu baterie în scădere lentă** - dar acest calcul descrie o configurație care,
  la data verificării, nu există ca atare pe niciun fork nemodificat.
* **Ce înseamnă practic:** fie acceptați Xo666 fără încărcare (jocul funcționează, dar telefonul se
  descarcă normal, fără nicio compensare din priză), fie cineva trebuie să porteze manual nodurile
  `pm8150b_charger` / `pm8150b_fg` din WuerfelDev peste DTS-ul Xo666 - o muncă de merge, nu o
  configurare.
* **Corectură 2026-10-01:** portarea descrisă mai jos a adus doar noduri de device tree, fără
  driver, deci nu activează încărcarea; a fost scoasă. Driverul existent în WuerfelDev și în
  kernelul oficial pmOS SM8250 are un bug grav (tensiune maximă de încărcare ~4.87 V în loc de
  4.435 V, confirmat independent pe alt dispozitiv SM8250) și nu trebuie portat așa cum e. Vezi
  `docs/hardware-safety.md`, 4.1.
* **Actualizare 2026-08-24: portarea a fost încercată.** Există acum un patch
  (`pmaports/linux-oneplus-instantnoodle/0001-port-charger-fg-from-wuerfeldev.patch`) care aduce
  nodurile `pm8150b_charger` și `pm8150b_fg`, plus canalele ADC pe care le folosesc, din WuerfelDev
  peste DTS-ul Xo666, fără să atingă nodul `&gpu` sau zap-shader-ul. S-a verificat că se compilează
  curat cu `dtc` (zero avertismente pe nodurile schimbate) și că pachetul chiar se construiește prin
  `abuild`/`pmbootstrap` cu patch-ul aplicat automat. **Nimic din asta nu a fost testat pe un telefon
  real** - nu se știe dacă driverul de charger sau fuel gauge chiar pornesc, dacă valorile ADC sunt
  corecte pe acest hardware, sau dacă adăugarea nodurilor interferează cumva cu GPU-ul la runtime
  (verificarea de mai sus arată doar că textul zap-shader-ului rămâne neschimbat în DTB-ul compilat,
  nu că interacțiunea la rulare e sigură). Detalii complete în `docs/verification-log.md`.

Remediile propuse inițial trebuie tratate cu scepticism:

* Fixarea profilului PD la 5V/3A prin patch DTS - DTS-ul deja declară exact acest profil; nu există
  dovadă că asta ar fi problema. Problema reală nu e o negociere eșuată, ci pur și simplu 5 W sub
  consumul de sistem în joc.
* Comanda `echo 0 > /sys/class/power_supply/battery/charging_enabled` - acesta e un nod **sysfs
  downstream** (Android/CAF), care nu există în kernelul mainline. `power_supply` din mainline expune
  în schimb `charge_control_limit` / `input_current_limit`. Comanda de mai sus va eșua aproape sigur.

**Cifrele de 5 W și deficitul de 3-6 W rămân proiecții, nu măsurători** - de confirmat cu telefonul
fizic în mână, pe o configurație care încă nu există: cea mai mare necunoscută reală a proiectului
nu mai e nici încărcarea, nici plumbing-ul clientului Steam ARM64 (Secțiunea 3) - e dacă nodurile
de charger din WuerfelDev pot fi portate peste DTS-ul Xo666 fără să strice GPU-ul sau mux-ul USB-C.

### **Arhitectura Subsistemului de Input**

Compositorul folosit pentru sesiunea de gaming (fie el un micro-compositor Wayland dedicat, fie
un mediu minimal) preia controlul direct asupra dispozitivului DRM Master (/dev/dri/card0) prin
subsistemul KMS, eliminând complet necesitatea unui server de afișare X11 tradițional sau a unui
mediu desktop complet. Interfațarea controllerului GameSir X3 Pro prin mufa Type-C se realizează
direct la nivel de kernel prin driverul generic hid-generic, creând un nod de evenimente în
/dev/input/eventX. Prin biblioteca libinput, pachetele binare HID brute sunt monitorizate și
interceptate direct din subsistemul evdev.
Evenimentele de axă și butoane sunt transpuse intern în apeluri standardizate specifice interfeței
Linux Gamepad API / SDL2, fiind injectate transparent în procesul Proton prin nodul virtual
/dev/uinput. Această arhitectură fără intermediari asigură o latență de intrare extrem de redusă
(< 2 ms) și garantează maparea instantanee a comenzilor în jocurile Windows cu suport nativ XInput.

## **5\. Ghid de Implementare, Benchmarks Așteptate & Managementul Riscurilor**

Desfășurarea stivei de operare necesită pregătirea partițiilor fizice UFS, compilarea imaginilor personalizate și flash-uirea acestora prin intermediul instrumentelor de nivel scăzut. Nota importantă, detaliată în Secțiunea 1: nu există un pachet `device-oneplus-instantnoodle` oficial în pmaports, deci fluxul standard `pmbootstrap init` cu codename `instantnoodle` **nu funcționează ca atare**. Pașii de mai jos presupun construirea dintr-un fork comunitar (Xo666 sau ObiKeahloa), integrat manual în arborele pmaports local sau compilat independent.

### **Fluxul Pas cu Pas de Instalare (dintr-un fork comunitar SM8250)**

> **Corectat 2026-10-01, cu telefonul disponibil.** Varianta anterioară a acestui flux avea
> erori care l-ar fi blocat sau ar fi dus în eroare: `pmbootstrap install --split` nu e
> compatibil cu `pmbootstrap flasher flash_rootfs` pe metoda `fastboot` (verificat în codul
> pmbootstrap 3.11.1), comanda `pmbootstrap flasher flash_boot` nu există pentru această
> metodă, combinația de taste pentru fastboot era greșită, lipsea pasul "Deblocare OEM", iar
> vbmeta era prezentat ca obligatoriu deși porturile oficiale 8 Pro și 8T nu îl scriu.
> Procedura completă, cu backup, comenzi exacte și teste: [`docs/hardware-safety.md`](docs/hardware-safety.md).

> 0. **Pregătire și backup complet, înainte de orice scriere** (`docs/hardware-safety.md`,
>    secțiunile 1-2): verificați modelul (IN2013/IN2015/IN2011/IN2010; IN2019 Verizon nu se
>    poate debloca, IN2017 T-Mobile cere token), descărcați pachetul MSM Download Tool pentru
>    regiunea voastră, salvați datele personale, apoi faceți backup la **toate** partițiile în
>    afară de `userdata` (inclusiv `super`, `persist` și partițiile EFS/IMEI) și verificați
>    backup-ul cu `sha256sum`.
> 1. **Deblocarea bootloader-ului:** Opțiuni dezvoltator > Deblocare OEM activat. Fastboot:
>    telefon oprit, **Volum Sus + Volum Jos + Power**. Apoi `fastboot flashing unlock`
>    (șterge toate datele).
> 2. **Kernelul:** pachetul `pmaports/linux-oneplus-instantnoodle/` din acest repo (fork-ul
>    Xo666, branch `6.16.7`, singurul cu GPU confirmat funcțional, plus două patch-uri de
>    siguranță). Directoarele din `pmaports/` se copiază în `device/testing/` dintr-o copie
>    locală a pmaports. **Nu folosiți** fork-ul WuerfelDev sau kernelul oficial pmOS SM8250
>    pe acest telefon: driverul lor de încărcare programează bateria la ~4.87 V
>    (`docs/hardware-safety.md`, 4.1).
> 3. **Inițializarea mediului:** `pmbootstrap init` cu pmaports-ul local, dispozitiv
>    `oneplus-instantnoodle`. **Interfața "gamescope" nu există ca opțiune** - lista reală din
>    pmbootstrap conține buffyboard, cage, console, cosmic, fbkeyboard, gnome, gnome-mobile,
>    i3wm, kodi, lomiri, lxqt, mate, moonlight, niri, openbox, phosh,
>    plasma-bigscreen/desktop/mobile, retroarch, shelli, sway, sxmo, weston, windowmaker, xfce4.
>    Cea mai apropiată alegere gata făcută e `retroarch` sau `moonlight`; un compositor de
>    gaming dedicat trebuie ambalat separat sau se alege `none` și se pornește manual după boot.
> 4. **Generarea imaginilor:** `pmbootstrap install` (**fără** `--split`), apoi
>    `pmbootstrap export`. Rezultă `boot.img`, `dtbo.img` și `oneplus-instantnoodle.img`
>    (rootfs-ul cu partițiile interioare pmOS_boot și pmOS_root, în format sparse).
> 5. **Scrierea partițiilor** (din Windows, cu `fastboot.exe`, pentru că WSL2 nu vede USB-ul):
>    ```
>    fastboot getvar current-slot
>    fastboot getvar partition-size:super
>    fastboot flash dtbo dtbo.img
>    fastboot flash boot boot.img
>    fastboot flash super oneplus-instantnoodle.img
>    fastboot reboot
>    ```
>    Din WSL, echivalentul este `pmbootstrap flasher flash_dtbo`, `flash_kernel` și
>    `flash_rootfs` (cu `usbipd-win`). Bootloader-ul refuză o imagine mai mare decât partiția
>    înainte de orice scriere (implementarea de referință Qualcomm ABL), deci scrierea în
>    `super` nu poate atinge alte partiții sau GPT-ul. vbmeta se scrie doar dacă
>    bootloader-ul refuză imaginea de boot.
> 6. **Primele teste**, înainte de orice joc: `docs/hardware-safety.md`, secțiunea 4
>    (încărcare, difuzoare, regulatoare, temperaturi, sloturi A/B).
>
> Despre `deviceinfo_super_partitions`: corectat 2026-10-01. Câmpul nu e citit de
> `pmbootstrap`, dar **este** citit de initramfs-ul de pe telefon (`init_2nd.sh`), care încearcă
> să mapeze partițiile logice Android din partițiile listate. Cu rootfs-ul scris direct peste
> `super` nu există partiții logice de mapat, așa că a fost scos din `deviceinfo`; initramfs-ul
> găsește imaginea pmOS din `super` oricum, scanând toate partițiile.

Pachetele `fex`, `proton`, `steam` și `box64` **nu există deloc în pmaports** - toată stiva de gaming din userspace e muncă neambalată, de făcut manual sau prin scripturi proprii.

> **Verificat fără telefon (2026-08-24):** sursa kernelului Xo666 chiar compilează. Cross-compilare
> directă (fără pmbootstrap) cu `aarch64-linux-gnu-gcc 13.3.0` pe Ubuntu 24.04/WSL2, folosind
> `op8_defconfig` (defconfig-ul specific OnePlus 8 din acest fork), a produs `Image.gz` (15.2 MB)
> și `sm8250-oneplus-instantnoodle.dtb` compilat fără erori, în 5m30s. Asta confirmă că sursa e
> internă consistentă și compilabilă - nu confirmă că pornește pe telefon, nici că shader-ul GPU
> chiar se încarcă. Detalii complete și pachete draft pmaports (`device-oneplus-instantnoodle`,
> `linux-oneplus-instantnoodle`, construite ulterior prin `abuild`/`pmbootstrap`) în `docs/verification-log.md` §7.5 și
> directorul `pmaports/`.

### **Estimări de Performanță și Benchmarks Așteptate**

> **Tratați acest tabel ca plafon superior, nu ca măsurătoare.** Cifrele de mai jos sunt proiecții, nu
> benchmark-uri reale rulate pe hardware, și presupun un GPU la 670 MHz - ceas pe care acest chip
> (865 simplu, nu 865+) nu îl atinge; plafonul real e 587 MHz. Asta le face optimiste cu aproximativ
> 12%, înainte de a lua în calcul overhead-ul de translatare FEX, care e necunoscuta mai mare dintre
> cele două.

Performanța atinsă combină eficiența recompilatorului JIT FEX-Emu, execuția nativă a straturilor Wine/DXVK și capacitățile de calcul ale GPU-ului Adreno 650. Utilizarea unui motor de upscaling gen AMD FidelityFX Super Resolution (FSR) în compositor permite reducerea rezoluției interne de randare la 720p cu scalare reconstructivă la 1080p, optimizând masiv rata de cadre.

| Titlu Joc | API Grafic / Rută Translatare | Rezoluție Răndare / Scalare | Rata Medie de Cadre (FPS) | 1% Lows (FPS) | Consum Mediu Energetic |
| :---- | :---- | :---- | :---- | :---- | :---- |
| **Hades** | Direct3D 11 / DXVK | 1080p Nativ (Fără FSR) | 75-90 FPS | 60 FPS | ≈ 5.5 W |
| **Fallout: New Vegas** | Direct3D 9 / DXVK 1.10.3 | 1080p Nativ / High | 50-60 FPS | 42 FPS | ≈ 6.8 W |
| **The Elder Scrolls V: Skyrim SE** | Direct3D 11 / DXVK 2.x | 720p → 1080p (FSR) | 40-52 FPS | 30 FPS | ≈ 8.5 W |
| **Grand Theft Auto V** | Direct3D 11 / DXVK 2.x | 720p → 1080p (FSR) | 32-45 FPS | 24 FPS | ≈ 9.2 W |

Jocurile pe 32 de biți Direct3D 9 (*Fallout: New Vegas*) și titlurile 2D/izometrice funcționează la rate de cadre ce saturează fluiditatea ecranului AMOLED de 90 Hz. În titlurile 3D complexe din generația a opta (*GTA V*, *Skyrim SE*), translatarea asincronă GPL și o scalare reconstructivă FSR sunt absolut indispensabile pentru menținerea unei medii stabile de peste 30 FPS.

### **Riscuri Tehnice Majore & Protocoale de Recuperare**

| Risc Tehnic Identificat | Mecanism Cauzal | Impact Asupra Sistemului | Protocol Tehnic de Remediere / Mitigare |
| :---- | :---- | :---- | :---- |
| **Scriere greșită în partiții / pierderea Android-ului** | `fastboot flash super` suprascrie complet partiția `super` (system/vendor/product). Bootloader-ul refuză imaginile mai mari decât partiția înainte de scriere, deci nu se poate revărsa în GPT sau în alte partiții (corectat 2026-10-01: varianta anterioară a tabelului descria greșit un mecanism de corupere GPT). | Android nu mai pornește până la restaurarea `super`; fastboot rămâne disponibil. Hard-brick doar prin re-blocarea bootloader-ului cu software modificat sau prin scrieri manuale în alte partiții. | Backup complet și verificat înainte (`docs/hardware-safety.md`, secțiunea 2); restaurare cu `img2simg` + `fastboot flash super`; ultima plasă de siguranță: MSM Download Tool (EDL) cu pachetul regiunii. Nu rulați niciodată `fastboot flashing lock`. |
| **Încărcare: niciun driver sigur** | Kernelele Xo666 și ObiKeahloa nu au driver pentru `qcom,pm8150b-charger`; WuerfelDev și kernelul oficial pmOS SM8250 au unul, dar programează tensiunea maximă a bateriei cu scala greșită (~4.87 V în loc de 4.435 V), nu setează curentul și scrie la o adresă greșită în PMIC (verificat 2026-10-01, confirmat independent pe Retroid Pocket 5). | Pe Xo666: încărcare doar pe setările hardware lăsate de bootloader. Cu driverul comunitar: risc real de supraîncărcare a bateriei. | Patch-urile anterioare de "portare a charger-ului" adăugau doar noduri de device tree fără driver; cel de pe Xo666 a fost scos. Test de încărcare cu monitorizarea tensiunii (`docs/hardware-safety.md`, 4.1). Nu se folosește driverul comunitar până nu e reparat. |
| **Eșec Handshake USB-PD** | Comportament netestat al mux-ului `fcs,fsa4480` la orientare inversă a conectorului. | Posibilă întrerupere a alimentării coolerului Peltier și revenire la throttling. | Marcat OPEN în log-ul de verificare; necesită testare directă pe dispozitiv. |

#### **Protocolul de Recuperare EDL (Emergency Download Mode)**

> **Tratați EDL ca transport confirmat funcțional, nu ca plasă de siguranță completă
> dovedită.** Există un loader Firehose comunitar pentru familia OnePlus 8 în
> `bkerler/edl`, verificat funcțional pe hardware real (autentificare EDL/Sahara reușită,
> inclusiv funcția `fixgpt` de reparare GPT). Dar nu există, din câte s-a putut verifica,
> niciun raport public al cuiva care a dus o recuperare completă capăt-la-capăt, de la un
> telefon efectiv mort la unul care pornește din nou. E o unealtă reală, nu una teoretică -
> dar nedovedită ca soluție completă. De-asta pasul 0 de mai sus (pachetul OxygenOS descărcat
> dinainte) contează mai mult decât EDL însuși.

În eventualitatea unui hard-brick provocat de alterarea tabelelor GUID ale discurilor fizice UFS, SoC-ul SM8250 poate fi recuperat prin modul de descărcare de urgență. Terminalul este deconectat, iar prin menținerea ambelor butoane de volum la introducerea cablului USB se inițializează interfața Qualcomm HS-USB QDLoader 9008.
De sub un sistem Linux, utilitarul open-source bkerler/edl permite comunicarea cu nucleul primar PBL (Primary Boot Loader), încărcarea binarului semnat Firehose (prog_firehose_ddr.elf) și reconstrucția completă a LUN-urilor UFS din imaginile de fabrică OxygenOS - **presupunând că aveți deja aceste imagini de fabrică pregătite dinainte** (pasul 0).

#### **Protecția Acumulatorului: de verificat, nu de presupus**

> **Actualizare 2026-10-01:** pe kernelul folosit (Xo666) nu există driver de încărcare,
> deci încărcarea rămâne pe setările hardware lăsate de bootloader. Singurul driver comunitar
> disponibil (`qcom_pm8150b_charger.c`) e periculos în forma actuală: ~4.87 V tensiune maximă,
> curent de încărcare nesetat, scriere la adresă greșită în PMIC. Testul de încărcare cu
> monitorizarea tensiunii e în `docs/hardware-safety.md`, 4.1.

Documentul original propunea un bypass de încărcare prin `echo 0 > /sys/class/power_supply/battery/charging_enabled`. Acesta e un nod **sysfs downstream** specific kernelelor Android/CAF - nu există în `power_supply` mainline, deci comanda va eșua pe acest kernel. Mainline expune în schimb `charge_control_limit` și `input_current_limit` sub `/sys/class/power_supply/`, dar chiar și acestea presupun un driver de charger funcțional - iar device tree-ul verificat nu declară niciunul (Secțiunea 4). Practic: nu există încă o rețetă confirmată de a proteja bateria în sesiuni lungi pe acest kernel; e primul lucru de testat cu telefonul fizic în mână, nu de presupus rezolvat.

## **6\. Concluzii**

Telefonul chiar boot-ează pe Linux mainline cu accelerare 3D funcțională - dar doar pe unul dintre
cele trei fork-uri cunoscute (Xo666), nu universal. Asta era singurul lucru care putea opri
proiectul din start, și pe acel fork specific răspunsul e da. "Mainline" înseamnă aici fork-ul unui
singur contributor, nu suport oficial în kernel.org sau în pmaports, iar fluxul de instalare din
documentul original nu rulează ca atare pe acest device tree.

Convergența dintre driverul grafic Mesa Turnip (cu suport complet Vulkan 1.3 și GPL) și stiva de
execuție hibridă Proton 11 ARM64 susținută de recompilatorul JIT FEX-Emu rezolvă principalele
bariere de compatibilitate - capitolul cel mai solid al documentului. Dar bariera reală, la data
verificării, nu mai e nici userspace-ul, nici alimentarea izolat - e faptul că **niciun fork nu are
simultan GPU și încărcare funcționale**. Xo666, folosit ca referință pentru tot ce ține de grafică
în acest document, nu are deloc nod de charger; WuerfelDev, fork-ul spre care indică wiki-ul
pentru încărcare (5 W confirmată, doar Warp lipsește), are `&gpu` dezactivat explicit. Compositorul
de gaming (fostul "Gamescope" din plan) și clientul Steam ARM64 rămân, la rândul lor, de asamblat
manual. Coolerul Peltier al GameSir X3 Pro rezolvă oricum jumătatea termică a problemei indiferent
de rezultatul alimentării, pentru că se alimentează singur de la priză - dar fără o portare a
nodurilor de charger peste DTS-ul Xo666, telefonul de pe acest fork joacă bine și se descarcă normal,
fără nicio compensare din priză.

**Corectură 2026-10-01:** ambele actualizări de mai jos descriu patch-uri care **nu activează
încărcarea**: kernelele Xo666 și ObiKeahloa nu au driverul care să folosească nodurile portate.
Concluzia reală e mai simplă: pe Xo666 telefonul încarcă doar pe setările hardware ale
PMIC-ului, iar un driver de încărcare sigur pentru PM8150B încă nu există în niciun fork
(cel din WuerfelDev/pmOS programează ~4.87 V). Patch-ul de pe Xo666 a fost scos; vezi
`docs/verification-log.md` §9.

**Actualizare 2026-08-24:** portarea de mai sus a fost încercată. Nodurile `pm8150b_charger` și
`pm8150b_fg` din WuerfelDev au fost aduse peste DTS-ul Xo666 fără să atingă nodul `&gpu` sau
zap-shader-ul, iar rezultatul se compilează curat - atât cu `dtc` direct, cât și prin pipeline-ul
real `abuild`/`pmbootstrap` (patch-ul e la
`pmaports/linux-oneplus-instantnoodle/0001-port-charger-fg-from-wuerfeldev.patch`, detalii complete
în `docs/verification-log.md`). **Important: asta e doar o verificare de compilare.** Nu s-a testat
pe niciun telefon real dacă driverul de charger sau fuel gauge chiar pornesc, dacă valorile ADC
raportate sunt corecte, sau dacă adăugarea acestor noduri interferează la runtime cu GPU-ul sau cu
mux-ul USB-C - lucruri pe care o comparație statică de device tree nu le poate dovedi. Problema
fork-fragmentării din Secțiunea 1 rămâne, în esență, nerezolvată până la testarea pe hardware; ce
există acum e un candidat de rezolvare, nu o rezolvare confirmată.

**Actualizare 2026-08-24 (mai târziu, aceeași zi):** și direcția inversă a fost încercată - zap-shader-ul
de la Xo666, portat peste DTS-ul ObiKeahloa. Asta a scos la iveală o eroare reală din acest
document: secțiunea 1 spunea că ObiKeahloa are "simultan GPU activat și încărcare funcțională",
concluzie trasă doar din citirea textului DTS. Compilarea reală a arătat că fork-ul ObiKeahloa, așa
cum e livrat, **nu se compilează deloc** - blocurile de override pentru charger/fg din DTS-ul lui
țintesc etichete pe care propriul `pm8150b.dtsi` nu le definește nicăieri. Patch-ul rezultat
(`pmaports/linux-oneplus-instantnoodle-obikeahloa/0001-port-zap-shader-from-xo666.patch`) a
crescut ca să porteze și acele definiții lipsă, nu doar zap-shader-ul. Rezultatul se compilează
curat și prin `abuild`/`pmbootstrap` real, iar DTB-ul compilat confirmă GPU zap-shader, charger și
fuel gauge rezolvate simultan cu `status = "okay"` - o combinație mai bună pe hârtie decât patch-ul
de mai sus, dar cu aceleași limitări: mux-ul SBU rămâne dezactivat, iar nimic din asta nu a fost
testat pe un telefon real. Detalii complete în `docs/verification-log.md`.

Prin respectarea corecțiilor din acest document, testarea pe hardware real a patch-ului de mai sus,
și verificarea necunoscutei rămase (clientul Steam ARM64, Secțiunea 3), OnePlus 8 poate depăși
stadiul de experiment demonstrativ și deveni o consolă portabilă funcțională pe Linux mainline.

#### **Lucrări citate**

> 1. OnePlus 8 (oneplus-instantnoodle) \- postmarketOS Wiki, [https://wiki.postmarketos.org/wiki/OnePlus\_8\_(oneplus-instantnoodle)](https://wiki.postmarketos.org/wiki/OnePlus_8_\(oneplus-instantnoodle\))  
> 2. Qualcomm Snapdragon 865/865+/870 (SM8250) \- postmarketOS Wiki, [https://wiki.postmarketos.org/wiki/Qualcomm\_Snapdragon\_865/865%2B/870\_(SM8250)](https://wiki.postmarketos.org/wiki/Qualcomm_Snapdragon_865/865%2B/870_\(SM8250\))  
> 3. User:Knuxify/List of chipsets and devices that use them \- postmarketOS Wiki, [https://wiki.postmarketos.org/wiki/User:Knuxify/List\_of\_chipsets\_and\_devices\_that\_use\_them](https://wiki.postmarketos.org/wiki/User:Knuxify/List_of_chipsets_and_devices_that_use_them)  
> 4. Releases · 0ctobot/neutrino\_kernel\_oneplus\_sm8250 \- GitHub, [https://github.com/0ctobot/neutrino\_kernel\_oneplus\_sm8250/releases](https://github.com/0ctobot/neutrino_kernel_oneplus_sm8250/releases)  
> 5. https://github.com/0ctobot/neutrino\_kernel\_oneplus\_sm8250 · GitHub \- GitHub Gist, [https://gist.github.com/0ctobot/e361b360b9e1eb09b41d29436654d21b](https://gist.github.com/0ctobot/e361b360b9e1eb09b41d29436654d21b)  
> 6. postmarketOS-powered Kubernetes cluster \- /dev/random \- Denys Vitali, [https://blog.denv.it/posts/pmos-k3s-cluster/](https://blog.denv.it/posts/pmos-k3s-cluster/)  
> 7. What can a Snapdragon 865+ play if I wanted to push it to the limit? : r/EmulationOnAndroid, [https://www.reddit.com/r/EmulationOnAndroid/comments/x7ip7r/what\_can\_a\_snapdragon\_865\_play\_if\_i\_wanted\_to/](https://www.reddit.com/r/EmulationOnAndroid/comments/x7ip7r/what_can_a_snapdragon_865_play_if_i_wanted_to/)  
> 8. Steam Deck: Gamescope Deep Dive \- GitHub, [https://github.com/dsrtfbbg379/gamescope-deep-dive](https://github.com/dsrtfbbg379/gamescope-deep-dive)  
> 9. Proton 11.0-2 Drops: vkd3d 2.0 and Wine 11.0 Regression Fixes \- Linux Compatible, [https://www.linuxcompatible.org/story/proton-1102-drops-vkd3d-20-and-wine-110-regression-fixes/](https://www.linuxcompatible.org/story/proton-1102-drops-vkd3d-20-and-wine-110-regression-fixes/)  
> 10. Valve isn't ditching Windows or x86, but it's quietly making both optional \- XDA Developers, [https://www.xda-developers.com/valve-isnt-ditching-windows-x86-quietly-making-optional/](https://www.xda-developers.com/valve-isnt-ditching-windows-x86-quietly-making-optional/)  
> 11. Mesa 22.1.0 Release Notes / 2022-05-18, [https://docs.mesa3d.org/relnotes/22.1.0.html](https://docs.mesa3d.org/relnotes/22.1.0.html)  
> 12. linux-sm8250 \- WuerfelDev \- postmarketOS · GitLab, [https://gitlab.postmarketos.org/WuerfelDev/linux-sm8250/-/tree/6.17.0-instantnoodle?ref\_type=heads](https://gitlab.postmarketos.org/WuerfelDev/linux-sm8250/-/tree/6.17.0-instantnoodle?ref_type=heads)  
> 13. linux \- Obi Keahloa \- postmarketOS · GitLab, [https://gitlab.postmarketos.org/ObiKeahloa/linux](https://gitlab.postmarketos.org/ObiKeahloa/linux)  
> 14. OnePlus 8 Pro (oneplus-instantnoodlep) \- postmarketOS Wiki, [https://wiki.postmarketos.org/wiki/OnePlus\_8\_Pro\_(oneplus-instantnoodlep)](https://wiki.postmarketos.org/wiki/OnePlus_8_Pro_\(oneplus-instantnoodlep\))  
> 15. User:Akku/android versions \- postmarketOS Wiki, [https://wiki.postmarketos.org/wiki/User:Akku/android\_versions](https://wiki.postmarketos.org/wiki/User:Akku/android_versions)  
> 16. oneplus 8 pro (instantnoodlep): new device packaging (\!3990) · Merge requests · postmarketOS / pmaports \- GitLab, [https://gitlab.com/postmarketOS/pmaports/-/merge\_requests/3990](https://gitlab.com/postmarketOS/pmaports/-/merge_requests/3990)  
> 17. Mesa 20.3.0 Release Notes / 2020-12-03, [https://docs.mesa3d.org/relnotes/20.3.0.html](https://docs.mesa3d.org/relnotes/20.3.0.html)  
> 18. Linux native BeamNG binary does not run · Issue \#424 · ptitSeb/box64 \- GitHub, [https://github.com/ptitSeb/box64/issues/424](https://github.com/ptitSeb/box64/issues/424)  
> 19. 21.2.0.rst « relnotes « docs \- mesa/mesa \- The Mesa 3D Graphics Library (mirrored from https://gitlab.freedesktop.org/mesa/mesa) \- freedesktop.org git repository browser, [https://cgit.freedesktop.org/mesa/mesa/tree/docs/relnotes/21.2.0.rst?h=21.2](https://cgit.freedesktop.org/mesa/mesa/tree/docs/relnotes/21.2.0.rst?h=21.2)  
> 20. Diff \- 0dcdeff049415cbd4f073bdba99bcf4cd61baa03^1..0dcdeff049415cbd4f073bdba99bcf4cd61baa03 \- platform/external/mesa3d \- Git at Google \- Android GoogleSource, [https://android.googlesource.com/platform/external/mesa3d/+/0dcdeff049415cbd4f073bdba99bcf4cd61baa03%5E1..0dcdeff049415cbd4f073bdba99bcf4cd61baa03/](https://android.googlesource.com/platform/external/mesa3d/+/0dcdeff049415cbd4f073bdba99bcf4cd61baa03%5E1..0dcdeff049415cbd4f073bdba99bcf4cd61baa03/)  
> 21. Optimizing Gaming Performance: ALSA vs PulseAudio & Environment Variables · Issue \#248 · The412Banner/Bannerlator \- GitHub, [https://github.com/The412Banner/Bannerlator/issues/248](https://github.com/The412Banner/Bannerlator/issues/248)  
> 22. Snapdragon 685 , everything is broken at any settings \+ low very performance (only 90 fps in the test, while on the classic Winlator Ludashi 960 fps. · Issue \#278 · The412Banner/Bannerlator \- GitHub, [https://github.com/The412Banner/Bannerlator/issues/278](https://github.com/The412Banner/Bannerlator/issues/278)  
> 23. Mesa 21.2.0 Release Notes / 2021-08-04, [https://docs.mesa3d.org/relnotes/21.2.0.html](https://docs.mesa3d.org/relnotes/21.2.0.html)  
> 24. i am getting low fps while my GPU can't even pass 75% usage. is there anything i can do? (besides getting a new phone or reducing the graphics) : r/winlator \- Reddit, [https://www.reddit.com/r/winlator/comments/1pgq9rs/i\_am\_getting\_low\_fps\_while\_my\_gpu\_cant\_even\_pass/](https://www.reddit.com/r/winlator/comments/1pgq9rs/i_am_getting_low_fps_while_my_gpu_cant_even_pass/)  
> 25. Proton/Makefile.in at proton\_11.0 \- GitHub, [https://github.com/ValveSoftware/Proton/blob/proton\_11.0/Makefile.in](https://github.com/ValveSoftware/Proton/blob/proton_11.0/Makefile.in)  
> 26. FEX-emu - Run x86 applications on ARM64 Linux devices \- Hacker News, [https://news.ycombinator.com/item?id=45905850](https://news.ycombinator.com/item?id=45905850)  
> 27. Canonical Promotes Steam Snap to Stable on ARM64, With... \- daily.dev, [https://daily.dev/posts/canonical-promotes-steam-snap-to-stable-on-arm64-with-plans-to-rebuild-it-from-scratch-later-h4rqoflv8](https://daily.dev/posts/canonical-promotes-steam-snap-to-stable-on-arm64-with-plans-to-rebuild-it-from-scratch-later-h4rqoflv8)  
> 28. Tiny Glade \- FEX-Emu Wiki, [https://wiki.fex-emu.com/index.php/Tiny\_Glade](https://wiki.fex-emu.com/index.php/Tiny_Glade)  
> 29. Makefile.in \- GloriousEggroll/proton-ge-custom \- GitHub, [https://github.com/GloriousEggroll/proton-ge-custom/blob/master/Makefile.in](https://github.com/GloriousEggroll/proton-ge-custom/blob/master/Makefile.in)  
> 30. émulation \- Liens en vrac de sebsauvage, [https://sebsauvage.net/links/?addtag=%C3%A9mulation](https://sebsauvage.net/links/?addtag=%C3%A9mulation)  
> 31. Valve kinda released ARM64 Proton, lol (works on my ARM64 machine, see the second screenshot) : r/linux\_gaming \- Reddit, [https://www.reddit.com/r/linux\_gaming/comments/1snjr0r/valve\_kinda\_released\_arm64\_proton\_lol\_works\_on\_my/](https://www.reddit.com/r/linux_gaming/comments/1snjr0r/valve_kinda_released_arm64_proton_lol_works_on_my/)  
> 32. GTK4 apps from Flatpak/Flathub fail to start with the vulkan rendering backend (\#3655) · Issue \- postmarketOS · GitLab, [https://gitlab.postmarketos.org/postmarketOS/pmaports/-/issues/3655](https://gitlab.postmarketos.org/postmarketOS/pmaports/-/issues/3655)  
> 33. Adreno 710 Guide For Better Performance and Not Visual Glitchs : r/winlator \- Reddit, [https://www.reddit.com/r/winlator/comments/1vuprt2/adreno\_710\_guide\_for\_better\_performance\_and\_not/](https://www.reddit.com/r/winlator/comments/1vuprt2/adreno_710_guide_for_better_performance_and_not/)  
> 34. FAQ - The AXP.OS Project, [https://axpos.org/docs/knowledge/faq/](https://axpos.org/docs/knowledge/faq/)  
> 35. Qualcomm CrashDump mode on recording HEVC 10-Bit video. (\#6421) · Issue \- GitLab, [https://gitlab.com/LineageOS/issues/android/-/issues/6421](https://gitlab.com/LineageOS/issues/android/-/issues/6421)

