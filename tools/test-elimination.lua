-- Run with the simulation in its Elimination mode:
--   SIM_ELIMINATION=1 SIM_AFTER=tools/test-elimination.lua lua5.1 tools/simulate.lua . <LibFights> out/m.json out/s.json
-- Checks that a 3-round, limited-lives match keeps updating past round 1: every
-- player's saved totals are the whole match, and lives are recorded.
local SBR = ScoreboardRemastered
local h = SBR.MatchLog:GetHistory()
local m = SBR.Realize(h[#h])
local checked, withLives = 0, 0
for _, p in pairs(m.players) do
    local kills = p.scores and p.scores.KILL
    local scoreOk = type(kills) == "number"
    assert(scoreOk, "kills recorded")
    checked = checked + 1
    if p.lives ~= nil then withLives = withLives + 1 end
end
-- totals must be the whole match: at least as many kills as the kill feed credits
local feed = {}
for _, k in ipairs(m.killFeed) do feed[k.killer] = (feed[k.killer] or 0) + 1 end
for _, p in pairs(m.players) do
    local n = feed[p.characterName] or 0
    assert((p.scores.KILL or 0) >= n, string.format("%s: %d kills saved, %d in the kill feed (stuck on round 1?)", p.characterName, p.scores.KILL or 0, n))
end
assert(m.numRounds == 3 and m.limitedLives, "match knows it is a 3-round, limited-lives mode")
assert(withLives == checked, "lives recorded for every player")
io.stderr:write(string.format("elimination ok: %d players, totals match the kill feed, lives recorded\n", checked))
