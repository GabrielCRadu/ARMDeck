#!/usr/bin/env python3
# op8-launch-options.py (armdeck): read or set a game's Steam Launch Options without typing them
# on a controller. Steam keeps them in userdata/<account>/config/localconfig.vdf and rewrites that
# file when it exits, so Steam must be stopped first (systemctl --user stop steam-gs).
#   python3 op8-launch-options.py 203160                      show the current options
#   python3 op8-launch-options.py 203160 VAR=1 %command%      set them (the words are joined)
#   python3 op8-launch-options.py 203160 --clear              remove them
# A copy of the file is kept as localconfig.vdf.armdeck-bak before every change.
import glob
import os
import shutil
import sys

STEAM = os.path.expanduser("~/.local/share/Steam")


def steam_running():
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                cmd = f.read().split(b"\0")[0]
        except OSError:
            continue
        if cmd.endswith(b"/steamrtarm64/steam") or cmd.endswith(b"/steamwebhelper"):
            return True
    return False


def tokenize(text):
    # Tokens: ("str", raw text between the quotes, escapes kept as they are), "{" and "}".
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c in " \t\r\n":
            i += 1
        elif c == "/" and text.startswith("//", i):
            i = text.find("\n", i)
            i = n if i < 0 else i
        elif c in "{}":
            yield c
            i += 1
        elif c == '"':
            j = i + 1
            while j < n and text[j] != '"':
                j += 2 if text[j] == "\\" else 1
            if j >= n:
                raise ValueError("unterminated string")
            yield ("str", text[i + 1:j])
            i = j + 1
        else:
            raise ValueError(f"unexpected character {c!r} at offset {i}")


def parse(tokens):
    # A block is a list of [key, value]; value is a raw string or another block.
    out = []
    for tok in tokens:
        if tok == "}":
            return out
        if tok == "{" or tok[0] != "str":
            raise ValueError("expected a key")
        key = tok[1]
        val = next(tokens)
        if val == "{":
            out.append([key, parse(tokens)])
        elif val != "}" and val[0] == "str":
            out.append([key, val[1]])
        else:
            raise ValueError(f"bad value for {key}")
    return out


def dump(block, depth=0):
    tab = "\t" * depth
    lines = []
    for key, val in block:
        if isinstance(val, list):
            lines.append(f'{tab}"{key}"')
            lines.append(f"{tab}{{")
            lines.extend(dump(val, depth + 1))
            lines.append(f"{tab}}}")
        else:
            lines.append(f'{tab}"{key}"\t\t"{val}"')
    return lines


def child(block, key, create=False):
    for k, v in block:
        if k.lower() == key.lower() and isinstance(v, list):
            return v
    if not create:
        return None
    new = []
    block.append([key, new])
    return new


def main():
    if len(sys.argv) < 2 or not sys.argv[1].isdigit():
        sys.exit(__doc__ or "usage: op8-launch-options.py APPID [options... | --clear]")
    appid, words = sys.argv[1], sys.argv[2:]
    files = glob.glob(f"{STEAM}/userdata/*/config/localconfig.vdf")
    if len(files) != 1:
        sys.exit(f"expected one localconfig.vdf, found {len(files)}")
    path = files[0]
    with open(path, encoding="utf-8") as f:
        tree = parse(iter(list(tokenize(f.read())) + ["}"]))
    root = child(tree, "UserLocalConfigStore")
    if root is None:
        sys.exit("UserLocalConfigStore missing, not touching the file")
    apps = child(child(child(child(root, "Software", True), "Valve", True), "Steam", True), "apps", True)
    app = child(apps, appid, create=bool(words))
    current = None
    if app is not None:
        current = next((v for k, v in app if k == "LaunchOptions"), None)
    print(f"{appid}: current Launch Options: {current!r}")
    if not words:
        return
    if steam_running():
        sys.exit("Steam is running; stop it first: systemctl --user stop steam-gs")
    app[:] = [kv for kv in app if kv[0] != "LaunchOptions"]
    if words != ["--clear"]:
        value = " ".join(words).replace("\\", "\\\\").replace('"', '\\"')
        app.append(["LaunchOptions", value])
    shutil.copy2(path, path + ".armdeck-bak")
    tmp = path + ".armdeck-new"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write("\n".join(dump(tree)) + "\n")
    # check the new file parses to the same tree before it replaces the old one
    with open(tmp, encoding="utf-8") as f:
        if parse(iter(list(tokenize(f.read())) + ["}"])) != tree:
            os.unlink(tmp)
            sys.exit("round-trip check failed, file not changed")
    os.replace(tmp, path)
    print(f"{appid}: new Launch Options: {' '.join(words) if words != ['--clear'] else None!r}")


if __name__ == "__main__":
    main()
