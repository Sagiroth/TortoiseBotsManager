-- Proves every rule of tests/lint.lua fires: lints tests/lint_fixture
-- (one broken line per rule) and checks each expected failure is reported.
-- Run with: lua5.1 tests/lint_selftest.lua .

local root = arg[1] or "."
local pipe = io.popen("lua5.1 '" .. root .. "/tests/lint.lua' '" .. root .. "/tests/lint_fixture' 2>&1")
local out = pipe:read("*a")
pipe:close()

local expected = {
    "reads unknown global 'GetTiem'",
    "reads unknown global 'laterPage'",
    "writes global 'leakedCounter'",
    ":SetSize() does not exist in 1.12",
    ":sub() on a string fails in Lua 5.0",
    "math.fmod is not in Lua 5.0",
    "`...` used as a value",
    "FAIL: lint,",
}
local missing = 0
for _, text in ipairs(expected) do
    if not string.find(out, text, 1, true) then
        print("FAIL: lint did not report: " .. text)
        missing = missing + 1
    end
end
if missing > 0 then
    print(out)
    os.exit(1)
end
print("PASS: lint self-test, all " .. table.getn(expected) .. " rules fire on the fixture")
