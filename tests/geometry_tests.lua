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
        -- Item/spell hyperlinks render as their display label only.
        s = string.gsub(s, "|H.-|h%[", "[")
        s = string.gsub(s, "%]|h", "]")
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

    -- UIPanelButtonTemplate keeps ~10 px total for the endcaps, and labels
    -- need ~4 px of breathing room on top: FRIZQT__.TTF is proportional, so a
    -- zero-margin label still touches the bevels in the client.
    local BUTTON_INSET = 10
    local BUTTON_SLACK = 4

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

    -- FontString height: explicit newlines and width-driven wrapping both
    -- add lines (12px each); a single-line bare string stays 12px.
    local function textHeight(f)
        if f.height then return f.height end
        local text = f.text or (f.GetText and f:GetText()) or ""
        local lines = 1
        for _ in string.gfind(text, "\n") do lines = lines + 1 end
        if (f.width or 0) > 0 and text ~= "" then
            local wrapped = math.ceil(textWidth(stripCodes(text), 6) / f.width)
            if wrapped > lines then lines = wrapped end
        end
        return lines * 12
    end

    -- Control box of a FontString: full declared width with template (or
    -- wrapped) height. Boxes on one line must not intersect even when the
    -- rendered glyphs are short: a later SetText can fill the whole box.
    local function boxRect(f, cache)
        local r = frameRect(f, cache)
        return { left = r.left, top = r.top,
            right = r.left + (f.width or 0), bottom = r.top + textHeight(f) }
    end

    -- Rendered rect of a FontString: full control width only when centered
    -- text fills it; left/right-justified or short text occupies its content.
    local function fsRect(f, cache)
        local r = frameRect(f, cache)
        local h = textHeight(f)
        local text = f.text or (f.GetText and f:GetText()) or ""
        local w = math.min(r.right - r.left, textWidth(stripCodes(text), 6))
        if w <= 0 then
            return { left = r.left, top = r.top, right = r.left, bottom = r.top }
        end
        return { left = r.left, top = r.top, right = r.left + w, bottom = r.top + h }
    end

    -- Button label fit: 1.12 centers the label across the full width, so a
    -- right-side lamp is cleared only when the half-text stays left of it
    -- (need T <= W - 34 for an 8px lamp, not T + lamp <= W). Icons beside the
    -- text still consume horizontal room; tall icons must also fit the 12px
    -- interior left by the 3px top/bottom bevels.
    local function labelFits(name, btn, sampleText, perChar)
        local w = btn.width or 0
        local h = btn.height or 0
        local text = sampleText or btn.text or btn:GetText() or ""
        local t = textWidth(text, perChar)
        local need = t + BUTTON_INSET + BUTTON_SLACK
        local icon = btn.icon
        if icon and icon.width and icon.visible ~= false and not (icon.hidden) then
            need = need + icon.width
        end
        if need > w then
            bad(string.format("%s: label '%s' needs ~%dpx in a %dpx button",
                name, stripCodes(text), need, w))
        end
        if btn.lamp and btn.lamp.width then
            local lampLeft = w - 9 - (btn.lamp.width or 8) -- RIGHT anchor, -9 nominal
            local pts = btn.lamp.points or {}
            if table.getn(pts) > 0 then
                local last = pts[table.getn(pts)]
                if last[1] == "RIGHT" then lampLeft = w + (last[4] or -9) - (btn.lamp.width or 8) end
            end
            -- Centered text spans [W/2 - T/2 + dx, W/2 + T/2 + dx]; the label
            -- FontString may carry a deliberate nudge (see switches card).
            local dx = 0
            local fs = btn.GetFontString and btn:GetFontString()
            if fs and fs.points and table.getn(fs.points) > 0 then
                local last = fs.points[table.getn(fs.points)]
                if last[1] == "CENTER" then dx = last[4] or 0 end
            end
            if w / 2 + t / 2 + dx > lampLeft then
                bad(string.format("%s: centered label '%s' (~%dpx) touches the lamp at x=%d in a %dpx button",
                    name, stripCodes(text), t, lampLeft, w))
            end
        end
        -- 16px icons are standard on 20px+ buttons; only short (stepper-row)
        -- buttons leave too little interior for a full-size icon (see endPull).
        if icon and icon.height and icon.visible ~= false and not (icon.hidden) then
            if h > 0 and h < 20 and icon.height > h - 6 then
                bad(string.format("%s: %dpx icon bleeds over the %dpx button bevels",
                    name, icon.height, h))
            end
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
            -- The hint sits under the title; the X must clear it.
            local xBtn = menu.closeButton or menu.close
            if not menu.hint then
                bad("CC menu: hint text missing")
            elseif not xBtn then
                bad("CC menu: close button missing")
            else
                childrenInside("CC menu", menu, mr,
                    { { "hint", menu.hint }, { "close", xBtn } }, cache, 0)
                local hr, xr = boxRect(menu.hint, cache), frameRect(xBtn, cache)
                if overlaps(hr, xr) then
                    bad(string.format("CC menu: hint %s overlaps the close button %s",
                        fmt(hr), fmt(xr)))
                end
            end
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
                "release", "rebuff", "resetTactics", "totem", "downtime" }) do
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
            -- The run button only shows while the server advertises
            -- dungeon-run: enable it so the subtitle-vs-button check runs.
            TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior,claimed-roster,dungeon-run")
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
            -- Dungeon tab (P11): with every tab shown (dungeon-run + a raid
            -- would make 8) the Log tab still ends inside the main window.
            if TB.tabDungeon then
                TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior,claimed-roster,dungeon-run")
                local lr = frameRect(TB.tabLog, cache)
                local mr = frameRect(TB.frame, cache)
                if lr.right > mr.right then
                    bad(string.format("Tabs: Log tab %s escapes the main window %s", fmt(lr), fmt(mr)))
                end
                TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior,claimed-roster")
            else
                bad("Tabs: Dungeon tab missing")
            end
            -- Loot tab: with loot-log too (9 tabs) the Log tab still fits.
            if TB.tabLoot then
                TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior,claimed-roster,dungeon-run,loot-log")
                local lr = frameRect(TB.tabLog, cache)
                local mr = frameRect(TB.frame, cache)
                if lr.right > mr.right then
                    bad(string.format("Tabs: with Loot, Log tab %s escapes the main window %s", fmt(lr), fmt(mr)))
                end
                TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior,claimed-roster")
            else
                bad("Tabs: Loot tab missing")
            end
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
                    -- Empty state: the hint must sit inside the list area,
                    -- clear of the Ask/paging row it explains.
                    if panel.spellEmpty and panel.spellAsk and panel.spellPrev
                        and panel.spellPageText and panel.spellNext then
                        local bottom = { { "ask", panel.spellAsk },
                            { "prev", panel.spellPrev },
                            { "page", panel.spellPageText },
                            { "next", panel.spellNext } }
                        childrenInside("BotPanel spells", panel, pr, bottom, cache, 2)
                        local er = boxRect(panel.spellEmpty, cache)
                        for _, entry in ipairs(bottom) do
                            local r = frameRect(entry[2], cache)
                            if overlaps(er, r) then
                                bad(string.format("BotPanel: empty-state text %s overlaps '%s' %s",
                                    fmt(er), entry[1], fmt(r)))
                            end
                        end
                        -- Hidden spell rows paint nothing; only visible rows collide.
                        for _, entry in ipairs(rows) do
                            if entry[2]:IsVisible() then
                                local r = frameRect(entry[2], cache)
                                if overlaps(er, r) then
                                    bad(string.format("BotPanel: empty-state text %s overlaps '%s' %s",
                                        fmt(er), entry[1], fmt(r)))
                                end
                            end
                        end
                    end
                    -- Filled state: two pages of real spell names. Visible rows
                    -- must fit their text and clear the Ask/paging row.
                    TB.SetSpellPending("Alpha", true)
                    TB.ConsumeSpellReply("Alpha", "=== Spells ===")
                    local spellNames = { "Fireball", "Frostbolt",
                        "Polymorph", "Arcane Intellect", "Conjure Water",
                        "Blizzard", "Frost Nova", "Counterspell", "Blink",
                        "Evocation", "Mana Shield", "Dampen Magic",
                        "Greater Heal", "Power Word: Shield" }
                    for i, name in ipairs(spellNames) do
                        TB.ConsumeSpellReply("Alpha",
                            "|cffffffff|Hspell:" .. (100 + i) .. "|h[" .. name .. "]|h|r")
                    end
                    do
                        local filled = {}
                        for i, row in ipairs(panel.spellRows or {}) do
                            if row:IsVisible() then
                                table.insert(filled, { "spell" .. i, row })
                                labelFits("BotPanel spell." .. i, row, nil, 6)
                            end
                        end
                        noOverlaps("BotPanel filled spells", filled, cache)
                        if panel.spellAsk and table.getn(filled) > 0 then
                            local ar = frameRect(panel.spellAsk, cache)
                            for _, entry in ipairs(filled) do
                                local r = frameRect(entry[2], cache)
                                if overlaps(r, ar) then
                                    bad(string.format("BotPanel: filled '%s' %s overlaps the ask row %s",
                                        entry[1], fmt(r), fmt(ar)))
                                end
                            end
                        end
                        if panel.spellEmpty and panel.spellEmpty:IsVisible() then
                            bad("BotPanel: empty-state text stays visible with a filled spellbook")
                        end
                        local pages = panel.spellPageText and panel.spellPageText:GetText() or ""
                        if pages ~= "1 / 2" then
                            bad("BotPanel: 14 spells must page as '1 / 2', got '" .. pages .. "'")
                        end
                    end
                    TB.SetSpellPending("Alpha", false)
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
                -- Summary (left) and hint (right) share the y=-62 line.
                if not (vault.summary and vault.hint) then
                    bad("BotVault: summary/hint texts missing")
                else
                    childrenInside("BotVault", vault, vr,
                        { { "summary", vault.summary }, { "hint", vault.hint } }, cache, 2)
                    local sr, hr = boxRect(vault.summary, cache), boxRect(vault.hint, cache)
                    if overlaps(sr, hr) then
                        bad(string.format("BotVault: summary %s overlaps hint %s",
                            fmt(sr), fmt(hr)))
                    end
                end
                local rows = {}
                for i, row in ipairs(vault.rows or {}) do
                    table.insert(rows, { "row" .. i, row })
                end
                childrenInside("BotVault", vault, vr, rows, cache, 2)
                noOverlaps("BotVault rows", rows, cache)
                -- Filled state: bank lines with counts and a long name, then
                -- the mailbox view with a long sender/subject line. Row text
                -- must fit the button; rows must not cover the paging row.
                TB.SetVaultPending("Alpha", true)
                TB.ConsumeVaultReply("Alpha", "=== Bank ===")
                TB.ConsumeVaultReply("Alpha",
                    "|cffffffff|Hitem:1234:0:0:0|h[Linen Cloth]|h|rx3")
                TB.ConsumeVaultReply("Alpha",
                    "|cffffffff|Hitem:5678:0:0:0|h[Greater Arcane Protection Potion of the Whale]|h|r")
                do
                    local filled = {}
                    for i, row in ipairs(vault.rows or {}) do
                        if row:IsVisible() then
                            table.insert(filled, { "row" .. i, row })
                            labelFits("BotVault filled." .. i, row, nil, 6)
                        end
                    end
                    noOverlaps("BotVault filled rows", filled, cache)
                    if vault.ask and table.getn(filled) > 0 then
                        for _, entry in ipairs(filled) do
                            local r = frameRect(entry[2], cache)
                            local ar = frameRect(vault.ask, cache)
                            if overlaps(r, ar) then
                                bad(string.format("BotVault: filled '%s' %s overlaps the ask row %s",
                                    entry[1], fmt(r), fmt(ar)))
                            end
                        end
                    end
                end
                TB.OpenVault("Alpha", "mail")
                TB.SetVaultPending("Alpha", true)
                TB.ConsumeVaultReply("Alpha", "=== Mailbox ===")
                TB.ConsumeVaultReply("Alpha",
                    "#1 |cffffffff|Hitem:1234:0:0:0|h[Linen Cloth]|h|r from Sendername, |cff00ff0030 day(s)")
                do
                    local filled = {}
                    for i, row in ipairs(vault.rows or {}) do
                        if row:IsVisible() then
                            table.insert(filled, { "row" .. i, row })
                            labelFits("BotVault mail." .. i, row, nil, 6)
                        end
                    end
                    noOverlaps("BotVault mail rows", filled, cache)
                end
                TB.SetVaultPending("Alpha", false)
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
                -- Filled state: two pages of real flight legs plus the empty
                -- hint hidden. Long destination names must fit their button.
                TB.SetNpcPending("Alpha", true)
                TB.ConsumeTaxiReply("Alpha", "=== Taxi ===")
                local legs = { "Stormwind, Elwynn", "Ironforge, Dun Morogh",
                    "Menethil Harbor, Wetlands", "Thelsamar, Loch Modan",
                    "Refuge Pointe, Arathi", "Hammerfall, Arathi Highlands",
                    "Booty Bay, Stranglethorn Vale" }
                for i, name in ipairs(legs) do
                    TB.ConsumeTaxiReply("Alpha", i .. ": " .. name)
                end
                do
                    local filled = {}
                    for i, row in ipairs(npc.rows or {}) do
                        if row:IsVisible() then
                            table.insert(filled, { "row" .. i, row })
                            labelFits("BotNpc flight." .. i, row, nil, 6)
                        end
                    end
                    noOverlaps("BotNpc filled flights", filled, cache)
                    if npc.ask and table.getn(filled) > 0 then
                        local ar = frameRect(npc.ask, cache)
                        for _, entry in ipairs(filled) do
                            local r = frameRect(entry[2], cache)
                            if overlaps(r, ar) then
                                bad(string.format("BotNpc: filled '%s' %s overlaps the ask row %s",
                                    entry[1], fmt(r), fmt(ar)))
                            end
                        end
                    end
                    if npc.flightEmpty and npc.flightEmpty:IsVisible() then
                        bad("BotNpc: empty-state text stays visible with filled flights")
                    end
                    local pages = npc.pageText and npc.pageText:GetText() or ""
                    if pages ~= "1 / 2" then
                        bad("BotNpc: 7 flights must page as '1 / 2', got '" .. pages .. "'")
                    end
                end
                TB.SetNpcPending("Alpha", false)
            end
            TB.CloseNpc()
        end
    end

    -- ── Satellite docking on both sides of the main window ─────────────
    -- The panel flips left of the main frame near the right screen edge;
    -- the vault/NPC must follow the panel, never land on the main frame.
    do
        if TB.OpenBotPanel and TB.OpenVault and TB.OpenNpc and TB.frame then
            local savedX = TB.frame.x
            for _, edge in ipairs({ "right", "left" }) do
                -- Park the main frame: near the right edge (panel flips
                -- left) or near the left edge (panel docks right).
                TB.frame.x = (edge == "right") and 700 or 60
                TB.OpenBotPanel("Alpha")
                local panel = TB.botPanel
                if not (panel and panel:IsVisible()) then
                    bad("Satellites (" .. edge .. "): panel did not open")
                else
                    local cache = {}
                    local fr = frameRect(TB.frame, cache)
                    local pr = frameRect(panel, cache)
                    for _, open in ipairs({ { "vault", TB.OpenVault },
                        { "npc", TB.OpenNpc } }) do
                        open[2]("Alpha")
                        local sat = (open[1] == "vault") and TB.botVault or TB.botNpc
                        if not (sat and sat:IsVisible()) then
                            bad("Satellites (" .. edge .. "): " .. open[1] .. " did not open")
                        else
                            local sr = frameRect(sat, cache)
                            if overlaps(sr, fr) then
                                bad(string.format("Satellites (%s): %s %s lands on the main frame %s",
                                    edge, open[1], fmt(sr), fmt(fr)))
                            end
                            if overlaps(sr, pr) then
                                bad(string.format("Satellites (%s): %s %s covers the panel %s",
                                    edge, open[1], fmt(sr), fmt(fr)))
                            end
                            -- Anchor intent: beside the panel, or beside main
                            -- only when the panel hugs the left screen edge.
                            local pt = sat.point or {}
                            local rel = pt[2]
                            if rel == TB.frame then
                                local panelLeft = panel.GetLeft and panel:GetLeft()
                                if not (panelLeft and panelLeft - 304 < 0) then
                                    bad(string.format("Satellites (%s): %s docks to main while the panel has room",
                                        edge, open[1]))
                                end
                            elseif rel ~= panel then
                                bad(string.format("Satellites (%s): %s anchors to neither panel nor main",
                                    edge, open[1]))
                            end
                        end
                        if TB.CloseVault then TB.CloseVault() end
                        if TB.CloseNpc then TB.CloseNpc() end
                    end
                    TB.CloseBotPanel()
                end
            end
            TB.frame.x = savedX
        end
    end

    -- ── Per-bot header class colors (roster and claimed) ───────────────
    do
        -- Alpha is a roster warrior (class 1); Goldie is claimed-only (class 1).
        for _, case in ipairs({ { "Alpha", "roster" }, { "Goldie", "claimed" } }) do
            local name, kind = case[1], case[2]
            local entry = (TB.GetRosterEntry and TB.GetRosterEntry(name))
                or (TB.GetClaimedEntry and TB.GetClaimedEntry(name))
            if not (entry and entry.classId) then
                bad("Headers: no " .. kind .. " entry for " .. name)
            else
                local col = TB.C.CLASS_COLORS[entry.classId]
                TB.OpenBotPanel(name)
                TB.OpenVault(name)
                TB.OpenNpc(name)
                for _, win in ipairs({ { "panel", TB.botPanel and TB.botPanel.nameText },
                    { "vault", TB.botVault and TB.botVault.nameText },
                    { "npc", TB.botNpc and TB.botNpc.nameText } }) do
                    local fs = win[2]
                    if not fs then
                        bad("Headers (" .. name .. "): " .. win[1] .. " has no name text")
                    else
                        local tc = fs.textColor
                        if not (tc and tc[1] == col[1] and tc[2] == col[2] and tc[3] == col[3]) then
                            bad(string.format("Headers (%s): %s name not class-colored (%s)",
                                name, win[1], tostring(fs:GetText())))
                        end
                    end
                end
                TB.CloseBotPanel()
            end
        end
    end

    -- ── Item menu at the screen edges ──────────────────────────────────
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
                -- Each corner: the menu must flip to stay on screen and keep
                -- every visible row inside its own frame.
                local corners = {
                    { right = 2000, bottom = -50, my = "BOTTOMRIGHT", rel = "TOPLEFT" },
                    { right = 2000, bottom = 900, my = "TOPRIGHT", rel = "BOTTOMLEFT" },
                    { right = 60, bottom = -50, my = "BOTTOMLEFT", rel = "TOPRIGHT" },
                    { right = 60, bottom = 900, my = "TOPLEFT", rel = "BOTTOMRIGHT" },
                }
                local realRight, realBottom = menu.GetRight, menu.GetBottom
                for i, c in ipairs(corners) do
                    menu.GetRight = function() return c.right end
                    menu.GetBottom = function() return c.bottom end
                    menu:Open(owner, { equipped = false, equippable = true })
                    local pts = menu.points or {}
                    local pt = pts[table.getn(pts)]
                    if not pt then
                        bad("ItemMenu corner " .. i .. ": no anchor after Open")
                    else
                        if not (pt[1] == c.my and pt[3] == c.rel) then
                            bad(string.format("ItemMenu corner %d: anchors %s->%s; need %s->%s",
                                i, tostring(pt[1]), tostring(pt[3]), c.my, c.rel))
                        end
                        local mr = frameRect(menu, cache)
                        local items = {}
                        for _, key in ipairs({ "first", "second", "third", "fourth",
                            "fifth", "sixth", "seventh" }) do
                            if menu[key] and menu[key]:IsVisible() then
                                table.insert(items, { key, menu[key] })
                            end
                        end
                        childrenInside("ItemMenu corner " .. i, menu, mr, items, cache, 4)
                        noOverlaps("ItemMenu corner " .. i .. " rows", items, cache)
                    end
                end
                menu.GetRight, menu.GetBottom = realRight, realBottom
            end
            TB.CloseBotPanel()
        end
    end

    -- ── Drag-stop audit: every movable frame re-anchors safely ─────────
    -- 1.12 detaches the anchor on StopMovingOrSizing (fatal GetPoint crash);
    -- every OnDragStop that stops a move must ClearAllPoints and pin back to
    -- UIParent/BOTTOMLEFT from GetLeft/GetTop (main header, MiniBar saver,
    -- vault, npc, run). The minimap drags via center math and never stops a move.
    do
        local frames = {
            { "main", TB.frame, TB.dragHeader },
            { "minibar", TB.miniBar, TB.miniBar },
            { "vault", TB.botVault, TB.botVault },
            { "npc", TB.botNpc, TB.botNpc },
            { "run", TB.runWindow, TB.runWindow },
        }
        this = nil
        for _, entry in ipairs(frames) do
            local name, frame, drag = entry[1], entry[2], entry[3]
            if frame and drag and drag.scripts
                and drag.scripts.OnDragStart and drag.scripts.OnDragStop then
                if frame.movable ~= true then
                    bad("Drag " .. name .. ": movable frame lost SetMovable(true)")
                end
                if frame.clamped ~= true then
                    bad("Drag " .. name .. ": movable frame must SetClampedToScreen(true)")
                end
                local stopped = false
                local realStop = frame.StopMovingOrSizing
                frame.StopMovingOrSizing = function(self) stopped = true end
                this = drag
                drag.scripts.OnDragStart()
                this = drag
                drag.scripts.OnDragStop()
                frame.StopMovingOrSizing = realStop
                if not stopped then
                    bad("Drag " .. name .. ": OnDragStop never stops the move")
                else
                    local pts = frame.points or {}
                    local pt = pts[table.getn(pts)]
                    if not (pt and pt[1] == "TOPLEFT" and pt[2] == UIParent
                        and pt[3] == "BOTTOMLEFT") then
                        bad("Drag " .. name .. ": OnDragStop must re-anchor TOPLEFT->UIParent/BOTTOMLEFT")
                    end
                end
            end
        end
        this = nil
        if TB.CloseVault then TB.CloseVault() end
        if TB.CloseNpc then TB.CloseNpc() end
        if TB.CloseRunWindow then TB.CloseRunWindow() end
    end

    -- ── Dungeon run window (P11) ───────────────────────────────────────
    do
        local cache = {}
        if not TB.OpenRunWindow then
            bad("RunWindow: OpenRunWindow missing")
        else
            TB.OnSystemMessage("TBM:CAPS|dungeon-run")
            TB.OpenRunWindow()
            local win = TB.runWindow
            if not win then
                bad("RunWindow: did not open")
            else
                -- The open search list is the tallest layout: check that one.
                TB.SetRunPlanPicker(true)
                local wr = frameRect(win, cache)
                local items = {}
                for _, key in ipairs({ "modeBot", "modeYou", "planToggle", "bind", "bindRaid", "unbind", "enter", "cmdStatus",
                    "plans", "planPrev", "planNext", "start", "pause",
                    "resume", "skip", "stop", "stopBox" }) do
                    if win[key] then
                        table.insert(items, { key, win[key] })
                        if win[key].kind == "Button" then
                            labelFits("RunWindow " .. key, win[key], nil, 6)
                        end
                    elseif key ~= "pause" and key ~= "resume" then
                        bad("RunWindow: control " .. key .. " missing")
                    end
                end
                -- Pause and Resume share one slot: exactly one shows.
                local pauseShown = win.pause and win.pause:IsVisible()
                local resumeShown = win.resume and win.resume:IsVisible()
                if pauseShown and resumeShown then
                    bad("RunWindow: Pause and Resume show at the same time")
                end
                childrenInside("RunWindow", win, wr, items, cache, 2)
                -- Empty plan list: the hint shows, rows hide, the pager
                -- still fits; filled: two pages of plans incl. a long
                -- name, rows fit their buttons and clear the pager row.
                if win.planEmpty and not win.planEmpty:IsVisible() then
                    bad("RunWindow: empty-state text must show with no plans")
                end
                TB.OnSystemMessage("Dungeon plans: uldaman (map 70, 41 steps), ragefire_chasm (map 389, 120 steps, 3 not supported yet), deadmines (map 36, 90 steps), wailing_caverns (map 43, 100 steps), scarlet_library (map 189, 88 steps), lower_blackrock_spire (map 229, 491 steps)")
                do
                    local filled = {}
                    for i, row in ipairs(win.planRows or {}) do
                        if row:IsVisible() then
                            table.insert(filled, { "row" .. i, row })
                            labelFits("RunWindow plan." .. i, row, nil, 6)
                        end
                    end
                    noOverlaps("RunWindow filled plans", filled, cache)
                    if win.plans and table.getn(filled) > 0 then
                        local ar = frameRect(win.plans, cache)
                        for _, entry in ipairs(filled) do
                            local r = frameRect(entry[2], cache)
                            if overlaps(r, ar) then
                                bad(string.format("RunWindow: filled '%s' %s overlaps the pager row %s",
                                    entry[1], fmt(r), fmt(ar)))
                            end
                        end
                    end
                    if win.planEmpty and win.planEmpty:IsVisible() then
                        bad("RunWindow: empty-state text stays visible with filled plans")
                    end
                    local pages = win.planPageText and win.planPageText:GetText() or ""
                    if pages ~= "1 / 2" then
                        bad("RunWindow: 6 plans must page as '1 / 2', got '" .. pages .. "'")
                    end
                end
                -- Status shown: a running line paints state, step, bar and
                -- the leg/phase/note lines, all inside the window.
                -- An 80-char note wraps to 2 lines: measure the wrapped box.
                if win.runNote then win.runNote:SetText(string.rep("n", 80)) end
                -- Wrapped hints: bindHint/planHint/stopHint and the pause
                -- warning all render (stopHint via the new window field).
                TB.OnSystemMessage("TBM:RUN|uldaman|running|7/41|baelog|pull|pull|pulling 4851|left 2")
                TB.OnSystemMessage("TBM:RAID_LAYOUT|25|Alpha,Beta,Gamma|Pri1 -> Alpha,Pri2 -> Beta|Druid1,Druid2|1=Alpha,Pri1;2=Beta,Druid1")
                local status = {}
                for _, key in ipairs({ "runBar", "runLeg", "runPhase",
                    "runNote", "runStop", "runStep", "runState", "bindHint", "planHint", "modeHint",
                    "feedback", "warn", "layout" }) do
                    if win[key] then table.insert(status, { key, win[key] }) end
                end
                childrenInside("RunWindow status", win, wr, status, cache, 2)
                -- InputBoxTemplate's left border reaches 5px past the box:
                -- stopBox must clear Stop even with the border.
                do
                    local sb = frameRect(win.stopBox, cache)
                    sb = { left = sb.left - 5, top = sb.top,
                        right = sb.right, bottom = sb.bottom }
                    local st = frameRect(win.stop, cache)
                    if overlaps(sb, st) then
                        bad(string.format("RunWindow: 'stopBox' %s (with border) touches 'stop' %s",
                            fmt(sb), fmt(st)))
                    end
                end
                -- runState (lamp-relative) must clear runStep: compare boxes,
                -- not glyphs, so a later SetText can fill the control.
                do
                    local rs = boxRect(win.runState, cache)
                    local rp = boxRect(win.runStep, cache)
                    if overlaps(rs, rp) then
                        bad(string.format("RunWindow status: 'runState' %s overlaps 'runStep' %s",
                            fmt(rs), fmt(rp)))
                    end
                end
                local boxes = {}
                for _, key in ipairs({ "layout", "runLeg", "runPhase", "runNote", "runStop" }) do
                    if win[key] and win[key].kind == "FontString" then
                        table.insert(boxes, { key, boxRect(win[key], cache) })
                    end
                end
                for i = 1, table.getn(boxes) do
                    for j = i + 1, table.getn(boxes) do
                        if overlaps(boxes[i][2], boxes[j][2]) then
                            bad(string.format("RunWindow status: '%s' %s overlaps '%s' %s",
                                boxes[i][1], fmt(boxes[i][2]),
                                boxes[j][1], fmt(boxes[j][2])))
                        end
                    end
                end
                -- The bind hint (right column) must clear the layout line and
                -- the plan header below it, even wrapped; the layout line must
                -- clear the plan header too.
                for _, pair in ipairs({ { "bindHint", "layout" }, { "layout", "planToggle" } }) do
                    local a, b = win[pair[1]], win[pair[2]]
                    if a and b and a.kind == "FontString" and b.kind == "FontString" then
                        local ra, rb = boxRect(a, cache), boxRect(b, cache)
                        if overlaps(ra, rb) then
                            bad(string.format("RunWindow: '%s' %s overlaps '%s' %s",
                                pair[1], fmt(ra), pair[2], fmt(rb)))
                        end
                    end
                end
                -- the window never covers main or the panel.
                if TB.OpenBotPanel and TB.frame then
                    local savedX = TB.frame.x
                    for _, edge in ipairs({ "right", "left" }) do
                        -- Fresh rects: OpenBotPanel/OpenRunWindow re-anchor
                        -- the frames, and frameRect caches by frame.
                        local edgeCache = {}
                        TB.frame.x = (edge == "right") and 700 or 60
                        TB.OpenBotPanel("Alpha")
                        TB.OpenRunWindow()
                        local rw = frameRect(win, edgeCache)
                        local main = frameRect(TB.frame, edgeCache)
                        if overlaps(rw, main) then
                            bad(string.format("RunWindow (%s): %s covers the main window %s",
                                edge, fmt(rw), fmt(main)))
                        end
                        local panel = TB.botPanel
                        if panel and panel:IsVisible() then
                            local pr = frameRect(panel, edgeCache)
                            if overlaps(rw, pr) then
                                bad(string.format("RunWindow (%s): %s covers the panel %s",
                                    edge, fmt(rw), fmt(pr)))
                            end
                        end
                        TB.CloseBotPanel()
                    end
                    TB.frame.x = savedX
                    TB.OpenRunWindow()
                end
            end
            TB.CloseRunWindow()
            TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior")
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
            if TB.OpenRunWindow then
                TB.OnSystemMessage("TBM:CAPS|dungeon-run")
                TB.OpenRunWindow()
                local runOpen = TB.runWindow and TB.runWindow:IsVisible()
                npcOpen = TB.botNpc and TB.botNpc:IsVisible()
                if runOpen and npcOpen then
                    bad("Satellites: RunWindow and BotNpc open at the same time (same anchor, stacked)")
                end
                TB.OpenVault("Alpha")
                runOpen = TB.runWindow and TB.runWindow:IsVisible()
                vaultOpen = TB.botVault and TB.botVault:IsVisible()
                if runOpen and vaultOpen then
                    bad("Satellites: RunWindow and BotVault open at the same time (same anchor, stacked)")
                end
                TB.OpenRunWindow()
                TB.CloseBotPanel()
                if TB.runWindow and TB.runWindow:IsVisible() then
                    bad("Satellites: closing the BotPanel leaves the run window open")
                end
                TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior")
            end
            TB.OpenVault("Alpha")
            TB.CloseBotPanel()
            if (TB.botVault and TB.botVault:IsVisible())
                or (TB.botNpc and TB.botNpc:IsVisible())
                or (TB.runWindow and TB.runWindow:IsVisible()) then
                bad("Satellites: closing the BotPanel leaves a satellite window open")
            end
            if TB.CloseVault then TB.CloseVault() end
            if TB.CloseNpc then TB.CloseNpc() end
            if TB.CloseRunWindow then TB.CloseRunWindow() end
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
