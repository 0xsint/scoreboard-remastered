-- Match database: a compact, long-lived index of every match you've played.
--
-- Full matches (every player, kill feed, recaps) are heavy, so only the last
-- `maxHistory` are kept in sv.history. Each finished match also writes one small
-- summary record to sv.db.records, which is kept far longer (`maxRecords`). The
-- history browser, lifetime stats, and per-map and per-class records all read
-- from these records. A record points back at its full match by id while that
-- match is still stored.
local SBR = ScoreboardRemastered
local DB = {}
SBR.MatchDB = DB

DB.FILTERS = { "all", "won", "lost", "map", "class" }
DB.FILTER_LABELS = { all = "All matches", won = "Victories", lost = "Defeats", map = "This map", class = "This class" }
DB.SORTS = { "newest", "score", "kills", "kda", "damage", "healing", "medals" }
DB.SORT_LABELS = {
    newest = "Newest", score = "Score", kills = "Kills", kda = "K/D/A", damage = "Damage", healing = "Healing", medals = "Medals",
}

local function Num(v) return type(v) == "number" and v or 0 end

function DB:Init(sv)
    sv.db = sv.db or { version = 1, records = {} }
    self.sv = sv
    self.records = sv.db.records
    -- matches saved before the database existed
    if #self.records == 0 then
        for _, m in ipairs(sv.history or {}) do
            if m.endedAt then self:Add(m) end
        end
    end
end

-- Where your row ranks in a match, by score.
local function Rank(match, me, sameTeamOnly)
    local list = {}
    for _, p in pairs(match.players or {}) do
        if not sameTeamOnly or p.team == me.team then list[#list + 1] = Num(p.scores and p.scores.SCORE) end
    end
    table.sort(list, function(a, b) return a > b end)
    local mine = Num(me.scores and me.scores.SCORE)
    for i, v in ipairs(list) do if v == mine then return i, #list end end
    return nil, #list
end

function DB:Summarize(match)
    local me
    for _, p in pairs(match.players or {}) do if p.isLocal then me = p break end end
    local s = me and me.scores or {}
    local f = me and me.fight or {}
    local rec = {
        id = match.id,
        at = match.startedAt,
        map = match.name or match.zoneName or "Battleground",
        gameType = match.gameTypeName,
        teamSize = match.teamSize,
        result = match.result or "unknown",
        duration = match.duration,
        character = match.character,
        account = match.account,
        localTeam = match.localTeam,
        teams = {},
        kills = s.KILL, deaths = s.DEATH, assists = s.ASSISTS, score = s.SCORE,
        damage = s.DAMAGE_DONE or f.damageDone, healing = s.HEALING_DONE or f.healingDone,
        flags = s.FLAG_CAPTURED,
        medalCount = me and me.medalCount or 0,
        medals = {},
        classId = me and me.classId, className = me and me.className, classIcon = me and me.classIcon,
        dps = f.dps, hps = f.hps, maxHit = f.maxHit, maxHitAbility = f.maxHitAbility,
        critRate = f.critRate, damageTaken = f.damageTaken, killingBlows = f.killingBlows,
        fights = match.lf and match.lf.fightList and #match.lf.fightList or nil,
        recaps = match.lf and match.lf.deaths and #match.lf.deaths or nil,
        top = {},
    }
    for id, t in pairs(match.teams or {}) do
        rec.teams[#rec.teams + 1] = { id = id, name = t.name, color = t.color, score = t.score }
    end
    table.sort(rec.teams, function(a, b) return a.id < b.id end)
    for _, m in ipairs(me and me.medals or {}) do
        rec.medals[#rec.medals + 1] = { name = m.name, icon = m.icon, count = m.count }
    end
    table.sort(rec.medals, function(a, b) return (a.count or 0) > (b.count or 0) end)
    for i, a in ipairs(f.topAbilities or {}) do
        if i > 3 then break end
        rec.top[#rec.top + 1] = { name = a.name, icon = a.icon, damage = a.damage }
    end
    if me then
        rec.teamRank, rec.teamSizeRanked = Rank(match, me, true)
        rec.rank, rec.players = Rank(match, me, false)
    end
    -- match MVP: top score across both teams
    local best
    for _, p in pairs(match.players or {}) do
        if not best or Num(p.scores and p.scores.SCORE) > Num(best.scores and best.scores.SCORE) then best = p end
    end
    if best then rec.mvp = { name = best.characterName, team = best.team, isYou = best.isLocal or nil } end
    return rec
end

function DB:Add(match)
    local rec = self:Summarize(match)
    for i, r in ipairs(self.records) do
        if r.id == rec.id then
            self.records[i] = rec
            return rec
        end
    end
    table.insert(self.records, rec)
    local max = SBR.sv.maxRecords or 500
    while #self.records > max do table.remove(self.records, 1) end
    return rec
end

function DB:GetRecords() return self.records end

function DB:FindMatch(id)
    for i, m in ipairs(self.sv.history or {}) do
        if m.id == id then return m, i end
    end
    return nil
end

local function KDA(r) return (Num(r.kills) + Num(r.assists) * 0.5) / math.max(1, Num(r.deaths)) end
DB.KDA = KDA

local SORT_VALUE = {
    newest = function(r) return Num(r.at) end,
    score = function(r) return Num(r.score) end,
    kills = function(r) return Num(r.kills) end,
    kda = KDA,
    damage = function(r) return Num(r.damage) end,
    healing = function(r) return Num(r.healing) end,
    medals = function(r) return Num(r.medalCount) end,
}

-- filter: one of DB.FILTERS. `ref` is the record whose map / class "This map" and
-- "This class" compare against.
function DB:Query(filter, sort, ref)
    local out = {}
    for _, r in ipairs(self.records) do
        local keep = true
        if filter == "won" then keep = r.result == "won"
        elseif filter == "lost" then keep = r.result == "lost"
        elseif filter == "map" then keep = ref ~= nil and r.map == ref.map
        elseif filter == "class" then keep = ref ~= nil and r.classId == ref.classId end
        if keep then out[#out + 1] = r end
    end
    local value = SORT_VALUE[sort] or SORT_VALUE.newest
    table.sort(out, function(a, b)
        local va, vb = value(a), value(b)
        if va ~= vb then return va > vb end
        return Num(a.at) > Num(b.at)
    end)
    return out
end

-- Lifetime numbers over a list of records.
function DB:Aggregate(list)
    local a = { matches = #list, won = 0, lost = 0, kills = 0, deaths = 0, assists = 0, damage = 0, healing = 0,
                medals = 0, seconds = 0, maps = {}, classes = {}, mvps = 0 }
    for _, r in ipairs(list) do
        if r.result == "won" then a.won = a.won + 1 elseif r.result == "lost" then a.lost = a.lost + 1 end
        a.kills = a.kills + Num(r.kills)
        a.deaths = a.deaths + Num(r.deaths)
        a.assists = a.assists + Num(r.assists)
        a.damage = a.damage + Num(r.damage)
        a.healing = a.healing + Num(r.healing)
        a.medals = a.medals + Num(r.medalCount)
        a.seconds = a.seconds + Num(r.duration)
        if r.mvp and r.mvp.isYou then a.mvps = a.mvps + 1 end
        local m = a.maps[r.map] or { map = r.map, played = 0, won = 0 }
        m.played, m.won = m.played + 1, m.won + (r.result == "won" and 1 or 0)
        a.maps[r.map] = m
        if r.className then
            local c = a.classes[r.className] or { className = r.className, icon = r.classIcon, played = 0, won = 0 }
            c.played, c.won = c.played + 1, c.won + (r.result == "won" and 1 or 0)
            a.classes[r.className] = c
        end
        if not a.bestDamage or Num(r.damage) > Num(a.bestDamage.damage) then a.bestDamage = r end
        if not a.bestKills or Num(r.kills) > Num(a.bestKills.kills) then a.bestKills = r end
        if not a.bestHealing or Num(r.healing) > Num(a.bestHealing.healing) then a.bestHealing = r end
    end
    local decided = a.won + a.lost
    a.winRate = decided > 0 and a.won / decided * 100 or nil
    a.kd = a.kills / math.max(1, a.deaths)
    local fav
    for _, m in pairs(a.maps) do if not fav or m.played > fav.played then fav = m end end
    a.favoriteMap = fav
    -- current streak from the newest match back
    local newest = self:Query("all", "newest")
    local streak, kind = 0, nil
    for _, r in ipairs(newest) do
        if r.result ~= "won" and r.result ~= "lost" then break end
        if kind == nil then kind = r.result end
        if r.result ~= kind then break end
        streak = streak + 1
    end
    a.streak, a.streakKind = streak, kind
    return a
end
