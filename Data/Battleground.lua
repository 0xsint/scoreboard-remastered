-- Reads everything the native battleground scoreboard exposes.
local SBR = ScoreboardRemastered
local BG = {}
SBR.Battleground = BG

-- Preferred column order and short labels. Any other SCORE_TRACKER_TYPE_* constant
-- the client defines is discovered at load time and appended, so new score types
-- added by ZOS show up without an addon update.
local PRIORITY = {
    { "SCORE", "Score" },
    { "KILL", "Kills" },
    { "DEATH", "Deaths" },
    { "ASSISTS", "Assists" },
    { "KILL_STREAK", "Streak" },
    { "DAMAGE_DONE", "Damage" },
    { "HEALING_DONE", "Healing" },
    { "DAMAGE_TAKEN", "Dmg Taken" },
    { "FLAG_CAPTURED", "Flags" },
    { "FLAG_RETURNED", "Returns" },
    { "RELIC_CAPTURED", "Relics" },
    { "CAPTURE_POINT", "Captures" },
}

local IGNORED_SUFFIX = { "ITERATION", "MIN_VALUE", "MAX_VALUE", "INVALID", "NONE" }

local FALLBACK_TEAM_COLORS = { "F0723C", "6BC26B", "A77BE0" } -- drakes, daemons, storm lords

function BG:DiscoverScoreTypes()
    local list, seenKey, seenId = {}, {}, {}

    local function add(suffix, label)
        if seenKey[suffix] then return end
        local id = _G["SCORE_TRACKER_TYPE_" .. suffix]
        if type(id) ~= "number" or seenId[id] then return end
        seenKey[suffix], seenId[id] = true, true
        list[#list + 1] = { key = suffix, id = id, label = label or SBR.Prettify(suffix) }
    end

    for _, entry in ipairs(PRIORITY) do add(entry[1], entry[2]) end

    local extra = {}
    SBR.ForEachGlobal(function(k, v)
        if type(v) == "number" then
            local suffix = k:match("^SCORE_TRACKER_TYPE_(.+)$")
            if suffix then
                for _, bad in ipairs(IGNORED_SUFFIX) do
                    if suffix:find(bad, 1, true) then return end
                end
                extra[#extra + 1] = suffix
            end
        end
    end)
    table.sort(extra)
    for _, suffix in ipairs(extra) do add(suffix) end

    self.scoreTypes = list
    return list
end

function BG:IsInBattleground()
    if SBR.HasAPI("IsActiveWorldBattleground") then
        return SBR.API("IsActiveWorldBattleground") == true
    end
    local id = SBR.API("GetCurrentBattlegroundId")
    return type(id) == "number" and id ~= 0
end

function BG:GetTeamRange()
    local first = SBR.Const("BATTLEGROUND_TEAM_ITERATION_BEGIN", "BATTLEGROUND_ALLIANCE_ITERATION_BEGIN")
    local last = SBR.Const("BATTLEGROUND_TEAM_ITERATION_END", "BATTLEGROUND_ALLIANCE_ITERATION_END")
    return first or 1, last or 3
end

function BG:GetTeamName(team)
    local name = SBR.API("GetBattlegroundTeamName", team)
    if type(name) == "string" and name ~= "" then return SBR.CleanName(name) end
    for _, prefix in ipairs({ "SI_BATTLEGROUNDTEAM", "SI_BATTLEGROUNDALLIANCE" }) do
        local ok, s = pcall(GetString, prefix, team)
        if ok and s and s ~= "" then return s end
    end
    return "Team " .. tostring(team)
end

function BG:GetTeamColorHex(team)
    for _, fnName in ipairs({ "GetBattlegroundTeamColor", "GetBattlegroundAllianceColor" }) do
        local color = SBR.API(fnName, team)
        if type(color) == "table" and color.ToHex then
            local hex = SBR.SafeCall(color.ToHex, color)
            if hex then return hex end
        end
    end
    return FALLBACK_TEAM_COLORS[team] or "FFFFFF"
end

function BG:GetLocalTeam()
    return SBR.API("GetUnitBattlegroundTeam", "player") or SBR.API("GetUnitBattlegroundAlliance", "player")
end

function BG:GetRoundIndex()
    return SBR.API("GetCurrentBattlegroundRoundIndex")
end

function BG:GetStateName(state)
    if state == nil then return "Unknown" end
    local names = {
        BATTLEGROUND_STATE_NONE = "None",
        BATTLEGROUND_STATE_PREROUND = "Round starting",
        BATTLEGROUND_STATE_STARTING = "Starting",
        BATTLEGROUND_STATE_RUNNING = "Running",
        BATTLEGROUND_STATE_POSTROUND = "Round over",
        BATTLEGROUND_STATE_FINISHED = "Finished",
    }
    for constName, label in pairs(names) do
        if _G[constName] == state then return label end
    end
    return tostring(state)
end

function BG:IsPostGame(state)
    return state ~= nil and (state == _G.BATTLEGROUND_STATE_POSTGAME or state == _G.BATTLEGROUND_STATE_FINISHED)
end

function BG:IsRunning(state)
    return state ~= nil and state == _G.BATTLEGROUND_STATE_RUNNING
end

-- Match-level info: id, name, game type, state, teams and team scores.
function BG:ReadMatchInfo()
    local info = {}
    info.battlegroundId = SBR.API("GetCurrentBattlegroundId")
    if info.battlegroundId then
        info.name = SBR.API("GetBattlegroundName", info.battlegroundId)
        info.gameType = SBR.API("GetCurrentBattlegroundGameType", self:GetRoundIndex())
            or SBR.API("GetBattlegroundGameType", info.battlegroundId, self:GetRoundIndex())
        if info.gameType then
            local ok, s = pcall(GetString, "SI_BATTLEGROUNDGAMETYPE", info.gameType)
            info.gameTypeName = ok and s ~= "" and s or nil
        end
        info.teamSize = SBR.API("GetBattlegroundTeamSize", info.battlegroundId)
        info.numTeams = SBR.API("GetBattlegroundNumTeams", info.battlegroundId)
        info.numRounds = SBR.API("GetBattlegroundNumRounds", info.battlegroundId)
    end
    info.zoneName = SBR.API("GetUnitZone", "player")
    info.state = SBR.API("GetCurrentBattlegroundState")
    info.stateName = self:GetStateName(info.state)
    info.roundIndex = self:GetRoundIndex()
    info.localTeam = self:GetLocalTeam()
    info.shutdownTimer = SBR.API("GetCurrentBattlegroundShutdownTimer")

    -- GetCurrentBattlegroundScore(roundIndex, team): the score of the current round,
    -- the same call the native scoreboard makes. Multi-round modes also record rounds won.
    info.teams = {}
    local first, last = self:GetTeamRange()
    local round = info.roundIndex or 1
    for team = first, last do
        info.teams[team] = {
            id = team,
            name = self:GetTeamName(team),
            color = self:GetTeamColorHex(team),
            score = SBR.API("GetCurrentBattlegroundScore", round, team),
            roundsWon = (info.numRounds or 1) > 1 and SBR.API("GetCurrentBattlegroundRoundsWonByTeam", team) or nil,
        }
    end
    return info
end

-- Mirrors ZO_BattlegroundMedalInfo (battlegroundmedalinfo_shared.lua): a nil round
-- index means the whole match, read through the cumulative medal API; a round
-- index reads that round. Both walk medal ids with a "next id" iterator.
local function MedalIterator(entryIndex, roundIndex)
    if roundIndex == nil and SBR.HasAPI("GenerateCumulativeMedalInfoForScoreboardEntry") then
        SBR.API("GenerateCumulativeMedalInfoForScoreboardEntry", entryIndex, BG:GetRoundIndex())
        return function(last) return SBR.API("GetNextBattlegroundCumulativeMedalId", last) end,
               function(id) return SBR.API("GetBattlegroundCumulativeNumEarnedMedalsById", id) end
    end
    return function(last) return SBR.API("GetNextScoreboardEntryMedalId", entryIndex, roundIndex, last) end,
           function(id) return SBR.API("GetScoreboardEntryNumEarnedMedalsById", entryIndex, id, roundIndex) end
end

local function ReadMedals(entryIndex, roundIndex)
    local medals = {}
    local nextId, countOf = MedalIterator(entryIndex, roundIndex)
    local medalId = nextId(nil)
    local guard = 0
    while medalId and guard < 64 do
        guard = guard + 1
        local medalCount = countOf(medalId)
        do
            local name, icon, condition, scoreReward = SBR.API("GetMedalInfo", medalId)
            medals[#medals + 1] = {
                id = medalId,
                count = medalCount or 1,
                name = name and SBR.CleanName(name) or ("Medal " .. medalId),
                icon = icon,
                condition = condition,
                scoreReward = scoreReward,
            }
        end
        medalId = nextId(medalId)
    end
    table.sort(medals, function(a, b) return (a.count or 0) > (b.count or 0) end)
    return medals
end

-- Every row the native scoreboard shows, with every score type it tracks.
function BG:ReadEntries(roundIndex)
    local types = self.scoreTypes or self:DiscoverScoreTypes()
    local entries = {}
    local n = SBR.API("GetNumScoreboardEntries", roundIndex) or 0
    for i = 1, n do
        local characterName, displayName, team, isLocal = SBR.API("GetScoreboardEntryInfo", i, roundIndex)
        if characterName or displayName then
            local e = {
                characterName = SBR.CleanName(characterName),
                displayName = displayName or "",
                team = team,
                isLocal = isLocal == true,
                scores = {},
            }
            e.classId = SBR.API("GetScoreboardEntryClassId", i, roundIndex)
            if e.classId then
                local className = SBR.API("GetClassName", GENDER_MALE or 1, e.classId)
                e.className = className and SBR.CleanName(className) or nil
                -- ZO_GetClassIcon is the real function; GetClassIcon is only a PC compatibility alias
                e.classIcon = SBR.API("ZO_GetClassIcon", e.classId) or SBR.API("GetClassIcon", e.classId)
            end
            for _, st in ipairs(types) do
                local v = SBR.API("GetScoreboardEntryScoreByType", i, st.id, roundIndex)
                if type(v) == "number" then e.scores[st.key] = v end
            end
            e.medals = ReadMedals(i, roundIndex)
            local medalTotal = 0
            for _, m in ipairs(e.medals) do medalTotal = medalTotal + (m.count or 1) end
            e.medalCount = medalTotal
            entries[#entries + 1] = e
        end
    end
    return entries
end

function BG:EntryKey(e)
    if e.displayName and e.displayName ~= "" then return e.displayName end
    return e.characterName
end
