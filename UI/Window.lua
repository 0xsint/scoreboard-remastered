-- The remastered scoreboard panel. One window, two styles:
--   keyboard  mouse UI attached to the native scoreboard; click a row for details
--   gamepad   console / gamepad mode, shown in its own scene (UI/Gamepad.lua); a
--             selected row moves with the d-pad and A / Cross opens its details
local SBR = ScoreboardRemastered
local UI = {
    rows = {},
    headers = {},
    columns = {},
    sort = { key = "s:SCORE", desc = true },
    viewIndex = nil,     -- nil = live, number = history index
    pinned = false,      -- opened manually, stays open when the native scoreboard closes
    selectedKey = nil,   -- player key of the selected row
    detailsOpen = false,
    mode = "keyboard",
}
SBR.Window = UI

local WM = WINDOW_MANAGER
local STRIP_W = 4

local function Font(...)
    for i = 1, select("#", ...) do
        local name = select(i, ...)
        if _G[name] ~= nil then return name end
    end
    return "ZoFontGame"
end

local STYLES = {
    keyboard = {
        pad = 12, topH = 78, headerH = 24, rowH = 22, footerH = 42, colScale = 1, detailsW = 340,
        fontRow = "ZoFontGameSmall", fontHead = "ZoFontGameBold", fontTitle = "ZoFontWinH3",
        fontSub = "ZoFontGameSmall", fontTeams = "ZoFontWinH4", fontDetails = "ZoFontGameSmall",
        fontDetailsTitle = "ZoFontWinH4", iconSize = 20,
    },
    gamepad = {
        pad = 20, topH = 104, headerH = 34, rowH = 34, footerH = 34, colScale = 1.35, detailsW = 470,
        fontRow = Font("ZoFontGamepad22", "ZoFontGame"),
        fontHead = Font("ZoFontGamepadBold22", "ZoFontGamepad22", "ZoFontGameBold"),
        fontTitle = Font("ZoFontGamepadBold34", "ZoFontGamepad34", "ZoFontWinH2"),
        fontSub = Font("ZoFontGamepad22", "ZoFontGame"),
        fontTeams = Font("ZoFontGamepadBold27", "ZoFontGamepad27", "ZoFontWinH3"),
        fontDetails = Font("ZoFontGamepad22", "ZoFontGame"),
        fontDetailsTitle = Font("ZoFontGamepadBold27", "ZoFontGamepad27", "ZoFontWinH3"),
        iconSize = 28,
    },
}

local nameCounter = 0
local function NextName(kind)
    nameCounter = nameCounter + 1
    return string.format("SBR_%s%d", kind, nameCounter)
end

local function CreateLabel(parent, font, align)
    local l = WM:CreateControl(NextName("Label"), parent, CT_LABEL)
    l:SetFont(font or "ZoFontGameSmall")
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

local function CreateBackdrop(parent, virtualNames)
    for _, v in ipairs(virtualNames) do
        local ok, bd = pcall(WM.CreateControlFromVirtual, WM, NextName("BG"), parent, v)
        if ok and bd then
            bd:SetAnchorFill(parent)
            return bd
        end
    end
    local bd = CreateTexture(parent, 0.05, 0.05, 0.06, 0.92)
    bd:SetAnchorFill(parent)
    return bd
end

local function ShowTooltip(control, text)
    InitializeTooltip(InformationTooltip, control, BOTTOM, 0, -4)
    SetTooltipText(InformationTooltip, text)
end

local function HideTooltip()
    ClearTooltip(InformationTooltip)
end

local function PlayerKey(p)
    return (p.displayName and p.displayName ~= "") and p.displayName or p.characterName
end

---------------------------------------------------------------------------
-- Columns
---------------------------------------------------------------------------
-- gp = shown in gamepad mode too (the rest stays in the details pane there,
-- so the table fits a TV-distance font size)
local FIGHT_COLUMNS = {
    { key = "dps", label = "DPS", tip = "Damage per second in combat", gp = true },
    { key = "hps", label = "HPS", tip = "Healing per second in combat", gp = true },
    { key = "damageTaken", label = "Taken", tip = "Damage taken", gp = true },
    { key = "healingTaken", label = "Healed", tip = "Healing received" },
    { key = "killingBlows", label = "KBs", tip = "Killing blows", gp = true },
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

local FIGHT_TIP = "\nYou: LibFights. Teammates: combat log (group members).\nEnemies: combat log, only what they did to and took from your team."

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
    local gamepad = self.mode == "gamepad"
    local st_ = self.style
    local scale = st_.colScale

    cols[#cols + 1] = {
        key = "class", label = "", width = st_.iconSize + 6, align = TEXT_ALIGN_CENTER,
        text = function(p) return p.classIcon and zo_iconFormat(p.classIcon, st_.iconSize, st_.iconSize) or "" end,
        sortValue = function(p) return p.className or "" end,
    }
    cols[#cols + 1] = {
        key = "name", label = "Player", width = math.floor(200 * scale), align = TEXT_ALIGN_LEFT,
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
                key = "s:" .. key, label = st.label, width = math.floor(math.max(52, #st.label * 8) * scale), numeric = true,
                value = get, tip = st.label .. " (native scoreboard)",
            }
        end
    end

    cols[#cols + 1] = {
        key = "medals", label = "Medals", width = math.floor(56 * scale), numeric = true,
        value = function(p) return p.medalCount end, tip = "Medals earned (open a row for the list)",
    }

    if SBR.sv.showFightColumns then
        for _, fc in ipairs(FIGHT_COLUMNS) do
            if fc.gp or not gamepad then
                local key = fc.key
                local get = function(p) return p.fight and p.fight[key] end
                if AnyValue(players, get) then
                    cols[#cols + 1] = {
                        key = "f:" .. key, label = fc.label, width = math.floor(56 * scale), numeric = true, value = get,
                        fmt = fc.fmt, tip = fc.tip .. FIGHT_TIP, fight = true,
                    }
                end
            end
        end
    end

    if SBR.sv.showVsColumns and not gamepad then
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
    self.style = STYLES.keyboard
    local tlw = WM:CreateTopLevelWindow("ScoreboardRemasteredWindow")
    self.control = tlw
    tlw:SetHidden(true)
    tlw:SetMouseEnabled(true)
    tlw:SetClampedToScreen(true)
    tlw:SetDrawLayer(DL_OVERLAY)
    tlw:SetDrawTier(DT_HIGH)
    tlw:SetDimensions(900, 400)
    tlw:SetHandler("OnMoveStop", function(control)
        SBR.sv.position = { left = control:GetLeft(), top = control:GetTop() }
        self:ApplyPosition()
    end)

    self.bgKeyboard = CreateBackdrop(tlw, { "ZO_DefaultBackdrop" })
    self.bgGamepad = CreateBackdrop(tlw, { "ZO_DefaultBackdrop_Gamepad", "ZO_DefaultBackdrop" })

    self.closeButton = WM:CreateControlFromVirtual(NextName("Close"), tlw, "ZO_CloseButton")
    self.closeButton:SetAnchor(TOPRIGHT, tlw, TOPRIGHT, -6, 6)
    self.closeButton:SetHandler("OnClicked", function() self:Hide(true) end)

    self.title = CreateLabel(tlw)
    self.subtitle = CreateLabel(tlw)
    self.subtitle:SetColor(0.75, 0.75, 0.75, 1)
    self.teamLabel = CreateLabel(tlw, nil, TEXT_ALIGN_RIGHT)
    self.sourceLabel = CreateLabel(tlw, nil, TEXT_ALIGN_RIGHT)
    self.sourceLabel:SetColor(0.6, 0.6, 0.6, 1)
    self.divider = CreateTexture(tlw, 1, 1, 1, 0.15)
    self.divider:SetHeight(1)

    self.headerRow = WM:CreateControl(NextName("Header"), tlw, CT_CONTROL)
    self.list = WM:CreateControl(NextName("List"), tlw, CT_CONTROL)

    self.emptyLabel = CreateLabel(self.list, "ZoFontGame", TEXT_ALIGN_CENTER)
    self.emptyLabel:SetAnchor(TOPLEFT, self.list, TOPLEFT, 0, 10)
    self.emptyLabel:SetColor(0.7, 0.7, 0.7, 1)

    -- footer (keyboard buttons; in gamepad mode the keybind strip replaces them)
    local footer = WM:CreateControl(NextName("Footer"), tlw, CT_CONTROL)
    footer:SetHeight(30)
    self.footer = footer

    self.buttons = {}
    local function button(text, width, fn)
        local b = CreateButton(footer, text, width, fn)
        self.buttons[#self.buttons + 1] = b
        return b
    end
    self.prevButton = button("<", 40, function() self:Step(-1) end)
    self.prevButton:SetAnchor(LEFT, footer, LEFT, 0, 0)
    self.liveButton = button("Live", 70, function() self:SetView(nil) end)
    self.liveButton:SetAnchor(LEFT, self.prevButton, RIGHT, 4, 0)
    self.nextButton = button(">", 40, function() self:Step(1) end)
    self.nextButton:SetAnchor(LEFT, self.liveButton, RIGHT, 4, 0)
    self.exportButton = button("Export", 90, function() SBR.Export:Show(self:GetViewedMatch()) end)
    self.exportButton:SetAnchor(RIGHT, footer, RIGHT, 0, 0)
    self.killsButton = button("Kill feed", 100, function() SBR.Export:ShowKillFeed(self:GetViewedMatch()) end)
    self.killsButton:SetAnchor(RIGHT, self.exportButton, LEFT, -4, 0)
    self.groupButton = button("", 120, function() self:ToggleGroupByTeam() end)
    self.groupButton:SetAnchor(RIGHT, self.killsButton, LEFT, -4, 0)

    self.viewLabel = CreateLabel(footer)
    self.viewLabel:SetDimensions(260, 28)
    self.viewLabel:SetColor(0.7, 0.7, 0.7, 1)

    self:CreateDetails()
    self:ApplyStyle("keyboard")
end

-- Details pane: what used to be the hover tooltip. Opens beside the panel.
function UI:CreateDetails()
    local pane = WM:CreateControl(NextName("Details"), self.control, CT_CONTROL)
    pane:SetHidden(true)
    pane:SetMouseEnabled(true)
    self.details = pane
    self.detailsBgKeyboard = CreateBackdrop(pane, { "ZO_DefaultBackdrop" })
    self.detailsBgGamepad = CreateBackdrop(pane, { "ZO_DefaultBackdrop_Gamepad", "ZO_DefaultBackdrop" })

    self.detailsClose = WM:CreateControlFromVirtual(NextName("DetailsClose"), pane, "ZO_CloseButton")
    self.detailsClose:SetAnchor(TOPRIGHT, pane, TOPRIGHT, -6, 6)
    self.detailsClose:SetHandler("OnClicked", function() self:CloseDetails() end)

    self.detailsTitle = CreateLabel(pane)
    self.detailsBody = CreateLabel(pane)
    self.detailsBody:SetVerticalAlignment(TEXT_ALIGN_TOP)
    self.detailsBody:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
end

function UI:ApplyStyle(mode)
    self.mode = mode
    local s = STYLES[mode]
    self.style = s
    local tlw = self.control
    local gamepad = mode == "gamepad"

    self.bgKeyboard:SetHidden(gamepad)
    self.bgGamepad:SetHidden(not gamepad)
    self.detailsBgKeyboard:SetHidden(gamepad)
    self.detailsBgGamepad:SetHidden(not gamepad)
    self.closeButton:SetHidden(gamepad)
    self.detailsClose:SetHidden(gamepad)
    for _, b in ipairs(self.buttons) do b:SetHidden(gamepad) end
    tlw:SetMovable(not gamepad)
    tlw:SetScale(gamepad and 1 or (SBR.sv.scale or 1))

    self.title:SetFont(s.fontTitle)
    self.title:ClearAnchors()
    self.title:SetAnchor(TOPLEFT, tlw, TOPLEFT, s.pad, s.pad - 2)
    self.title:SetDimensions(600, s.topH * 0.4)
    self.subtitle:SetFont(s.fontSub)
    self.subtitle:ClearAnchors()
    self.subtitle:SetAnchor(TOPLEFT, self.title, BOTTOMLEFT, 0, 0)
    self.subtitle:SetDimensions(600, s.topH * 0.3)
    self.teamLabel:SetFont(s.fontTeams)
    self.teamLabel:ClearAnchors()
    self.teamLabel:SetAnchor(TOPRIGHT, tlw, TOPRIGHT, gamepad and -s.pad or -40, s.pad)
    self.teamLabel:SetDimensions(520, s.topH * 0.35)
    self.sourceLabel:SetFont(s.fontSub)
    self.sourceLabel:ClearAnchors()
    self.sourceLabel:SetAnchor(TOPRIGHT, self.teamLabel, BOTTOMRIGHT, 0, 0)
    self.sourceLabel:SetDimensions(620, s.topH * 0.3)

    self.divider:ClearAnchors()
    self.divider:SetAnchor(TOPLEFT, tlw, TOPLEFT, s.pad, s.topH - 4)
    self.divider:SetAnchor(TOPRIGHT, tlw, TOPRIGHT, -s.pad, s.topH - 4)
    self.headerRow:ClearAnchors()
    self.headerRow:SetAnchor(TOPLEFT, tlw, TOPLEFT, s.pad, s.topH)
    self.headerRow:SetHeight(s.headerH)
    self.list:ClearAnchors()
    self.list:SetAnchor(TOPLEFT, self.headerRow, BOTTOMLEFT, 0, 2)
    self.emptyLabel:SetFont(s.fontSub)
    self.emptyLabel:SetText(gamepad
        and "No battleground data yet. Join a battleground, or use the bumpers to browse past matches."
        or "No battleground data yet. Join a battleground, or browse history with < >.")

    self.footer:ClearAnchors()
    self.footer:SetAnchor(BOTTOMLEFT, tlw, BOTTOMLEFT, s.pad, -s.pad + 4)
    self.footer:SetAnchor(BOTTOMRIGHT, tlw, BOTTOMRIGHT, -s.pad, -s.pad + 4)
    self.viewLabel:SetFont(s.fontSub)
    self.viewLabel:ClearAnchors()
    if gamepad then
        self.viewLabel:SetAnchor(LEFT, self.footer, LEFT, 0, 0)
    else
        self.viewLabel:SetAnchor(LEFT, self.nextButton, RIGHT, 10, 0)
    end

    self.detailsTitle:SetFont(s.fontDetailsTitle)
    self.detailsBody:SetFont(s.fontDetails)
    self.details:SetWidth(s.detailsW)
    self.detailsTitle:ClearAnchors()
    self.detailsTitle:SetAnchor(TOPLEFT, self.details, TOPLEFT, s.pad, s.pad - 2)
    self.detailsTitle:SetDimensions(s.detailsW - s.pad * 2 - (gamepad and 0 or 24), s.rowH + 4)
    self.detailsBody:ClearAnchors()
    self.detailsBody:SetAnchor(TOPLEFT, self.detailsTitle, BOTTOMLEFT, 0, 4)
    self.detailsBody:SetWidth(s.detailsW - s.pad * 2)

    -- existing pooled controls pick up the new metrics in Refresh
    for _, h in ipairs(self.headers) do
        h:SetFont(s.fontHead)
        h:SetHeight(s.headerH)
    end
    for i, row in ipairs(self.rows) do self:StyleRow(row, i) end
    self:ApplyPosition()
end

function UI:ApplyPosition()
    local c = self.control
    if not c then return end
    c:ClearAnchors()
    if self.mode == "gamepad" then
        -- centered, leaving room on the right for the details pane
        c:SetAnchor(CENTER, GuiRoot, CENTER, -math.floor(self.style.detailsW / 2), 0)
        return
    end
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
    h = CreateLabel(self.headerRow, self.style.fontHead)
    h:SetHeight(self.style.headerH)
    h:SetMouseEnabled(true)
    h:SetHandler("OnMouseUp", function(control, button, upInside)
        if upInside and control.column then self:SortBy(control.column.key) end
    end)
    h:SetHandler("OnMouseEnter", function(control)
        if self.mode == "keyboard" and control.column and control.column.tip then ShowTooltip(control, control.column.tip) end
    end)
    h:SetHandler("OnMouseExit", HideTooltip)
    self.headers[i] = h
    return h
end

function UI:StyleRow(row, i)
    local s = self.style
    row:SetHeight(s.rowH)
    row:ClearAnchors()
    row:SetAnchor(TOPLEFT, self.list, TOPLEFT, 0, (i - 1) * s.rowH)
    row.strip:SetDimensions(STRIP_W, s.rowH - 2)
    for _, cell in ipairs(row.cells) do
        cell:SetFont(s.fontRow)
        cell:SetHeight(s.rowH)
    end
end

function UI:GetRow(i)
    local row = self.rows[i]
    if row then return row end
    row = WM:CreateControl(NextName("Row"), self.list, CT_CONTROL)
    row:SetMouseEnabled(true)
    row.bg = CreateTexture(row, 1, 1, 1, 0)
    row.bg:SetAnchorFill(row)
    row.strip = CreateTexture(row, 1, 1, 1, 1)
    row.strip:SetAnchor(TOPLEFT, row, TOPLEFT, 0, 1)
    row.cells = {}
    row:SetHandler("OnMouseEnter", function(control)
        if self.mode == "keyboard" then control.bg:SetColor(1, 1, 1, 0.12) end
    end)
    row:SetHandler("OnMouseExit", function(control) self:PaintRowBackground(control) end)
    row:SetHandler("OnMouseUp", function(control, button, upInside)
        if upInside and button == MOUSE_BUTTON_INDEX_LEFT and control.player then
            self:OnRowClicked(control.player)
        end
    end)
    self.rows[i] = row
    self:StyleRow(row, i)
    return row
end

function UI:PaintRowBackground(row)
    local selected = row.player and self.selectedKey == PlayerKey(row.player)
        and (self.mode == "gamepad" or self.detailsOpen)
    if selected then
        row.bg:SetColor(1, 0.85, 0.45, self.mode == "gamepad" and 0.28 or 0.22)
    elseif row.player and row.player.isLocal then
        row.bg:SetColor(0.31, 0.76, 0.97, 0.18)
    elseif row.index and row.index % 2 == 0 then
        row.bg:SetColor(1, 1, 1, 0.04)
    else
        row.bg:SetColor(1, 1, 1, 0)
    end
end

---------------------------------------------------------------------------
-- Selection and details
---------------------------------------------------------------------------
function UI:GetSelectedPlayer()
    local list = self.sortedPlayers or {}
    for i, p in ipairs(list) do
        if PlayerKey(p) == self.selectedKey then return p, i end
    end
    return nil
end

function UI:Select(p)
    self.selectedKey = p and PlayerKey(p) or nil
    for _, row in ipairs(self.rows) do
        if not row:IsHidden() then self:PaintRowBackground(row) end
    end
    if self.detailsOpen then self:RefreshDetails() end
end

function UI:MoveSelection(delta)
    local list = self.sortedPlayers or {}
    if #list == 0 then return end
    local _, idx = self:GetSelectedPlayer()
    idx = idx and zo_clamp(idx + delta, 1, #list) or 1
    self:Select(list[idx])
    if SOUNDS and SOUNDS.GAMEPAD_MENU_DOWN then PlaySound(SOUNDS.GAMEPAD_MENU_DOWN) end
end

-- PC: click a row to open its details, click it again (or X) to close.
function UI:OnRowClicked(p)
    if self.detailsOpen and self.selectedKey == PlayerKey(p) then
        self:CloseDetails()
    else
        self:Select(p)
        self:OpenDetails()
    end
end

-- Gamepad: A / Cross toggles details for the selected row.
function UI:ToggleDetails()
    if self.detailsOpen then
        self:CloseDetails()
    else
        if not self:GetSelectedPlayer() then self:MoveSelection(0) end
        self:OpenDetails()
    end
end

function UI:OpenDetails()
    if not self:GetSelectedPlayer() then return end
    self.detailsOpen = true
    self.details:SetHidden(false)
    self:RefreshDetails()
    for _, row in ipairs(self.rows) do self:PaintRowBackground(row) end
end

function UI:CloseDetails()
    self.detailsOpen = false
    if self.details then self.details:SetHidden(true) end
    for _, row in ipairs(self.rows) do self:PaintRowBackground(row) end
    if SBR.Gamepad then SBR.Gamepad:UpdateKeybinds() end
end

function UI:RefreshDetails()
    if not self.detailsOpen then return end
    local p = self:GetSelectedPlayer()
    if not p then
        self:CloseDetails()
        return
    end
    local s = self.style
    local title = p.characterName ~= "" and p.characterName or p.displayName or "?"
    if p.isLocal then title = "|c4FC3F7" .. title .. "|r" end
    self.detailsTitle:SetText(title)
    self.detailsBody:SetText(self:PlayerDetailsText(p))
    local h = self.detailsBody:GetTextHeight() + s.rowH + s.pad * 2 + 10
    self.details:SetHeight(math.max(h, 120))

    -- put the pane on whichever side of the panel has room
    local pane, tlw = self.details, self.control
    pane:ClearAnchors()
    local right = (tlw:GetRight() or 0) + s.detailsW + 8
    if right > (GuiRoot:GetWidth() or 1920) then
        pane:SetAnchor(TOPRIGHT, tlw, TOPLEFT, -8, 0)
    else
        pane:SetAnchor(TOPLEFT, tlw, TOPRIGHT, 8, 0)
    end
    if SBR.Gamepad then SBR.Gamepad:UpdateKeybinds() end
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

function UI:ToggleSortOrder()
    self.sort.desc = not self.sort.desc
    self:Refresh()
end

-- Gamepad left/right: move the sort to the previous/next column.
function UI:CycleSort(delta)
    local cols = self.columns
    if #cols == 0 then return end
    local idx = 1
    for i, c in ipairs(cols) do
        if c.key == self.sort.key then idx = i break end
    end
    idx = ((idx - 1 + delta) % #cols) + 1
    if cols[idx].key == "class" then idx = ((idx - 1 + delta) % #cols) + 1 end
    self.sort.key = cols[idx].key
    self.sort.desc = cols[idx].numeric == true
    self:Refresh()
end

function UI:ToggleGroupByTeam()
    SBR.sv.groupByTeam = not SBR.sv.groupByTeam
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

function UI:PlayerDetailsText(p)
    local lines = {}
    local function add(s) lines[#lines + 1] = s end
    local gamepad = self.mode == "gamepad"
    local iconSize = gamepad and 24 or 18
    add(string.format("%s%s", p.displayName or "", p.className and ("  |c999999" .. p.className .. "|r") or ""))
    if p.scores then
        local parts = {}
        for _, key in ipairs({ "SCORE", "KILL", "DEATH", "ASSISTS" }) do
            if p.scores[key] then parts[#parts + 1] = string.format("%s %s", SBR.Prettify(key), tostring(p.scores[key])) end
        end
        if #parts > 0 then add(table.concat(parts, "   ")) end
    end
    if p.medals and #p.medals > 0 then
        add(" ")
        add("|cD0C4A0Medals|r")
        for _, m in ipairs(p.medals) do
            local icon = (m.icon and m.icon ~= "") and zo_iconFormat(m.icon, iconSize, iconSize) or ""
            add(string.format("  %s %s x%d", icon, m.name or "?", m.count or 1))
        end
    end
    if p.fight then
        local f = p.fight
        add(" ")
        add("|cD0C4A0Fight data|r" .. (f.source and (" |c999999(" .. f.source .. ")|r") or ""))
        -- core stats always show; the rest only when non-zero, to keep the pane short on a TV
        local function stat(label, v, fmt, keepZero)
            if v ~= nil and (keepZero or v ~= 0) then
                add(string.format("  %s: %s", label, fmt and fmt(v) or SBR.FormatNumber(v)))
            end
        end
        local pct = function(v) return string.format("%.1f%%", v) end
        stat("Damage", f.damageDone, nil, true)
        stat("Healing", f.healingDone, nil, true)
        stat("DPS / HPS", f.dps, function(v) return SBR.FormatNumber(v) .. " / " .. SBR.FormatNumber(f.hps) end, true)
        stat("Damage taken", f.damageTaken, nil, true)
        stat("Healing taken", f.healingTaken, nil, true)
        stat("Shielded", f.damageShielded)
        stat("Blocked", f.damageBlocked)
        stat("Killing blows", f.killingBlows)
        stat("Deaths", f.deaths)
        stat("Interrupts", f.interrupts)
        stat("Interrupted", f.interrupted)
        stat("CC applied", f.ccApplied)
        stat("CC taken", f.ccTaken)
        stat("Crit rate", f.critRate, pct)
        stat("Heal crit rate", f.healCritRate, pct)
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
                    local icon = (a.icon and a.icon ~= "") and zo_iconFormat(a.icon, iconSize - 2, iconSize - 2) or ""
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
        add("|cD0C4A0You vs them|r")
        add(string.format("  You dealt %s, took %s", SBR.FormatNumber(v.damageFromYou), SBR.FormatNumber(v.damageToYou)))
        if (v.killedByYou or 0) > 0 or (v.killedYou or 0) > 0 then
            add(string.format("  You killed them %d, they killed you %d", v.killedByYou or 0, v.killedYou or 0))
        end
        if (v.healedByYou or 0) > 0 then add("  You healed them " .. SBR.FormatNumber(v.healedByYou)) end
        if (v.healedYou or 0) > 0 then add("  They healed you " .. SBR.FormatNumber(v.healedYou)) end
    end
    if p.isLocal then
        local match = self:GetViewedMatch()
        local deaths = match and match.lf and match.lf.deaths
        if deaths and #deaths > 0 then
            add(" ")
            add(string.format("Deaths with recap: %d (see the kill feed)", #deaths))
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
    local s = self.style
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
        if self.mode == "gamepad" and self.sort.key == c.key then h:SetColor(1, 1, 1, 1)
        elseif c.fight then h:SetColor(1, 0.85, 0.45, 1)
        elseif c.vs then h:SetColor(0.6, 0.85, 1, 1)
        else h:SetColor(0.85, 0.85, 0.85, 1) end
        c.x = x
        x = x + c.width + 6
    end
    for i = #cols + 1, #self.headers do self.headers[i]:SetHidden(true) end
    local contentWidth = math.max(x, self.mode == "gamepad" and 900 or 640)

    local players = match and self:SortedPlayers(match) or {}
    self.sortedPlayers = players
    if self.mode == "gamepad" and not self:GetSelectedPlayer() and players[1] then
        -- keep a cursor on screen; start on your own row
        local start = players[1]
        for _, p in ipairs(players) do
            if p.isLocal then start = p break end
        end
        self.selectedKey = PlayerKey(start)
    end

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
                cell = CreateLabel(row, s.fontRow)
                cell:SetHeight(s.rowH)
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

    local listH = math.max(#players, 2) * s.rowH
    self.headerRow:SetWidth(contentWidth)
    self.list:SetDimensions(contentWidth, listH)
    self.control:SetDimensions(contentWidth + s.pad * 2, s.topH + s.headerH + 2 + listH + s.footerH + s.pad)

    -- footer state
    local history = SBR.MatchLog:GetHistory()
    if self.viewIndex then
        self.viewLabel:SetText(string.format("History %d / %d", self.viewIndex, #history))
    else
        self.viewLabel:SetText(SBR.MatchLog:GetCurrent() and "|c66FF66Live|r" or (#history > 0 and "Last match" or ""))
    end
    self.groupButton:SetText(SBR.sv.groupByTeam and "By team: on" or "By team: off")

    self:RefreshDetails()
    if SBR.Gamepad then SBR.Gamepad:UpdateKeybinds() end
end

function UI:OnDataChanged()
    if self.viewIndex == nil then self:Refresh() end
end

---------------------------------------------------------------------------
-- Visibility
---------------------------------------------------------------------------
function UI:Show(pinned)
    self:Create()
    if SBR.IsGamepad() then
        SBR.Gamepad:Open()
        return
    end
    if self.mode ~= "keyboard" then self:ApplyStyle("keyboard") end
    if pinned then self.pinned = true end
    self:ApplyPosition()
    self.control:SetHidden(false)
    if SBR.MatchLog:GetCurrent() then SBR.MatchLog:Snapshot() end
    self:Refresh()
end

-- Gamepad scene shown/hidden (UI/Gamepad.lua drives these).
function UI:OnGamepadShown()
    self:ApplyStyle("gamepad")
    if SBR.MatchLog:GetCurrent() then SBR.MatchLog:Snapshot() end
    self:Refresh()
end

function UI:OnGamepadHidden()
    self:CloseDetails()
    self:ApplyStyle("keyboard")
end

function UI:Hide(force)
    if not self.control then return end
    if self.mode == "gamepad" then
        SBR.Gamepad:Close()
        return
    end
    if self.pinned and not force then return end
    self.pinned = false
    self:CloseDetails()
    self.control:SetHidden(true)
    HideTooltip()
end

function UI:Toggle()
    if self:IsShown() then
        self:Hide(true)
    else
        self:Show(true)
        -- keyboard: needs the cursor when opened outside the native scoreboard
        if self.mode == "keyboard" and not SCENE_MANAGER:IsInUIMode() then SCENE_MANAGER:SetInUIMode(true) end
    end
end

function UI:IsShown()
    return self.control ~= nil and not self.control:IsHidden()
end

-- Called by the hook when the native keyboard scoreboard opens / closes.
function UI:OnNativeShown()
    if not SBR.sv.autoShowWithScoreboard then return end
    self:Show(false)
end

function UI:OnNativeHidden()
    if self.mode ~= "keyboard" then return end
    self:Hide(false)
    self:ApplyPosition()
end
