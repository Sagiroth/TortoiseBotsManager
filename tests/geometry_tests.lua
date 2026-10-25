-- tests/geometry_tests.lua
-- Pixel-geometry regression: every window/tab must assemble without overlaps.
-- Computes each frame's absolute rect from size + SetPoint anchors, then asserts:
--   * every child rect sits inside its parent (allowing the card border inset),
--   * sibling controls in the same card/row do not overlap,
--   * cards on a tab do not overlap each other,
--   * button labels fit their button (estimated text width vs inner width).
-- Wired into tests/regression.lua after the main pass.

return function()
    local TB = TortoiseBots

    -- ── anchor math ──────────────────────────────────────────────────
    -- Rects are { left, top, right, bottom } with y growing DOWNWARD from the
    -- window top: a child at SetPoint("TOPLEFT", parent, "TOPLEFT", x, y) sits
    -- at (x, -y), because WoW offsets grow upward. All checks stay in this space.

    local function anchorXY(rect, point)
        if point == "TOPLEFT" then return rect.left, rect.top end
        if point == "TOPRIGHT" then return rect.right, rect.top end
        if point == "BOTTOMLEFT" then return rect.left, rect.bottom end
        if point == "BOTTOMRIGHT" then return rect.right, rect.bottom end
        if point == "TOP" then return (rect.left + rect.right) / 2, rect.top end
        if point == "BOTTOM" then return (rect.left + rect.right) / 2, rect.bottom end
        if point == "LEFT" then return rect.left, (rect.top + rect.bottom) / 2 end
        if point == "RIGHT" then return rect.right, (rect.top + rect.bottom) / 2 end
        return (rect.left + rect.right) / 2, (rect.top + rect.bottom) / 2 -- CENTER
    end

    local function stripCodes(text)
        local s = string.gsub(text or "", "|c%x%x%x%x%x%x%x%x", "")
        s = string.gsub(s, "|r", "")
        return s
    end

    -- Estimated rendered text width. GameFontNormalSmall /
    -- GameFontHighlightSmall average ~6 px per latin char; GameFontNormal ~7.
    local function textWidth(text, perChar)
        text = stripCodes(text)
        local narrow = 0
        for _ in string.gfind(text, "·") do narrow = narrow + 1 end
        for _ in string.gfind(text, " ") do narrow = narrow + 1 end
        return (string.len(text) - narrow) * (perChar or 6) + narrow * 3
    end

    -- UIPanelButtonTemplate keeps ~10 px total for the endcaps.
    local BUTTON_INSET = 10

    local function overlaps(a, b)
        return not (a.right <= b.left or b.right <= a.left
            or a.bottom <= b.top or b.bottom <= a.top)
    end

    local function inside(child, parent, inset)
        inset = inset or 0
        return child.left >= parent.left - inset
            and child.right <= parent.right + inset
            and child.top >= parent.top - inset
            and child.bottom <= parent.bottom + inset
    end

    local function fmt(r)
        return string.format("(%d,%d)-(%d,%d)",
            math.floor(r.left + 0.5), math.floor(r.top + 0.5),
            math.floor(r.right + 0.5), math.floor(r.bottom + 0.5))
    end

    -- Resolve a mock frame's absolute rect from its SetPoint chain. The mock
    -- records every SetPoint in f.points plus the live one in f.point; the
    -- LAST point wins (1.12 semantics: SetPoint replaces), except the two
    -- corner stretch pattern (TOPLEFT + TOPRIGHT/BOTTOMRIGHT/BOTTOMLEFT),
    -- which spans both anchors.
    local function frameRect(f, cache, depth)
        cache = cache or {}
        depth = depth or 0
        assert(depth < 30, "geometry: anchor cycle near " .. tostring(f and f.name))
        if cache[f] then return cache[f] end
        local width = f.width or 0
        local height = f.height or 0
        local pts = {}
        if f.points then
            for _, p in ipairs(f.points) do table.insert(pts, p) end
        end
        if table.getn(pts) == 0 and f.point then
            table.insert(pts, f.point)
        end
        local r
        if table.getn(pts) == 0 then
            local px, py = 0, 0
            if f.parent and f.parent ~= f then
                local pr = frameRect(f.parent, cache, depth + 1)
                px, py = pr.left, pr.top
            end
            r = { left = px, top = py, right = px + width, bottom = py + height }
        elseif table.getn(pts) >= 2 then
            local first, last = pts[1], pts[table.getn(pts)]
            local stretch = first[1] == "TOPLEFT"
                and (last[1] == "TOPRIGHT" or last[1] == "BOTTOMRIGHT" or last[1] == "BOTTOMLEFT")
            if stretch then
                local pra = frameRect(first[2] or f.parent, cache, depth + 1)
                local prb = frameRect(last[2] or f.parent, cache, depth + 1)
                local ax, ay = anchorXY(pra, first[1])
                local bx, by = anchorXY(prb, last[1])
                ax, ay = ax + (first[4] or 0), ay - (first[5] or 0)
                bx, by = bx + (last[4] or 0), by - (last[5] or 0)
                r = {
                    left = math.min(ax, bx),
                    top = math.min(ay, by),
                    right = math.max(ax, bx),
                    bottom = math.max(ay, by),
                }
                if height > 0 and last[1] == "TOPRIGHT" then
                    r.bottom = r.top + height
                end
            else
                local pt = last
                local relTo = pt[2] or f.parent
                local pr = frameRect(relTo, cache, depth + 1)
                local ax, ay = anchorXY(pr, pt[3] or "TOPLEFT")
                ax, ay = ax + (pt[4] or 0), ay - (pt[5] or 0)
                local self = { left = 0, top = 0, right = width, bottom = height }
                local mx, my = anchorXY(self, pt[1] or "TOPLEFT")
                r = { left = ax - mx, top = ay - my,
                    right = ax - mx + width, bottom = ay - my + height }
            end
        else
            local pt = pts[1]
            local relTo = pt[2] or f.parent
            local pr = frameRect(relTo, cache, depth + 1)
            local ax, ay = anchorXY(pr, pt[3] or "TOPLEFT")
            ax, ay = ax + (pt[4] or 0), ay - (pt[5] or 0)
            local self = { left = 0, top = 0, right = width, bottom = height }
            local mx, my = anchorXY(self, pt[1] or "TOPLEFT")
            r = { left = ax - mx, top = ay - my,
                right = ax - mx + width, bottom = ay - my + height }
        end
        cache[f] = r
        return r
    end

    local problems = {}
    local function bad(msg)
        table.insert(problems, msg)
    end

    -- FontStrings without explicit SetHeight: single-line height by template.
    local function textHeight(f)
        if f.height then return f.height end
        return 12
    end

    -- Button label fit: centered text must clear endcaps, lamps and icons.
    local function labelFits(name, btn, sampleText, perChar)
        local w = btn.width or 0
        local text = sampleText or btn.text or btn:GetText() or ""
        local need = textWidth(text, perChar) + BUTTON_INSET
        if btn.lamp and btn.lamp.width then need = need + btn.lamp.width + 2 end
        local icon = btn.icon
        if icon and icon.width and icon.visible ~= false and not (icon.hidden) then
            need = need + icon.width
        end
        if need > w then
            bad(string.format("%s: label '%s' needs ~%dpx in a %dpx button",
                name, stripCodes(text), need, w))
        end
    end

    local function childrenInside(group, parent, parentRect, names, cache, inset)
        for _, entry in ipairs(names) do
            local f = entry[2]
            if f then
                local r = frameRect(f, cache)
                if not inside(r, parentRect, inset or 3) then
                    bad(string.format("%s: '%s' %s escapes parent %s",
                        group, entry[1], fmt(r), fmt(parentRect)))
                end
            end
        end
    end

    local function noOverlaps(group, items, cache)
        local rects = {}
        for _, entry in ipairs(items) do
            if entry[2] then
                table.insert(rects, { entry[1], frameRect(entry[2], cache) })
            end
        end
        for i = 1, table.getn(rects) do
            for j = i + 1, table.getn(rects) do
                if overlaps(rects[i][2], rects[j][2]) then
                    bad(string.format("%s: '%s' %s overlaps '%s' %s",
                        group, rects[i][1], fmt(rects[i][2]),
                        rects[j][1], fmt(rects[j][2])))
                end
            end
        end
    end

    -- ── Fight tab ────────────────────────────────────────────────────
    do
        local cache = {}
        local cards = TB.fightCards or {}
        local order = { "engage", "pull", "move", "switches", "tactics" }
        local items = {}
        for _, id in ipairs(order) do
            if cards[id] then table.insert(items, { id, cards[id] }) end
        end
        noOverlaps("Fight cards", items, cache)
        local B = TB.actionButtons or {}
        local function cardControls(id, names)
            local card = cards[id]
            if not card then return end
            local cr = frameRect(card, cache)
            local list = {}
            for _, n in ipairs(names) do
                if B[n] then table.insert(list, { n, B[n] }) end
            end
            childrenInside("Fight " .. id, card, cr, list, cache, 3)
            noOverlaps("Fight " .. id .. " controls", list, cache)
        end
        cardControls("engage", { "attack", "stop", "interrupt", "flee" })
        cardControls("pull", { "pull", "pullback", "pullTimer", "pullbackTimer",
            "endPull", "focusSkull", "ccMoon" })
        cardControls("move", { "follow", "stay", "come", "guard", "free" })
        local moveList = {}
        for _, n in ipairs({ "follow", "stay", "come", "guard", "free" }) do
            if B[n] then table.insert(moveList, { n, B[n] }) end
        end
        for id, pill in pairs(TB.stancePills or {}) do
            table.insert(moveList, { "stance." .. id, pill })
        end
        if cards.move then
            childrenInside("Fight move", cards.move, frameRect(cards.move, cache), moveList, cache, 3)
        end
        noOverlaps("Fight move controls", moveList, cache)
        local switchList = {}
        for key, btn in pairs(TB.toggleButtons or {}) do
            table.insert(switchList, { key, btn })
        end
        if cards.switches then
            childrenInside("Fight switches", cards.switches,
                frameRect(cards.switches, cache), switchList, cache, 3)
        end
        noOverlaps("Fight switch controls", switchList, cache)
        cardControls("tactics", { "tacticKite", "tacticMark", "tacticFocus", "tacticAoeFear" })

        for key, sample in pairs({ aoe = "AoE ~", autocc = "Auto CC Off",
            sap = "Sap Off", spread = "Spread Off", loot = "Loot Off" }) do
            local btn = (TB.toggleButtons or {})[key]
            if btn then labelFits("Fight switches." .. key, btn, sample, 6) end
        end
        for _, n in ipairs({ "follow", "stay", "come", "guard", "free" }) do
            if B[n] then labelFits("Fight move." .. n, B[n], nil, 6) end
        end
        for _, n in ipairs({ "pull", "pullback", "focusSkull", "ccMoon", "endPull" }) do
            if B[n] then labelFits("Fight pull." .. n, B[n], nil, 6) end
        end
        for _, n in ipairs({ "pullTimer", "pullbackTimer" }) do
            local st = B[n]
            if st and st.minus and st.label and st.plus then
                local span = (st.minus.width or 0) + 2 + (st.label.width or 0)
                    + 2 + (st.plus.width or 0)
                local frame = st.width or 0
                if frame - span > 6 then
                    bad(string.format("Fight pull.%s: children span %dpx in a %dpx stepper (%dpx dead gap)",
                        n, span, frame, frame - span))
                end
            end
        end
    end

    -- ── CC menu ──────────────────────────────────────────────────────
    do
        local cache = {}
        local menu = TB.ccMenu
        if not menu then
            bad("CC menu: TB.ccMenu missing")
        else
            if TB.ToggleCcMenu and not menu:IsVisible() then TB.ToggleCcMenu() end
            -- Placement: the popup hangs off the CC Mark button. It overlays
            -- lower cards by design (FULLSCREEN_DIALOG), but must not jut
            -- past the main window's left/right edges.
            local mr = frameRect(menu, cache)
            local main = TB.frame and frameRect(TB.frame, cache)
            if main and menu:IsVisible()
                and (mr.left < main.left or mr.right > main.right) then
                bad(string.format("CC menu: %s juts past the main window sides %s",
                    fmt(mr), fmt(main)))
            end
            local rows = {}
            for id, row in pairs(menu.rows or {}) do
                local owner = row.ownerText and row.ownerText.parent
                if owner then table.insert(rows, { "row." .. id, owner }) end
            end
            noOverlaps("CC menu rows", rows, cache)
            if menu.clearAll then
                childrenInside("CC menu", menu, mr, { { "clearAll", menu.clearAll } }, cache, 3)
            end
            local strata = menu.strata or ""
            if strata ~= "FULLSCREEN_DIALOG" and strata ~= "TOOLTIP" then
                local lvl = menu.frameLevel or 0
                if lvl < 10 then
                    bad("CC menu: strata '" .. strata .. "' level " .. lvl
                        .. " renders under card buttons (need FULLSCREEN_DIALOG/TOOLTIP or level+10)")
                end
            end
            if not menu.closeButton and not menu.close then
                bad("CC menu: no close (X) button")
            end
            if menu:IsVisible() and TB.ToggleCcMenu then TB.ToggleCcMenu() end
        end
    end

    -- ── Camp tab ─────────────────────────────────────────────────────
    do
        local cache = {}
        local B = TB.actionButtons or {}
        local rest = B.rest and B.rest.parent
        local form = TB.formationPills and TB.formationPills.shield
            and TB.formationPills.shield.parent
        local quests = B.acceptQuest and B.acceptQuest.parent
        local cards = {}
        if rest then table.insert(cards, { "rest", rest }) end
        if form then table.insert(cards, { "formation", form }) end
        if quests then table.insert(cards, { "quests", quests }) end
        noOverlaps("Camp cards", cards, cache)
        if rest then
            local list = {}
            for _, n in ipairs({ "rest", "ready", "repair", "sell", "learn",
                "release", "rebuff", "resetTactics", "totem" }) do
                if B[n] then table.insert(list, { n, B[n] }) end
            end
            childrenInside("Camp rest", rest, frameRect(rest, cache), list, cache, 3)
            noOverlaps("Camp rest controls", list, cache)
        end
        if form then
            local cr = frameRect(form, cache)
            local list = {}
            local maxRight = 0
            for id, pill in pairs(TB.formationPills or {}) do
                table.insert(list, { id, pill })
                local r = frameRect(pill, cache)
                if r.right > maxRight then maxRight = r.right end
                labelFits("Camp formation." .. id, pill, nil, 6)
            end
            childrenInside("Camp formation", form, cr, list, cache, 3)
            noOverlaps("Camp formation pills", list, cache)
            if maxRight > 0 and cr.right - maxRight > 24 then
                bad(string.format("Camp formation: pills end at x=%d, %dpx dead gap to the card edge",
                    math.floor(maxRight + 0.5), math.floor(cr.right - maxRight + 0.5)))
            end
        end
        if quests then
            local list = {}
            for _, n in ipairs({ "acceptQuest", "shareQuest", "grind" }) do
                if B[n] then table.insert(list, { n, B[n] }) end
            end
            childrenInside("Camp quests", quests, frameRect(quests, cache), list, cache, 3)
            noOverlaps("Camp quest controls", list, cache)
            for _, entry in ipairs(list) do
                labelFits("Camp quests." .. entry[1], entry[2], nil, 6)
            end
        end
    end

    -- ── Party tab ────────────────────────────────────────────────────
    do
        local cache = {}
        local frame = TB.partyFrame
        if not frame or not frame.rows then
            bad("Party: rows missing")
        else
            TB.RefreshPartyView()
            local fr = frameRect(frame, cache)
            local rowItems = {}
            for i, row in ipairs(frame.rows) do
                table.insert(rowItems, { "row" .. i, row })
                local r = frameRect(row, cache)
                local items = {}
                if row.nameText then table.insert(items, { "name", row.nameText }) end
                if row.descText then table.insert(items, { "desc", row.descText }) end
                if row.playerLabel and row.playerLabel:IsVisible() then
                    table.insert(items, { "playerLabel", row.playerLabel })
                end
                for b, btn in ipairs(row.roleButtons or {}) do
                    if btn:IsVisible() then
                        table.insert(items, { "role" .. b, btn })
                        labelFits("Party row " .. i .. " role" .. b, btn, nil, 6)
                    end
                end
                -- desc/playerLabel/role buttons share the row: text columns
                -- must not cover buttons.
                local btns, texts = {}, {}
                for _, entry in ipairs(items) do
                    local f = entry[2]
                    if f.kind == "Button" then
                        table.insert(btns, entry)
                    else
                        local rr = frameRect(f, cache)
                        -- Only the filled text width counts, not the full
                        -- justified control width.
                        local w = math.min(rr.right - rr.left,
                            textWidth(f.text or f:GetText() or "", 6))
                        table.insert(texts, { entry[1],
                            { left = rr.left, top = rr.top,
                                right = rr.left + w, bottom = rr.top + textHeight(f) } })
                    end
                end
                for _, t in ipairs(texts) do
                    for _, entry in ipairs(btns) do
                        local br = frameRect(entry[2], cache)
                        if overlaps(t[2], br) then
                            bad(string.format("Party row %d: '%s' %s overlaps '%s' %s",
                                i, t[1], fmt(t[2]), entry[1], fmt(br)))
                        end
                    end
                end
                local btnItems = {}
                for _, entry in ipairs(btns) do table.insert(btnItems, entry) end
                noOverlaps("Party row " .. i .. " buttons", btnItems, cache)
            end
            noOverlaps("Party rows", rowItems, cache)
        end
    end

    -- ── Roster tab ───────────────────────────────────────────────────
    do
        local cache = {}
        local frame = TB.rosterFrame
        if not frame then
            bad("Roster: frame missing")
        else
            local fr = frameRect(frame, cache)
            local chips = {}
            for _, chip in ipairs(TB.classChips or {}) do
                table.insert(chips, { chip.text or "?", chip })
                labelFits("Roster chip." .. (chip.text or "?"), chip, nil, 6)
            end
            childrenInside("Roster chips", frame, fr, chips, cache, 0)
            noOverlaps("Roster chips", chips, cache)
            if TB.searchBox then
                local sr = frameRect(TB.searchBox, cache)
                for _, entry in ipairs(chips) do
                    if overlaps(frameRect(entry[2], cache), sr) then
                        bad("Roster: chip '" .. entry[1] .. "' overlaps the search box")
                    end
                end
            end
            for i, row in ipairs(TB.rows or {}) do
                local r = frameRect(row, cache)
                local cols = {}
                for _, key in ipairs({ "name", "class", "status", "location" }) do
                    if row[key] then table.insert(cols, { key, row[key] }) end
                end
                childrenInside("Roster row " .. i, row, r, cols, cache, 2)
                -- Columns chain left-to-right; filled text must not overrun
                -- the next column's start.
                local x = r.left
                for _, entry in ipairs(cols) do
                    local cr = frameRect(entry[2], cache)
                    if cr.left < x - 1 then
                        bad(string.format("Roster row %d: column '%s' starts at %d, before %d",
                            i, entry[1], math.floor(cr.left + 0.5), math.floor(x + 0.5)))
                    end
                    x = cr.left + (entry[2].width or 0)
                end
            end
            local bar = TB.rosterBar
            local scroll = TB.scroll
            if bar and scroll then
                local br = frameRect(bar, cache)
                local sr = frameRect(scroll, cache)
                local items = {}
                for name, btn in pairs(TB.lifecycleButtons or {}) do
                    table.insert(items, { name, btn })
                    labelFits("Roster bar." .. name, btn, nil, 6)
                end
                childrenInside("Roster bar", bar, br, items, cache, 4)
                noOverlaps("Roster lifecycle buttons", items, cache)
                for _, entry in ipairs(items) do
                    local r = frameRect(entry[2], cache)
                    if r.top < sr.bottom - 1 then
                        bad(string.format("Roster: lifecycle button '%s' %s overlaps the scroll frame (bottom %d)",
                            entry[1], fmt(r), math.floor(sr.bottom + 0.5)))
                    end
                end
            end
        end
    end

    -- ── Guild tab ────────────────────────────────────────────────────
    do
        local cache = {}
        local frame = TB.guildFrame
        if not frame or not frame.rows then
            bad("Guild: rows missing")
        else
            TB.RefreshGuildView()
            local worstRoles = {}
            for classId = 1, 11 do
                local roles = TB.Roles and TB.Roles.GetClassRoles
                    and TB.Roles.GetClassRoles(classId) or {}
                for _, role in ipairs(roles) do
                    table.insert(worstRoles, role.label)
                end
            end
            for i, row in ipairs(frame.rows) do
                local r = frameRect(row, cache)
                local cols = {}
                for _, key in ipairs({ "name", "lvlClass", "gearBadge", "status" }) do
                    if row[key] then table.insert(cols, { key, row[key] }) end
                end
                if row.roleBtn then table.insert(cols, { "roleBtn", row.roleBtn }) end
                if row.relBtn then table.insert(cols, { "relBtn", row.relBtn }) end
                childrenInside("Guild row " .. i, row, r, cols, cache, 2)
                noOverlaps("Guild row " .. i .. " columns", cols, cache)
                if row.roleBtn and i == 1 then
                    local saved = row.roleBtn.text
                    for _, label in ipairs(worstRoles) do
                        local shown = TB.Roles.ShortLabel and TB.Roles.ShortLabel(label) or label
                        labelFits("Guild roleBtn", row.roleBtn, shown, 6)
                    end
                    row.roleBtn.text = saved
                end
            end
            local bar = frame.guildBar
            local scroll = frame.scroll
            if bar and scroll then
                local br = frameRect(bar, cache)
                local sr = frameRect(scroll, cache)
                local items = {}
                for _, key in ipairs({ "inviteBtn", "summonBtn", "syncBtn", "fillBtn" }) do
                    if frame[key] then table.insert(items, { key, frame[key] }) end
                end
                childrenInside("Guild bar", bar, br, items, cache, 4)
                noOverlaps("Guild action buttons", items, cache)
                for _, entry in ipairs(items) do
                    local r = frameRect(entry[2], cache)
                    labelFits("Guild bar." .. entry[1], entry[2], nil, 6)
                    if r.top < sr.bottom - 1 then
                        bad(string.format("Guild: action button '%s' %s overlaps the scroll frame (bottom %d)",
                            entry[1], fmt(r), math.floor(sr.bottom + 0.5)))
                    end
                end
            end
        end
    end

    -- ── Raid tab ─────────────────────────────────────────────────────
    do
        local cache = {}
        local frame = TB.raidFrame
        if not frame then
            bad("Raid: frame missing")
        else
            local fr = frameRect(frame, cache)
            local encounters = frame.tankface and frame.tankface.parent
            local custom = frame.customToggle and frame.customToggle.parent
            local status = frame.statusButton and frame.statusButton.parent
            local cards = {}
            if encounters then table.insert(cards, { "encounters", encounters }) end
            if custom then table.insert(cards, { "custom", custom }) end
            if status then table.insert(cards, { "status", status }) end
            for _, entry in ipairs(cards) do
                local r = frameRect(entry[2], cache)
                if not inside(r, fr, 0) then
                    bad("Raid card '" .. entry[1] .. "' escapes the raid frame")
                end
            end
            noOverlaps("Raid cards", cards, cache)
            local function cardControls(card, names)
                if not card then return end
                local cr = frameRect(card, cache)
                local list = {}
                for _, n in ipairs(names) do
                    if frame[n] then table.insert(list, { n, frame[n] }) end
                end
                childrenInside("Raid", card, cr, list, cache, 3)
            end
            cardControls(encounters, { "tankface", "douse" })
            cardControls(custom, { "customToggle", "customCheck" })
            cardControls(status, { "statusButton" })
            -- The status list is plain text: it may sit below the button but
            -- must not cover it.
            if status and frame.statusButton and frame.statusList then
                local br = frameRect(frame.statusButton, cache)
                local lr = frameRect(frame.statusList, cache)
                if overlaps(br, lr) then
                    bad(string.format("Raid: status list %s overlaps the Check bots button %s",
                        fmt(lr), fmt(br)))
                end
            end
        end
    end

    -- ── Log tab ──────────────────────────────────────────────────────
    do
        local cache = {}
        if not TB.logScroll or not TB.logRows then
            bad("Log: scroll/rows missing")
        else
            TB.RefreshLogView()
            local sr = frameRect(TB.logScroll, cache)
            local rowItems = {}
            for i, row in ipairs(TB.logRows) do
                table.insert(rowItems, { "row" .. i, row })
                if row.msgText then
                    local mh = row.msgText.height
                    if (mh or 99) > (row.height or 18) then
                        bad(string.format("Log row %d: msgText height %s exceeds the %spx row; long lines wrap into the next row",
                            i, tostring(mh), tostring(row.height)))
                    end
                end
            end
            for _, entry in ipairs(rowItems) do
                local r = frameRect(entry[2], cache)
                if not inside(r, sr, 2) then
                    bad(string.format("Log: '%s' %s escapes the scroll frame %s",
                        entry[1], fmt(r), fmt(sr)))
                end
            end
            noOverlaps("Log rows", rowItems, cache)
        end
    end

    -- ── BotPanel (each tab + footer + item menu) ─────────────────────
    do
        local cache = {}
        if not TB.OpenBotPanel then
            bad("BotPanel: OpenBotPanel missing")
        else
            TB.OpenBotPanel("Alpha")
            local panel = TB.botPanel
            if not panel then
                bad("BotPanel: did not open")
            else
                local pr = frameRect(panel, cache)
                if panel.subText then
                    local worst = "Lvl 60 · Death Knight · Gear Locked · Following"
                    local need = textWidth(worst, 6)
                    local have = panel.subText.width or 0
                    if need > have then
                        bad(string.format("BotPanel: subtitle needs ~%dpx but has %dpx; wraps into the tab row",
                            need, have))
                    end
                end
                local tabs = {}
                for _, key in ipairs({ "tabGear", "tabBags", "tabBehavior", "tabSpells" }) do
                    if panel[key] then table.insert(tabs, { key, panel[key] }) end
                end
                childrenInside("BotPanel", panel, pr, tabs, cache, 2)
                noOverlaps("BotPanel tabs", tabs, cache)
                local footer = {}
                for _, key in ipairs({ "tradeButton", "refreshButton", "npcButton",
                    "vaultButton", "upkeepButton", "gearUpButton" }) do
                    local btn = panel[key]
                    if not btn then
                        bad("BotPanel: footer button " .. key .. " missing")
                    else
                        table.insert(footer, { key, btn })
                        labelFits("BotPanel " .. key, btn, nil, 6)
                    end
                end
                childrenInside("BotPanel", panel, pr, footer, cache, 2)
                noOverlaps("BotPanel footer", footer, cache)
                if panel.gearButtons then
                    local slots = {}
                    for i, b in ipairs(panel.gearButtons) do
                        table.insert(slots, { "slot" .. i, b })
                    end
                    childrenInside("BotPanel gear", panel, pr, slots, cache, 2)
                end
                if panel.bagButtons then
                    local slots = {}
                    for i, b in ipairs(panel.bagButtons) do
                        table.insert(slots, { "bag" .. i, b })
                    end
                    childrenInside("BotPanel bags", panel, pr, slots, cache, 2)
                end
                if panel.behaviorChips then
                    local chips = {}
                    for key, chip in pairs(panel.behaviorChips) do
                        if chip:IsVisible() then
                            table.insert(chips, { chip.text or key, chip })
                        end
                    end
                    childrenInside("BotPanel behavior", panel, pr, chips, cache, 2)
                    noOverlaps("BotPanel behavior chips", chips, cache)
                end
                if panel.spellRows then
                    local rows = {}
                    for i, row in ipairs(panel.spellRows) do
                        table.insert(rows, { "spell" .. i, row })
                    end
                    childrenInside("BotPanel spells", panel, pr, rows, cache, 2)
                    noOverlaps("BotPanel spell rows", rows, cache)
                end
            end
            TB.CloseBotPanel()
        end
    end

    -- ── Item menu ────────────────────────────────────────────────────
    do
        local cache = {}
        if TB.OpenBotPanel then
            TB.OpenBotPanel("Alpha")
            local panel = TB.botPanel
            local menu = panel and panel.itemMenu or TB.itemMenu
            if not menu or not menu.Open then
                bad("ItemMenu: menu missing")
            else
                local owner = (panel.bagButtons or {})[1] or panel
                -- Bottom-right slot: both flips must apply at once.
                local realRight, realBottom = menu.GetRight, menu.GetBottom
                menu.GetRight = function() return 2000 end
                menu.GetBottom = function() return -50 end
                menu:Open(owner, { equipped = false, equippable = true })
                local pts = menu.points or {}
                local pt = pts[table.getn(pts)]
                if pt then
                    if not (pt[1] == "BOTTOMRIGHT" and pt[3] == "TOPLEFT") then
                        bad(string.format("ItemMenu: bottom-right slot anchors %s->%s; need BOTTOMRIGHT->TOPLEFT (both flips)",
                            tostring(pt[1]), tostring(pt[3])))
                    end
                else
                    bad("ItemMenu: no anchor after Open")
                end
                menu.GetRight, menu.GetBottom = realRight, realBottom
                local mr = frameRect(menu, cache)
                local items = {}
                for _, key in ipairs({ "first", "second", "third", "fourth",
                    "fifth", "sixth", "seventh" }) do
                    if menu[key] and menu[key]:IsVisible() then
                        table.insert(items, { key, menu[key] })
                    end
                end
                childrenInside("ItemMenu", menu, mr, items, cache, 4)
                noOverlaps("ItemMenu rows", items, cache)
                if menu.seventh and not string.find(menu.seventh.text or "", "|cff", 1, true) then
                    bad("ItemMenu: 'Destroy' has no danger color; one misclick from 'Put to bank'")
                end
            end
            TB.CloseBotPanel()
        end
    end

    -- ── BotVault ─────────────────────────────────────────────────────
    do
        local cache = {}
        if not TB.OpenVault then
            bad("BotVault: OpenVault missing")
        else
            TB.OpenVault("Alpha")
            local vault = TB.botVault
            if not vault then
                bad("BotVault: did not open")
            else
                local vr = frameRect(vault, cache)
                local chrome = {}
                for _, key in ipairs({ "tabBank", "tabMail", "ask" }) do
                    if vault[key] then table.insert(chrome, { key, vault[key] }) end
                end
                childrenInside("BotVault", vault, vr, chrome, cache, 2)
                local rows = {}
                for i, row in ipairs(vault.rows or {}) do
                    table.insert(rows, { "row" .. i, row })
                end
                childrenInside("BotVault", vault, vr, rows, cache, 2)
                noOverlaps("BotVault rows", rows, cache)
                if not (vault.prevPage and vault.nextPage and vault.pageText) then
                    bad("BotVault: no < / page / > controls; items past row 8 are unreachable")
                else
                    childrenInside("BotVault paging", vault, vr,
                        { { "prev", vault.prevPage }, { "next", vault.nextPage } }, cache, 2)
                end
            end
            TB.CloseVault()
        end
    end

    -- ── BotNpc ───────────────────────────────────────────────────────
    do
        local cache = {}
        if not TB.OpenNpc then
            bad("BotNpc: OpenNpc missing")
        else
            TB.OpenNpc("Alpha")
            local npc = TB.botNpc
            if not npc then
                bad("BotNpc: did not open")
            else
                local nr = frameRect(npc, cache)
                local items = {}
                for _, key in ipairs({ "talk", "home", "trainer", "leader",
                    "ask", "prevPage", "nextPage" }) do
                    if npc[key] then
                        table.insert(items, { key, npc[key] })
                        if npc[key].kind == "Button" then
                            labelFits("BotNpc " .. key, npc[key], nil, 6)
                        end
                    elseif key == "prevPage" or key == "nextPage" then
                        bad("BotNpc: paging control " .. key .. " missing")
                    end
                end
                childrenInside("BotNpc", npc, nr, items, cache, 2)
                local rows = {}
                for i, row in ipairs(npc.rows or {}) do
                    table.insert(rows, { "row" .. i, row })
                end
                childrenInside("BotNpc flights", npc, nr, rows, cache, 2)
                noOverlaps("BotNpc flight rows", rows, cache)
            end
            TB.CloseNpc()
        end
    end

    -- ── Satellite exclusivity ────────────────────────────────────────
    do
        if TB.OpenVault and TB.OpenNpc and TB.OpenBotPanel then
            TB.OpenBotPanel("Alpha")
            TB.OpenVault("Alpha")
            TB.OpenNpc("Alpha")
            local vaultOpen = TB.botVault and TB.botVault:IsVisible()
            local npcOpen = TB.botNpc and TB.botNpc:IsVisible()
            if vaultOpen and npcOpen then
                bad("Satellites: BotVault and BotNpc open at the same time (same anchor, stacked)")
            end
            TB.OpenVault("Alpha")
            TB.CloseBotPanel()
            if (TB.botVault and TB.botVault:IsVisible())
                or (TB.botNpc and TB.botNpc:IsVisible()) then
                bad("Satellites: closing the BotPanel leaves a satellite window open")
            end
            if TB.CloseVault then TB.CloseVault() end
            if TB.CloseNpc then TB.CloseNpc() end
        end
    end

    -- ── MiniBar ──────────────────────────────────────────────────────
    do
        local cache = {}
        local bar = TB.miniBar
        if not bar then
            bad("MiniBar: bar missing")
        else
            local br = frameRect(bar, cache)
            local items = {}
            for intent, icon in pairs(bar.icons or {}) do
                table.insert(items, { intent, icon })
            end
            if bar.expand then table.insert(items, { "expand", bar.expand }) end
            childrenInside("MiniBar", bar, br, items, cache, 2)
            noOverlaps("MiniBar icons", items, cache)
        end
    end

    -- ── main window chrome ───────────────────────────────────────────
    do
        local cache = {}
        if TB.frame then
            local mr = frameRect(TB.frame, cache)
            if TB.versionLine and TB.miniButton then
                local vr = frameRect(TB.versionLine, cache)
                local br = frameRect(TB.miniButton, cache)
                if overlaps(vr, br) then
                    bad(string.format("Chrome: version line %s overlaps the Mini button %s",
                        fmt(vr), fmt(br)))
                end
            end
            if TB.versionTitle and TB.versionLine then
                local tr = frameRect(TB.versionTitle, cache)
                local vr = frameRect(TB.versionLine, cache)
                if overlaps(tr, vr) then
                    bad(string.format("Chrome: title %s overlaps the version line %s",
                        fmt(tr), fmt(vr)))
                end
            end
        end
    end

    for _, p in ipairs(problems) do
        print("GEOMETRY: " .. p)
    end
    assert(table.getn(problems) == 0,
        "geometry: " .. table.getn(problems) .. " layout problem(s), see GEOMETRY lines above")
    print("PASS: TBM window geometry checks")
end
