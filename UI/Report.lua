-- Battle report: the story of one match on one screen, opened when you leave a
-- finished battleground (setting), from the records (A / double-click) or
-- /sbr report. Three tabs:
--   Overview    result, match balance (0-100), team totals, MVP, every player's title
--   Timeline    score over time, the damage race, kills per minute (momentum)
--   Your match  what you gained (AP, XP, Champion Points, AvA rank, medals), your
--               title and your profile against the best in the match
-- Same window on PC (mouse) and console (controller), laid out for a 1920 x 1080
-- canvas and scaled down on smaller ones. Data: Data/Report.lua.
local SBR = ScoreboardRemastered
local RP = { tab = "overview", keyboardSceneName = "scoreboardRemasteredReportKeyboard", gamepadSceneName = "scoreboardRemasteredReport" }
SBR.ReportUI = RP

local WM = WINDOW_MANAGER
local DESIGN_W, DESIGN_H = 1920, 1080
local PANEL_W, PANEL_H = 1560, 860
local PAD = 36
local BODY_TOP = 236
local TABS = { "overview", "timeline", "you" }
local TAB_LABEL = { overview = "Overview", timeline = "Timeline", you = "Your match" }

local RESULT = {
    won = { "Victory", { 0.42, 0.86, 0.45 } }, lost = { "Defeat", { 0.92, 0.38, 0.35 } },
    tie = { "Draw", { 0.85, 0.80, 0.55 } }, left = { "Left early", { 0.62, 0.62, 0.62 } },
    unknown = { "Unfinished", { 0.62, 0.62, 0.62 } },
}
local DIM, WHITE, GOLD, NORMAL = { 0.62, 0.62, 0.62 }, { 1, 1, 1 }, { 0.90, 0.78, 0.45 }, { 0.77, 0.76, 0.62 }

local function Num(v) return type(v) == "number" and v or 0 end
local function N(v) return v == nil and "-" or SBR.FormatNumber(v) end

---------------------------------------------------------------------------
-- control helpers
---------------------------------------------------------------------------
local count = 0
local function Name(kind) count = count + 1 return "SBR_RP_" .. kind .. count end

local function Font(...)
    for i = 1, select("#", ...) do
        local f = select(i, ...)
        if _G[f] ~= nil then return f end
    end
    return "ZoFontGame"
end
local F
local function Fonts()
    if F then return F end
    F = {
        huge = Font("ZoFontGamepadBold54", "ZoFontGamepadBold48", "ZoFontGamepad42", "ZoFontWinH1"),
        title = Font("ZoFontGamepadBold34", "ZoFontGamepad34", "ZoFontWinH2"),
        big = Font("ZoFontGamepadBold27", "ZoFontGamepad27", "ZoFontWinH3"),
        text = Font("ZoFontGamepad27", "ZoFontGamepad25", "ZoFontGame"),
        small = Font("ZoFontGamepad22", "ZoFontGame"),
        tiny = Font("ZoFontGamepad18", "ZoFontGamepad20", "ZoFontGameSmall"),
    }
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

local function Tex(parent, r, g, b, a)
    local t = WM:CreateControl(Name("T"), parent, CT_TEXTURE)
    t:SetColor(r, g, b, a)
    return t
end

local function Backdrop(parent)
    for _, v in ipairs({ "ZO_DefaultBackdrop_Gamepad", "ZO_DefaultBackdrop" }) do
        local ok, bd = pcall(WM.CreateControlFromVirtual, WM, Name("BG"), parent, v)
        if ok and bd then bd:SetAnchorFill(parent) return bd end
    end
    local t = Tex(parent, 0.04, 0.05, 0.06, 0.94)
    t:SetAnchorFill(parent)
    return t
end

local function Paint(c, rgb, a) c:SetColor(rgb[1], rgb[2], rgb[3], a or 1) end

local function TeamRGB(match, id)
    local t = match and match.teams and match.teams[id]
    return { SBR.HexToRGB(t and t.color or "BBBBBB") }
end

-- a reusable pool of child controls under `parent`, reset before each render
local function Pool(parent, make)
    local pool = { items = {}, used = 0 }
    function pool:Get()
        self.used = self.used + 1
        local c = self.items[self.used]
        if not c then
            c = make(parent)
            self.items[self.used] = c
        end
        c:SetHidden(false)
        c:ClearAnchors()
        return c
    end
    function pool:Reset()
        for i = 1, #self.items do self.items[i]:SetHidden(true) end
        self.used = 0
    end
    return pool
end

---------------------------------------------------------------------------
-- construction
---------------------------------------------------------------------------
function RP:Create()
    if self.control then return end
    local f = Fonts()
    local tlw = WM:CreateTopLevelWindow("ScoreboardRemasteredReport")
    self.control = tlw
    tlw:SetHidden(true)
    tlw:SetAnchorFill(GuiRoot)
    tlw:SetDrawLayer(DL_OVERLAY)
    tlw:SetDrawTier(DT_HIGH)
    local dim = Tex(tlw, 0, 0, 0, 0.6)
    dim:SetAnchorFill(tlw)

    local frame = WM:CreateControl(Name("Frame"), tlw, CT_CONTROL)
    frame:SetDimensions(DESIGN_W, DESIGN_H)
    frame:SetAnchor(CENTER, tlw, CENTER, 0, 0)
    self.frame = frame

    local panel = WM:CreateControl(Name("Panel"), frame, CT_CONTROL)
    panel:SetDimensions(PANEL_W, PANEL_H)
    panel:SetAnchor(TOPLEFT, frame, TOPLEFT, (DESIGN_W - PANEL_W) / 2, 50)
    panel:SetMouseEnabled(true)
    Backdrop(panel)
    self.panel = panel
    self.banner = Tex(panel, 1, 1, 1, 1)
    self.banner:SetDimensions(PANEL_W, 6)
    self.banner:SetAnchor(TOPLEFT, panel, TOPLEFT, 0, 0)

    -- header: result, map, details; balance on the right
    self.result = Upper(Label(panel, f.huge))
    self.result:SetDimensions(700, 60)
    self.result:SetAnchor(TOPLEFT, panel, TOPLEFT, PAD, 26)
    self.map = Label(panel, f.title, WHITE)
    self.map:SetDimensions(900, 40)
    self.map:SetAnchor(TOPLEFT, self.result, BOTTOMLEFT, 0, 2)
    self.details = Label(panel, f.small, NORMAL)
    self.details:SetDimensions(900, 28)
    self.details:SetAnchor(TOPLEFT, self.map, BOTTOMLEFT, 0, 2)

    self.balanceCaption = Upper(Label(panel, f.small, DIM, TEXT_ALIGN_RIGHT))
    self.balanceCaption:SetDimensions(360, 26)
    self.balanceCaption:SetAnchor(TOPRIGHT, panel, TOPRIGHT, -PAD, 30)
    self.balanceCaption:SetText("Match balance")
    self.balanceValue = Label(panel, f.huge, WHITE, TEXT_ALIGN_RIGHT)
    self.balanceValue:SetDimensions(200, 60)
    self.balanceValue:SetAnchor(TOPRIGHT, self.balanceCaption, BOTTOMRIGHT, 0, 0)
    self.balanceText = Label(panel, f.big, WHITE, TEXT_ALIGN_RIGHT)
    self.balanceText:SetDimensions(240, 34)
    self.balanceText:SetAnchor(RIGHT, self.balanceValue, LEFT, -14, 4)
    self.balanceTrack = Tex(panel, 1, 1, 1, 0.12)
    self.balanceTrack:SetDimensions(360, 8)
    self.balanceTrack:SetAnchor(TOPRIGHT, self.balanceValue, BOTTOMRIGHT, 0, 6)
    self.balanceFill = Tex(panel, 1, 1, 1, 1)
    self.balanceFill:SetAnchor(TOPLEFT, self.balanceTrack, TOPLEFT, 0, 0)
    self.balanceFill:SetHeight(8)

    -- tabs
    self.tabs = {}
    local x = PAD
    for _, key in ipairs(TABS) do
        local tab = Upper(Label(panel, f.big, NORMAL, TEXT_ALIGN_CENTER))
        tab:SetText(TAB_LABEL[key])
        tab:SetDimensions(220, 40)
        tab:SetAnchor(TOPLEFT, panel, TOPLEFT, x, BODY_TOP - 58)
        tab:SetMouseEnabled(true)
        tab:SetHandler("OnMouseUp", function(_, button, upInside) if upInside then RP:SetTab(key) end end)
        tab.underline = Tex(panel, 1, 1, 1, 1)
        tab.underline:SetDimensions(160, 3)
        tab.underline:SetAnchor(TOP, tab, BOTTOM, 0, 0)
        self.tabs[key] = tab
        x = x + 230
    end
    local line = Tex(panel, 1, 1, 1, 0.12)
    line:SetDimensions(PANEL_W - PAD * 2, 1)
    line:SetAnchor(TOPLEFT, panel, TOPLEFT, PAD, BODY_TOP - 12)

    -- body: everything per tab comes from these pools
    local body = WM:CreateControl(Name("Body"), panel, CT_CONTROL)
    body:SetDimensions(PANEL_W - PAD * 2, PANEL_H - BODY_TOP - PAD)
    body:SetAnchor(TOPLEFT, panel, TOPLEFT, PAD, BODY_TOP)
    self.body = body
    self.texts = Pool(body, function(p) return Label(p, f.text) end)
    self.boxes = Pool(body, function(p) return Tex(p, 1, 1, 1, 1) end)
end

-- the label pool hands out one font; set it per use
local function Text(self, font, rgb, align, text, w, h)
    local l = self.texts:Get()
    l:SetFont(font)
    Paint(l, rgb or WHITE)
    l:SetHorizontalAlignment(align or TEXT_ALIGN_LEFT)
    l:SetDimensions(w or 300, h or 30)
    l:SetText(text or "")
    if l.SetModifyTextType and MODIFY_TEXT_TYPE_NONE then l:SetModifyTextType(MODIFY_TEXT_TYPE_NONE) end
    return l
end

local function Box(self, rgb, a, w, h)
    local b = self.boxes:Get()
    b:SetColor(rgb[1], rgb[2], rgb[3], a or 1)
    b:SetDimensions(math.max(0, w), math.max(0, h))
    return b
end

---------------------------------------------------------------------------
-- rendering
---------------------------------------------------------------------------
function RP:Render()
    local m = self.match
    if not m then return end
    local f = Fonts()
    local res = RESULT[m.result] or RESULT.unknown
    Paint(self.result, res[2])
    self.result:SetText(res[1])
    Paint(self.banner, res[2])
    self.map:SetText(m.name or m.zoneName or "Battleground")
    self.details:SetText(string.format("%s  ·  %s  ·  %s", m.gameTypeName or "", SBR.FormatDuration(m.duration), SBR.FormatTimestamp(m.startedAt)))
    local b = m.balance
    local r, g, bl = SBR.Report.BalanceColor(b)
    self.balanceValue:SetText(b and tostring(b) or "-")
    self.balanceValue:SetColor(r, g, bl, 1)
    self.balanceText:SetText(SBR.Report.BalanceText(b))
    self.balanceText:SetColor(r, g, bl, 1)
    self.balanceFill:SetWidth(360 * Num(b) / 100)
    self.balanceFill:SetColor(r, g, bl, 1)
    for key, tab in pairs(self.tabs) do
        local on = key == self.tab
        Paint(tab, on and WHITE or NORMAL, on and 1 or 0.7)
        tab.underline:SetHidden(not on)
        Paint(tab.underline, GOLD)
    end
    self.texts:Reset()
    self.boxes:Reset()
    if self.tab == "timeline" then self:RenderTimeline(m, f)
    elseif self.tab == "you" then self:RenderYou(m, f)
    else self:RenderOverview(m, f) end
    if self.keybinds then KEYBIND_STRIP:UpdateKeybindButtonGroup(self.keybinds) end
end

local function SortedTeams(m)
    local ids = {}
    for id in pairs(m.teams or {}) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b) return Num(m.teams[a].score) > Num(m.teams[b].score) end)
    return ids
end

function RP:RenderOverview(m, f)
    local body = self.body
    -- team cards
    local totals = {}
    for _, p in pairs(m.players or {}) do
        local t = totals[p.team] or { kills = 0, damage = 0, healing = 0, players = 0 }
        local s = p.scores or {}
        t.kills, t.damage, t.healing = t.kills + Num(s.KILL), t.damage + Num(s.DAMAGE_DONE), t.healing + Num(s.HEALING_DONE)
        t.players = t.players + 1
        totals[p.team] = t
    end
    local y = 0
    for _, id in ipairs(SortedTeams(m)) do
        local t, rgb, tot = m.teams[id], TeamRGB(m, id), totals[id] or {}
        local card = Box(self, { 1, 1, 1 }, 0.05, 700, 112)
        card:SetAnchor(TOPLEFT, body, TOPLEFT, 0, y)
        local strip = Box(self, rgb, 1, 6, 112)
        strip:SetAnchor(TOPLEFT, card, TOPLEFT, 0, 0)
        local name = Text(self, f.title, rgb, TEXT_ALIGN_LEFT, (id == m.localTeam and "* " or "") .. (t.name or "?"), 440, 40)
        name:SetAnchor(TOPLEFT, card, TOPLEFT, 22, 10)
        local score = Text(self, f.huge, WHITE, TEXT_ALIGN_RIGHT, tostring(t.score or "-"), 200, 60)
        score:SetAnchor(TOPRIGHT, card, TOPRIGHT, -20, 10)
        local line = Text(self, f.small, NORMAL, TEXT_ALIGN_LEFT, string.format("%d kills  ·  %s damage  ·  %s healing  ·  %d players",
            Num(tot.kills), N(tot.damage), N(tot.healing), Num(tot.players)), 560, 30)
        line:SetAnchor(TOPLEFT, name, BOTTOMLEFT, 0, 12)
        y = y + 126
    end
    -- MVP
    local mvp
    for _, p in pairs(m.players or {}) do
        if not mvp or Num(p.scores and p.scores.SCORE) > Num(mvp.scores and mvp.scores.SCORE) then mvp = p end
    end
    if mvp then
        local cap = Upper(Text(self, f.small, DIM, TEXT_ALIGN_LEFT, "Match MVP", 300, 26))
        cap:SetAnchor(TOPLEFT, body, TOPLEFT, 0, y + 8)
        local nm = Text(self, f.title, GOLD, TEXT_ALIGN_LEFT, string.format("%s %s", (type(mvp.classIcon) == "string" and mvp.classIcon ~= "") and zo_iconFormat(mvp.classIcon, 36, 36) or "", mvp.characterName or "?"), 600, 40)
        nm:SetAnchor(TOPLEFT, cap, BOTTOMLEFT, 0, 2)
        local s = mvp.scores or {}
        local st = Text(self, f.small, NORMAL, TEXT_ALIGN_LEFT, string.format("%s score  ·  %s / %s / %s  ·  %s",
            N(s.SCORE), tostring(s.KILL or 0), tostring(s.DEATH or 0), tostring(s.ASSISTS or 0), mvp.className or ""), 660, 30)
        st:SetAnchor(TOPLEFT, nm, BOTTOMLEFT, 0, 2)
    end
    -- every player's title, best score first, grouped by team colour
    local cap = Upper(Text(self, f.small, DIM, TEXT_ALIGN_LEFT, "Titles earned", 400, 26))
    cap:SetAnchor(TOPLEFT, body, TOPLEFT, 760, 0)
    local list = {}
    for _, p in pairs(m.players or {}) do list[#list + 1] = p end
    table.sort(list, function(a, b) return Num(a.scores and a.scores.SCORE) > Num(b.scores and b.scores.SCORE) end)
    local titles = m.titles or {}
    for i, p in ipairs(list) do
        if i > 16 then break end
        local col, row = (i - 1) >= 8 and 1 or 0, (i - 1) % 8
        local x, yy = 760 + col * 370, 34 + row * 64
        local strip = Box(self, TeamRGB(m, p.team), 1, 4, 52)
        strip:SetAnchor(TOPLEFT, body, TOPLEFT, x, yy)
        local key = (p.displayName and p.displayName ~= "") and p.displayName or p.characterName
        local nm = Text(self, f.big, p.isLocal and GOLD or WHITE, TEXT_ALIGN_LEFT, (p.characterName or "?") .. (p == mvp and "  (MVP)" or ""), 330, 28)
        nm:SetAnchor(TOPLEFT, strip, TOPRIGHT, 12, 0)
        local tt = Text(self, f.small, NORMAL, TEXT_ALIGN_LEFT, titles[key] or "-", 330, 24)
        tt:SetAnchor(TOPLEFT, nm, BOTTOMLEFT, 0, 0)
    end
end

-- bar chart: series[teamId] = { {t, v}, ... }; mode "cumulative" values as given,
-- "rate" for per-bucket values. Draws grouped bars per bucket, one per team.
function RP:Chart(m, f, top, title, series, teams, height, fmt, mirrored)
    local body = self.body
    local width = PANEL_W - PAD * 2 - 120
    local cap = Upper(Text(self, f.small, DIM, TEXT_ALIGN_LEFT, title, 600, 26))
    cap:SetAnchor(TOPLEFT, body, TOPLEFT, 0, top)
    local area = Box(self, { 1, 1, 1 }, 0.04, width, height)
    area:SetAnchor(TOPLEFT, body, TOPLEFT, 120, top + 30)
    local buckets, maxV = 0, 0
    for _, id in ipairs(teams) do
        local s = series[id] or {}
        buckets = math.max(buckets, #s)
        for _, pt in ipairs(s) do maxV = math.max(maxV, Num(pt[2])) end
    end
    if buckets == 0 or maxV == 0 then
        local none = Text(self, f.small, DIM, TEXT_ALIGN_CENTER, "Not recorded for this match", width, height)
        none:SetAnchor(TOPLEFT, area, TOPLEFT, 0, 0)
        return
    end
    -- at most 48 buckets on screen: merge neighbours by taking the later sample
    local step = math.max(1, math.ceil(buckets / 48))
    local shown = math.ceil(buckets / step)
    local slot = width / shown
    local nTeams = #teams
    local barW = math.max(2, math.floor((slot - 4) / (mirrored and 1 or nTeams)))
    local half = height / 2
    for bi = 1, shown do
        local idx = math.min(buckets, bi * step)
        for ti, id in ipairs(teams) do
            local pt = (series[id] or {})[idx]
            local v = pt and Num(pt[2]) or 0
            if v > 0 then
                local rgb = TeamRGB(m, id)
                if mirrored then
                    -- first team up from the middle, the others down
                    local h = (half - 2) * v / maxV
                    local bar = Box(self, rgb, 0.9, barW, h)
                    local x = (bi - 1) * slot + 2
                    if ti == 1 then bar:SetAnchor(BOTTOMLEFT, area, TOPLEFT, x, half)
                    else bar:SetAnchor(TOPLEFT, area, TOPLEFT, x + (ti - 2) * math.floor(barW / math.max(1, nTeams - 1)), half) end
                else
                    local h = (height - 4) * v / maxV
                    local bar = Box(self, rgb, 0.9, barW, h)
                    bar:SetAnchor(BOTTOMLEFT, area, BOTTOMLEFT, (bi - 1) * slot + 2 + (ti - 1) * barW, 0)
                end
            end
        end
    end
    if mirrored then
        local mid = Box(self, { 1, 1, 1 }, 0.3, width, 1)
        mid:SetAnchor(LEFT, area, TOPLEFT, 0, half)
    end
    -- scale and time axis
    local maxL = Text(self, f.tiny, DIM, TEXT_ALIGN_RIGHT, fmt(maxV), 110, 22)
    maxL:SetAnchor(TOPRIGHT, area, TOPLEFT, -8, 0)
    local firstT = ((series[teams[1]] or {})[1] or {})[1] or 0
    local lastT = ((series[teams[1]] or {})[buckets] or {})[1] or 0
    local t0 = Text(self, f.tiny, DIM, TEXT_ALIGN_LEFT, SBR.FormatDuration(firstT), 120, 22)
    t0:SetAnchor(TOPLEFT, area, BOTTOMLEFT, 0, 2)
    local t1 = Text(self, f.tiny, DIM, TEXT_ALIGN_RIGHT, SBR.FormatDuration(lastT), 120, 22)
    t1:SetAnchor(TOPRIGHT, area, BOTTOMRIGHT, 0, 2)
end

function RP:RenderTimeline(m, f)
    local R = SBR.Report
    local teams = SortedTeams(m)
    local score = R:Series(m, 1)
    self:Chart(m, f, 0, "Score over time", score, teams, 130, function(v) return N(v) end)
    local damage = R:Series(m, 2)
    self:Chart(m, f, 196, "Damage race (team damage done)", damage, teams, 130, function(v) return N(v) end)
    -- momentum: kills per minute
    local perMin, minutes = R:Momentum(m)
    local series = {}
    for _, id in ipairs(teams) do
        local list = {}
        for mi = 1, minutes do list[mi] = { (mi - 1) * 60, (perMin[id] or {})[mi] or 0 } end
        series[id] = list
    end
    self:Chart(m, f, 392, "Momentum (kills per minute)", series, teams, 150, function(v) return tostring(v) end, true)
    -- legend
    local x = 0
    for _, id in ipairs(teams) do
        local rgb = TeamRGB(m, id)
        local sw = Box(self, rgb, 1, 18, 18)
        sw:SetAnchor(TOPLEFT, self.body, TOPLEFT, 700 + x, 2)
        local nm = Text(self, f.small, rgb, TEXT_ALIGN_LEFT, m.teams[id].name or "?", 220, 24)
        nm:SetAnchor(LEFT, sw, RIGHT, 8, 0)
        x = x + 250
    end
end

function RP:RenderYou(m, f)
    local body = self.body
    local h = m.haul or {}
    local tiles = {
        { "Alliance points", h.ap and ("+" .. N(h.ap)) or "-" },
        { "Experience", h.xp and ("+" .. N(h.xp)) or "-" },
        { "Champion points", h.cp and ((h.cp >= 0 and "+" or "") .. h.cp) or "-" },
        { "Medals", tostring(h.medals or #(m.myMedals or {})) },
        { "Alliance rank", h.rank and (SBR.CleanName(SBR.API("GetAvARankName", GENDER_MALE or 1, h.rank) or "") .. (h.rankUp and "  (rank up!)" or "")) or "-" },
    }
    for i, t in ipairs(tiles) do
        local x = (i - 1) * 296
        local box = Box(self, { 1, 1, 1 }, 0.05, 284, 96)
        box:SetAnchor(TOPLEFT, body, TOPLEFT, x, 0)
        local cap = Upper(Text(self, f.tiny, DIM, TEXT_ALIGN_LEFT, t[1], 260, 22))
        cap:SetAnchor(TOPLEFT, box, TOPLEFT, 16, 12)
        local v = Text(self, f.title, WHITE, TEXT_ALIGN_LEFT, t[2], 260, 44)
        v:SetAnchor(TOPLEFT, cap, BOTTOMLEFT, 0, 4)
    end
    -- your title and profile
    local me
    for _, p in pairs(m.players or {}) do if p.isLocal then me = p break end end
    local key = me and ((me.displayName and me.displayName ~= "") and me.displayName or me.characterName)
    local title = key and m.titles and m.titles[key]
    local cap = Upper(Text(self, f.small, DIM, TEXT_ALIGN_LEFT, "Your title this match", 400, 26))
    cap:SetAnchor(TOPLEFT, body, TOPLEFT, 0, 126)
    local tt = Text(self, f.huge, GOLD, TEXT_ALIGN_LEFT, title or "-", 640, 60)
    tt:SetAnchor(TOPLEFT, cap, BOTTOMLEFT, 0, 0)
    local hint = Text(self, f.small, NORMAL, TEXT_ALIGN_LEFT, "The stat where you came closest to the best player in the match.", 640, 28)
    hint:SetAnchor(TOPLEFT, tt, BOTTOMLEFT, 0, 0)
    -- medals
    local mcap = Upper(Text(self, f.small, DIM, TEXT_ALIGN_LEFT, "Your medals", 400, 26))
    mcap:SetAnchor(TOPLEFT, body, TOPLEFT, 0, 290)
    local counts, order = {}, {}
    for _, md in ipairs(m.myMedals or {}) do
        local k = md.name or md.id
        if not counts[k] then counts[k] = { name = md.name, icon = md.icon, n = 0 }; order[#order + 1] = counts[k] end
        counts[k].n = counts[k].n + 1
    end
    for i, md in ipairs(order) do
        if i > 10 then break end
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        local l = Text(self, f.text, WHITE, TEXT_ALIGN_LEFT, string.format("%s %s  x%d",
            (type(md.icon) == "string" and md.icon ~= "") and zo_iconFormat(md.icon, 32, 32) or "", md.name or "?", md.n), 320, 36)
        l:SetAnchor(TOPLEFT, body, TOPLEFT, col * 330, 322 + row * 42)
    end
    if #order == 0 then
        local none = Text(self, f.small, DIM, TEXT_ALIGN_LEFT, "No medals this time.", 400, 30)
        none:SetAnchor(TOPLEFT, body, TOPLEFT, 0, 322)
    end
    -- profile bars
    local pcap = Upper(Text(self, f.small, DIM, TEXT_ALIGN_LEFT, "Your profile (against the best in the match)", 700, 26))
    pcap:SetAnchor(TOPLEFT, body, TOPLEFT, 760, 126)
    for i, axis in ipairs(m.profile or {}) do
        local y = 166 + (i - 1) * 58
        local l = Text(self, f.big, WHITE, TEXT_ALIGN_LEFT, axis.label, 230, 30)
        l:SetAnchor(TOPLEFT, body, TOPLEFT, 760, y)
        local track = Box(self, { 1, 1, 1 }, 0.1, 440, 12)
        track:SetAnchor(LEFT, l, RIGHT, 10, 2)
        local share = math.max(0, math.min(1, Num(axis.share)))
        local fill = Box(self, share >= 0.999 and GOLD or { 0.48, 0.70, 0.88 }, 1, 440 * share, 12)
        fill:SetAnchor(LEFT, track, LEFT, 0, 0)
        local v = Text(self, f.small, NORMAL, TEXT_ALIGN_RIGHT, string.format("%d%%", math.floor(share * 100 + 0.5)), 70, 30)
        v:SetAnchor(LEFT, track, RIGHT, 6, -2)
    end
end

---------------------------------------------------------------------------
-- scenes, keybinds, opening
---------------------------------------------------------------------------
function RP:SetTab(tab)
    if tab == self.tab then return end
    self.tab = tab
    if SOUNDS and SOUNDS.GAMEPAD_MENU_FORWARD then PlaySound(SOUNDS.GAMEPAD_MENU_FORWARD) end
    self:Render()
end

function RP:CycleTab(delta)
    local i = 1
    for k, key in ipairs(TABS) do if key == self.tab then i = k end end
    self:SetTab(TABS[((i - 1 + delta) % #TABS) + 1])
end

function RP:StoredIndex()
    if not self.match then return nil end
    local _, index = SBR.MatchDB:FindMatch(self.match.id)
    return index
end

function RP:BuildKeybinds()
    self.keybinds = {
        alignment = KEYBIND_STRIP_ALIGN_LEFT,
        { name = "Scoreboard", keybind = "UI_SHORTCUT_PRIMARY", visible = function() return RP:StoredIndex() ~= nil end,
          callback = function()
              SBR.Window.viewIndex = RP:StoredIndex()
              SBR.Window:Show(true)
          end },
        { name = "Back", keybind = "UI_SHORTCUT_NEGATIVE", callback = function() RP:Close() end },
        { name = "Previous tab", keybind = "UI_SHORTCUT_LEFT_SHOULDER", callback = function() RP:CycleTab(-1) end },
        { name = "Next tab", keybind = "UI_SHORTCUT_RIGHT_SHOULDER", callback = function() RP:CycleTab(1) end },
    }
end

function RP:Init()
    if self.keyboardScene or not (ZO_Scene and SCENE_MANAGER and KEYBIND_STRIP) then return end
    self:Create()
    local fragment = ZO_SimpleSceneFragment:New(self.control)
    local function scene(name, group)
        local sc = ZO_Scene:New(name, SCENE_MANAGER)
        sc:AddFragment(fragment)
        if group then sc:AddFragmentGroup(group) end
        if MINIMIZE_CHAT_FRAGMENT then sc:AddFragment(MINIMIZE_CHAT_FRAGMENT) end
        sc:RegisterCallback("StateChange", function(_, newState)
            if newState == SCENE_SHOWN then RP:OnShown()
            elseif newState == SCENE_HIDING then KEYBIND_STRIP:RemoveKeybindButtonGroup(RP.keybinds) end
        end)
        return sc
    end
    self.keyboardScene = scene(self.keyboardSceneName, FRAGMENT_GROUP and FRAGMENT_GROUP.MOUSE_DRIVEN_UI_WINDOW)
    self.gamepadScene = scene(self.gamepadSceneName, FRAGMENT_GROUP and FRAGMENT_GROUP.GAMEPAD_DRIVEN_UI_WINDOW)
    self:BuildKeybinds()
end

function RP:FitToScreen()
    local w = GuiRoot and GuiRoot:GetWidth() or DESIGN_W
    local h = GuiRoot and GuiRoot:GetHeight() or DESIGN_H
    self.frame:SetScale(math.min(1, w / DESIGN_W, h / DESIGN_H))
end

function RP:OnShown()
    self:FitToScreen()
    self:Render()
    KEYBIND_STRIP:AddKeybindButtonGroup(self.keybinds)
end

function RP:IsShowing()
    return (self.keyboardScene and self.keyboardScene:IsShowing()) or (self.gamepadScene and self.gamepadScene:IsShowing()) or false
end

-- match: a match table (history entry), or nil for the latest finished match
function RP:Open(match, tab)
    match = match or SBR.MatchLog:GetHistory()[#SBR.MatchLog:GetHistory()]
    if not match then
        SBR.Print("No finished match to report yet.")
        return
    end
    self:Init()
    if not self.keyboardScene then return end
    self.match = SBR.Realize(match)
    self.tab = tab or "overview"
    if self:IsShowing() then self:Render() return end
    SCENE_MANAGER:Push(SBR.IsGamepad() and self.gamepadSceneName or self.keyboardSceneName)
end

function RP:Close()
    if self:IsShowing() then SCENE_MANAGER:HideCurrentScene() end
end

-- After a finished match: open its report once you're out of the battleground.
function RP:OnPlayerActivated()
    local pending = SBR.MatchLog.reportPending
    if not pending or SBR.Battleground:IsInBattleground() then return end
    SBR.MatchLog.reportPending = nil
    if SBR.sv.autoReport == false then return end
    zo_callLater(function() RP:Open(pending) end, 2000)
end

ScoreboardRemastered.Mark("UI/Report.lua")
