#!/usr/bin/python3
# op8-buttons (armdeck): the phone's volume buttons, in a single process that reads both buttons
# together (Volume Up and Volume Down are separate input devices). Replaces op8-volbtn (two sh
# processes that coordinated through files: the combination worked about one time in three) and
# op8-steamkey.
#
# - short press on one button: +/-5% on release (so a press on both does not change the volume)
# - one button held: after HOLD_S, +/-5% every STEP_S while it is held (the buttons send no
#   automatic repeat, EV_REP is missing)
# - both buttons pressed together: on release, Shift+Tab on a virtual keyboard. Steam registers
#   Shift+Tab with gamescope as the Steam button (GuideKeyboardHotkey), so the Steam menu opens,
#   also in games, without a controller. It is sent only after release: gamescope triggers the
#   combination only when no other key is down, and the volume buttons are keyboards to it too.
#
# The buttons are swapped: held in landscape (screen rotated to the right), the physical Volume Up
# is on the left, and Steam's volume bar grows to the right. So KEY_VOLUMEDOWN (right) = louder.
# The volume is that of the default output (the protected speaker filter, op8_speakers_protected),
# capped at 100%; the physical ceiling stays the volume of the direct output (-18 dB), which the
# buttons do not touch.
#
# Runs in the "steam" container (python3-evdev, pulseaudio-utils), started by
# steam-in-container.sh before "exec steam" (its parent becomes the Steam process; when Steam
# exits, it exits too). In standby (op8-standby on the host) the buttons are ignored.
# Log: ~/op8-buttons.log
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
        log("gpio-keys / pm8941_resin not found")
        return
    log("started: " + ", ".join(f"{d.name} ({d.path})" for d in devs.values()))
    kbd = UInput({e.EV_KEY: [e.KEY_LEFTSHIFT, e.KEY_TAB]}, name="ARMDeck Steam key",
                 bustype=e.BUS_VIRTUAL)

    down = {}            # code -> the moment it was pressed
    held = set()         # codes that already changed the volume while held
    next_step = {}       # code -> the next volume change while held
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
        log("Volume Up + Volume Down -> Steam button")

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
            # held: continuous volume after HOLD_S, as long as it is not the combination
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
        log("stopped")


if __name__ == "__main__":
    main()
