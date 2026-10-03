# Empire PZ Mods

A suite of personal Lua mods for **Project Zomboid** (Build 42; a few older mods date from Build 41), written for one long-running "empire" playthrough: base logistics, vehicle repair from base stock, inventory sorting, survivor-NPC management and quality-of-life fixes.

- **Status:** dormant. Last code change 3 July 2026; nothing is in active development.
- **Distribution:** not packaged for the Steam Workshop. Install by copying folders (below).
- **Language:** Lua (PZ's Kahlua runtime) plus PZ script `.txt` files. No build step.

## Mods

Each top-level `Empire*/` folder is one standalone mod. "B42" means the mod has a `42/` subfolder (Build 42 layout); in those mods the root `mod.info` is a stub and `42/` holds the version the game loads. "Root only" mods have no `42/` folder and use the older Build 41-style layout.

| Mod | Layout | What it does |
|---|---|---|
| **EmpireQoL** | B42 | The largest mod. Base registry and live material cache; craft/build and vehicle mechanics drawing materials from nearby base storage; one-click vehicle **Quick repair** and **Quick replace** from base stock (with Vehicle Repair Overhaul integration); corpse vacuum; find item in base; top off magazines; reload from worn gear; no sleep confirmation; delete item; remove un-openable safes; roof-collector plumbing; vehicle unstick; KI5 M998 Humvee part compatibility; context-menu width cache (right-click freeze fix); server-side loot buffs for ammo and residential guns; an in-game self-test (`49_AutoTest.lua`). |
| **EmpireSortAll** | B42 | One-button smart sort of inventory into nearby containers by category; containers can be locked to a category from the world right-click menu. |
| **EmpireZones** | B42 | Paint freeform, multi-floor base/work zones (base, farm, guard, workshop, storage), persisted in the save. |
| **EmpireProduction** | B42 | Accrual-based automation: a container becomes a production node that converts inputs to outputs over game time. Recipes are data. |
| **EmpireLoot** | B42 | Auto engine start on entering a vehicle. (The loot filter and trailer transfer were removed from the B42 version; they remain in the root Build 41 copy.) |
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

## Testing

There is no out-of-game test suite. **EmpireQoL's `49_AutoTest.lua`** runs at game start and on Numpad 9: it asserts the vanilla API surface, Empire globals, recipe registration and core pipelines, printing one PASS/FAIL line per check to the game console. Most debugging in this repo's history is done by reading `console.txt` output from telemetry prints.

## Key bindings (from code)

| Key | Mod | Action |
|---|---|---|
| Numpad 2 | EmpireQoL | Find item in base |
| Numpad 3 | EmpireSortAll | Smart sort |
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
