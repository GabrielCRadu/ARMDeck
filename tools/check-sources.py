#!/usr/bin/env python3
"""Check the outside projects listed in docs/sources.md for news since the last check.

Usage:
  python tools/check-sources.py                      # check everything, print what changed
  python tools/check-sources.py --if-older-than 20   # only if the last check is older than 20 h

Every table row of docs/sources.md with a link in the first column and a `Watch` column is
checked: new commits (GitHub or GitLab API, optionally only those touching a path), new or moved
branches and new tags (git ls-remote), new GitHub releases. The state is kept in
tools/.sources-state.json (not committed); the first run only records it.
"""
import argparse
import datetime as dt
import json
import os
import re
import subprocess
import sys
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCES = os.path.join(ROOT, "docs", "sources.md")
STATE = os.path.join(ROOT, "tools", ".sources-state.json")
ROW = re.compile(r"^\|\s*\[([^\]]+)\]\((https?://[^)\s]+)\)\s*\|\s*`([^`]+)`\s*\|")
MAX_LISTED = 15


def parse_sources(path):
    items = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            m = ROW.match(line)
            if not m:
                continue
            name, url, watch = m.groups()
            for part in watch.split(";"):
                kind, _, arg = part.strip().partition(":")
                items.append({"name": name, "url": url.rstrip("/"), "kind": kind.strip(),
                              "arg": arg.strip(), "key": f"{url.rstrip('/')}|{part.strip()}"})
    return items


def github_token():
    token = os.environ.get("GITHUB_TOKEN")
    if token:
        return token
    try:
        out = subprocess.run(["gh", "auth", "token"], capture_output=True, text=True, timeout=20)
        return out.stdout.strip() or None
    except (OSError, subprocess.SubprocessError):
        return None


TOKEN = None


def get_json(url):
    headers = {"User-Agent": "armdeck-check-sources", "Accept": "application/json"}
    if TOKEN and url.startswith("https://api.github.com/"):
        headers["Authorization"] = f"Bearer {TOKEN}"
    with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=30) as r:
        return json.load(r)


def api_base(url):
    u = urllib.parse.urlparse(url)
    path = u.path.strip("/").removesuffix(".git")
    if u.netloc == "github.com":
        return "github", f"https://api.github.com/repos/{path}"
    return "gitlab", f"https://{u.netloc}/api/v4/projects/{urllib.parse.quote(path, safe='')}"


def query(params):
    return urllib.parse.urlencode({k: v for k, v in params.items() if v})


def commits(item, old):
    host, base = api_base(item["url"])
    if host == "github":
        rows = get_json(f"{base}/commits?{query({'per_page': 1, 'path': item['arg']})}")
        latest = {"sha": rows[0]["sha"], "date": rows[0]["commit"]["committer"]["date"]} if rows else {}
    else:
        rows = get_json(f"{base}/repository/commits?{query({'per_page': 1, 'path': item['arg']})}")
        latest = {"sha": rows[0]["id"], "date": rows[0]["committed_date"]} if rows else {}
    if not latest:
        raise RuntimeError("no commits found (wrong path?)")
    news = []
    if old and old.get("sha") != latest["sha"]:
        params = {"per_page": MAX_LISTED + 1, "path": item["arg"], "since": old.get("date")}
        if host == "github":
            for c in get_json(f"{base}/commits?{query(params)}"):
                if c["sha"] != old.get("sha"):
                    news.append(f"{c['commit']['committer']['date'][:10]} {c['sha'][:9]} "
                                f"{c['commit']['message'].splitlines()[0]}")
        else:
            for c in get_json(f"{base}/repository/commits?{query(params)}"):
                if c["id"] != old.get("sha"):
                    news.append(f"{c['committed_date'][:10]} {c['id'][:9]} {c['title']}")
        if not news:
            news.append(f"head moved to {latest['sha'][:9]} ({latest['date'][:10]})")
    return latest, news


def ls_remote(item, old):
    flag = "--heads" if item["kind"] == "heads" else "--tags"
    out = subprocess.run(["git", "ls-remote", flag, item["url"]], capture_output=True, text=True,
                         timeout=120)
    if out.returncode != 0:
        raise RuntimeError(out.stderr.strip().splitlines()[-1] if out.stderr.strip() else "git failed")
    pattern = re.compile(item["arg"]) if item["arg"] else None
    refs = {}
    for line in out.stdout.splitlines():
        sha, _, ref = line.partition("\t")
        if ref.endswith("^{}"):
            continue
        name = ref.split("/", 2)[-1]
        if pattern is None or pattern.search(name):
            refs[name] = sha
    news = []
    if old is not None:
        for name in sorted(refs):
            if name not in old:
                news.append(f"new {'branch' if item['kind'] == 'heads' else 'tag'}: {name}")
            elif item["kind"] == "heads" and old[name] != refs[name]:
                news.append(f"branch moved: {name} ({old[name][:9]} -> {refs[name][:9]})")
        if item["kind"] == "heads":
            news += [f"branch removed: {name}" for name in sorted(old) if name not in refs]
    return refs, news[:MAX_LISTED]


def releases(item, old):
    host, base = api_base(item["url"])
    if host != "github":
        return ls_remote(dict(item, kind="tags"), old)
    rows = [r for r in get_json(f"{base}/releases?per_page=10") if not r.get("draft")]
    tags = [r["tag_name"] for r in rows]
    news = []
    if old is not None:
        news = [f"new release: {r['tag_name']} ({(r.get('published_at') or '')[:10]})"
                f"{' pre-release' if r.get('prerelease') else ''}"
                for r in rows if r["tag_name"] not in old]
    return tags, news


CHECKS = {"commits": commits, "heads": ls_remote, "tags": ls_remote, "releases": releases}


def check(item, state):
    fn = CHECKS.get(item["kind"])
    if fn is None:
        return item, None, None, f"unknown watch '{item['kind']}'"
    try:
        new_state, news = fn(item, state.get(item["key"]))
        return item, new_state, news, None
    except Exception as e:  # report and keep the old state for this source
        return item, None, None, str(e)


def main():
    global TOKEN
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--if-older-than", type=float, metavar="HOURS")
    args = ap.parse_args()
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    state = {}
    if os.path.exists(STATE):
        with open(STATE, encoding="utf-8") as f:
            state = json.load(f)
    now = dt.datetime.now(dt.timezone.utc)
    last = state.get("_last_check")
    if args.if_older_than and last:
        age = now - dt.datetime.fromisoformat(last)
        if age < dt.timedelta(hours=args.if_older_than):
            print(f"Sources were checked {age.total_seconds() / 3600:.1f} h ago; skipping.")
            return

    TOKEN = github_token()
    items = parse_sources(SOURCES)
    with ThreadPoolExecutor(max_workers=8) as pool:
        results = list(pool.map(lambda it: check(it, state), items))

    print(f"Checked {len(items)} items from docs/sources.md at {now:%Y-%m-%d %H:%M} UTC"
          + (f" (last check {last[:16].replace('T', ' ')} UTC)" if last else " (first run)"))
    changed = unchanged = baseline = errors = 0
    for item, new_state, news, err in results:
        label = f"{item['name']} [{item['kind']}{': ' + item['arg'] if item['arg'] else ''}]"
        if err:
            errors += 1
            print(f"ERROR    {label}: {err}")
            continue
        if item["key"] not in state:
            baseline += 1
        elif news:
            changed += 1
            print(f"NEW      {label}  {item['url']}")
            for n in news:
                print(f"           {n}")
        else:
            unchanged += 1
        state[item["key"]] = new_state
    state["_last_check"] = now.isoformat()
    with open(STATE, "w", encoding="utf-8") as f:
        json.dump(state, f, indent=1, sort_keys=True)
    print(f"Changed: {changed}, unchanged: {unchanged}, recorded for the first time: {baseline}, "
          f"errors: {errors}")


if __name__ == "__main__":
    main()
