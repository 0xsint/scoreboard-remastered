-- Built-in fight tracker: reads EVENT_COMBAT_EVENT while in a battleground.
-- The client only reports combat events the local player (or their pet) is part
-- of, so this gives full stats for you and "you vs them" stats for everyone you
-- fought. LibFights data, when present, takes priority over this.
local SBR = ScoreboardRemastered
local FT = { name = "Built-in", active = false }
SBR.FightTracker = FT

local DAMAGE = SBR.ConstSet({
    "ACTION_RESULT_DAMAGE", "ACTION_RESULT_CRITICAL_DAMAGE", "ACTION_RESULT_DOT_TICK",
    "ACTION_RESULT_DOT_TICK_CRITICAL", "ACTION_RESULT_BLOCKED_DAMAGE", "ACTION_RESULT_PRECISE_DAMAGE",
    "ACTION_RESULT_WRECKING_DAMAGE", "ACTION_RESULT_FALL_DAMAGE",
})
local HEAL = SBR.ConstSet({
    "ACTION_RESULT_HEAL", "ACTION_RESULT_CRITICAL_HEAL", "ACTION_RESULT_HOT_TICK", "ACTION_RESULT_HOT_TICK_CRITICAL",
})
local CRIT = SBR.ConstSet({
    "ACTION_RESULT_CRITICAL_DAMAGE", "ACTION_RESULT_DOT_TICK_CRITICAL", "ACTION_RESULT_CRITICAL_HEAL",
    "ACTION_RESULT_HOT_TICK_CRITICAL",
})
local CC = SBR.ConstSet({
    "ACTION_RESULT_STUNNED", "ACTION_RESULT_KNOCKBACK", "ACTION_RESULT_FEARED", "ACTION_RESULT_ROOTED",
    "ACTION_RESULT_LEVITATED", "ACTION_RESULT_DISORIENTED", "ACTION_RESULT_SILENCED", "ACTION_RESULT_OFFBALANCE",
})
local DIED = SBR.ConstSet({ "ACTION_RESULT_DIED", "ACTION_RESULT_DIED_XP" })
local R_KB = _G.ACTION_RESULT_KILLING_BLOW
local R_INTERRUPT = _G.ACTION_RESULT_INTERRUPT
local R_SHIELDED = _G.ACTION_RESULT_DAMAGE_SHIELDED
local R_BLOCKED = _G.ACTION_RESULT_BLOCKED_DAMAGE

local function NewStats()
    return {
        damageDone = 0, damageTaken = 0, healingDone = 0, healingTaken = 0,
        damageShielded = 0, damageBlocked = 0,
        hits = 0, crits = 0, killingBlows = 0, deaths = 0,
        interrupts = 0, interrupted = 0, ccApplied = 0, ccTaken = 0,
        topAbilities = {},
    }
end

local function NewVs()
    return { damageToYou = 0, damageFromYou = 0, healedByYou = 0, healedYou = 0, killedYou = 0, killedByYou = 0 }
end

function FT:Reset()
    self.me = NewStats()
    self.vs = {}
    self.unitNames = {}
    self.inCombatSince = nil
    self.combatMs = 0
    self.startedMs = GetGameTimeMilliseconds()
end

function FT:Vs(name)
    if name == "" then return nil end
    local v = self.vs[name]
    if not v then
        v = NewVs()
        self.vs[name] = v
    end
    return v
end

function FT:ResolveName(name, unitId)
    name = SBR.CleanName(name)
    if name ~= "" then
        if unitId and unitId ~= 0 then self.unitNames[unitId] = name end
        return name
    end
    return unitId and self.unitNames[unitId] or ""
end

local function IsMe(unitType)
    return unitType == COMBAT_UNIT_TYPE_PLAYER or unitType == COMBAT_UNIT_TYPE_PLAYER_PET
end

function FT:OnCombatEvent(result, isError, abilityName, sourceName, sourceType, targetName, targetType, hitValue, sourceUnitId, targetUnitId, abilityId)
    if isError or not self.me then return end
    local srcMe = IsMe(sourceType)
    local tgtMe = targetType == COMBAT_UNIT_TYPE_PLAYER
    if not srcMe and not tgtMe then return end

    local me = self.me
    local src = self:ResolveName(sourceName, sourceUnitId)
    local tgt = self:ResolveName(targetName, targetUnitId)
    hitValue = hitValue or 0

    if DAMAGE[result] and hitValue > 0 then
        if srcMe and not tgtMe then
            me.damageDone = me.damageDone + hitValue
            me.hits = me.hits + 1
            if CRIT[result] then me.crits = me.crits + 1 end
            local v = self:Vs(tgt)
            if v then v.damageFromYou = v.damageFromYou + hitValue end
            local an = SBR.CleanName(abilityName)
            if an ~= "" then me.topAbilities[an] = (me.topAbilities[an] or 0) + hitValue end
        elseif tgtMe and not srcMe then
            me.damageTaken = me.damageTaken + hitValue
            local v = self:Vs(src)
            if v then v.damageToYou = v.damageToYou + hitValue end
        end
        if tgtMe and result == R_BLOCKED then me.damageBlocked = me.damageBlocked + hitValue end
    elseif HEAL[result] and hitValue > 0 then
        if srcMe then
            me.healingDone = me.healingDone + hitValue
            if not tgtMe then
                local v = self:Vs(tgt)
                if v then v.healedByYou = v.healedByYou + hitValue end
            end
        end
        if tgtMe then
            me.healingTaken = me.healingTaken + hitValue
            if not srcMe then
                local v = self:Vs(src)
                if v then v.healedYou = v.healedYou + hitValue end
            end
        end
    elseif result == R_SHIELDED and tgtMe then
        me.damageShielded = me.damageShielded + hitValue
    elseif result == R_KB then
        if srcMe and not tgtMe then
            me.killingBlows = me.killingBlows + 1
            local v = self:Vs(tgt)
            if v then v.killedByYou = v.killedByYou + 1 end
        elseif tgtMe and not srcMe then
            local v = self:Vs(src)
            if v then v.killedYou = v.killedYou + 1 end
        end
    elseif DIED[result] and tgtMe then
        me.deaths = me.deaths + 1
    elseif result == R_INTERRUPT then
        if srcMe and not tgtMe then me.interrupts = me.interrupts + 1 end
        if tgtMe and not srcMe then me.interrupted = me.interrupted + 1 end
    elseif CC[result] then
        if srcMe and not tgtMe then me.ccApplied = me.ccApplied + 1 end
        if tgtMe and not srcMe then me.ccTaken = me.ccTaken + 1 end
    end
end

function FT:OnCombatState(inCombat)
    local now = GetGameTimeMilliseconds()
    if inCombat then
        self.inCombatSince = self.inCombatSince or now
    elseif self.inCombatSince then
        self.combatMs = self.combatMs + (now - self.inCombatSince)
        self.inCombatSince = nil
    end
end

function FT:GetCombatSeconds()
    local ms = self.combatMs or 0
    if self.inCombatSince then ms = ms + (GetGameTimeMilliseconds() - self.inCombatSince) end
    return ms / 1000
end

local function TopAbilities(map, n)
    local list = {}
    for name, dmg in pairs(map) do list[#list + 1] = { name = name, damage = dmg } end
    table.sort(list, function(a, b) return a.damage > b.damage end)
    for i = #list, n + 1, -1 do list[i] = nil end
    return list
end

-- Provider interface (same shape LibFights data is normalized to).
function FT:GetPlayerStats(characterName, displayName, isLocal)
    if not self.me then return nil end
    if isLocal then
        local me = self.me
        local secs = self:GetCombatSeconds()
        local s = SBR.ShallowCopy(me)
        s.topAbilities = TopAbilities(me.topAbilities, 5)
        s.activeTime = secs
        s.dps = secs > 0 and me.damageDone / secs or 0
        s.hps = secs > 0 and me.healingDone / secs or 0
        s.critRate = me.hits > 0 and (me.crits / me.hits) * 100 or nil
        return s
    end
    return nil
end

function FT:GetVsStats(characterName)
    if not self.vs then return nil end
    local v = self.vs[characterName]
    return v and SBR.ShallowCopy(v) or nil
end

function FT:Start()
    if self.active then return end
    self:Reset()
    if not SBR.sv.trackCombat then return end
    self.active = true
    local ns = SBR.name .. "_Combat"
    EVENT_MANAGER:RegisterForEvent(ns, EVENT_COMBAT_EVENT,
        function(_, result, isError, abilityName, _, _, sourceName, sourceType, targetName, targetType, hitValue, _, _, _, sourceUnitId, targetUnitId, abilityId)
            FT:OnCombatEvent(result, isError, abilityName, sourceName, sourceType, targetName, targetType, hitValue, sourceUnitId, targetUnitId, abilityId)
        end)
    EVENT_MANAGER:AddFilterForEvent(ns, EVENT_COMBAT_EVENT, REGISTER_FILTER_IS_ERROR, false)
    EVENT_MANAGER:RegisterForEvent(ns, EVENT_PLAYER_COMBAT_STATE, function(_, inCombat) FT:OnCombatState(inCombat) end)
    if SBR.API("IsUnitInCombat", "player") then self:OnCombatState(true) end
end

function FT:Stop()
    if not self.active then return end
    if self.me then self:OnCombatState(false) end
    self.active = false
    local ns = SBR.name .. "_Combat"
    EVENT_MANAGER:UnregisterForEvent(ns, EVENT_COMBAT_EVENT)
    EVENT_MANAGER:UnregisterForEvent(ns, EVENT_PLAYER_COMBAT_STATE)
end
