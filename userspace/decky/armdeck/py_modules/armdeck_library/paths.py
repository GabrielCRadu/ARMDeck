# Where the Library keeps things. Games and emulators go on the games partition (~/games, the
# ext4 "op8games" on userdata), the launcher next to the user's other programs. A device without
# a games partition uses the home folder.
import os

import decky

HOME = decky.DECKY_USER_HOME
PLUGIN = decky.DECKY_PLUGIN_DIR
SETTINGS = decky.DECKY_PLUGIN_SETTINGS_DIR


def games():
    g = os.path.join(HOME, "games")
    return g if os.path.isdir(g) else HOME


def emulation():
    return os.path.join(games(), "Emulation")


def emulators():
    return os.path.join(emulation(), "emulators")


def roms():
    return os.path.join(emulation(), "roms")


def emulator(emu_id):
    return os.path.join(emulators(), emu_id)


# What the tiles start: copied there from the plugin when it loads (install_launcher), so the
# tiles keep working when the plugin folder is replaced by an update.
LIB = os.path.join(HOME, ".local/lib/armdeck")
RUN = os.path.join(LIB, "armdeck-run")
LAUNCHER_FILES = (("armdeck-run", 0o755), ("systems.json", 0o644),
                  ("armdeck-asound.conf", 0o644), ("armdeck-retroarch.cfg", 0o644))


def install_launcher():
    """Copy the launcher files from the plugin to LIB, only those that differ, each atomically."""
    os.makedirs(LIB, exist_ok=True)
    changed = []
    for name, mode in LAUNCHER_FILES:
        with open(os.path.join(PLUGIN, "library", name), "rb") as f:
            new = f.read()
        dest = os.path.join(LIB, name)
        try:
            with open(dest, "rb") as f:
                if f.read() == new and (os.stat(dest).st_mode & 0o777) == mode:
                    continue
        except OSError:
            pass
        tmp = dest + ".armdeck-new"
        with open(tmp, "wb") as f:
            f.write(new)
        os.chmod(tmp, mode)
        os.replace(tmp, dest)
        changed.append(name)
    return changed


def free_bytes(path):
    while not os.path.exists(path):
        path = os.path.dirname(path)
    st = os.statvfs(path)
    return st.f_bavail * st.f_frsize
