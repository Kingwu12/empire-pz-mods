# Automation jobs D4-D7 + sorter hardening D1 (written 27 Nov 2026)

King (26 Nov 2026): "i love empire building but dont like the sorting and small things".
Candidates and reasoning: `docs/SUITE-AUDIT-2026-11-26.md` section D. This file is what was built from it.

**Nothing here has run in the real game.** Every module has a mock test (`tests/chores/`, fengari, mocked PZ globals) and an in-game self-test block (`49_AutoTest.lua`, Numpad 9). The mock tests check logic, not the engine. See "Untested in game" at the end.

## Rules every job follows (King's doctrine)

- **Performance first.** No `OnTick`, `OnPlayerUpdate`, `OnRenderTick`, `LoadGridsquare` or any per-frame scan. The only triggers are the single 10-minute beat (`Events.EveryTenMinutes`, registered once in `13_AutoChores.lua`) and one one-shot event (`Events.OnEnterVehicle`, restock only).
- **A competent crew member, no cheats.** Real items are moved (`dest:addItem(it); src:Remove(it)`, the quartermaster pattern), nothing is spawned or deleted, and eating, drinking, harvesting and watering go through the vanilla timed actions / entry points.
- **Loot never goes into the body inventory by automation** except where the survivor needs it in hand: food/water/can opener he is about to use, a watering container, spare mags and rounds for the guns he carries.
- **Safe by construction:** every call that can fail is `pcall`ed, every object is existence-checked, a chore that throws 3 beats in a row switches itself off (and says so), and **Numpad 5** switches all of it off and re-arms it.
- **One heavy thing per beat.** A chore returns `true` when it did heavy work (a sort, queued timed actions); the beat ends there.

## The beat (`13_AutoChores.lua`, now a registry)

`EmpireAutoChores.register(name, order, fn, opts)`. `fn(player, ctx)` runs only when the survivor is idle and safe (alive, awake, not driving, no timed action running, no zombie visible/chasing/very close). `ctx = {beat, inBase, justLeft, consumeLeave()}`.

| order | chore | file | when |
|---|---|---|---|
| 10 | needs | `14_AutoNeeds.lua` | anywhere |
| 20 | unload | `13_AutoChores.lua` | after parking at the dock |
| 30 | sort | `13_AutoChores.lua` | in base, carrying new loot |
| 40 | loot | `13_AutoChores.lua` | after a fight |
| 50 | farm | `15_AutoFarm.lua` | in a farm zone |
| 60 | production | `16_AutoProduction.lua` | in base |
| 70 | restock | `17_PreTripRestock.lua` | in base, or just left it |

Shared helpers exported from `13_AutoChores.lua` so the modules carry no copies: `say, busy, zombiesAround, inBase, carriedCount, nowMs, noteLoot, m` (safe method call), `carriedContainers(player)` (body inventory plus worn bags, nested), `baseContainers()`, `fetch(player, item, container)` (move one real item into the body inventory).

## D4. Needs on autopilot (`14_AutoNeeds.lua`)

Eats, drinks and opens cans from carried food and (inside the base) base stock.

- **When:** hunger or thirst at or above 0.20 (`CharacterStat.HUNGER/THIRST`, 0 = fine, 1 = worst). One need per beat. Skipped while the "stuffed" moodle (`FOOD_EATEN`) is level 3+, and while he is walking (unless the need is severe, 0.5+).
- **What he picks:** food closest to spoiling first (`getOffAgeMax - getAge`), cooked before raw, unhappy food last. Never: burnt, rotten, frozen, spices, tainted, favourites, alcohol, anything the game already marks as known poison or dangerous raw.
- **Portion:** a quarter, a half or the whole item, whichever gets him back under 0.05 without waste.
- **Water:** clean bottles first, jugs and buckets only when no bottle is left. Only the fluids `Water` and `CarbonatedWater`.
- **Sealed cans:** uses the item's own opening recipe through `HandcraftLogic`, fetching a can opener (and the can) from base stock when needed.
- **Failure handling:** nothing edible or three tries that did not move the stat: quiet for 6 beats (an hour of game time).
- **Settings:** top of the file (`EAT_AT`, `DRINK_AT`, `SEVERE_AT`, `BACKOFF_BEATS`, `BASE_STOCK`, `BIG_CONTAINER`).
- **Test:** `tests/chores/needs_test.lua`, 48 checks.

## D5. Auto-tend farm (`15_AutoFarm.lua`)

Harvests ripe plants and waters thirsty ones, only inside an Empire **farm zone**.

- **No tile scan.** It walks vanilla's own plant registry (`CFarmingSystem.instance:getLuaObjectCount/ByIndex`, at most `MAX_SCAN` rows per beat) and keeps plants that are inside a farm zone, within `REACH` tiles and on a loaded square.
- **Harvest first, then water**, at most `MAX_TASKS` plants per beat (vanilla `ISFarmingMenu.walkToPlant`, `ISHarvestPlantAction`, `ISWaterPlantAction`). Harvested produce is counted toward the next auto sort.
- **Water:** tainted water first, clean water only from containers of 2 L or more (small drinking bottles are left alone unless `USE_DRINKING_WATER`). The container is fetched from base stock if needed. He equips it for the pour and puts the previous item back. Outdoor plants are skipped while it is raining.
- **Never:** sows, fertilises, sprays, digs or pulls plants.
- **Test:** `tests/chores/farm_test.lua`, 36 checks.

## D6. Production nodes that feed and collect themselves (`16_AutoProduction.lua`)

An EmpireProduction node (right-click a container, Set up production) now keeps itself stocked and emptied.

- **Registry:** `EmpireProd.registry()` (ModData `EmpireProdNodes`, one `"x,y,z"` key per node). Written when a node is set up, removed when it is stopped, and adopted when you open an older node's menu. The chore visits at most 3 nodes per beat, round robin; a key on an unloaded square is skipped, a loaded square with no node is dropped.
- **Feed:** tops each input up to 6 game hours of production from base storage (max 40 items per node per beat, split across inputs, never more than the container has room for).
- **Collect:** when the node holds 20+ of its output (or half its buffer, or after 12 beats of waiting), `EmpireSortAll.run(player, {carriedOnly=true, noCarried=true, sources={node}, itemFilter=...})` files that output into the right base containers.
- **Node containers are excluded** from the base index and the sorter (`EmpireSortConfig.isExcludedContainer`), so the sorter never pulls a node's inputs back out.
- **Per node switch:** right-click the node, "Auto-feed: ON/OFF" (`node.manual`).
- **Test:** `tests/chores/production_test.lua`, 34 checks (loads the real `EmpireProd_Core.lua` and `EmpireSortAll_Config.lua`).

## D7. Pre-trip restock (`17_PreTripRestock.lua`)

Before he heads out, the guns he carries are stocked from base storage.

- **Which guns:** ranged weapons in his hands or on his hotbar. This is exactly the set the sorter already treats as loadout, so the sorter will not file the restocked ammo straight back (no ping-pong).
- **Targets:** 3 spare magazines per magazine type (fullest first) and 40 loose rounds per ammo type, counted over everything he carries (worn bags included). Never takes favourites. Stops above 90% of carry weight. An item the base has none of is not looked for again for 6 beats. At most 150 items per restock.
- **Three moments:** (1) the beat while he is in the base (acts only if a gun is short), then the vanilla mag-loading actions through `EmpireQoL_TopOffMags(player, {quiet=true})`; (2) the moment he boards a vehicle inside the base (`OnEnterVehicle`, instant moves only); (3) a beat after he walked out, if he is still within 30 tiles of the base and the last base index (`EmpireBaseCache.peek()`) still points at loaded containers.
- **Supporting changes:** `EmpireBaseCache.peek()`; `39_TopOffMags.lua` takes `opts.quiet` and is exported as `EmpireQoL_TopOffMags`.
- **Test:** `tests/chores/restock_test.lua`, 37 checks.

## D1. Sorter hardening (`EmpireSortAll_Client.lua`)

`EmpireSortAll.run(player, opts)` and the internal `smartSort(player, opts)` take new optional `opts`. **No opts = the old behaviour; F9/Numpad 3 and the menus do not pass any.**

| opt | effect |
|---|---|
| `carriedOnly` | a deposit only: files what is carried (or `sources`) and skips eviction, over-capacity shed, magnet pull, rot purge (PASS A), floor pickup (PASS B), placed-ammo-can restock and the consolidate pass. Implies `quiet`. Rotten carried food is left in the pack (a deposit-only run has no rot purge, so it must not shelve rot beside fresh food). |
| `sources` | containers whose items are filed as if carried (a production node's output). The gun-loadout rule does not apply to them. |
| `noCarried` | do not touch the survivor's own inventory. |
| `itemFilter(item)` | only items for which it returns true may move (carried and sources). |
| `quiet` | no "already in order" / "no storage nearby" chatter. |

Also: `freeOf` is memoised per run and invalidated on every move (`freeDirty`); the memo only orders candidates, the real capacity check in `placeInto` is unchanged. With `carriedOnly`, per-container category counts are cached for 30 s (`countByCatCached`) and dropped for every container a sort touched. `13_AutoChores` auto sorts pass `{carriedOnly = true}` (`SORT_CARRIED_ONLY`).

**Test:** `tests/chores/sorter_test.lua`, 53 checks (mocks the cell and containers; compares no-opts behaviour against the unpatched sorter when it is given as the 4th argument, otherwise those 5 checks skip). Known small caveats: category counts can be up to 30 s stale after a full F9 sort (only changes which shelf a deposit prefers); a bag nested inside a `sources` container is not exempt from the gun-loadout rule.

## Self-test (Numpad 9, `49_AutoTest.lua` block T2c)

Checks that all seven chores are registered, the helper/export functions exist (`EmpireBaseCache.peek`, `EmpireQoL_TopOffMags`, `EmpireProd.registry`, `EmpireSortConfig.isExcludedContainer`), the vanilla entry points resolve (`eatItem`, `onDrinkFluid`, `HandcraftLogic.new`, `ISFarmingMenu.walkToPlant`, `ISHarvestPlantAction`, `ISWaterPlantAction`, `ISEquipWeaponAction`, `ISLoadBulletsInMagazine`), the Java enums exist (`CharacterStat`, `MoodleType.FOOD_EATEN`, `FluidCategory.Beverage`, `CFarmingSystem.instance`, `RainManager`) and that hunger/thirst read as numbers. All were verified against the 42.22.2 Lua copy before use.

## Untested in game (read this before trusting any of it)

- **D4:** the can opener is found by item type name (`TinOpener`/`CanOpener`) because `ItemTag.CAN_OPENER` does not appear in vanilla Lua; the `getOpeningRecipe` + `HandcraftLogic` path for sealed cans has never run against the real engine; the 0.20 thresholds are a guess at "peckish".
- **D5:** the registry walk (`getLuaObjectCount/ByIndex`) and B42's fluid-based watering through `ISWaterPlantAction`; how a plant's square and farm-zone tiles line up in a real zone.
- **D6:** `collect` depends on the real sorter honouring `sources/itemFilter/noCarried` (mock-tested only). A node whose recipe output is also loadout ammo is the odd case to watch.
- **D7:** `EmpireBaseCache.peek()` after leaving the base (the heartbeat that clears the index is off by default, so it should still be there, but this has not been seen); the `OnEnterVehicle` path; hotbar read through `getPlayerHotbar`.
- **D1:** the new sorter paths in the real engine; the 30 s count cache; timing of an auto sort (still prints `[EmpireAutoChores] auto-sort took N ms` to the console).
- **Overall:** no multi-chore interaction run (needs eats while a sort is queued, etc.). Check `console.txt` for `[EmpireAutoChores]`, `[EmpireAutoNeeds]`, `[EmpireAutoFarm]`, `[EmpireAutoProduction]`, `[EmpireAutoRestock]` lines after the first play session.
