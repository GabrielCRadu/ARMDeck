# The tiles the Library made: a key of ours ("emu:<id>", later "game:<path>") mapped to the
# appid Steam handed back. Steam's appid is only recorded, never computed: shortcut appids change
# when a tile is added again (Nova-Deck's shortcuts.py, the same rule). A tile the user deleted
# in Steam is not brought back by itself; the frontend checks that the appid still exists.
import base64
import json
import os
import shlex

from . import paths

# Steam's internal name of "Proton 11.0 (ARM64)" (config.vdf CompatToolMapping, 2026-10-30)
PROTON = "proton_11-arm64"

FILE = os.path.join(paths.SETTINGS, "tiles.json")


def load():
    try:
        with open(FILE) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def save(data):
    os.makedirs(paths.SETTINGS, exist_ok=True)
    tmp = FILE + ".new"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=1)
    os.replace(tmp, FILE)


def created(key, appid, name):
    data = load()
    data[key] = {"appid": int(appid), "name": name}
    save(data)


def forget(key):
    data = load()
    if data.pop(key, None) is not None:
        save(data)


def emulator_spec(entry):
    """What the frontend passes to SteamClient.Apps.AddShortcut for an emulator's own tile."""
    return {"key": f"emu:{entry['id']}", "name": entry["name"], "exe": paths.RUN,
            "start_dir": paths.LIB, "options": f"emulator {shlex.quote(entry['id'])}"}


def path_argument(path):
    """A file path for a tile's launch options, which Steam splits like a shell does. Double
    quotes are enough for ordinary names (spaces, brackets, apostrophes); a name with characters
    that are special even inside double quotes goes in base64, which armdeck-run decodes."""
    if any(c in path for c in '"$`\\\n'):
        return "b64:" + base64.urlsafe_b64encode(path.encode()).decode()
    return f'"{path}"'


def game_spec(path, kind, name):
    """A game's tile: an emulated game through armdeck-run, a Windows program through Proton
    (Steam composes Proton, its runtime and FEX, as for a Steam game), a native one directly."""
    real = os.path.realpath(path)
    spec = {"key": f"game:{real}", "name": name, "start_dir": os.path.dirname(real)}
    if kind == "windows":
        spec.update(exe=real, options="", compat_tool=PROTON)
    elif kind == "native":
        spec.update(exe=real, options="")
    else:
        spec.update(exe=paths.RUN, start_dir=paths.LIB,
                    options=f"game {shlex.quote(kind)} {path_argument(real)}")
    return spec
