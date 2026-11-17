-- The remastered scoreboard panel.
local SBR = ScoreboardRemastered
local UI = {
    rows = {},
    headers = {},
    columns = {},
    sort = { key = "s:SCORE", desc = true },
    viewIndex = nil, -- nil = live, number = history index
    pinned = false,  -- opened manually, stays open when the native scoreboard closes
}
SBR.Window = UI

local WM = WINDOW_MANAGER
local PAD = 12
local TOP_H = 78
local HEADER_H = 24
local ROW_H = 22
local FOOTER_H = 42
local STRIP_W = 4
local FONT_ROW = "ZoFontGameSmall"
local FONT_HEAD = "ZoFontGameBold"

local nameCounter = 0
local function NextName(kind)
    nameCounter = nameCounter + 1
    return string.format("SBR_%s%d", kind, nameCounter)
end

local function CreateLabel(parent, font, align)
    local l = WM:CreateControl(NextName("Label"), parent, CT_LABEL)
    l:SetFont(font or FONT_ROW)
    l:SetHorizontalAlignment(align or TEXT_ALIGN_LEFT)
    l:SetVerticalAlignment(TEXT_ALIGN_CENTER)
    l:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
    l:SetColor(1, 1, 1, 1)
    return l
end

local function CreateTexture(parent, r, g, b, a)
    local t = WM:CreateControl(NextName("Tex"), parent, CT_TEXTURE)
    t:SetColor(r, g, b, a)
    return t
end

local function CreateButton(parent, text, width, onClick)
    local b = WM:CreateControlFromVirtual(NextName("Button"), parent, "ZO_DefaultButton")
    b:SetText(text)
    b:SetDimensions(width, 28)
    b:SetHandler("OnClicked", onClick)
    return b
end

local function ShowTooltip(control, text)
    InitializeTooltip(InformationTooltip, control, BOTTOM, 0, -4)
    SetTooltipText(InformationTooltip, text)
end

local function HideTooltip()
    ClearTooltip(InformationTooltip)
end

---------------------------------------------------------------------------
-- Columns
---------------------------------------------------------------------------
local FIGHT_COLUMNS = {
    { key = "dps", label = "DPS", tip = "Damage per second in combat" },
    { key = "hps", label = "HPS", tip = "Healing per second in combat" },
    { key = "damageTaken", label = "Taken", tip = "Damage taken" },
    { key = "healingTaken", label = "Healed", tip = "Healing received" },
    { key = "killingBlows", label = "KBs", tip = "Killing blows" },
    { key = "interrupts", label = "Intr", tip = "Interrupts" },
    { key = "ccApplied", label = "CC", tip = "Crowd control applied" },
    { key = "damageShielded", label = "Shield", tip = "Damage absorbed by shields" },
    { key = "critRate", label = "Crit%", tip = "Critical hit rate", fmt = function(v) return string.format("%.0f%%", v) end },
    { key = "maxHit", label = "Max hit", tip = "Biggest single hit" },
}

local VS_COLUMNS = {
    { key = "damageFromYou", label = "You>", tip = "Damage you dealt to this player" },
    { key = "damageToYou", label = ">You", tip = "Damage this player dealt to you" },
    { key = "healedByYou", label = "You heal", tip = "Healing you gave this player" },
    { key = "killedByYou", label = "Killed", tip = "Times you killed this player (kill feed)" },
    { key = "killedYou", label = "By", tip = "Times this player killed you (kill feed)" },
}

local function AnyValue(players, getter)
    for _, p in pairs(players) do
        local v = getter(p)
        if v ~= nil and v ~= 0 then return true end
    end
    return false
end

function UI:BuildColumns(match)
    local cols = {}
    local players = match.players or {}
    local hideEmpty = SBR.sv.hideEmptyColumns

    cols[#cols + 1] = {
        key = "class", label = "", width = 26, align = TEXT_ALIGN_CENTER,
        text = function(p) return p.classIcon and zo_iconFormat(p.classIcon, 20, 20) or "" end,
        sortValue = function(p) return p.className or "" end,
    }
    cols[#cols + 1] = {
        key = "name", label = "Player", width = 200, align = TEXT_ALIGN_LEFT,
        text = function(p)
            local name = p.characterName ~= "" and p.characterName or p.displayName or "?"
            if p.left then name = "|c888888" .. name .. " (left)|r" end
            return name
        end,
        sortValue = function(p) return (p.characterName or ""):lower() end,
    }

    for _, st in ipairs(SBR.Battleground.scoreTypes or {}) do
        local key = st.key
        local get = function(p) return p.scores and p.scores[key] end
        if (match.columnsSeen and match.columnsSeen[key]) and (not hideEmpty or AnyValue(players, get)) then
            cols[#cols + 1] = {
                key = "s:" .. key, label = st.label, width = math.max(52, #st.label * 8), numeric = true,
                value = get, tip = st.label .. " (native scoreboard)",
            }
        end
    end

    cols[#cols + 1] = {
        key = "medals", label = "Medals", width = 56, numeric = true,
        value = function(p) return p.medalCount end, tip = "Medals earned (hover a row for the list)",
    }

    if SBR.sv.showFightColumns then
        for _, fc in ipairs(FIGHT_COLUMNS) do
            local key = fc.key
            local get = function(p) return p.fight and p.fight[key] end
            if AnyValue(players, get) then
                cols[#cols + 1] = {
                    key = "f:" .. key, label = fc.label, width = 56, numeric = true, value = get, fmt = fc.fmt,
                    tip = fc.tip .. "\nYou: LibFights. Teammates: combat log (group members).\nEnemies: combat log, only what they did to and took from your team.", fight = true,
                }
            end
        end
    end

    if SBR.sv.showVsColumns then
        for _, vc in ipairs(VS_COLUMNS) do
            local key = vc.key
            local get = function(p) return p.vs and p.vs[key] end
            if AnyValue(players, get) then
                cols[#cols + 1] = {
                    key = "v:" .. key, label = vc.label, width = 56, numeric = true, value = get, tip = vc.tip, vs = true,
                }
            end
        end
    end

    for _, c in ipairs(cols) do
        c.align = c.align or (c.numeric and TEXT_ALIGN_RIGHT or TEXT_ALIGN_LEFT)
        if c.numeric and not c.text then
            local value, fmt = c.value, c.fmt
            c.text = function(p)
                local v = value(p)
                if v == nil then return "|c666666-|r" end
                return fmt and fmt(v) or SBR.FormatNumber(v)
            end
        end
        c.sortValue = c.sortValue or c.value
    end
    self.columns = cols
    return cols
end

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------
function UI:Create()
    if self.control then return end
    local tlw = WM:CreateTopLevelWindow("ScoreboardRemasteredWindow")
    self.control = tlw
    tlw:SetHidden(true)
    tlw:SetMouseEnabled(true)
    tlw:SetMovable(true)
    tlw:SetClampedToScreen(true)
    tlw:SetDrawLayer(DL_OVERLAY)
    tlw:SetDrawTier(DT_HIGH)
    tlw:SetDimensions(900, 400)
    tlw:SetScale(SBR.sv.scale or 1)
    tlw:SetHandler("OnMoveStop", function(control)
        SBR.sv.position = { left = control:GetLeft(), top = control:GetTop() }
        self:ApplyPosition()
    end)

    local bg = WM:CreateControlFromVirtual(NextName("BG"), tlw, "ZO_DefaultBackdrop")
    bg:SetAnchorFill(tlw)

    local close = WM:CreateControlFromVirtual(NextName("Close"), tlw, "ZO_CloseButton")
    close:SetAnchor(TOPRIGHT, tlw, TOPRIGHT, -6, 6)
    close:SetHandler("OnClicked", function() self:Hide(true) end)

    self.title = CreateLabel(tlw, "ZoFontWinH3")
    self.title:SetAnchor(TOPLEFT, tlw, TOPLEFT, PAD, PAD - 2)
    self.title:SetDimensions(560, 28)

    self.subtitle = CreateLabel(tlw, FONT_ROW)
    self.subtitle:SetAnchor(TOPLEFT, self.title, BOTTOMLEFT, 0, 0)
    self.subtitle:SetDimensions(560, 20)
    self.subtitle:SetColor(0.75, 0.75, 0.75, 1)

    self.teamLabel = CreateLabel(tlw, "ZoFontWinH4", TEXT_ALIGN_RIGHT)
    self.teamLabel:SetAnchor(TOPRIGHT, tlw, TOPRIGHT, -40, PAD)
    self.teamLabel:SetDimensions(420, 26)

    self.sourceLabel = CreateLabel(tlw, FONT_ROW, TEXT_ALIGN_RIGHT)
    self.sourceLabel:SetAnchor(TOPRIGHT, self.teamLabel, BOTTOMRIGHT, 0, 0)
    self.sourceLabel:SetDimensions(420, 20)
    self.sourceLabel:SetColor(0.6, 0.6, 0.6, 1)

    local divider = CreateTexture(tlw, 1, 1, 1, 0.15)
    divider:SetAnchor(TOPLEFT, tlw, TOPLEFT, PAD, TOP_H - 4)
    divider:SetAnchor(TOPRIGHT, tlw, TOPRIGHT, -PAD, TOP_H - 4)
    divider:SetHeight(1)

    self.headerRow = WM:CreateControl(NextName("Header"), tlw, CT_CONTROL)
    self.headerRow:SetAnchor(TOPLEFT, tlw, TOPLEFT, PAD, TOP_H)
    self.headerRow:SetHeight(HEADER_H)

    self.list = WM:CreateControl(NextName("List"), tlw, CT_CONTROL)
    self.list:SetAnchor(TOPLEFT, self.headerRow, BOTTOMLEFT, 0, 2)

    self.emptyLabel = CreateLabel(self.list, "ZoFontGame", TEXT_ALIGN_CENTER)
    self.emptyLabel:SetAnchor(TOPLEFT, self.list, TOPLEFT, 0, 10)
    self.emptyLabel:SetText("No battleground data yet. Join a battleground, or browse history with < >.")
    self.emptyLabel:SetColor(0.7, 0.7, 0.7, 1)

    -- footer
    local footer = WM:CreateControl(NextName("Footer"), tlw, CT_CONTROL)
    footer:SetAnchor(BOTTOMLEFT, tlw, BOTTOMLEFT, PAD, -PAD + 4)
    footer:SetAnchor(BOTTOMRIGHT, tlw, BOTTOMRIGHT, -PAD, -PAD + 4)
    footer:SetHeight(30)
    self.footer = footer

    self.prevButton = CreateButton(footer, "<", 40, function() self:Step(-1) end)
    self.prevButton:SetAnchor(LEFT, footer, LEFT, 0, 0)
    self.liveButton = CreateButton(footer, "Live", 70, function() self:SetView(nil) end)
    self.liveButton:SetAnchor(LEFT, self.prevButton, RIGHT, 4, 0)
    self.nextButton = CreateButton(footer, ">", 40, function() self:Step(1) end)
    self.nextButton:SetAnchor(LEFT, self.liveButton, RIGHT, 4, 0)

    self.viewLabel = CreateLabel(footer, FONT_ROW)
    self.viewLabel:SetAnchor(LEFT, self.nextButton, RIGHT, 10, 0)
    self.viewLabel:SetDimensions(260, 28)
    self.viewLabel:SetColor(0.7, 0.7, 0.7, 1)

    self.exportButton = CreateButton(footer, "Export", 90, function() SBR.Export:Show(self:GetViewedMatch()) end)
    self.exportButton:SetAnchor(RIGHT, footer, RIGHT, 0, 0)
    self.killsButton = CreateButton(footer, "Kill feed", 100, function() SBR.Export:ShowKillFeed(self:GetViewedMatch()) end)
    self.killsButton:SetAnchor(RIGHT, self.exportButton, LEFT, -4, 0)
    self.groupButton = CreateButton(footer, "", 120, function()
        SBR.sv.groupByTeam = not SBR.sv.groupByTeam
        self:Refresh()
    end)
    self.groupButton:SetAnchor(RIGHT, self.killsButton, LEFT, -4, 0)

    self:ApplyPosition()
end

function UI:ApplyPosition()
    local c = self.control
    if not c then return end
    c:ClearAnchors()
    local pos = SBR.sv.position
    if pos and pos.left then
        c:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT, pos.left, pos.top)
        return
    end
    local native = SBR.Hook and SBR.Hook:GetAnchorControl()
    local mode = SBR.sv.attach or "right"
    if native and mode ~= "free" then
        if mode == "left" then
            c:SetAnchor(TOPRIGHT, native, TOPLEFT, -8, 0)
        elseif mode == "below" then
            c:SetAnchor(TOP, native, BOTTOM, 0, 8)
        else
            c:SetAnchor(TOPLEFT, native, TOPRIGHT, 8, 0)
        end
    else
        c:SetAnchor(CENTER, GuiRoot, CENTER, 0, 0)
    end
end

function UI:ResetPosition()
    SBR.sv.position = nil
    self:ApplyPosition()
end

function UI:GetHeader(i)
    local h = self.headers[i]
    if h then return h end
    h = CreateLabel(self.headerRow, FONT_HEAD)
    h:SetHeight(HEADER_H)
    h:SetMouseEnabled(true)
    h:SetHandler("OnMouseUp", function(control, button, upInside)
        if upInside and control.column then self:SortBy(control.column.key) end
    end)
    h:SetHandler("OnMouseEnter", function(control)
        if control.column and control.column.tip then ShowTooltip(control, control.column.tip) end
    end)
    h:SetHandler("OnMouseExit", HideTooltip)
    self.headers[i] = h
    return h
end

function UI:GetRow(i)
    local row = self.rows[i]
    if row then return row end
    row = WM:CreateControl(NextName("Row"), self.list, CT_CONTROL)
    row:SetHeight(ROW_H)
    row:SetAnchor(TOPLEFT, self.list, TOPLEFT, 0, (i - 1) * ROW_H)
    row:SetMouseEnabled(true)
    row.bg = CreateTexture(row, 1, 1, 1, 0)
    row.bg:SetAnchorFill(row)
    row.strip = CreateTexture(row, 1, 1, 1, 1)
    row.strip:SetAnchor(TOPLEFT, row, TOPLEFT, 0, 1)
    row.strip:SetDimensions(STRIP_W, ROW_H - 2)
    row.cells = {}
    row:SetHandler("OnMouseEnter", function(control)
        control.bg:SetColor(1, 1, 1, 0.12)
        if control.player then ShowTooltip(control, self:PlayerTooltip(control.player)) end
    end)
    row:SetHandler("OnMouseExit", function(control)
        self:PaintRowBackground(control)
        HideTooltip()
    end)
    self.rows[i] = row
    return row
end

function UI:PaintRowBackground(row)
    if row.player and row.player.isLocal then
        row.bg:SetColor(0.31, 0.76, 0.97, 0.18)
    elseif row.index and row.index % 2 == 0 then
        row.bg:SetColor(1, 1, 1, 0.04)
    else
        row.bg:SetColor(1, 1, 1, 0)
    end
end

---------------------------------------------------------------------------
-- Data -> UI
---------------------------------------------------------------------------
function UI:GetViewedMatch()
    if self.viewIndex then return SBR.MatchLog:GetHistory()[self.viewIndex] end
    return SBR.MatchLog:GetLive()
end

function UI:SetView(index)
    local history = SBR.MatchLog:GetHistory()
    if index and (index < 1 or index > #history) then index = nil end
    self.viewIndex = index
    self:Refresh()
end

function UI:Step(delta)
    local history = SBR.MatchLog:GetHistory()
    if #history == 0 then return end
    local idx = self.viewIndex
    if not idx then
        -- Live view of a finished match already shows history[#history].
        idx = SBR.MatchLog:GetCurrent() and (#history + 1) or #history
    end
    idx = zo_clamp(idx + delta, 1, #history)
    self:SetView(idx)
end

function UI:SortBy(key)
    if self.sort.key == key then
        self.sort.desc = not self.sort.desc
    else
        self.sort.key, self.sort.desc = key, key ~= "name" and key ~= "class"
    end
    self:Refresh()
end

function UI:SortedPlayers(match)
    local list = {}
    for _, p in pairs(match.players or {}) do list[#list + 1] = p end
    local col
    for _, c in ipairs(self.columns) do
        if c.key == self.sort.key then col = c break end
    end
    if not col then
        for _, c in ipairs(self.columns) do
            if c.numeric then col = c break end
        end
    end
    local desc = self.sort.desc
    local group = SBR.sv.groupByTeam
    local localTeam = match.localTeam
    table.sort(list, function(a, b)
        if group and a.team ~= b.team then
            -- your team first, then by team id
            if a.team == localTeam then return true end
            if b.team == localTeam then return false end
            return (a.team or 99) < (b.team or 99)
        end
        if col then
            local va, vb = col.sortValue(a), col.sortValue(b)
            if va ~= vb then
                if va == nil then return false end
                if vb == nil then return true end
                if type(va) ~= type(vb) then va, vb = tostring(va), tostring(vb) end
                if desc then return va > vb else return va < vb end
            end
        end
        return (a.characterName or "") < (b.characterName or "")
    end)
    return list
end

function UI:PlayerTooltip(p)
    local lines = {}
    local function add(s) lines[#lines + 1] = s end
    add(string.format("%s  %s", p.characterName or "?", p.displayName or ""))
    if p.className then add(p.className) end
    if p.medals and #p.medals > 0 then
        add(" ")
        add("Medals:")
        for _, m in ipairs(p.medals) do
            local icon = m.icon and zo_iconFormat(m.icon, 18, 18) or ""
            add(string.format("  %s %s x%d", icon, m.name or "?", m.count or 1))
        end
    end
    if p.fight then
        local f = p.fight
        add(" ")
        add("Fight data" .. (f.source and (" (" .. f.source .. ")") or "") .. ":")
        local function stat(label, v, fmt)
            if v ~= nil then add(string.format("  %s: %s", label, fmt and fmt(v) or SBR.FormatNumber(v))) end
        end
        stat("Damage", f.damageDone)
        stat("Healing", f.healingDone)
        stat("Damage taken", f.damageTaken)
        stat("Healing taken", f.healingTaken)
        stat("Shielded", f.damageShielded)
        stat("Blocked", f.damageBlocked)
        stat("Killing blows", f.killingBlows)
        stat("Deaths", f.deaths)
        stat("Interrupts", f.interrupts)
        stat("Interrupted", f.interrupted)
        stat("CC applied", f.ccApplied)
        stat("CC taken", f.ccTaken)
        stat("Crit rate", f.critRate, function(v) return string.format("%.1f%%", v) end)
        stat("Heal crit rate", f.healCritRate, function(v) return string.format("%.1f%%", v) end)
        if f.maxHit then add(string.format("  Max hit: %s%s", SBR.FormatNumber(f.maxHit), f.maxHitAbility and (" (" .. f.maxHitAbility .. ")") or "")) end
        stat("Mitigated", f.mitigated)
        stat("Overheal", f.overheal)
        stat("Enemy shields soaked", f.enemyShieldAbsorbed)
        if f.lightAttacks or f.heavyAttacks or f.skillCasts then
            add(string.format("  LA/HA/skills/ults: %s/%s/%s/%s, weaves %s", tostring(f.lightAttacks or 0), tostring(f.heavyAttacks or 0),
                tostring(f.skillCasts or 0), tostring(f.ultimates or 0), tostring(f.weaves or 0)))
        end
        stat("Fights", f.fights)
        stat("Combat time", f.activeTime, SBR.FormatDuration)
        local function abilityList(title, list)
            if type(list) == "table" and #list > 0 then
                add("  " .. title .. ":")
                for _, a in ipairs(list) do
                    local icon = a.icon and zo_iconFormat(a.icon, 16, 16) or ""
                    add(string.format("    %s %s  %s", icon, a.name or "?", SBR.FormatNumber(a.damage)))
                end
            end
        end
        abilityList("Top damage", f.topAbilities)
        abilityList("Top heals", f.topHeals)
        if f.source and f.source:find("vs your team", 1, true) then
            add("  |c999999Enemy: only what they did to and took from your team.|r")
        end
    end
    if p.vs then
        local v = p.vs
        add(" ")
        add("You vs them:")
        add(string.format("  You dealt %s, took %s", SBR.FormatNumber(v.damageFromYou), SBR.FormatNumber(v.damageToYou)))
        if (v.killedByYou or 0) > 0 or (v.killedYou or 0) > 0 then
            add(string.format("  You killed them %d, they killed you %d", v.killedByYou or 0, v.killedYou or 0))
        end
        if (v.healedByYou or 0) > 0 then add("  You healed them " .. SBR.FormatNumber(v.healedByYou)) end
    end
    if p.isLocal then
        local match = self:GetViewedMatch()
        local deaths = match and match.lf and match.lf.deaths
        if deaths and #deaths > 0 then
            add(" ")
            add(string.format("Deaths with recap: %d (Kill feed button for details)", #deaths))
        end
    end
    return table.concat(lines, "\n")
end

function UI:RefreshHeader(match)
    if not match then
        self.title:SetText(SBR.displayName)
        self.subtitle:SetText("")
        self.teamLabel:SetText("")
        self.sourceLabel:SetText("")
        return
    end
    self.title:SetText(match.name or match.zoneName or "Battleground")
    local parts = {}
    if match.gameTypeName then parts[#parts + 1] = match.gameTypeName end
    if match.teamSize then parts[#parts + 1] = string.format("%dv%d", match.teamSize, match.teamSize) end
    if match.endedAt then
        local res = ({ won = "|c66FF66Victory|r", lost = "|cFF6666Defeat|r", tie = "Tie", left = "|cAAAAAALeft early|r" })[match.result]
        parts[#parts + 1] = res or "Ended"
        parts[#parts + 1] = SBR.FormatDuration(match.duration)
        parts[#parts + 1] = SBR.FormatTimestamp(match.startedAt)
    else
        parts[#parts + 1] = match.stateName or "In progress"
        if match.runningSince then parts[#parts + 1] = SBR.FormatDuration(SBR.Now() - match.runningSince) end
        if match.numRounds and match.numRounds > 1 and match.roundIndex then
            parts[#parts + 1] = string.format("Round %d/%d", match.roundIndex, match.numRounds)
        end
    end
    self.subtitle:SetText(table.concat(parts, "  |c666666•|r  "))

    local teamTexts = {}
    local ids = {}
    for id, t in pairs(match.teams or {}) do
        local hasPlayers = false
        for _, p in pairs(match.players or {}) do
            if p.team == id then hasPlayers = true break end
        end
        if hasPlayers or t.score then ids[#ids + 1] = id end
    end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local t = match.teams[id]
        local marker = id == match.localTeam and "*" or ""
        teamTexts[#teamTexts + 1] = SBR.Colorize(t.color, string.format("%s%s %s", marker, t.name or id, t.score ~= nil and tostring(t.score) or "-"))
    end
    self.teamLabel:SetText(table.concat(teamTexts, "   "))

    local src
    local ledgerOn = match.ledger ~= nil or (match.endedAt and SBR.sv.trackCombat)
    if match.lf then
        local n = match.lf.fightList and #match.lf.fightList or 0
        if match.lf.fights then for _ in pairs(match.lf.fights) do n = n + 1 end end
        src = string.format("LibFights (you, %d fight%s)", n, n == 1 and "" or "s")
        if ledgerOn then src = src .. " + combat log (everyone)" end
    elseif ledgerOn then
        src = "combat log (everyone)"
    end
    if not match.endedAt then src = SBR.LibFights:StatusText() .. (src and ("  |  " .. src) or "") end
    self.sourceLabel:SetText("Fight data: " .. (src or "none"))
end

function UI:Refresh()
    if not self.control or self.control:IsHidden() then return end
    local match = self:GetViewedMatch()
    self:RefreshHeader(match)

    local cols = match and self:BuildColumns(match) or {}
    local x = STRIP_W + 4
    for i, c in ipairs(cols) do
        local h = self:GetHeader(i)
        h.column = c
        h:SetHidden(false)
        h:ClearAnchors()
        h:SetAnchor(TOPLEFT, self.headerRow, TOPLEFT, x, 0)
        h:SetWidth(c.width)
        h:SetHorizontalAlignment(c.align)
        local arrow = ""
        if self.sort.key == c.key then arrow = self.sort.desc and " v" or " ^" end
        h:SetText(c.label .. arrow)
        if c.fight then h:SetColor(1, 0.85, 0.45, 1)
        elseif c.vs then h:SetColor(0.6, 0.85, 1, 1)
        else h:SetColor(0.9, 0.9, 0.9, 1) end
        c.x = x
        x = x + c.width + 6
    end
    for i = #cols + 1, #self.headers do self.headers[i]:SetHidden(true) end
    local contentWidth = math.max(x, 640)

    local players = match and self:SortedPlayers(match) or {}
    for i, p in ipairs(players) do
        local row = self:GetRow(i)
        row:SetHidden(false)
        row:SetWidth(contentWidth)
        row.player, row.index = p, i
        local team = match.teams and match.teams[p.team]
        row.strip:SetColor(SBR.HexToRGB(team and team.color or "FFFFFF"))
        self:PaintRowBackground(row)
        for ci, c in ipairs(cols) do
            local cell = row.cells[ci]
            if not cell then
                cell = CreateLabel(row, FONT_ROW)
                cell:SetHeight(ROW_H)
                row.cells[ci] = cell
            end
            cell:SetHidden(false)
            cell:ClearAnchors()
            cell:SetAnchor(TOPLEFT, row, TOPLEFT, c.x, 0)
            cell:SetWidth(c.width)
            cell:SetHorizontalAlignment(c.align)
            cell:SetText(c.text(p))
            if p.isLocal and c.key == "name" then cell:SetColor(0.31, 0.76, 0.97, 1) else cell:SetColor(1, 1, 1, 1) end
        end
        for ci = #cols + 1, #row.cells do row.cells[ci]:SetHidden(true) end
    end
    for i = #players + 1, #self.rows do
        self.rows[i]:SetHidden(true)
        self.rows[i].player = nil
    end

    self.emptyLabel:SetHidden(#players > 0)
    self.emptyLabel:SetWidth(contentWidth)

    local listH = math.max(#players, 2) * ROW_H
    self.headerRow:SetWidth(contentWidth)
    self.list:SetDimensions(contentWidth, listH)
    self.control:SetDimensions(contentWidth + PAD * 2, TOP_H + HEADER_H + 2 + listH + FOOTER_H + PAD)

    -- footer state
    local history = SBR.MatchLog:GetHistory()
    if self.viewIndex then
        self.viewLabel:SetText(string.format("History %d / %d", self.viewIndex, #history))
    else
        self.viewLabel:SetText(SBR.MatchLog:GetCurrent() and "|c66FF66Live|r" or (#history > 0 and "Last match" or ""))
    end
    self.groupButton:SetText(SBR.sv.groupByTeam and "By team: on" or "By team: off")
end

function UI:OnDataChanged()
    if self.viewIndex == nil then self:Refresh() end
end

---------------------------------------------------------------------------
-- Visibility
---------------------------------------------------------------------------
function UI:Show(pinned)
    self:Create()
    if pinned then self.pinned = true end
    self:ApplyPosition()
    self.control:SetHidden(false)
    if SBR.MatchLog:GetCurrent() then SBR.MatchLog:Snapshot() end
    self:Refresh()
end

function UI:Hide(force)
    if not self.control then return end
    if self.pinned and not force then return end
    self.pinned = false
    self.control:SetHidden(true)
    HideTooltip()
end

function UI:Toggle()
    if self.control and not self.control:IsHidden() then
        self:Hide(true)
    else
        self:Show(true)
        -- needs the cursor when opened outside the native scoreboard
        if not SCENE_MANAGER:IsInUIMode() then SCENE_MANAGER:SetInUIMode(true) end
    end
end

function UI:IsShown()
    return self.control ~= nil and not self.control:IsHidden()
end

-- Called by the hook when the native scoreboard opens / closes.
function UI:OnNativeShown()
    if not SBR.sv.autoShowWithScoreboard then return end
    self:Show(false)
end

function UI:OnNativeHidden()
    self:Hide(false)
    self:ApplyPosition()
end
