# Lua mock tests (no game needed)

Pure-JS Lua VM (fengari) runs our Lua against mocked PZ globals. They check logic, not the real
engine, so they do not replace booting the game and pressing Numpad 9 (AutoTest).

```bash
npm i --no-save fengari   # once, anywhere on NODE_PATH, e.g. in this folder
node runner.js ../../EmpireQoL/42/media/lua/client/13_AutoChores.lua chores_test.lua
node runner.js ../../EmpireZones/42/media/lua/shared/EmpireZones_Core.lua zone_test.lua \
  "$(cat ../../EmpireQoL/42/media/lua/client/29_BaseRegistry.lua)"
```

- `chores_test.lua`: 13_AutoChores beat logic (guards, cooldown, pack-full back-off, circuit
  breaker, Numpad 5 toggle and persistence).
- `zone_test.lua`: EmpireBases.getEmpireZoneBase cache and EmpireZones.version invalidation.
