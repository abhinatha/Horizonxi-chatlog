# chatlog

An [Ashita v4](https://www.ashitaxi.com/) addon for Final Fantasy XI that writes every chat message you see (Say, Shout, Yell, Tell, Party, Linkshell, Linkshell 2) to a per-session log file, plus a standalone HTML viewer designed to run on a second monitor with per-channel toggles, color customization, and live updates.

Tuned for [HorizonXI](https://horizonxi.com), but works on retail and other private servers — the chat-mode mappings are configurable at runtime.

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
- Hex dump command for diagnosing unknown byte sequences in player names / decorations

**Viewer (`viewer.html`)**
- Pure HTML / JS, zero install — opens in Edge or Chrome
- Remembers your logs folder across browser restarts (IndexedDB)
- Auto-detects the newest session file and switches to it when the addon rotates logs
- Polls the file once per second and auto-scrolls
- Per-channel on/off toggles (Say, Shout, Tell, LS, LS2, Party, Yell, plus a Debug channel)
- Color picker for each channel and the background
- Adjustable font size and font family (mono / sans / serif)
- All preferences saved to localStorage
- Designed for a second monitor — F11 fullscreen, or "Install as app" in Edge for a dedicated window

---

## Installation

### Addon

1. Copy `chatlog.lua` to:
   ```
   Ashita4\addons\chatlog\chatlog.lua
   ```
2. (Optional) Copy `at_dict.txt` to:
   ```
   Ashita4\config\addons\chatlog\at_dict.txt
   ```
3. In-game, load it:
   ```
   /addon load chatlog
   ```
4. To auto-load every session, append to `Ashita4\scripts\default.txt`:
   ```
   /addon load chatlog
   ```

### Viewer

1. Save `viewer.html` anywhere on disk (e.g. `Documents\chatviewer.html`).
2. Right-click → Open with → Microsoft Edge or Google Chrome.
3. Click **Pick logs folder…** and select:
   ```
   Ashita4\config\addons\chatlog\logs
   ```
4. Done. The folder choice persists; future opens just need a one-click permission grant if the browser dropped permission since last visit.

> **Why Edge / Chrome?** The viewer uses the [File System Access API](https://developer.mozilla.org/en-US/docs/Web/API/File_System_Access_API) so it can poll the live log file without the user re-uploading it. Firefox and Safari don't support this API yet.

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
| `/chatlog clean on\|off` | Strip stray high bytes that render as � (default: on) |
| `/chatlog hex [n]` | Dump the next *n* chat lines as raw hex (default 5) — for diagnosing unknown byte sequences |
| `/chatlog debug on\|off` | Log every chat line tagged `[RAW##/M##]` instead of by channel — for identifying server chat-mode IDs |
| `/chatlog set <m> <TAG>` | Map masked chat-mode `m` to tag `TAG` (e.g. `/chatlog set 14 LS`) |
| `/chatlog clear <m>` | Stop logging masked chat-mode `m` |
| `/chatlog show` | Print the current mode → tag mapping || `/chatlog at <hex...> <word>` | Manually add an auto-translate dictionary entry, e.g. `/chatlog at 02 02 01 0B Hello` |

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
| LS2 | 213 | 217 | 214 |

If you're on a different server (or HorizonXI changes the modes), use `/chatlog debug on`, send a message in each channel, then map them with `/chatlog set <mode> <TAG>`. See **Adapting to a different server** below.

---

## Adapting to a different server

The addon ships with HorizonXI defaults. If you're on retail / a different private server, the chat-mode numbers may differ. Identify them once:

1. `/chatlog debug on`
2. Post a test message in each channel (have a friend / mule send the incoming variants):
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

## Viewer screenshot guide

```
┌────────────────────────────────────────────────────────────────────────┐
│ [Pick logs folder] [Forget]   [✓Say][✓Shout][✓Tell][✓LS][✓LS2][ Yell] │
│ [Size◀━━●━━━▶] [Mono▼]   BG[■] Say[■] Shout[■] Tell[■] LS[■] LS2[■]   │
│ [✓timestamps] [✓auto-scroll] [ system lines]      watching: session... │
├────────────────────────────────────────────────────────────────────────┤
│ 21:05:33 [SAY] You say, 'hello'                                        │
│ 21:06:02 [LS]  <Friend> wb                                             │
│ 21:06:20 [TELL] >>Friend : ty                                          │
│ ...                                                                    │
└────────────────────────────────────────────────────────────────────────┘
```

Tip: in Edge, click `⋯` → **Apps → Install this site as an app** for a dedicated always-there window without browser chrome.

---

## Troubleshooting

**Some chat lines aren't showing up in the viewer**
1. Check the log file directly. If lines are present in the file but not the viewer, refresh the viewer page.
2. If lines are missing from the file, the addon doesn't recognize that mode number. Run `/chatlog debug on` and have those lines repeat — the raw mode will be logged. Map it with `/chatlog set <m> <TAG>`.

**Player names show as `�Name�` in the log**
- These are FFXI's name decoration bytes that aren't valid UTF-8. By default `clean` is on and strips them. If they're still showing, run `/chatlog clean on` to confirm. To diagnose unknown decoration bytes, use `/chatlog hex 10` and inspect the raw bytes.

**Auto-translate phrases show as `{AT?:02 02 XX YY}`**
- Ashita's native `ParseAutoTranslate` couldn't resolve them. Add a dictionary entry: `/chatlog at 02 02 XX YY <Word>`.

**Viewer says "no folder" after browser restart**
- The browser dropped its permission grant. Click "Allow access" in the popup, or click "Pick logs folder…" again.

---

## Files

```
chatlog/
├── README.md
├── chatlog.lua        # the Ashita addon
├── viewer.html        # the standalone viewer
```

---

## License

MIT.

## Credits

- [Ashita](https://www.ashitaxi.com/) for the v4 addon framework
- [ThornyFFXI/AutoTrans](https://github.com/ThornyFFXI/AutoTrans) for the reference on how to handle the auto-translate dictionary
