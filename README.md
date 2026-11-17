# Scoreboard Remastered (ESO)

An Elder Scrolls Online add-on that remasters the battleground scoreboard. It opens
next to the native scoreboard, logs everything the native scoreboard tracks, adds fight
data from **LibFights** (with a built-in combat-log fallback), and keeps a saved history
of your matches.

## Install

Copy this folder into
`Documents/Elder Scrolls Online/live/AddOns/ScoreboardRemastered/`
(the folder name must match `ScoreboardRemastered.txt`). Optional: LibFights,
LibAddonMenu-2.0 (for a settings panel).

## What it logs

From the native scoreboard, re-read on every `EVENT_BATTLEGROUND_SCOREBOARD_UPDATED`
and every 5 seconds:

- Battleground name, game type, team size, rounds, state, timer, your team
- Every team's name, color and score, plus per-round team scores
- Every player: character name, @account, team, class and class icon
- **Every score type the client defines.** It finds all `SCORE_TRACKER_TYPE_*`
  constants at load time, so new score types appear without an add-on update
- Medals per player (name, icon, count) and your own medals in the order you earned them
- A kill feed (`EVENT_BATTLEGROUND_KILL`): killer, victim, teams, ability, time
- Players who left mid-match are kept and marked *(left)*
- The result (victory, defeat, tie or left early) and the match duration

Fight data (LibFights first, built-in tracker fills gaps):

- DPS, HPS, damage and healing done and taken, killing blows, deaths, interrupts,
  CC applied and taken, shields, blocked damage, crit rate, combat time, your top abilities
- "You vs them" per player: damage you dealt them, damage they dealt you,
  healing you gave them, and kills each way

Matches are saved in `SavedVariables/ScoreboardRemastered.lua`
(`history`, 50 by default). A match still in progress (`current`) survives `/reloadui`.

## Using it

- The panel opens and closes with the native battleground scoreboard and anchors
  to its right side. Drag it to give it a fixed position (`/sbr reset` undoes this).
- Click a column header to sort. Hover a row to see medals, all fight stats and
  the you-vs-them breakdown.
- `<` `Live` `>` browse saved matches. **Export** gives a CSV and **Kill feed** gives
  the kill log, both in a pre-selected box ready for Ctrl+C.
- Keybinds: *Controls → Scoreboard Remastered*.

| Command | |
|---|---|
| `/sbr` | toggle panel |
| `/sbr export` / `/sbr kills` | CSV / kill feed of the viewed match |
| `/sbr history [n]` | list saved matches / open match *n* |
| `/sbr live` | back to the live match |
| `/sbr attach right\|left\|below\|free`, `/sbr reset` | positioning |
| `/sbr status` | fight providers and score types detected |
| `/sbr hooks` | which native scoreboard scenes/fragments were hooked |
| `/sbr clear`, `/sbr debug` | clear history, toggle debug output |

## LibFights integration

Edit `Data/LibFightsAdapter.lua` only.

**Option A: auto-detect (no changes to LibFights).** If a global `LibFights` exists
(or LibStub `"LibFights-1.0"`), the adapter calls the first method it finds out of
`GetPlayerStats`, `GetStatsForPlayer`, `GetUnitStats`, `GetPlayerFightData` and `GetStats`, as:

```lua
LibFights:GetPlayerStats(characterName, displayName, isLocal) -> table | nil
```

It maps the result's fields through the `FIELDS` alias table. For example,
`damage`, `dmg` and `damageDone` all become `damageDone`. If your names differ,
add them to `FIELDS` or `METHOD_CANDIDATES`. If the lib has a `Reset` method, it is
called at match start. If it has `GetMatchSummary` or `GetFightSummary`, the result
is saved with the match.

**Option B: push from LibFights.**

```lua
ScoreboardRemastered.RegisterFightProvider({
    name = "LibFights",
    GetPlayerStats = function(self, characterName, displayName, isLocal)
        return { damageDone = ..., healingDone = ..., dps = ..., killingBlows = ... }
    end,
    OnMatchStart = function(self, info) end,       -- optional
    OnMatchEnd = function(self, match) end,        -- optional
    GetMatchSummary = function(self) return {} end, -- optional, saved with the match
})
```

Call this after `ScoreboardRemastered` has loaded, for example in `EVENT_PLAYER_ACTIVATED`.
Load order puts LibFights first, so a call at LibFights' own load-time is too early.

Canonical stat keys: `damageDone damageTaken healingDone healingTaken dps hps
killingBlows deaths interrupts ccApplied ccTaken damageShielded damageBlocked
critRate activeTime fights`.

## Notes

- The ESO client only reports combat events that involve you, so the built-in tracker
  has full stats for you and you-vs-them stats for others. Full stats for every player
  need LibFights (or another provider) to supply them.
- Every game API call is protected. If ZOS renames a function, that column goes
  empty and nothing errors. If the panel doesn't open with the scoreboard, run
  `/sbr hooks` and add the scene or fragment name to `UI/ScoreboardHook.lua`.
- Update `## APIVersion` in `ScoreboardRemastered.txt` to the current client
  (`/script d(GetAPIVersion())`).
