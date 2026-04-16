#!/usr/bin/env python3
"""
chatlog-server — tiny local HTTP server for the FFXI chat viewer.

Usage:
    python server.py                          (uses default Ashita path)
    python server.py "C:/Ashita4/config/addons/chatlog/logs"

Opens the viewer automatically in your default browser.
Press Ctrl+C in the terminal to stop.
"""

import http.server
import json
import os
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
# Viewer HTML (embedded so only one file is needed, but we also serve the
# standalone viewer.html if present next to us)
# ---------------------------------------------------------------------------
VIEWER_HTML_PATH = Path(__file__).parent / "viewer.html"

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

    def serve_viewer(self):
        if VIEWER_HTML_PATH.exists():
            content = VIEWER_HTML_PATH.read_bytes()
        else:
            content = EMBEDDED_VIEWER.encode("utf-8")
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
        data = json.dumps({"log_dir": log_dir, "file": get_newest_log()})
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(data.encode("utf-8"))

    def serve_setdir(self, d):
        global log_dir, last_file, last_mtime, cached_lines
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
def main():
    global log_dir

    if len(sys.argv) > 1:
        log_dir = sys.argv[1]
    else:
        log_dir = find_log_dir()

    if log_dir and os.path.isdir(log_dir):
        print(f"[chatlog-server] Watching: {log_dir}")
    else:
        print(f"[chatlog-server] Log directory not found.")
        print(f'  Pass it as an argument:  python server.py "C:/path/to/logs"')
        print(f"  Or set it in the viewer after it opens.")
        log_dir = None

    server = http.server.HTTPServer(("127.0.0.1", PORT), Handler)
    print(f"[chatlog-server] Running at http://127.0.0.1:{PORT}")
    print(f"[chatlog-server] Press Ctrl+C to stop.\n")

    # Open browser after a short delay
    def open_browser():
        time.sleep(0.5)
        webbrowser.open(f"http://127.0.0.1:{PORT}")
    threading.Thread(target=open_browser, daemon=True).start()

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[chatlog-server] Stopped.")
        server.server_close()

if __name__ == "__main__":
    main()
