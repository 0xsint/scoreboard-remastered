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

Fight data from [LibFights](https://github.com/0xsint/LibFights), summed across every fight in the match:

- **You:** damage, healing, DPS/HPS (over active time), damage/healing taken, shields
  absorbed, mitigation, blocked damage, overheal, killing blows, deaths, interrupts done and
  received, CC done and received, crit rate, max hit and its ability, light/heavy attacks,
  skills, ultimates, weaves, top damage and heal abilities with icons, and the number of fights
- **Teammates** (LibFights group mode): damage, healing, crit rate, shields absorbed
- **Everyone:** damage you dealt them, damage they dealt you, healing you gave them, and
  kills each way (from the kill feed)
- **Your deaths** with LibFights' death recap (the last hits before each death)
- **A fight list** for the match: title, duration, DPS, damage, healing, KBs and deaths

Without LibFights, a built-in combat-log tracker gives a smaller version of the "you" and
"everyone" data.

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
| `/sbr status` | LibFights state and the score types detected |
| `/sbr hooks` | which native scoreboard scenes/fragments were hooked |
| `/sbr clear`, `/sbr debug` | clear history, toggle debug output |

## LibFights integration

Nothing needs configuring. When a battleground starts:

1. If LibFights isn't already logging, Scoreboard Remastered calls
   `Start_Logging({ groupMode = true, rawEvents = false, saveFights = false })`.
   If another add-on or you already started logging, it shares that session and
   never stops it.
2. Every `FIGHT_ENDED` during the match is stored. Each snapshot also reads
   `LibFights.GetCurrentFight()`, so the panel stays live mid-fight.
3. Each player's numbers are built from `f:GetSummary()`, `f:GetTargets()`,
   `f:GetSources()`, `f.healTargets`, `f:GetGroup()` and
   `f:GetAbilityBreakdown()`. Your death recaps come from the `DEATH` callback.
4. When the match ends, it calls `Stop_Logging()`, but only if it started the
   logging. That closes the running fight, so the last fight is counted too.
   Per-fight breakdowns are then reduced to a compact fight list, which keeps
   SavedVariables small.

Settings: *Use LibFights*, *Group mode* (teammates' damage/healing; costs more
CPU in 8v8), and *Also save fights in LibFights' SavedVariables* (off by default,
so battlegrounds don't fill your LibFights saved fights).

LibFights drops fights shorter than its `minFightSeconds` (2s by default), so
very short skirmishes don't count toward the fight stats. The native scoreboard
columns are unaffected.

## Notes

- The ESO client only reports combat events that involve you (and your group in group
  mode), so full fight stats for enemies aren't possible from any add-on. The native
  scoreboard columns cover every player.
- Every game API call is protected. If ZOS renames a function, that column goes
  empty and nothing errors. If the panel doesn't open with the scoreboard, run
  `/sbr hooks` and add the scene or fragment name to `UI/ScoreboardHook.lua`.
- Update `## APIVersion` in `ScoreboardRemastered.txt` to the current client
  (`/script d(GetAPIVersion())`).
