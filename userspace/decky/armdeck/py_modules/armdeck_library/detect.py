# What a file is, so the Library knows how to start it: a game for one of the systems in
# systems.json, a Windows program (Proton), a native ARM64 program, or nothing it can start.
# Extensions that belong to one system decide alone; the shared ones (.iso, .chd, .bin, .cso,
# .pbp, .rvz, .zip...) are read: only headers and a few sectors, never the whole file.
import json
import os
import re
import struct
import subprocess
import zipfile

from . import fetch, paths

SECTOR = 2048
RAW_SECTOR = 2352


def systems():
    with open(os.path.join(paths.PLUGIN, "library", "systems.json")) as f:
        return {s["id"]: s for s in json.load(f)["systems"]}


def by_extension():
    table = {}
    for s in systems().values():
        for ext in s["ext"]:
            table[ext] = s["id"]
    return table


def _read(f, offset, size):
    f.seek(offset)
    return f.read(size)


# --- disc images ---

def _iso9660_root(f, sector_size, data_offset):
    """The names in the root folder of an ISO 9660 image, or None if it is not one."""
    pvd = _read(f, 16 * sector_size + data_offset, SECTOR)
    if pvd[1:6] != b"CD001":
        return None
    root = pvd[156:156 + 34]
    extent, size = struct.unpack_from("<I", root, 2)[0], struct.unpack_from("<I", root, 10)[0]
    names = set()
    for i in range(min(size, 8 * SECTOR) // SECTOR):
        block = _read(f, (extent + i) * sector_size + data_offset, SECTOR)
        pos = 0
        while pos < len(block):
            length = block[pos]
            if length == 0:
                break
            name_len = block[pos + 32]
            name = block[pos + 33:pos + 33 + name_len].decode("ascii", "replace")
            names.add(name.split(";")[0].upper())
            pos += length
    return names, extent


def _iso_file(f, sector_size, data_offset, wanted):
    """The start of one root-folder file of an ISO 9660 image (SYSTEM.CNF is small)."""
    pvd = _read(f, 16 * sector_size + data_offset, SECTOR)
    root = pvd[156:156 + 34]
    extent = struct.unpack_from("<I", root, 2)[0]
    block = _read(f, extent * sector_size + data_offset, SECTOR)
    pos = 0
    while pos < len(block) and block[pos]:
        length, name_len = block[pos], block[pos + 32]
        name = block[pos + 33:pos + 33 + name_len].decode("ascii", "replace").split(";")[0]
        if name.upper() == wanted:
            start = struct.unpack_from("<I", block, pos + 2)[0]
            return _read(f, start * sector_size + data_offset, SECTOR)
        pos += length
    return None


def _playstation_or_psp(f, sector_size, data_offset):
    found = _iso9660_root(f, sector_size, data_offset)
    if found is None:
        return None
    names, _ = found
    if "PSP_GAME" in names or "UMD_DATA.BIN" in names:
        return "psp"
    if "SYSTEM.CNF" in names:
        cnf = _iso_file(f, sector_size, data_offset, "SYSTEM.CNF") or b""
        if re.search(rb"BOOT2\s*=", cnf):
            return "ps2"
        if re.search(rb"BOOT\s*=", cnf):
            return "psx"
    return None


def _nintendo_disc(f):
    head = _read(f, 0, 0x20)
    if len(head) < 0x20:
        return None
    if head[0x1C:0x20] == b"\xc2\x33\x9f\x3d":
        return "gc"
    if head[0x18:0x1C] == b"\x5d\x1c\x9e\xa3":
        return "wii"
    return None


def _sega_disc(head):
    """Sega's disc header in the first data sector (raw 2352-byte sectors start 16 bytes in)."""
    for off in (0, 16):
        tag = head[off:off + 16]
        if tag.startswith(b"SEGA SEGAKATANA"):
            return "dreamcast"
        if tag.startswith(b"SEGA SEGASATURN") or tag.startswith(b"SEGADISCSYSTEM"):
            return "unsupported:Sega Saturn or Sega CD (not in the Library yet)"
    return None


def _iso(path):
    with open(path, "rb") as f:
        return (_nintendo_disc(f) or _playstation_or_psp(f, SECTOR, 0)
                or _sega_disc(_read(f, 0, 32)))


def _bin(path):
    with open(path, "rb") as f:
        head = _read(f, 0, 0x200)
        if head[0x100:0x104] == b"SEGA":
            return "megadrive"
        sega = _sega_disc(head)
        if sega:
            return sega
        # a raw CD image: MODE2 sectors carry their data 24 bytes in, MODE1 16 bytes in
        for data_offset in (24, 16):
            system = _playstation_or_psp(f, RAW_SECTOR, data_offset)
            if system:
                return system
    return None


def _cue(path):
    """A .cue sheet: a PlayStation game unless its first track says otherwise."""
    try:
        with open(path, errors="replace") as f:
            m = re.search(r'FILE\s+"([^"]+)"', f.read(64 * 1024))
    except OSError:
        return "psx"
    if m:
        track = os.path.join(os.path.dirname(path), m.group(1))
        if os.path.exists(track):
            with open(track, "rb") as f:
                sega = _sega_disc(_read(f, 0, 32))
            if sega:
                return sega
    return "psx"


def _chd(path):
    """CHD (compressed disc image): its metadata says CD, GD-ROM or DVD."""
    with open(path, "rb") as f:
        head = _read(f, 0, 0x7C)
        if head[:8] != b"MComprHD":
            return None
        version = struct.unpack_from(">I", head, 12)[0]
        if version != 5:
            return "choose:psx,ps2,dreamcast"
        offset = struct.unpack_from(">Q", head, 0x30)[0]
        for _ in range(64):
            if not offset:
                break
            entry = _read(f, offset, 16)
            if len(entry) < 16:
                break
            tag = entry[:4]
            if tag == b"CHGD":
                return "dreamcast"
            if tag == b"DVD ":
                return "ps2"
            if tag in (b"CHCD", b"CHTR", b"CHT2"):
                return "psx"
            offset = struct.unpack_from(">Q", entry, 8)[0]
    return "choose:psx,ps2,dreamcast"


def _pbp(path):
    """A PSP EBOOT: a PSP game, or a PlayStation game converted for the PSP."""
    with open(path, "rb") as f:
        head = _read(f, 0, 0x28)
        if head[:4] != b"\x00PBP":
            return None
        psar = struct.unpack_from("<I", head, 0x24)[0]
        tag = _read(f, psar, 8)
    return "psx" if tag in (b"PSISOIMG", b"PSTITLEI") else "psp"


def _dolphin_compressed(path):
    with open(path, "rb") as f:
        head = _read(f, 0, 0x4C)
    if head[:4] in (b"RVZ\x01", b"WIA\x01") and len(head) >= 0x4C:
        return {1: "gc", 2: "wii"}.get(struct.unpack_from(">I", head, 0x48)[0], "gc")
    if head[:4] == b"\x01\xc0\x0b\xb1":
        return "wii" if struct.unpack_from("<I", head, 4)[0] == 1 else "gc"
    return None


def _cso(path):
    with open(path, "rb") as f:
        head = _read(f, 0, 24)
    if head[:4] not in (b"CISO", b"ZISO"):
        return None
    return "choose:psp,ps2"


# --- archives ---

def _archive_members(path):
    if path.lower().endswith(".zip"):
        with zipfile.ZipFile(path) as z:
            return [n for n in z.namelist() if not n.endswith("/")]
    rc = subprocess.run(["7z", "l", "-slt", "-ba", path], env=fetch.clean_env(),
                        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=60)
    return re.findall(r"^Path = (.+)$", rc.stdout.decode("utf-8", "replace"), re.M)


def _archive(path):
    """A zip or 7z with one cartridge game inside: RetroArch reads it without unpacking."""
    try:
        members = _archive_members(path)
    except (zipfile.BadZipFile, OSError, subprocess.SubprocessError):
        return None
    table = by_extension()
    found = {table[os.path.splitext(m)[1].lower()] for m in members
             if os.path.splitext(m)[1].lower() in table}
    if len(found) == 1:
        system = found.pop()
        if systems()[system]["emulator"] == "retroarch":
            return system
        return f"unsupported:a {systems()[system]['name']} game inside an archive; unpack it first"
    if any(m.lower().endswith(".exe") for m in members):
        return "unsupported:a Windows game inside an archive; unpack it first"
    return None


# --- programs ---

def _program(path):
    with open(path, "rb") as f:
        head = f.read(64)
    if head[:2] == b"MZ":
        return "windows"
    if head[:4] == b"\x7fELF":
        machine = struct.unpack_from("<H", head, 18)[0]
        if machine == 0xB7:
            return "native"
        if machine == 0x3E:
            return "unsupported:an x86 Linux program (only through Steam for now)"
        return "unsupported:a Linux program for another processor"
    if head[:2] == b"#!":
        return "native"
    return None


READERS = {".iso": _iso, ".gcm": _iso, ".bin": _bin, ".img": _bin, ".cue": _cue, ".chd": _chd,
           ".pbp": _pbp, ".rvz": _dolphin_compressed, ".wia": _dolphin_compressed,
           ".gcz": _dolphin_compressed, ".cso": _cso, ".zso": _cso, ".zip": _archive,
           ".7z": _archive}


def detect(path):
    """One of: a system id, "windows", "native", "choose:<ids>", "unsupported:<why>", None."""
    ext = os.path.splitext(path)[1].lower()
    try:
        if ext in READERS:
            return READERS[ext](path)
        table = by_extension()
        if ext in table:
            return table[ext]
        if ext in (".exe", ".appimage", ".sh") or not ext or os.access(path, os.X_OK):
            return _program(path)
    except OSError as e:
        return f"unsupported:cannot read the file ({e.strerror})"
    return None


# --- names ---

GENERIC = {"game", "launcher", "start", "play", "main", "run", "app", "bin", "win64", "win32",
           "x64", "binaries", "shipping"}


def display_name(path, kind):
    """A tile name: the file name without extension, region and dump tags; for a Windows
    program with a generic name, its folder."""
    stem = os.path.splitext(os.path.basename(path))[0]
    if kind == "windows":
        parent = os.path.basename(os.path.dirname(path))
        low = re.sub(r"[-_ ]?(win64|win32|x64|shipping)$", "", stem.lower())
        if low in GENERIC and parent:
            stem = parent
    name = re.sub(r"\s*[\(\[][^\)\]]*[\)\]]", "", stem)
    name = re.sub(r"[_\s]+", " ", name).strip() or stem
    m = re.match(r"^(.*), (The|A|An)$", name)
    if m:
        name = f"{m.group(2)} {m.group(1)}"
    return name
