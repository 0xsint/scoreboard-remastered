-- Console / gamepad entry points.
--
-- In gamepad mode (always on console, or gamepad mode on PC) everything opens the
-- native-framework screens in UI/Console.lua:
--   Scoreboard Remastered   tabs Players / Kill feed / Match
--   Battleground records    tabs Matches / Players / Lifetime
-- While the native battleground scoreboard is open, "Open Remastered" (right stick
-- click by default) is added to its keybind strip.
local SBR = ScoreboardRemastered
local GP = {}
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

function GP:Init()
    if self.initialized then return end
    self.initialized = true
    -- switching between keyboard and gamepad mode on PC closes whichever view is open
    if EVENT_GAMEPAD_PREFERRED_MODE_CHANGED then
        EVENT_MANAGER:RegisterForEvent(SBR.name .. "_GamepadMode", EVENT_GAMEPAD_PREFERRED_MODE_CHANGED, function()
            if GP:IsShowing() then GP:Close() end
            SBR.Window:Hide(true)
            GP:RemoveOpenKeybind()
        end)
    end
end

local function Screen() return SBR.Console and SBR.Console.scoreboard end

function GP:IsShowing()
    local s = Screen()
    return s ~= nil and s:IsShowingScene()
end

-- tab: optional "players" | "kills" | "match"
function GP:Open(tab)
    local s = Screen()
    if not s then return end
    if tab and s.tab ~= tab then
        s.tab = tab
        local index = ({ players = 1, kills = 2, match = 3 })[tab]
        if index then ZO_GamepadGenericHeader_SetActiveTabIndex(s.header, index) end
    end
    s:Open()
end

function GP:Close()
    local s = Screen()
    if s then s:Close() end
end

-- kept for callers in Window.lua; the native screens manage their own keybinds
function GP:UpdateKeybinds()
    local s = Screen()
    if s and s:IsShowingScene() then s:RefreshKeybinds() end
end

-- "Open Remastered" on the native battleground scoreboard's keybind strip.
function GP:AddOpenKeybind()
    if not KEYBIND_STRIP or self.openKeybindAdded then return end
    local key = OPEN_KEYS[SBR.sv.gamepadOpenKey] or OPEN_KEYS.right_stick
    self.openKeybind = {
        alignment = KEYBIND_STRIP_ALIGN_RIGHT,
        {
            name = "Open Remastered",
            keybind = key.keybind,
            callback = function() GP:Open("players") end,
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
