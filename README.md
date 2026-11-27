# Empire PZ Mods

A suite of personal Lua mods for **Project Zomboid** (Build 42; a few older mods date from Build 41), written for one long-running "empire" playthrough: base logistics, vehicle repair from base stock, inventory sorting, survivor-NPC management and quality-of-life fixes.

- **Status:** being brought to Build 42.22.2 (stable since 9 Nov 2026) for a new playthrough. Last tested in game on 42.19. The pack, launch config, NPC options and a bake-off protocol are in [`docs/PLAYTHROUGH-B42.22.md`](docs/PLAYTHROUGH-B42.22.md). The 184-mod pack audit and two ready presets (`docs/presets/`) are in section 5b; the audit of this suite and the next automation jobs are in [`docs/SUITE-AUDIT-2026-11-26.md`](docs/SUITE-AUDIT-2026-11-26.md). **Build 43 does not exist yet.** After updating, run the self-test (Numpad 9) first: it now checks every vanilla function the mods call or wrap.
- **Build 41 only, do not enable on B42:** EmpireNPC, EmpirePerf, EmpireAmmo (recipes switched off). **EmpireCraftFix** wraps `ISCraftingUI.new` without changing it, so it does nothing.
- **Distribution:** not packaged for the Steam Workshop. Install by copying folders (below).
- **Language:** Lua (PZ's Kahlua runtime) plus PZ script `.txt` files. No build step.

## Mods

Each top-level `Empire*/` folder is one standalone mod. "B42" means the mod has a `42/` subfolder (Build 42 layout); in those mods the root `mod.info` is a stub and `42/` holds the version the game loads. "Root only" mods have no `42/` folder and use the older Build 41-style layout.

| Mod | Layout | What it does |
|---|---|---|
| **EmpireQoL** | B42 | The largest mod. Base registry and live material cache; craft/build and vehicle mechanics drawing materials from nearby base storage; one-click vehicle **Quick repair** and **Quick replace** from base stock (with Vehicle Repair Overhaul integration); corpse vacuum; **auto-chores** (hands-free corpse looting and smart sort at base, below); find item in base; top off magazines; reload from worn gear; no sleep confirmation; delete item; remove un-openable safes; roof-collector plumbing; vehicle unstick; KI5 M998 Humvee part compatibility; context-menu width cache (right-click freeze fix); server-side loot buffs for ammo and residential guns; an in-game self-test (`49_AutoTest.lua`). |
| **EmpireSortAll** | B42 | One-button smart sort of inventory into nearby containers by category; containers can be locked to a category from the world right-click menu. |
| **EmpireZones** | B42 | Paint freeform, multi-floor base/work zones (base, farm, guard, workshop, storage), persisted in the save. |
| **EmpireProduction** | B42 | Accrual-based automation: a container becomes a production node that converts inputs to outputs over game time. Recipes are data. |
| **EmpireLoot** | B42 | Auto engine start on entering a vehicle (its per-frame handler is only registered between entering and the next tick). (The loot filter and trailer transfer were removed from the B42 version; they remain in the root Build 41 copy.) |
| **EmpireAmmoDrop** | B42 | Zombies drop ammo on death (`OnZombieDead`); police and military zombies carry more. |
| **EmpireEatAll** | B42 | The normal "Eat" click eats the whole item; no portion submenu. |
| **EmpireCommand** | B42 | Readable roster/command window for the Knox Survivors mod (follow, base, rest, call, unstick, combat policy). Requires Knox Survivors. |
| **EmpireKSTune** | B42 | Re-applies preferred Knox Survivors sandbox balance at game start. Requires Knox Survivors. |
| **EmpireRFGunFix** | B42 | Script patch registering `RF_AR15SAIGRY` and `RF_G36K`. Requires RealFirearms. |
| **EmpireCraftFix** | Root only | Patches the crafting UI to pre-populate on first open (crafting menu freeze fix). |
| **EmpireNPC** | Root only | Colony layer over Superb Survivors Continued: settler roles (Guard, Medic, Farmer, Warden, Looter), guard posts, garrison control, status panel (F10). Build 41 era. |
| **EmpirePerf** | Root only | Build 41 performance patches (zombie AI, inventory scans, render pacing). Several parts are self-disabled in code. |
| **EmpireAmmo** | Root only | Lean ammo crafting overriding `ammo_smelting` + `GunFighter`. Its only recipe file is currently `EmpireAmmo_recipes.txt.off`, so it adds nothing while that stays disabled. |

## Install and run

1. Copy the `Empire*` folder(s) you want into your Project Zomboid `mods/` directory.
2. Enable them in the game's mod list (and any required third-party mods named above).
3. Start or load a save. Lua is re-read on load; there is nothing to compile.

Load order: EmpireAmmo after `ammo_smelting` and `GunFighter`. EmpireQoL's M998 script overrides (`42/media/scripts/vehicles/`) assume it loads after the M998 Humvee mod when that is used.

## Auto-chores (26 Nov 2026): the sorting and small things, hands-free

`EmpireQoL/.../13_AutoChores.lua` presses the two keys King used to press every trip:

- **Auto-loot:** something died, zombies are gone, corpses are in reach and the worn pack has room: Corpse Vacuum runs once per fight (a kill counter on `OnZombieDead` re-arms it, so quiet beats scan nothing).
- **Auto-park:** you leave a vehicle within 8 tiles of the painted base: engine and headlights go off (a parked car's lights drain the battery). If you are coming home from a trip, the next beat unloads the truck into base storage when it holds 6+ items (same action as right-click vehicle > "Transfer loot to base"). The unload belongs to that truck at that dock: getting back in, or getting out anywhere else, drops it, and the beat checks again that the truck is docked and you are in the base or by the truck. A stop at the gate on the way out never unloads.
- **Auto-sort:** you are inside the painted base, back from a trip (3+ beats, about 75 s, outside the base) with 5+ new items, or anything was auto-looted: Smart Sort runs. Items you take from base storage are **held** and never auto-sorted back: things you grab off your own shelves while in the base, and every quartermaster fetch (build, craft, mechanics, quick repair and replace). Holds end when your next trip starts, so trip leftovers are filed when you get home. Numpad 3 by hand still files everything.

**Performance:** one handler on `Events.EveryTenMinutes` (about 25 real seconds at the default day length). No per-frame handler of any kind. Each beat checks cheap guards first (alive, not driving, not asleep, no timed action running, no zombie visible/chasing/very close) and does one heavy chore at most. Looting never runs while the pack is full. An auto sort that takes more than 250 ms lengthens the cooldown (it is one synchronous frame), and every auto sort prints its duration to the console, so check `console.txt` for `[EmpireAutoChores] auto-sort took` after the first play session. A chore that throws three beats in a row switches itself off and says so. Settings are at the top of the file. **Numpad 5** is the master switch (saved per character). Favourite (star) anything you want to keep carrying; equipped, holstered and "Keep this bag" items are never moved.

### Event-driven chores (27 Nov 2026): eating, farming, production and kit

Four more chores on the same 10-minute beat (details, settings and the full untested-in-game list: `docs/AUTOMATION-JOBS-2026-11-26.md`):

- **Needs (`14_AutoNeeds.lua`):** hungry or thirsty, he eats or drinks from what he carries, and inside the base from base stock (food closest to spoiling first, never favourites, rotten, burnt, frozen or alcohol; sealed cans are opened with a can opener fetched from the base).
- **Farm (`15_AutoFarm.lua`):** inside a painted farm zone he harvests ripe plants, then waters thirsty ones (tainted water first). No tile scan: it walks vanilla's plant registry.
- **Production (`16_AutoProduction.lua`):** EmpireProduction nodes are fed from base storage and their output is filed by the sorter. Per node switch in the node's right-click menu ("Auto-feed").
- **Restock (`17_PreTripRestock.lua`):** the guns in his hands and on his hotbar get 3 spare mags and 40 rounds from base storage in the base, when he boards a vehicle there, and a beat after he leaves.

Each can be switched off in the CONFIG block at the top of its file, all of them with **Numpad 5**. `EmpireSortAll.run(player, opts)` gained `carriedOnly` (deposit-only fast path, used by the auto sort), `sources`, `noCarried`, `itemFilter` and `quiet`; the keys and menus pass no opts and behave as before.

Supporting changes: `EmpireZones.version` plus a cache in `EmpireBases.getEmpireZoneBase` (it used to walk every painted tile on every `activeBase()` call); `EmpireSortAll.run(player)` and `EmpireQoL_Vacuum({auto=true})` are the public entry points.

## Tools

- `tools/apply-jvm-tuning.ps1`: re-applies the heap setting (`-Xms2048m -Xmx6144m`) after a Steam update overwrites `ProjectZomboid64.json`. Idempotent, keeps a backup, `-Check` to look only.

## Testing

`tests/chores/` holds Lua mock tests (run with a pure-JS Lua VM, no game needed): the auto-chores beat logic, the zone-base cache, and each chore (needs, farm, production, restock) plus the sorter's new options. See its README. They check logic against mocked globals, not the real engine.

**In game:** there is no automated end-to-end suite. **EmpireQoL's `49_AutoTest.lua`** runs at game start and on Numpad 9: it asserts the vanilla API surface, Empire globals, recipe registration, core pipelines and that every auto-chore is registered with its vanilla entry points present, printing one PASS/FAIL line per check to the game console. Most debugging in this repo's history is done by reading `console.txt` output from telemetry prints.

## Key bindings (from code)

| Key | Mod | Action |
|---|---|---|
| Numpad 2 | EmpireQoL | Find item in base |
| Numpad 3 | EmpireSortAll | Smart sort |
| Numpad 5 | EmpireQoL | Auto-chores on/off |
| Numpad 7 | EmpireQoL | Corpse vacuum |
| Numpad 8 | EmpireQoL | Top off magazines |
| Numpad 9 | EmpireQoL | Run self-test |
| F10 | EmpireNPC | Status panel |

Header comments in some files still name older keys; the `Keyboard.KEY_*` constants in code are authoritative.

## Notes for agents

- **Only `.lua` and `.txt` files load.** Files ending `.off`, `.bak*`, `.disabled`, `.v3bak` etc. are disabled copies kept for history (about 90 of them). Do not edit them expecting an effect; to disable a feature, rename it to `.off`.
- EmpireQoL client files load in filename order; the numeric prefixes (`02_`, `12_` ... `49_`) set that order. Features share globals such as `EmpireBases`, `EmpireBaseCache` and `EmpireQoL_FetchForRecipe`.
- Several features hook third-party mods (Vehicle Repair Overhaul, tsarslib/ATA tuning, Neat Building, KI5 M998, Knox Survivors) and are written to no-op when those mods are absent. Keep that guard style (`pcall`, existence checks).
- `.gitignore` ignores everything at the top level except `Empire*/` folders and this README, so the repo can sit directly inside a PZ `mods/` directory alongside third-party mods. `EmpireLean.txt` (a mod-list preset) is deliberately untracked.
- Commit messages are long and evidence-based (console findings, root cause, fix); they are the best record of why code looks the way it does. Read `git log` for a file before changing it.
