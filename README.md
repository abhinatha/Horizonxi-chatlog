# chatlog

An [Ashita v4](https://www.ashitaxi.com/) addon for Final Fantasy XI that writes every chat message you see (Say, Shout, Yell, Tell, Party, Linkshell, Linkshell 2) to a per-session log file, plus a standalone HTML viewer designed to run on a second monitor with per-channel toggles, color customization, and live updates.

Tuned for [HorizonXI](https://horizonxi.com), but works on retail and other private servers — the chat-mode mappings are configurable at runtime.

Works in **any browser** (Chrome, Edge, Firefox, Safari, etc.).

![channels](https://img.shields.io/badge/channels-Say%20%7C%20Shout%20%7C%20Yell%20%7C%20Tell%20%7C%20Party%20%7C%20LS%20%7C%20LS2-blue)
![ashita](https://img.shields.io/badge/Ashita-v4-orange)

---

## Features

**Addon (`chatlog.lua`)**
- Logs every Say / Shout / Yell / Tell (in & out) / Party / Linkshell / Linkshell 2 message
- One log file per session with timestamped filename
- Optional auto-purge of old session logs on startup
- Native auto-translate decoding via Ashita's `ChatManager:ParseAutoTranslate`
- Configurable chat-mode → channel mapping (live-editable in chat)
- Debug mode that dumps every chat line with its raw + masked mode number, for identifying server-specific channel IDs
- Hex dump command for diagnosing unknown byte sequences
- `clean` mode strips stray high bytes that display as `�` in editors
- Outbox poller that lets the viewer send chat back into the game (whitelisted commands only)

**Viewer (`viewer.html` + `server.py`)**
- Works in any browser — Chrome, Edge, Firefox, Safari, Opera, etc.
- Tiny Python server reads the log files; the viewer polls it once per second
- One-click launch with `start-viewer.bat` (auto-detects your Ashita install)
- Auto-detects the newest session file and switches when the addon rotates logs
- Per-channel on/off toggles (Say, Shout, Tell, LS, LS2, Party, Yell, Debug)
- **Composer bar** for sending Say / Shout / Yell / Tell / Party / LS / LS2 messages back into the game (loopback-only by default; opt-in for remote)
- Color picker for each channel and the background
- Adjustable font size and font family (mono / sans / serif)
- All preferences saved across sessions
- Connection status indicator with auto-reconnect
- Mobile-friendly: responsive layout, tap-sized controls, designed to work over a Cloudflare tunnel
- Designed for a second monitor — F11 fullscreen

---

## Requirements

- [Ashita v4](https://www.ashitaxi.com/)
- [Python 3.6+](https://www.python.org/downloads/) for the viewer server (no extra packages needed)

> **Note:** When installing Python, check **"Add Python to PATH"** so the bat file can find it.

---

## Installation

### Addon

1. Copy `chatlog.lua` to:
   ```
   Ashita4\addons\chatlog\chatlog.lua
   ```
2. In-game, load it:
   ```
   /addon load chatlog
   ```
3. To auto-load every session, append to `Ashita4\scripts\default.txt`:
   ```
   /addon load chatlog
   ```

### Viewer

1. Put `server.py`, `viewer.html`, and `start-viewer.bat` together in the same folder (e.g. `Documents\chatviewer\`).

2. **Easy launch:** Double-click `start-viewer.bat`. It auto-detects your Ashita install, starts the server, and opens the viewer in your default browser.

3. **Manual launch:** Open a terminal and run:
   ```
   python server.py "C:\Ashita4\config\addons\chatlog\logs"
   ```
   Then open `http://127.0.0.1:8271` in any browser.

   Full options:
   ```
   python server.py [logdir] [--host HOST] [--port PORT] [--no-browser]
                    [--allow-remote-send] [--disable-send] [--outbox-dir DIR]
   ```

   | Flag | Default | Purpose |
   |---|---|---|
   | `logdir` | auto-detected | Path to the chatlog logs folder |
   | `--host` | `127.0.0.1` | Interface to bind. Use `0.0.0.0` to expose for LAN or a Cloudflare tunnel, or a specific NIC IP |
   | `--port` | `8271` | Port to bind |
   | `--no-browser` | off | Skip the auto-open of the default browser |
   | `--allow-remote-send` | off | Permit non-loopback clients to POST `/api/send`. **Only enable behind authentication** (Cloudflare Access, VPN, etc.) |
   | `--disable-send` | off | Disable the send endpoint entirely. The viewer's composer hides automatically |
   | `--outbox-dir` | `<logdir>/../outbox` | Override where outbound `.cmd` files are dropped for the addon to pick up |

4. Drag the browser window to your second monitor. Press **F11** for fullscreen.

5. Close the terminal window (or Ctrl+C) to stop the server.

> **Tip:** In Edge you can go to `⋯` → Apps → Install this site as an app to get a dedicated window without browser chrome.

---

## Log format

```
=== Session started 2026-04-14 21:05:11 ===
[21:05:33] [SAY] You say, 'hello'
[21:05:38] [SAY] Someone : hi
[21:06:02] [LS] [1]<Friend> wb
[21:06:20] [TELL] >>Friend : ty
[21:06:55] [YELL] <Mickstabber>[PortJeuno]: [Looking for Party] [Experience points] BST39/NIN19
=== Session ended 2026-04-14 22:14:02 ===
```

Auto-translate phrases are decoded in-place and wrapped in `[ ]`. Lines arrive in the order the game received them.

Default location:
```
Ashita4\config\addons\chatlog\logs\session_YYYY-MM-DD_HH-MM-SS.log
```

---

## Commands

All commands are entered in-game and start with `/chatlog`.

| Command | Purpose |
|---|---|
| `/chatlog path` | Print the current session log path |
| `/chatlog reopen` | Close the current log and start a new session file |
| `/chatlog keep on\|off` | Keep old session logs vs. auto-purge on new session (default: off = purge) |
| `/chatlog clean on\|off` | Strip stray high bytes that render as `�` (default: on) |
| `/chatlog hex [n]` | Dump the next *n* chat lines as raw hex (default 5) — for diagnosing byte sequences |
| `/chatlog debug on\|off` | Log every chat line tagged `[RAW##/M##]` — for identifying server chat-mode IDs |
| `/chatlog set <m> <TAG>` | Map masked chat-mode `m` to tag `TAG` (e.g. `/chatlog set 14 LS`) |
| `/chatlog clear <m>` | Stop logging masked chat-mode `m` |
| `/chatlog show` | Print the current mode → tag mapping |
| `/chatlog send on\|off\|status` | Enable/disable the viewer-driven send pipeline; `off` drains pending commands |

---

## Channel mapping

Chat modes are read as `mode & 0xFF` (the low byte) so direction-flag bits in the upper bytes don't matter. Default mapping is the **HorizonXI** layout:

| Channel | Outgoing (you) | Incoming (others) | LS MOTD |
|---|---|---|---|
| SAY | 1 | 9 |
| SHOUT | 2 | 10 |
| YELL | 3 | 11 |
| TELL | 4 | 12 |
| PARTY | 5 | 13 |
| LS | 6 | 14 | 205 |
| LS2 | 213 | 214 | 217 |

---

## Adapting to a different server

The addon ships with HorizonXI defaults. If you're on retail or a different private server, the chat-mode numbers may differ. Identify them once:

1. `/chatlog debug on`
2. Post a test message in each channel (have a friend send the incoming variants):
   ```
   /say test-say
   /shout test-shout
   /linkshell test-ls
   /yell test-yell
   /tell <yourself> test-tell
   ```
3. Open the session log in Notepad. Lines look like:
   ```
   [HH:MM:SS] [RAW402653185/M1] You say, 'test-say'
   [HH:MM:SS] [RAW9/M9]         Friend : test-say
   ```
   The `M##` is the masked mode you need to map.
4. Map each one:
   ```
   /chatlog set 1 SAY
   /chatlog set 9 SAY
   ...
   /chatlog debug off
   ```
5. To make it permanent, edit the `mode_tag` table near the top of `chatlog.lua`.

---

## Remote access (mobile / second device)

By default the server binds to `127.0.0.1` and is only reachable from the same PC. To view your chat log from another device — phone, tablet, second computer — bind the server to a non-loopback interface.

**Pick a host:**

| Host | What it exposes |
|---|---|
| `127.0.0.1` (default) | Loopback only. Local browser, or `cloudflared` running on the same PC |
| `0.0.0.0` | All interfaces. Reachable from any LAN device, or any tunnel/reverse proxy on the box |
| `192.168.x.x` (your LAN IP) | Only that NIC. LAN devices can reach it, but not other interfaces |

**Two ways to set it:**

1. **Persistent (recommended for `start-viewer.bat`)** — create a file named `chatviewer.host` next to the bat file. Line 1 is the bind address; subsequent lines are flag keywords:

   ```
   0.0.0.0
   remote-send
   ```

   Recognized flag lines:

   | Keyword | Equivalent flag |
   |---|---|
   | `remote-send` | `--allow-remote-send` |
   | `disable-send` | `--disable-send` |
   | `no-browser` | `--no-browser` |

   Lines starting with `;` are treated as comments. Blank lines are ignored. A single-line file (legacy format, just an IP) still works. Delete the file to revert to loopback.

2. **One-off** — pass the equivalent flags on the command line:
   ```
   python server.py "C:\Ashita4\config\addons\chatlog\logs" --host 0.0.0.0 --allow-remote-send
   ```

**Connecting from your phone over LAN:** find the PC's LAN IP (`ipconfig` → IPv4 Address) and open `http://<that-ip>:8271` in your phone's browser. Both devices must be on the same network and Windows Firewall must allow inbound TCP 8271 (Windows usually prompts on first launch).

**Connecting from anywhere via Cloudflare Tunnel:** install `cloudflared`, point it at `http://localhost:8271` (loopback bind is fine — `cloudflared` runs on the same PC), and you can leave `--host 127.0.0.1`. Put **Cloudflare Access** in front of the tunnel hostname unless you're comfortable publishing your chat log to the open internet.

**Security notes:**

- The server has no authentication. Anyone who can reach the bound port reads everything in the log directory. Use Cloudflare Access, a VPN, an SSH tunnel, or stay on LAN.
- `/api/setdir` (the in-viewer "change log folder" API) is restricted to loopback connections only — remote viewers cannot repoint the server at a different directory.
- `/api/send` (sending chat into the game — see next section) is loopback-only by default. `--allow-remote-send` opens it up; only do this behind authentication.
- Auto-open of the browser is suppressed when you bind to a non-loopback interface, since you're probably running headless or on a different device.

---

## Sending chat from the viewer

The viewer can send chat *into* the game — respond to tells, chat in linkshells, etc. — using the composer bar that appears below the chat log.

### How it works

```
viewer ── POST /api/send ──▶ server.py ── writes ──▶ outbox/*.cmd
                                                          │
                                                          ▼
                                                     chatlog.lua
                                                  (polls ~4× per sec)
                                                          │
                                                          ▼
                                            QueueCommand(1, "/l hello")
```

The server validates the channel, target, and message, then drops a single timestamped `.cmd` file into `Ashita4\config\addons\chatlog\outbox\`. The addon polls that directory, executes any matching whitelisted slash command in-game, and deletes the file. Sent messages then appear in the chat log via the normal incoming-text path, which is your confirmation that it actually went through.

### Channels

| Composer channel | In-game command |
|---|---|
| Say | `/say <message>` |
| Shout | `/shout <message>` |
| Yell | `/yell <message>` |
| Party | `/party <message>` |
| LS | `/linkshell <message>` |
| LS2 | `/linkshell2 <message>` |
| Tell | `/tell <name> <message>` |

### Validation

- Message length capped at 150 characters (FFXI's input limit).
- Newlines and control characters are stripped/rejected — one POST = one slash command, no chaining.
- Tell target must be 3–16 alphanumeric chars starting with a letter.
- The addon independently re-checks that every command starts with one of the whitelisted prefixes (`/say /sh /yell /tell /party /linkshell /linkshell2` and short forms). Anything else is silently dropped, even if dropped into the outbox by some other process.
- Outbox backlog is capped at 100 pending files — if the game isn't running, further sends 500 instead of piling up forever.

### Permissions

| Server flags | Loopback clients (same PC) | Remote clients (LAN / tunnel) |
|---|---|---|
| *(default)* | ✅ can send | ❌ 403 |
| `--allow-remote-send` | ✅ can send | ✅ can send |
| `--disable-send` | ❌ disabled | ❌ disabled |

The viewer's composer auto-hides if the server tells it the calling client isn't allowed to send, so a remote viewer simply won't show the composer unless `--allow-remote-send` is set.

### Addon-side toggle

If you want to kill the send pipeline locally without restarting anything, in-game:

```
/chatlog send off       (drains the outbox and stops polling)
/chatlog send on        (resumes polling)
/chatlog send status    (shows current state and outbox path)
```

### Sending from your phone

1. Start the server bound to `0.0.0.0` (or use Cloudflare Tunnel pointed at loopback).
2. Add `--allow-remote-send`.
3. Open the viewer on your phone. Pick a channel, type, hit Enter.
4. The composer's send button is large and the channel/target inputs are tap-sized — the layout collapses for narrow viewports.

### Recipe: phone access via Cloudflare Tunnel with send enabled

The end-to-end setup most users actually want. Cloudflare Access provides authentication; the server sits on loopback so only `cloudflared` reaches it.

1. Install `cloudflared` and create a tunnel pointing at `http://localhost:8271`.
2. Put **Cloudflare Access** in front of the public hostname (Zero Trust → Access → Applications → require email / Google / GitHub / whatever).
3. Next to `start-viewer.bat`, create `chatviewer.host` with these contents:
   ```
   127.0.0.1
   remote-send
   ```
   First line keeps the server on loopback (only `cloudflared` can reach it). Second line enables `--allow-remote-send` so requests forwarded by the tunnel can POST to `/api/send`. Cloudflare Access is doing the auth.
4. Double-click `start-viewer.bat`. Open the tunnel hostname on your phone, authenticate via Access, and the composer appears.

### Programmatic use

The endpoint accepts JSON:

```
POST /api/send
Content-Type: application/json

{ "channel": "ls",   "message": "wb" }
{ "channel": "tell", "target": "Friend", "message": "ty" }
```

Response is `{"ok": true}` or `{"ok": false, "error": "..."}` with an appropriate HTTP code.

---

## Viewer controls

| Control | What it does |
|---|---|
| Channel checkboxes | Show / hide each chat channel |
| Size slider | Adjust font size (10–28px) |
| Font dropdown | Switch between Monospace, Sans, and Serif |
| Color pickers | Customize the color for each channel and the background |
| Timestamps | Show or hide the `HH:MM:SS` prefix |
| Auto-scroll | Keep the view pinned to the latest message |
| System lines | Show session start/end markers |

All settings are saved in your browser and restored on next visit.

---

## Troubleshooting

**"Server not running" overlay in the viewer**
- Make sure `server.py` is running. Double-click `start-viewer.bat` or run `python server.py "path\to\logs"` in a terminal.
- Check that Python is installed and in your PATH: run `python --version` in a command prompt.

**Some chat lines aren't showing up in the viewer**
1. Check the `.log` file directly in Notepad. If lines are present in the file but not the viewer, they may be tagged as a channel that's toggled off — check all channel toggles.
2. If lines are missing from the file, the addon doesn't recognize that mode number. Run `/chatlog debug on`, trigger the missing lines, then map them with `/chatlog set <m> <TAG>`.

**Player names show as `�Name�` in the log**
- Make sure `clean` is on: `/chatlog clean on` (this is the default). These are FFXI's name decoration bytes that aren't valid UTF-8.

**Server can't find the logs folder**
- Pass the full path explicitly: `python server.py "C:\Your\Ashita4\config\addons\chatlog\logs"`.
- Make sure the addon has been loaded at least once (which creates the folder).

**Phone or other LAN device can't reach the server**
- Confirm the server is bound to `0.0.0.0` (or your LAN IP) — `127.0.0.1` only accepts loopback connections. The server prints the bind address on startup.
- Check Windows Firewall: it must allow inbound TCP on port 8271 for `python.exe`. The first time you bind to a non-loopback interface, Windows usually pops a dialog; click **Allow**.
- Both devices must be on the same network. Test by opening `http://<pc-lan-ip>:8271/api/status` from the phone — you should see a JSON response.

**Cloudflare tunnel works but `/api/setdir` returns 403**
- That's intentional. Repointing the log folder is loopback-only for security. Use a `chatviewer.host` file or the `logdir` argument instead.

**Composer doesn't appear in the viewer**
- The server told the viewer that this client can't send. Likely causes: you're a remote client and didn't pass `--allow-remote-send`, or you started the server with `--disable-send`. Check the server console — it prints the send mode on startup.

**Composer appears, send returns 200, but nothing happens in-game**
- The addon isn't running, or `/chatlog send` is off. In-game, run `/chatlog send status` — it'll show the current state and the outbox path. If the addon is off, files pile up in the outbox until the cap (100) is hit; load the addon and they'll execute.
- Check the outbox directory directly. If `.cmd` files are sitting there, the addon isn't polling. If they vanish but no chat happens, the addon's whitelist rejected them — turn on `/chatlog debug on` to log `[SEND]` and `[SEND/REJECTED]` lines.

---

## Files

```
chatlog/
├── README.md
├── chatlog.lua           # Ashita v4 addon (logger + outbox poller)
├── server.py             # local HTTP server for the viewer
├── viewer.html           # browser-based chat viewer + composer
├── start-viewer.bat      # one-click launcher (Windows)
├── chatviewer.cfg        # (auto-created) saved logs-folder path
└── chatviewer.host       # (optional, you create) one line: bind address, e.g. 0.0.0.0
```

At runtime, the addon also creates `Ashita4\config\addons\chatlog\outbox\` for the send-pipeline IPC.

---

## License

MIT.

## Credits

- [Ashita](https://www.ashitaxi.com/) for the v4 addon framework
- [ThornyFFXI/AutoTrans](https://github.com/ThornyFFXI/AutoTrans) for reference on FFXI auto-translate handling
