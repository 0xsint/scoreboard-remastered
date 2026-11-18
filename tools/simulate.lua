-- Scoreboard Remastered simulation.
--
-- Runs the add-on (and the real LibFights library) inside a stand-in ESO client
-- through eight simulated battlegrounds, then drives the add-on's screens and
-- records every control it builds (anchors, sizes, fonts, colours, text,
-- textures, visibility). tools/render.js turns those control trees into the
-- screenshots in docs/screenshots.
--
-- The stand-in answers the add-on's API calls with the signatures from the ESO
-- API documentation (API 101051). The matches are generated; nothing here is
-- read from the live game.
--
-- usage: lua5.1 tools/simulate.lua <addonDir> <libfightsDir> <out.json> [screens.json]
local ADDON, LFDIR, OUT, SCREENS_OUT = arg[1], arg[2], arg[3], arg[4]

---------------------------------------------------------------------------
-- deterministic RNG
---------------------------------------------------------------------------
local seed = tonumber(arg[4]) or 20261117
local function rand()
    seed = (seed * 1103515245 + 12345) % 2147483648
    return seed / 2147483648
end
local function randint(a, b) return a + math.floor(rand() * (b - a + 1)) end
local function pick(t) return t[randint(1, #t)] end

---------------------------------------------------------------------------
-- ESO API mocks
---------------------------------------------------------------------------
local LOG = {}
local simMs = 0
local function logline(kind, text) LOG[#LOG + 1] = { t = simMs / 1000, kind = kind, text = text } end

-- Control mock: records what the add-on does to every control so the layout can
-- be rendered afterwards. Anchor points and alignments are plain strings here.
for _, p in ipairs({ "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }) do _G[p] = p end
TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP, TEXT_ALIGN_BOTTOM = "left", "center", "right", "top", "bottom"
CT_CONTROL, CT_LABEL, CT_TEXTURE, CT_BACKDROP, CT_BUTTON, CT_EDITBOX = "control", "label", "texture", "backdrop", "button", "editbox"
TEXT_WRAP_MODE_ELLIPSIS, TEXT_WRAP_MODE_TRUNCATE = "ellipsis", "truncate"
MODIFY_TEXT_TYPE_UPPERCASE, MODIFY_TEXT_TYPE_NONE = "upper", "none"
DL_OVERLAY, DL_BACKGROUND, DT_HIGH, DT_MEDIUM, DT_LOW = "overlay", "background", "high", "medium", "low"
local FONT_SIZE = setmetatable({}, { __index = function(t, f)
    local n = tonumber(tostring(f):match("(%d+)$"))
    if n then return n end
    return ({ ZoFontGame = 18, ZoFontGameBold = 18, ZoFontGameMedium = 18, ZoFontGameSmall = 13, ZoFontHeader = 18,
              ZoFontWinH1 = 30, ZoFontWinH2 = 24, ZoFontWinH3 = 20, ZoFontWinH4 = 18 })[f] or 18
end })
local function plain(text)
    return (tostring(text or ""):gsub("|c%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|t[^|]*|t", "  "))
end
-- ESO creates a global object for every font in EsoUI/FontDefs (ZoFontGame, ZoFontGamepad42, ...)
for _, f in ipairs({ "ZoFontGame", "ZoFontGameBold", "ZoFontGameMedium", "ZoFontGameSmall", "ZoFontHeader",
    "ZoFontWinH1", "ZoFontWinH2", "ZoFontWinH3", "ZoFontWinH4", "ZoFontGamepad18", "ZoFontGamepad20", "ZoFontGamepad22",
    "ZoFontGamepad25", "ZoFontGamepad27", "ZoFontGamepad34", "ZoFontGamepad42", "ZoFontGamepadBold22", "ZoFontGamepadBold27",
    "ZoFontGamepadBold34", "ZoFontGamepadBold42", "ZoFontGamepadBold48", "ZoFontGamepadBold54" }) do
    _G[f] = { fontName = f }
end
local ALL = {}
local M = {}
local MT = { __index = function(t, k)
    if M[k] then return M[k] end
    if type(k) == "string" and k:sub(1, 1) ~= "_" then return function() end end
end }
local function ctl(name, parent, kind, virtual)
    local c = setmetatable({ _name = name, _parent = parent, _kind = kind or "control", _virtual = virtual, _anchors = {},
        _children = {}, _hidden = false, _color = { 1, 1, 1, 1 }, _alpha = 1 }, MT)
    if parent then table.insert(parent._children, c) end
    ALL[#ALL + 1] = c
    c._id = #ALL
    if name and name ~= "" then rawset(_G, name, c) end
    return c
end
function M:SetAnchor(point, rel, relPoint, ox, oy)
    if #self._anchors >= 2 then table.remove(self._anchors, 1) end
    table.insert(self._anchors, { point, rel or self._parent or GuiRoot, relPoint or point, ox or 0, oy or 0 })
end
function M:ClearAnchors() self._anchors = {} end
function M:SetAnchorFill(rel)
    rel = rel or self._parent or GuiRoot
    self._anchors = { { "TOPLEFT", rel, "TOPLEFT", 0, 0 }, { "BOTTOMRIGHT", rel, "BOTTOMRIGHT", 0, 0 } }
end
function M:SetDimensions(w, h) if w then self._w = w end if h then self._h = h end end
function M:SetWidth(w) self._w = w end
function M:SetHeight(h) self._h = h end
function M:GetWidth() return self._w or (self == GuiRoot and 1920) or 0 end
function M:GetHeight() return self._h or (self == GuiRoot and 1080) or 0 end
function M:SetHidden(v) self._hidden = v and true or false end
function M:IsHidden() return self._hidden end
function M:SetColor(r, g, b, a) self._color = { r or 1, g or 1, b or 1, a or 1 } end
function M:SetAlpha(a) self._alpha = a end
function M:SetText(v) self._text = v end
function M:GetText() return self._text end
function M:SetFont(f) self._font = f end
function M:SetHorizontalAlignment(a) self._halign = a end
function M:SetVerticalAlignment(a) self._valign = a end
function M:SetTexture(p) self._texture = p end
function M:SetModifyTextType(t) self._upper = t == "upper" end
function M:SetWrapMode(m) self._wrap = m end
function M:SetScale(s) self._scale = s end
function M:SetHandler(name, fn) self._handlers = self._handlers or {}; self._handlers[name] = fn end
function M:GetName() return self._name end
function M:GetTextWidth() return #plain(self._text) * FONT_SIZE[self._font or "ZoFontGame"] * 0.48 end
function M:GetTextHeight()
    local _, lines = tostring(self._text or ""):gsub("\n", "")
    return (lines + 1) * FONT_SIZE[self._font or "ZoFontGame"] * 1.3
end
function M:GetRight() return 0 end
function M:GetLeft() return 0 end
function M:GetTop() return 0 end
WINDOW_MANAGER = {
    CreateTopLevelWindow = function(_, n) local c = ctl(n, nil, "toplevel"); c._hidden = true; return c end,
    CreateControl = function(_, n, parent, kind) return ctl(n, parent, kind) end,
    CreateControlFromVirtual = function(_, n, parent, virtual)
        local c = ctl(n ~= "" and n or nil, parent, "virtual", virtual)
        if virtual == "ZO_DefaultBackdrop" or virtual == "ZO_DefaultBackdrop_Gamepad" or virtual == "ZO_EditBackdrop" then c._kind = "backdrop" end
        if virtual == "ZO_DefaultButton" then c._kind = "button" end
        if virtual == "ZO_CloseButton" then c._kind = "closebutton" end
        return c
    end,
}
GuiRoot = ctl("GuiRoot", nil, "root"); GuiRoot._w, GuiRoot._h = 1920, 1080
InformationTooltip = ctl("InformationTooltip")
function InitializeTooltip() end function SetTooltipText() end function ClearTooltip() end
SLASH_COMMANDS = {}
local function mockScene(name) return { name = name, cbs = {}, RegisterCallback = function(sc, _, f) table.insert(sc.cbs, f) end, IsShowing = function() return false end } end
SCENE_MANAGER = { scenes = { inventory = mockScene("inventory"), gamepad_inventory_root = mockScene("gamepad_inventory_root") },
    IsInUIMode = function() return true end, SetInUIMode = function() end }
function SCENE_MANAGER:GetScene(n) return self.scenes[n] or SCENES[n] end
function SCENE_MANAGER:IsShowing(n) return SCENES[n] ~= nil and SCENES[n].showing == true end
function SCENE_MANAGER:Push(name)
    local sc = SCENES[name]
    local top = sceneStack[#sceneStack]
    if top then top:SetState("hiding"); top:SetState("hidden") end
    table.insert(sceneStack, sc)
    sc:SetState("showing"); sc:SetState("shown")
end
function SCENE_MANAGER:HideCurrentScene()
    local sc = table.remove(sceneStack)
    if sc then sc:SetState("hiding"); sc:SetState("hidden") end
    local top = sceneStack[#sceneStack]
    if top then top:SetState("showing"); top:SetState("shown") end
end
-- ZO_PlayerInventory: 565 wide on ZO_SharedRightPanelBackground (575 x 750, RIGHT of GuiRoot, +20)
local rightPanel = ctl("ZO_SharedRightPanelBackground", nil, "toplevel"); rightPanel:SetDimensions(575, 750); rightPanel:SetAnchor("RIGHT", GuiRoot, "RIGHT", 0, 20)
ZO_PlayerInventory = ctl("ZO_PlayerInventory", nil, "toplevel"); ZO_PlayerInventory:SetDimensions(565, nil)
ZO_PlayerInventory:SetAnchor("TOPLEFT", rightPanel, "TOPLEFT", 0, -20); ZO_PlayerInventory:SetAnchor("BOTTOMLEFT", rightPanel, "BOTTOMLEFT", 0, -30)
MOUSE_BUTTON_INDEX_LEFT = 1; MOUSE_BUTTON_INDEX_RIGHT = 2
local nativeTop = ctl("ZO_BattlegroundScoreboardTopLevel", nil, "toplevel"); nativeTop:SetAnchorFill(GuiRoot)
local nativeBoard = ctl("ZO_BattlegroundScoreboardTopLevelBackgrounds", nativeTop, "control")
nativeBoard:SetDimensions(1124, 810); nativeBoard:SetAnchor("CENTER", nativeTop, "CENTER", 0, 0)
local nativeFragment = { control = nativeTop, RegisterCallback = function(s, _, f) s.cb = f end }
BATTLEGROUND_SCOREBOARD_FRAGMENT = nativeFragment
SCENE_SHOWN = "shown"; SCENE_HIDDEN = "hidden"; SCENE_HIDING = "hiding"; SCENE_SHOWING = "showing"
SCENE_FRAGMENT_SHOWN = "shown"; SCENE_FRAGMENT_HIDDEN = "hidden"
function ZO_PostHook() end
function ZO_CreateStringId(k, v) _G[k] = v end
function ZO_ClearNumericallyIndexedTable(t) for i = #t, 1, -1 do t[i] = nil end end
function zo_clamp(v, a, b) return math.max(a, math.min(b, v)) end
function zo_iconFormat(p, w, h) return string.format("|t%s:%s:%s|t", tostring(w or 32), tostring(h or 32), p) end
function zo_strformat(_, n) return (tostring(n):gsub("%^.*$", "")) end
function zo_callLater() end
SI_UNIT_NAME = 1
function d(s) logline("chat", tostring(s)) end
function PlaySound() end

-- gamepad mocks (Gamepad:Init runs at load)
function IsInGamepadPreferredMode() return false end
KEYBIND_STRIP_ALIGN_LEFT = 1; KEYBIND_STRIP_ALIGN_RIGHT = 2
MOVEMENT_CONTROLLER_DIRECTION_VERTICAL = 1; MOVEMENT_CONTROLLER_DIRECTION_HORIZONTAL = 2
ZO_MovementController = { New = function() return { CheckMovement = function() return 0 end } end }
DIRECTIONAL_INPUT = { Activate = function() end, Deactivate = function() end }
KEYBIND_STRIP = { groups = {}, order = {}, AddKeybindButtonGroup = function(s, g) if not s.groups[g] then s.groups[g] = true; table.insert(s.order, g) end end,
    RemoveKeybindButtonGroup = function(s, g)
        s.groups[g] = nil
        for i = #s.order, 1, -1 do if s.order[i] == g then table.remove(s.order, i) end end
    end, UpdateKeybindButtonGroup = function() end,
    GetDefaultGamepadBackButtonDescriptor = function() return KEYBIND_STRIP_BACK end }
PushActionLayerByName = function(n) LAYERS = LAYERS or {}; LAYERS[n] = true end
RemoveActionLayerByName = function(n) if LAYERS then LAYERS[n] = nil end end
IsActionLayerActiveByName = function(n) return LAYERS and LAYERS[n] or false end
SI_KEYBINDINGS_LAYER_USER_INTERFACE_SHORTCUTS = 676
ZO_SimpleSceneFragment = { New = function(_, c) return { control = c } end }
SCENES = {}
sceneStack = {}
ZO_Scene = { New = function(_, name)
    local sc = { name = name, frags = {}, cbs = {} }
    function sc:AddFragment(f) table.insert(self.frags, f) end
    function sc:AddFragmentGroup() end
    function sc:RegisterCallback(_, f) table.insert(self.cbs, f) end
    function sc:IsShowing() return self.showing == true end
    function sc:SetState(st)
        self.showing = st == "showing" or st == "shown"
        for _, f in ipairs(self.frags) do
            if f.control then
                if st == "showing" then f.control:SetHidden(false) elseif st == "hidden" then f.control:SetHidden(true) end
            end
        end
        for _, f in ipairs(self.cbs) do f(nil, st) end
    end
    SCENES[name] = sc
    return sc
end }
FRAGMENT_GROUP = { GAMEPAD_DRIVEN_UI_WINDOW = {}, GAMEPAD_KEYBIND_STRIP_GROUP = {}, MOUSE_DRIVEN_UI_WINDOW = {} }

-- ESO gamepad framework stand-in (records what the add-on puts into it).
-- Mirrors the API of ZO_Gamepad_ParametricList_Screen, ZO_GamepadEntryData, the
-- generic header and GAMEPAD_TOOLTIPS used by UI/Console.lua.
ZO_InitializingObject = {}
ZO_InitializingObject.__index = ZO_InitializingObject
function ZO_InitializingObject:Subclass()
    local c = setmetatable({}, { __index = self })
    c.__index = c
    return c
end
function ZO_InitializingObject:New(...)
    local o = setmetatable({}, self)
    o:Initialize(...)
    return o
end
ZO_FadeSceneFragment = { New = function(_, c) return { control = c } end }
GAMEPAD_NAV_QUADRANT_1_BACKGROUND_FRAGMENT, MINIMIZE_CHAT_FRAGMENT, GAMEPAD_MENU_SOUND_FRAGMENT = {}, {}, {}
ZO_GAMEPAD_HEADER_TABBAR_CREATE = true
GAMEPAD_RIGHT_TOOLTIP = "GAMEPAD_RIGHT_TOOLTIP"
function ZO_GamepadGenericHeader_Refresh(header, data) header.data = data; header.tab = header.tab or 1 end
ZO_GamepadGenericHeader_RefreshData = ZO_GamepadGenericHeader_Refresh
function ZO_GamepadGenericHeader_Activate(header) header.active = true end
function ZO_GamepadGenericHeader_Deactivate(header) header.active = false end
function ZO_GamepadGenericHeader_SetActiveTabIndex(header, i) header.tab = i end
function ZO_Gamepad_AddListTriggerKeybindDescriptors(desc, list)
    table.insert(desc, { keybind = "UI_SHORTCUT_LEFT_TRIGGER", name = "", ethereal = true, callback = function() list:Move(-10) end })
    table.insert(desc, { keybind = "UI_SHORTCUT_RIGHT_TRIGGER", name = "", ethereal = true, callback = function() list:Move(10) end })
end
ZO_GamepadEntryData = {}
ZO_GamepadEntryData.__index = ZO_GamepadEntryData
function ZO_GamepadEntryData:New(text, icon) return setmetatable({ text = text, icon = icon }, self) end
function ZO_GamepadEntryData:SetHeader(h) self.header = h end
function ZO_GamepadEntryData:SetIconTintOnSelection(v) self.iconTint = v end
function ZO_GamepadEntryData:SetNameColors() end
local function NewList(screen)
    local l = { entries = {}, selected = 1 }
    function l:Clear() self.entries = {} end
    function l:AddEntry(template, data) table.insert(self.entries, { template = template, data = data }) end
    function l:Commit()
        self.selected = math.min(math.max(1, self.selected), math.max(1, #self.entries))
        screen:OnTargetChanged(self, self:GetTargetData())
    end
    function l:GetTargetData() local e = self.entries[self.selected]; return e and e.data end
    function l:SetSelectedIndex(i)
        self.selected = math.min(math.max(1, i), math.max(1, #self.entries))
        screen:OnTargetChanged(self, self:GetTargetData())
    end
    function l:Move(d) self:SetSelectedIndex(self.selected + d) end
    return l
end
ZO_Gamepad_ParametricList_Screen = ZO_InitializingObject:Subclass()
function ZO_Gamepad_ParametricList_Screen:Initialize(control, createTabBar, activateOnShow, scene)
    self.control = control
    self.header = { tabBar = createTabBar }
    self.list = NewList(self)
    self.scene = scene
    scene:RegisterCallback("StateChange", function(_, st)
        if st == "showing" then
            if self.keybindStripDescriptor then KEYBIND_STRIP:AddKeybindButtonGroup(self.keybindStripDescriptor) end
            self:OnShowing()
        elseif st == "hiding" then
            if self.keybindStripDescriptor then KEYBIND_STRIP:RemoveKeybindButtonGroup(self.keybindStripDescriptor) end
        elseif st == "hidden" then
            self:OnHide()
        end
    end)
    self:InitializeKeybindStripDescriptors()
end
function ZO_Gamepad_ParametricList_Screen:GetMainList() return self.list end
function ZO_Gamepad_ParametricList_Screen:Update() self:PerformUpdate() end
function ZO_Gamepad_ParametricList_Screen:RefreshKeybinds() end
function ZO_Gamepad_ParametricList_Screen:OnTargetChanged() end
function ZO_Gamepad_ParametricList_Screen:OnShowing() end
function ZO_Gamepad_ParametricList_Screen:OnHide() end
ZO_Tooltip = {}
local function NewTooltip()
    local tip = { sections = {} }
    function tip:GetStyle(n) return n end
    function tip:AcquireSection(style)
        local sec = { style = style, items = {} }
        function sec:AddLine(text, st) table.insert(self.items, { kind = "line", text = text, style = st }) end
        function sec:AcquireStatValuePair(st)
            local pair = { kind = "pair", style = st }
            function pair:SetStat(t, st2) self.stat, self.statStyle = t, st2 end
            function pair:SetValue(v, st2) self.value, self.valueStyle = v, st2 end
            return pair
        end
        function sec:AddStatValuePair(pair) table.insert(self.items, { kind = "pair", stat = pair.stat, value = pair.value, valueStyle = pair.valueStyle }) end
        return sec
    end
    function tip:AddSection(sec) table.insert(self.sections, sec) end
    return setmetatable(tip, { __index = ZO_Tooltip })
end
GAMEPAD_TOOLTIPS = setmetatable({ current = {} }, { __index = function(t, k)
    if k == "ClearTooltip" then return function(self, tt) self.current[tt] = nil end end
    if type(k) == "string" and k:find("^Layout") then
        return function(self, tt, ...)
            local tip = NewTooltip()
            ZO_Tooltip[k](tip, ...)
            self.current[tt] = tip.sections
        end
    end
end })
KEYBIND_STRIP_BACK = { name = "Back", keybind = "UI_SHORTCUT_NEGATIVE", callback = function() SCENE_MANAGER:HideCurrentScene() end }
ZO_CallbackObject = {}
function ZO_CallbackObject:New()
    local o = { cbs = {} }
    function o:RegisterCallback(n, f, a) self.cbs[n] = self.cbs[n] or {}; table.insert(self.cbs[n], { f, a }) end
    function o:UnregisterCallback() end
    function o:FireCallbacks(n, ...)
        for _, c in ipairs(self.cbs[n] or {}) do
            if c[2] ~= nil then c[1](c[2], ...) else c[1](...) end
        end
    end
    return o
end
ZO_SavedVars = {}
function ZO_SavedVars:NewAccountWide(_, _, _, def) return def end
function ZO_SavedVars:New(_, _, _, def) return def end
function ZO_SavedVars:NewCharacterIdSettings(_, _, _, def) return def end

-- events with filter emulation (args exclude eventCode: result=1,isError=2,sourceType=7,targetType=9)
local events, updates = {}, {}
local ARGPOS = {}
EVENT_MANAGER = {
    RegisterForEvent = function(_, ns, ev, f) events[ns .. ":" .. tostring(ev)] = { ev = ev, f = f, filters = {} } end,
    UnregisterForEvent = function(_, ns, ev) events[ns .. ":" .. tostring(ev)] = nil end,
    AddFilterForEvent = function(_, ns, ev, ...)
        local e = events[ns .. ":" .. tostring(ev)]
        local a = { ... }
        for i = 1, #a, 2 do table.insert(e.filters, { a[i], a[i + 1] }) end
    end,
    RegisterForUpdate = function(_, ns, ms, f) updates[ns] = { ms = ms, f = f, nextAt = simMs + ms } end,
    UnregisterForUpdate = function(_, ns) updates[ns] = nil end,
}
local function pass(e, ...)
    local args = { ... }
    for _, fl in ipairs(e.filters) do
        if fl[1] == 4 and args[1] ~= fl[2] then return false end
        if fl[1] == 5 and (type(args[1]) ~= "string" or args[1]:sub(1, #fl[2]) ~= fl[2]) then return false end
        local pos = ARGPOS[fl[1]]
        if pos and args[pos] ~= fl[2] then return false end
    end
    return true
end
local function fire(ev, ...)
    local l = {}
    for _, e in pairs(events) do if e.ev == ev and pass(e, ...) then l[#l + 1] = e.f end end
    for _, f in ipairs(l) do f(ev, ...) end
end
local function runUpdates()
    local due = {}
    for ns, u in pairs(updates) do if simMs >= u.nextAt then due[#due + 1] = ns end end
    table.sort(due)
    for _, ns in ipairs(due) do
        local u = updates[ns]
        if u then
            u.nextAt = simMs + u.ms
            u.f()
        end
    end
end

local ev = 0
for _, n in ipairs({ "EVENT_ADD_ON_LOADED", "EVENT_PLAYER_ACTIVATED", "EVENT_BATTLEGROUND_STATE_CHANGED",
    "EVENT_BATTLEGROUND_SCOREBOARD_UPDATED", "EVENT_BATTLEGROUND_KILL", "EVENT_MEDAL_AWARDED",
    "EVENT_COMBAT_EVENT", "EVENT_PLAYER_COMBAT_STATE", "EVENT_UNIT_DEATH_STATE_CHANGED" }) do
    ev = ev + 1; _G[n] = ev
end
local C = {
    SCORE_TRACKER_TYPE_SCORE = 1, SCORE_TRACKER_TYPE_KILL = 2, SCORE_TRACKER_TYPE_DEATH = 3,
    SCORE_TRACKER_TYPE_ASSISTS = 4, SCORE_TRACKER_TYPE_DAMAGE_DONE = 5, SCORE_TRACKER_TYPE_HEALING_DONE = 6,
    SCORE_TRACKER_TYPE_FLAG_CAPTURED = 7,
    BATTLEGROUND_TEAM_ITERATION_BEGIN = 1, BATTLEGROUND_TEAM_ITERATION_END = 2,
    BATTLEGROUND_STATE_PREROUND = 1, BATTLEGROUND_STATE_RUNNING = 3, BATTLEGROUND_STATE_FINISHED = 5,
    ACTION_RESULT_DAMAGE = 1, ACTION_RESULT_CRITICAL_DAMAGE = 2, ACTION_RESULT_DOT_TICK = 1073741825,
    ACTION_RESULT_DOT_TICK_CRITICAL = 1073741826, ACTION_RESULT_HEAL = 16, ACTION_RESULT_CRITICAL_HEAL = 32,
    ACTION_RESULT_HOT_TICK = 1073741840, ACTION_RESULT_HOT_TICK_CRITICAL = 1073741856,
    ACTION_RESULT_DAMAGE_SHIELDED = 2460, ACTION_RESULT_BLOCKED_DAMAGE = 2151,
    ACTION_RESULT_KILLING_BLOW = 2265, ACTION_RESULT_DIED = 2260, ACTION_RESULT_INTERRUPT = 2230,
    ACTION_RESULT_STUNNED = 2020, ACTION_RESULT_KNOCKBACK = 2475, ACTION_RESULT_ROOTED = 2480,
    COMBAT_UNIT_TYPE_NONE = 0, COMBAT_UNIT_TYPE_PLAYER = 1, COMBAT_UNIT_TYPE_PLAYER_PET = 2,
    COMBAT_UNIT_TYPE_GROUP = 3, COMBAT_UNIT_TYPE_OTHER = 5,
    REGISTER_FILTER_IS_ERROR = 1, REGISTER_FILTER_SOURCE_COMBAT_UNIT_TYPE = 2, REGISTER_FILTER_TARGET_COMBAT_UNIT_TYPE = 3,
    REGISTER_FILTER_UNIT_TAG = 4, REGISTER_FILTER_UNIT_TAG_PREFIX = 5,
    GENDER_MALE = 1,
}
for k, v in pairs(C) do _G[k] = v end
ARGPOS[1] = 2; ARGPOS[2] = 7; ARGPOS[3] = 9

---------------------------------------------------------------------------
-- the match
---------------------------------------------------------------------------
local CLASSES = { DK = 1, SO = 2, NB = 3, TE = 6, WA = 4, NE = 5, AR = 117 }
local CLASS_NAME = { [1] = "Dragonknight", [2] = "Sorcerer", [3] = "Nightblade", [4] = "Warden", [5] = "Necromancer", [6] = "Templar", [117] = "Arcanist" }
local ABILITIES = {
    DK = { { 20805, "Molten Whip" }, { 20668, "Venomous Claw" }, { 23806, "Flame Lash" } },
    SO = { { 46331, "Crystal Fragments" }, { 23214, "Lightning Flood" }, { 23234, "Endless Fury" } },
    NB = { { 25484, "Surprise Attack" }, { 36508, "Incapacitating Strike" }, { 61902, "Merciless Resolve" } },
    TE = { { 26114, "Puncturing Sweeps" }, { 63044, "Radiant Glory" }, { 22223, "Biting Jabs" } },
    WA = { { 86113, "Arctic Blast" }, { 85999, "Cutting Dive" }, { 86109, "Northern Storm" } },
    NE = { { 117690, "Stalking Blastbones" }, { 117854, "Detonating Siphon" }, { 118726, "Ricochet Skull" } },
    AR = { { 185805, "Fatecarver" }, { 183122, "Pragmatic Fatecarver" }, { 185817, "Runeblades" } },
}
local HEALS = {
    TE = { { 22253, "Breath of Life" }, { 22304, "Illustrious Healing" } },
    WA = { { 85862, "Enchanted Forest" } },
    AR = { { 183261, "Remedy Cascade" } },
    NE = { { 115307, "Render Flesh" } },
    DK = { { 32853, "Coagulating Blood" } },
    SO = { { 46198, "Dark Deal" } },
    NB = { { 33291, "Strife" } },
}
local SHIELDS = { { 22180, "Blazing Shield" }, { 61233, "Harness Magicka" } }

local ROSTER = {
    { "Vashti Emberlock", "@you", 1, "AR", "dps", true },
    { "Orsk gro-Durbash", "@ironjaw", 1, "DK", "dps" },
    { "Seren of the Reach", "@seren.r", 1, "TE", "heal" },
    { "Tamsin Velothi", "@tamsin_v", 1, "NB", "dps" },
    { "Hrolf Snowmane", "@hrolfsm", 1, "WA", "tank" },
    { "Ilyra Duskmere", "@ilyra", 1, "SO", "dps" },
    { "Corvus Marrowind", "@corvus.m", 1, "NE", "dps" },
    { "Brindle Oakhart", "@brindle", 1, "TE", "heal" },
    { "Morvayn Ashcroft", "@morvayn", 2, "DK", "dps" },
    { "Kesh-Varra", "@keshv", 2, "NB", "dps" },
    { "Aldwin Greaves", "@agreaves", 2, "WA", "tank" },
    { "Yselle Mournwood", "@yselle", 2, "TE", "heal" },
    { "Draven Thule", "@dthule", 2, "SO", "dps" },
    { "Nhalia Stormbreak", "@nhalia", 2, "AR", "dps" },
    { "Gorlak the Grim", "@gorlak", 2, "NE", "dps" },
    { "Wren Hollowell", "@wrenh", 2, "TE", "heal" },
}
local P = {}
local ME
local CUR = { map = "Foyada Quarry", bgId = 42, gameType = "Capture the Flag", gameTypeId = 2, baseTs = 1795468800, inBG = true }
local function resetPlayers(cfg)
for k in pairs(P) do P[k] = nil end
ROSTER[1][1], ROSTER[1][4] = cfg.char, cfg.cls
for i, r in ipairs(ROSTER) do
    local role = r[5]
    P[i] = {
        i = i, name = r[1], raw = r[1] .. "^Mx", acct = r[2], team = r[3], cls = r[4], role = role, isLocal = r[6] == true,
        classId = CLASSES[r[4]], unitId = 1000 + i,
        maxHp = role == "tank" and 38000 or (role == "heal" and 26000 or 28000),
        power = role == "dps" and (0.85 + rand() * 0.4) or (role == "tank" and 0.55 or 0.35),
        alive = true, respawnAt = 0, lastHitBy = {},
        sc = { SCORE = 0, KILL = 0, DEATH = 0, ASSISTS = 0, DAMAGE_DONE = 0, HEALING_DONE = 0, FLAG_CAPTURED = 0 },
        medals = {},
    }
    P[i].hp = P[i].maxHp
end
ME = P[1]
end
local teamScore = { 0, 0 }
local bgState = C.BATTLEGROUND_STATE_PREROUND

local function unitType(p)
    if p.isLocal then return C.COMBAT_UNIT_TYPE_PLAYER end
    if p.team == ME.team then return C.COMBAT_UNIT_TYPE_GROUP end
    return C.COMBAT_UNIT_TYPE_OTHER
end
local function visible(a, b) return a.team == ME.team or b.team == ME.team end

local function combat(result, ability, src, tgt, hit)
    if not visible(src, tgt) then return end
    fire(EVENT_COMBAT_EVENT, result, false, ability[2] .. "^n", 0, 0, src.raw, unitType(src), tgt.raw, unitType(tgt),
        hit, 0, 0, 0, src.unitId, tgt.unitId, ability[1], 0)
end

-- medals
local MEDAL = {
    { 1, "First Blood" }, { 2, "Flag Bearer" }, { 3, "Assassin" }, { 4, "Lifesaver" }, { 5, "Defender" },
    { 6, "Killing Spree" }, { 7, "Bloodthirsty" }, { 8, "Unstoppable" },
}
local firstBlood = false
local function award(p, medal)
    local m = p.medals[medal[1]] or { id = medal[1], count = 0 }
    m.count = m.count + 1
    p.medals[medal[1]] = m
    p.sc.SCORE = p.sc.SCORE + 50
    if p.isLocal then fire(EVENT_MEDAL_AWARDED, medal[1], medal[2] .. "^n", "medal_" .. medal[1] .. ".dds", 50) end
end

-- native scoreboard API
local function entries() return P end
function GetNumScoreboardEntries() return #P end
function GetScoreboardEntryInfo(i) local p = P[i]; return p.raw, p.acct, p.team, p.isLocal end
function GetScoreboardEntryClassId(i) return P[i].classId end
function GetClassName(_, c) return CLASS_NAME[c] .. "^m" end
function ZO_GetClassIcon(c) return "class_" .. c .. ".dds" end
local ST = { "SCORE", "KILL", "DEATH", "ASSISTS", "DAMAGE_DONE", "HEALING_DONE", "FLAG_CAPTURED" }
function GetScoreboardEntryScoreByType(i, t) return P[i].sc[ST[t]] end
-- medal iterators, as in API 101051
local function nextMedal(medals, last)
    local ids = {}
    for id in pairs(medals) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do if last == nil or id > last then return id end end
    return nil
end
function GetNextScoreboardEntryMedalId(i, roundIndex, last) return nextMedal(P[i].medals, last) end
function GetScoreboardEntryNumEarnedMedalsById(i, id, roundIndex) return P[i].medals[id] and P[i].medals[id].count or 0 end
local cumulative = {}
function GenerateCumulativeMedalInfoForScoreboardEntry(i, roundIndex) cumulative = P[i].medals end
function GetNextBattlegroundCumulativeMedalId(last) return nextMedal(cumulative, last) end
function GetBattlegroundCumulativeNumEarnedMedalsById(id) return cumulative[id] and cumulative[id].count or 0 end
function GetCurrentBattlegroundRoundIndex() return 1 end
function GetBattlegroundNumRounds() return 1 end
function GetMedalInfo(id) return MEDAL[id][2] .. "^n", "medal_" .. id .. ".dds", "", 50 end
function GetAbilityName(id)
    for _, set in pairs(ABILITIES) do for _, a in ipairs(set) do if a[1] == id then return a[2] .. "^n" end end end
    for _, set in pairs(HEALS) do for _, a in ipairs(set) do if a[1] == id then return a[2] .. "^n" end end end
    for _, a in ipairs(SHIELDS) do if a[1] == id then return a[2] .. "^n" end end
    if id == 21970 then return "Bash^n" end
    return "Ability " .. id
end
function DoesAbilityExist(id) return GetAbilityName(id):sub(1, 8) ~= "Ability " end
function GetAbilityIcon(id) return "ability_" .. tostring(id) .. ".dds" end
function IsActiveWorldBattleground() return CUR.inBG end
function GetCurrentBattlegroundId() return CUR.inBG and CUR.bgId or 0 end
function GetBattlegroundName() return CUR.map end
function GetBattlegroundGameType() return CUR.gameTypeId end
function GetBattlegroundTeamSize() return 8 end
function GetCurrentBattlegroundState() return bgState end
function GetUnitBattlegroundTeam() return ME.team end
function GetCurrentBattlegroundScore(roundIndex, t)
    assert(type(roundIndex) == "number", "GetCurrentBattlegroundScore needs (roundIndex, team)")
    return teamScore[t]
end
function GetBattlegroundTeamName(t) return ({ "Fire Drakes", "Pit Daemons" })[t] end
function GetCurrentBattlegroundGameType(roundIndex) return CUR.gameTypeId end
function GetString(prefix, id)
    if prefix == 676 then return "User Interface Shortcuts" end
    if prefix == "SI_BATTLEGROUNDGAMETYPE" then return CUR.gameType end
    return ""
end
function GetUnitName() return ME.raw end
function GetUnitDisplayName() return ME.acct end
function GetUnitZone() return "Foyada Quarry" end
function GetGameTimeMilliseconds() return simMs end
function GetTimeStamp() return CUR.baseTs + math.floor(simMs / 1000) end
function GetDateStringFromTimestamp(ts) return os.date("!%Y-%m-%d", ts) end
function GetFrameTimeSeconds() return simMs / 1000 end
function IsUnitInCombat(tag) return tag == "player" and ME.alive and (simMs - (ME.lastCombatMs or -99999)) < 2500 end
function IsUnitDead(tag) return tag == "player" and not ME.alive end

setmetatable(_G, { __index = function(t, k)
    if type(k) == "string" then
        for _, p in ipairs({ "Get", "Is", "Has", "Can", "Does", "Do" }) do
            if k:sub(1, #p) == p and k:sub(#p + 1, #p + 1):match("%u") then return function() return nil end end
        end
    end
end })

---------------------------------------------------------------------------
-- load LibFights, then the add-on (manifest order)
---------------------------------------------------------------------------
local function manifest(path)
    local files = {}
    for line in io.lines(path) do if line:match("%.lua$") then files[#files + 1] = line end end
    return files
end
for _, f in ipairs(manifest(LFDIR .. "/LibFights.addon")) do
    local ok, err = pcall(dofile, LFDIR .. "/" .. f)
    if not ok then io.stderr:write("LF load error " .. f .. ": " .. tostring(err) .. "\n") end
end
for _, f in ipairs(manifest(ADDON .. "/ScoreboardRemastered.addon")) do dofile(ADDON .. "/" .. f) end
-- UI/Console.xml: the two ZO_Gamepad_ParametricList_Screen top levels
ScoreboardRemastered_ScoreboardConsole_OnInitialized(ctl("ScoreboardRemastered_ScoreboardConsole", nil, "toplevel"))
ScoreboardRemastered_RecordsConsole_OnInitialized(ctl("ScoreboardRemastered_RecordsConsole", nil, "toplevel"))
local SBR = ScoreboardRemastered
fire(EVENT_ADD_ON_LOADED, "LibFights")
fire(EVENT_ADD_ON_LOADED, "ScoreboardRemastered")
LibFights.RegisterCallback(LibFights.EVENTS.FIGHT_ENDED, function(f, reason)
    local s = f:GetSummary()
    logline("libfights", string.format("LibFights fight %d ended (%s): %s, %.0fs, %d damage, %d healing",
        f.id, reason, f:GetTitle(), s.durationSec, s.damage, s.healing))
end)

---------------------------------------------------------------------------
-- simulate
---------------------------------------------------------------------------
local FRAMES = {}
local function snapshotFrame()
    local m = SBR.MatchLog:GetCurrent() or SBR.MatchLog:GetHistory()[#SBR.MatchLog:GetHistory()]
    if not m then return end
    local fr = { t = simMs / 1000, state = m.stateName, teams = {}, players = {}, kills = #(m.killFeed or {}),
        fights = 0, result = m.result }
    for id, t in pairs(m.teams or {}) do fr.teams[id] = t.score end
    if m.lf then
        fr.fights = (m.lf.fightList and #m.lf.fightList or 0)
        if m.lf.fights then for _ in pairs(m.lf.fights) do fr.fights = fr.fights + 1 end end
        fr.lfDeaths = #(m.lf.deaths or {})
    end
    local cur = LibFights.GetCurrentFight()
    fr.liveFight = cur and true or false
    for _, p in pairs(m.players) do
        local f = p.fight or {}
        local v = p.vs or {}
        local tops = {}
        for _, a in ipairs(f.topAbilities or {}) do tops[#tops + 1] = { a.name, math.floor(a.damage) } end
        local heals = {}
        for _, a in ipairs(f.topHeals or {}) do heals[#heals + 1] = { a.name, math.floor(a.damage) } end
        local medals = {}
        for _, md in ipairs(p.medals or {}) do medals[#medals + 1] = { md.name, md.count } end
        local function n(x) return type(x) == "number" and math.floor(x * 10 + 0.5) / 10 or nil end
        fr.players[#fr.players + 1] = {
            name = p.characterName, acct = p.displayName, team = p.team, cls = p.className, isLocal = p.isLocal and true or false,
            s = { p.scores.SCORE, p.scores.KILL, p.scores.DEATH, p.scores.ASSISTS, p.scores.DAMAGE_DONE, p.scores.HEALING_DONE, p.scores.FLAG_CAPTURED },
            medals = medals, medalCount = p.medalCount,
            f = { dps = n(f.dps), hps = n(f.hps), taken = n(f.damageTaken), healed = n(f.healingTaken), kbs = f.killingBlows,
                  intr = f.interrupts, cc = f.ccApplied, ccTaken = f.ccTaken, shield = n(f.damageShielded), crit = n(f.critRate),
                  maxHit = f.maxHit, maxAb = f.maxHitAbility, dmg = n(f.damageDone), heal = n(f.healingDone),
                  deaths = f.deaths, active = n(f.activeTime), fights = f.fights, src = f.source,
                  la = f.lightAttacks, ha = f.heavyAttacks, mit = n(f.mitigated) },
            vs = { dealt = v.damageFromYou, took = v.damageToYou, heal = v.healedByYou, healedYou = v.healedYou,
                   killed = v.killedByYou, by = v.killedYou },
            top = tops, topHeals = heals,
        }
    end
    FRAMES[#FRAMES + 1] = fr
end

local function enemiesOf(p, aliveOnly)
    local list = {}
    for _, q in ipairs(P) do if q.team ~= p.team and (q.alive or not aliveOnly) then list[#list + 1] = q end end
    return list
end
local function alliesOf(p)
    local list = {}
    for _, q in ipairs(P) do if q.team == p.team and q.alive then list[#list + 1] = q end end
    return list
end

local function kill(victim, killer, ability)
    victim.alive = false
    victim.hp = 0
    victim.respawnAt = simMs + 15000
    combat(C.ACTION_RESULT_KILLING_BLOW, ability, killer, victim, 0)
    combat(C.ACTION_RESULT_DIED, ability, killer, victim, 0)
    killer.sc.KILL = killer.sc.KILL + 1
    killer.sc.SCORE = killer.sc.SCORE + 100
    victim.sc.DEATH = victim.sc.DEATH + 1
    for attacker, at in pairs(victim.lastHitBy) do
        if attacker ~= killer and simMs - at < 8000 then
            attacker.sc.ASSISTS = attacker.sc.ASSISTS + 1
            attacker.sc.SCORE = attacker.sc.SCORE + 50
        end
    end
    victim.lastHitBy = {}
    if victim.isLocal then fire(EVENT_UNIT_DEATH_STATE_CHANGED, "player", true) end
    killer.streak = (killer.streak or 0) + 1
    victim.streak = 0
    if not firstBlood then firstBlood = true; award(killer, MEDAL[1]) end
    if killer.streak == 3 then award(killer, MEDAL[6]) end
    if killer.streak == 5 then award(killer, MEDAL[7]) end
    if rand() < 0.25 then award(killer, MEDAL[3]) end
    fire(EVENT_BATTLEGROUND_KILL, victim.raw, victim.acct, victim.team, killer.raw, killer.acct, killer.team, 1, ability[1])
    logline("kill", string.format("%s killed %s with %s", killer.name, victim.name, ability[2]))
end

local function hit(src, tgt)
    local ability = pick(ABILITIES[src.cls])
    local base = 1400 + rand() * 2600
    local dmg = math.floor(base * src.power)
    local crit = rand() < (src.role == "dps" and 0.5 or 0.3)
    if crit then dmg = math.floor(dmg * 1.7) end
    local dot = rand() < 0.3
    local result = dot and (crit and C.ACTION_RESULT_DOT_TICK_CRITICAL or C.ACTION_RESULT_DOT_TICK)
        or (crit and C.ACTION_RESULT_CRITICAL_DAMAGE or C.ACTION_RESULT_DAMAGE)
    if tgt.role == "tank" and rand() < 0.4 then
        result = C.ACTION_RESULT_BLOCKED_DAMAGE
        dmg = math.floor(dmg * 0.4)
    end
    -- shields soak part of the hit on the receiving side
    if rand() < 0.18 then
        local soak = math.floor(dmg * 0.5)
        combat(C.ACTION_RESULT_DAMAGE_SHIELDED, pick(SHIELDS), src, tgt, soak)
        dmg = dmg - soak
    end
    combat(result, ability, src, tgt, dmg)
    src.sc.DAMAGE_DONE = src.sc.DAMAGE_DONE + dmg
    src.sc.SCORE = src.sc.SCORE + math.floor(dmg / 2000)
    tgt.lastHitBy[src] = simMs
    tgt.hp = tgt.hp - dmg
    if src.isLocal or tgt.isLocal then ME.lastCombatMs = simMs end
    if rand() < 0.03 then combat(C.ACTION_RESULT_STUNNED, ability, src, tgt, 0) end
    if rand() < 0.012 then combat(C.ACTION_RESULT_INTERRUPT, { 21970, "Bash" }, src, tgt, 0) end
    if tgt.hp <= 0 then kill(tgt, src, ability) end
end

local function heal(src)
    local allies = alliesOf(src)
    table.sort(allies, function(a, b) return a.hp / a.maxHp < b.hp / b.maxHp end)
    local tgt = allies[1]
    if not tgt or tgt.hp >= tgt.maxHp then tgt = src end
    local abilities = HEALS[src.cls] or HEALS.TE
    local ability = pick(abilities)
    local amount = math.floor((src.role == "heal" and 2600 or 900) * (0.7 + rand() * 0.8))
    local crit = rand() < 0.35
    if crit then amount = math.floor(amount * 1.5) end
    local result = rand() < 0.4 and (crit and C.ACTION_RESULT_HOT_TICK_CRITICAL or C.ACTION_RESULT_HOT_TICK)
        or (crit and C.ACTION_RESULT_CRITICAL_HEAL or C.ACTION_RESULT_HEAL)
    local effective = math.min(amount, tgt.maxHp - tgt.hp)
    if effective <= 0 then return end
    tgt.hp = tgt.hp + effective
    combat(result, ability, src, tgt, effective) -- only visible for your team
    src.sc.HEALING_DONE = src.sc.HEALING_DONE + effective
    src.sc.SCORE = src.sc.SCORE + math.floor(effective / 2500)
    if src.role == "heal" and rand() < 0.004 then award(src, MEDAL[4]) end
end

-- skirmish focus: groups clash, rest, clash again; the local player is in most fights
local STEP = 250
local function runMatch(cfg, record)
seed = cfg.seed
resetPlayers(cfg)
teamScore[1], teamScore[2] = 0, 0
firstBlood = false
CUR.map, CUR.bgId, CUR.gameType, CUR.gameTypeId = cfg.map, cfg.bgId, cfg.gameType, cfg.gameTypeId
CUR.baseTs = cfg.ts - math.floor(simMs / 1000)
local dm = cfg.gameType == "Deathmatch"
local MATCH_MS = simMs + (dm and 10 or 8) * 60 * 1000
local startMs = simMs
local nextFlag = simMs + 70000
local nextScoreboardEvent = simMs
local nextFrame = simMs
CUR.inBG = true
bgState = C.BATTLEGROUND_STATE_PREROUND
fire(EVENT_PLAYER_ACTIVATED)
if record then nativeFragment.cb(nil, "shown") end
simMs = simMs + 3000
bgState = C.BATTLEGROUND_STATE_RUNNING
fire(EVENT_BATTLEGROUND_STATE_CHANGED, C.BATTLEGROUND_STATE_PREROUND, C.BATTLEGROUND_STATE_RUNNING)
if record then snapshotFrame() end
local target = dm and 25 or 5
while simMs < MATCH_MS and teamScore[1] < target and teamScore[2] < target do
    simMs = simMs + STEP
    local phase = math.floor(simMs / 1000) % 45 -- 45s cycles: ~28s of fighting, ~17s rotating
    local fighting = phase < 28
    for _, p in ipairs(P) do
        if not p.alive then
            if simMs >= p.respawnAt then
                p.alive = true; p.hp = p.maxHp
                if p.isLocal then fire(EVENT_UNIT_DEATH_STATE_CHANGED, "player", false) end
            end
        elseif fighting then
            if p.role == "heal" and rand() < 0.55 then
                if rand() < 0.5 then heal(p) end
            elseif rand() < 0.16 then
                local foes = enemiesOf(p, true)
                if #foes > 0 then
                    -- focus fire: prefer whoever is lowest
                    table.sort(foes, function(a, b) return a.hp < b.hp end)
                    local tgt = rand() < 0.5 and foes[1] or pick(foes)
                    hit(p, tgt)
                end
            end
            if p.role ~= "heal" and rand() < 0.03 then heal(p) end
            p.hp = math.min(p.maxHp, p.hp + 60) -- passive regen in combat
        else
            -- out of combat regen (not a combat event)
            p.hp = math.min(p.maxHp, p.hp + 400)
        end
    end
    if dm then
        local k1, k2 = 0, 0
        for _, p in ipairs(P) do if p.team == 1 then k1 = k1 + p.sc.KILL else k2 = k2 + p.sc.KILL end end
        teamScore[1], teamScore[2] = k1, k2
    end
    if not dm and simMs >= nextFlag then
        local team = rand() < 0.53 and 1 or 2
        local carriers = {}
        for _, p in ipairs(P) do if p.team == team and p.alive then carriers[#carriers + 1] = p end end
        local c = pick(carriers)
        teamScore[team] = teamScore[team] + 1
        c.sc.FLAG_CAPTURED = c.sc.FLAG_CAPTURED + 1
        c.sc.SCORE = c.sc.SCORE + 300
        award(c, MEDAL[2])
        logline("flag", string.format("%s captured the flag for %s (%d-%d)", c.name, team == 1 and "Fire Drakes" or "Pit Daemons", teamScore[1], teamScore[2]))
        nextFlag = simMs + randint(60000, 100000)
        fire(EVENT_BATTLEGROUND_SCOREBOARD_UPDATED)
    end
    if simMs >= nextScoreboardEvent then
        fire(EVENT_BATTLEGROUND_SCOREBOARD_UPDATED)
        nextScoreboardEvent = simMs + 2000
    end
    runUpdates()
    if record and simMs >= nextFrame then
        snapshotFrame()
        nextFrame = simMs + 5000
    end
end

-- end of match: post-game, then final record
simMs = simMs + 500
bgState = C.BATTLEGROUND_STATE_FINISHED
fire(EVENT_BATTLEGROUND_STATE_CHANGED, C.BATTLEGROUND_STATE_RUNNING, C.BATTLEGROUND_STATE_FINISHED)
if record then snapshotFrame() end
-- leave the battleground
simMs = simMs + 20000
CUR.inBG = false
fire(EVENT_PLAYER_ACTIVATED)
simMs = simMs + 600000
io.stderr:write(string.format("  %s (%s) %s: %d-%d\n", cfg.map, cfg.gameType, cfg.char, teamScore[1], teamScore[2]))
end

local DAY = 86400
local MATCHES = {
    { seed = 101, map = "Ald Carac", bgId = 11, gameType = "Capture the Flag", gameTypeId = 2, char = "Vashti Emberlock", cls = "AR", ts = 1795468800 - 6 * DAY },
    { seed = 202, map = "Ularra", bgId = 12, gameType = "Deathmatch", gameTypeId = 1, char = "Vashti Emberlock", cls = "AR", ts = 1795468800 - 5 * DAY },
    { seed = 303, map = "Arcane University", bgId = 13, gameType = "Capture the Flag", gameTypeId = 2, char = "Kaelen Frostveil", cls = "WA", ts = 1795468800 - 4 * DAY },
    { seed = 404, map = "Deeping Drome", bgId = 14, gameType = "Deathmatch", gameTypeId = 1, char = "Kaelen Frostveil", cls = "WA", ts = 1795468800 - 3 * DAY },
    { seed = 505, map = "Foyada Quarry", bgId = 42, gameType = "Capture the Flag", gameTypeId = 2, char = "Vashti Emberlock", cls = "AR", ts = 1795468800 - 2 * DAY },
    { seed = 606, map = "Mor Khazgur", bgId = 15, gameType = "Deathmatch", gameTypeId = 1, char = "Vashti Emberlock", cls = "AR", ts = 1795468800 - DAY },
    { seed = 707, map = "Istirus Outpost", bgId = 16, gameType = "Capture the Flag", gameTypeId = 2, char = "Kaelen Frostveil", cls = "WA", ts = 1795468800 - 40000 },
    { seed = 11, map = "Foyada Quarry", bgId = 42, gameType = "Capture the Flag", gameTypeId = 2, char = "Vashti Emberlock", cls = "AR", ts = 1795468800 },
}
for i, cfg in ipairs(MATCHES) do runMatch(cfg, i == #MATCHES) end

local final = SBR.MatchLog:GetHistory()[#SBR.MatchLog:GetHistory()]

-- drive the real match browser through its views and keep what it rendered
IsInGamepadPreferredMode = function() return true end
local MB = SBR.MatchBrowser
MB:Create()
local function grab(view)
    MB:Render()
    local rows = {}
    for _, r in ipairs(MB.rows) do
        if not r:IsHidden() then rows[#rows + 1] = { r.map:GetText(), r.meta:GetText(), r.kda:GetText(), r.result:GetText() } end
    end
    local tiles = {}
    for _, t in ipairs(MB.tiles) do tiles[#tiles + 1] = { t.value:GetText(), t.label:GetText() } end
    local bars = {}
    for _, b in ipairs(MB.bars) do if not b:IsHidden() then bars[#bars + 1] = { b.name:GetText(), b.value:GetText() } end end
    local medals = {}
    for _, m in ipairs(MB.medals) do if not m:IsHidden() then medals[#medals + 1] = { m.name:GetText(), m.count:GetText() } end end
    return { view = view, sub = MB.listSub:GetText(), chips = { MB.chips[1].value:GetText(), MB.chips[2].value:GetText(), MB.chips[3].value:GetText() },
             rows = rows, result = MB.result:GetText(), title = MB.title:GetText(), meta = MB.meta:GetText(), teams = MB.teams:GetText(),
             tiles = tiles, rank = MB.rank:GetText(), bars = bars, medals = medals, highlights = MB.highlights:GetText(), footer = MB.footer:GetText() }
end
local BROWSER = {}
MB:Reload()
BROWSER[#BROWSER + 1] = grab("newest")
MB:Move(2); BROWSER[#BROWSER + 1] = grab("third row")
MB:CycleSort(); MB:CycleSort(); MB:CycleSort(); MB:CycleSort(); BROWSER[#BROWSER + 1] = grab("sorted by damage")
MB:CycleFilter(1); BROWSER[#BROWSER + 1] = grab("victories")
MB.card = "life"; BROWSER[#BROWSER + 1] = grab("lifetime")
MB.card = "match"
MB:SetTab("players"); BROWSER[#BROWSER + 1] = grab("players")
MB:Move(1); BROWSER[#BROWSER + 1] = grab("players second")
MB:CycleFilter(1); MB:CycleFilter(1); BROWSER[#BROWSER + 1] = grab("players opponents")
for _ = 1, 5 do MB:CycleSort() end; BROWSER[#BROWSER + 1] = grab("opponents by killed you")
MB:CycleFilter(1); MB:CycleFilter(1); BROWSER[#BROWSER + 1] = grab("you")
MB:SetTab("matches"); BROWSER[#BROWSER + 1] = grab("back to matches")

-- inventory hooks: PC button and gamepad keybind
local inv = SBR.InventoryHook
local invOut = { button = inv.button ~= nil, hooked = {} }
for n in pairs(inv.hookedScenes) do invOut.hooked[#invOut.hooked + 1] = n end
for _, f in ipairs(SCENE_MANAGER.scenes.gamepad_inventory_root.cbs) do f(nil, "shown") end
invOut.gamepadKeybind = inv.keybindAdded and inv.keybind[1].name .. " on " .. inv.keybind[1].keybind or "none"
for _, f in ipairs(SCENE_MANAGER.scenes.gamepad_inventory_root.cbs) do f(nil, "hiding") end
invOut.removed = not inv.keybindAdded
local out = {
    records = SBR.MatchDB:GetRecords(),
    aggregate = (function() local a = SBR.MatchDB:Aggregate(SBR.MatchDB:GetRecords()); a.bestDamage = a.bestDamage and a.bestDamage.id; a.bestKills = a.bestKills and a.bestKills.id; a.bestHealing = a.bestHealing and a.bestHealing.id; return a end)(),
    browser = BROWSER,
    inventory = invOut,
    players = (function()
        local list = {}
        for _, e in ipairs(SBR.MatchDB:QueryPlayers("all", "seen")) do
            local sum = SBR.MatchDB:PlayerSummary(e)
            local copy = {}
            for k, v in pairs(e) do if type(v) ~= "table" then copy[k] = v end end
            copy.relation = sum.relation
            copy.classes = sum.classes
            copy.abilities = sum.abilities
            copy.maps = sum.maps
            copy.characters = sum.characters
            list[#list + 1] = copy
        end
        return list
    end)(),
    frames = FRAMES,
    log = LOG,
    killFeedText = SBR.Export:BuildKillFeed(final),
    csv = SBR.Export:BuildCSV(final),
    result = final.result,
    duration = final.duration,
    fightList = final.lf and final.lf.fightList or {},
}

---------------------------------------------------------------------------
-- JSON
---------------------------------------------------------------------------
local function isArray(t)
    local n = 0
    for k in pairs(t) do
        if type(k) ~= "number" then return false end
        n = n + 1
    end
    for i = 1, n do if t[i] == nil then return false end end
    return true
end
local function esc(s)
    return '"' .. s:gsub('[%c"\\]', function(c)
        if c == '"' then return '\\"' elseif c == "\\" then return "\\\\" elseif c == "\n" then return "\\n" end
        return string.format("\\u%04x", c:byte())
    end) .. '"'
end
local function enc(v)
    local t = type(v)
    if t == "nil" then return "null" end
    if t == "boolean" then return tostring(v) end
    if t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return "null" end
        if v == math.floor(v) then return string.format("%d", v) end
        return string.format("%.1f", v)
    end
    if t == "string" then return esc(v) end
    if t == "table" then
        local parts = {}
        if isArray(v) then
            for i = 1, #v do parts[i] = enc(v[i]) end
            return "[" .. table.concat(parts, ",") .. "]"
        end
        for k, val in pairs(v) do parts[#parts + 1] = esc(tostring(k)) .. ":" .. enc(val) end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return "null"
end
local fh = io.open(OUT, "w")
fh:write(enc(out))
fh:close()
io.stderr:write(string.format("frames=%d log=%d result=%s duration=%s fights=%d final score %d-%d\n",
    #FRAMES, #LOG, tostring(final.result), tostring(final.duration), #out.fightList, teamScore[1], teamScore[2]))


---------------------------------------------------------------------------
-- Screens: drive the add-on's UI and record its control trees for rendering
---------------------------------------------------------------------------
if SCREENS_OUT then
    local function serialize(c)
        local node = { id = c._id, name = c._name, kind = c._kind, virtual = c._virtual, hidden = c._hidden,
            w = c._w, h = c._h, color = c._color, alpha = c._alpha, text = c._text, font = c._font,
            halign = c._halign, valign = c._valign, texture = c._texture, upper = c._upper, wrap = c._wrap,
            anchors = {}, children = {} }
        for _, a in ipairs(c._anchors) do
            node.anchors[#node.anchors + 1] = { a[1], a[2] and a[2]._id or GuiRoot._id, a[3], a[4], a[5] }
        end
        for _, ch in ipairs(c._children) do node.children[#node.children + 1] = serialize(ch) end
        return node
    end
    local function roots()
        local out = {}
        for _, c in ipairs(ALL) do if not c._parent then out[#out + 1] = serialize(c) end end
        return out
    end
    local function strip()
        local out = {}
        for _, g in ipairs(KEYBIND_STRIP.order) do
            local grp = { align = g.alignment == KEYBIND_STRIP_ALIGN_RIGHT and "right" or "left", buttons = {} }
            for _, b in ipairs(g) do
                local vis = b.visible == nil or (type(b.visible) == "function" and b.visible()) or b.visible == true
                if vis and not b.ethereal then
                    local name = type(b.name) == "function" and b.name() or b.name
                    grp.buttons[#grp.buttons + 1] = { key = b.keybind, name = name }
                end
            end
            out[#out + 1] = grp
        end
        return out
    end
    local SCREENS = {}
    local function consoleState(scr)
        local entries = {}
        for i, e in ipairs(scr.list.entries) do
            entries[i] = { text = e.data.text, icon = e.data.icon, header = e.data.header }
        end
        local tip = GAMEPAD_TOOLTIPS.current[GAMEPAD_RIGHT_TOOLTIP]
        return { header = { data = scr.header.data, tab = scr.header.tab }, entries = entries, selected = scr.list.selected,
                 tooltip = tip or {} }
    end
    local function consoleScreen(id, title, scr, standins)
        SCREENS[#SCREENS + 1] = { id = id, title = title, mode = "gamepad", draw = {}, standins = standins or { "world" },
            strip = (function()
                local out = {}
                for _, g in ipairs(KEYBIND_STRIP.order) do
                    local grp = { align = g.alignment == KEYBIND_STRIP_ALIGN_RIGHT and "right" or "left", buttons = {} }
                    for _, b in ipairs(g) do
                        local vis = b.visible == nil or (type(b.visible) == "function" and b.visible()) or b.visible == true
                        if vis and not b.ethereal then
                            grp.buttons[#grp.buttons + 1] = { key = b.keybind, name = type(b.name) == "function" and b.name() or b.name }
                        end
                    end
                    out[#out + 1] = grp
                end
                return out
            end)(), trees = {}, console = consoleState(scr) }
        io.stderr:write("screen " .. id .. "\n")
    end
    local function screen(id, title, mode, draw, standins)
        SCREENS[#SCREENS + 1] = { id = id, title = title, mode = mode, draw = draw, standins = standins,
            strip = strip(), trees = roots(), shortcutLayer = IsActionLayerActiveByName("User Interface Shortcuts") }
        io.stderr:write("screen " .. id .. "\n")
    end
    local W, GP, MB = SBR.Window, SBR.Gamepad, SBR.MatchBrowser
    local lastMatch = SBR.MatchLog:GetHistory()[#SBR.MatchLog:GetHistory()]
    local function find(pred)
        local list = W.sortedPlayers or {}
        for _, p in ipairs(list) do if pred(p) then return p end end
    end

    -- 1. PC: the native scoreboard opens and the panel appears over it, details open on your row
    IsInGamepadPreferredMode = function() return false end
    MB.tab, MB.filter, MB.sort, MB.selected, MB.offset, MB.card = "matches", 1, 1, 1, 0, "match"
    W.viewIndex = nil
    nativeFragment.cb(nil, "shown")
    W:Select(find(function(p) return p.isLocal end))
    W:OpenDetails()
    screen("pc-scoreboard", "PC: the panel over the battleground scoreboard, your row's details open",
        "keyboard", { "ScoreboardRemasteredDim", "ScoreboardRemasteredWindow" }, { "world", "nativeScoreboard" })
    W:CloseDetails()
    nativeFragment.cb(nil, "hidden")

    -- 2. Gamepad: the native scoreboard's button bar gets "Open Remastered"
    IsInGamepadPreferredMode = function() return true end
    nativeFragment.cb(nil, "shown")
    screen("gamepad-native", "Gamepad: Open Remastered on the battleground scoreboard's button bar",
        "gamepad", {}, { "world", "nativeScoreboard" })
    nativeFragment.cb(nil, "hidden")

    -- 3-5. Console: Scoreboard Remastered (Players / Kill feed / Match)
    local C = SBR.Console
    GP:Open("players")
    C.scoreboard.list:SetSelectedIndex(4)
    consoleScreen("console-scoreboard", "Console: Scoreboard Remastered, Players tab", C.scoreboard)
    C.scoreboard.tab = "kills"; C.scoreboard.header.tab = 2; C.scoreboard:Update()
    C.scoreboard.list:SetSelectedIndex(1)
    consoleScreen("console-killfeed", "Console: Scoreboard Remastered, Kill feed tab", C.scoreboard)
    C.scoreboard.tab = "match"; C.scoreboard.header.tab = 3; C.scoreboard:Update()
    C.scoreboard.list:SetSelectedIndex(2)
    consoleScreen("console-match", "Console: Scoreboard Remastered, Match tab (your LibFights fights)", C.scoreboard)
    C.scoreboard.tab = "players"; C.scoreboard.header.tab = 1

    -- 6-8. Console: Battleground records (Matches / Players / Lifetime), opened with Y / Triangle
    C.records:Open("matches")
    C.records.list:SetSelectedIndex(1)
    consoleScreen("console-records-matches", "Console: Battleground records, Matches tab", C.records)
    C.records.tab = "players"; C.records.header.tab = 2
    C.records.state.players.filter, C.records.state.players.sort = 3, 6   -- Opponents, sorted by "Killed you"
    C.records:Update()
    C.records.list:SetSelectedIndex(1)
    consoleScreen("console-records-players", "Console: Battleground records, Players tab (opponents, by who killed you most)", C.records)
    C.records.tab = "lifetime"; C.records.header.tab = 3; C.records:Update()
    C.records.list:SetSelectedIndex(1)
    consoleScreen("console-records-lifetime", "Console: Battleground records, Lifetime tab", C.records)
    SCENE_MANAGER:HideCurrentScene()
    SCENE_MANAGER:HideCurrentScene()

    -- 8. Gamepad inventory: "Battleground records" on its button bar
    for _, f in ipairs(SCENE_MANAGER.scenes.gamepad_inventory_root.cbs) do f(nil, "shown") end
    screen("gamepad-inventory", "Gamepad inventory: Battleground records on the button bar",
        "gamepad", {}, { "world", "gamepadInventory" })
    for _, f in ipairs(SCENE_MANAGER.scenes.gamepad_inventory_root.cbs) do f(nil, "hiding") end

    -- 9. PC inventory: the button above the inventory window
    IsInGamepadPreferredMode = function() return false end
    for _, f in ipairs(SCENE_MANAGER.scenes.inventory.cbs) do f(nil, "showing") end
    ZO_PlayerInventory:SetHidden(false)
    screen("pc-inventory", "PC inventory: the Battleground records button",
        "keyboard", { "ZO_PlayerInventory" }, { "world", "pcInventory" })
    ZO_PlayerInventory:SetHidden(true)

    -- 10. PC: Battleground records with the mouse (Players tab)
    MB:SetTabSilently("players")
    MB.filter, MB.sort, MB.selected, MB.offset = 1, 1, 1, 0
    MB:Open()
    MB.items = MB:Query()
    MB.selected = 2
    MB:Render()
    screen("pc-records", "PC: Battleground records with the mouse, Players tab",
        "keyboard", { "ScoreboardRemasteredMatchBrowser" }, { "world" })

    -- data for the native stand-ins
    local final = FRAMES[#FRAMES]
    local out2 = { screens = SCREENS, native = { map = lastMatch.name, teams = lastMatch.teams, players = final.players,
        localTeam = lastMatch.localTeam, result = lastMatch.result, duration = lastMatch.duration } }
    local fh2 = io.open(SCREENS_OUT, "w")
    fh2:write(enc(out2))
    fh2:close()
end
