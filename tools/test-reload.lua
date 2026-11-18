-- Run with the simulation: SIM_AFTER=tools/test-reload.lua lua5.1 tools/simulate.lua . <LibFights> out/m.json out/s.json
-- Saves the saved variables as plain data, loads the add-on again from them, and
-- checks every match, record and player reads back the same.
local SBR = ScoreboardRemastered
local function plainCopy(v, path)
    if type(v) ~= "table" then return v end
    if getmetatable(v) then error("saved variables hold a table with a metatable at " .. path) end
    local out = {}
    for k, x in pairs(v) do out[k] = plainCopy(x, path .. "." .. tostring(k)) end
    return out
end
local before = {
    history = {}, records = {}, players = {},
}
for _, m in ipairs(SBR.MatchLog:GetHistory()) do
    local n = 0; for _ in pairs(m.players) do n = n + 1 end
    before.history[#before.history + 1] = { id = m.id, players = n, kills = #m.killFeed, result = m.result }
end
for _, r in ipairs(SBR.MatchDB:GetRecords()) do before.records[#before.records + 1] = r.id .. ":" .. tostring(r.kills) .. ":" .. tostring(r.result) end
for k, e in pairs(SBR.MatchDB.players) do before.players[k] = e.matches .. ":" .. e.kills .. ":" .. tostring(e.isYou) end

local saved = plainCopy(SBR.sv, "sv")
-- a fresh load from the saved copy
SBR.sv = saved
SBR.MatchLog:Init(saved)
SBR.MatchDB:Init(saved)
local after = { history = {}, records = {}, players = {} }
for _, m in ipairs(SBR.MatchLog:GetHistory()) do
    assert(SBR.IsLazy(m), "history is not unpacked at load")
end
for _, m in ipairs(SBR.MatchLog:GetHistory()) do
    local n = 0; for _ in pairs(m.players) do n = n + 1 end
    after.history[#after.history + 1] = { id = m.id, players = n, kills = #m.killFeed, result = m.result }
end
for _, r in ipairs(SBR.MatchDB:GetRecords()) do after.records[#after.records + 1] = r.id .. ":" .. tostring(r.kills) .. ":" .. tostring(r.result) end
for k, e in pairs(SBR.MatchDB.players) do after.players[k] = e.matches .. ":" .. e.kills .. ":" .. tostring(e.isYou) end
assert(#after.history == #before.history and #after.history > 0, "history count")
for i, h in ipairs(before.history) do
    local a = after.history[i]
    assert(a.id == h.id and a.players == h.players and a.kills == h.kills and a.result == h.result, "history match " .. i)
end
assert(#after.records == #before.records, "records count")
for i, r in ipairs(before.records) do assert(after.records[i] == r, "record " .. i) end
local n = 0
for k, v in pairs(before.players) do n = n + 1; assert(after.players[k] == v, "player " .. k) end
local recaps = 0
for _, m in ipairs(SBR.MatchLog:GetHistory()) do
    for _, k in ipairs(m.killFeed) do recaps = recaps + #SBR.MatchLog.DecodeRecap(k) end
end
assert(recaps > 0, "recaps survive")
io.stderr:write(string.format("reload round trip ok: %d matches, %d records, %d players, %d recap hits\n",
    #after.history, #after.records, n, recaps))
