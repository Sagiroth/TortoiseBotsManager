-- Alt-bot summary checks (issue: what the player's alt-bots did away).
-- Run from tests/regression.lua, same shape as tests/wire_cases.lua:
-- the caller passes its locals (sent, now, set helpers) in env.

return function(env)
local sent = env.sent
local advanceTime = env.advanceTime

local TB = TortoiseBots

-- The window status line has no mock frame in this harness, so watch what
-- SetStatus is asked to show instead of reading the widget.
local lastStatus, lastKind = nil, nil
local origSetStatus = TB.SetStatus
TB.SetStatus = function(msg, kind) lastStatus, lastKind = msg, kind end

-- The button sends exactly one ".bot alts" query and says it is asking.
advanceTime(1)
local beforeAlts = table.getn(sent)
this = TB.lifecycleButtons.altsummary
TB.lifecycleButtons.altsummary.scripts.OnClick(TB.lifecycleButtons.altsummary)
assert(table.getn(sent) == beforeAlts + 1 and sent[table.getn(sent)] == ".bot alts",
    "Alt summary must send exactly one alts query")
assert(lastStatus == "Asking your alt-bots for a summary…" and lastKind == "pending",
    "Alt summary must say it is asking")

-- Each reply line lands in the Log tab as its own sentence.
local logBefore = table.getn(TB.GetLogHistory())
TB.OnSystemMessage("TBM:ALTSUM|Alpha|Alpha: level 23, now in Elwynn Forest.")
TB.OnSystemMessage("TBM:ALTSUM|Beta|Beta: level 41 -> 44, +12g, 8 quests done, now in Stranglethorn Vale.")
TB.OnSystemMessage("TBM:ALTSUM_END|2")
local historyAfter = TB.GetLogHistory()
assert(table.getn(historyAfter) == logBefore + 2, "each summary line must reach the Log tab")
assert(historyAfter[table.getn(historyAfter) - 1].msg == "Alpha: level 23, now in Elwynn Forest.",
    "the first summary sentence must be kept whole")
assert(historyAfter[table.getn(historyAfter)].msg
    == "Beta: level 41 -> 44, +12g, 8 quests done, now in Stranglethorn Vale.",
    "the second summary sentence must be kept whole")
assert(lastStatus == "Alt summary · 2 alt-bots" and lastKind == "ok",
    "the status line must count the summaries")

-- A complete burst is shown even unprompted: the server pushes one at login.
TB.OnSystemMessage("TBM:ALTSUM|Gamma|Gamma: rested.")
TB.OnSystemMessage("TBM:ALTSUM_END|1")
assert(TB.GetLogHistory()[table.getn(TB.GetLogHistory())].msg == "Gamma: rested.",
    "an unprompted burst must still be shown")

-- A malformed row is dropped; END still commits an empty summary.
TB.OnSystemMessage("TBM:ALTSUM|Broken")
TB.OnSystemMessage("TBM:ALTSUM_END|1")
assert(TB.GetLogHistory()[table.getn(TB.GetLogHistory())].msg
    == "No alt-bots are playing on their own.", "a malformed row must be dropped, not logged")

-- Count 0 says the alts are quiet, on screen and in the Log tab.
TB.OnSystemMessage("TBM:ALTSUM_END|0")
assert(TB.GetLogHistory()[table.getn(TB.GetLogHistory())].msg
    == "No alt-bots are playing on their own.", "count 0 must say no alt-bots are out")
assert(lastStatus == "No alt-bots are playing on their own." and lastKind == "muted",
    "count 0 must show on the status line")

TB.SetStatus = origSetStatus

print("PASS: alt-bot summary checks")
end
