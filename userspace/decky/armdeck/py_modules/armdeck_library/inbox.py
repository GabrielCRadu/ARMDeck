# The Inbox (Library part 3): a folder on the games partition, ~/games/Inbox. Whatever lands
# there (copied over USB or the network, downloaded, later uploaded from the QR page) is
# recognized with detect.py, moved to its place and given a tile:
# - a game for one of the systems goes to Emulation/roms/<system>/; a folder with a .cue, .gdi
#   or .m3u moves whole, so the sheet still finds its tracks (several discs and no .m3u: one is
#   written, so the game has one tile);
# - a folder with a Windows .exe goes to Windows/<folder>/, with a tile when one .exe is clearly
#   the game;
# - an ARM64 program or script goes to Apps/;
# - an archive is unpacked first (a cartridge game in a zip or 7z stays packed: RetroArch reads
#   it) and removed once something from it has been placed.
# What it cannot place stays in the Inbox, and the toast says why, once. A game whose emulator is
# not installed yet is moved anyway and gets its tile when the emulator is installed.
# The watcher sleeps in inotify between changes, so an idle Inbox costs nothing; a batch is
# handled when nothing in it is still being written and it has been quiet for QUIET seconds.
import ctypes
import json
import os
import re
import select
import shutil
import stat
import struct
import subprocess
import threading
import time
import zipfile

from . import detect, emulators, fetch, games, paths

QUIET = 5
# names a download or a copy still in progress has
TEMP_SUFFIXES = (".part", ".crdownload", ".tmp", ".partial", ".download", ".!qb", ".filepart",
                 ".armdeck-new")
ARCHIVES = (".zip", ".7z", ".rar")
SHEETS = (".m3u", ".cue", ".gdi")
# kept free after unpacking, like an emulator install
RESERVE = emulators.RESERVE
# .exe files that are not the game: installers, redistributables, crash reporters, anti-cheat
NOT_THE_GAME = re.compile(
    r"unins|setup|install|redist|vc_?redist|dxsetup|directx|dotnet|physx|prereq|crash|report|"
    r"easyanticheat|battleye|cefprocess|helper|notification|update|patch|config|bugsplat",
    re.I)

PENDING = os.path.join(paths.SETTINGS, "inbox-pending.json")
LEFT = os.path.join(paths.SETTINGS, "inbox-left.json")

IN_CLOSE_WRITE = 0x8
IN_MOVED_TO = 0x80
IN_CREATE = 0x100
IN_DELETE_SELF = 0x400
IN_Q_OVERFLOW = 0x4000
IN_ISDIR = 0x40000000
WATCH_MASK = IN_CLOSE_WRITE | IN_MOVED_TO | IN_CREATE | IN_DELETE_SELF


def inbox():
    return os.path.join(paths.games(), "Inbox")


def _unpack_root():
    # outside the Inbox, so unpacking wakes no watch; on the same partition, so moves are renames
    return os.path.join(paths.games(), ".armdeck-unpack")


def _load(path):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def _save(path, data):
    os.makedirs(paths.SETTINGS, exist_ok=True)
    tmp = path + ".new"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=1)
    os.replace(tmp, path)


def _ignored(name):
    return name.startswith(".") or name.lower().endswith(TEMP_SUFFIXES)


def _clean(title):
    """A tile name from a folder name (no extension to cut: "Game v1.5" keeps its ".5")."""
    return detect.display_name(title + ".folder", "")


def _signature(path):
    """Size and newest change of a file or a whole folder: tells whether it is still changing."""
    try:
        st = os.lstat(path)
    except OSError:
        return None
    if not stat.S_ISDIR(st.st_mode):
        return [st.st_size, int(st.st_mtime)]
    size, newest = 0, st.st_mtime
    for root, dirs, files in os.walk(path):
        for n in dirs + files:
            try:
                s = os.lstat(os.path.join(root, n))
            except OSError:
                continue
            size += s.st_size
            newest = max(newest, s.st_mtime)
    return [size, int(newest)]


# --- sheets: the files a .cue, .gdi or .m3u needs next to it ---

def _sheet_files(sheet):
    """The file names a sheet refers to, relative to its folder."""
    try:
        with open(sheet, errors="replace") as f:
            text = f.read(256 * 1024)
    except OSError:
        return []
    ext = os.path.splitext(sheet)[1].lower()
    if ext == ".cue":
        return re.findall(r'^\s*FILE\s+"?(.+?)"?\s+\w+\s*$', text, re.M | re.I)
    if ext == ".gdi":
        out = []
        for line in text.splitlines()[1:]:
            m = re.match(r'\s*\d+\s+\d+\s+\d+\s+\d+\s+("([^"]+)"|(\S+))', line)
            if m:
                out.append(m.group(2) or m.group(3))
        return out
    return [ln.strip() for ln in text.splitlines() if ln.strip() and not ln.startswith("#")]


def _inside(base, rel):
    full = os.path.realpath(os.path.join(base, rel))
    return full if full.startswith(os.path.realpath(base) + os.sep) else None


# --- where things go ---

class Batch:
    """What one pass over the Inbox did: tiles for the frontend to make, and what to tell."""

    def __init__(self):
        self.tiles = []      # tile specs (tiles.game_spec)
        self.placed = []     # names of games moved without a tile (emulator still to install)
        self.notes = []      # what stayed in the Inbox, and why
        self.waiting = False  # something was skipped because it changed a moment ago

    def view(self):
        return {"tiles": self.tiles, "placed": self.placed, "notes": self.notes}


def _free_target(dest):
    return not os.path.lexists(dest)


def _move(src, dest):
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    shutil.move(src, dest)


def _tile_or_pending(batch, path, kind, name=None):
    """A tile now when the game can start, else a tile when its emulator gets installed."""
    name = name or detect.display_name(path, kind)
    if kind in ("windows", "native"):
        batch.tiles.append(games.spec(path, kind, name))
        return
    emu_id = detect.systems()[kind]["emulator"]
    if emulators.installed(emulators.catalog()[emu_id]):
        batch.tiles.append(games.spec(path, kind, name))
        return
    pending = _load(PENDING)
    pending.setdefault(emu_id, []).append({"path": path, "kind": kind, "name": name})
    _save(PENDING, pending)
    batch.placed.append(f"{name} (gets its tile when {emulators.catalog()[emu_id]['name']} "
                        "is installed)")


def take_pending(emu_id):
    """The tiles of games that waited for this emulator, for the frontend to make."""
    pending = _load(PENDING)
    waiting = pending.pop(emu_id, [])
    if waiting:
        _save(PENDING, pending)
    return [games.spec(g["path"], g["kind"], g["name"]) for g in waiting
            if os.path.isfile(g["path"])]


def _system_of(path):
    """A system id when the file is a game the Library can place, else (None, why)."""
    kind = detect.detect(path)
    name = os.path.basename(path)
    if kind is None:
        return None, f"{name}: ARMDeck does not know this kind of file"
    if kind.startswith("unsupported:"):
        return None, f"{name}: {kind[12:]}"
    if kind.startswith("choose:"):
        return None, (f"{name}: this disc image could be for more than one console; use "
                      "Add a game to choose")
    return kind, None


def _place_rom(batch, path, kind, companions=()):
    """A game file (with the tracks its sheet names) into roms/<system>/."""
    dest_dir = os.path.join(paths.roms(), kind)
    dest = os.path.join(dest_dir, os.path.basename(path))
    targets = [os.path.join(dest_dir, os.path.basename(c)) for c in companions]
    if not all(_free_target(t) for t in [dest] + targets):
        batch.notes.append(f"{os.path.basename(path)}: a file with that name is already in "
                           f"Emulation/roms/{kind}")
        return False
    for c, t in zip(companions, targets):
        _move(c, t)
    _move(path, dest)
    _tile_or_pending(batch, dest, kind)
    return True


def _place_program(batch, path):
    dest = os.path.join(paths.games(), "Apps", os.path.basename(path))
    if not _free_target(dest):
        batch.notes.append(f"{os.path.basename(path)}: already in Apps")
        return False
    _move(path, dest)
    _tile_or_pending(batch, dest, "native")
    return True


def _place_file(batch, path, folder_files=None):
    """One file. folder_files: the other files beside it, when it came in a folder whose sheets
    were already handled (a track named by a sheet is not placed on its own)."""
    name = os.path.basename(path)
    ext = os.path.splitext(name)[1].lower()
    if ext in ARCHIVES:
        kind = detect.detect(path)
        if kind and not kind.startswith(("unsupported:", "choose:")) and kind not in (
                "windows", "native"):
            return _place_rom(batch, path, kind)
        return _place_archive(batch, path)
    if ext == ".exe":
        batch.notes.append(f"{name}: a Windows program on its own; put the whole game folder in "
                           "the Inbox (installers are not supported yet)")
        return False
    kind, why = _system_of(path)
    if ext == ".m3u":
        first = next(iter(_sheet_files(path)), None)
        full = _inside(os.path.dirname(path), first) if first else None
        if full and os.path.isfile(full):
            kind, why = _system_of(full)
    if kind is None:
        batch.notes.append(why)
        return False
    if kind == "native":
        return _place_program(batch, path)
    if kind == "windows":
        batch.notes.append(f"{name}: a Windows program on its own; put the whole game folder in "
                           "the Inbox")
        return False
    companions = []
    if ext in SHEETS:
        missing = _sheet_closure(path, companions)
        if missing:
            batch.notes.append(f"{name}: it needs {missing}, which is not next to it (a game "
                               "with its tracks in subfolders goes in as its folder)")
            return False
    return _place_rom(batch, path, kind, companions)


def _sheet_closure(sheet, out):
    """Every file a sheet needs, next to it, also through an .m3u's own sheets, added to out.
    Returns the first one missing, or None."""
    base = os.path.realpath(os.path.dirname(sheet))
    for rel in _sheet_files(sheet):
        full = _inside(base, rel)
        if full is None or not os.path.isfile(full) or os.path.dirname(full) != base:
            return rel
        if full in out:
            continue
        out.append(full)
        if sheet.lower().endswith(".m3u") and full.lower().endswith((".cue", ".gdi")):
            missing = _sheet_closure(full, out)
            if missing:
                return missing
    return None


def _exes(folder):
    found = []
    for root, dirs, files in os.walk(folder):
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        depth = os.path.relpath(root, folder).count(os.sep) + (root != folder)
        if depth > 4:
            dirs[:] = []
            continue
        for n in files:
            if n.lower().endswith(".exe"):
                found.append((depth, os.path.join(root, n)))
    return found


def _main_exe(folder, title):
    """The .exe that is the game: the only one left once installers and helpers are set aside,
    at the shallowest level (Unreal's small starter is at the top, the real one deeper), or
    the one named like the folder. None when it is not clear."""
    candidates = [(d, p) for d, p in _exes(folder) if not NOT_THE_GAME.search(os.path.basename(p))]
    if not candidates:
        return None
    top = min(d for d, _ in candidates)
    shallow = [p for d, p in candidates if d == top]
    if len(shallow) == 1:
        return shallow[0]
    key = re.sub(r"[^a-z0-9]", "", title.lower())
    named = [p for p in shallow
             if re.sub(r"[^a-z0-9]", "", os.path.splitext(os.path.basename(p))[0].lower()) == key]
    return named[0] if len(named) == 1 else None


def _place_windows(batch, folder, title):
    dest = os.path.join(paths.games(), "Windows", title)
    if not _free_target(dest):
        batch.notes.append(f"{title}: a folder with that name is already in Windows")
        return False
    _move(folder, dest)
    exe = _main_exe(dest, title)
    if exe is None:
        batch.placed.append(f"{title} (moved to Windows/{title}; choose its .exe with Add a game)")
        return True
    _tile_or_pending(batch, exe, "windows", _clean(title))
    return True


def _place_app_folder(batch, folder, title):
    """A folder with an ARM64 program and the files it needs: moved whole to Apps/<folder>."""
    dest = os.path.join(paths.games(), "Apps", title)
    if not _free_target(dest):
        batch.notes.append(f"{title}: a folder with that name is already in Apps")
        return False
    _move(folder, dest)
    programs = [os.path.join(dest, n) for n in sorted(os.listdir(dest))
                if os.path.isfile(os.path.join(dest, n))
                and detect.detect(os.path.join(dest, n)) == "native"]
    if len(programs) == 1:
        _tile_or_pending(batch, programs[0], "native", _clean(title))
    else:
        batch.placed.append(f"{title} (moved to Apps/{title}; choose the program with Add a game)")
    return True


def _write_m3u(folder, sheets, title):
    m3u = os.path.join(folder, f"{title}.m3u")
    with open(m3u, "w") as f:
        f.write("".join(os.path.basename(s) + "\n" for s in sorted(sheets)))
    return m3u


def _place_folder(batch, folder, title):
    """A folder: a Windows game, a disc game with its sheet, or a set of separate games."""
    if _exes(folder):
        return _place_windows(batch, folder, title)
    names = sorted(os.listdir(folder))
    sheets = [os.path.join(folder, n) for n in names if n.lower().endswith(SHEETS)
              and os.path.isfile(os.path.join(folder, n))]
    if sheets:
        m3us = [s for s in sheets if s.lower().endswith(".m3u")]
        discs = m3us or [s for s in sheets if s.lower().endswith((".cue", ".gdi"))]
        probe = discs[0]
        if m3us:
            # .m3u is listed under PlayStation; the first disc it names tells the real system
            first = next(iter(_sheet_files(probe)), None)
            full = _inside(folder, first) if first else None
            if full and os.path.isfile(full):
                probe = full
        kind, why = _system_of(probe)
        if kind is None or kind in ("windows", "native"):
            batch.notes.append(why or f"{title}: not a game folder ARMDeck knows")
            return False
        dest = os.path.join(paths.roms(), kind, title)
        if not _free_target(dest):
            batch.notes.append(f"{title}: a folder with that name is already in "
                               f"Emulation/roms/{kind}")
            return False
        _move(folder, dest)
        if not m3us and len(discs) > 1:
            main = _write_m3u(dest, discs, title)
        else:
            main = os.path.join(dest, os.path.basename(discs[0]))
        _tile_or_pending(batch, main, kind, _clean(title))
        return True
    files = [os.path.join(folder, n) for n in names if os.path.isfile(os.path.join(folder, n))]
    if any(not p.lower().endswith(ARCHIVES) and detect.detect(p) == "native" for p in files):
        return _place_app_folder(batch, folder, title)
    # separate games: each file on its own, the folder removed when it is left empty
    placed = False
    for n in names:
        p = os.path.join(folder, n)
        if _ignored(n):
            continue
        if os.path.isdir(p):
            placed |= _place_folder(batch, p, n)
        elif os.path.isfile(p):
            placed |= _place_file(batch, p)
    try:
        os.rmdir(folder)
    except OSError:
        pass
    return placed


# --- archives ---

def _archive_size(path):
    if path.lower().endswith(".zip"):
        with zipfile.ZipFile(path) as z:
            return sum(i.file_size for i in z.infolist())
    p = subprocess.run(["7z", "l", "-slt", "-ba", path], env=fetch.clean_env(),
                       stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=120)
    if p.returncode:
        raise OSError("7z could not read it")
    return sum(int(s) for s in re.findall(r"^Size = (\d+)$", p.stdout.decode("utf-8", "replace"),
                                         re.M))


def _unzip(path, dest):
    with zipfile.ZipFile(path) as z:
        for info in z.infolist():
            target = _inside(dest, info.filename)
            if target is None:
                raise OSError(f"it has a file outside its own folder ({info.filename})")
            if (info.external_attr >> 16) & 0o170000 == 0o120000:
                continue   # a symlink: never followed or made
            if info.is_dir():
                os.makedirs(target, exist_ok=True)
                continue
            os.makedirs(os.path.dirname(target), exist_ok=True)
            with z.open(info) as src, open(target, "wb") as out:
                shutil.copyfileobj(src, out, 1 << 20)


def _check_tree(dest):
    """Nothing unpacked may point outside dest: symlinks are removed."""
    for root, dirs, files in os.walk(dest):
        for n in dirs + files:
            p = os.path.join(root, n)
            if os.path.islink(p):
                os.unlink(p)


def _unpack(path, dest):
    if path.lower().endswith(".zip"):
        _unzip(path, dest)
    else:
        if shutil.which("7z") is None:
            raise OSError("7z is not installed in the container")
        p = subprocess.run(["7z", "x", "-y", f"-o{dest}", "--", path],
                           env=fetch.clean_env(), stdin=subprocess.DEVNULL,
                           stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, timeout=3600)
        if p.returncode:
            err = p.stderr.decode("utf-8", "replace").strip().splitlines()
            raise OSError(err[-1] if err else f"7z failed ({p.returncode})")
    _check_tree(dest)


def _place_archive(batch, path):
    name = os.path.basename(path)
    title = detect.display_name(path, "") or os.path.splitext(name)[0]
    try:
        size = _archive_size(path)
    except (OSError, zipfile.BadZipFile, subprocess.SubprocessError) as e:
        batch.notes.append(f"{name}: cannot read the archive ({e})")
        return False
    if paths.free_bytes(paths.games()) < size + RESERVE:
        batch.notes.append(f"{name}: not enough free space to unpack it "
                           f"({size / 1e9:.1f} GB inside)")
        return False
    work = os.path.join(_unpack_root(), str(int(time.time() * 1000)))
    os.makedirs(work)
    try:
        try:
            _unpack(path, work)
        except (OSError, zipfile.BadZipFile, subprocess.SubprocessError) as e:
            batch.notes.append(f"{name}: could not unpack it ({e})")
            return False
        entries = [n for n in os.listdir(work) if not _ignored(n)]
        root = work
        if len(entries) == 1 and os.path.isdir(os.path.join(work, entries[0])):
            root = os.path.join(work, entries[0])
        else:
            os.makedirs(os.path.join(work, ".top"))
            for n in os.listdir(work):
                if n != ".top":
                    os.rename(os.path.join(work, n), os.path.join(work, ".top", n))
            root = os.path.join(work, ".top")
        before = len(batch.tiles) + len(batch.placed)
        placed = _place_folder_nested(batch, root, title)
        if not placed and len(batch.tiles) + len(batch.placed) == before:
            batch.notes.append(f"{name}: nothing in it could be placed; the archive stays")
            return False
        # what could not be placed goes back to the Inbox as a folder, the archive goes away
        if os.path.isdir(root) and os.listdir(root):
            back = os.path.join(inbox(), title)
            if _free_target(back):
                os.rename(root, back)
                batch.notes.append(f"{title}: some files from {name} were left in the Inbox")
        os.unlink(path)
        return True
    finally:
        emulators._rmtree(work)


def _place_folder_nested(batch, folder, title):
    """A folder unpacked from an archive. One level only: an archive inside it is placed if it
    is a cartridge game, never unpacked again (no endless or exploding archives)."""
    if _exes(folder) or any(n.lower().endswith(SHEETS) for n in os.listdir(folder)):
        return _place_folder(batch, folder, title)
    placed = False
    for n in sorted(os.listdir(folder)):
        p = os.path.join(folder, n)
        if os.path.isdir(p):
            placed |= _place_folder_nested(batch, p, n)
        elif n.lower().endswith(ARCHIVES):
            kind = detect.detect(p)
            if kind and not kind.startswith(("unsupported:", "choose:")):
                placed |= _place_rom(batch, p, kind)
            else:
                batch.notes.append(f"{n}: an archive inside an archive; unpack it first")
        elif os.path.isfile(p):
            placed |= _place_file(batch, p)
    return placed


# --- a pass over the Inbox ---

def _claimed_by_sheets(entries):
    """Top-level files a top-level sheet names: they move with their sheet, not on their own."""
    claimed = []
    for p in entries:
        if p.lower().endswith(SHEETS) and os.path.isfile(p):
            _sheet_closure(p, claimed)
    return set(claimed)


def scan(only_new=True):
    """One pass: place everything in the Inbox that is not still being written. With only_new,
    what was left before and has not changed is not reported again."""
    box = inbox()
    os.makedirs(box, exist_ok=True)
    left_before = _load(LEFT) if only_new else {}
    left_now = {}
    batch = Batch()
    entries = [os.path.join(box, n) for n in sorted(os.listdir(box)) if not _ignored(n)]
    claimed = _claimed_by_sheets(entries)
    # sheets first (.m3u before the .cue files it lists): they take their files with them
    entries.sort(key=lambda p: (not p.lower().endswith(".m3u"), not p.lower().endswith(SHEETS), p))
    now = time.time()
    for p in entries:
        if not os.path.lexists(p) or (os.path.realpath(p) in claimed
                                      and not p.lower().endswith(".m3u")):
            continue
        sig = _signature(p)
        if sig is None:
            continue
        if now - sig[1] < QUIET:
            batch.waiting = True   # changed a moment ago; the watcher comes back to it
            continue
        name = os.path.basename(p)
        if left_before.get(name) == sig:
            left_now[name] = sig
            continue
        try:
            if os.path.isdir(p):
                _place_folder(batch, p, name)
            else:
                _place_file(batch, p)
        except (OSError, ValueError, KeyError) as e:
            batch.notes.append(f"{name}: {e}")
        if os.path.lexists(p):
            left_now[name] = _signature(p)
    # tracks a sheet named but that stayed (the sheet failed) are remembered as left too
    for p in claimed:
        if os.path.lexists(p) and os.path.dirname(p) == os.path.realpath(box):
            left_now.setdefault(os.path.basename(p), _signature(p))
    if left_now != _load(LEFT):
        _save(LEFT, left_now)
    return batch


# --- the watcher ---

class _Inotify:
    def __init__(self):
        self.libc = ctypes.CDLL("libc.so.6", use_errno=True)
        self.fd = self.libc.inotify_init1(os.O_CLOEXEC | os.O_NONBLOCK)
        if self.fd < 0:
            raise OSError(ctypes.get_errno(), "inotify_init1 failed")
        self.wds = {}

    def add(self, path):
        wd = self.libc.inotify_add_watch(self.fd, os.fsencode(path), WATCH_MASK)
        if wd >= 0:
            self.wds[wd] = path

    def add_tree(self, path):
        self.add(path)
        for root, dirs, _ in os.walk(path):
            for d in dirs:
                self.add(os.path.join(root, d))

    def events(self):
        try:
            data = os.read(self.fd, 64 * 1024)
        except BlockingIOError:
            return
        pos = 0
        while pos + 16 <= len(data):
            wd, mask, _cookie, length = struct.unpack_from("iIII", data, pos)
            name = data[pos + 16:pos + 16 + length].rstrip(b"\0").decode("utf-8", "replace")
            pos += 16 + length
            yield self.wds.get(wd), mask, name

    def prune(self, root):
        """Stop watching folders moved out of root: a watch follows its folder, and a game
        folder in Windows/ or roms/ must not wake the Inbox when the game writes to it."""
        for wd, p in list(self.wds.items()):
            if not os.path.isdir(p) or not (p == root or p.startswith(root + os.sep)):
                self.libc.inotify_rm_watch(self.fd, wd)
                del self.wds[wd]

    def close(self):
        os.close(self.fd)


class Watcher:
    """Runs scan() when the Inbox has changed and settled. on_batch(view) gets what it did."""

    def __init__(self, on_batch, log):
        self.on_batch = on_batch
        self.log = log
        self.lock = threading.Lock()
        self.stop_r, self.stop_w = os.pipe()
        self.thread = None

    def start(self):
        if self.thread is None:
            self.thread = threading.Thread(target=self._run, name="armdeck-inbox", daemon=True)
            self.thread.start()

    def stop(self):
        os.write(self.stop_w, b"x")

    def scan_now(self, only_new=False):
        with self.lock:
            batch = scan(only_new)
        view = batch.view()
        if view["tiles"] or view["placed"] or view["notes"]:
            self.on_batch(view)
        return batch

    def _run(self):
        try:
            self.scan_now(only_new=True)
        except OSError as e:
            self.log(f"inbox: first scan failed: {e}")
        try:
            ino = _Inotify()
            ino.add_tree(inbox())
        except OSError as e:
            self.log(f"inbox: no inotify ({e}); the Inbox is checked when the Library opens")
            return
        writing = set()     # files created and not closed yet
        dirty = False
        last = 0.0
        while True:
            if dirty:
                # wake when the batch should have settled, or at once for new events
                timeout = max(0.5, QUIET - (time.time() - last))
            else:
                timeout = None
            ready, _, _ = select.select([ino.fd, self.stop_r], [], [], timeout)
            if self.stop_r in ready:
                ino.close()
                return
            if ino.fd in ready:
                for folder, mask, name in ino.events():
                    if mask & IN_Q_OVERFLOW:
                        dirty = True
                        continue
                    if folder is None:
                        continue
                    if mask & IN_DELETE_SELF and folder == inbox():
                        os.makedirs(inbox(), exist_ok=True)
                        ino.add(inbox())
                        continue
                    path = os.path.join(folder, name)
                    if mask & IN_ISDIR and mask & (IN_CREATE | IN_MOVED_TO):
                        ino.add_tree(path)
                    elif mask & IN_CREATE:
                        writing.add(path)
                    elif mask & (IN_CLOSE_WRITE | IN_MOVED_TO):
                        writing.discard(path)
                    dirty = True
                    last = time.time()
                continue
            # quiet for QUIET seconds
            writing = {p for p in writing if os.path.exists(p)}
            if writing:
                last = time.time()
                continue
            try:
                dirty = self.scan_now(only_new=True).waiting
                last = time.time()
            except OSError as e:
                self.log(f"inbox: scan failed: {e}")
                dirty = False
            ino.prune(inbox())
