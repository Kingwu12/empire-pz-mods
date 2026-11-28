# Lua mock tests (no game needed)

Pure-JS Lua VM (fengari) runs our Lua against mocked PZ globals. They check logic, not the real
engine, so they do not replace booting the game and pressing Numpad 9 (AutoTest).

```bash
npm i --no-save fengari   # once, anywhere on NODE_PATH, e.g. in this folder
bash tests/chores/run_all.sh   # every test below, from the repo root; non-zero exit on any failure
node runner.js ../../EmpireQoL/42/media/lua/client/13_AutoChores.lua chores_test.lua
# chore tests: argv[2] = 13_AutoChores.lua, argv[3] = the test, argv[4..] = SRC2, SRC3, ... (module under test, then extras)
node runner.js ../../EmpireQoL/42/media/lua/client/13_AutoChores.lua needs_test.lua ../../EmpireQoL/42/media/lua/client/14_AutoNeeds.lua
node runner.js ../../EmpireZones/42/media/lua/shared/EmpireZones_Core.lua zone_test.lua \
  "$(cat ../../EmpireQoL/42/media/lua/client/29_BaseRegistry.lua)"
```

- `chores_test.lua`: 13_AutoChores beat logic (chore registry and ordering, guards, cooldown,
  pack-full back-off, circuit breaker, Numpad 5 toggle and persistence, leave-base edge), and the bug hunt
  round 2 regressions: a stale park never unloads elsewhere; trips arm the arrival sort; held items
  (quartermaster fetches, grabs off base shelves via the transfer hook, held bags) are never re-sorted.
- `needs_test.lua` (14_AutoNeeds): thresholds, ranking, exclusions, portions, sealed cans, base stock, back-off.
- `farm_test.lua` (15_AutoFarm): farm-zone gating, harvest then water, water source choice, rain, reach, re-tend.
- `production_test.lua` (16_AutoProduction + the real `EmpireProd_Core.lua` and `EmpireSortAll_Config.lua`):
  node registry, feeding, collecting through the sorter's `sources`, node exclusion from the sorter.
- `restock_test.lua` (17_PreTripRestock): which guns, targets, nested bags, favourites, back-off, weight,
  base beat / vehicle boarding / just-left-base paths.
- `sorter_test.lua` (EmpireSortAll_Client): `carriedOnly`, `sources`, `noCarried`, `itemFilter`, `quiet`,
  capacity with the `freeOf` memo, category-count cache, no-opts behaviour against the unpatched sorter, and
  `transferVehicle` returning the items that really left the truck (0 when no storage is in range).
- `waypoints_test.lua` (18_Waypoints): seed, save/update/cap, chase and re-entry guards, truck carry (world-delta transform with physics offsets, relative layout vs saved truck spot, seat re-entry, missing truck, trailer refusal), which vehicle qualifies, Numpad 1 home/back, blocked-arrival search, right-click menu, world-map right-click. Engine behaviour of the real teleport is NOT covered: read the `[EmpireWaypoints]` lines in console.txt after the first trip.
- `zone_test.lua`: EmpireBases.getEmpireZoneBase cache and EmpireZones.version invalidation.
- `stockpiles_test.lua`: EmpireStockpiles against the real vanilla ProceduralDistributions and Distributions (rolls, home weights, port room aliases, idempotence). Needs the vanilla files: `VANILLA_ITEMS=<42.22.2>/media/lua/server/Items bash tests/chores/run_all.sh`.
