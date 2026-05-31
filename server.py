#!/usr/bin/env python3
"""
chatlog-server — tiny local HTTP server for the FFXI chat viewer.

Usage:
    python server.py                          (uses default Ashita path, loopback)
    python server.py "C:/Ashita4/config/addons/chatlog/logs"
    python server.py "C:/path/to/logs" --host 0.0.0.0
    python server.py --host 0.0.0.0 --port 8271 --no-browser

Opens the viewer automatically in your default browser when bound to loopback.
Press Ctrl+C in the terminal to stop.
"""

import argparse
import http.server
import json
import os
import re
import sys
import glob
import webbrowser
import threading
import time
from pathlib import Path
from urllib.parse import parse_qs, urlparse

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
PORT = 8271  # arbitrary high port unlikely to conflict
DEFAULT_LOG_DIR = None  # set below after path detection

def find_log_dir():
    """Try to auto-detect the Ashita chatlog logs folder."""
    candidates = [
        Path(os.environ.get("USERPROFILE", "")) / "Desktop" / "Ashita4" / "config" / "addons" / "chatlog" / "logs",
        Path("C:/Ashita4/config/addons/chatlog/logs"),
        Path("C:/Program Files (x86)/Ashita4/config/addons/chatlog/logs"),
        Path("D:/Ashita4/config/addons/chatlog/logs"),
    ]
    for c in candidates:
        if c.is_dir():
            return str(c)
    return None

# ---------------------------------------------------------------------------
# Viewer HTML lookup. Tries multiple candidate paths because relative __file__
# (rare but possible) or Windows hidden-extensions can hide the file.
# ---------------------------------------------------------------------------
def find_viewer_html():
    script_dir = Path(__file__).resolve().parent
    candidates = [
        script_dir / "viewer.html",
        script_dir / "viewer.html.html",   # Windows hidden-extensions surprise
        script_dir / "viewer.htm",
        Path.cwd() / "viewer.html",
    ]
    for c in candidates:
        if c.is_file():
            return c
    return None

VIEWER_HTML_PATH = find_viewer_html()

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
log_dir = None
last_file = None
last_mtime = 0
cached_lines = ""

def get_newest_log():
    """Return the path to the newest .log file in log_dir, or None."""
    if log_dir is None or not os.path.isdir(log_dir):
        return None
    logs = glob.glob(os.path.join(log_dir, "*.log"))
    if not logs:
        return None
    return max(logs, key=os.path.getmtime)

def read_log():
    """Return (filename, content) of the newest log, with caching."""
    global last_file, last_mtime, cached_lines
    newest = get_newest_log()
    if newest is None:
        return None, ""
    mtime = os.path.getmtime(newest)
    if newest == last_file and mtime == last_mtime:
        return os.path.basename(newest), cached_lines
    try:
        with open(newest, "r", encoding="utf-8", errors="replace") as f:
            cached_lines = f.read()
    except Exception:
        cached_lines = ""
    last_file = newest
    last_mtime = mtime
    return os.path.basename(newest), cached_lines

# ---------------------------------------------------------------------------
# Outbox: viewer POSTs to /api/send → we append a line to <outbox>/queue.txt.
# The Ashita addon atomically renames the file to claim it, executes the
# whitelisted slash commands, then deletes it. No directory enumeration.
# ---------------------------------------------------------------------------
outbox_dir = None
allow_remote_send = False
send_enabled_global = True   # --disable-send flips this off
outbox_write_lock = threading.Lock()
OUTBOX_QUEUE_NAME = "queue.txt"
OUTBOX_QUEUE_MAX_BYTES = 200 * 1024  # 200 KB cap; trips if the game isn't running

CHANNEL_TO_CMD = {
    "say":   "/say",
    "shout": "/shout",
    "yell":  "/yell",
    "party": "/party",
    "ls":    "/linkshell",
    "ls2":   "/linkshell2",
    "tell":  "/tell",
}
NAME_RE = re.compile(r"^[A-Za-z][A-Za-z0-9]{2,15}$")
MAX_MESSAGE_LEN = 150  # FFXI's chat input limit

def can_client_send(client_ip):
    if not send_enabled_global or outbox_dir is None:
        return False
    if client_ip in ("127.0.0.1", "::1"):
        return True
    return allow_remote_send

def build_command(channel, message, target):
    """Validate and assemble a slash command. Returns (cmd, error)."""
    if not isinstance(channel, str):
        return None, "channel required"
    channel = channel.lower()
    if channel not in CHANNEL_TO_CMD:
        return None, f"unknown channel '{channel}'"
    if not isinstance(message, str):
        return None, "message must be a string"
    # Normalize whitespace, strip control chars.
    message = message.replace("\r", " ").replace("\n", " ").strip()
    if not message:
        return None, "empty message"
    if len(message) > MAX_MESSAGE_LEN:
        return None, f"message too long (max {MAX_MESSAGE_LEN})"
    if any(ord(c) < 0x20 for c in message):
        return None, "control characters not allowed"
    if channel == "tell":
        if not isinstance(target, str) or not NAME_RE.match(target):
            return None, "invalid target name (3–16 alphanumerics, starts with letter)"
        return f"{CHANNEL_TO_CMD[channel]} {target} {message}", None
    return f"{CHANNEL_TO_CMD[channel]} {message}", None

def write_outbox(cmd):
    """Append one command to queue.txt under a lock. Returns (ok, error)."""
    if outbox_dir is None or not os.path.isdir(outbox_dir):
        return False, "outbox directory not available"
    queue_path = os.path.join(outbox_dir, OUTBOX_QUEUE_NAME)
    try:
        with outbox_write_lock:
            try:
                if os.path.getsize(queue_path) > OUTBOX_QUEUE_MAX_BYTES:
                    return False, "outbox queue too large — is the game running?"
            except OSError:
                pass  # file doesn't exist yet, which is fine
            with open(queue_path, "a", encoding="utf-8") as f:
                f.write(cmd + "\n")
    except Exception as e:
        return False, f"write failed: {e}"
    return True, None

# ---------------------------------------------------------------------------
# HTTP Handler
# ---------------------------------------------------------------------------
class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass  # silence per-request logs

    def do_GET(self):
        parsed = urlparse(self.path)

        if parsed.path == "/" or parsed.path == "/viewer":
            self.serve_viewer()
        elif parsed.path == "/api/log":
            self.serve_log()
        elif parsed.path == "/api/status":
            self.serve_status()
        elif parsed.path == "/api/setdir":
            qs = parse_qs(parsed.query)
            d = qs.get("dir", [None])[0]
            self.serve_setdir(d)
        else:
            self.send_error(404)

    def do_POST(self):
        parsed = urlparse(self.path)
        if parsed.path == "/api/send":
            self.serve_send()
        else:
            self.send_error(404)

    def _json(self, code, data):
        body = json.dumps(data).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def serve_viewer(self):
        # Re-resolve every request so the user can drop viewer.html into place
        # after the server is already running without a restart.
        path = VIEWER_HTML_PATH if (VIEWER_HTML_PATH and VIEWER_HTML_PATH.is_file()) else find_viewer_html()
        if path is not None:
            content = path.read_bytes()
        else:
            looked = Path(__file__).resolve().parent
            content = (
                f"<!doctype html><meta charset=utf-8>"
                f"<body style='font-family:sans-serif;padding:20px;background:#111;color:#eee'>"
                f"<h2>viewer.html not found</h2>"
                f"<p>The server is running but couldn't find <code>viewer.html</code>.</p>"
                f"<p>Looked in: <code>{looked}</code></p>"
                f"<p>Make sure <code>viewer.html</code> is in that exact folder. Common causes:</p>"
                f"<ul><li>Windows hides known extensions — the file may actually be named "
                f"<code>viewer.html.txt</code>. Rename it to <code>viewer.html</code> "
                f"(enable 'File name extensions' in File Explorer's View menu first).</li>"
                f"<li>The zip wasn't fully extracted.</li></ul></body>"
            ).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(content)))
        self.end_headers()
        self.wfile.write(content)

    def serve_log(self):
        fname, content = read_log()
        data = json.dumps({"file": fname, "content": content})
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(data.encode("utf-8"))

    def serve_status(self):
        client_can_send = can_client_send(self.client_address[0])
        data = json.dumps({
            "log_dir": log_dir,
            "file": get_newest_log(),
            "send_enabled": client_can_send,
        })
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(data.encode("utf-8"))

    def serve_send(self):
        if not can_client_send(self.client_address[0]):
            self._json(403, {"ok": False, "error": "send not permitted for this client"})
            return
        length = int(self.headers.get("Content-Length", "0") or 0)
        if length <= 0 or length > 4096:
            self._json(400, {"ok": False, "error": "invalid request size"})
            return
        try:
            body = self.rfile.read(length).decode("utf-8")
            data = json.loads(body)
        except Exception:
            self._json(400, {"ok": False, "error": "invalid JSON body"})
            return
        cmd, err = build_command(
            data.get("channel"),
            data.get("message"),
            data.get("target"),
        )
        if err is not None:
            self._json(400, {"ok": False, "error": err})
            return
        ok, err = write_outbox(cmd)
        if not ok:
            self._json(500, {"ok": False, "error": err})
            return
        self._json(200, {"ok": True})

    def serve_setdir(self, d):
        global log_dir, last_file, last_mtime, cached_lines
        if self.client_address[0] not in ("127.0.0.1", "::1"):
            self.send_error(403, "setdir is loopback-only")
            return
        if d and os.path.isdir(d):
            log_dir = d
            last_file = None
            last_mtime = 0
            cached_lines = ""
            data = json.dumps({"ok": True, "log_dir": log_dir})
        else:
            data = json.dumps({"ok": False, "error": "directory not found"})
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(data.encode("utf-8"))

# ---------------------------------------------------------------------------
# Fallback embedded viewer (used when viewer.html is not next to server.py)
# ---------------------------------------------------------------------------
EMBEDDED_VIEWER = "<!-- see viewer.html -->"
# We'll serve the real file if present; otherwise this placeholder.

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def load_host_config():
    """
    Read chatviewer.host (sitting next to this server.py).
    Returns (host, extra_flags_dict) where extra_flags is a dict of
    {'allow_remote_send': bool, 'disable_send': bool, 'no_browser': bool}.
    Tolerates CRLF, BOM, blank lines, and ;-comments.
    """
    cfg_path = Path(__file__).parent / "chatviewer.host"
    flags = {"allow_remote_send": False, "disable_send": False, "no_browser": False}
    host = None
    if not cfg_path.is_file():
        return host, flags
    try:
        # utf-8-sig strips a BOM if Notepad saved one
        with open(cfg_path, "r", encoding="utf-8-sig") as f:
            lines = f.readlines()
    except Exception as e:
        print(f"[chatlog-server] Could not read {cfg_path}: {e}")
        return host, flags

    # Filter out blanks/comments, keep meaningful lines in order
    real = []
    for ln in lines:
        ln = ln.strip()  # strips \r\n and surrounding whitespace
        if not ln or ln.startswith(";") or ln.startswith("#"):
            continue
        real.append(ln)

    if real:
        host = real[0]
    for keyword in real[1:]:
        k = keyword.lower()
        if k == "remote-send":
            flags["allow_remote_send"] = True
        elif k == "disable-send":
            flags["disable_send"] = True
        elif k == "no-browser":
            flags["no_browser"] = True
        else:
            print(f"[chatlog-server] chatviewer.host: ignoring unknown keyword '{keyword}'")
    return host, flags


def main():
    global log_dir, outbox_dir, allow_remote_send, send_enabled_global

    parser = argparse.ArgumentParser(description="Local HTTP server for the FFXI chat viewer.")
    parser.add_argument("logdir", nargs="?", default=None,
                        help="Path to chatlog logs directory.")
    parser.add_argument("--host", default=None,
                        help="Interface to bind. Default: read from chatviewer.host, "
                             "else 127.0.0.1. Use 0.0.0.0 for LAN/tunnel exposure.")
    parser.add_argument("--port", type=int, default=PORT,
                        help=f"Port to bind (default: {PORT}).")
    parser.add_argument("--no-browser", action="store_true",
                        help="Don't auto-open the browser.")
    parser.add_argument("--allow-remote-send", action="store_true",
                        help="Allow non-loopback clients to use /api/send. "
                             "Off by default — only loopback can send.")
    parser.add_argument("--disable-send", action="store_true",
                        help="Disable the /api/send endpoint entirely.")
    parser.add_argument("--outbox-dir", default=None,
                        help="Override outbox directory. Default: <logdir>/../outbox.")
    args = parser.parse_args()

    # chatviewer.host populates whatever the CLI didn't.
    file_host, file_flags = load_host_config()
    bind_host = args.host or file_host or "127.0.0.1"

    log_dir = args.logdir or find_log_dir()
    allow_remote_send = args.allow_remote_send or file_flags["allow_remote_send"]
    send_enabled_global = not (args.disable_send or file_flags["disable_send"])
    no_browser = args.no_browser or file_flags["no_browser"]

    if log_dir and os.path.isdir(log_dir):
        print(f"[chatlog-server] Watching: {log_dir}")
    else:
        print(f"[chatlog-server] Log directory not found.")
        print(f'  Pass it as an argument:  python server.py "C:/path/to/logs"')
        print(f"  Or set it in the viewer after it opens.")
        log_dir = None

    if VIEWER_HTML_PATH and VIEWER_HTML_PATH.is_file():
        print(f"[chatlog-server] Viewer:   {VIEWER_HTML_PATH}")
    else:
        looked = Path(__file__).resolve().parent
        print(f"[chatlog-server] Viewer:   NOT FOUND. Looked in: {looked}")
        print(f"                 The page will display an error message instead of the viewer.")
        print(f"                 Make sure viewer.html is in that folder. Windows may have")
        print(f"                 hidden the .html extension — check for viewer.html.txt.")

    # Outbox: derive from logs path unless overridden.
    if send_enabled_global:
        if args.outbox_dir:
            outbox_dir = args.outbox_dir
        elif log_dir:
            outbox_dir = os.path.normpath(os.path.join(log_dir, "..", "outbox"))
        if outbox_dir:
            try:
                os.makedirs(outbox_dir, exist_ok=True)
                print(f"[chatlog-server] Outbox:   {outbox_dir}")
            except Exception as e:
                print(f"[chatlog-server] Could not create outbox dir: {e}")
                outbox_dir = None

    is_loopback = bind_host in ("127.0.0.1", "localhost", "::1")

    server = http.server.HTTPServer((bind_host, args.port), Handler)
    print(f"[chatlog-server] Running at http://{bind_host}:{args.port}")
    if not is_loopback:
        print(f"[chatlog-server] WARNING: bound to {bind_host} — anyone who can reach")
        print(f"                 this host:port can read your chat log. Put a tunnel,")
        print(f"                 reverse proxy, or firewall rule in front of it.")
    if send_enabled_global and outbox_dir:
        if allow_remote_send and not is_loopback:
            print(f"[chatlog-server] WARNING: --allow-remote-send is ON. Anyone who can")
            print(f"                 reach this server can inject chat into your game.")
            print(f"                 Make sure your tunnel has authentication in front.")
        elif allow_remote_send and is_loopback:
            print(f"[chatlog-server] Send:     ON (remote-send allowed; loopback bind)")
        elif is_loopback:
            print(f"[chatlog-server] Send:     loopback only")
        else:
            print(f"[chatlog-server] Send:     loopback only (add 'remote-send' to chatviewer.host)")
    elif not send_enabled_global:
        print(f"[chatlog-server] Send:     DISABLED")
    print(f"[chatlog-server] Press Ctrl+C to stop.\n")

    if not no_browser and is_loopback:
        def open_browser():
            time.sleep(0.5)
            webbrowser.open(f"http://{bind_host}:{args.port}")
        threading.Thread(target=open_browser, daemon=True).start()

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[chatlog-server] Stopped.")
        server.server_close()

if __name__ == "__main__":
    main()
