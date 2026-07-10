# Empire PZ Mods

Custom Project Zomboid mods for a long-form multiplayer server. Focus areas: ammo
simplification, NPC colony management, loot filtering, and quality-of-life automation
for extended empire runs.

**Status:** Active development.

## Mods

| Mod | What it does |
|-----|-------------|
| **EmpireAmmo** | Lean ammo crafting — rounds directly from raw materials (lead, brass, powder, primer), no per-calibre intermediate items. Overrides `ammo_smelting` + `GunFighter` recipes; load after both. |
| **EmpireAmmoDrop** | Ammo drop rate tuning. |
| **EmpireCommand** | Server admin commands. |
| **EmpireCraftFix** | Crafting recipe corrections. |
| **EmpireEatAll** | Eat all items of a type in one action. |
| **EmpireKSTune** | Keybind and setting adjustments. |
| **EmpireLoot** | Smart loot filter (F7 toggle) + auto engine start on vehicle entry + quick trailer transfer. Filter what matters, skip junk. |
| **EmpireNPC** | Colony management layer on top of Superb Survivors. Assign settler roles (Guard, Medic, Farmer, Warden, Looter), place guard posts, auto-defend against threats. Status panel on F10. |
| **EmpirePerf** | Performance tuning. |
| **EmpireProduction** | Production and crafting tweaks. |
| **EmpireQoL** | Auto eat, drink, medicate, low-fuel warning, smart weapon hotswap. Stop micromanaging survival. |
| **EmpireRFGunFix** | Reload animation / gun fix. |
| **EmpireSortAll** | Sort all inventory items. |
| **EmpireZones** | Zone definition and management. |

## Installation

Each folder is a standalone mod. Copy the folder(s) you want into your Project Zomboid
`mods/` directory and enable them in the server/game settings.

**Load order note for EmpireAmmo:** load AFTER `ammo_smelting` and `GunFighter`.

## Requirements

- Project Zomboid (tested on Build 41/42)
- **EmpireNPC** requires [Superb Survivors Continued](https://steamcommunity.com/sharedfiles/filedetails/?id=2390075702)
