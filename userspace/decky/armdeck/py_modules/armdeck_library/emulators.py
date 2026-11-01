# The emulator catalog (catalog.json in the plugin): what is installed, and installing or removing
# one emulator at a time in a background thread. Each emulator lives in its own folder,
# ~/games/Emulation/emulators/<id>/, with armdeck-installed.json describing what was put there.
import json
import os
import shutil
import threading
import time
import zipfile

from . import fetch, paths

RECORD = "armdeck-installed.json"
# kept free on the games partition after an install, for saves, shader caches and Steam
RESERVE = 1 << 30
# An AppImage is unpacked once, at install, into app/ next to it, and the tile starts app/AppRun:
# without FUSE in the container an AppImage unpacks itself into /tmp, which is in RAM, at every
# start (231 MB for PPSSPP, 2026-10-30). STAMP names the AppImage the copy came from; armdeck-run
# compares it, in the same format, and starts the AppImage itself when they differ.
APP = "app"
STAMP = ".armdeck-appimage"
# the unpacked size against the download, with room to spare (PPSSPP: 48 MB, 231 MB unpacked)
UNPACK_FACTOR = 6
APPIMAGE_TYPES = ("appimage", "appimage-zip")

_lock = threading.Lock()
_job = None


def catalog():
    with open(os.path.join(paths.PLUGIN, "catalog.json")) as f:
        return {e["id"]: e for e in json.load(f)["emulators"]}


def record(emu_id):
    try:
        with open(os.path.join(paths.emulator(emu_id), RECORD)) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def installed(entry):
    rec = record(entry["id"])
    if rec is None:
        return None
    if entry["install"]["type"] == "dnf" and not os.path.exists(entry["install"]["exec"]):
        return None   # the container was recreated: the package is gone, the record stayed
    return rec


def _write_record(emu_id, rec):
    d = paths.emulator(emu_id)
    os.makedirs(d, exist_ok=True)
    tmp = os.path.join(d, RECORD + ".new")
    with open(tmp, "w") as f:
        json.dump(rec, f, indent=1)
    os.replace(tmp, os.path.join(d, RECORD))


class Job:
    def __init__(self, emu_id, action):
        self.emu_id = emu_id
        self.action = action        # "install" or "remove"
        self.phase = "starting"
        self.done = 0
        self.total = 0
        self.error = None
        self.finished = False
        self.cancel = threading.Event()

    def view(self):
        return {"id": self.emu_id, "action": self.action, "phase": self.phase,
                "done": self.done, "total": self.total, "error": self.error,
                "finished": self.finished}

    def progress(self, done, total):
        self.done, self.total = done, total


def current_job():
    return _job.view() if _job else None


def status():
    jobs = current_job()
    out = []
    for entry in catalog().values():
        rec = installed(entry)
        out.append({"id": entry["id"], "name": entry["name"], "systems": entry["systems"],
                    "source": entry["source"], "size": entry["size"],
                    "installed": rec is not None,
                    "version": rec.get("version") if rec else None,
                    "available": entry["install"].get("version", "Fedora package")})
    return {"emulators": out, "job": jobs, "free": paths.free_bytes(paths.emulators())}


def start(emu_id, action, on_finish):
    """Start installing, removing or unpacking one emulator; on_finish(job view) runs when it
    ends."""
    global _job
    entry = catalog().get(emu_id)
    if entry is None:
        raise ValueError(f"unknown emulator {emu_id}")
    with _lock:
        if _job is not None and not _job.finished:
            raise RuntimeError(f"{_job.emu_id} is still being handled; wait for it to finish")
        job = Job(emu_id, action)
        _job = job
    target = {"install": _install, "remove": _remove, "unpack": _unpack_installed}[action]

    def body():
        try:
            target(entry, job)
            job.phase = "done"
        except fetch.Cancelled:
            job.error = "cancelled"
        except Exception as e:   # shown to the user as it is
            job.error = str(e) or type(e).__name__
        finally:
            job.finished = True
            on_finish(job.view())

    threading.Thread(target=body, name=f"armdeck-{action}-{emu_id}", daemon=True).start()
    return job.view()


def cancel():
    if _job is not None and not _job.finished:
        _job.cancel.set()


def _check_space(entry, download=True):
    size = entry.get("size", 0)
    need = RESERVE + (int(size * 1.2) if download else 0)
    if entry["install"]["type"] in APPIMAGE_TYPES:
        need += size * UNPACK_FACTOR
    free = paths.free_bytes(paths.emulators())
    if free < need:
        raise RuntimeError(f"not enough space: {free >> 20} MB free, {need >> 20} MB needed")


def _install(entry, job):
    _check_space(entry)
    inst = entry["install"]
    kind = inst["type"]
    d = paths.emulator(entry["id"])
    os.makedirs(d, exist_ok=True)
    if kind == "appimage":
        name = os.path.basename(inst["url"])
        job.phase = "download"
        fetch.download(inst["url"], os.path.join(d, name + ".new"), inst["sha256"],
                       job.progress, job.cancel)
        _place_appimage(d, name)
        files = {name: inst["sha256"]}
    elif kind == "appimage-zip":
        job.phase = "download"
        archive = os.path.join(d, "download.zip")
        fetch.download(inst["url"], archive, inst["sha256"], job.progress, job.cancel)
        job.phase = "unpack"
        try:
            name = _unzip_appimage(archive, d)
        finally:
            os.unlink(archive)
        files = {name: None}
    elif kind == "dnf":
        files = _install_dnf(entry, job)
    else:
        raise ValueError(f"unknown install type {kind}")
    rec = {"id": entry["id"], "version": inst.get("version", "Fedora"), "files": files,
           "installed": time.strftime("%F %T")}
    if kind in APPIMAGE_TYPES:
        try:
            _unpack(d, name, job)
        except Exception as e:
            # the tile still works, armdeck-run then starts the AppImage itself; the plugin tries
            # again when it loads next (pending_unpacks)
            rec["unpack_error"] = str(e) or type(e).__name__
    _write_record(entry["id"], rec)


def _place_appimage(d, name):
    """The verified download becomes the only AppImage in the folder."""
    new = os.path.join(d, name + ".new")
    os.chmod(new, 0o755)
    for old in os.listdir(d):
        if old.endswith(".AppImage") and old != name:
            os.unlink(os.path.join(d, old))
    os.replace(new, os.path.join(d, name))


def _unzip_appimage(archive, d):
    with zipfile.ZipFile(archive) as z:
        members = [m for m in z.namelist() if m.endswith(".AppImage")]
        if len(members) != 1:
            raise RuntimeError(f"expected one AppImage in the archive, found {members}")
        name = os.path.basename(members[0])
        with z.open(members[0]) as src, open(os.path.join(d, name + ".new"), "wb") as out:
            shutil.copyfileobj(src, out, fetch.CHUNK)
    _place_appimage(d, name)
    return name


def stamp(path):
    """What identifies an AppImage file; armdeck-run builds the same line."""
    st = os.stat(path)
    return f"{os.path.basename(path)} {st.st_size} {st.st_mtime_ns}"


def _appimage_in(d):
    try:
        names = sorted(n for n in os.listdir(d) if n.endswith(".AppImage"))
    except OSError:
        names = []
    return os.path.join(d, names[0]) if names else None


def _unpacked_current(d, image):
    try:
        with open(os.path.join(d, APP, STAMP)) as f:
            return f.read().strip() == stamp(image)
    except OSError:
        return False


def _rmtree(path):
    # an unpacked AppImage can hold read-only folders, whose entries cannot be removed as they are
    def writable_parent(func, p, exc):
        os.chmod(os.path.dirname(p), 0o755)
        func(p)

    if os.path.lexists(path):
        shutil.rmtree(path, onexc=writable_parent)


# The "anylinux" AppImages (sharun: PPSSPP, Dolphin, Azahar) bring their own Mesa (26.0.6 in
# PPSSPP 1.20.4) and, on aarch64, add every Vulkan driver of the system to theirs: PPSSPP had two
# Turnips, lvp (Vulkan on the CPU, with LLVM) and dzn loaded at once (2026-10-30). Without their
# driver list, and with SHARUN_ALLOW_SYS_VKICD=0 from armdeck-run, sharun leaves VK_DRIVER_FILES as
# the Steam session set it: the container's Turnip, the Mesa we keep up to date. OpenGL still
# uses the bundled Mesa.
def _drop_bundled_vulkan(root):
    icd = os.path.join(root, "share", "vulkan", "icd.d")
    if os.path.isfile(os.path.join(root, "sharun")) and os.path.isdir(icd):
        _rmtree(icd)
        try:
            os.rmdir(os.path.dirname(icd))   # share/vulkan, when nothing else is in it
        except OSError:
            pass


def _unpack(d, name, job=None):
    """Unpack the AppImage d/name into d/app; the old copy goes only once the new one is whole."""
    if job:
        job.phase, job.done, job.total = "unpack", 0, 0
    work = os.path.join(d, ".unpack")
    _rmtree(work)
    os.makedirs(work)
    try:
        # the AppImage's own runtime, which also reads the DwarFS images of the "anylinux" builds
        rc, out = fetch.run([os.path.join(d, name), "--appimage-extract"], cwd=work, timeout=900)
        # the classic runtime makes squashfs-root; uruntime makes AppDir, and squashfs-root as a
        # link to it
        root = next((p for p in (os.path.join(work, n) for n in ("squashfs-root", "AppDir"))
                     if os.path.isdir(p)), None)
        if rc != 0 or root is None or not os.path.isfile(os.path.join(root, "AppRun")):
            raise RuntimeError(f"unpacking {name} failed ({rc}): {out}")
        root = os.path.realpath(root)
        _drop_bundled_vulkan(root)
        with open(os.path.join(root, STAMP), "w") as f:
            f.write(stamp(os.path.join(d, name)) + "\n")
        app = os.path.join(d, APP)
        if os.path.lexists(app):
            os.replace(app, os.path.join(work, "old"))
        os.replace(root, app)
    finally:
        _rmtree(work)


def pending_unpacks():
    """Installed AppImage emulators with no unpacked copy of their current AppImage (installed
    before the Library unpacked them, or the unpack failed)."""
    out = []
    for entry in catalog().values():
        if entry["install"]["type"] in APPIMAGE_TYPES and installed(entry):
            d = paths.emulator(entry["id"])
            image = _appimage_in(d)
            if image and not _unpacked_current(d, image):
                out.append(entry["id"])
    return out


def _unpack_installed(entry, job):
    d = paths.emulator(entry["id"])
    image = _appimage_in(d)
    if image is None:
        raise RuntimeError("no AppImage to unpack")
    _check_space(entry, download=False)
    _unpack(d, os.path.basename(image), job)


def _install_dnf(entry, job):
    inst = entry["install"]
    job.phase = "packages"
    # the container's own root (rootless podman: root there is this user on the host)
    rc, out = fetch.run(["sudo", "-n", "dnf", "install", "-y", "--setopt=install_weak_deps=False"]
                        + inst["packages"])
    if rc != 0 or not os.path.exists(inst["exec"]):
        raise RuntimeError(f"dnf install failed ({rc}): {out}")
    files = {}
    cores = os.path.join(paths.emulator(entry["id"]), "cores")
    os.makedirs(cores, exist_ok=True)
    for i, core in enumerate(inst.get("cores", [])):
        job.phase = f"core {i + 1} of {len(inst['cores'])}: {core}"
        so = f"{core}_libretro.so"
        archive = os.path.join(cores, so + ".zip")
        files[so + ".zip"] = fetch.download(inst["cores_url"] + so + ".zip", archive, None,
                                            job.progress, job.cancel)
        try:
            with zipfile.ZipFile(archive) as z, z.open(so) as src, \
                    open(os.path.join(cores, so + ".new"), "wb") as out:
                shutil.copyfileobj(src, out, fetch.CHUNK)
            os.replace(os.path.join(cores, so + ".new"), os.path.join(cores, so))
        finally:
            os.unlink(archive)
    return files


def _remove(entry, job):
    job.phase = "remove"
    if entry["install"]["type"] == "dnf":
        rc, out = fetch.run(["sudo", "-n", "dnf", "remove", "-y"] + entry["install"]["packages"])
        if rc != 0:
            raise RuntimeError(f"dnf remove failed ({rc}): {out}")
    d = paths.emulator(entry["id"])
    # only the folder the Library made for this emulator; the user's games and saves are elsewhere
    if os.path.isdir(d) and os.path.dirname(d) == paths.emulators():
        _rmtree(d)
