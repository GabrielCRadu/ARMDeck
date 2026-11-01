# "Add a game" (Library part 2): what a file picked in Decky's file picker is, what it needs before
# it can get a tile, and the tile itself. The file stays where it is; the tile points at it.
import os
import stat

from . import detect, emulators, tiles


def inspect(path, system=None):
    """For the frontend: the file's kind and tile name, the systems to choose from when the file
    alone does not tell, the emulator still to install, the tile it already has, or why it
    cannot be started. system: the user's choice among those systems."""
    real = os.path.realpath(path)
    out = {"path": real, "kind": None, "name": None, "how": None, "choices": [], "needs": None,
           "existing": tiles.load().get(f"game:{real}"), "error": None}
    if not os.path.isfile(real):
        out["error"] = "That is not a file."
        return out
    systems = detect.systems()
    kind = detect.detect(real)
    if system and kind and kind.startswith("choose:") and system in kind[7:].split(","):
        kind = system
    if kind is None:
        out["error"] = "ARMDeck does not know how to start this file."
    elif kind.startswith("unsupported:"):
        out["error"] = kind[12:][:1].upper() + kind[13:] + "."
    elif kind.startswith("choose:"):
        out["choices"] = [{"id": s, "name": systems[s]["name"]} for s in kind[7:].split(",")
                          if s in systems]
    elif kind == "windows":
        out["how"] = "A Windows program, started through Proton 11 (ARM64)."
    elif kind == "native":
        out["how"] = "An ARM64 Linux program, started directly."
    else:
        emu = emulators.catalog()[systems[kind]["emulator"]]
        out["how"] = f"A {systems[kind]['name']} game, started in {emu['name']}."
        if not emulators.installed(emu):
            out["needs"] = {"id": emu["id"], "name": emu["name"]}
    if out["how"]:
        out["kind"] = kind
        out["name"] = detect.display_name(real, kind)
    return out


def spec(path, kind, name):
    """The tile for a file inspect() accepted."""
    real = os.path.realpath(path)
    if kind == "native":
        # an AppImage or a script the user picked is often not executable yet (a download)
        mode = os.stat(real).st_mode
        if not mode & stat.S_IXUSR:
            os.chmod(real, mode | stat.S_IXUSR)
    return tiles.game_spec(real, kind, name.strip() or detect.display_name(real, kind))
