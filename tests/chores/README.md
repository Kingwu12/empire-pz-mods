# Lua mock tests (no game needed)

Pure-JS Lua VM (fengari) runs our Lua against mocked PZ globals. They check logic, not the real
engine, so they do not replace booting the game and pressing Numpad 9 (AutoTest).

```bash
npm i --no-save fengari   # once, anywhere on NODE_PATH, e.g. in this folder
node runner.js ../../EmpireQoL/42/media/lua/client/13_AutoChores.lua chores_test.lua
# chore tests: argv[2] = 13_AutoChores.lua, argv[3] = the test, argv[4..] = SRC2, SRC3, ... (module under test, then extras)
node runner.js ../../EmpireQoL/42/media/lua/client/13_AutoChores.lua needs_test.lua ../../EmpireQoL/42/media/lua/client/14_AutoNeeds.lua
node runner.js ../../EmpireZones/42/media/lua/shared/EmpireZones_Core.lua zone_test.lua \
  "$(cat ../../EmpireQoL/42/media/lua/client/29_BaseRegistry.lua)"
```

- `chores_test.lua`: 13_AutoChores beat logic (chore registry and ordering, guards, cooldown,
  pack-full back-off, circuit breaker, Numpad 5 toggle and persistence, leave-base edge).
- `needs_test.lua` (14_AutoNeeds): thresholds, ranking, exclusions, portions, sealed cans, base stock, back-off.
- `farm_test.lua` (15_AutoFarm): farm-zone gating, harvest then water, water source choice, rain, reach, re-tend.
- `production_test.lua` (16_AutoProduction + the real `EmpireProd_Core.lua` and `EmpireSortAll_Config.lua`):
  node registry, feeding, collecting through the sorter's `sources`, node exclusion from the sorter.
- `restock_test.lua` (17_PreTripRestock): which guns, targets, nested bags, favourites, back-off, weight,
  base beat / vehicle boarding / just-left-base paths.
- `sorter_test.lua` (EmpireSortAll_Client): `carriedOnly`, `sources`, `noCarried`, `itemFilter`, `quiet`,
  capacity with the `freeOf` memo, category-count cache, and no-opts behaviour against the unpatched sorter.
- `zone_test.lua`: EmpireBases.getEmpireZoneBase cache and EmpireZones.version invalidation.
