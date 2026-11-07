-- Deliberately broken for tests/lint_selftest.lua: one line per lint rule.
local TB = TortoiseBots

function TB.UsesTypo()
    return GetTiem()                       -- unknown global (typo)
end

function TB.ReadsBeforeLocal()
    return laterPage                       -- local declared below its use
end
local laterPage = 1

function TB.ForgetsLocal()
    leakedCounter = 1                      -- global write without `local`
end

function TB.NewerApi(frame)
    frame:SetSize(10, 10)                  -- method added after 1.12
end

function TB.StringMethod(s)
    return s:sub(1, 2)                     -- strings have no methods in 5.0
end

function TB.NewerLibrary(a, b)
    return math.fmod(a, b)                 -- Lua 5.1 library member
end

function TB.Varargs(...)
    local first = ...                      -- `...` as a value
    return first
end
