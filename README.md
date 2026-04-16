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

**Viewer (`viewer.html` + `server.py`)**
- Works in any browser — Chrome, Edge, Firefox, Safari, Opera, etc.
- Tiny Python server reads the log files; the viewer polls it once per second
- One-click launch with `start-viewer.bat` (auto-detects your Ashita install)
- Auto-detects the newest session file and switches when the addon rotates logs
- Per-channel on/off toggles (Say, Shout, Tell, LS, LS2, Party, Yell, Debug)
- Color picker for each channel and the background
- Adjustable font size and font family (mono / sans / serif)
- All preferences saved across sessions
- Connection status indicator with auto-reconnect
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

---

## Files

```
chatlog/
├── README.md
├── chatlog.lua           # Ashita v4 addon
├── server.py             # local HTTP server for the viewer
├── viewer.html           # browser-based chat viewer
└── start-viewer.bat      # one-click launcher (Windows)
```

---

## License

MIT.

## Credits

- [Ashita](https://www.ashitaxi.com/) for the v4 addon framework
- [ThornyFFXI/AutoTrans](https://github.com/ThornyFFXI/AutoTrans) for reference on FFXI auto-translate handling
