-- Saved-variables tests: packing, recap encoding, and converting an older save.
-- Run from the repository root: lua5.1 tools/test-savedvars.lua
ScoreboardRemastered = { name = "SBR", Debug = function() end }
local SBR = ScoreboardRemastered
local updates = {}
EVENT_MANAGER = {
    RegisterForUpdate = function(_, ns, ms, f) updates[ns] = f end,
    UnregisterForUpdate = function(_, ns) updates[ns] = nil end,
}
function GetTimeStamp() return 0 end
function ZO_ClearNumericallyIndexedTable(t) for i = #t, 1, -1 do t[i] = nil end end
dofile("Util.lua")
dofile("Data/MatchLog.lua")
dofile("Data/MatchDB.lua")
local ML, DB = SBR.MatchLog, SBR.MatchDB

local function check(ok, what) if not ok then error("FAILED: " .. what, 2) end end
local function eq(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not eq(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
local function plainCopy(v, path)
    if type(v) ~= "table" then return v end
    check(getmetatable(v) == nil, "saved variables hold no metatables (" .. path .. ")")
    local out = {}
    for k, x in pairs(v) do out[k] = plainCopy(x, path .. "." .. tostring(k)) end
    return out
end
local function countTables(v)
    if type(v) ~= "table" then return 0 end
    local n = 1
    for _, x in pairs(v) do n = n + countTables(x) end
    return n
end

-- 1. packing
local big = { id = "1795-42", unicode = "Hrólf Snöwmane ★", colon = "a:b;c T E", yes = true, no = false, neg = -7,
    [3] = "three", players = {}, killFeed = {} }
for i = 1, 200 do big.players["@p" .. i] = { characterName = "Ñame " .. i, scores = { SCORE = i * 13 }, medals = { { id = i, count = 2 } } } end
for i = 1, 300 do big.killFeed[i] = { t = i / 10, killer = "K" .. i, recap = { "123\31\31Fatecarver\31Nhalia" } } end
local packed = SBR.Pack(big)
check(type(packed) == "table" and #packed > 10, "long data is split into pieces")
for _, piece in ipairs(packed) do check(#piece <= 1900, "pieces fit a saved string") end
check(eq(SBR.Unpack(packed), big), "pack / unpack round trip")
check(SBR.Unpack("Tgarbage") == nil, "bad data unpacks to nil")
local lazy = SBR.LazyUnpack(SBR.Pack({ id = "x", endedAt = 5, players = { a = 1 } }), { id = "x" })
check(lazy.id == "x" and SBR.IsLazy(lazy), "known fields read without unpacking")
check(lazy.endedAt == 5 and not SBR.IsLazy(lazy) and lazy.players.a == 1, "unpacks on first read")
local w = SBR.LazyUnpack(SBR.Pack({ isYou = false, name = "old" }))
w.isYou = true
check(w.isYou == true and w.name == "old", "a write before any read is kept")
print("packing ok")

-- 2. recaps
local enc = ML.EncodeRecap({ { hit = 1627.4, crit = true, ability = "Fatecarver", source = "Nhalia" }, { hit = 5, ability = "", source = "?" } })
local dec = ML.DecodeRecap({ recap = enc })
check(dec[1].hit == 1627 and dec[1].crit and dec[1].ability == "Fatecarver" and dec[1].source == "Nhalia", "recap 1")
check(dec[2].hit == 5 and not dec[2].crit and dec[2].ability == "" and dec[2].source == "?", "recap 2")
check(ML.DecodeRecap({ recap = { { hit = 9, ability = "A", source = "B" } } })[1].hit == 9, "old table recaps still read")
print("recaps ok")

-- 3. an older save (1.3 and before: plain tables, 50 matches, 2000 players) converts
local old = { maxHistory = 50, maxPlayers = 2000, maxRecords = 500, history = {}, db = { records = {}, players = {}, applied = {} } }
SBR.sv = old
for i = 1, 30 do
    local kf, players = {}, {}
    for k = 1, 40 do kf[k] = { victim = "v", killer = "k", recap = { { hit = 100 + k, crit = k % 2 == 0, ability = "A", source = "S" } } } end
    for p = 1, 16 do players["@p" .. p] = { characterName = "P" .. p, displayName = "@p" .. p, team = p % 2 + 1, scores = { SCORE = p } } end
    old.history[i] = { id = "m" .. i, startedAt = 1000 + i, endedAt = 2000 + i, result = "won", players = players, killFeed = kf }
    old.db.records[i] = { id = "m" .. i, at = 1000 + i, kills = i, result = "won", top = { { name = "A", damage = 5, icon = "x" } } }
    old.db.applied["m" .. i] = true
end
for i = 1, 500 do old.db.applied["gone" .. i] = true end
for i = 1, 1200 do
    old.db.players["@q" .. i] = { key = "@q" .. i, name = "Q" .. i, lastSeen = i, matches = 1, kills = i, deaths = 1, assists = 2,
        damage = 100, healing = 10, score = 50, medals = 0, flags = 0, withMatches = 0, withWon = 0, againstMatches = 1, againstWon = 1,
        killedYou = 0, killedByYou = 0, damageToYou = 0, damageFromYou = 0, healedYou = 0, healedByYou = 0, bestScore = 50, abilities = { Fire = { name = "Fire", icon = "f", damage = i } }, classes = { Sorc = { className = "Sorc", matches = 1 } },
        maps = {}, characters = {} }
end
old.db.players["@me"] = { key = "@me", name = "Me", isYou = true, lastSeen = 0, matches = 30, kills = 0, withMatches = 0,
    againstMatches = 0, killedYou = 0, abilities = {}, classes = {}, maps = {}, characters = {} }
local tablesBefore = countTables(old)

ML:Init(old)
DB:Init(old)
check(old.maxHistory == 20 and old.maxPlayers == 1000, "old defaults move to the new ones")
check(#ML:GetHistory() == 30 and ML:GetHistory()[30].id == "m30", "old history readable straight away")
check(DB:GetPlayer("@q5").kills == 5, "old players readable straight away")
ML:StartBackgroundCompaction()
local steps = 0
local job = SBR.name .. "_Compact"
while updates[job] and steps < 10000 do updates[job](); steps = steps + 1 end
check(steps < 10000, "background job finishes")
check(#ML:GetHistory() == 20 and ML:GetHistory()[1].id == "m11", "history trimmed, oldest first")
check(#old.history == 0 and #old.packedHistory == 20, "matches packed")
check(#old.db.records == 0 and #old.db.recordsPacked == 30, "records packed")
check(next(old.db.players) == nil, "players packed")
local napplied = 0
for k in pairs(old.db.applied) do napplied = napplied + 1; check(k:match("^m%d+$") ~= nil, "stale ids dropped: " .. k) end
check(napplied == 20, "applied ids pruned to history")
local nplayers = 0
for _ in pairs(old.db.playersPacked) do nplayers = nplayers + 1 end
check(nplayers == 1000 and old.db.playersPacked["@me"], "players trimmed to 1000, you kept")
local tablesAfter = countTables(old)

-- 4. reload from the converted save
local saved = plainCopy(old, "sv")
SBR.sv = saved
ML:Init(saved)
DB:Init(saved)
local h = ML:GetHistory()
check(#h == 20 and SBR.IsLazy(h[1]), "history loads packed (unpacked on first use)")
check(h[20].id == "m30" and h[20].result == "won" and #h[20].killFeed == 40, "a match reads back")
check(ML.DecodeRecap(h[20].killFeed[2])[1].crit == true, "its recaps read back")
check(#DB:GetRecords() == 30 and DB:GetRecords()[30].kills == 30, "records read back")
local q = DB:GetPlayer("@q1200")
check(q and q.kills == 1200, "players read back")
local sum = DB:PlayerSummary(q)
check(sum.abilities[1].name == "Fire" and sum.abilities[1].icon == "f" and sum.classes[1].className == "Sorc", "old player fields still summarize")
print(string.format("old save converts in %d background steps (%.0f s); saved tables %d -> %d", steps, steps * 0.2, tablesBefore, tablesAfter))
print("all saved-variables tests passed")
