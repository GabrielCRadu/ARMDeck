#!/usr/bin/python3
# op8-buttons (armdeck): butoanele de volum ale telefonului, intr-un singur proces care
# citeste ambele butoane deodata (Volume Up si Volume Down sunt dispozitive de intrare diferite).
# Inlocuieste op8-volbtn (doua procese sh care se coordonau prin fisiere: combinatia mergea cam o
# data din trei) si op8-steamkey.
#
# - apasare scurta pe un buton: +/-5% la eliberare (ca o apasare pe ambele sa nu schimbe volumul)
# - un buton tinut apasat: dupa HOLD_S, +/-5% la fiecare STEP_S cat timp e tinut (butoanele nu
#   trimit repetare automata, EV_REP lipseste)
# - ambele butoane apasate in acelasi timp: la eliberarea lor, Shift+Tab pe o tastatura virtuala.
#   Steam inregistreaza Shift+Tab la gamescope ca butonul Steam (GuideKeyboardHotkey), deci se
#   deschide meniul Steam, si in jocuri, fara controler. Se trimite abia dupa eliberare: gamescope
#   declanseaza combinatia doar daca nicio alta tasta nu e apasata, iar butoanele de volum sunt
#   si ele tastaturi pentru el.
#
# Butoanele sunt inversate: tinut in landscape (ecranul rotit spre dreapta), Volume Up fizic e in
# stanga, iar bara de volum din Steam creste spre dreapta. Deci KEY_VOLUMEDOWN (dreapta) = mai tare.
# Volumul e cel al iesirii implicite ("Difuzoare (protejat)"), cu limita 100%; plafonul fizic
# ramane volumul iesirii directe (-30 dB), pe care butoanele nu-l ating.
#
# Ruleaza in containerul "steam" (python3-evdev, pulseaudio-utils), pornit de steam-in-container.sh
# inainte de "exec steam" (parintele devine procesul Steam; cand Steam se inchide, iese si el).
# In standby (op8-standby pe gazda) butoanele se ignora. Jurnal: ~/op8-buttons.log
import os
import re
import select
import subprocess
import time

from evdev import InputDevice, UInput, ecodes as e, list_devices

HOLD_S = 0.5
STEP_S = 0.15
STEAM_DEBOUNCE_S = 1.5
LOUDER, QUIETER = e.KEY_VOLUMEDOWN, e.KEY_VOLUMEUP
STANDBY = "/run/host/run/op8-standby.active"
RUN = f"/run/user/{os.getuid()}"
PIDF = f"{RUN}/op8-buttons.pid"
LOG = os.path.expanduser("~/op8-buttons.log")
ENV = dict(os.environ, XDG_RUNTIME_DIR=RUN)


def log(msg):
    with open(LOG, "a") as f:
        f.write(time.strftime("%F %T ") + msg + "\n")


def single_instance():
    try:
        with open(PIDF) as f:
            os.kill(int(f.read().strip()), 15)
            time.sleep(0.3)
    except (OSError, ValueError):
        pass
    with open(PIDF, "w") as f:
        f.write(str(os.getpid()))


def volume_percent():
    out = subprocess.run(["pactl", "get-sink-volume", "@DEFAULT_SINK@"], env=ENV,
                         capture_output=True, text=True).stdout
    m = re.search(r"(\d+)%", out)
    return int(m.group(1)) if m else None


def volume_step(code):
    if code == LOUDER:
        cur = volume_percent()
        arg = "100%" if cur is not None and cur >= 95 else "+5%"
    else:
        arg = "-5%"
    subprocess.run(["pactl", "set-sink-volume", "@DEFAULT_SINK@", arg], env=ENV)


def main():
    single_instance()
    steam_pid = os.getppid()
    devs = {}
    for path in list_devices():
        d = InputDevice(path)
        if d.name in ("gpio-keys", "pm8941_resin"):
            devs[d.fd] = d
    if not devs:
        log("nu gasesc gpio-keys / pm8941_resin")
        return
    log("pornit: " + ", ".join(f"{d.name} ({d.path})" for d in devs.values()))
    kbd = UInput({e.EV_KEY: [e.KEY_LEFTSHIFT, e.KEY_TAB]}, name="ARMDeck Steam key",
                 bustype=e.BUS_VIRTUAL)

    down = {}            # cod -> momentul apasarii
    held = set()         # coduri care au schimbat deja volumul cat timp erau tinute
    next_step = {}       # cod -> urmatoarea schimbare de volum la tinere
    combo = False
    last_steam = 0.0

    def steam_key():
        nonlocal last_steam
        now = time.monotonic()
        if now - last_steam < STEAM_DEBOUNCE_S:
            return
        last_steam = now
        for key, val in ((e.KEY_LEFTSHIFT, 1), (e.KEY_TAB, 1), (e.KEY_TAB, 0),
                         (e.KEY_LEFTSHIFT, 0)):
            kbd.write(e.EV_KEY, key, val)
            kbd.syn()
            time.sleep(0.04)
        log("Volume Up + Volume Down -> butonul Steam")

    try:
        while True:
            now = time.monotonic()
            timeout = 2.0
            for code, t0 in down.items():
                if not combo:
                    due = next_step.get(code, t0 + HOLD_S)
                    timeout = min(timeout, max(0.0, due - now))
            r, _, _ = select.select(list(devs), [], [], timeout)
            try:
                os.kill(steam_pid, 0)
            except OSError:
                break
            standby = os.path.exists(STANDBY)
            now = time.monotonic()
            for fd in r:
                for ev in devs[fd].read():
                    if ev.type != e.EV_KEY or ev.code not in (LOUDER, QUIETER):
                        continue
                    other = QUIETER if ev.code == LOUDER else LOUDER
                    if ev.value == 1:
                        down[ev.code] = now
                        held.discard(ev.code)
                        next_step.pop(ev.code, None)
                        if other in down:
                            combo = True
                    elif ev.value == 0:
                        down.pop(ev.code, None)
                        next_step.pop(ev.code, None)
                        if combo:
                            if other not in down:
                                combo = False
                                held.clear()
                                if not standby:
                                    steam_key()
                        elif ev.code in held:
                            held.discard(ev.code)
                        elif not standby:
                            volume_step(ev.code)
            # tinere: volum continuu dupa HOLD_S, cat timp nu e combinatie
            if not combo and not standby:
                for code, t0 in list(down.items()):
                    due = next_step.get(code, t0 + HOLD_S)
                    if now >= due:
                        volume_step(code)
                        held.add(code)
                        next_step[code] = now + STEP_S
    finally:
        kbd.close()
        try:
            os.remove(PIDF)
        except OSError:
            pass
        log("oprit")


if __name__ == "__main__":
    main()
