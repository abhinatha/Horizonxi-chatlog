--[[
    chatlog - Ashita v4 addon - HorizonXI tuned

    Install: Ashita4\addons\chatlog\chatlog.lua
    Load:    /addon load chatlog

    Per-session log at:
        Ashita4\config\addons\chatlog\logs\session_YYYY-MM-DD_HH-MM-SS.log

    By default, old session logs are deleted when a new session starts.
    Use  /chatlog keep on   to keep history.

    Commands:
        /chatlog path
        /chatlog reopen
        /chatlog keep on|off
        /chatlog clean on|off
        /chatlog hex [n]
        /chatlog debug on|off
        /chatlog set <masked-mode> <TAG>
        /chatlog clear <masked-mode>
        /chatlog show
]]

addon.name    = 'chatlog';
addon.author  = 'abhinatha';
addon.version = '2.2.0-horizon';
addon.desc    = 'Per-session chat log + outbox for viewer-driven sends. Tested on HorizonXI and Retail.';

require('common');

local state = {
    file           = nil,
    path           = nil,
    log_dir        = nil,
    debug          = false,
    keep           = false,
    clean          = true,
    hex_next       = 0,
    outbox_dir     = nil,
    send_enabled   = true,
    last_poll      = 0,     -- os.clock() of last outbox check
    poll_interval  = 0.25,  -- seconds between outbox polls
};

-- (mode & 0xFF) -> tag. Confirmed on HorizonXI.
local mode_tag = {
    [1]   = 'SAY',     [9]  = 'SAY',
    [2]   = 'SHOUT',   [10] = 'SHOUT',
    [3]   = 'YELL',    [11] = 'YELL',
    [4]   = 'TELL',    [12] = 'TELL',
    [5]   = 'PARTY',   [13] = 'PARTY',
    [6]   = 'LS',      [14] = 'LS',     [205] = 'LS',
    [213] = 'LS2',     [214] = 'LS2',      [217] = 'LS2',
};

----------------------------------------------------------------------
-- Auto-translate decoding
--
-- Uses Ashita's native ChatManager:ParseAutoTranslate(msg, useBrackets)
-- which resolves 0xFD...0xFD blocks using the game's own DAT files.
----------------------------------------------------------------------

local function sanitize(msg)
    if msg == nil then return ''; end

    -- Decode auto-translate via Ashita's native parser.
    local cm = AshitaCore:GetChatManager();
    if cm and cm.ParseAutoTranslate then
        local ok, parsed = pcall(function() return cm:ParseAutoTranslate(msg, true); end);
        if ok and type(parsed) == 'string' then
            msg = parsed;
        end
    end

    -- Strip any 0xFD markers that survived.
    msg = msg:gsub('\xFD', '');

    -- Auto-translate bracket bytes: 0xEF 0x27 (open), 0xEF 0x28 (close).
    msg = msg:gsub('\xEF\x27', '[');
    msg = msg:gsub('\xEF\x28', ']');

    -- FFXI's auto-translate framing sometimes emits a trailing 0x28 ( '(' )
    -- or leading 0x29 ( ')' ) byte that survives ParseAutoTranslate. Clean
    -- the common ']( ' and ' )[' artefacts here. Run /chatlog hex 1 before
    -- an auto-translate message if you suspect other leftover characters.
    msg = msg:gsub('%]%(', ']');
    msg = msg:gsub('%)%[', '[');

    -- Player-name decorative brackets (full-width SJIS).
    msg = msg:gsub('\x81\x79', '<');
    msg = msg:gsub('\x81\x7A', '>');

    -- Color / italic / reset control sequences.
    msg = msg:gsub('[\x1E\x1F].', '');
    msg = msg:gsub('[\x00-\x08\x0B-\x1F\x7F]', '');

    -- Strip remaining high bytes that render as ? in editors.
    if state.clean then
        msg = msg:gsub('[\x80-\xFF]', '');
    end

    return msg;
end

----------------------------------------------------------------------
-- File I/O
----------------------------------------------------------------------

-- Normalize Ashita-install-path-derived paths. GetInstallPath() may or may
-- not include a trailing slash; without normalization we end up with strings
-- like "...FFXINA\\config\\addons\\chatlog\\outbox" which Ashita's fs.* helpers
-- treat as a distinct path from the server's normalized form, so files dropped
-- by the server become invisible to the addon.
local function addon_subdir(sub)
    local install = AshitaCore:GetInstallPath();
    install = install:gsub('[\\/]+$', '');
    return ('%s\\config\\addons\\%s\\%s'):format(install, addon.name, sub);
end

local function write_line(tag, msg)
    if state.file == nil then return; end
    state.file:write(('[%s] [%s] %s\n'):format(os.date('%H:%M:%S'), tag, msg));
    state.file:flush();
end

local function close_log()
    if state.file ~= nil then
        state.file:write(('=== Session ended %s ===\n'):format(os.date('%Y-%m-%d %H:%M:%S')));
        state.file:close();
        state.file = nil;
    end
end

local function purge_old_logs()
    if state.log_dir == nil then return; end
    local all = ashita.fs.get_directory(state.log_dir);
    if all == nil then return; end
    for _, name in ipairs(all) do
        if name:lower():sub(-4) == '.log' then
            os.remove(('%s\\%s'):format(state.log_dir, name));
        end
    end
end

local function open_log()
    close_log();

    state.log_dir = addon_subdir('logs');
    ashita.fs.create_directory(state.log_dir);

    if not state.keep then
        purge_old_logs();
    end

    local stamp = os.date('%Y-%m-%d_%H-%M-%S');
    state.path  = ('%s\\session_%s.log'):format(state.log_dir, stamp);
    state.file  = io.open(state.path, 'a+');
    if state.file ~= nil then
        state.file:write(('=== Session started %s ===\n'):format(os.date('%Y-%m-%d %H:%M:%S')));
        state.file:flush();
        print(('[chatlog] logging to: %s'):format(state.path));
    end
end

local function chat(msg) print(('[chatlog] %s'):format(msg)); end

----------------------------------------------------------------------
-- Outbox: viewer-driven sends. The server appends one command per line
-- to <outbox>\queue.txt; we atomically rename it to claim it, read the
-- lines, execute, delete. No directory enumeration anywhere.
----------------------------------------------------------------------

-- Whitelist of slash-command prefixes the viewer is permitted to inject.
-- Defense-in-depth — the server already validates, but if anyone gains
-- local write access to the outbox dir, they still can't run arbitrary
-- commands like /shutdown, /equip, /map, etc.
local OUTBOX_ALLOWED = {
    ['/say']        = true, ['/s']  = true,
    ['/shout']      = true, ['/sh'] = true,
    ['/yell']       = true, ['/y']  = true,
    ['/tell']       = true, ['/t']  = true,
    ['/party']      = true, ['/p']  = true,
    ['/linkshell']  = true, ['/l']  = true,
    ['/linkshell2'] = true, ['/l2'] = true,
};

local QUEUE_NAME       = 'queue.txt';
local QUEUE_PROCESSING = 'queue.processing';

local function queue_path()       return ('%s\\%s'):format(state.outbox_dir, QUEUE_NAME);       end
local function processing_path()  return ('%s\\%s'):format(state.outbox_dir, QUEUE_PROCESSING); end

-- Read every line of `path`, execute whitelisted slash commands, then delete
-- the file. Safe to call when the file doesn't exist (io.open returns nil).
local function process_queue_file(path)
    local f = io.open(path, 'r');
    if f == nil then return 0; end
    local count = 0;
    for line in f:lines() do
        local cmd = line:gsub('[\r\n]', ' ');
        cmd = cmd:match('^%s*(.-)%s*$') or '';
        if #cmd > 0 then
            local prefix = cmd:match('^(/[%w]+)');
            if prefix ~= nil and OUTBOX_ALLOWED[prefix:lower()] and #cmd <= 250 then
                AshitaCore:GetChatManager():QueueCommand(1, cmd);
                if state.debug then write_line('SEND', cmd); end
            else
                if state.debug then write_line('SEND/REJECTED', cmd); end
            end
            count = count + 1;
        end
    end
    f:close();
    os.remove(path);
    return count;
end

local function process_outbox()
    if not state.send_enabled then return; end
    if state.outbox_dir == nil then return; end
    -- Atomic claim: rename queue.txt → queue.processing. If queue.txt
    -- doesn't exist, rename returns nil and we skip. If the server has the
    -- file open mid-write, rename fails on Windows; we retry next tick.
    os.rename(queue_path(), processing_path());
    process_queue_file(processing_path());  -- no-op if processing file isn't there
end

local function drain_outbox()
    if state.outbox_dir == nil then return; end
    os.remove(queue_path());
    os.remove(processing_path());
end

local function init_outbox()
    state.outbox_dir = addon_subdir('outbox');
    ashita.fs.create_directory(state.outbox_dir);

    -- Write a marker file so the user can verify (in Explorer) that the
    -- addon and the server agree on which physical folder this is. If this
    -- file appears in a different folder than where the server is writing,
    -- something is virtualizing/redirecting paths.
    local marker = ('%s\\addon-marker.txt'):format(state.outbox_dir);
    local f = io.open(marker, 'w');
    if f ~= nil then
        f:write(('addon last loaded: %s\n'):format(os.date('%Y-%m-%d %H:%M:%S')));
        f:write(('outbox path: %s\n'):format(state.outbox_dir));
        f:close();
    end

    -- Recover any in-flight queue.processing left over from a previous crash.
    process_queue_file(processing_path());
end

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------

ashita.events.register('load',   'chatlog_load',   function () open_log(); init_outbox(); drain_outbox(); end);
ashita.events.register('unload', 'chatlog_unload', function () close_log(); end);

ashita.events.register('d3d_present', 'chatlog_present', function ()
    local now = os.clock();
    if (now - state.last_poll) >= state.poll_interval then
        state.last_poll = now;
        process_outbox();
    end
end);

-- Backup poll on every incoming packet. d3d_present stops firing when the
-- FFXI window is minimized or unfocused; packet_in keeps firing because the
-- game still receives heartbeats and other server packets in the background.
-- The wall-clock throttle ensures we don't actually poll faster than the
-- configured interval regardless of which event triggers it.
ashita.events.register('packet_in', 'chatlog_packet_in', function (e)
    local now = os.clock();
    if (now - state.last_poll) >= state.poll_interval then
        state.last_poll = now;
        process_outbox();
    end
end);

ashita.events.register('text_in', 'chatlog_text_in', function (e)
    if state.file == nil then return; end

    local masked = e.mode % 256;

    -- One-shot raw hex capture for diagnosing byte sequences.
    if state.hex_next > 0 then
        state.hex_next = state.hex_next - 1;
        local out = {};
        for i = 1, #e.message do out[i] = ('%02X'):format(e.message:byte(i)); end
        write_line(('HEX/M%d'):format(masked), table.concat(out, ' '));
    end

    local clean = sanitize(e.message);

    if state.debug then
        write_line(('RAW%d/M%d'):format(e.mode, masked), clean);
        return;
    end

    local tag = mode_tag[masked];
    if tag == nil then return; end
    write_line(tag, clean);
end);

ashita.events.register('command', 'chatlog_command', function (e)
    local args = e.command:args();
    if #args == 0 or args[1]:lower() ~= '/chatlog' then return; end
    e.blocked = true;

    local sub = (args[2] or ''):lower();
    if sub == 'path' then
        chat(state.path or '(none)');
    elseif sub == 'reopen' then
        open_log();
    elseif sub == 'keep' then
        local v = (args[3] or ''):lower();
        if v == 'on' then state.keep = true; chat('keep ON - old logs will be preserved');
        elseif v == 'off' then state.keep = false; chat('keep OFF - old logs will be purged on new session');
        else chat('usage: /chatlog keep on|off'); end
    elseif sub == 'clean' then
        local v = (args[3] or ''):lower();
        if v == 'on' then state.clean = true;  chat('clean ON - high bytes stripped');
        elseif v == 'off' then state.clean = false; chat('clean OFF - raw bytes preserved');
        else chat('usage: /chatlog clean on|off'); end
    elseif sub == 'hex' then
        local n = tonumber(args[3]) or 5;
        state.hex_next = n;
        chat(('hex dumping next %d chat lines'):format(n));
    elseif sub == 'debug' then
        local v = (args[3] or ''):lower();
        if v == 'on' then state.debug = true;  chat('debug ON');
        elseif v == 'off' then state.debug = false; chat('debug OFF');
        else chat('usage: /chatlog debug on|off'); end
    elseif sub == 'set' then
        local m = tonumber(args[3]);
        local t = (args[4] or ''):upper();
        if m == nil or t == '' then chat('usage: /chatlog set <masked-mode> <TAG>');
        else mode_tag[m] = t; chat(('mode %d -> %s'):format(m, t)); end
    elseif sub == 'clear' then
        local m = tonumber(args[3]);
        if m == nil then chat('usage: /chatlog clear <masked-mode>');
        else mode_tag[m] = nil; chat(('mode %d cleared'):format(m)); end
    elseif sub == 'show' then
        local keys = {};
        for k, _ in pairs(mode_tag) do keys[#keys+1] = k; end
        table.sort(keys);
        for _, k in ipairs(keys) do chat(('  %d -> %s'):format(k, mode_tag[k])); end
    elseif sub == 'send' then
        local v = (args[3] or ''):lower();
        if v == 'on' then
            state.send_enabled = true;
            chat('send ON - viewer can inject chat commands');
        elseif v == 'off' then
            state.send_enabled = false;
            drain_outbox();
            chat('send OFF - outbox drained, polling halted');
        elseif v == 'poll' then
            -- Manual trigger + verbose diagnostic.
            chat(('outbox: %s'):format(state.outbox_dir or '(nil — init_outbox never ran)'));
            chat(('send_enabled: %s'):format(tostring(state.send_enabled)));
            if state.outbox_dir == nil then return; end

            local function inspect(label, path)
                local f = io.open(path, 'r');
                if f == nil then
                    chat(('  %s: not present'):format(label));
                    return;
                end
                local content = f:read('*a') or '';
                f:close();
                chat(('  %s: %d bytes, %d lines'):format(label, #content, select(2, content:gsub('\n', '\n')) or 0));
            end
            inspect('queue.txt',        queue_path());
            inspect('queue.processing', processing_path());
            inspect('addon-marker.txt', ('%s\\addon-marker.txt'):format(state.outbox_dir));

            process_outbox();
            chat('manual poll done');
        elseif v == 'status' or v == '' then
            chat(('send is %s; outbox: %s'):format(
                state.send_enabled and 'ON' or 'OFF',
                state.outbox_dir or '(none)'));
        else
            chat('usage: /chatlog send on|off|poll|status');
        end
    else
        chat('commands: path | reopen | keep on|off | clean on|off | hex [n] | debug on|off | set <m> <TAG> | clear <m> | show | send on|off|poll|status');
    end
end);
