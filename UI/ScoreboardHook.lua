-- Hooks the native battleground scoreboard: our panel opens/closes with it,
-- anchors next to it, and refreshes when the native one refreshes.
--
-- ZOS has renamed the scoreboard objects across updates, so instead of relying
-- on one name this discovers every scene/fragment/object whose name looks like
-- the battleground scoreboard. `/sbr hooks` lists what was found.
local SBR = ScoreboardRemastered
local Hook = { fragments = {}, scenes = {}, objects = {}, visible = {} }
SBR.Hook = Hook

local FRAGMENT_NAMES = {
    "BATTLEGROUND_SCOREBOARD_FRAGMENT",
    "KEYBOARD_BATTLEGROUND_SCOREBOARD_FRAGMENT",
    "BATTLEGROUND_SCOREBOARD_KEYBOARD_FRAGMENT",
    "BATTLEGROUND_SCOREBOARD_END_OF_GAME_FRAGMENT",
    "GAMEPAD_BATTLEGROUND_SCOREBOARD_FRAGMENT",
}
local OBJECT_NAMES = {
    "BATTLEGROUND_SCOREBOARD",
    "BATTLEGROUND_SCOREBOARD_KEYBOARD",
    "KEYBOARD_BATTLEGROUND_SCOREBOARD",
    "BATTLEGROUND_SCOREBOARD_END_OF_GAME",
    "ZO_BATTLEGROUND_SCOREBOARD",
}
local REFRESH_METHODS = { "UpdateAll", "RefreshAll", "UpdateScores", "RefreshScores", "OnScoreboardUpdated", "UpdateEntries", "Refresh" }
local CONTROL_NAMES = {
    "ZO_BattlegroundScoreboardTopLevel",
    "ZO_BattlegroundScoreboard_KeyboardTopLevel",
    "ZO_Battleground_Scoreboard_KeyboardTopLevel",
    "ZO_BattlegroundScoreboardEndOfGameTopLevel",
}

local SHOWN = { [SCENE_SHOWN or "shown"] = true, [SCENE_FRAGMENT_SHOWN or "shown"] = true }
local HIDDEN = { [SCENE_HIDDEN or "hidden"] = true, [SCENE_FRAGMENT_HIDDEN or "hidden"] = true,
                 [SCENE_HIDING or "hiding"] = true, [SCENE_FRAGMENT_HIDING or "hiding"] = true }

local function IsScoreboardName(name)
    local n = name:lower()
    return n:find("battleground", 1, true) and n:find("scoreboard", 1, true)
end

function Hook:OnVisibility(id, control, newState)
    if SHOWN[newState] then
        self.visible[id] = control or true
        if control then self.anchorControl = control end
        SBR.Debug("native scoreboard shown (%s)", id)
        SBR.MatchLog:RequestSnapshot()
        SBR.Window:OnNativeShown()
    elseif HIDDEN[newState] then
        self.visible[id] = nil
        if next(self.visible) == nil then
            SBR.Debug("native scoreboard hidden (%s)", id)
            SBR.Window:OnNativeHidden()
        end
    end
end

function Hook:IsNativeVisible()
    return next(self.visible) ~= nil
end

function Hook:GetAnchorControl()
    if self.anchorControl and not self.anchorControl:IsHidden() then return self.anchorControl end
    for _, name in ipairs(CONTROL_NAMES) do
        local c = _G[name]
        if type(c) == "userdata" and not c:IsHidden() then return c end
    end
    return nil
end

function Hook:HookFragment(name, fragment)
    if type(fragment) ~= "table" or type(fragment.RegisterCallback) ~= "function" or self.fragments[name] then return end
    self.fragments[name] = fragment
    local control = fragment.control or (fragment.GetControl and SBR.SafeCall(fragment.GetControl, fragment))
    fragment:RegisterCallback("StateChange", function(_, newState)
        Hook:OnVisibility("fragment:" .. name, control, newState)
    end)
end

function Hook:HookScene(name, scene)
    if type(scene) ~= "table" or type(scene.RegisterCallback) ~= "function" or self.scenes[name] then return end
    self.scenes[name] = scene
    scene:RegisterCallback("StateChange", function(_, newState)
        Hook:OnVisibility("scene:" .. name, nil, newState)
    end)
end

function Hook:HookObject(name, obj)
    if type(obj) ~= "table" or self.objects[name] then return end
    local hooked = {}
    for _, method in ipairs(REFRESH_METHODS) do
        if type(obj[method]) == "function" then
            ZO_PostHook(obj, method, function() SBR.MatchLog:RequestSnapshot() end)
            hooked[#hooked + 1] = method
        end
    end
    if #hooked > 0 then self.objects[name] = hooked end
end

function Hook:Install()
    for _, n in ipairs(FRAGMENT_NAMES) do self:HookFragment(n, _G[n]) end
    for _, n in ipairs(OBJECT_NAMES) do self:HookObject(n, _G[n]) end

    SBR.ForEachGlobal(function(k, v)
        if type(v) == "table" and IsScoreboardName(k) then
            if k:find("FRAGMENT$") then
                self:HookFragment(k, v)
            elseif k:find("SCENE$") then
                self:HookScene(k, v)
            elseif not k:find("^SI_") then
                self:HookObject(k, v)
            end
        end
    end)

    if SCENE_MANAGER and type(SCENE_MANAGER.scenes) == "table" then
        for name, scene in pairs(SCENE_MANAGER.scenes) do
            if type(name) == "string" and IsScoreboardName(name) then self:HookScene(name, scene) end
        end
    end
end

function Hook:Report()
    local function keys(t)
        local list = {}
        for k, v in pairs(t) do
            list[#list + 1] = type(v) == "table" and #v > 0 and (k .. "(" .. table.concat(v, ",") .. ")") or k
        end
        table.sort(list)
        return #list > 0 and table.concat(list, ", ") or "none"
    end
    SBR.Print("fragments: %s", keys(self.fragments))
    SBR.Print("scenes: %s", keys(self.scenes))
    SBR.Print("objects: %s", keys(self.objects))
    local a = self:GetAnchorControl()
    SBR.Print("anchor control: %s", a and a:GetName() or "none (native scoreboard not open)")
end
