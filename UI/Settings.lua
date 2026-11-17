-- Optional LibAddonMenu-2.0 settings panel. Everything here is also reachable via /sbr.
local SBR = ScoreboardRemastered
local Settings = {}
SBR.Settings = Settings

function Settings:Create()
    local LAM = LibAddonMenu2 or (LibStub and LibStub("LibAddonMenu-2.0", true))
    if not LAM then return end
    local sv = SBR.sv

    LAM:RegisterAddonPanel("ScoreboardRemasteredOptions", {
        type = "panel",
        name = "Scoreboard Remastered",
        displayName = SBR.displayName,
        version = SBR.version,
        registerForRefresh = true,
    })

    local function refresh() SBR.Window:Refresh() end
    LAM:RegisterOptionControls("ScoreboardRemasteredOptions", {
        { type = "header", name = "Display" },
        { type = "checkbox", name = "Open with the native scoreboard",
          getFunc = function() return sv.autoShowWithScoreboard end,
          setFunc = function(v) sv.autoShowWithScoreboard = v end },
        { type = "dropdown", name = "Attach position", choices = { "right", "left", "below", "free" },
          tooltip = "Where the panel sits relative to the native scoreboard. Dragging the panel stores a fixed position.",
          getFunc = function() return sv.attach end,
          setFunc = function(v) sv.attach = v; SBR.Window:ResetPosition() end },
        { type = "button", name = "Reset position", func = function() SBR.Window:ResetPosition() end },
        { type = "slider", name = "Scale", min = 60, max = 150, step = 5,
          getFunc = function() return math.floor((sv.scale or 1) * 100) end,
          setFunc = function(v)
              sv.scale = v / 100
              if SBR.Window.control then SBR.Window.control:SetScale(sv.scale) end
          end },
        { type = "checkbox", name = "Group rows by team",
          getFunc = function() return sv.groupByTeam end, setFunc = function(v) sv.groupByTeam = v; refresh() end },
        { type = "checkbox", name = "Hide columns that are all zero",
          getFunc = function() return sv.hideEmptyColumns end, setFunc = function(v) sv.hideEmptyColumns = v; refresh() end },
        { type = "checkbox", name = "Show LibFights / fight columns",
          getFunc = function() return sv.showFightColumns end, setFunc = function(v) sv.showFightColumns = v; refresh() end },
        { type = "checkbox", name = "Show 'you vs them' columns",
          getFunc = function() return sv.showVsColumns end, setFunc = function(v) sv.showVsColumns = v; refresh() end },
        { type = "header", name = "LibFights" },
        { type = "checkbox", name = "Use LibFights", disabled = function() return not SBR.LibFights:IsAvailable() end,
          tooltip = "Starts LibFights logging for each battleground (unless it's already running) and stops it again afterwards.",
          getFunc = function() return sv.useLibFights end, setFunc = function(v) sv.useLibFights = v end },
        { type = "checkbox", name = "Also save fights in LibFights' SavedVariables",
          getFunc = function() return sv.lfSaveFights end, setFunc = function(v) sv.lfSaveFights = v end },
        { type = "header", name = "Logging" },
        { type = "checkbox", name = "Fight stats for every player (combat ledger)",
          tooltip = "Reads every combat event the client sends during a battleground: full stats for your group, and what enemies did to and took from your team.",
          getFunc = function() return sv.trackCombat end, setFunc = function(v) sv.trackCombat = v end },
        { type = "checkbox", name = "Print match summary to chat",
          getFunc = function() return sv.chatSummary end, setFunc = function(v) sv.chatSummary = v end },
        { type = "slider", name = "Matches kept in history", min = 5, max = 200, step = 5,
          getFunc = function() return sv.maxHistory end, setFunc = function(v) sv.maxHistory = v end },
        { type = "button", name = "Clear history", isDangerous = true, warning = "Deletes all saved matches.",
          func = function() SBR.MatchLog:ClearHistory() end },
        { type = "checkbox", name = "Debug output",
          getFunc = function() return sv.debug end, setFunc = function(v) sv.debug = v end },
    })
end
