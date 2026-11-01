# Downloads: HTTPS only, streamed to a ".part" file next to the target, the sha256 computed while
# it is written, renamed into place only when it matches. Nothing half-downloaded or altered is
# ever left under the real name.
import hashlib
import os
import ssl
import subprocess
import urllib.request

# Decky is a PyInstaller bundle; the container's own CA list is the one kept up to date by Fedora
CA_FILES = ("/etc/pki/tls/certs/ca-bundle.crt", "/etc/ssl/certs/ca-certificates.crt")
CHUNK = 1 << 20
USER_AGENT = "ARMDeck-Library/1"


class Cancelled(Exception):
    pass


def ssl_context():
    for ca in CA_FILES:
        if os.path.exists(ca):
            return ssl.create_default_context(cafile=ca)
    return ssl.create_default_context()


def download(url, dest, sha256=None, progress=None, cancel=None, timeout=30):
    """Download url to dest. With sha256, refuse a file that does not match. Returns the sha256."""
    if not url.startswith("https://"):
        raise ValueError(f"not an HTTPS address: {url}")
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    part = dest + ".part"
    digest = hashlib.sha256()
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=ssl_context()) as resp, \
                open(part, "wb") as out:
            total = int(resp.headers.get("Content-Length") or 0)
            done = 0
            while True:
                if cancel is not None and cancel.is_set():
                    raise Cancelled()
                chunk = resp.read(CHUNK)
                if not chunk:
                    break
                out.write(chunk)
                digest.update(chunk)
                done += len(chunk)
                if progress:
                    progress(done, total)
        got = digest.hexdigest()
        if sha256 and got != sha256.lower():
            raise ValueError(f"checksum mismatch for {os.path.basename(dest)}: "
                             f"expected {sha256}, got {got}")
        os.replace(part, dest)
        return got
    finally:
        if os.path.exists(part):
            os.unlink(part)


# Decky's loader exports its unpack folder as LD_LIBRARY_PATH; a program started with it loads
# the bundle's libraries instead of the container's and can fail (Armada's proc.py, the same fix).
def clean_env(extra=None):
    env = dict(os.environ)
    original = env.pop("LD_LIBRARY_PATH_ORIG", None)
    if original:
        env["LD_LIBRARY_PATH"] = original
    else:
        env.pop("LD_LIBRARY_PATH", None)
    if extra:
        env.update(extra)
    return env


def run(cmd, timeout=1800, cwd=None):
    """Run a container command with a clean environment; returns (exit code, last output lines)."""
    p = subprocess.run(cmd, env=clean_env(), stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                       stderr=subprocess.STDOUT, timeout=timeout, cwd=cwd)
    tail = p.stdout.decode("utf-8", "replace").strip().splitlines()[-5:]
    return p.returncode, "\n".join(tail)
