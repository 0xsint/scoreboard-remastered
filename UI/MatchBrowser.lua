-- Match database browser (gamepad screen).
--
-- ESO's standard gamepad layout: a list of matches on the left, a detail card on
-- the right. The card shows the selected match (result banner, team scores, stat
-- tiles, medals with icons, top abilities with icons and bars, fight highlights)
-- or, with Y / Triangle, your lifetime record (win rate, K/D, bests, per-map and
-- per-class records).
--
--   Up / Down            select a match          Left / Right   change the filter
--   A / Cross            open its full scoreboard X / Square    change the sort
--   Y / Triangle         match card / lifetime    LB / RB        page up / down
--   B / Circle           back
local SBR = ScoreboardRemastered
local MB = { sceneName = "scoreboardRemasteredHistory", filter = 1, sort = 1, selected = 1, offset = 0, card = "match" }
SBR.MatchBrowser = MB

local WM = WINDOW_MANAGER
local VISIBLE_ROWS = 8
local ROW_H = 86
local LIST_W = 760
local CARD_W = 980

-- Item icons (class, medals, abilities) come from the game API. These are ESO
-- interface art used for the stat tiles; each sits on a coloured badge with a
-- text label, so a moved path only loses the picture.
local ICONS = {
    kills = "EsoUI/Art/TreeIcons/achievements_indexIcon_combat_up.dds",
    deaths = "EsoUI/Art/DeathRecap/deathRecap_killingBlow_icon.dds",
    assists = "EsoUI/Art/TreeIcons/achievements_indexIcon_ava_up.dds",
    damage = "EsoUI/Art/TreeIcons/achievements_indexIcon_combat_up.dds",
    healing = "EsoUI/Art/TreeIcons/achievements_indexIcon_skills_up.dds",
    score = "EsoUI/Art/TreeIcons/achievements_indexIcon_summary_up.dds",
    highlight = "EsoUI/Art/Miscellaneous/listItem_highlight.dds",
    divider = "EsoUI/Art/Miscellaneous/horizontalDivider.dds",
}

local RESULT = {
    won = { text = "Victory", rgb = { 0.42, 0.86, 0.45 } },
    lost = { text = "Defeat", rgb = { 0.92, 0.38, 0.35 } },
    tie = { text = "Draw", rgb = { 0.85, 0.80, 0.55 } },
    left = { text = "Left early", rgb = { 0.62, 0.62, 0.62 } },
    unknown = { text = "Unfinished", rgb = { 0.62, 0.62, 0.62 } },
}

local TILE_COLORS = {
    kills = { 0.85, 0.45, 0.32 }, deaths = { 0.62, 0.62, 0.66 }, assists = { 0.48, 0.70, 0.88 },
    damage = { 0.93, 0.63, 0.30 }, healing = { 0.45, 0.80, 0.52 }, score = { 0.90, 0.78, 0.45 },
}

---------------------------------------------------------------------------
-- small control helpers
---------------------------------------------------------------------------
local n = 0
local function Name(kind)
    n = n + 1
    return "SBR_MB_" .. kind .. n
end

local function Font(...)
    for i = 1, select("#", ...) do
        local f = select(i, ...)
        if _G[f] ~= nil then return f end
    end
    return "ZoFontGame"
end
local F = {}
local function Fonts()
    if F.ready then return F end
    F.huge = Font("ZoFontGamepadBold54", "ZoFontGamepadBold48", "ZoFontGamepadBold42", "ZoFontGamepad42", "ZoFontWinH1")
    F.title = Font("ZoFontGamepadBold34", "ZoFontGamepad34", "ZoFontWinH2")
    F.big = Font("ZoFontGamepadBold27", "ZoFontGamepad27", "ZoFontWinH3")
    F.text = Font("ZoFontGamepad27", "ZoFontGamepad25", "ZoFontGame")
    F.small = Font("ZoFontGamepad22", "ZoFontGame")
    F.tiny = Font("ZoFontGamepad18", "ZoFontGamepad20", "ZoFontGameSmall")
    F.ready = true
    return F
end

local function Label(parent, font, rgb, align)
    local l = WM:CreateControl(Name("L"), parent, CT_LABEL)
    l:SetFont(font)
    l:SetColor(rgb and rgb[1] or 1, rgb and rgb[2] or 1, rgb and rgb[3] or 1, 1)
    l:SetHorizontalAlignment(align or TEXT_ALIGN_LEFT)
    l:SetVerticalAlignment(TEXT_ALIGN_CENTER)
    l:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
    return l
end

local function Upper(l)
    if MODIFY_TEXT_TYPE_UPPERCASE and l.SetModifyTextType then l:SetModifyTextType(MODIFY_TEXT_TYPE_UPPERCASE) end
    return l
end

local function Tex(parent, r, g, b, a, path)
    local t = WM:CreateControl(Name("T"), parent, CT_TEXTURE)
    if path then t:SetTexture(path) end
    t:SetColor(r, g, b, a)
    return t
end

local function Backdrop(parent)
    for _, v in ipairs({ "ZO_DefaultBackdrop_Gamepad", "ZO_DefaultBackdrop" }) do
        local ok, bd = pcall(WM.CreateControlFromVirtual, WM, Name("BG"), parent, v)
        if ok and bd then
            bd:SetAnchorFill(parent)
            return bd
        end
    end
    local t = Tex(parent, 0.04, 0.05, 0.06, 0.94)
    t:SetAnchorFill(parent)
    return t
end

local function Divider(parent, anchorTo, offsetY, width)
    local line = Tex(parent, 1, 1, 1, 0.12)
    line:SetDimensions(width, 1)
    line:SetAnchor(TOPLEFT, anchorTo, BOTTOMLEFT, 0, offsetY)
    local art = Tex(parent, 1, 1, 1, 0.9, ICONS.divider)
    art:SetDimensions(width + 40, 4)
    art:SetAnchor(CENTER, line, CENTER, 0, 0)
    return line
end

local function Icon(path, size)
    if type(path) ~= "string" or path == "" then return "" end
    return zo_iconFormat(path, size, size)
end

local function Paint(c, rgb, a) c:SetColor(rgb[1], rgb[2], rgb[3], a or 1) end

local DIM = { 0.66, 0.66, 0.66 }
local WHITE = { 1, 1, 1 }
local GOLD = { 0.90, 0.78, 0.45 }
local NORMAL = { 0.77, 0.76, 0.62 }

---------------------------------------------------------------------------
-- construction
---------------------------------------------------------------------------
function MB:Create()
    if self.control then return end
    Fonts()
    local tlw = WM:CreateTopLevelWindow("ScoreboardRemasteredMatchBrowser")
    self.control = tlw
    tlw:SetHidden(true)
    tlw:SetAnchorFill(GuiRoot)
    tlw:SetDrawLayer(DL_OVERLAY)
    tlw:SetDrawTier(DT_HIGH)

    local dim = Tex(tlw, 0, 0, 0, 0.6)
    dim:SetAnchorFill(tlw)

    self:CreateList(tlw)
    self:CreateCard(tlw)
end

function MB:CreateList(tlw)
    local list = WM:CreateControl(Name("List"), tlw, CT_CONTROL)
    list:SetAnchor(TOPLEFT, tlw, TOPLEFT, 70, 60)
    list:SetDimensions(LIST_W, 160 + VISIBLE_ROWS * ROW_H + 70)
    Backdrop(list)
    self.list = list

    self.listTitle = Upper(Label(list, F.title, WHITE))
    self.listTitle:SetAnchor(TOPLEFT, list, TOPLEFT, 28, 22)
    self.listTitle:SetDimensions(LIST_W - 56, 40)
    self.listTitle:SetText("Match database")

    self.listSub = Label(list, F.small, NORMAL)
    self.listSub:SetAnchor(TOPLEFT, self.listTitle, BOTTOMLEFT, 0, 2)
    self.listSub:SetDimensions(LIST_W - 56, 28)

    -- lifetime chips
    self.chips = {}
    for i = 1, 3 do
        local chip = WM:CreateControl(Name("Chip"), list, CT_CONTROL)
        chip:SetDimensions((LIST_W - 56 - 20) / 3, 52)
        chip:SetAnchor(TOPLEFT, self.listSub, BOTTOMLEFT, (i - 1) * ((LIST_W - 56 - 20) / 3 + 10), 10)
        local bg = Tex(chip, 1, 1, 1, 0.06)
        bg:SetAnchorFill(chip)
        chip.value = Label(chip, F.big, WHITE, TEXT_ALIGN_CENTER)
        chip.value:SetAnchor(TOP, chip, TOP, 0, 2)
        chip.value:SetDimensions(chip:GetWidth(), 30)
        chip.label = Upper(Label(chip, F.tiny, DIM, TEXT_ALIGN_CENTER))
        chip.label:SetAnchor(TOP, chip.value, BOTTOM, 0, -2)
        chip.label:SetDimensions(chip:GetWidth(), 20)
        self.chips[i] = chip
    end

    local top = 160
    self.rowsTop = top
    self.rows = {}
    for i = 1, VISIBLE_ROWS do
        local row = WM:CreateControl(Name("Row"), list, CT_CONTROL)
        row:SetDimensions(LIST_W - 40, ROW_H - 6)
        row:SetAnchor(TOPLEFT, list, TOPLEFT, 20, top + (i - 1) * ROW_H)
        row.bg = Tex(row, 1, 1, 1, 0)
        row.bg:SetAnchorFill(row)
        row.glow = Tex(row, 1, 1, 1, 0.9, ICONS.highlight)
        row.glow:SetAnchorFill(row)
        row.bar = Tex(row, 1, 1, 1, 1)
        row.bar:SetDimensions(6, ROW_H - 6)
        row.bar:SetAnchor(LEFT, row, LEFT, 0, 0)
        row.class = WM:CreateControl(Name("Cls"), row, CT_TEXTURE)
        row.class:SetDimensions(44, 44)
        row.class:SetAnchor(LEFT, row, LEFT, 20, 0)
        row.map = Label(row, F.big, WHITE)
        row.map:SetAnchor(TOPLEFT, row, TOPLEFT, 78, 8)
        row.map:SetDimensions(390, 34)
        row.meta = Label(row, F.tiny, DIM)
        row.meta:SetAnchor(TOPLEFT, row.map, BOTTOMLEFT, 0, 0)
        row.meta:SetDimensions(390, 26)
        row.kda = Label(row, F.big, WHITE, TEXT_ALIGN_RIGHT)
        row.kda:SetAnchor(TOPRIGHT, row, TOPRIGHT, -16, 8)
        row.kda:SetDimensions(220, 34)
        row.result = Upper(Label(row, F.tiny, WHITE, TEXT_ALIGN_RIGHT))
        row.result:SetAnchor(TOPRIGHT, row.kda, BOTTOMRIGHT, 0, 0)
        row.result:SetDimensions(220, 26)
        self.rows[i] = row
    end

    self.moreAbove = Label(list, F.tiny, DIM, TEXT_ALIGN_CENTER)
    self.moreAbove:SetAnchor(BOTTOM, self.rows[1], TOP, 0, 2)
    self.moreAbove:SetDimensions(LIST_W - 40, 18)
    self.moreBelow = Label(list, F.tiny, DIM, TEXT_ALIGN_CENTER)
    self.moreBelow:SetAnchor(TOP, self.rows[VISIBLE_ROWS], BOTTOM, 0, 6)
    self.moreBelow:SetDimensions(LIST_W - 40, 22)

    self.empty = Label(list, F.text, DIM, TEXT_ALIGN_CENTER)
    self.empty:SetAnchor(TOP, list, TOP, 0, top + 120)
    self.empty:SetDimensions(LIST_W - 80, 120)
    self.empty:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
end

function MB:CreateCard(tlw)
    local card = WM:CreateControl(Name("Card"), tlw, CT_CONTROL)
    card:SetAnchor(TOPLEFT, self.list, TOPRIGHT, 30, 0)
    card:SetDimensions(CARD_W, self.list:GetHeight())
    Backdrop(card)
    self.card = card
    local inner = CARD_W - 64

    -- banner
    self.banner = Tex(card, 1, 1, 1, 0.12)
    self.banner:SetAnchor(TOPLEFT, card, TOPLEFT, 0, 0)
    self.banner:SetDimensions(CARD_W, 8)
    self.result = Upper(Label(card, F.huge, WHITE))
    self.result:SetAnchor(TOPLEFT, card, TOPLEFT, 32, 26)
    self.result:SetDimensions(inner, 60)
    self.title = Label(card, F.title, WHITE)
    self.title:SetAnchor(TOPLEFT, self.result, BOTTOMLEFT, 0, 0)
    self.title:SetDimensions(inner, 40)
    self.meta = Label(card, F.small, NORMAL)
    self.meta:SetAnchor(TOPLEFT, self.title, BOTTOMLEFT, 0, 2)
    self.meta:SetDimensions(inner, 30)
    self.teams = Upper(Label(card, F.big, WHITE, TEXT_ALIGN_RIGHT))
    self.teams:SetAnchor(TOPRIGHT, card, TOPRIGHT, -32, 34)
    self.teams:SetDimensions(480, 36)
    local div = Divider(card, self.meta, 14, inner)

    -- six stat tiles, 3 x 2
    self.tiles = {}
    local tileW, tileH = (inner - 2 * 16) / 3, 96
    for i = 1, 6 do
        local col, rowIdx = (i - 1) % 3, math.floor((i - 1) / 3)
        local tile = WM:CreateControl(Name("Tile"), card, CT_CONTROL)
        tile:SetDimensions(tileW, tileH)
        tile:SetAnchor(TOPLEFT, div, BOTTOMLEFT, col * (tileW + 16), 18 + rowIdx * (tileH + 14))
        tile.bg = Tex(tile, 1, 1, 1, 0.05)
        tile.bg:SetAnchorFill(tile)
        tile.accent = Tex(tile, 1, 1, 1, 1)
        tile.accent:SetDimensions(4, tileH)
        tile.accent:SetAnchor(LEFT, tile, LEFT, 0, 0)
        tile.badge = Tex(tile, 1, 1, 1, 0.22)
        tile.badge:SetDimensions(56, 56)
        tile.badge:SetAnchor(LEFT, tile, LEFT, 18, 0)
        tile.badgeText = Upper(Label(tile, F.small, WHITE, TEXT_ALIGN_CENTER))
        tile.badgeText:SetAnchor(CENTER, tile.badge, CENTER, 0, 0)
        tile.badgeText:SetDimensions(56, 56)
        tile.icon = WM:CreateControl(Name("Ico"), tile, CT_TEXTURE)
        tile.icon:SetDimensions(48, 48)
        tile.icon:SetAnchor(CENTER, tile.badge, CENTER, 0, 0)
        tile.value = Label(tile, F.title, WHITE)
        tile.value:SetAnchor(TOPLEFT, tile.badge, TOPRIGHT, 16, -6)
        tile.value:SetDimensions(tileW - 100, 40)
        tile.label = Upper(Label(tile, F.tiny, DIM))
        tile.label:SetAnchor(TOPLEFT, tile.value, BOTTOMLEFT, 0, 0)
        tile.label:SetDimensions(tileW - 100, 22)
        self.tiles[i] = tile
    end

    self.rank = Label(card, F.small, NORMAL)
    self.rank:SetAnchor(TOPLEFT, self.tiles[4], BOTTOMLEFT, 0, 16)
    self.rank:SetDimensions(inner, 30)

    -- two columns: medals (left), top abilities (right)
    local colW = (inner - 30) / 2
    self.sectionA = Upper(Label(card, F.small, GOLD))
    self.sectionA:SetAnchor(TOPLEFT, self.rank, BOTTOMLEFT, 0, 18)
    self.sectionA:SetDimensions(colW, 28)
    local divA = Divider(card, self.sectionA, 2, colW)
    self.sectionB = Upper(Label(card, F.small, GOLD))
    self.sectionB:SetAnchor(TOPLEFT, self.sectionA, TOPRIGHT, 30, 0)
    self.sectionB:SetDimensions(colW, 28)
    local divB = Divider(card, self.sectionB, 2, colW)

    -- medals: 6 icons with counts and names
    self.medals = {}
    local medalW = colW / 3
    for i = 1, 6 do
        local m = WM:CreateControl(Name("Medal"), card, CT_CONTROL)
        m:SetDimensions(medalW, 104)
        m:SetAnchor(TOPLEFT, divA, BOTTOMLEFT, ((i - 1) % 3) * medalW, 12 + math.floor((i - 1) / 3) * 110)
        m.icon = WM:CreateControl(Name("MIco"), m, CT_TEXTURE)
        m.icon:SetDimensions(56, 56)
        m.icon:SetAnchor(TOP, m, TOP, 0, 0)
        m.count = Label(m, F.small, WHITE, TEXT_ALIGN_RIGHT)
        m.count:SetAnchor(BOTTOMRIGHT, m.icon, BOTTOMRIGHT, 14, 6)
        m.count:SetDimensions(40, 24)
        m.name = Label(m, F.tiny, NORMAL, TEXT_ALIGN_CENTER)
        m.name:SetAnchor(TOP, m.icon, BOTTOM, 0, 4)
        m.name:SetDimensions(medalW - 8, 40)
        self.medals[i] = m
    end

    -- ability rows (also used for map / class records on the lifetime card)
    self.bars = {}
    for i = 1, 5 do
        local r = WM:CreateControl(Name("Bar"), card, CT_CONTROL)
        r:SetDimensions(colW, 42)
        r:SetAnchor(TOPLEFT, divB, BOTTOMLEFT, 0, 12 + (i - 1) * 46)
        r.icon = WM:CreateControl(Name("BIco"), r, CT_TEXTURE)
        r.icon:SetDimensions(36, 36)
        r.icon:SetAnchor(LEFT, r, LEFT, 0, 0)
        r.name = Label(r, F.tiny, WHITE)
        r.name:SetAnchor(TOPLEFT, r, TOPLEFT, 46, -2)
        r.name:SetDimensions(colW - 150, 22)
        r.value = Label(r, F.tiny, WHITE, TEXT_ALIGN_RIGHT)
        r.value:SetAnchor(TOPRIGHT, r, TOPRIGHT, 0, -2)
        r.value:SetDimensions(100, 22)
        r.track = Tex(r, 1, 1, 1, 0.08)
        r.track:SetDimensions(colW - 46, 8)
        r.track:SetAnchor(BOTTOMLEFT, r, BOTTOMLEFT, 46, -4)
        r.fill = Tex(r, 1, 1, 1, 1)
        r.fill:SetHeight(8)
        r.fill:SetAnchor(LEFT, r.track, LEFT, 0, 0)
        self.bars[i] = r
    end

    self.highlights = Label(card, F.small, NORMAL)
    self.highlights:SetAnchor(BOTTOMLEFT, card, BOTTOMLEFT, 32, -70)
    self.highlights:SetDimensions(inner, 30)
    self.footer = Label(card, F.tiny, DIM)
    self.footer:SetAnchor(BOTTOMLEFT, card, BOTTOMLEFT, 32, -34)
    self.footer:SetDimensions(inner, 26)
end

---------------------------------------------------------------------------
-- data
---------------------------------------------------------------------------
function MB:FilterKey() return SBR.MatchDB.FILTERS[self.filter] end
function MB:SortKey() return SBR.MatchDB.SORTS[self.sort] end

function MB:Reload()
    local DB = SBR.MatchDB
    local ref = self.items and self.items[self.selected] or DB:Query("all", "newest")[1]
    self.ref = ref
    self.items = DB:Query(self:FilterKey(), self:SortKey(), ref)
    self.selected = zo_clamp(self.selected, 1, math.max(1, #self.items))
    self:ClampScroll()
end

function MB:ClampScroll()
    if self.selected <= self.offset then self.offset = self.selected - 1 end
    if self.selected > self.offset + VISIBLE_ROWS then self.offset = self.selected - VISIBLE_ROWS end
    self.offset = zo_clamp(self.offset, 0, math.max(0, #self.items - VISIBLE_ROWS))
end

local function KDAText(r)
    return string.format("%s / %s / %s", tostring(r.kills or "-"), tostring(r.deaths or "-"), tostring(r.assists or "-"))
end

local function ShortDate(ts)
    return SBR.FormatTimestamp(ts)
end

---------------------------------------------------------------------------
-- render
---------------------------------------------------------------------------
function MB:Render()
    local DB = SBR.MatchDB
    local all = DB:GetRecords()
    local life = DB:Aggregate(all)

    local filterLabel = DB.FILTER_LABELS[self:FilterKey()]
    if self:FilterKey() == "map" and self.ref then filterLabel = self.ref.map end
    if self:FilterKey() == "class" and self.ref then filterLabel = self.ref.className or filterLabel end
    self.listSub:SetText(string.format("%s  |c999999•|r  Sorted by %s  |c999999•|r  %d of %d",
        filterLabel, DB.SORT_LABELS[self:SortKey()], #self.items, #all))

    local chipData = {
        { life.winRate and string.format("%.0f%%", life.winRate) or "-", "Win rate" },
        { string.format("%.2f", life.kd), "K/D" },
        { life.streak > 0 and string.format("%s%d", life.streakKind == "won" and "W" or "L", life.streak) or "-", "Streak" },
    }
    for i, chip in ipairs(self.chips) do
        chip.value:SetText(chipData[i][1])
        chip.label:SetText(chipData[i][2])
    end

    for i, row in ipairs(self.rows) do
        local r = self.items[self.offset + i]
        row:SetHidden(r == nil)
        if r then
            local selected = (self.offset + i) == self.selected
            local res = RESULT[r.result] or RESULT.unknown
            Paint(row.bar, res.rgb)
            row.bg:SetColor(1, 1, 1, selected and 0.10 or ((i % 2 == 0) and 0.03 or 0))
            row.glow:SetHidden(not selected)
            if r.classIcon then row.class:SetTexture(r.classIcon) end
            row.class:SetHidden(r.classIcon == nil)
            row.class:SetAlpha(selected and 1 or 0.7)
            row.map:SetText(r.map)
            Paint(row.map, selected and WHITE or { 0.85, 0.85, 0.85 })
            row.meta:SetText(string.format("%s  •  %s  •  %s", r.gameType or "Battleground", ShortDate(r.at), SBR.FormatDuration(r.duration)))
            row.kda:SetText(KDAText(r))
            Paint(row.kda, selected and WHITE or { 0.80, 0.80, 0.80 })
            row.result:SetText(res.text .. "  " .. SBR.FormatNumber(r.damage) .. " dmg")
            Paint(row.result, res.rgb)
        end
    end
    self.moreAbove:SetText(self.offset > 0 and string.format("%d more above", self.offset) or "")
    local below = #self.items - self.offset - VISIBLE_ROWS
    self.moreBelow:SetText(below > 0 and string.format("%d more below", below) or "")
    self.empty:SetHidden(#self.items > 0)
    self.empty:SetText(#all == 0 and "No matches yet.\nFinish a battleground and it shows up here."
        or "No matches match this filter.\nPress Left or Right to change it.")

    if self.card == "life" then
        self:RenderLifetime(life)
    else
        self:RenderMatch(self.items[self.selected])
    end
    if self.keybinds then KEYBIND_STRIP:UpdateKeybindButtonGroup(self.keybinds) end
end

function MB:SetTile(i, key, value, label, badge)
    local t = self.tiles[i]
    local rgb = TILE_COLORS[key] or GOLD
    Paint(t.accent, rgb)
    t.badge:SetColor(rgb[1], rgb[2], rgb[3], 0.22)
    t.badgeText:SetText(badge or "")
    t.icon:SetTexture(ICONS[key] or "")
    t.icon:SetHidden(ICONS[key] == nil)
    t.value:SetText(value)
    t.label:SetText(label)
end

function MB:ShowMedals(list)
    for i, m in ipairs(self.medals) do
        local md = list[i]
        m:SetHidden(md == nil)
        if md then
            m.icon:SetTexture(md.icon or "")
            m.count:SetText((md.count or 1) > 1 and ("x" .. md.count) or "")
            m.name:SetText(md.name or "")
        end
    end
end

-- rows: { icon, name, value text, fraction 0..1, rgb }
function MB:ShowBars(rows)
    for i, b in ipairs(self.bars) do
        local d = rows[i]
        b:SetHidden(d == nil)
        if d then
            b.icon:SetTexture(d.icon or "")
            b.icon:SetHidden(not d.icon or d.icon == "")
            b.name:SetText(d.name or "")
            b.value:SetText(d.value or "")
            local w = (b.track:GetWidth() or 0) * zo_clamp(d.fraction or 0, 0.02, 1)
            b.fill:SetWidth(w)
            Paint(b.fill, d.rgb or GOLD)
        end
    end
end

function MB:RenderMatch(r)
    if not r then
        self.result:SetText("")
        self.title:SetText("")
        self.meta:SetText("")
        self.teams:SetText("")
        for i = 1, 6 do self:SetTile(i, "score", "-", "", "") end
        self:ShowMedals({})
        self:ShowBars({})
        self.rank:SetText("")
        self.highlights:SetText("")
        self.footer:SetText("")
        self.sectionA:SetText("")
        self.sectionB:SetText("")
        return
    end
    local res = RESULT[r.result] or RESULT.unknown
    Paint(self.banner, res.rgb, 0.85)
    self.result:SetText(res.text)
    Paint(self.result, res.rgb)
    self.title:SetText(r.map)
    self.meta:SetText(string.format("%s%s  •  %s  •  %s  •  %s %s",
        r.gameType or "Battleground", r.teamSize and string.format(" %dv%d", r.teamSize, r.teamSize) or "",
        SBR.FormatDuration(r.duration), ShortDate(r.at), Icon(r.classIcon, 26), r.character or ""))

    local parts = {}
    for _, t in ipairs(r.teams or {}) do
        local marker = t.id == r.localTeam and "*" or ""
        parts[#parts + 1] = SBR.Colorize(t.color, string.format("%s%s %s", marker, t.name or t.id, tostring(t.score or "-")))
    end
    self.teams:SetText(table.concat(parts, "  |c777777vs|r  "))

    self:SetTile(1, "kills", tostring(r.kills or "-"), "Kills", "K")
    self:SetTile(2, "deaths", tostring(r.deaths or "-"), "Deaths", "D")
    self:SetTile(3, "assists", tostring(r.assists or "-"), "Assists", "A")
    self:SetTile(4, "damage", SBR.FormatNumber(r.damage), "Damage done", "DMG")
    self:SetTile(5, "healing", SBR.FormatNumber(r.healing), "Healing done", "HEAL")
    self:SetTile(6, "score", SBR.FormatNumber(r.score), "Score", "PTS")

    local rank = {}
    if r.teamRank then rank[#rank + 1] = string.format("|cFFFFFF#%d|r on your team", r.teamRank) end
    if r.rank then rank[#rank + 1] = string.format("|cFFFFFF#%d|r of %d overall", r.rank, r.players or 0) end
    if r.mvp then
        rank[#rank + 1] = r.mvp.isYou and "|cE8C873Match MVP: you|r" or ("MVP: " .. (r.mvp.name or "?"))
    end
    rank[#rank + 1] = string.format("K/D/A ratio |cFFFFFF%.2f|r", SBR.MatchDB.KDA(r))
    self.rank:SetText(table.concat(rank, "   |c777777•|r   "))

    self.sectionA:SetText(string.format("Medals  (%d)", r.medalCount or 0))
    self:ShowMedals(r.medals or {})

    self.sectionB:SetText("Top abilities")
    local rows, max = {}, 0
    for _, a in ipairs(r.top or {}) do max = math.max(max, a.damage or 0) end
    for _, a in ipairs(r.top or {}) do
        rows[#rows + 1] = { icon = a.icon, name = a.name, value = SBR.FormatNumber(a.damage),
                            fraction = max > 0 and a.damage / max or 0, rgb = TILE_COLORS.damage }
    end
    self:ShowBars(rows)

    local hl = {}
    if r.dps then hl[#hl + 1] = "DPS |cFFFFFF" .. SBR.FormatNumber(r.dps) .. "|r" end
    if r.maxHit then hl[#hl + 1] = string.format("Max hit |cFFFFFF%s|r%s", SBR.FormatNumber(r.maxHit), r.maxHitAbility and (" (" .. r.maxHitAbility .. ")") or "") end
    if r.critRate then hl[#hl + 1] = string.format("Crit |cFFFFFF%.0f%%|r", r.critRate) end
    if r.fights then hl[#hl + 1] = string.format("|cFFFFFF%d|r fights", r.fights) end
    if r.recaps and r.recaps > 0 then hl[#hl + 1] = string.format("|cFFFFFF%d|r death recaps", r.recaps) end
    if r.flags and r.flags > 0 then hl[#hl + 1] = string.format("|cFFFFFF%d|r flags", r.flags) end
    self.highlights:SetText(table.concat(hl, "   |c777777•|r   "))

    local stored = SBR.MatchDB:FindMatch(r.id) ~= nil
    self.footer:SetText(stored and "Full scoreboard, kill feed and recaps stored. Press A to open."
        or string.format("Summary only: full scoreboards are kept for the last %d matches.", SBR.sv.maxHistory or 50))
end

function MB:RenderLifetime(a)
    Paint(self.banner, GOLD, 0.85)
    self.result:SetText("Lifetime")
    Paint(self.result, GOLD)
    self.title:SetText(string.format("%d matches  •  %d won  •  %d lost", a.matches, a.won, a.lost))
    local hours = a.seconds / 3600
    self.meta:SetText(string.format("%s in battlegrounds  •  %d kills, %d deaths, %d assists",
        hours >= 1 and string.format("%.1f hours", hours) or string.format("%d minutes", math.floor(a.seconds / 60)),
        a.kills, a.deaths, a.assists))
    self.teams:SetText("")

    self:SetTile(1, "score", a.winRate and string.format("%.0f%%", a.winRate) or "-", "Win rate", "WIN")
    self:SetTile(2, "kills", string.format("%.2f", a.kd), "Kill / death", "K/D")
    self:SetTile(3, "assists", tostring(a.mvps), "Times MVP", "MVP")
    self:SetTile(4, "damage", a.bestDamage and SBR.FormatNumber(a.bestDamage.damage) or "-", "Best damage", "DMG")
    self:SetTile(5, "healing", a.bestHealing and SBR.FormatNumber(a.bestHealing.healing) or "-", "Best healing", "HEAL")
    self:SetTile(6, "kills", a.bestKills and tostring(a.bestKills.kills) or "-", "Most kills", "K")

    local fav = a.favoriteMap
    self.rank:SetText(fav and string.format("Most played: |cFFFFFF%s|r (%d)   |c777777•|r   %d medals earned", fav.map, fav.played, a.medals) or "")

    -- left column: classes as icon tiles; right column: maps as win-rate bars
    self.sectionA:SetText("By class")
    local classes = {}
    for _, c in pairs(a.classes) do classes[#classes + 1] = c end
    table.sort(classes, function(x, y) return x.played > y.played end)
    local medalLike = {}
    for _, c in ipairs(classes) do
        medalLike[#medalLike + 1] = { icon = c.icon, count = nil,
            name = string.format("%s  %d-%d", c.className, c.won, c.played - c.won) }
    end
    self:ShowMedals(medalLike)

    self.sectionB:SetText("By map (win rate)")
    local maps = {}
    for _, m in pairs(a.maps) do maps[#maps + 1] = m end
    table.sort(maps, function(x, y) return x.played > y.played end)
    local rows = {}
    for _, m in ipairs(maps) do
        rows[#rows + 1] = { name = m.map, value = string.format("%d-%d", m.won, m.played - m.won),
                            fraction = m.played > 0 and m.won / m.played or 0,
                            rgb = (m.won / math.max(1, m.played)) >= 0.5 and RESULT.won.rgb or RESULT.lost.rgb }
    end
    self:ShowBars(rows)

    self.highlights:SetText(string.format("Damage |cFFFFFF%s|r   |c777777•|r   Healing |cFFFFFF%s|r   |c777777•|r   Medals |cFFFFFF%d|r",
        SBR.FormatNumber(a.damage), SBR.FormatNumber(a.healing), a.medals))
    self.footer:SetText(string.format("Database: %d match records (keeps up to %d).", #SBR.MatchDB:GetRecords(), SBR.sv.maxRecords or 500))
end

---------------------------------------------------------------------------
-- input
---------------------------------------------------------------------------
function MB:Move(delta)
    if #self.items == 0 then return end
    self.selected = zo_clamp(self.selected + delta, 1, #self.items)
    self:ClampScroll()
    if SOUNDS and SOUNDS.GAMEPAD_MENU_DOWN then PlaySound(SOUNDS.GAMEPAD_MENU_DOWN) end
    self:Render()
end

function MB:CycleFilter(delta)
    local DB = SBR.MatchDB
    self.ref = self.items[self.selected] or self.ref
    self.filter = ((self.filter - 1 + delta) % #DB.FILTERS) + 1
    self.items = DB:Query(self:FilterKey(), self:SortKey(), self.ref)
    self.selected, self.offset = 1, 0
    self:Render()
end

function MB:CycleSort()
    local DB = SBR.MatchDB
    self.sort = (self.sort % #DB.SORTS) + 1
    self.items = DB:Query(self:FilterKey(), self:SortKey(), self.ref)
    self.selected, self.offset = 1, 0
    self:Render()
end

function MB:OpenSelected()
    local r = self.items[self.selected]
    if not r then return end
    local _, index = SBR.MatchDB:FindMatch(r.id)
    if not index then return end
    SBR.Window.viewIndex = index
    SBR.Gamepad:Open()
end

function MB:UpdateDirectionalInput()
    local v = self.vertical:CheckMovement()
    local h = self.horizontal:CheckMovement()
    if v == MOVEMENT_CONTROLLER_MOVE_NEXT then self:Move(1)
    elseif v == MOVEMENT_CONTROLLER_MOVE_PREVIOUS then self:Move(-1) end
    if h == MOVEMENT_CONTROLLER_MOVE_NEXT then self:CycleFilter(1)
    elseif h == MOVEMENT_CONTROLLER_MOVE_PREVIOUS then self:CycleFilter(-1) end
end

function MB:BuildKeybinds()
    local DB = SBR.MatchDB
    local function selectedStored()
        local r = self.items and self.items[self.selected]
        return r ~= nil and DB:FindMatch(r.id) ~= nil
    end
    self.keybinds = {
        alignment = KEYBIND_STRIP_ALIGN_LEFT,
        { name = "View scoreboard", keybind = "UI_SHORTCUT_PRIMARY",
          callback = function() MB:OpenSelected() end, visible = selectedStored },
        { name = "Back", keybind = "UI_SHORTCUT_NEGATIVE", callback = function() MB:Close() end },
        { name = function() return "Sort: " .. DB.SORT_LABELS[MB:SortKey()] end, keybind = "UI_SHORTCUT_SECONDARY",
          callback = function() MB:CycleSort() end },
        { name = function() return MB.card == "life" and "Match details" or "Lifetime stats" end, keybind = "UI_SHORTCUT_TERTIARY",
          callback = function()
              MB.card = MB.card == "life" and "match" or "life"
              MB:Render()
          end },
        { name = "Page up", keybind = "UI_SHORTCUT_LEFT_SHOULDER", callback = function() MB:Move(-VISIBLE_ROWS) end,
          visible = function() return MB.selected > 1 end },
        { name = "Page down", keybind = "UI_SHORTCUT_RIGHT_SHOULDER", callback = function() MB:Move(VISIBLE_ROWS) end,
          visible = function() return MB.items and MB.selected < #MB.items end },
    }
end

---------------------------------------------------------------------------
-- scene
---------------------------------------------------------------------------
function MB:Init()
    if self.scene or not (ZO_Scene and SCENE_MANAGER and KEYBIND_STRIP and DIRECTIONAL_INPUT and ZO_MovementController) then return end
    self:Create()
    self.fragment = ZO_SimpleSceneFragment:New(self.control)
    local scene = ZO_Scene:New(self.sceneName, SCENE_MANAGER)
    scene:AddFragment(self.fragment)
    if FRAGMENT_GROUP then
        for _, group in ipairs({ FRAGMENT_GROUP.GAMEPAD_DRIVEN_UI_WINDOW, FRAGMENT_GROUP.GAMEPAD_KEYBIND_STRIP_GROUP }) do
            if group then scene:AddFragmentGroup(group) end
        end
    end
    scene:RegisterCallback("StateChange", function(_, newState)
        if newState == SCENE_SHOWN then MB:OnShown()
        elseif newState == SCENE_HIDING then MB:OnHiding() end
    end)
    self.scene = scene
    self.vertical = ZO_MovementController:New(MOVEMENT_CONTROLLER_DIRECTION_VERTICAL)
    self.horizontal = ZO_MovementController:New(MOVEMENT_CONTROLLER_DIRECTION_HORIZONTAL)
    self:BuildKeybinds()
end

function MB:IsShowing() return self.scene ~= nil and self.scene:IsShowing() end

function MB:Open()
    if not SBR.IsGamepad() then
        SBR.Print("The match database is a gamepad screen. Switch to gamepad mode (Settings > Gameplay), or use /sbr history.")
        return
    end
    self:Init()
    if self.scene and not self:IsShowing() then SCENE_MANAGER:Push(self.sceneName) end
end

function MB:Close()
    if self:IsShowing() then SCENE_MANAGER:HideCurrentScene() end
end

function MB:OnShown()
    self:Reload()
    self:Render()
    KEYBIND_STRIP:AddKeybindButtonGroup(self.keybinds)
    DIRECTIONAL_INPUT:Activate(self, self.control)
end

function MB:OnHiding()
    DIRECTIONAL_INPUT:Deactivate(self)
    KEYBIND_STRIP:RemoveKeybindButtonGroup(self.keybinds)
end
