BINDING_HEADER_TBM = "TortoiseBots Manager"
BINDING_NAME_TBM_ATTACK = "Attack target"
BINDING_NAME_TBM_STOP = "Stop combat"
BINDING_NAME_TBM_INTERRUPT = "Interrupt target"
BINDING_NAME_TBM_FLEE = "Flee"
BINDING_NAME_TBM_PULL = "Pull target"
BINDING_NAME_TBM_PULLBACK = "Pull target back"
BINDING_NAME_TBM_FOCUS_SKULL = "Focus skull"
BINDING_NAME_TBM_FOLLOW = "Follow"
BINDING_NAME_TBM_STAY = "Stay"
BINDING_NAME_TBM_COME = "Come and hold"
BINDING_NAME_TBM_TOGGLE_WINDOW = "Toggle window"
BINDING_NAME_TBM_MINI_MODE = "Toggle mini bar"

local TB = TortoiseBots

-- Keybinding handlers: one gameplay intent each, same path as the Fight tab.
function TB.SendKeyIntent(intent)
    intent = TB.Trim(intent or "")
    if intent == "" then return false end
    if intent == "flee" then
        if TB.HasServerCapability and not TB.HasServerCapability("flee") then return false end
        return TB.SendBotCommand("action " .. intent)
    end
    if intent == "pull" or intent == "pullback" then
        if TB.PullIntent then intent = TB.PullIntent(intent) end
        return TB.SendBotCommand("action " .. intent)
    end
    return TB.SendActionIntent(intent)
end
