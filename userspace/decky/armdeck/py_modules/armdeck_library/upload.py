# Files without a cable (Library part 4): a small upload page served by the phone, opened from
# a QR code in the Library. What arrives goes to the Inbox (inbox.py), which places it.
# Safety, since this listens on the network:
# - it runs only while the user has it on, and closes by itself after IDLE seconds without a
#   request;
# - it listens only on the WiFi address, and only when that address is a private (home network)
#   one; requests from any other address are refused, and the firewall rule
#   (userspace/system/61_armdeck_upload.nft) opens the port only on WiFi, only for private
#   addresses;
# - every address carries a fresh random token (128 bits); a wrong one is answered like a page
#   that does not exist, and after MAX_BAD of them the server closes;
# - a file is only written inside its own staging folder, never outside it (no "..", no
#   absolute paths), streamed to a ".part" name and checked against the free space first.
# Plain HTTP: the token is visible to someone who can read the home network's traffic, which is
# why the page lives only minutes and only on a private network.
import http.server
import ipaddress
import json
import os
import secrets
import shutil
import socket
import threading
import time
import urllib.parse

from . import emulators, inbox, paths

PORT = 8737
IDLE = 15 * 60
MAX_BAD = 20
CHUNK = 1 << 20
RESERVE = emulators.RESERVE


def lan_ip():
    """This phone's address on its home network, or None (no WiFi, or not a private network).
    A UDP connect sends nothing: it only asks the kernel which address it would use."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("192.0.2.1", 9))
        ip = s.getsockname()[0]
    except OSError:
        return None
    finally:
        s.close()
    addr = ipaddress.ip_address(ip)
    return ip if addr.is_private and not addr.is_loopback and not addr.is_link_local else None


def safe_parts(rel):
    """The folder names and file name of an uploaded path, or None if it could leave its
    folder or is not a plain name."""
    if not rel or "\\" in rel or "\0" in rel or rel.startswith("/"):
        return None
    parts = rel.split("/")
    if any(p in ("", ".", "..") for p in parts) or parts[0].startswith("."):
        return None
    if any(len(p.encode()) > 255 for p in parts) or len(parts) > 32:
        return None
    return parts


def _free_name(folder, name):
    """name, or "name (2)", "name (3)"... if the Inbox already has one."""
    if not os.path.lexists(os.path.join(folder, name)):
        return name
    stem, ext = os.path.splitext(name)
    if os.path.isdir(os.path.join(folder, name)):
        stem, ext = name, ""
    n = 2
    while os.path.lexists(os.path.join(folder, f"{stem} ({n}){ext}")):
        n += 1
    return f"{stem} ({n}){ext}"


PAGE = """<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>ARMDeck upload</title>
<style>
:root{color-scheme:light dark;--bg:#f4f5f7;--fg:#16181d;--card:#fff;--line:#d5d8de;--acc:#1a73e8}
@media (prefers-color-scheme:dark){:root{--bg:#121417;--fg:#e8eaed;--card:#1d2026;--line:#353a43;--acc:#6aa4ff}}
body{margin:0;background:var(--bg);color:var(--fg);font:16px/1.45 system-ui,sans-serif}
main{max-width:640px;margin:0 auto;padding:24px 16px}
h1{font-size:1.4em;margin:0 0 4px}p{margin:0 0 16px;opacity:.8}
.card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:16px;margin-bottom:16px}
label.btn{display:inline-block;background:var(--acc);color:#fff;border-radius:8px;padding:10px 16px;margin:4px 8px 4px 0;cursor:pointer}
input[type=file]{display:none}
progress{width:100%;height:14px}
#log{font-size:.9em;white-space:pre-wrap;word-break:break-all;max-height:40vh;overflow:auto}
</style></head><body><main>
<h1>Send to ARMDeck</h1>
<p>Games, archives or whole game folders. They go to the Inbox, and the phone puts each one in
its place and gives it a tile. Keep the phone awake until this page says it is done.</p>
<div class="card">
<label class="btn">Choose files<input id="files" type="file" multiple></label>
<label class="btn">Choose a folder<input id="folder" type="file" webkitdirectory></label>
</div>
<div class="card"><div id="now">Nothing sent yet.</div><progress id="bar" max="1" value="0"></progress>
<div id="log"></div></div>
</main><script>
const now=document.getElementById("now"),bar=document.getElementById("bar"),log=document.getElementById("log");
let busy=false;
function put(file,rel){return new Promise((ok,fail)=>{const x=new XMLHttpRequest();
x.open("PUT","file?path="+encodeURIComponent(rel));
x.upload.onprogress=e=>{if(e.lengthComputable){bar.max=e.total;bar.value=e.loaded}};
x.onload=()=>x.status==200?ok():fail(new Error(x.responseText||x.status));
x.onerror=()=>fail(new Error("the phone did not answer (asleep, or the page closed)"));
x.send(file)})}
async function send(list,folder){if(busy)return;busy=true;let sent=0,bytes=0;
const files=[...list];for(const f of files){const rel=folder?f.webkitRelativePath:f.name;
now.textContent="Sending "+rel+" ("+(sent+1)+" of "+files.length+")";
try{await put(f,rel);sent++;bytes+=f.size;log.textContent+="sent  "+rel+"\\n"}
catch(e){log.textContent+="FAILED "+rel+": "+e.message+"\\n";if(e.message.includes("answer"))break}}
try{await fetch("done",{method:"POST"})}catch(e){}
now.textContent="Done: "+sent+" of "+files.length+" file(s), "+(bytes/1e6).toFixed(1)+" MB. The phone is placing them now.";
busy=false}
document.getElementById("files").onchange=e=>send(e.target.files,false);
document.getElementById("folder").onchange=e=>send(e.target.files,true);
</script></body></html>
"""


class Server:
    def __init__(self, log):
        self.log = log
        self.lock = threading.Lock()
        self.httpd = None
        self.token = None
        self.url = None
        self.stage = None
        self.last = 0.0
        self.bad = 0
        self.received = 0
        self.received_bytes = 0
        self.wake = threading.Event()

    def status(self):
        with self.lock:
            if self.httpd is None:
                return {"running": False}
            return {"running": True, "url": self.url,
                    "closes_in": max(0, int(IDLE - (time.time() - self.last))),
                    "received": self.received, "bytes": self.received_bytes}

    def start(self):
        with self.lock:
            if self.httpd is not None:
                self.last = time.time()
        if self.httpd is not None:
            return self.status()
        ip = lan_ip()
        if ip is None:
            return {"running": False, "error": "Not on a home WiFi network (no private address)."}
        token = secrets.token_urlsafe(16)
        stage = os.path.join(paths.games(), ".armdeck-upload")
        shutil.rmtree(stage, ignore_errors=True)
        os.makedirs(stage)
        try:
            httpd = http.server.ThreadingHTTPServer((ip, PORT), _handler(self))
        except OSError as e:
            return {"running": False, "error": f"Cannot listen on {ip}:{PORT} ({e.strerror})."}
        httpd.daemon_threads = True
        with self.lock:
            self.httpd, self.token, self.stage = httpd, token, stage
            self.url = f"http://{ip}:{PORT}/u/{token}/"
            self.last = time.time()
            self.bad = self.received = self.received_bytes = 0
            self.wake.clear()
        threading.Thread(target=httpd.serve_forever, name="armdeck-upload", daemon=True).start()
        threading.Thread(target=self._idle_close, name="armdeck-upload-idle", daemon=True).start()
        self.log(f"upload page open on {ip}:{PORT}")
        return self.status()

    def stop(self, why="stopped"):
        with self.lock:
            httpd, self.httpd = self.httpd, None
            stage = self.stage
        if httpd is None:
            return
        self.wake.set()
        threading.Thread(target=httpd.shutdown, daemon=True).start()
        httpd.server_close()
        # what was sent as a top-level file is already in the Inbox; an unfinished folder is not
        shutil.rmtree(stage, ignore_errors=True)
        self.log(f"upload page closed ({why})")

    def _idle_close(self):
        while True:
            with self.lock:
                if self.httpd is None:
                    return
                left = IDLE - (time.time() - self.last)
            if left <= 0:
                self.stop("idle")
                return
            self.wake.wait(left)

    def touch(self):
        with self.lock:
            self.last = time.time()

    def store(self, rel, length, stream):
        """Write one uploaded file. A top-level file goes to the Inbox at once; files of a
        folder wait in the staging folder until the page says the folder is complete."""
        parts = safe_parts(rel)
        if parts is None:
            raise ValueError("not an allowed file name")
        if length + RESERVE > paths.free_bytes(paths.games()):
            raise ValueError("not enough free space on the phone")
        target = os.path.join(self.stage, *parts)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        part = target + ".part"
        left = length
        try:
            with open(part, "wb") as out:
                while left > 0:
                    chunk = stream.read(min(CHUNK, left))
                    if not chunk:
                        raise ValueError("the upload stopped before the end")
                    out.write(chunk)
                    left -= len(chunk)
                    self.touch()
            os.replace(part, target)
        finally:
            if os.path.exists(part):
                os.unlink(part)
        with self.lock:
            self.received += 1
            self.received_bytes += length
        if len(parts) == 1:
            self._to_inbox(parts[0])

    def _to_inbox(self, name):
        box = inbox.inbox()
        os.makedirs(box, exist_ok=True)
        os.rename(os.path.join(self.stage, name), os.path.join(box, _free_name(box, name)))

    def done(self):
        """The page sent everything: complete folders move to the Inbox."""
        for name in sorted(os.listdir(self.stage)):
            self._to_inbox(name)


def _handler(server):
    class Handler(http.server.BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"
        server_version = "ARMDeck"
        sys_version = ""

        def log_message(self, fmt, *args):
            pass   # no per-request log; the server logs only what it did

        def _answer(self, code, body=b"", ctype="text/plain; charset=utf-8"):
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("Referrer-Policy", "no-referrer")
            self.end_headers()
            self.wfile.write(body)

        def _route(self):
            """The action after the token, or None (and the answer sent) when it is refused."""
            try:
                private = ipaddress.ip_address(self.client_address[0]).is_private
            except ValueError:
                private = False
            if not private:
                self.close_connection = True
                self._answer(403, b"only from the home network")
                return None
            url = urllib.parse.urlsplit(self.path)
            parts = url.path.split("/")
            if len(parts) != 4 or parts[1] != "u" or not secrets.compare_digest(
                    parts[2], server.token or ""):
                with server.lock:
                    server.bad += 1
                    too_many = server.bad >= MAX_BAD
                self.close_connection = True
                self._answer(404, b"not found")
                if too_many:
                    server.stop("too many wrong addresses")
                return None
            server.touch()
            return parts[3], urllib.parse.parse_qs(url.query)

        def do_GET(self):
            route = self._route()
            if route is None:
                return
            if route[0] == "":
                self._answer(200, PAGE.encode(), "text/html; charset=utf-8")
            else:
                self._answer(404, b"not found")

        def do_PUT(self):
            route = self._route()
            if route is None:
                return
            action, query = route
            length = self.headers.get("Content-Length")
            if action != "file" or not length or not length.isdigit():
                self.close_connection = True
                return self._answer(400, b"bad request")
            try:
                server.store(query.get("path", [""])[0], int(length), self.rfile)
            except (ValueError, OSError) as e:
                self.close_connection = True
                return self._answer(400, str(e).encode())
            self._answer(200, b"ok")

        def do_POST(self):
            route = self._route()
            if route is None:
                return
            if route[0] != "done":
                return self._answer(404, b"not found")
            try:
                server.done()
            except OSError as e:
                return self._answer(500, str(e).encode())
            self._answer(200, json.dumps({"ok": True}).encode(), "application/json")

    return Handler
