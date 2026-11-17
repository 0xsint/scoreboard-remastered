# Scoreboard Remastered (ESO)

An Elder Scrolls Online add-on that remasters the battleground scoreboard. It opens
next to the native scoreboard, logs everything the native scoreboard tracks, adds fight
data from **LibFights** (with a built-in combat-log fallback), and keeps a saved history
of your matches.

## Install

Copy this folder into
`Documents/Elder Scrolls Online/live/AddOns/ScoreboardRemastered/`
(the folder name must match `ScoreboardRemastered.addon`). Works on PC/Mac and on
console (Xbox / PlayStation). Optional: LibFights, LibAddonMenu-2.0 (PC settings
panel), LibHarvensAddonSettings (console / gamepad settings panel).

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

Fight data for **every player on the scoreboard**:

- **You:** [LibFights](https://github.com/0xsint/LibFights), summed across every fight in the
  match. That covers damage, healing, DPS/HPS (over active time), damage/healing taken, shields
  absorbed, mitigation, blocked damage, overheal, killing blows, deaths, interrupts and CC done
  and received, crit rate, max hit and its ability, light/heavy attacks, skills, ultimates,
  weaves, top damage and heal abilities with icons, and the number of fights.
- **Teammates and enemies:** a per-player combat ledger that records every combat event the
  client sends during the match. It gives damage done and taken, healing done and taken,
  DPS/HPS over each player's own active time, crit and heal-crit rate, max hit and its ability,
  killing blows, interrupts, CC applied and taken, shields absorbed, damage blocked, and top
  damage and heal abilities. It uses LibFights' own result categories, so both sources agree
  on what counts as damage, healing or CC.
- **You vs each player:** damage each way, healing each way, and kills each way.
- **Death recaps for every kill** in the kill feed: the last hits the victim took before dying.
  Your own deaths also get LibFights' full recap.
- **A fight list** for the match (LibFights): title, duration, DPS, damage, healing, KBs and deaths.

**What the client can see.** ESO only sends combat events where the source or target is
you, your pet or a member of your group:

| Player | Coverage |
|---|---|
| You | complete |
| Teammates in your group | complete for everything they do and everything done to them |
| Enemies | everything they did to your team and everything your team did to them. Their healing, and fights with a third team in 3-team modes, aren't visible. Their healing shows "-", not 0 |

In 2-team modes, an enemy's damage done is all their damage. The native scoreboard's
Damage/Healing columns stay authoritative for everyone.

Matches are saved in `SavedVariables/ScoreboardRemastered.lua`
(`history`, 50 by default). A match still in progress (`current`) survives `/reloadui`.

## Using it

### PC with mouse and keyboard

- The panel opens and closes with the native battleground scoreboard and anchors
  to its right side. Drag it to give it a fixed position (`/sbr reset` undoes this).
- **Click a row** to open its details beside the panel: medals, every fight stat, top
  abilities and the you-vs-them breakdown. Click the row again, or the X, to close.
- Click a column header to sort. Hover a header to see what it measures.
- `<` `Live` `>` browse saved matches. **Export** gives a CSV and **Kill feed** gives
  the kill log, both in a pre-selected box ready for Ctrl+C.
- Keybinds: *Controls → Scoreboard Remastered*.

### Console, or gamepad mode on PC

While the native battleground scoreboard is open, its button bar gets
**Open Remastered** (right stick click by default; you can change it in settings).
That opens the panel on its own screen with your row selected:

| Xbox | PlayStation | Action |
|---|---|---|
| D-pad / left stick up, down | same | move the selected row |
| D-pad / left stick left, right | same | sort by the previous / next column |
| **A** | **Cross** | show / hide details for the selected row (they follow the selection) |
| B | Circle | close the kill feed, then details, then the panel |
| X | Square | flip the sort order |
| Y | Triangle | kill feed (scroll with up/down, page with left/right) |
| LB / RB | L1 / R1 | previous / next saved match |
| L3 | L3 | group by team on / off |

The gamepad table uses bigger text and fewer columns. The rest of the stats are in the
details pane. Settings has an **Open Scoreboard Remastered** button so you can browse
saved matches outside a battleground, since consoles have no slash commands. On console,
10 matches are kept by default because console SavedVariables are smaller.

### Slash commands (PC)

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
   `Start_Logging({ rawEvents = false, saveFights = false })`.
   If another add-on or you already started logging, it shares that session and
   never stops it.
2. Every `FIGHT_ENDED` during the match is stored. Each snapshot also reads
   `LibFights.GetCurrentFight()`, so the panel stays live mid-fight.
3. Your row is built from `f:GetSummary()` and `f:GetAbilityBreakdown()`.
   `f:GetTargets()`, `f:GetSources()` and `f.healTargets` are a fallback for the
   you-vs-them columns if the ledger is turned off. Your death recaps come from
   the `DEATH` callback.
4. When the match ends, it calls `Stop_Logging()`, but only if it started the
   logging. That closes the running fight, so the last fight is counted too.
   Per-fight breakdowns are then reduced to a compact fight list, which keeps
   SavedVariables small.

Settings: *Use LibFights*, and *Also save fights in LibFights' SavedVariables* (off by
default, so battlegrounds don't fill your LibFights saved fights). Other players' stats
come from the combat ledger (*Fight stats for every player*), not from LibFights' group
mode, so LibFights runs in its lighter player-only mode.

LibFights drops fights shorter than its `minFightSeconds` (2s by default), so
very short skirmishes don't count toward the fight stats. The native scoreboard
columns are unaffected.

## Notes

- The combat ledger is saved with the in-progress match, so `/reloadui` mid-match keeps
  it. It is dropped when the match ends, since each player's row already holds the totals.
- Battleground teams are normally grouped. If a teammate isn't in your group, they only
  get the stats from their interactions with you.
- Every game API call is protected. If ZOS renames a function, that column goes
  empty and nothing errors. If the panel doesn't open with the scoreboard, run
  `/sbr hooks` and add the scene or fragment name to `UI/ScoreboardHook.lua`.
- The gamepad view uses ESO's standard gamepad building blocks: its own scene, the
  keybind strip, directional input and the movement controller. Like the rest of the
  add-on, it hasn't been run on a console yet. If a button doesn't show up, the
  settings panel has the open button and the open-key choice.
- The panel uses ESO's own text colours (`ZO_NORMAL_TEXT`, `ZO_SELECTED_TEXT`, `ZO_DISABLED_TEXT`)
  and stock list textures (row highlight, selected highlight, divider, sort arrows from
  `EsoUI/Art/Miscellaneous/`). Each texture sits on top of a plain colour, so if a path
  changes in a game update the panel still reads correctly, just with less polish.
- Update `## APIVersion` in `ScoreboardRemastered.addon` to the current client
  (`/script d(GetAPIVersion())`).
