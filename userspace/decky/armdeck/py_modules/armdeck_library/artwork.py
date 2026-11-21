# Artwork for the Library's tiles (part 5): for an emulated game, its box art, title screen and
# a screenshot from libretro-thumbnails (thumbnails.libretro.com, no account needed). The
# frontend hands them to Steam (SteamClient.Apps.SetCustomArtworkForApp), which keeps its own
# copy, so nothing is stored here but the server's name lists.
# Names: libretro names its files after the No-Intro / Redump title ("Advance Wars (USA)"), with
# &*/:`<>?\|" replaced by "_". A ROM named that way is found at once; otherwise the folder's
# name list (1-3 MB, fetched once and kept for LIST_DAYS) is searched for the same title without
# its tags, preferring the ROM's own region.
# PC games (SteamGridDB) need the user's API key: not done yet.
import base64
import json
import os
import re
import time
import urllib.parse

from . import detect, fetch, paths

BASE = "https://thumbnails.libretro.com"
# libretro's folder -> Steam's asset type (0 portrait capsule, 1 hero, 3 wide capsule)
KINDS = (("Named_Boxarts", "grid_p"), ("Named_Titles", "grid_l"), ("Named_Snaps", "hero"))
LIMIT = 8 << 20
LIST_DAYS = 30
LISTS = os.path.join(paths.SETTINGS, "art-lists")
REGIONS = ("USA", "World", "Europe", "Japan")


def libretro_name(title):
    return re.sub(r'[&*/:`<>?\\|"]', "_", title)


def bare(title):
    """A title without its tags, for comparing: "The Legend of Zelda (USA) (Rev 1)" and
    "Legend of Zelda, The (USA)" give the same, also before a subtitle ("Legend of Zelda, The -
    A Link to the Past")."""
    t = re.sub(r"\s*[\(\[][^\)\]]*[\)\]]", "", title)
    parts = []
    for part in t.split(" - "):
        m = re.match(r"^(.*), (The|A|An)$", part.strip())
        parts.append(f"{m.group(2)} {m.group(1)}" if m else part)
    return re.sub(r"[^a-z0-9]", "", " ".join(parts).lower())


def _regions(title):
    return {r for r in REGIONS if re.search(rf"\b{r}\b", title)}


def _names(folder, kind):
    """The file names (without .png) in one libretro folder, cached for LIST_DAYS."""
    cache = os.path.join(LISTS, f"{folder}.{kind}.json".replace("/", "_"))
    try:
        if time.time() - os.stat(cache).st_mtime < LIST_DAYS * 86400:
            with open(cache) as f:
                return json.load(f)
    except (OSError, ValueError):
        pass
    url = f"{BASE}/{urllib.parse.quote(folder)}/{kind}/"
    page = fetch.get(url, 16 << 20, timeout=60)
    if page is None:
        return []
    names = [urllib.parse.unquote(h)[:-4] for h in
             re.findall(r'href="([^"?/][^"]*\.png)"', page.decode("utf-8", "replace"))]
    os.makedirs(LISTS, exist_ok=True)
    tmp = cache + ".new"
    with open(tmp, "w") as f:
        json.dump(names, f)
    os.replace(tmp, cache)
    return names


def best_match(title, names):
    """The name in names for the same game as title, or None."""
    key = bare(title)
    same = [n for n in names if bare(n) == key]
    if not same:
        return None
    want = _regions(title)
    # the ROM's region first, then the plainest name (no "(Virtual Console)" or "(Beta)"),
    # then USA, World, Europe, Japan
    same.sort(key=lambda n: (not (_regions(n) & want) if want else False,
                             len(re.findall(r"[\(\[]", n)),
                             [r not in _regions(n) for r in REGIONS], len(n)))
    return same[0]


def _fetch(folder, kind, name):
    url = f"{BASE}/{urllib.parse.quote(folder)}/{kind}/{urllib.parse.quote(libretro_name(name))}.png"
    data = fetch.get(url, LIMIT)
    return data if data and data[:8] == b"\x89PNG\r\n\x1a\n" else None


def for_game(path, kind):
    """{"grid_p": base64 PNG, ...} for an emulated game; empty when nothing was found or the
    network is down."""
    systems = detect.systems()
    if kind not in systems or not systems[kind].get("thumbs"):
        return {}
    folder = systems[kind]["thumbs"]
    # a game's file name ("Racer (USA).cue"); an .m3u is named after its folder, without tags
    title = os.path.splitext(os.path.basename(path))[0]
    out = {}
    try:
        name = title
        boxart = _fetch(folder, KINDS[0][0], name)
        if boxart is None:
            name = best_match(title, _names(folder, KINDS[0][0]))
            if name is None:
                return {}   # no box art under any near name: no titles or snaps either
            boxart = _fetch(folder, KINDS[0][0], name)
        if boxart:
            out[KINDS[0][1]] = base64.b64encode(boxart).decode()
        for lr_kind, steam in KINDS[1:]:
            data = _fetch(folder, lr_kind, name)
            if data:
                out[steam] = base64.b64encode(data).decode()
    except (OSError, ValueError):
        pass   # offline or a server error: the tile keeps what it has
    return out
