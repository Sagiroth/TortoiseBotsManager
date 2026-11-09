-- TortoiseBotsManager lint: catches code that loads in the tests (Lua 5.1)
-- but breaks in the WoW 1.12 client (Lua 5.0 and the 1.12 widget API).
-- Run with: lua5.1 tests/lint.lua .   (also run by tests/lua50_syntax.lua)
--
-- It reads the compiler listing (luac5.1 -l, shipped with the lua5.1 package)
-- of every file in the .toc and checks:
--   1. Globals. Every global the code reads or writes must be on the lists
--      below. An unknown read is a typo, a `local` declared below its first
--      use (the code then reads a nil global), or an API the 1.12 client
--      does not have. An unknown write is a missing `local`.
--      Adding a name: make sure the 1.12 client has it (vanilla FrameXML or
--      the 1.12 API list), then add it to the right list with its source.
--   2. Methods that do not exist in 1.12 (SetSize, SetShown, HookScript ...)
--      and string methods called with ':' (Lua 5.0 strings have no methods:
--      s:sub(1, 2) fails, string.sub(s, 1, 2) works).
--   3. Library members: string./math./table./coroutine. may only name what
--      Lua 5.0 has (string.match, math.fmod, math.huge, table.maxn are 5.1).
--   4. `...` outside a parameter list (5.0 passes varargs in `arg`).
--   5. Functions close to the 32-upvalue limit are listed as a warning.

local root = arg[1] or "."
local luac = os.getenv("LUAC") or "luac5.1"

local function set(list)
    local s = {}
    for _, v in ipairs(list) do s[v] = true end
    return s
end

-- Lua 5.0 as the 1.12 client ships it (no io, os, debug, require).
local LUA_GLOBALS = set({
    "assert", "collectgarbage", "error", "gcinfo", "getfenv", "getmetatable", "ipairs",
    "loadstring", "next", "pairs", "pcall", "rawequal", "rawget", "rawset",
    "setfenv", "setmetatable", "tonumber", "tostring", "type", "unpack", "xpcall", "_G",
    "string", "table", "math", "coroutine",
    -- WoW's own Lua helpers in 1.12
    "date", "time", "getglobal", "setglobal", "strlen", "strsub", "strfind", "strlower",
    "strupper", "format", "gsub", "strrep", "tinsert", "tremove", "getn", "floor", "ceil",
    "abs", "min", "max", "mod", "random", "sqrt",
    -- the 1.12 script globals: the running frame, the event and its args
    "this", "event", "arg", "arg1", "arg2", "arg3", "arg4", "arg5", "arg6", "arg7", "arg8", "arg9",
})

-- 1.12 client API and FrameXML globals the addon uses.
local WOW_GLOBALS = set({
    -- widgets and FrameXML frames
    "CreateFrame", "UIParent", "Minimap", "GameTooltip", "UIErrorsFrame", "RaidWarningFrame",
    "DEFAULT_CHAT_FRAME", "ChatFrameEditBox", "UISpecialFrames", "SlashCmdList",
    "StaticPopupDialogs", "StaticPopup_Show", "ToggleDropDownMenu", "UIDropDownMenu_AddButton",
    "UIDropDownMenu_Initialize", "FauxScrollFrame_GetOffset", "FauxScrollFrame_OnVerticalScroll",
    "FauxScrollFrame_Update", "ChatFrame_AddMessageEventFilter", "ChatFrame_OnEvent",
    "MailFrame", "MailFrameTab_OnClick", "SendMailBodyEditBox", "SendMailNameEditBox",
    "SendMailSubjectEditBox", "ClickSendMailItemButton", "GetSendMailItem",
    -- units, group, guild
    "UnitClass", "UnitExists", "UnitFactionGroup", "UnitIsDead", "UnitIsGhost", "UnitIsPlayer",
    "UnitLevel", "UnitName", "GetNumPartyMembers", "GetNumRaidMembers", "TargetByName",
    "TargetUnit", "DoReadyCheck", "CanEditOfficerNote", "GuildControlGetNumRanks",
    "GuildControlGetRankName", "GuildUninvite", "UnitHealth", "UnitHealthMax",
    "UnitMana", "UnitManaMax", "UnitBuff", "CheckInteractDistance", "UnitIsUnit",
    -- items and bags
    "GetContainerItemInfo", "GetContainerItemLink", "GetContainerNumSlots", "GetItemInfo",
    "GetItemQualityColor", "PickupContainerItem", "SplitContainerItem", "ClearCursor",
    "CursorHasItem",
    -- misc
    "GetTime", "GetCursorPosition", "GetScreenHeight", "GetScreenWidth", "GetRealZoneText",
    "GetZoneText", "IsInInstance", "IsShiftKeyDown", "PlaySound", "SendAddonMessage",
    "SendChatMessage",
    -- key bindings (C API plus FrameXML UIParent.lua)
    "GetBindingKey", "GetBindingText",
    -- `os and os.date(...)`: a probe that is nil in the client, never called there
    "os",
})

-- Globals the addon itself owns.
local ADDON_GLOBALS = set({ "TortoiseBots", "TortoiseBotsDB" })
local ADDON_WRITE_PATTERNS = { "^BINDING_HEADER_", "^BINDING_NAME_", "^SLASH_" }
-- Deliberate writes to a client global (a hook that keeps the original).
local HOOKED_GLOBALS = set({ "ChatFrame_OnEvent" })

-- Methods added after 1.12: calling one fails with "attempt to call method".
local NOT_IN_112 = {
    SetSize = "3.0", GetSize = "3.0", SetShown = "5.0", SetColorTexture = "7.0", SetAtlas = "5.0",
    HookScript = "2.1", CreateAnimationGroup = "3.1", SetClipsChildren = "7.0",
    SetObeyStepOnDrag = "7.0", SetResizeBounds = "10.0", SetFixedFrameStrata = "8.0",
    SetFixedFrameLevel = "8.0", SetIgnoreParentScale = "2.0", SetIgnoreParentAlpha = "2.0",
    SetEnabled = "3.0", SetFormattedText = "2.0", RegisterUnitEvent = "5.0",
    SetMask = "7.0", SetSnapToPixelGrid = "8.0", SetTexelSnappingBias = "8.0",
    SetPropagateKeyboardInput = "5.0", SetMotionScriptsWhileDisabled = "3.0",
}
local STRING_METHODS = set({ "sub", "find", "gsub", "len", "lower", "upper", "format", "rep",
    "byte", "char", "match", "gmatch", "gfind", "reverse", "split", "trim" })

-- What each library has in Lua 5.0.
local LIB_50 = {
    string = set({ "byte", "char", "dump", "find", "format", "gfind", "gsub", "len", "lower",
        "rep", "sub", "upper" }),
    math = set({ "abs", "acos", "asin", "atan", "atan2", "ceil", "cos", "deg", "exp", "floor",
        "frexp", "ldexp", "log", "log10", "max", "min", "mod", "pi", "pow", "rad", "random",
        "randomseed", "sin", "sqrt", "tan" }),
    table = set({ "concat", "foreach", "foreachi", "getn", "insert", "remove", "setn", "sort" }),
    coroutine = set({ "create", "resume", "status", "wrap", "yield" }),
}

local UPVALUE_LIMIT, UPVALUE_WARN = 32, 30

local function read(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

local function tocFiles()
    local files = {}
    for raw in string.gmatch(read(root .. "/TortoiseBotsManager.toc") or "", "[^\n]+") do
        local line = string.gsub(string.gsub(raw, "\r", ""), "^%s*(.-)%s*$", "%1")
        if line ~= "" and string.sub(line, 1, 1) ~= "#" then table.insert(files, line) end
    end
    return files
end

local function writeAllowed(name)
    if ADDON_GLOBALS[name] or HOOKED_GLOBALS[name] then return true end
    for _, p in ipairs(ADDON_WRITE_PATTERNS) do
        if string.find(name, p) then return true end
    end
    return false
end

local problems, warnings = {}, {}
local function bad(msg) table.insert(problems, msg) end

-- Source-level checks: library members and `...`.
local function checkSource(rel, src)
    -- Blank out comments and strings, keeping line breaks for line numbers.
    local clean = string.gsub(src, "%-%-%[(=*)%[.-%]%1%]", function(eq) return "" end)
    clean = string.gsub(clean, "%-%-[^\n]*", "")
    clean = string.gsub(clean, "%[(=*)%[(.-)%]%1%]", function(_, body)
        return (string.gsub(body, "[^\n]", " "))
    end)
    clean = string.gsub(clean, "\"[^\"\n]*\"", "\"\"")
    clean = string.gsub(clean, "'[^'\n]*'", "''")
    local lineNo = 0
    for line in string.gmatch(clean .. "\n", "([^\n]*)\n") do
        lineNo = lineNo + 1
        for lib, member in string.gmatch(line, "%f[%w_]([%a]+)%.([%a_][%w_]*)") do
            if LIB_50[lib] and not LIB_50[lib][member] then
                bad(string.format("%s:%d: %s.%s is not in Lua 5.0 (the 1.12 client)", rel, lineNo, lib, member))
            end
        end
        local start = 1
        while true do
            local s, e = string.find(line, "%.%.%.", start)
            if not s then break end
            -- Only a parameter list may hold `...`: "function name(a, ...)".
            local before = string.sub(line, 1, s - 1)
            if not string.find(before, "function[%s%w_%.:]*%([%w_,%s]*$") then
                bad(string.format("%s:%d: `...` used as a value (Lua 5.0 passes varargs in `arg`)", rel, lineNo))
            end
            start = e + 1
        end
    end
end

-- Bytecode checks: globals, methods, upvalues.
local function checkListing(rel, listing)
    local where = "?"
    for line in string.gmatch(listing, "[^\n]+") do
        local _, _, span = string.find(line, "^%a+ <[^:]+:(%d+),%d+>")
        if span then where = span end
        local _, _, ups = string.find(line, "(%d+) upvalues?,")
        if ups then
            local n = tonumber(ups)
            if n > UPVALUE_LIMIT then
                bad(string.format("%s:%s: function has %d upvalues; the 1.12 client allows %d (split it)",
                    rel, where, n, UPVALUE_LIMIT))
            elseif n >= UPVALUE_WARN then
                table.insert(warnings, string.format("%s:%s: %d upvalues, close to the limit of %d",
                    rel, where, n, UPVALUE_LIMIT))
            end
        end
        local _, _, lineNo, op, name = string.find(line, "%[(%d+)%]%s+([GS]ETGLOBAL)%s.-; ([%w_]+)%s*$")
        if op == "GETGLOBAL" and not (LUA_GLOBALS[name] or WOW_GLOBALS[name] or ADDON_GLOBALS[name]
            or writeAllowed(name)) then
            bad(string.format("%s:%s: reads unknown global '%s' (typo? local declared below its use?"
                .. " API missing in 1.12? see tests/lint.lua)", rel, lineNo, name))
        elseif op == "SETGLOBAL" and not writeAllowed(name) then
            bad(string.format("%s:%s: writes global '%s' (missing `local`?)", rel, lineNo, name))
        end
        local _, _, selfLine, method = string.find(line, "%[(%d+)%]%s+SELF%s.-; \"([%w_]+)\"%s*$")
        if method then
            if NOT_IN_112[method] then
                bad(string.format("%s:%s: :%s() does not exist in 1.12 (added in %s)",
                    rel, selfLine, method, NOT_IN_112[method]))
            elseif STRING_METHODS[method] then
                bad(string.format("%s:%s: :%s() on a string fails in Lua 5.0; use string.%s(s, ...)",
                    rel, selfLine, method, method))
            end
        end
    end
end

local probe = io.popen(luac .. " -v 2>&1")
local version = probe and probe:read("*a") or ""
if probe then probe:close() end
if not string.find(version, "Lua") then
    print("FAIL: lint needs luac5.1 (part of the lua5.1 package; or set LUAC=...)")
    os.exit(1)
end

local files = tocFiles()
for _, rel in ipairs(files) do
    local path = root .. "/" .. rel
    local src = read(path)
    if not src then
        bad(rel .. ": listed in the .toc but missing")
    else
        checkSource(rel, src)
        local pipe = io.popen(luac .. " -l -p '" .. path .. "' 2>&1")
        local listing = pipe and pipe:read("*a") or ""
        if pipe then pipe:close() end
        if string.find(listing, "^luac") then
            bad(rel .. ": does not compile: " .. listing)
        else
            checkListing(rel, listing)
        end
    end
end

for _, w in ipairs(warnings) do print("WARN: " .. w) end
if table.getn(problems) > 0 then
    for _, p in ipairs(problems) do print("FAIL: " .. p) end
    print(string.format("FAIL: lint, %d problem(s) in %d file(s)", table.getn(problems), table.getn(files)))
    os.exit(1)
end
print(string.format("PASS: lint, %d .toc files: globals, 1.12 methods, Lua 5.0 library, varargs, upvalues",
    table.getn(files)))
