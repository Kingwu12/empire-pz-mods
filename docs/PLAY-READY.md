# Play-ready: what was decided, and the one command (26 Nov 2026, Build 42.22.2)

**Bottom line (27 Nov).** Every Workshop item the pack needs is subscribed and downloaded (the old H.E.C.U. is unsubscribed; the five Guns of Marz items were added later the same day), and the check said READY for the earlier 178-mod list (every requirement present and in load order). The Guns of Marz list is also 178 mods and has not been through the check yet. `EmpirePlay` is already the default mod list on the PC and its sandbox preset has the NPC settings. The one thing left is to push the repo and pull it on the PC: until then the PC has the Empire mods from `8aca8cd`, without the newer automation (needs, farm, production, restock).

**Update (27 Nov, later): the guns changed.** Guns of '93 was only boring real guns, so the pack now runs **Guns of Marz** instead (section "Guns" below). Its five Workshop items are subscribed and downloaded. Checked since: each mod's real `mod.info` (ids, requirements, incompatible list), a recipe-reference scan of the whole new list (the 17 rows it flags are the same ones that loaded cleanly in your last run, none from a gun mod), and the Empire chore tests. Not checked: the world actually loading, which only your next new game shows. Run `ready-to-play.ps1` again after the repo is pushed and pulled on the PC. The preset is still 178 mods.

```
.\tools\ready-to-play.ps1          (PowerShell on the PC, game closed; -Check only reports)
```

If a Workshop item ever needs subscribing again, `.\tools\open-workshop-pages.ps1` opens each page in your signed-in Steam client, one click each.

## The decisions

| Question | Decision | Why |
|---|---|---|
| Java mods or Lua? | **Lua only.** | The Indie Stone (21 Oct) support Lua only; Java mods break on updates, need a loader, and the Java NPC mod (Knox Survivors) was the one that froze 1-2 s. Java is faster per operation, but our lag is how often code runs, not the language. |
| NPCs | **Bandits NPC + NPC Crew** (Lua, no loader). Alternative if it disappoints: Stay With Me. | Best colony features among Lua mods (beacon, zones, sorters, farmer, builder, hunter, loot runs). Cost grows with zombie count, so population is lowered below. |
| Which pack | **`EmpirePlay`: 178 mods.** Fallback `EmpireB42-22-lean` (35 mods, the performance control). | Your 184-mod pack minus 20 (12 cut, 7 replaced, 1 Knox-only window), plus 7 maintained additions, the two libraries Evolving Traits World needs (Moodle Framework, Unified Carry Weight Framework) and the Louisville Shipping Port with the 4 tile packs its B42 version needs. |
| Zombie population | **Low** (`Sandbox Presets\EmpirePlay.cfg`, a copy of your `empire.cfg` with `Zombies=5`). `empire.cfg` is untouched. | NPC mods cost frame time per zombie. Change it back in the sandbox screen if the run feels empty. |
| JVM heap | **-Xms2048m -Xmx6144m**, applied. | Steam's update had reset it to stock 3 GB, probably the biggest cause of the old lag. Re-run the script after every game update. |
| Sorting and chores | **Automatic** (`13_AutoChores`): corpse looting, base sort, park and unload, one 10-minute beat, no per-frame work. Numpad 5 turns it off. | "I love empire building but dont like the sorting and small things." |

## What the 7 additions are

Subscribe (Steam page > Subscribe):

1. [Common Sense B42.20+ (VB_CommonSense)](https://steamcommunity.com/sharedfiles/filedetails/?id=3750253491), replaces the old Common Sense that throws on 42.21+. `ReloadAllMagazines` is dropped because this one already reloads all.
2. [Evolving Traits World](https://steamcommunity.com/sharedfiles/filedetails/?id=2914075159), replaces More Traits Legacy (unsupported). Turn dynamic gain and loss off. It also needs [Moodle Framework](https://steamcommunity.com/sharedfiles/filedetails/?id=3396446795) (`MoodleFramework`, now subscribed and in the preset) and Unified Carry Weight Framework (already installed, now in the preset).
3. [Bandits NPC](https://steamcommunity.com/sharedfiles/filedetails/?id=3268487204), the NPC base.
4. [NPC Crew](https://steamcommunity.com/sharedfiles/filedetails/?id=3800132623), the colony jobs on top of it.
5. [H.E.C.U. B42.20](https://steamcommunity.com/sharedfiles/filedetails/?id=3737864976), same mod id as your old H.E.C.U. **Then unsubscribe the old item** [3452711271](https://steamcommunity.com/sharedfiles/filedetails/?id=3452711271): two items with one id fight each other.
6. [KI5 Vehicle Performance Patch](https://steamcommunity.com/sharedfiles/filedetails/?id=3808100388) and 7. [KI5 General Fixes](https://steamcommunity.com/sharedfiles/filedetails/?id=3789366983): the 12 KI5 vehicles each add a per-frame handler; these remove part of that cost and the vehicle-load stutter. The performance patch is unofficial (its author promises no support).

Wait for Steam to finish the downloads (the port and its tile packs are listed in the next section), then run the script again. It prints the exact list of anything still missing, and when all is well it makes `EmpirePlay` the default mod list for new games.

## The shipping port (added at your request)

The mod you meant is **Louisville Shipping Port** by Simon MD: a map mod just west of Louisville Airport (cells 41:15, 41:16, 42:16) with two docked ships, a military vessel and a freighter, and rows of shipping containers full of loot. Its loot respawns. It is tagged Build 42 and was updated 5 Nov. No map mod already in the pack overlaps those cells (checked against the installed ones on the PC). The game orders map mods itself, so the preset has no map entry.

Subscribed on 27 Nov (the port's Subscribe-to-All also pulled in three old B41-era tile packs):

1. [Louisville Shipping Port](https://steamcommunity.com/sharedfiles/filedetails/?id=3149613879) (mod id `SimonMDLVHarbor`, 15 MB)
2. [Simon MD's Tiles](https://steamcommunity.com/sharedfiles/filedetails/?id=2852704777) (`simonMDsTiles`, 809 MB)
3. [Melos Tiles for Miles Tilepack](https://steamcommunity.com/sharedfiles/filedetails/?id=2879745353) (`melos_tiles_for_miles_pack`, 1.6 GB)
4. [Community Tile Pack](https://steamcommunity.com/sharedfiles/filedetails/?id=3628736763) (`UnofficialMappersCommunityTilePack`, 220 MB)
5. PertsPartyTiles (already in the pack)

The port's own B42 `mod.info` (its `42` folder, which the game reads on 42.22) requires exactly those four tile packs. Its old B41 file also lists Daddy Dirkie's, Dylan's and throttlekitty's tiles; those are not needed on B42, so they are **not** in `EmpirePlay`. They are still subscribed (about 140 MB, harmless): unsubscribe them if you want a tidier library. The script now reads only the `mod.info` the game would use, so it does not ask for them.

Tile packs hold no Lua, so they add loading time and some texture memory, not per-frame work. The port itself is unmeasured: if the frame rate drops near the docks, that is the place to look.

`Containers!` (the placeable shipping containers, `isoContainers`) is a different mod. It stays in the pack as TEST.

## Realism and crafting (27 Nov, your call: loot respawn is not realistic, ammo must be craftable)

What the preset had before: loot respawned every 200 hours; food, medical, ammo, guns, mechanics and materials were all "abundant"; tools and recipe parts were "rare"; and three mods made zombies drop ammo, magazines and guns from about half of all bodies. That is the opposite of a crafting game.

What it is now (`docs/presets/EmpirePlay-mod-options.cfg`, written into `Sandbox Presets\EmpirePlay.cfg` by the script):

| Setting | Before | Now | Why |
|---|---|---|---|
| `HoursForLootRespawn` | 200 | **0 (off)** | A looted shelf stays empty. The world is finite, so farming, trapping and crafting matter. |
| `AmmoLootNew`, `RangedWeaponLootNew` | abundant (3.0) | **normal (1.0)** | A global squeeze hits gun shops and armories as hard as a random shelf, which is not realistic or fun. The dial stays at normal and the Empire Stockpiles mod (below) decides where the supply sits. |
| `ToolLootNew`, `RecipeResourceLoot` | rare (0.6) | **normal (1.0)** | Crafting is the main loop, so the things recipes need are not scarce. |
| Zombie ammo, magazine and gun drops | 3 Guns of '93 add-on mods (ammo from about 55 percent of ALL bodies) | **Guns of Marz's own armed zombies** | Marz spawns zombies carrying a gun by outfit (civilian, police, army); each one drops that gun, a few magazines and a box of the right calibre when it dies. Police stations, army bases and prisons pay out; the suburbs do not. The rate is Marz's own: tune it after the first police station with `MarzGuns.LootMultiplier`. |

**Ammo from found things: Ammo Maker** (Workshop 2788256295, mod id `ammomaker`, 330k subscribers, updated 11 Nov with a 42.22.2 hotfix). Vanilla 42.22.2 cannot make or reload any ammo (it only boxes, unboxes, and breaks a round down to gunpowder). Ammo Maker adds gunpowder (nitre beds), lead and brass casting, a reloading press and casings, for over 80 calibres, and Guns of Marz ships a table built for it. Primers are off by default (sandbox `ammomakerOptions.Primers`); turn them on later for the harder version. It is script and art only (no Java), it overrides no vanilla functions, and its loot hooks are two ten-minute handlers plus the container-fill hook. Its licence forbids patching or forking it, so anything we add goes in a separate mod. Not tested in the game yet.

## Guns (27 Nov, second pick: Guns of Marz)

You said Guns of '93 was "all boring old guns", so it is out. The pack now runs the **Guns of Marz** stack, read from the real mod files:

| Mod | Workshop | Mod id | What it does |
|---|---|---|---|
| Gunworks Framework | 3722064198 | `SWMG` | Library Guns of Marz needs: folding stocks, bipods, bayonets, underbarrel launchers, mixed ammo, real rate of fire. |
| Guns of Marz | 3722134990 | `GunsOfMarz` | About 90 guns and 150 ammo and magazine items (below). Enable `GunsOfMarz` only, never `MarzGuns` (the old version; the mod itself lists it as incompatible). |
| Gunworks Heavy Ordnance | 3802070967 | `HeavyOrdnance` | RPG-7 rocket launcher with visible rockets and explosions that throw zombies. |
| Reload Your Weapons Again | 3837229266 | `ReloadBackAgain` | Fixes the endless reload errors that vanilla 42.22 throws with ALICE-pack style gear. |
| Gun Hit Fix 42.22 | 3837999415 | `GunHitFix42_22` | Vanilla 42.22 bug: with Sandbox "Firearms Use Damage Chance" on, bullets that "hit" can do no damage. This makes connecting bullets always hurt. |

**The fun, from the files:** an M60 machine gun, an AA-12 full-auto shotgun, an M79 and M203 grenade launchers (HE, buckshot and incendiary 40mm rounds), the CAR-15 and M16A2 with underbarrel M203, a silenced AS Val, an SVD and PSG-1 for sniping, a BAR, M1 Garand, Thompson, MP5 family, MAC-10, Tec-9, AKs, FAMAS, G36, Desert Eagle, lever-action rifles, M67 and M18 grenades, and bayonets you can fix. Guns have real automatic rates, several magazine sizes (drums, 100-round mags) and mixed ammo types. It is still real-world guns set around 1993, not sci-fi.

**Checked:** mod ids and requirements come from each `mod.info` (Marz requires only `SWMG`; Hot Brass is NOT required and is left out). None of Marz's listed incompatible mods (`RAF`, `VFExpansion*`, `MarzGuns`) are in the preset. I scanned every installed mod for the reload, rack and magazine functions Gunworks and Marz change: only CleanUI touches one (it rewrites `doMagazineMenu`), and Marz wraps whatever is there and loads after CleanUI in the preset, so both apply. N.W.M.F. Weaponry is melee only, All Shots Fired and MSXBow only add XP and hit hooks. Marz inserts its loot as `MarzGuns.*_Spawner` items, which Empire Stockpiles already recognises (test added). Ammo Maker has a built-in Marz table.

**Left out on purpose:** US Military Grenades (`Explosives`: grenades, claymores, mines, flashbangs). Marz and Heavy Ordnance already bring grenades and launchers, and a second explosives mod is the likeliest thing to clash. It can come back after the first clean load. Also out: Z'Ware flamethrowers (untested on 42.22.2 and fire can burn the base) and Guns of Tien (more ammo types, realism). Guns of '93 and its ammo-drop add-on stay installed on the PC as a fallback until Marz has been played; unsubscribe them after.

## Where the guns and ammo are (27 Nov, your call: stockpiles where it makes sense, still hard, still fun)

You asked for fun guns, mods and vehicles, with ammo piled up in the places that would really have it. Guns of Marz is in the pack (it adds the guns, the ammo calibres and its own spots for them: gun stores, police, army and army surplus, pawn shops, garages and hunters' lockers, and its zombies carry guns by outfit). The mistake was my global "rare" dial, which squeezed gun stores and armories as hard as a random shelf. So the dial is back at normal and a new small mod, **Empire Stockpiles** (`EmpireStockpiles/`), decides where the supply sits. It only edits vanilla loot lists once while the game loads (no events at runtime, no per-tick cost), and every list name was checked against vanilla 42.22.2.

| Place | What changes | Roughly |
|---|---|---|
| Gun stores (counter, shelves, cases, mag racks), pawn shops | more rolls on the ammo and gun lists | ammo x2.5, guns x1.5: about two and a half times what vanilla puts on the ammo shelves, across ten calibres |
| Police stations and evidence rooms | more rolls on ammo, guns, evidence | ammo x3, guns x2, evidence x3 |
| Army storage, hangars, surplus | more rolls on ammo, guns, ammo boxes | ammo x3, guns x2, boxes x2 |
| Louisville port | its warehouse and cargo rooms had **no** vanilla loot table, only generic crate junk. Cargo rooms now use a warehouse copy where each container has a 12 percent chance of an army ammo shipment, 8 percent gun-store ammo, 4 percent army guns, 4 percent police ammo. The port's army hangar and gun-store back room borrow the vanilla army-storage and gun-store-storage tables | about 100 cargo rooms, 8 hangar rooms and 2 gun back rooms (counted from the port map files) |
| Homes | gun and ammo entries already in the bedroom, closet, wardrobe, garage and hunting-locker lists are 1.5 to 2 times likelier, and those spots get the odd box of ammo (9mm, .38, .45, shotgun shells, .308, .30-30) at 0.2 to 5 percent per roll | "sometimes in people's homes" |

Everything else (random houses, shops, streets) stays at the normal dial, and zombies only carry ammo if they were armed outfits, so the open world is still tight. All numbers are at the top of `EmpireStockpiles.lua` if it feels too rich or too poor. A mock test runs the mod against the real vanilla loot tables (19 checks, `tests/chores/stockpiles_test.lua`). **Not tested in the game yet:** the first thing to check is the line `[EmpireStockpiles] applied: rolls on 19 lists, ... 3 port rooms` in `console.txt`, then open the first gun store and the port.

## Looking through base storage (27 Nov, your call: no opening chests one by one)

- **Proximity Inventory is back in the pack** (`ProximityInventory`, 178th mod). It adds one "Proximity" tab to the loot window that lists everything in the containers around you. I had cut it for cost (it rebuilds that list on every refresh, so it gets slower with thousands of items nearby), which was the wrong trade for how you play.
- It sees what the loot window sees (the containers next to you), not the whole base. For the whole base: **Numpad 2** (or right-click inventory, "Find item in base...") types a name and lights up every chest holding it, within 14 tiles, all floors.
- EmpireSortAll does not read the loot window, so the two do not collide. If a big base makes the Proximity tab stutter, switch the mod off in the Mods screen and rely on Numpad 2 plus auto-sort.

## What the check found (so you do not have to)

- Every required mod is in the pack, and every mod loads after the mods it needs (six were in the wrong order and are fixed).
- **Tank Water is cut**: its own `mod.info` says it is incompatible with Starlit Library, which two other mods in the pack need, so the game could not enable both.
- EmpireCommand (the Knox roster window) is out: Knox Survivors is cut.
- Every mod has a version folder that matches 42.22.2 (including the Neat mods, which shipped a 42.22 folder).
- Old `EmpireStable.txt` and `EmpireLean.txt` in `Zomboid\mods` are the pre-audit presets (they still include Knox). Do not use them.

## First play session

1. New Game > Mods: pick preset `EmpirePlay` and check that the list shows Proximity Inventory and Guns of Marz (the script rewrites the game's own saved copy of the preset, `Zomboid\Lua\pz_modlist_settings.cfg`, which is what that screen reads; on 27 Nov that copy was stale and a world got the old guns and no Proximity Inventory). Sandbox: pick preset `EmpirePlay`. The NPC and trait settings are already in that preset (written by the script from `docs/presets/EmpirePlay-mod-options.cfg`): no hostile bandits, at most 12 crew per player (the mod default is 30), no self-evolving traits. Raise the crew cap once the frame rate is known.
2. Once in the game press **Numpad 9** and read the `[EmpireTest]` lines in `Zomboid\console.txt`. Any `FAIL` names the Empire feature that did not wire up on 42.22.2.
3. After a session, search `console.txt` for `[EmpireAutoChores] auto-sort took`. Over about 250 ms means the base sort is too heavy: say so.
4. Frame rate: if it is bad, switch the mod list to `EmpireB42-22-lean` on a new save and compare. The bake-off steps are in `PLAYTHROUGH-B42.22.md`.

## Not tested

Nothing here has been run in the real game: the preset has never been loaded, the auto-chores have only mock tests, and the mods marked TEST are plausible but unmeasured on 42.22.2. Expect to cut a few after the first sessions; the console log names the ones that throw.
