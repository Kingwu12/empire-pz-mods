# Play-ready: what was decided, and the one command (26 Nov 2026, Build 42.22.2)

**Bottom line.** Everything that can be set up is set up. What is left is subscribing to 14 Workshop items (14 clicks on your Steam account), then one command that checks the whole pack and says READY.

```
.\tools\ready-to-play.ps1          (PowerShell on the PC, game closed; -Check only reports)
```

Quickest way to subscribe: run `.\tools\open-workshop-pages.ps1` in PowerShell on the PC. It opens the 15 pages below one at a time in your signed-in Steam client, so each is one click (the last one is the Unsubscribe).

## The decisions

| Question | Decision | Why |
|---|---|---|
| Java mods or Lua? | **Lua only.** | The Indie Stone (21 Oct) support Lua only; Java mods break on updates, need a loader, and the Java NPC mod (Knox Survivors) was the one that froze 1-2 s. Java is faster per operation, but our lag is how often code runs, not the language. |
| NPCs | **Bandits NPC + NPC Crew** (Lua, no loader). Alternative if it disappoints: Stay With Me. | Best colony features among Lua mods (beacon, zones, sorters, farmer, builder, hunter, loot runs). Cost grows with zombie count, so population is lowered below. |
| Which pack | **`EmpirePlay`: 176 mods.** Fallback `EmpireB42-22-lean` (35 mods, the performance control). | Your 184-mod pack minus 21 (13 cut, 7 replaced, 1 Knox-only window), plus 7 maintained additions and the Louisville Shipping Port with its 6 tile packs. |
| Zombie population | **Low** (`Sandbox Presets\EmpirePlay.cfg`, a copy of your `empire.cfg` with `Zombies=5`). `empire.cfg` is untouched. | NPC mods cost frame time per zombie. Change it back in the sandbox screen if the run feels empty. |
| JVM heap | **-Xms2048m -Xmx6144m**, applied. | Steam's update had reset it to stock 3 GB, probably the biggest cause of the old lag. Re-run the script after every game update. |
| Sorting and chores | **Automatic** (`13_AutoChores`): corpse looting, base sort, park and unload, one 10-minute beat, no per-frame work. Numpad 5 turns it off. | "I love empire building but dont like the sorting and small things." |

## What the 7 additions are

Subscribe (Steam page > Subscribe):

1. [Common Sense B42.20+ (VB_CommonSense)](https://steamcommunity.com/sharedfiles/filedetails/?id=3750253491), replaces the old Common Sense that throws on 42.21+. `ReloadAllMagazines` is dropped because this one already reloads all.
2. [Evolving Traits World](https://steamcommunity.com/sharedfiles/filedetails/?id=2914075159), replaces More Traits Legacy (unsupported). Turn dynamic gain and loss off.
3. [Bandits NPC](https://steamcommunity.com/sharedfiles/filedetails/?id=3268487204), the NPC base.
4. [NPC Crew](https://steamcommunity.com/sharedfiles/filedetails/?id=3800132623), the colony jobs on top of it.
5. [H.E.C.U. B42.20](https://steamcommunity.com/sharedfiles/filedetails/?id=3737864976), same mod id as your old H.E.C.U. **Then unsubscribe the old item** [3452711271](https://steamcommunity.com/sharedfiles/filedetails/?id=3452711271): two items with one id fight each other.
6. [KI5 Vehicle Performance Patch](https://steamcommunity.com/sharedfiles/filedetails/?id=3808100388) and 7. [KI5 General Fixes](https://steamcommunity.com/sharedfiles/filedetails/?id=3789366983): the 12 KI5 vehicles each add a per-frame handler; these remove part of that cost and the vehicle-load stutter. The performance patch is unofficial (its author promises no support).

Wait for Steam to finish the downloads (the port and its tile packs are listed in the next section), then run the script again. It prints the exact list of anything still missing, and when all is well it makes `EmpirePlay` the default mod list for new games.

## The shipping port (added at your request)

The mod you meant is **Louisville Shipping Port** by Simon MD: a map mod just west of Louisville Airport (cells 41:15, 41:16, 42:16) with two docked ships, a military vessel and a freighter, and rows of shipping containers full of loot. Its loot respawns. It is tagged Build 42 and was updated 5 Nov. No map mod already in the pack overlaps those cells (checked against the installed ones on the PC). The game orders map mods itself, so the preset has no map entry.

Subscribe to the port and the six tile packs it needs (PertsPartyTiles, the seventh, is already installed):

1. [Louisville Shipping Port](https://steamcommunity.com/sharedfiles/filedetails/?id=3149613879) (mod id `SimonMDLVHarbor`, 15 MB)
2. [Simon MD's Tiles](https://steamcommunity.com/sharedfiles/filedetails/?id=2852704777) (`simonMDsTiles`, 809 MB)
3. [Melos Tiles for Miles Tilepack](https://steamcommunity.com/sharedfiles/filedetails/?id=2879745353) (`melos_tiles_for_miles_pack`, 1.6 GB)
4. [Community Tile Pack](https://steamcommunity.com/sharedfiles/filedetails/?id=3628736763) (`UnofficialMappersCommunityTilePack`, 220 MB)
5. [Daddy Dirkie dirks tiles](https://steamcommunity.com/sharedfiles/filedetails/?id=2337452747) (`Diederiks Tile Palooza`, 64 MB)
6. [Dylan's Tile Pack](https://steamcommunity.com/sharedfiles/filedetails/?id=2599752664) (`DylansTiles`, 71 MB)
7. [throttlekitty's tiles](https://steamcommunity.com/sharedfiles/filedetails/?id=2384329562) (`tkTiles_01`, 10 MB)

About 2.8 GB to download; the PC's Steam drive has 1.5 TB free. Tile packs hold no Lua, so they add loading time and some texture memory, not per-frame work. The port itself is unmeasured: if the frame rate drops near the docks, that is the place to look. Also unverified until the downloads land: the mod ids above come from the Workshop descriptions. If any differs from its real `mod.info`, the script prints the ids the item really provides.

`Containers!` (the placeable shipping containers, `isoContainers`) is a different mod. It stays in the pack as TEST.

## What the check found (so you do not have to)

- Every required mod is in the pack, and every mod loads after the mods it needs (six were in the wrong order and are fixed).
- **Tank Water is cut**: its own `mod.info` says it is incompatible with Starlit Library, which two other mods in the pack need, so the game could not enable both.
- EmpireCommand (the Knox roster window) is out: Knox Survivors is cut.
- Every mod has a version folder that matches 42.22.2 (including the Neat mods, which shipped a 42.22 folder).
- Old `EmpireStable.txt` and `EmpireLean.txt` in `Zomboid\mods` are the pre-audit presets (they still include Knox). Do not use them.

## First play session

1. New Game > Mods: `EmpirePlay` is already ticked. Sandbox: pick preset `EmpirePlay`. In the Sandbox mod options set Bandits NPC to **no hostile bandits** and keep the NPC count low; tell Claude after subscribing and it writes the exact keys into the preset.
2. Once in the game press **Numpad 9** and read the `[EmpireTest]` lines in `Zomboid\console.txt`. Any `FAIL` names the Empire feature that did not wire up on 42.22.2.
3. After a session, search `console.txt` for `[EmpireAutoChores] auto-sort took`. Over about 250 ms means the base sort is too heavy: say so.
4. Frame rate: if it is bad, switch the mod list to `EmpireB42-22-lean` on a new save and compare. The bake-off steps are in `PLAYTHROUGH-B42.22.md`.

## Not tested

Nothing here has been run in the real game: the preset has never been loaded, the auto-chores have only mock tests, and the mods marked TEST are plausible but unmeasured on 42.22.2. Expect to cut a few after the first sessions; the console log names the ones that throw.
