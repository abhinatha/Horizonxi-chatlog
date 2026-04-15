--[[
    chatlog - Ashita v4 addon - HorizonXI tuned (v1.5)

    Install: Ashita4\addons\chatlog\chatlog.lua
    Load:    /addon load chatlog

    Per-session log at:
        Ashita4\config\addons\chatlog\logs\session_YYYY-MM-DD_HH-MM-SS.log

    By default, old session logs are deleted when a new session starts.
    Use  /chatlog keep on   to keep history.

    Commands:
        /chatlog path
        /chatlog reopen
        /chatlog keep on|off          - keep or purge old logs (default: off = purge)
        /chatlog debug on|off
        /chatlog set <masked-mode> <TAG>
        /chatlog clear <masked-mode>
        /chatlog show
]]

addon.name    = 'chatlog';
addon.author  = 'abhinatha';
addon.version = '2.0.0-horizon';
addon.desc    = 'Per-session chat log, tuned for HorizonXI.';

require('common');

local state = {
    file     = nil,
    path     = nil,
    log_dir  = nil,
    debug    = false,
    keep     = false,
    clean    = true,    -- strip leftover high bytes that show as � in editors
    hex_next = 0,       -- when > 0, log the next N lines as hex dumps
};

-- (mode & 0xFF) -> tag. Confirmed on HorizonXI.
local mode_tag = {
    [1]   = 'SAY',     [9]  = 'SAY',
    [2]   = 'SHOUT',   [10] = 'SHOUT',
    [3]   = 'YELL',    [11] = 'YELL',
    [4]   = 'TELL',    [12] = 'TELL',
    [5]   = 'PARTY',   [13] = 'PARTY',
    [6]   = 'LS',      [14] = 'LS',     [205] = 'LS2',
    [213] = 'LS2',     [217] = 'LS2',      [214] = 'LS2',
};

-- ------------------------------------------------------------------
-- Auto-translate decoding
--
-- Ashita v4 exposes a native parser: ChatManager:ParseAutoTranslate(msg, useBrackets).
-- It finds 0xFD...0xFD blocks and substitutes the matching English text
-- from the game's own autotranslate DAT files. With useBrackets = true it
-- wraps the result in {Braces} so auto-translated words stay visually distinct.
--
-- If that call isn't available (older Ashita builds), we fall back to a
-- user-editable dictionary at  config\addons\chatlog\at_dict.txt  in the format
--     02 02 01 0B = Hello
-- You can append entries live with   /chatlog at <hex bytes> <word>
-- ------------------------------------------------------------------

local at_dict = {};
local at_dict_path = nil;

local function hex_dump(s)
    local out = {};
    for i = 1, #s do out[i] = ('%02X'):format(s:byte(i)); end
    return table.concat(out, ' ');
end

local function load_at_dict()
    at_dict = {};
    at_dict_path = ('%s\\config\\addons\\%s\\at_dict.txt'):format(AshitaCore:GetInstallPath(), addon.name);
    local f = io.open(at_dict_path, 'r');
    if f == nil then return; end
    for line in f:lines() do
        local hex, word = line:match('^%s*([0-9A-Fa-f%s]+)%s*=%s*(.+)%s*$');
        if hex and word then
            local key = hex:upper():gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '');
            at_dict[key] = word;
        end
    end
    f:close();
end

local function save_at_dict_entry(hex, word)
    if at_dict_path == nil then return; end
    at_dict[hex] = word;
    local f = io.open(at_dict_path, 'a+');
    if f == nil then return; end
    f:write(('%s = %s\n'):format(hex, word));
    f:close();
end

-- Fallback parser: replace each 0xFD...0xFD with dictionary text or hex dump.
local function fallback_decode(msg)
    return (msg:gsub('\xFD(.-)\xFD', function(inner)
        local hex = hex_dump(inner);
        if at_dict[hex] then return '{' .. at_dict[hex] .. '}'; end
        return '{AT?:' .. hex .. '}';
    end));
end

local function sanitize(msg)
    if msg == nil then return ''; end

    -- Prefer Ashita's native parser.
    local cm = AshitaCore:GetChatManager();
    if cm and cm.ParseAutoTranslate then
        local ok, parsed = pcall(function() return cm:ParseAutoTranslate(msg, true); end);
        if ok and type(parsed) == 'string' then
            msg = parsed;
            -- If any 0xFD blocks survived (rare), run the dict fallback on them.
            if msg:find('\xFD') then msg = fallback_decode(msg); end
        else
            msg = fallback_decode(msg);
        end
    else
        msg = fallback_decode(msg);
    end

    -- FFXI uses several non-ASCII byte pairs as decorative brackets.
    -- Known auto-translate brackets: 0xEF 0x27 (open), 0xEF 0x28 (close).
    msg = msg:gsub('\xEF\x27', '[');
    msg = msg:gsub('\xEF\x28', ']');

    -- Player-name and item-name decorative brackets FFXI sends around
    -- names in chat (e.g. <Name>). These appear as single high bytes in
    -- the stream. We replace common ones with ASCII angle brackets and
    -- strip any lone high byte that slipped through.
    msg = msg:gsub('\x81\x79', '<');   -- SJIS heavy bracket open
    msg = msg:gsub('\x81\x7A', '>');   -- SJIS heavy bracket close

    -- Strip color / italic / reset control sequences and any remaining control bytes.
    msg = msg:gsub('[\x1E\x1F].', '');
    msg = msg:gsub('[\x00-\x08\x0B-\x1F\x7F]', '');

    -- Optionally strip remaining high bytes (the � characters in your editor).
    -- Safe for English chat; turn off via /chatlog clean off if it eats content.
    if state.clean then
        msg = msg:gsub('[\x80-\xFF]', '');
    end

    return msg;
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

-- Delete every .log file in the logs dir. Called before opening a new session
-- unless state.keep is true.
local function purge_old_logs()
    if state.log_dir == nil then return; end
    local files = ashita.fs.get_directory(state.log_dir, '.*%.log$');
    if files == nil then return; end
    for _, name in ipairs(files) do
        os.remove(('%s\\%s'):format(state.log_dir, name));
    end
end

local function open_log()
    close_log();

    state.log_dir = ('%s\\config\\addons\\%s\\logs'):format(AshitaCore:GetInstallPath(), addon.name);
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

ashita.events.register('load',   'chatlog_load',   function () load_at_dict(); open_log();  end);
ashita.events.register('unload', 'chatlog_unload', function () close_log(); end);

ashita.events.register('text_in', 'chatlog_text_in', function (e)
    if state.file == nil then return; end

    local masked = e.mode % 256;

    -- One-shot raw hex capture so we can identify the bytes used to wrap names.
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
    elseif sub == 'at' then
        -- /chatlog at <HEX...> <word or phrase>
        -- Example: /chatlog at 02 02 01 0B Hello
        -- Everything that looks like hex bytes at the start becomes the key,
        -- the rest is the translation.
        local rest = {};
        for i = 3, #args do rest[#rest+1] = args[i]; end
        if #rest < 2 then chat('usage: /chatlog at <hex bytes...> <word>'); return; end

        local hex_parts = {};
        local word_parts = {};
        local in_word = false;
        for _, tok in ipairs(rest) do
            if not in_word and tok:match('^%x%x$') then
                hex_parts[#hex_parts+1] = tok:upper();
            else
                in_word = true;
                word_parts[#word_parts+1] = tok;
            end
        end
        if #hex_parts == 0 or #word_parts == 0 then chat('usage: /chatlog at <hex bytes...> <word>'); return; end
        local key = table.concat(hex_parts, ' ');
        local val = table.concat(word_parts, ' ');
        save_at_dict_entry(key, val);
        chat(('AT: %s = %s (saved)'):format(key, val));
        local keys = {};
        for k, _ in pairs(mode_tag) do keys[#keys+1] = k; end
        table.sort(keys);
        for _, k in ipairs(keys) do chat(('  %d -> %s'):format(k, mode_tag[k])); end
    else
        chat('commands: path | reopen | keep on|off | clean on|off | hex [n] | debug on|off | set <m> <TAG> | clear <m> | show | at <hex> <word>');
    end
end);
