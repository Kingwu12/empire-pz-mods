#!/usr/bin/env bash
# Runs every Lua mock test in this folder; exits non-zero if any fails.
#   bash tests/chores/run_all.sh                  (fengari must be on NODE_PATH: npm i --no-save fengari)
#   ORIG_SORTER=/path/to/EmpireSortAll_Client.orig.lua bash tests/chores/run_all.sh   (adds the sorter A/B checks)
set -u
cd "$(dirname "$0")/../.."
Q=EmpireQoL/42/media/lua/client
S=EmpireSortAll/42/media/lua/client
R=tests/chores/runner.js
failed=0
run() {
  local name=$1; shift
  local out; out=$(node "$R" "$@" 2>&1); local rc=$?
  local tally; tally=$(printf '%s\n' "$out" | grep -E '^[0-9]+ checks' | tail -1)
  if [ $rc -ne 0 ]; then
    failed=1; echo "FAIL $name: ${tally:-no tally}"
    printf '%s\n' "$out" | grep -E '^FAIL|LUA ERROR' | head -20
  else
    echo "ok   $name: $tally"
  fi
}
run chores     $Q/13_AutoChores.lua tests/chores/chores_test.lua
run needs      $Q/13_AutoChores.lua tests/chores/needs_test.lua $Q/14_AutoNeeds.lua
run farm       $Q/13_AutoChores.lua tests/chores/farm_test.lua $Q/15_AutoFarm.lua
run production $Q/13_AutoChores.lua tests/chores/production_test.lua $Q/16_AutoProduction.lua \
               EmpireProduction/42/media/lua/shared/EmpireProd_Core.lua $S/EmpireSortAll_Config.lua
run restock    $Q/13_AutoChores.lua tests/chores/restock_test.lua $Q/17_PreTripRestock.lua
run sorter     $S/EmpireSortAll_Client.lua tests/chores/sorter_test.lua $S/EmpireSortAll_Config.lua ${ORIG_SORTER:-}
run waypoints $Q/18_Waypoints.lua tests/chores/waypoints_test.lua
run zone       EmpireZones/42/media/lua/shared/EmpireZones_Core.lua tests/chores/zone_test.lua "$(cat $Q/29_BaseRegistry.lua)"
# Needs the vanilla loot tables (not shipped here): VANILLA_ITEMS=<42.22.2>/media/lua/server/Items
if [ -n "${VANILLA_ITEMS:-}" ]; then
  run stockpiles EmpireStockpiles/42/media/lua/server/Items/EmpireStockpiles.lua tests/chores/stockpiles_test.lua \
      "$VANILLA_ITEMS/ProceduralDistributions.lua" "$VANILLA_ITEMS/Distributions.lua"
fi
exit $failed
