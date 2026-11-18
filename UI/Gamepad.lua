-- Console / gamepad support.
--
-- In gamepad mode (always on console, or "Gamepad mode" on PC) the panel runs
-- in its own scene with a keybind strip and a selected row instead of a mouse:
--   D-pad / left stick up-down   move the selected row
--   D-pad / left stick left-right sort by the previous / next column
--   A (Xbox) / Cross (PlayStation)  show / hide details for the selected row
--   B / Circle                     close details, then close the panel
--   X / Square                     flip the sort order
--   Y / Triangle                   kill feed
--   LB / RB (L1 / R1)              previous / next saved match
--   Left stick click (L3)          group by team on / off
--   Right stick click (R3)         battleground records (UI/MatchBrowser.lua)
-- While the native battleground scoreboard is open, an "Open Remastered"
-- button (right stick click by default) is added to its keybind strip.
local SBR = ScoreboardRemastered
local GP = { sceneName = "scoreboardRemasteredGamepad" }
SBR.Gamepad = GP

function SBR.IsGamepad()
    if type(IsConsoleUI) == "function" and IsConsoleUI() then return true end
    return type(IsInGamepadPreferredMode) == "function" and IsInGamepadPreferredMode() == true
end

function SBR.IsConsole()
    return type(IsConsoleUI) == "function" and IsConsoleUI() == true
end

local OPEN_KEYS = {
    right_stick = { keybind = "UI_SHORTCUT_RIGHT_STICK", label = "Right stick click" },
    left_stick = { keybind = "UI_SHORTCUT_LEFT_STICK", label = "Left stick click" },
    quaternary = { keybind = "UI_SHORTCUT_QUATERNARY", label = "Quaternary button" },
}
GP.OPEN_KEYS = OPEN_KEYS

local function Reader() return SBR.Export.reader end
local function ReaderOpen() return Reader() and Reader():IsOpen() end

function GP:Init()
    if self.scene or not (ZO_Scene and SCENE_MANAGER and KEYBIND_STRIP and DIRECTIONAL_INPUT and ZO_MovementController) then
        return
    end
    local W = SBR.Window
    W:Create()

    self.fragment = ZO_SimpleSceneFragment:New(W.control)
    local scene = ZO_Scene:New(self.sceneName, SCENE_MANAGER)
    scene:AddFragment(self.fragment)
    if FRAGMENT_GROUP then
        for _, group in ipairs({ FRAGMENT_GROUP.GAMEPAD_DRIVEN_UI_WINDOW, FRAGMENT_GROUP.GAMEPAD_KEYBIND_STRIP_GROUP }) do
            if group then scene:AddFragmentGroup(group) end
        end
    end
    scene:RegisterCallback("StateChange", function(_, newState)
        if newState == SCENE_SHOWN then
            GP:OnShown()
        elseif newState == SCENE_HIDING then
            GP:OnHiding()
        end
    end)
    self.scene = scene

    self.vertical = ZO_MovementController:New(MOVEMENT_CONTROLLER_DIRECTION_VERTICAL)
    self.horizontal = ZO_MovementController:New(MOVEMENT_CONTROLLER_DIRECTION_HORIZONTAL)
    self:BuildKeybinds()

    -- switching between keyboard and gamepad mode on PC closes whichever view is open
    if EVENT_GAMEPAD_PREFERRED_MODE_CHANGED then
        EVENT_MANAGER:RegisterForEvent(SBR.name .. "_GamepadMode", EVENT_GAMEPAD_PREFERRED_MODE_CHANGED, function()
            if GP:IsShowing() then SCENE_MANAGER:HideCurrentScene() end
            if W.mode == "keyboard" then W:Hide(true) end
            GP:RemoveOpenKeybind()
        end)
    end
end

function GP:IsShowing()
    return self.scene ~= nil and self.scene:IsShowing()
end

function GP:Open()
    self:Init()
    if not self.scene or self:IsShowing() then return end
    SCENE_MANAGER:Push(self.sceneName)
end

function GP:Close()
    if self:IsShowing() then SCENE_MANAGER:HideCurrentScene() end
end

function GP:OnShown()
    SBR.Window:OnGamepadShown()
    KEYBIND_STRIP:AddKeybindButtonGroup(self.keybinds)
    DIRECTIONAL_INPUT:Activate(self, SBR.Window.control)
end

function GP:OnHiding()
    DIRECTIONAL_INPUT:Deactivate(self)
    KEYBIND_STRIP:RemoveKeybindButtonGroup(self.keybinds)
    if ReaderOpen() then Reader():Close() end
    SBR.Window:OnGamepadHidden()
end

-- Called every frame by DIRECTIONAL_INPUT while the scene is shown.
function GP:UpdateDirectionalInput()
    local v = self.vertical:CheckMovement()
    local h = self.horizontal:CheckMovement()
    local W = SBR.Window
    if ReaderOpen() then
        if v == MOVEMENT_CONTROLLER_MOVE_NEXT then Reader():Scroll(1)
        elseif v == MOVEMENT_CONTROLLER_MOVE_PREVIOUS then Reader():Scroll(-1) end
        if h == MOVEMENT_CONTROLLER_MOVE_NEXT then Reader():Scroll(Reader():PageSize())
        elseif h == MOVEMENT_CONTROLLER_MOVE_PREVIOUS then Reader():Scroll(-Reader():PageSize()) end
        return
    end
    if v == MOVEMENT_CONTROLLER_MOVE_NEXT then W:MoveSelection(1)
    elseif v == MOVEMENT_CONTROLLER_MOVE_PREVIOUS then W:MoveSelection(-1) end
    if h == MOVEMENT_CONTROLLER_MOVE_NEXT then W:CycleSort(1)
    elseif h == MOVEMENT_CONTROLLER_MOVE_PREVIOUS then W:CycleSort(-1) end
end

function GP:BuildKeybinds()
    local W = SBR.Window
    local function table_() return not ReaderOpen() end
    self.keybinds = {
        alignment = KEYBIND_STRIP_ALIGN_LEFT,
        {
            name = function() return W.detailsOpen and "Hide details" or "Details" end,
            keybind = "UI_SHORTCUT_PRIMARY",
            callback = function() W:ToggleDetails() end,
            visible = table_,
        },
        {
            name = function()
                if ReaderOpen() then return "Close" end
                return "Back"
            end,
            keybind = "UI_SHORTCUT_NEGATIVE",
            callback = function()
                if ReaderOpen() then
                    Reader():Close()
                    GP:UpdateKeybinds()
                elseif W.detailsOpen then
                    W:CloseDetails()
                else
                    GP:Close()
                end
            end,
        },
        {
            name = "Sort order",
            keybind = "UI_SHORTCUT_SECONDARY",
            callback = function() W:ToggleSortOrder() end,
            visible = table_,
        },
        {
            name = "Kill feed",
            keybind = "UI_SHORTCUT_TERTIARY",
            callback = function()
                SBR.Export:ShowKillFeed(W:GetViewedMatch())
                GP:UpdateKeybinds()
            end,
            visible = table_,
        },
        {
            name = "Older",
            keybind = "UI_SHORTCUT_LEFT_SHOULDER",
            callback = function() W:Step(-1) end,
            visible = function() return table_() and #SBR.MatchLog:GetHistory() > 0 end,
        },
        {
            name = "Newer",
            keybind = "UI_SHORTCUT_RIGHT_SHOULDER",
            callback = function() W:Step(1) end,
            visible = function() return table_() and W.viewIndex ~= nil end,
        },
        {
            name = "Records",
            keybind = "UI_SHORTCUT_RIGHT_STICK",
            callback = function() SBR.MatchBrowser:Open() end,
            visible = table_,
        },
        {
            name = function() return SBR.sv.groupByTeam and "Ungroup" or "Group" end,
            keybind = "UI_SHORTCUT_LEFT_STICK",
            callback = function() W:ToggleGroupByTeam() end,
            visible = table_,
        },
    }
end

function GP:UpdateKeybinds()
    if self.keybinds and self:IsShowing() then
        KEYBIND_STRIP:UpdateKeybindButtonGroup(self.keybinds)
    end
end

-- "Open Remastered" on the native gamepad scoreboard's keybind strip.
function GP:AddOpenKeybind()
    self:Init()
    if not KEYBIND_STRIP or self.openKeybindAdded then return end
    local key = OPEN_KEYS[SBR.sv.gamepadOpenKey] or OPEN_KEYS.right_stick
    self.openKeybind = {
        alignment = KEYBIND_STRIP_ALIGN_RIGHT,
        {
            name = "Open Remastered",
            keybind = key.keybind,
            callback = function() GP:Open() end,
        },
    }
    KEYBIND_STRIP:AddKeybindButtonGroup(self.openKeybind)
    self.openKeybindAdded = true
end

function GP:RemoveOpenKeybind()
    if self.openKeybindAdded and KEYBIND_STRIP then
        KEYBIND_STRIP:RemoveKeybindButtonGroup(self.openKeybind)
    end
    self.openKeybindAdded = false
end
