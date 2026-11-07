-- TortoiseBotsManager Lua 5.0 syntax guard.
-- Run with: lua5.1 tests/lua50_syntax.lua .
--
-- The WoW 1.12 client runs Lua 5.0. CI only has lua5.1 (no lua5.0 package is
-- available), so instead of compiling with a 5.0 interpreter this tokenizes every
-- addon file listed in the .toc and fails on constructs the 1.12 client rejects:
--   %          arithmetic operator (5.0: use math.mod)
--   #          length operator (house rule: use table.getn)
--   select('#' select does not exist in 5.0
--   gmatch     string.gmatch / :gmatch( (5.0: string.gfind)
--   goto       reserved in neither 5.0 nor 5.1; kept on the list as a house rule
-- It also fails on any function with more than 32 upvalues (5.0's limit; see
-- the end of this file).
-- Strings and comments are skipped, so '%s' patterns and "# drop" text pass.

local root = arg[1] or "."

local function read_file(path)
    local f, err = io.open(path, "rb")
    if not f then return nil, err end
    local s = f:read("*a")
    f:close()
    return s
end

local function count_newlines(text)
    local _, n = string.gsub(text, "\n", "")
    return n
end

-- Token kinds: name, number, string (quotes kept in text), op (one char).
-- Comments and whitespace produce no tokens.
local function tokenize(src, file)
    local toks = {}
    local pos, line, n = 1, 1, string.len(src)
    while pos <= n do
        local _, ws_end = string.find(src, "^%s+", pos)
        if ws_end then
            line = line + count_newlines(string.sub(src, pos, ws_end))
            pos = ws_end + 1
        elseif string.sub(src, pos, pos + 1) == "--" then
            local _, _, eqs = string.find(src, "^%[(=*)%[", pos + 2)
            local stop
            if eqs then
                local close = "]" .. eqs .. "]"
                local _, ce = string.find(src, close, pos + 2 + #eqs + 2, true)
                if not ce then error(file .. ":" .. line .. ": unterminated long comment") end
                stop = ce
            else
                local nl = string.find(src, "\n", pos, true)
                stop = nl and (nl - 1) or n
            end
            line = line + count_newlines(string.sub(src, pos, stop))
            pos = stop + 1
        elseif string.find(src, "^%[=*%[", pos) then
            local _, _, eqs = string.find(src, "^%[(=*)%[", pos)
            local close = "]" .. eqs .. "]"
            local _, ce = string.find(src, close, pos + #eqs + 2, true)
            if not ce then error(file .. ":" .. line .. ": unterminated long string") end
            local text = string.sub(src, pos, ce)
            table.insert(toks, { kind = "string", text = text, line = line })
            line = line + count_newlines(text)
            pos = ce + 1
        elseif string.find(src, "^[\"']", pos) then
            local q = string.sub(src, pos, pos)
            local pat = (q == "'") and "[\\\n']" or "[\\\n\"]"
            local j, close = pos + 1, nil
            while true do
                local p = string.find(src, pat, j)
                if not p then error(file .. ":" .. line .. ": unterminated string") end
                local ch = string.sub(src, p, p)
                if ch == "\\" then
                    j = p + 2
                elseif ch == "\n" then
                    error(file .. ":" .. line .. ": newline in string")
                else
                    close = p
                    break
                end
            end
            local text = string.sub(src, pos, close)
            table.insert(toks, { kind = "string", text = text, line = line })
            line = line + count_newlines(text)
            pos = close + 1
        elseif string.find(src, "^[%a_]", pos) then
            local _, e = string.find(src, "^[%a_][%w_]*", pos)
            table.insert(toks, { kind = "name", text = string.sub(src, pos, e), line = line })
            pos = e + 1
        elseif string.find(src, "^%.?%d", pos) then
            local _, e = string.find(src, "^%.?%d[%w%.]*", pos)
            table.insert(toks, { kind = "number", text = string.sub(src, pos, e), line = line })
            pos = e + 1
        else
            local ch = string.sub(src, pos, pos)
            table.insert(toks, { kind = "op", text = ch, line = line })
            pos = pos + 1
        end
    end
    return toks
end

local BANNED_OPS = {
    ["%"] = "% arithmetic operator (Lua 5.0 has no %; use math.mod)",
    ["#"] = "# length operator (house rule: use table.getn)",
}
local BANNED_NAMES = {
    gmatch = "string.gmatch / :gmatch( (Lua 5.0 has string.gfind)",
    goto = "goto (reserved in neither 5.0 nor 5.1; house rule)",
}

local function check_tokens(toks, file)
    local problems = {}
    local function flag(line, msg)
        table.insert(problems, file .. ":" .. line .. ": " .. msg)
    end
    for i, t in ipairs(toks) do
        if t.kind == "op" and BANNED_OPS[t.text] then
            flag(t.line, BANNED_OPS[t.text])
        elseif t.kind == "name" and BANNED_NAMES[t.text] then
            flag(t.line, BANNED_NAMES[t.text])
        elseif t.kind == "name" and t.text == "select" then
            local a, b = toks[i + 1], toks[i + 2]
            if a and b and a.kind == "op" and a.text == "(" and b.kind == "string"
                and (b.text == "'#'" or b.text == '"#"') then
                flag(t.line, "select('#', ...) (select is not in Lua 5.0)")
            end
        end
    end
    return problems
end

local function toc_files(toc_path)
    local src, err = read_file(toc_path)
    if not src then error("cannot read " .. toc_path .. ": " .. tostring(err)) end
    local files = {}
    for raw in string.gmatch(src, "[^\n]+") do
        local line = string.gsub(raw, "\r", "")
        line = string.gsub(line, "^%s+", "")
        line = string.gsub(line, "%s+$", "")
        if line ~= "" and string.sub(line, 1, 1) ~= "#" then
            table.insert(files, line)
        end
    end
    return files
end

local toc = root .. "/TortoiseBotsManager.toc"
local files = toc_files(toc)
local problems, scanned = {}, 0
for _, rel in ipairs(files) do
    local path = root .. "/" .. rel
    local src, err = read_file(path)
    if not src then
        table.insert(problems, path .. ": listed in .toc but cannot be read (" .. tostring(err) .. ")")
    else
        scanned = scanned + 1
        local ok, toks = pcall(tokenize, src, rel)
        if not ok then
            table.insert(problems, tostring(toks))
        else
            for _, p in ipairs(check_tokens(toks, rel)) do
                table.insert(problems, p)
            end
        end
    end
end

-- Compiler limits. Lua 5.0 refuses a function with more than 32 upvalues
-- ("too many upvalues (limit=32)") where 5.1 allows 60, so a file that loads
-- here can still fail in the client. luac5.1 (shipped with the lua5.1
-- package) lists every function with its upvalue and register counts; 5.0
-- shares the 250-register and 200-local limits, so only upvalues differ.
local MAX_UPVALUES_50 = 32
local luac = os.getenv("LUAC") or "luac5.1"
local probe = io.popen(luac .. " -v 2>&1")
local version = probe and probe:read("*a") or ""
if probe then probe:close() end
if not string.find(version, "Lua") then
    table.insert(problems, "luac5.1 not found: cannot check the Lua 5.0 upvalue limit (set LUAC=...)")
else
    for _, rel in ipairs(files) do
        local path = root .. "/" .. rel
        local pipe = io.popen(luac .. " -l -p '" .. path .. "' 2>&1")
        local listing = pipe and pipe:read("*a") or ""
        if pipe then pipe:close() end
        local where = nil
        for line in string.gmatch(listing, "[^\n]+") do
            local _, _, span = string.find(line, "^%a+ <[^:]+:(%d+,%d+)>")
            if span then where = span end
            local _, _, ups = string.find(line, "(%d+) upvalues?,")
            if ups and tonumber(ups) > MAX_UPVALUES_50 then
                table.insert(problems, string.format("%s:%s: %s upvalues, the 1.12 client allows %d"
                    .. " (split the function)", rel, where or "?", ups, MAX_UPVALUES_50))
            end
        end
    end
end

if table.getn(problems) > 0 then
    for _, p in ipairs(problems) do print("FAIL: " .. p) end
    print(string.format("FAIL: Lua 5.0 syntax check, %d problem(s) in %d file(s)", table.getn(problems), scanned))
    os.exit(1)
end
print(string.format("PASS: Lua 5.0 syntax check, %d .toc files scanned, no 5.1-only syntax, upvalues within %d", scanned, MAX_UPVALUES_50))
