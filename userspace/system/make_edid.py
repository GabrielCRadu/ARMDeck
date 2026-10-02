#!/usr/bin/env python3
# EDID 1.4 pentru panoul OnePlus 8 (Samsung AMB655UV01, DSI, fara EDID propriu), din timing-urile
# driverului panel-samsung-amb655uv01.c (Xo666). Modul de 60 Hz primul (preferat, ceas exact),
# apoi 90 Hz (243,33 MHz in loc de 243,331: EDID-ul are pasi de 10 kHz). sRGB, fara HDR.
import struct, sys

def dtd(clock_khz, ha, hss, hse, ht, va, vss, vse, vt, wmm, hmm):
    pc = clock_khz // 10
    hb, vb = ht - ha, vt - va
    hso, hsw = hss - ha, hse - hss
    vso, vsw = vss - va, vse - vss
    d = bytearray(18)
    d[0], d[1] = pc & 0xff, pc >> 8
    d[2] = ha & 0xff; d[3] = hb & 0xff; d[4] = ((ha >> 8) << 4) | (hb >> 8)
    d[5] = va & 0xff; d[6] = vb & 0xff; d[7] = ((va >> 8) << 4) | (vb >> 8)
    d[8] = hso & 0xff; d[9] = hsw & 0xff
    d[10] = ((vso & 0xf) << 4) | (vsw & 0xf)
    d[11] = ((hso >> 8) << 6) | ((hsw >> 8) << 4) | ((vso >> 4) << 2) | (vsw >> 4)
    d[12] = wmm & 0xff; d[13] = hmm & 0xff; d[14] = ((wmm >> 8) << 4) | (hmm >> 8)
    d[17] = 0x18  # digital separate sync, ambele polaritati negative (modul driverului n-are flaguri)
    return d

def text_desc(tag, s):
    b = s.encode()[:13]
    if len(b) < 13:
        b = b + b"\n" + b" " * (12 - len(b))
    return bytes([0, 0, 0, tag, 0]) + b

ha, hss, hse, ht = 1080, 1088, 1112, 1120
va, vss, vse, vt = 2400, 2404, 2408, 2414
clk60 = ht * vt * 60 // 1000   # 162220 kHz, ca in driver
clk90 = ht * vt * 90 // 1000   # 243331 kHz in driver -> 243330 in EDID
wmm, hmm = 70, 151

# "landscape": EDID-ul pe care Steam il primeste de la gamescope pentru ecranul rotit (gamescope
# --force-orientation right); acelasi panou, cu orizontala si verticala schimbate intre ele, iar
# primul mod e cel pe care gamescope il foloseste efectiv (90 Hz).
landscape = len(sys.argv) > 2 and sys.argv[2] == "landscape"
if landscape:
    (ha, hss, hse, ht), (va, vss, vse, vt) = (va, vss, vse, vt), (ha, hss, hse, ht)
    wmm, hmm = hmm, wmm

e = bytearray(128)
e[0:8] = b"\x00\xff\xff\xff\xff\xff\xff\x00"
# producator "ONP" (cod PNP fictiv, ca gamescope sa nu aplice profilul altui ecran)
m = ((ord("O") - 64) << 10) | ((ord("N") - 64) << 5) | (ord("P") - 64)
e[8:10] = struct.pack(">H", m)
e[10:12] = struct.pack("<H", 0x0655)   # cod produs
e[12:16] = struct.pack("<I", 0)        # serie: niciuna
e[16], e[17] = 1, 2020 - 1990          # saptamana, anul
e[18], e[19] = 1, 4                    # EDID 1.4
e[20] = 0xA0                           # digital, 8 biti/culoare, interfata nedefinita (DSI)
e[21], e[22] = (wmm + 5) // 10, (hmm + 5) // 10   # cm
e[23] = 120                            # gamma 2.2
e[24] = 0x06                           # sRGB implicit, modul preferat e primul DTD
def c10(v): return round(v * 1024)
rx, ry, gx, gy = c10(0.640), c10(0.330), c10(0.300), c10(0.600)
bx, by, wx, wy = c10(0.150), c10(0.060), c10(0.3127), c10(0.3290)
e[25] = ((rx & 3) << 6) | ((ry & 3) << 4) | ((gx & 3) << 2) | (gy & 3)
e[26] = ((bx & 3) << 6) | ((by & 3) << 4) | ((wx & 3) << 2) | (wy & 3)
e[27:35] = bytes([rx >> 2, ry >> 2, gx >> 2, gy >> 2, bx >> 2, by >> 2, wx >> 2, wy >> 2])
e[35:38] = b"\x00\x00\x00"             # fara moduri "established"
e[38:54] = b"\x01\x01" * 8             # fara moduri standard
first, second = (clk90, clk60) if landscape else (clk60, clk90)
e[54:72] = dtd(first, ha, hss, hse, ht, va, vss, vse, vt, wmm, hmm)
e[72:90] = dtd(second, ha, hss, hse, ht, va, vss, vse, vt, wmm, hmm)
e[90:108] = text_desc(0xFC, "OnePlus 8")
e[108:126] = bytes([0, 0, 0, 0x10, 0]) + bytes(13)   # descriptor gol
e[126] = 0                             # fara extensii
e[127] = (-sum(e[:127])) & 0xff
open(sys.argv[1], "wb").write(e)
print("clk60", clk60, "clk90", clk90, "->", (clk90 // 10) * 10, "checksum", hex(e[127]))
