# Empire PZ suite audit (26 Nov 2026)

Scope: repo `/home/zenan-wu/work/empire-pz-mods` (HEAD 54cf9c2 plus uncommitted work, see 0.2), handoff `pc-data/empire-pz-handoff.md` (24 Jun 2026), `pc-data/EMPIRE_LEAN_PACK.md`.
Request this serves (King, 26 Nov 2026): "i love empire building but dont like the sorting and small things".
Nothing was run in game. Line numbers are from the working tree at 22:18 AEDT on 26 Nov; "~" means approximate.

## 0. Read this first

0.1 Vanilla B42.22.2 Lua IS on this machine: `/tmp/claude-1000/-home-zenan-wu-work/2b984375-6eb0-477a-93e8-a7fd33ca296a/scratchpad/vanilla-42.22.2/lua/{client,server,shared}`. Section F cites real lines from it (call it `VAN/`). Grep it before using any API.

0.2 Someone is already building the first two candidates in the working tree (uncommitted, written 22:17):
- NEW `EmpireQoL/42/media/lua/client/13_AutoChores.lua` (188 lines): one `Events.EveryTenMinutes` beat; auto corpse vacuum plus auto sort when `EmpireBases.activeBase(player)` is non-nil; Numpad 5 master switch saved in player ModData.
- MODIFIED `EmpireSortAll_Client.lua:2383-2395` adds `EmpireSortAll.run(player)` (smartSort + consolidateTypes + cache invalidate + UI refresh). `EmpireSortAll_UIRefresh.lua:47-49` adds `EmpireSortAll.refreshUI()`.
- MODIFIED `12_Vacuum.lua` exports `EmpireQoL_Vacuum(opts)` with `opts.auto` (silent) returning `grabbed, full`.
- MODIFIED `02_MenuWidthCache.lua` (icon-aware width formula for 42.22) and `49_AutoTest.lua` (`ISReloadManager.startReloadFromUi` moved to optional).
Candidates D1 and D3 therefore need hardening, not a start from zero. My notes on 13_AutoChores are in D1 and D3.

0.3 Four facts that change the design brief:
1. `Events.OnContainerUpdate` is NOT an "items changed" or "window closed" signal. Vanilla fires it only for world containers appearing/disappearing (campfire, BBQ propane, vehicle door open/close, item break, moveables): `VAN/client/ISUI/ISInventoryPage.lua:2154` just sets `renderDirty`. It carries no container. Do not hang auto-sort on it. Usable signals are in D (EveryTenMinutes, OnExitVehicle, `OnRefreshInventoryWindowContainers` stage "end", wraps of `ISInventoryPage:close` / `ISInventoryTransferAction`).
2. B42.22 removed the old stat getters on `Stats`. Vanilla reads `player:getStats():get(CharacterStat.HUNGER)` (and THIRST, PAIN, BOREDOM, FATIGUE, ENDURANCE...); `getHunger()/getThirst()/getPain()` on stats no longer appear anywhere in `VAN/`. The disabled `9_AutoFeed`, `2_AutoMedicate`, `5_BoredomKiller` call `stats:getHunger()`, `getThirst()`, `getPain()` and would silently no-op under pcall. Any revival must be rewritten, not just renamed back. `getNumVisibleZombies/getNumChasingZombies/getNumVeryCloseZombies` are still valid (`VAN/client/ISUI/ISWorldObjectContextMenu.lua:1036`).
3. `ISCraftAction` still exists (`VAN/shared/TimedActions/ISCraftAction.lua`) and still handles item-menu recipes such as can opening (`ISInventoryPaneContextMenu.lua:3488, 3546`). The crafting window uses `ISHandcraftAction` (`VAN/shared/Entity/TimedActions/ISHandcraftAction.lua`, `performRecipe` :225). Any "instant craft" revival must hook both.
4. Vanilla farming already keeps a plant registry (`CFarmingSystem.instance`, `SFarmingSystem.instance:getLuaObjectAt/OnSquare`, `VAN/client/Farming/CFarmingSystem.lua`, `CPlantGlobalObject:canHarvest` :30). An auto-farm needs no tile scan. Unverified: the enumeration method (`getLuaObjectCount/getLuaObjectByIndex` on the Java base class; grep found no Lua caller, check at runtime).

---

## A. King's pain points and preferences (verbatim, short)

Sources: [REQ] this task, 26 Nov 2026. [HO] handoff 24 Jun 2026 (sessions cont 1-8). [GIT] commit messages 2-3 Jul 2026 (they relay King's calls). Much of [HO] is Claude's paraphrase of King; items in quote marks are King's own words as the handoff recorded them, the rest are marked (paraphrase).

**Sorting / inventory**
- [REQ] "i love empire building but dont like the sorting and small things"
- [HO 24 Jun, supply run] "dont send that shit to my inventory"
- [HO 24 Jun, armour pack] (paraphrase) Brita armour (549 clothing + 101 vests) fell into Misc/Bags; King wanted it filed as Clothing.
- [GIT 99bd4ca, 2 Jul] "remove worn-bag combat-kit gate per King": random weapons, medical, armour in worn bags file to base like any loot. Only equipped/attached/favourite and matching loadout ammo stay on him.
- [HO] (paraphrase) F9 yanked the working battery out of the ISA solar box; excluded containers must be left alone.
- [GIT ce919d2/ebfe8e9, 2-3 Jul] compost bin black hole and NaN weights: King saw negative storage in the UI.
- [GIT 2a1f83c, 2 Jul] "declutter item right-click per King": removed "Find item in base" and the mag/ammo finder options; "Numpad 2 prompt is the entry".

**Base logistics (build/craft from storage)**
- [HO] (paraphrase) the whole "pull from base" chain exists because the crafting window only saw worn bags and open loot windows.
- [GIT 8a88544, 2 Jul] "King diagnosed the transfer gap correctly": materials display from base shelves, but the action needs them on him. Led to the quartermaster (44).
- [GIT 33c5330] King's crafting/building UIs are the "Neat Rocco suite" (Neat Building, Neat Crafting).

**Vehicles**
- [HO] (paraphrase) parked car lights drained the battery; fixed in a disabled mod (4_AutoEngineOff).
- [GIT 984459d..3ae1f83, 2-3 Jul] King kept hitting "one part at a time" and "red parts unrepairable"; Quick repair, Quick replace and FIX vehicle exist because of it.
- [GIT f1570b3] "the repair/replace split is game taxonomy leaking into UX".

**Crafting / building**
- [HO 24 Jun] (paraphrase) ammo crafting "realistic but grinds forever"; wanted action time cut for all crafting and 300 ammo not to be 300 long actions.
- [HO] (paraphrase) looting = "too many slow mini-actions"; make the result just happen.

**Survival chores**
- [HO] (paraphrase) eating was "inconsistent" when only canned food (can opener sat on a shelf). Food and drink should just work.
- [HO] (paraphrase) the "are you sure you want to sleep" prompt is removed (28_NoSleepConfirm, active).
- [HO] (paraphrase) "still can't walk to far actions / can't sleep": root was ISTimedActionQueue wiping the whole queue when one action went bugged (Arsenal reload spam). Fixed by the disabled 0_QueueGuard.

**NPCs (B41 era, all inactive on B42)**
- [HO] (paraphrase) survivors must use OUR supplies, not spawned vanilla kit.
- [HO cont 7] (paraphrase) King called a spawn-on-demand command a cheat that breaks immersion: "Whole point = immersive empire building, not cheats." Culling survivors counts as the same crime.
- [HO] (paraphrase) no floating labels; use SSC's existing Page-Up table.
- [HO cont 8] "14 ran fine before, 40% shouldn't make those SAME 14 lag" (his critique, which forced a real measurement).

**Performance (the dominant theme)**
- [HO 24 Jun] "FPS 90 -> 20, game unplayable" (cause: Claude had raised survivor spawns).
- [HO] right-click lag: world menu ~880-920 options, 680-1928 ms to build, bulk in inventory recursion plus build/craft submenus.
- [HO] post-smelt lag from the craft window re-validating recipes against every container in radius (RADIUS cut 20 -> 10 -> 6).
- [PLAYTHROUGH-B42.22 s3] 16 GB, Ryzen 5 3600, RTX 3060; "Performance comes first in every choice below".
- Standing house style in the handoff: "All my lua is heavily pcall-guarded so a bad call fails silent". Side effect: silent failure is how dead code stayed unnoticed (C.1 weakness 7).

**UI clutter**
- [GIT 8002ba2, 2 Jul] "so many things in there" (two base-marker menus; one removed).
- [GIT 0d2337d, 2 Jul] EmpireZones "MINIMAL menu per King": auto-detect / patch 5x5 / trim / show-hide / delete only.
- [GIT 2a1f83c] item right-click decluttered (above).

**Keybinds**
- Active: Numpad 2 find, 3 sort, 7 vacuum, 8 top-off mags, 9 self-test. [README]
- [HO] (paraphrase) Logitech thumb buttons send F6/F7 (1_MouseButtons, disabled): F6 toggled 1x/3x speed.

**Farming, comms style**
- No King complaint about farming in the sources; 14_AutoFarm was built unprompted.
- [HO] style: "Bottom line first. Short sentences. Decisive — one answer, not a menu" and "Tell me what it does for the empire (outcome), not mechanism."
- [HO] want: "Keep making this playthrough super enjoyable / low-grind."

**Doctrine for the implementer (from King)**: no cheats or magic systems; automation should behave like a competent crew member (fetch from base, real items moved, never spawned). Realism pushback on auto-recovery: field deaths stay on the corpse.

---

## B. Catalogue of every feature

Legend: ACTIVE = loads on B42.22 (plain .lua in a `42/` folder). OFF = `.off`/`.disabled`. BAK = `.bak*` history copy, ignore. Reasons for OFF are NOT recorded in commit messages (baseline commit 113c7c7 has no body); the reasons below are inferred from code comments or from the B41 to B42 API change and marked (inferred).

### B.1 EmpireQoL (`EmpireQoL/42/media/lua/client/`)

| File | What it does | Status |
|---|---|---|
| 02_MenuWidthCache | Replaces `ISContextMenu:calcWidth` with a cached measurement; kills N^2 string measuring in huge menus. Tree adds the 42.22 icon-aware formula. | ACTIVE (modified, uncommitted) |
| 12_Vacuum | Numpad7. Loots every corpse in range into the WORN BACK BAG, value-first, `MAX_ITEMS=250`; refuses with zombies near. Header still says F1. Tree exports `EmpireQoL_Vacuum(opts)`. | ACTIVE |
| 13_AutoChores | NEW, uncommitted. EveryTenMinutes auto vacuum + auto sort at base. | WIP in tree |
| 19_FindItem | Numpad2 (header says F11): prompt, scan every storage in radius, highlight containers. Has a per-frame `OnTick` that only checks `clearAt` (:463). | ACTIVE |
| 28_NoSleepConfirm | Skips the sleep confirm modal | ACTIVE |
| 29_BaseRegistry | `EmpireBases`: persisted base list, painted-zone base, KS/SSC seeding, `activeBase`, `scanBounds`, `vehicleNearBase` | ACTIVE |
| 31_BaseCache | `EmpireBaseCache`: item counts per base container for craft/build windows; event-invalidated | ACTIVE |
| 35_ReloadFromGear | Reload using mags in worn rigs/bags; guards the missing `ISReloadManager.startReloadFromUi` (absent in 42.22.2) | ACTIVE |
| 37_DeleteItem | Right-click delete item/stack/selection with confirm | ACTIVE |
| 38_RemoveSafe | Right-click safe -> disassemble for scrap | ACTIVE |
| 39_TopOffMags | Numpad8: fills empty/partial mags on body from loose rounds | ACTIVE |
| 40_RoofPlumbing | Links sinks to any roof rain collector in the building; ModData registry + `EveryTenMinutes` pump (:210) | ACTIVE; the best low-cost pattern in the suite |
| 41_VehicleUnstick | Right-click vehicle -> unstick | ACTIVE |
| 44_CraftFromBase | Quartermaster: shims on Neat Building/Crafting, fetch tools and materials from base into player before build/craft click; exports `EmpireQoL_BaseContainers`, `EmpireQoL_FetchForRecipe` (ten iterations of history) | ACTIVE |
| 45_MechanicFromBase | Same for the mechanics window and tsarslib/ATA tuning (`ISVehicleTuning2` shims) | ACTIVE |
| 46_M998PartCompat | Converter for KI5 M998 double-load item vintages | ACTIVE; "delete when KI5 cleans root". Unneeded on the recommended pack (PLAYTHROUGH says avoid Papa_Chad M998, use KI5's) |
| 47_QuickRepair | Right-click vehicle -> repair every damaged part from base stock, multi-pass, VRO integration | ACTIVE; needs a real vehicle test on 42.22 |
| 48_QuickReplace | Right-click vehicle -> swap wrecked/missing parts for best spares; "FIX vehicle" chains 48 then 47 | ACTIVE |
| 49_AutoTest | OnGameStart and Numpad9 self-test; its T1b list is the vanilla symbol reading list | ACTIVE |

OFF in EmpireQoL (what it did, why off, revive?):

| File | Did | Off because | Revive? |
|---|---|---|---|
| 0_QueueGuard | Replaces `ISTimedActionQueue:onCompleted/tick` so a bugged action is dropped instead of wiping the queue | Written for Arsenal GunFighter reload spam; verified working 24 Jun (inferred: GunFighter not in the new pack) | Conditional: only if console shows "bugged action, cleared queue". Anchors still exist (`VAN/client/TimedActions/ISTimedActionQueue.lua:60, 115`) |
| 1_MouseButtons | F6/F7 thumb buttons: speed toggle | (inferred) personal keybind | Safe, trivial; verify the game-speed API |
| 2_AutoMedicate | auto bandage/painkiller/disinfect, OnTick | B41 getters (`getPain`) dead in 42.22 | Rewrite on `CharacterStat.PAIN`, event-driven; immersion check |
| 3_FuelWarning | warn below 25% fuel, OnTick | (inferred) per-frame, low value | Safe if moved to EveryTenMinutes |
| 4_AutoEngineOff | OnExitVehicle: engine off + headlights off | (inferred) EmpireLoot now auto-starts on enter | **Revive: safest.** Events only. Anchors `VAN/client/Vehicles/TimedActions/ISExitVehicle.lua:62`, `server/Vehicles/VehicleCommands.lua:73` |
| 5_BoredomKiller | auto read book / watch TV | B41 getters | Low value, skip |
| 6_AutoFastForward | speeds time during timed actions, OnTick | per-frame; speed hack | No |
| 7_FixZombieHealth | patch for third-party "Display Zombie Health" | third-party | Only if that mod is in the pack |
| 8_FastTravel | drive boost/time skip, OnTick + key | per-frame, cheat-ish | No |
| 9_AutoFeed (v7, 546 lines) | keeps hunger/thirst topped up from carried and nearby food, can opening, bag-to-main moves | OnTick every ~1 s, B41 getters | **Revive as a thin rewrite** (D4); reuse its can-opener path (`ISInventoryPaneContextMenu.OnCraft`) |
| 10_BarricadeHammerFix | patch for SSC barricade | SSC only | No |
| 11_LootRange | widen loot panel to 5x5 via OnRefreshInventoryWindowContainers | (inferred) superseded by the base-wide quartermaster; B42 loot window restructured | No |
| 13_Reach | cheat: reach any container | cheat | No (King: no cheats) |
| 14_AutoFarm | OnTick every 150 ticks; harvest + water plants within 8 tiles using a held water source | per-frame scan; B42 farming rewrite; farm zone never read | Rewrite on the vanilla plant registry (D5) |
| 15_SmartBuild (+v3/v4 bak), 24_SmartCraft, 32_BuildFromBase, 33_CraftN, 25_CraftBatchCap | earlier "build/craft from base" generations; SmartCraft RADIUS 20 -> 10 -> 6 because validation cost scaled with container count | Superseded by the 44 quartermaster | No |
| 16_LootFocus | stop the loot panel sticking to an emptied container | (inferred) minor | Maybe; small annoyance fix |
| 17_NoMoveToContainer | strip vanilla "Move to" menu items | declutter | Safe if King wants the menu thinner |
| 20_SurvivorCap | SSC spawn sandbox tuning | SSC/B41 | No |
| 22_Housekeeping | tool return (stow tools; disabled inside, "was yanking sledgehammers"), junk drop | OnTick, misbehaved | Garbage-tidy half could be an event after eating; low value |
| 23_AmmoRun | right-click gun: gather matching mags/rounds from nearby storage | nil-call spam (fixed in .bak_nilfix) | **Revive as pre-trip restock** (D7); same idea as `EmpireQoL_FetchForRecipe` |
| 26_FastCraft / 34_FastCraftPlus / 27_InstantActions | wrap `ISCraftAction:new` and `ISInventoryTransferAction/ISGrabItemAction:new` to force `maxTime=1` | (inferred) King later wanted direct moves; the craft window uses `ISHandcraftAction` | Zero per-frame cost; retarget to `ISHandcraftAction` and keep `ISCraftAction`. Taste call: instant actions are mildly cheaty |
| 30_BuildMenu, 36_GrabN, 97_MenuTrim, 97_BuildMenuNilGuard | menu/UI helpers; MenuTrim strips heavy third-party builders (Hydrocraft, CheatMenu) | third-party specific | MenuTrim only if menu bloat returns (~900 options) |
| 39_WalkThrough.lua.disabled, 97_WalkTrace, 99_SleepDebug, 90/93/95/98/99 profilers, 92_PathTimer, 96_LootRefreshTimer | diagnostics | served their purpose | No |

### B.2 EmpireSortAll (`EmpireSortAll/42/media/lua/{client,shared}`)
- `EmpireSortAll_Client.lua` v19.11 (2395 lines in tree): Numpad3 smart sort + consolidate; context menus: tag a container to a category, PRIMARY home, "Keep this bag", transfer vehicle to base. ACTIVE. Design in C.
- `EmpireSortAll_Config.lua`: `isExcludedContainer` (ISA solar box via accept-function "ISA_Batteries"), `isNeverMove` (TMC carts). ACTIVE. `fulltypeBucket` is dead code (never called).
- `EmpireSortAll_UIRefresh.lua`: 2-tick countdown then `refreshBackpacks()` + `inventoryPane:refreshContainer()`. ACTIVE (modified).
- `shared/EmpireSortAll_Shared.lua`: stale B41 category map, unused. Dead.

### B.3 Other B42 mods
| Mod | What | Status / notes |
|---|---|---|
| EmpireZones | Paint base/farm/guard/workshop/storage zones, persisted in `ModData "EmpireZones"`; auto-detect by flood fill (`floodDetect` `EmpireZones_Paint.lua:63`, `MAX_FILL=6000`); menu is minimal by King's call | ACTIVE. Only the "base" type is ever read (by 29_BaseRegistry). farm/guard/workshop/storage zones have no consumer |
| EmpireProduction | Container becomes a production node; recipes are data; accrual over game hours (`EP.nowHours`, `EP.resolve` `EmpireProd_Core.lua:85`, `EP.status` :121); state on the container object's ModData | ACTIVE. No registry: nodes resolve only through the right-click menu (`EmpireProd_Menu.lua:60 onFill`) |
| EmpireLoot | Auto engine start on vehicle enter; the one-tick handler is registered only between enter and next tick (`EmpireLoot.lua:29, 50`) | ACTIVE. Good pattern. Loot filter and trailer transfer were removed in B42 |
| EmpireAmmoDrop | `OnZombieDead` ammo drops (`EmpireAmmoDrop.lua:183-184`) | ACTIVE |
| EmpireEatAll | Eat click eats the whole item | ACTIVE |
| EmpireCommand, EmpireKSTune | Knox Survivors roster window and sandbox re-apply | Variant B (Knox) only |
| EmpireRFGunFix | Registers two Real Firearms guns | Only with Real Firearms; may be redundant after its update #52 |
| EmpireCraftFix | wraps `ISCraftingUI.new`, changes nothing, no `42/` folder | Do not enable |
| EmpireNPC (settler roles, garrison, quartermaster equip, recovery, supply run, cull strays), EmpirePerf, EmpireAmmo (recipes `.off`) | B41 era, SSC based | Do not enable on B42. EmpireNPC holds the best "equip from armory" and "recovery loop" ideas for a future Bandits/Knox layer |

### B.4 Third-party overlap to watch (PLAYTHROUGH s5)
Better Sorting (data-only, test with SortAll), Proximity Inventory (overlaps the quartermaster), Farming Zone (overlaps EmpireZones farm type). Neat Building/Crafting/Inventory Tetris are on the PLAYTHROUGH "Avoid" list because they conflict with our crafting and sorting, yet the quartermaster shims (44/45) target the Neat panels. Settle this before building more on 44.

---

## C. Current design: sorting and the registries

### C.1 EmpireSortAll pipeline (all `EmpireSortAll_Client.lua`; local functions, only `EmpireSortAll.run` is exported and only in the tree)
- **Trigger**: Numpad3 `onKeyPressed` :2369 -> `pcall(smartSort)`, `pcall(consolidateTypes)`, `EmpireBaseCache.invalidate()`; UI refresh in `_UIRefresh.lua`. Right-click vehicle "transfer to base" -> `onTransferVehicleToBase` :2255 (calls `smartSort(player,{vehicle=veh})`). Tree: `EmpireSortAll.run` :2387 repeats the Numpad3 body for callers.
- **Scan**: `collectStorages` :600. Bounds = `EmpireBases.scanBounds(player, RADIUS=12)` (the whole base box when standing in a base, else 12 tiles), clamped to `SS_MAX_SPAN=64`. Triple loop z,x,y over `cell:getGridSquare`, per object `getContainerCount/getContainerByIndex` (multi-compartment fridges), plus placed world-inventory cans and vehicle part containers (`vehicleStorageContainers` :831). Cached 20 s keyed on the box (`SS_CACHE_TTL_MS` :595). `isExcludedContainer` filters inside the scan.
- **Floor items**: `collectFloorItems` :783 (same radius, every floor).
- **Categorise**: `categoryOfRaw` :204 -> `categoryOf` :376 with a per-run `_catCache` (:375, reset at :851). Input is the vanilla `DisplayCategory` mapped by `CAT_MAP` :38 to ~37 buckets (the `VALID` set ~:509): Perishable, Frozen, DryFood, Water, Drinks, Alcohol, Cooking, Compost, Gun, Weapon, Ammo, AmmoVehicle, GunParts, Explosives, Armor, Medical, Tools, VehicleParts, Materials, Chemicals, Electronics, Light, Gardening, Fishing, Trapping, Camping, Animals, AnimalParts, Books, SkillBooks, Entertainment, Clothing, Accessory, Bags, Furniture, Household, Misc. Food splits Perishable/DryFood by spoilage; Frozen vs fridge by `isFreezerFood` :140; wearables (Clothing instance or body location) catch armour packs.
- **Destinations**, in priority: PRIMARY-marked container for the category (`ModData "EmpireStoragePrimary"`) > tagged container (`ModData "EmpireStorageTags"`, keyed by world position + type, not by object, so menu and scan agree) > type affinity (`TYPE_AFFINITY`, `affinityOf` :460) > room affinity (`ROOM_CATS` ~:478: kitchen, pantry, bedroom, bathroom, garage, shed, medical, office, library) > "general" untagged boxes round-robin (`homeFor` :1025) > emergency tier (any container with room except cold-strict and compost). Spread vs fill-one-first policy: `byFreeDesc` :1046, `byFillFirst` :1055 (ammo fills one box first).
- **Passes inside `smartSort`** (:846 to ~1960): plan moves ~1120; apply moves ~1400 (`placeInto`: `dest:addItem(item); fromCont:Remove(item)` ~1430; direct, no timed action); carried sweep `addCarried` ~1265 (worn bags and body, skipping favourite/equipped/hotbar via `isProtected` :387, "keep bag" ModData `empireKeepBag`, and loadout ammo matching held guns); eviction (items in the wrong tagged home); shed; magnet ~1200 (pull tagged categories home); PASS A :1501 rot to compost; PASS B :1650 floor loot to homes; placed-can restock :1755; overflow ~1889.
- **Then `consolidateTypes`** :1969: stacks identical items; a second full pass over the same containers.
- **Cost model**: synchronous, one frame, zero timed actions. Cost = scan (cached) + O(items) classification + per-move `spillCands` (E1). On a big base this is a visible hitch (not measured; commit history shows only correctness fixes). Auto-triggering moves that hitch to unpredictable moments.
- **Refresh after moves**: direct moves do not update the UI; `EmpireSortAll.refreshUI()` arms a 2-tick countdown, then `refreshBackpacks` + `refreshContainer`.
- **Weaknesses**
  1. No event trigger and no incremental mode: every run sweeps the whole base, twice (smartSort + consolidate).
  2. `spillCands`/`freeOf` re-sort with Java calls per move (E1).
  3. "In a base" = bounding rectangle of ALL painted base tiles (`getEmpireZoneBase`), so two distant painted areas make everything between them "base".
  4. Vehicle unload is manual (right-click) and falls back to a street sweep if no base is registered.
  5. Stale cache window: `EmpireBaseCache.invalidate()` runs only after our sorts and wrapped transfers; manual drags between containers are caught only by the 5 min safety refresh.
  6. `fulltypeBucket` and `shared/EmpireSortAll_Shared.lua` are dead.
  7. Silent-pcall style hides regressions (the `isExcludedContainer` helpers were dead code for a whole version in June).
  8. Known fragile spots with commit evidence: compost-bin weight cache sentinel -1.0 (ce919d2), NaN weights crash the `%f` formatter (ebfe8e9).

### C.2 Entry points for an automatic mode

| Purpose | Call | File:line |
|---|---|---|
| Full sort + consolidate (Numpad3) | `EmpireSortAll.run(player)` | `EmpireSortAll_Client.lua:2387` (tree only) |
| Vehicle unload to base | `onTransferVehicleToBase(player, veh)` (local; export or wrap) and `smartSort(player,{vehicle=veh})` | :2255, :846 |
| Container scan | `collectStorages(player, boundsOverride)` | :600 |
| Refile only what I carry | none exists. Needs `opts.carriedOnly` that skips eviction/magnet/rot/floor/consolidate; entry is the carried sweep ~1265 | smartSort :846 |
| Classify one item | `categoryOf(item)` (local) | :376 |
| UI refresh | `EmpireSortAll.refreshUI()` | `_UIRefresh.lua:49` (tree only) |
| Corpse vacuum | `EmpireQoL_Vacuum({auto=true})` -> `grabbed, full` | `12_Vacuum.lua:~194` (tree only) |
| Top off mags | local in `39_TopOffMags.lua`; hook is the Numpad8 `onKeyPressed` :206; export needed | |
| Fetch from base into player | `EmpireQoL_FetchForRecipe(...)`, `EmpireQoL_BaseContainers(player)` | `44_CraftFromBase.lua:60`, fetch ~203 |
| Which base am I in | `EmpireBases.activeBase / inBase / scanBounds / vehicleNearBase(veh,n)` | `29_BaseRegistry.lua:161 / 181 / 219 / 257` |
| Item counts in base | `EmpireBaseCache.get / count / containersFor / invalidate / noteConsumed` | `31_BaseCache.lua:123 / 139 / 146 / 153 / 162` |

### C.3 EmpireBases (29_BaseRegistry.lua) and EmpireBaseCache (31_BaseCache.lua)
- Persists: `ModData.getOrCreate("EmpireBases")` (`store()` :21) holds `list` of `{name,x1,x2,y1,y2,z}`. "Main" is auto-seeded only when the list is empty, from `getEmpireZoneBase()` else SSC (`getSSCBase` :37) else Knox (`getKSBase` :58).
- Read: `activeBase(player)` :161 first computes the LIVE painted base rectangle with `getEmpireZoneBase` :94 (loops EVERY tile of EVERY "base" zone, parses each key, takes min/max) on every call, then falls back to stored rects with `inRect`. `scanBounds` :219 returns box plus z range (`BASEMENT_REACH`, `FLOOR_SPREAD`). `syncKSToOurBase` :189 pushes our base to Knox.
- BaseCache: `enumerate` :31 sweeps the base volume once into per-container item counts; `rebuild` :101; `get(force)` :123 rebuilds when dirty (debounced `MIN_REBUILD_MS=2000`) or older than `REFRESH_MS=300000`; `heartbeat` :193 is registered on EveryOneMinute only if enabled (off). Wraps `ISInventoryTransferAction.perform` (marks dirty) and `ISCraftAction.perform` when present. The craft window calls `get()` per refresh, which calls `activeBaseFor` :117 -> `activeBase` -> the tile loop.

### C.4 EmpireQoL_BaseContainers (44) and the quartermaster
- `EmpireQoL_BaseContainers(player)` :60 returns base containers from the cache, else `proximityContainers` :16 (RADIUS 16, z 0-7, 10 s TTL) when no base is registered. Shims on `NB_BuildingPanel` / `NC_CraftLogicPanel` / `NC_HandCraftPanel` `updateContainers` add them to the windows' lists; click wrappers (`NC_CraftActionPanel.startHandcraft`, `ISBuildIsoEntity.create`, `ISHandcraftAction.performRecipe`) fetch needed items into the player first (instant `addItem/Remove`), because vanilla range-validates source containers at action time and far shelves fail silently.
- Rule that came out of ten iterations: items must be ON the player when the action runs; display-only augmentation is not enough.

### C.5 EmpireZones and EmpireProduction
- EmpireZones: `ModData "EmpireZones"` (`EmpireZones_Core.lua:14`), zones with `type` and `tiles[key]=true` (`parseKey`). API `EmpireZones.all()`, `parseKey`. Paint, auto-detect, trim, patch 5x5, show/hide in `EmpireZones_Paint.lua`. Read only by `EmpireBases.getEmpireZoneBase` (type "base"). There is no helper for "which zone is the player in".
- EmpireProduction: node state lives on the world object `obj:getModData()` (`EmpireProd_Core.lua:86-87, 122`; set/collect/stop in `EmpireProd_Menu.lua:39-66`). Accrual is lazy: `EP.resolve(obj)` converts elapsed game hours into outputs when asked. Only the right-click menu asks, so there is no list of nodes and nothing happens by itself.

---

## D. Ranked automation candidates

Rule for all: no `OnTick`, `OnPlayerUpdate`, `OnRenderTick` or `LoadGridsquare` handler doing scans. Allowed triggers: EveryTenMinutes, EveryOneMinute (cheap guards only), OnExitVehicle/OnEnterVehicle, OnZombieDead (counter only), OnRefreshInventoryWindowContainers stage "end", one-shot timers armed by an event, and wraps of vanilla actions' `perform`. Guard every automation with the 13_AutoChores `busy()` checks and a per-chore failure breaker.

### D1. Auto-sort after a trip (loot comes home filed)
- By hand today: walk to base, press Numpad3, sometimes twice, open windows to verify.
- Trigger: EveryTenMinutes beat with edge detection: "player in base AND carried count grew since last sort (or vacuumed items > 0)". 13_AutoChores already does this (cooldown 3 beats, +5 items).
- Reuse: `EmpireSortAll.run`, `EmpireBases.activeBase`, vacuum counters.
- Vanilla: `ISTimedActionQueue.isPlayerDoingAction`, `Stats:getNumVisibleZombies`, direct `ItemContainer:addItem/Remove` (inside smartSort).
- Perf risk: HIGH as it stands. A whole-base sort is one synchronous frame, and `getEmpireZoneBase` loops all zone tiles per `activeBase` call (fine once per beat, bad per frame). Mitigations in order: (a) add `opts.carriedOnly` and use it for auto runs, leaving the full sort on the key; (b) memoise `freeOf` (E1); (c) run only after N consecutive quiet beats; (d) cache the base rectangle until the zone changes.
- Failure modes: sorts while King is mid-craft with items he carries (only items picked up since the last sort, favourites protected); moves ammo he just loaded (loadout ammo is protected); noise from things moving when he did not ask. Off switch exists (Numpad5).
- Gaps in 13_AutoChores: `carriedCount` counts top-level items in body + back bag only, so loot in webbing/other bags never triggers; `inBase` uses the bounding box; `packFull` is cleared only by a sort.

### D2. Auto-unload vehicle on arrival
- By hand: drive home, park, right-click vehicle, "transfer to base", engine off, lights off.
- Trigger: `Events.OnExitVehicle` (fired at `VAN/client/Vehicles/TimedActions/ISExitVehicle.lua:62`). One shot: if `EmpireBases.vehicleNearBase(veh, n)` (29:257), defer 1-2 ticks, run `smartSort(player,{vehicle=veh})`; also stop engine and headlights (code in `4_AutoEngineOff.lua.off`).
- Reuse: `onTransferVehicleToBase` :2255 (export), `vehicleStorageContainers` :831, 4_AutoEngineOff.
- Vanilla: `IsoPlayer:getVehicle`, `BaseVehicle` part containers, `ISVehicleMenu.onShutOff` (`VAN/client/Vehicles/ISUI/ISVehicleMenu.lua:1178`), `onToggleHeadlights` :1116.
- Perf risk: LOW (one event, one sort).
- Failure: exits to fight; truck parked outside the registered base; sorting the truck's gas cans/ammo into a shelf he wanted in the truck (add a "keep in vehicle" tag or skip containers King tagged).

### D3. Auto corpse loot after a fight
- By hand: Numpad7 near piles.
- Trigger: `OnZombieDead` bumps a counter and timestamp; the EveryTenMinutes beat loots when counter > 0, no zombies visible/chasing, and the pack has room. 13_AutoChores currently calls the vacuum every beat with no kill counter, so it scans corpses even when nothing died.
- Reuse: `EmpireQoL_Vacuum({auto=true})`, `MAX_ITEMS=250`.
- Vanilla: `IsoDeadBody` containers (`corpsesNear` in 12_Vacuum), `OnZombieDead`.
- Perf risk: LOW to MEDIUM; the corpse scan radius is the cost. The counter makes idle free.
- Failure: looting while a second horde approaches; filling the bag with junk then auto-sorting junk into base (value-first filter exists); touching NPC bodies.

### D4. Needs on autopilot (eat, drink, open cans) from base stock
- By hand: eat/drink when moodles show, carry a can opener, walk to a kitchen shelf.
- Trigger: EveryTenMinutes only. Read `stats:get(CharacterStat.HUNGER/THIRST)` (B42 API; scale to verify against `VAN/client/ISUI/ISInventoryPane.lua:1064`). If above threshold and safe/idle, quartermaster-fetch one food item (and the can opener via `ISInventoryPaneContextMenu.OnCraft`), then queue vanilla `ISEatFoodAction` / `ISDrinkFluidAction` (`VAN/shared/TimedActions/`).
- Reuse: 9_AutoFeed.lua.off logic (546 lines) for item choice, can opening, bag-to-main moves; `EmpireQoL_BaseContainers`.
- Perf risk: LOW once off OnTick (the B41 version ran every ~1 s).
- Failure: eats the good stuff (rank by spoilage first, never touch favourites); queue interactions. The QueueGuard history shows queue wipes break walk/sleep, so enqueue via `ISTimedActionQueue.add` only when `isPlayerDoingAction` is false.

### D5. Auto-tend farm (harvest, water) inside a painted farm zone
- By hand: walk rows, harvest, water, replant.
- Trigger: EveryTenMinutes (or on entering a farm zone). Iterate the vanilla plant registry for plants inside the farm zone's tiles; queue `ISHarvestPlantAction` / `ISWaterPlantAction` for ripe/dry ones; drop produce into the nearest storage and let sorting home it.
- Reuse: EmpireZones "farm" type (painted but unread), 14_AutoFarm.lua.off logic, `findWaterSource`.
- Vanilla: `CFarmingSystem.instance`, `CPlantGlobalObject:canHarvest` (:30), `VAN/shared/Farming/TimedActions/ISHarvestPlantAction.lua`, `ISWaterPlantAction.lua:6`, `ISFarmingMenu`.
- Perf risk: MEDIUM unless the registry call is O(plants). Never scan tiles.
- Failure: B42 plant states differ from B41; watering needs a fluid container with water (B42 fluid API). Needs a real-game check. Third-party Farming Zone overlap.

### D6. Production nodes that feed and collect themselves
- By hand: right-click node to start, return to collect, re-feed inputs.
- Trigger: add a registry (copy 40_RoofPlumbing's `REG_KEY` ModData pattern) written when a node is created; EveryTenMinutes iterates it (O(nodes)), calls `EP.resolve`, moves outputs into base storage; optional input restock through the quartermaster fetch.
- Reuse: `EmpireProd_Core.lua` (`resolve`, `status`), RoofPlumbing registry, `EmpireSortAll.run` for homing outputs.
- Vanilla: `ItemContainer` APIs only; item creation via `instanceItem`.
- Perf risk: LOW (registry, lazy accrual).
- Failure: nodes in unloaded chunks (guard null squares, skip); double-counting game hours across sleep (`EP.nowHours` is the single clock); outputs overflowing containers (check `hasRoomFor`).

### D7. Pre-trip loadout restock when leaving base
- By hand: Numpad8 top-off, drag mags/ammo, check reload gear.
- Trigger: edge "was in base last beat, not now" on EveryTenMinutes, or `OnEnterVehicle` when starting from base. One shot: pull matching mags and rounds for carried guns (23_AmmoRun logic), run TopOffMags.
- Reuse: `23_AmmoRun.lua.off`, `39_TopOffMags`, `35_ReloadFromGear`.
- Perf risk: LOW.
- Failure: guns without `MagazineType`; weight overload; King may want to pick his own loadout (taste call).

### D8. Clean-ups that remove clicks without new loops
- Revive 4_AutoEngineOff (events only, part of D2), 16_LootFocus (loot panel sticks to emptied container), 17_NoMoveToContainer (menu declutter). Each is an event or one-time hook.
- Keep 97_MenuTrim off unless the world menu option count returns above ~900.

### D9. Water chores (not started; verify first)
- Auto-fill empty bottles at sinks/rain collectors near base; ties into 40_RoofPlumbing. B42 fluids (`getFluidContainer`, `ISAddFluidFromItemAction`) changed everything here, so API drift risk is high. Do after D1-D6 are verified.

### D10. Not recommended (violates King's doctrine or perf rules)
Spawn buttons, mass culls, teleports, `13_Reach`, per-tick auto-medicate, fast-forward hacks, anything scanning from `LoadGridsquare`.

---

## E. Performance hotspots in our own code

| # | Where | Problem | Fix |
|---|---|---|---|
| E1 | `EmpireSortAll_Client.lua:1039-1062` `freeOf`/`byFreeDesc`/`byFillFirst`; `spillCands` :1093, called per move at :1458, :1477, :1691 | Each call rebuilds candidate lists and `table.sort`s with a comparator that calls `capOf` and Java `getCapacityWeight` (in pcall) on every comparison: O(moves x n log n) Java calls | Memoise `freeOf` per run, invalidate only the two containers a move touched; sort once per category per run |
| E2 | `EmpireSortAll_Client.lua:600-700` `collectStorages` | Triple loop over `getGridSquare` for up to 65 x 65 x zRange squares; 20 s cache keyed on bounds, so any bounds change rescans | Keep; auto mode should reuse the cache and take invalidation from `EmpireBaseCache`/zone changes |
| E3 | `29_BaseRegistry.lua:94-113` `getEmpireZoneBase` | Loops every tile of every base zone and parses keys on every call. Called by `activeBase` :161 (each craft-window refresh via `31_BaseCache.lua:117`, now each beat) and `list()` seeding | Cache bounds with a zone version counter; recompute on paint/trim only |
| E4 | `31_BaseCache.lua:31 enumerate` | Full base-volume sweep to rebuild counts; debounced 2 s, safety 5 min | OK; keep heartbeat off |
| E5 | `44_CraftFromBase.lua:16 proximityContainers` | Radius 16 x z 0-7 scan when no base is registered, 10 s TTL | Register the base so the cache path is used |
| E6 | `19_FindItem.lua:463` `onTick` | Per-frame handler (cheap timestamp check); one of the few left | Replace with a one-shot timer armed on highlight |
| E7 | `12_Vacuum` corpse scan, `MAX_ITEMS=250` | Each run scans corpses in range; auto mode would call it every beat | Kill-count gate (D3) |
| E8 | One-shot `OnTick` installers (`44:453`, `45:554`, `46:143`, `47:529/561`, `48:166`, `EmpireLoot:29`) | Late-install loops must remove themselves | Confirm each calls `Events.OnTick.Remove`; let the self-test assert it |
| E9 | `EmpireSortAll_UIRefresh.lua:45` `OnTick` countdown | Per-frame, trivial | Leave |
| E10 | ~900-option world menu (handoff) | Lag came from third-party menus; the width cache fixed the O(n^2) measuring | Keep 02 active; 97_MenuTrim only if the count returns |
| E11 | Auto-sort hitch (new) | Whole-base sort in one frame at a time King does not choose | `carriedOnly` mode (D1); run only when idle |

---

## F. Vanilla B42.22.2 reading list (all under `VAN/` = `.../scratchpad/vanilla-42.22.2/lua/`)

Read these before writing code; line numbers are from the local copy.
- Inventory UI and refresh: `client/ISUI/ISInventoryPage.lua` (`refreshBackpacks` :1537; refresh events "begin" :1560, "beforeFloor" :1795, "buttonsAdded" :1802, "end" :1906; `close` :720; `OnContainerUpdate` handler :2154; registrations :2212-2214). `client/ISUI/ISInventoryPane.lua` (`refreshContainer` :2039, `transferItemsByWeight` :634, thirst check :1063).
- Moving items: `client/TimedActions/ISInventoryTransferAction.lua` (`isValid` :11, `start` :258, `perform` :477; B42 item transactions via `createItemTransaction` :313 are `isClient()` branches that single player skips). Also `shared/TimedActions/ISTransferAction.lua`, `server/TransactionProcessor.lua`, `client/ISUI/InventoryWindow/Handlers/TransferSameType.lua`. Our direct `addItem/Remove` bypasses all of it: fine in single player, wrong in multiplayer.
- Queue: `client/TimedActions/ISTimedActionQueue.lua` (`onCompleted` :60, `tick` :115, `isPlayerDoingAction` :269).
- Menus we hook: `client/ISUI/ISWorldObjectContextMenu.lua` (`onConfirmSleep` :987, zombie check :1036), `client/ISUI/ISInventoryPaneContextMenu.lua` (`getContainers` :2425, `ISCraftAction:new` call sites :3488, :3546, `onFix`).
- Crafting: `shared/Entity/TimedActions/ISHandcraftAction.lua` (`start` :89, `perform` :177, `performRecipe` :225), `shared/TimedActions/ISCraftAction.lua` (`perform` :73), `server/BuildingObjects/ISBuildIsoEntity.lua`. The T1b list in `EmpireQoL/42/media/lua/client/49_AutoTest.lua` (~:40-70) is the full set of vanilla functions we already depend on; start there.
- Vehicles: `client/Vehicles/ISUI/ISVehicleMenu.lua` (`getVehicleToInteractWith` :244, `onToggleHeadlights` :1116, `onStartEngine` :1166, `onShutOff` :1178, `onEnter` :1374), `client/Vehicles/TimedActions/ISEnterVehicle.lua:79` and `ISExitVehicle.lua:62` (fire `OnEnterVehicle`/`OnExitVehicle`), `shared/Vehicles/TimedActions/*` (refuel, install/uninstall part), `shared/TimedActions/ISFixVehiclePartAction.lua`, `client/Vehicles/ISUI/ISVehicleMechanics.lua`, `server/Vehicles/VehicleCommands.lua:73` (`setHeadlightsOn`).
- Needs: `shared/TimedActions/ISEatFoodAction.lua`, `ISDrinkFluidAction.lua`, `ISDrinkFromBottle.lua`, `ISApplyBandage.lua`; stats API `getStats():get(CharacterStat.X)` (`shared/Foraging/forageSystem.lua:1767`); valid names: ANGER BOREDOM DISCOMFORT ENDURANCE FATIGUE FITNESS FOOD_SICKNESS HUNGER IDLENESS INTOXICATION MORALE NICOTINE_WITHDRAWAL PAIN PANIC POISON SANITY SICKNESS STRESS TEMPERATURE THIRST UNHAPPINESS WETNESS ZOMBIE_FEVER ZOMBIE_INFECTION.
- Farming: `client/Farming/CFarmingSystem.lua`, `CPlantGlobalObject.lua` (`canHarvest` :30), `shared/Farming/TimedActions/ISHarvestPlantAction.lua`, `ISWaterPlantAction.lua`, `ISPlowAction.lua`, `shared/Farming/ISFarmingMenu.lua`. Traps (`STrapSystem.instance:getLuaObjectAt`) and the feeding trough use the same global-object registry pattern.
- Corpses: `shared/TimedActions/ISGrabCorpseAction.lua`, `shared/BodyDragging/corpseStorageCheck.lua`.
- Events we use or may use: `OnGameStart`, `EveryTenMinutes`, `EveryOneMinute`, `OnExitVehicle`, `OnEnterVehicle`, `OnZombieDead`, `OnRefreshInventoryWindowContainers`, `OnFillWorldObjectContextMenu`, `OnFillInventoryObjectContextMenu`, `OnKeyPressed`. Not a sorting trigger: `OnContainerUpdate` (0.3).
- Still unverified; check by grep or the self-test before relying: `ItemPicker.updateOverlaySprite` signature (shelf visuals); `ItemContainer:hasRoomFor/isItemAllowed/getEffectiveCapacity` behaviour in 42.22 (PLAYTHROUGH s6 lists `canItemFit` as a changed signature); `CFarmingSystem` enumeration; B42 fluid APIs for D9.

### F.1 Process notes
- Self-test: Numpad9 after every change; add a check for each vanilla symbol a new feature calls (T1b pattern).
- Evidence culture: commits name console lines and root cause; keep that. Never guess an API (handoff cardinal rule): grep `VAN/` first.
- Patterns to copy: registry + EveryTenMinutes in `40_RoofPlumbing.lua`; one-tick handler in `EmpireLoot.lua:29`; per-run memo `_catCache` in SortAll :375.
