-- Saved-variables tests: recap encoding and the background compaction.
-- Run from the repository root: lua5.1 tools/test-savedvars.lua
do
ScoreboardRemastered = { name = "SBR" }
EVENT_MANAGER = { RegisterForUpdate = function() end }
dofile("Data/MatchLog.lua")
local ML = ScoreboardRemastered.MatchLog
local enc = ML.EncodeRecap({ { hit = 1627.4, crit = true, ability = "Fatecarver", source = "Nhalia" }, { hit = 5, ability = "", source = "?" } })
assert(#enc == 2 and type(enc[1]) == "string")
local dec = ML.DecodeRecap({ recap = enc })
assert(dec[1].hit == 1627 and dec[1].crit == true and dec[1].ability == "Fatecarver" and dec[1].source == "Nhalia", "first")
assert(dec[2].hit == 5 and dec[2].crit == nil and dec[2].ability == "" and dec[2].source == "?", "second")
local legacy = ML.DecodeRecap({ recap = { { hit = 9, ability = "A", source = "B" } } })
assert(legacy[1].hit == 9)
print("recap encode/decode ok")
end
do
ScoreboardRemastered = { name = "SBR", sv = {} }
local updates = {}
EVENT_MANAGER = { RegisterForUpdate = function(_, ns, ms, f) updates[ns] = f end, UnregisterForUpdate = function(_, ns) updates[ns] = nil end }
dofile("Data/MatchLog.lua")
local SBR, ML = ScoreboardRemastered, ScoreboardRemastered.MatchLog
local sv = { maxHistory = 50, maxPlayers = 2000, history = {} }
local applied, players = {}, {}
for i = 1, 30 do
    local kf = {}
    for k = 1, 40 do kf[k] = { victim = "v", recap = { { hit = 100 + k, crit = k % 2 == 0, ability = "A", source = "S" } } } end
    sv.history[i] = { id = "m" .. i, killFeed = kf }
    applied["m" .. i] = true
end
for i = 1, 500 do applied["old" .. i] = true end
for i = 1, 1200 do players["p" .. i] = { lastSeen = i } end
players.me = { isYou = true, lastSeen = 0 }
SBR.MatchDB = { applied = applied, players = players }
ML:Init(sv)
assert(sv.maxHistory == 20 and sv.maxPlayers == 1000, "defaults migrated")
ML:StartBackgroundCompaction()
local steps = 0
while updates.SBR_Compact and steps < 5000 do updates.SBR_Compact(); steps = steps + 1 end
assert(#sv.history == 20, "history trimmed: " .. #sv.history)
assert(sv.history[1].id == "m11", "oldest dropped first")
for _, m in ipairs(sv.history) do for _, k in ipairs(m.killFeed) do assert(type(k.recap[1]) == "string", "recap compacted") end end
local n = 0; for k in pairs(applied) do n = n + 1; assert(k:match("^m%d+$") and tonumber(k:sub(2)) > 10, "stale id kept: " .. k) end
assert(n == 20, "applied pruned to history: " .. n)
local pc = 0; for _ in pairs(players) do pc = pc + 1 end
assert(pc == 1000 and players.me, "players trimmed, you kept: " .. pc)
assert(ML.DecodeRecap(sv.history[20].killFeed[2].recap and sv.history[20].killFeed[2])[1].crit == true)
print(string.format("background compaction ok in %d steps (%.0f s at 200 ms a step)", steps, steps * 0.2))
end
