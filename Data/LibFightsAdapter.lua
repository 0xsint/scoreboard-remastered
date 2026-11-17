-- LibFights integration.
--
-- Two ways to feed fight data into the scoreboard:
--
-- 1) Push (recommended): from LibFights (or any addon) call
--        ScoreboardRemastered.RegisterFightProvider(provider)
--    where provider implements
--        provider:GetPlayerStats(characterName, displayName, isLocal) -> table|nil
--    and optionally
--        provider:OnMatchStart(matchInfo)        -- reset per-match state
--        provider:OnMatchEnd(match)              -- final snapshot taken
--        provider:GetMatchSummary() -> table     -- stored with the match log
--    The returned stats table uses the canonical keys listed in FIELDS below.
--
-- 2) Auto-detect: if a global `LibFights` (or LibStub "LibFights-1.0") exists,
--    this adapter calls the first method it finds from METHOD_CANDIDATES and maps
--    the result through FIELDS aliases. If your lib's names differ, add them to
--    the two tables below. That's the only place you should need to touch.
local SBR = ScoreboardRemastered
local Adapter = { providers = {} }
SBR.Fights = Adapter

-- Canonical key -> accepted field names in the provider's result table.
local FIELDS = {
    damageDone    = { "damageDone", "damage", "dmg", "totalDamage", "DamageDone", "damageOut" },
    damageTaken   = { "damageTaken", "damageIn", "dmgTaken", "DamageTaken", "incomingDamage" },
    healingDone   = { "healingDone", "healing", "heal", "totalHealing", "HealingDone", "healOut" },
    healingTaken  = { "healingTaken", "healIn", "HealingTaken", "incomingHealing" },
    dps           = { "dps", "DPS", "damagePerSecond" },
    hps           = { "hps", "HPS", "healingPerSecond" },
    killingBlows  = { "killingBlows", "kbs", "kb", "KillingBlows" },
    deaths        = { "deaths", "Deaths" },
    interrupts    = { "interrupts", "Interrupts" },
    ccApplied     = { "ccApplied", "cc", "crowdControl", "CC" },
    ccTaken       = { "ccTaken", "ccIn" },
    damageShielded= { "damageShielded", "shielded", "absorbed" },
    damageBlocked = { "damageBlocked", "blocked" },
    critRate      = { "critRate", "crit", "critChance", "critPercent" },
    activeTime    = { "activeTime", "combatTime", "fightTime", "duration" },
    fights        = { "fights", "numFights", "fightCount" },
}
Adapter.FIELDS = FIELDS

-- Methods tried in order on the auto-detected library. Signature assumed:
-- lib:Method(characterName, displayName, isLocal)
local METHOD_CANDIDATES = { "GetPlayerStats", "GetStatsForPlayer", "GetUnitStats", "GetPlayerFightData", "GetStats" }
local SUMMARY_CANDIDATES = { "GetMatchSummary", "GetFightSummary", "GetCurrentFight", "GetSummary" }
local RESET_CANDIDATES = { "Reset", "ResetFights", "ClearFights" }

local function Normalize(raw)
    if type(raw) ~= "table" then return nil end
    local out, any = {}, false
    for canonical, aliases in pairs(FIELDS) do
        for _, alias in ipairs(aliases) do
            local v = raw[alias]
            if type(v) == "number" then
                out[canonical] = v
                any = true
                break
            end
        end
    end
    if not out.dps and out.damageDone and out.activeTime and out.activeTime > 0 then
        out.dps = out.damageDone / out.activeTime
    end
    if not out.hps and out.healingDone and out.activeTime and out.activeTime > 0 then
        out.hps = out.healingDone / out.activeTime
    end
    return any and out or nil
end
Adapter.Normalize = Normalize

local function FindMethod(lib, candidates)
    for _, name in ipairs(candidates) do
        if type(lib[name]) == "function" then return name end
    end
end

local function WrapLibrary(lib)
    local statsMethod = FindMethod(lib, METHOD_CANDIDATES)
    if not statsMethod then
        SBR.Debug("LibFights found but no stats method (%s)", table.concat(METHOD_CANDIDATES, ", "))
        return nil
    end
    local summaryMethod = FindMethod(lib, SUMMARY_CANDIDATES)
    local resetMethod = FindMethod(lib, RESET_CANDIDATES)
    return {
        name = "LibFights",
        lib = lib,
        method = statsMethod,
        GetPlayerStats = function(_, characterName, displayName, isLocal)
            return SBR.SafeCall(lib[statsMethod], lib, characterName, displayName, isLocal)
        end,
        GetMatchSummary = summaryMethod and function()
            return SBR.SafeCall(lib[summaryMethod], lib)
        end or nil,
        OnMatchStart = resetMethod and function()
            SBR.SafeCall(lib[resetMethod], lib)
        end or nil,
    }
end

function Adapter:DetectLibFights()
    if self.autoDetected then return self.autoDetected end
    local lib = _G.LibFights
    if not lib and LibStub then
        lib = SBR.SafeCall(LibStub.GetLibrary, LibStub, "LibFights-1.0", true)
    end
    if type(lib) ~= "table" then return nil end
    local provider = WrapLibrary(lib)
    if provider then
        self.autoDetected = provider
        self:Register(provider)
        SBR.Debug("LibFights auto-detected (method %s)", provider.method)
    end
    return provider
end

function Adapter:Register(provider)
    if type(provider) ~= "table" or type(provider.GetPlayerStats) ~= "function" then
        SBR.Print("RegisterFightProvider: provider needs a GetPlayerStats method")
        return false
    end
    for _, p in ipairs(self.providers) do
        if p == provider then return true end
    end
    provider.name = provider.name or ("Provider " .. (#self.providers + 1))
    table.insert(self.providers, provider)
    return true
end

function Adapter:HasExternal()
    return #self.providers > 0
end

-- Merged stats for one player: external providers first, built-in tracker fills gaps.
function Adapter:GetPlayerStats(characterName, displayName, isLocal)
    local merged, sources = nil, {}
    for _, p in ipairs(self.providers) do
        local stats = Normalize(SBR.SafeCall(p.GetPlayerStats, p, characterName, displayName, isLocal))
        if stats then
            merged = merged or {}
            for k, v in pairs(stats) do
                if merged[k] == nil then merged[k] = v end
            end
            sources[#sources + 1] = p.name
        end
    end
    if SBR.sv.trackCombat then
        local own = SBR.FightTracker:GetPlayerStats(characterName, displayName, isLocal)
        if own then
            merged = merged or {}
            local used = false
            for k, v in pairs(own) do
                if merged[k] == nil then
                    merged[k] = v
                    used = true
                end
            end
            if used then sources[#sources + 1] = SBR.FightTracker.name end
        end
    end
    if merged then merged.source = table.concat(sources, " + ") end
    return merged
end

function Adapter:Broadcast(methodName, ...)
    for _, p in ipairs(self.providers) do
        if type(p[methodName]) == "function" then SBR.SafeCall(p[methodName], p, ...) end
    end
end

function Adapter:GetMatchSummaries()
    local out
    for _, p in ipairs(self.providers) do
        if type(p.GetMatchSummary) == "function" then
            local s = SBR.SafeCall(p.GetMatchSummary, p)
            if type(s) == "table" then
                out = out or {}
                out[p.name] = s
            end
        end
    end
    return out
end

-- Public API
function SBR.RegisterFightProvider(provider)
    return Adapter:Register(provider)
end
