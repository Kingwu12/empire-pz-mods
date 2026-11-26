# EmpireStable pack audit against Build 42.22.2 (2026-11-26)

> **Amendment by the lead session (26 Nov 2026).** The worker cut `Neat_Building`, `Neat_Crafting` and both AddonXP ids because they "fight the Empire base-storage hooks". That is backwards: `EmpireQoL/.../44_CraftFromBase.lua` carries shims written *for* the Neat panels (`NB_BuildingPanel`, `NC_CraftLogicPanel`, `NC_HandCraftPanel`), and the Neat suite is the set of windows King actually plays with. The audit's own rule is "CUT is objective only", so these four are **TEST**, not CUT, in `presets/EmpireB42-22.txt` (165 mods, not the 161 counted below; counts below are the worker's original). Neat Crafting's batch crafting regressed repeatedly in November, so check ammo/bulk crafting in the bake-off before committing to it. `presets/pack-audit.csv` is amended to match.


Input: `pc-data/EmpireStable.txt`, 184 mod ids. Live data: Steam `GetPublishedFileDetails` (161 Workshop items, fetched 2026-11-26), plus 8 candidate replacements. Machine: Ryzen 5 3600, 16 GB, RTX 3060, single player. Performance is the first criterion.

## Counts

| Verdict | Mod ids |
|---|---|
| KEEP | 37 |
| TEST | 124 |
| CUT | 16 |
| REPLACE | 7 |
| Total | 184 |

- **EmpireB42-22.txt (KEEP + TEST): 184 -> 161 mods.** REPLACE rows are left out until you subscribe to the replacement (lines to add are below).
- **EmpireB42-22-lean.txt (KEEP only, no TASTE-HEAVY, closure-checked): 35 mods.** Lean drops KEEP items whose only known users are excluded (Vehicle Military Zones without the military trucks, Starlit Library without N.W.M.F.).
- Download size (each Workshop item counted once): current pack about 5376 MB, KEEP+TEST about 5216 MB, lean about 130 MB. Most of the weight (Silent Hill music 1,627 MB, Authentic Z 878 MB, Ahu 634 MB, Erika 291 MB) is taste content kept as TEST, so the full preset is only a small download cut; the gain is in the 23 removed mods and the pruned Neat/Knox/proximity stack.

### How the verdicts were set

- **KEEP** needs: updated on or after **2026-09-28** (42.21 stable, the first build that throws RuntimeException on missing recipes, translations and fluids), maintained, light, and no overlap. Three exceptions: Starlit Library (idle library, 2026-08-19), Rain Cleans Blood (2026-09-25, a performance mod, three days short) and Better Auto Mechanics (2026-08-08, title states B42.22+, rewrite of a mod that is being cut).
- **TEST** is everything plausibly fine but unverified on 42.22.2: every era A id that is not cut (53), era B before 09-28, every KI5 vehicle (per-frame handler each), every heavy content pack, and libraries whose users I could not identify.
- **CUT** is objective only: removed from Workshop, deprecated or unsupported by the author, a hard requirement missing, redundant with another kept mod, a duplicate of an Empire feature, orphaned, or Java-loader plus documented freezes. No item was cut on taste.
- Workshop dependencies are not exposed by the keyless API (`IPublishedFileService/GetDetails` returns 401). Dependents are inferred from descriptions and credits; see "Not verified".

## Era breakdown (mod ids)

| Era | KEEP | TEST | CUT | REPLACE |
|---|---|---|---|---|
| A  before 07-29 (pre-stable, high risk) | 0 | 53 | 4 | 3 |
| B  07-29 to 10-26 | 13 | 53 | 7 | 4 |
| C  10-27 to 11-08 | 2 | 7 | 0 | 0 |
| D  on/after 11-09 | 16 | 10 | 3 | 0 |
| Local or removed | 6 | 1 | 2 | 0 |

Era A items (58 Workshop items) are the high-risk group: none is KEEP. Four are CUT and three REPLACE; 53 mod ids are TEST. The oldest are `UBPropFix` (2024-12-17), `ClimbDownRope` (12-18), `ConditionOnDash` (12-21), `DEON_CVG`, `GenRange` and `All Shots Fired` (all December 2024).

## CUT list (16 mod ids)

| Mod id | Workshop | MB | Reason |
|---|---|---|---|
| Erikas_Furniture_Store | 3363546437 | 8.9 | Author banner says OUTDATED MAP with bugs in B42 stable (updated 2026-01-19); it occupies cells between Muldraugh and West Point that other map mods also touch. The tile pack stays on its own. |
| UnifiedCarryWeightFramework | 3682045254 | 0.1 | Idle framework: the only users its page names are More Traits (legacy, being replaced) and Evolving Traits World. Re-add only if you adopt ETW. |
| Military_Tool_Kit | 2705406713 | 31.5 | 31.5 MB, page says work in progress for B42 MP. Its users (Papa_Chad military vehicles) are not in this pack, so it is an orphan. |
| ProximityInventory | 3669550831 | 0.4 | Merges nearby containers into one tab and rebuilds it on every inventory refresh. Duplicates EmpireQoL registry and find-item-in-base and competes with EmpireSortAll. Updated 2026-06-04. |
| FE_CommonSensePatch | 3667553980 |  | Removed from the Workshop (API result 9). |
| CheckAround | 3300688173 | 16.3 | Marked [DEPRECATED] by its author; 16.3 MB; he points to a newer visibility mod (Zombie Visibility Fix, id not verified). |
| Neat_Building_AddonXP | 3540503606 | 4.0 | XP add-on for Neat Crafting/Building, which are cut. |
| Neat_Building | 3536052310 | 47.0 | Replaces the build UI (47.0 MB, WIP tag) and fights the Empire craft/build-from-base-storage hooks; no performance claim from the author. |
| Neat_Crafting_AddonXP | 3540503606 | 4.0 | XP add-on for Neat Crafting/Building, which are cut. |
| Neat_Crafting | 3502080466 | 4.4 | Replaces the crafting UI; Empire registry already feeds crafting from base storage. Batch crafting regressed repeatedly in Nov (stops with thousands of inputs); WIP tag. |
| P4OnTheDoor | 3056481712 | 5.4 | Its own page says keys no longer spawn on doors in B42; the mod only retrieves keys from doors, so it does nothing today. |
| SwapIt | 2366717227 | 0.2 | Hard requirement errorMagnifier is not in the pack: the build report logged MISSING requirement twice, so it cannot enable as configured. To use it add errorMagnifier 2896041179 (0.4 MB, 2026-11-18). |
| UBPropFix | 2883755057 | 0.0 | Propane torch fix for 41.78 (updated 2024-12-17), duplicates the maintained Fix BlowTorch & PropaneTank. |
| AutoMechanics | 3387539308 | 0.8 | Same job as Better Auto Mechanics (which says it is a rewrite of this mod). Keep one. |
| KnoxSurvivors | 3749727604 | 6.8 | Needs the ZombieBuddy Java loader (TIS: Java mods unsupported, break on updates). Documented freezes of 1-2 s every few seconds in Nov that population limits did not fix; author is rewriting the population system; incompatible with Tactical Hold, shaky with KI5 vehicles. Saves from older versions may not load. |
| EmpireKSTune | LOCAL |  | Tunes Knox Survivors, which is cut; does nothing without it. |

`NeatUI_Framework` stays (KEEP) because CleanUI, The Shortcut, Project Cook and Neat Rocco need it.

## REPLACE list (7 mod ids, 4 Workshop items)

| Old item (mod ids) | Replace with | Why |
|---|---|---|
| Common Sense 2875848298 (`BB_CommonSense`); 3667553980 patch (`FE_CommonSensePatch`, removed) | **Common Sense [B42.20+] 3750253491**, mod id `VB_CommonSense`, updated 2026-11-19, 0.9 MB, 410k subs | Old one dates from 2025-03-07 and throws on the Alcohol fluid since 42.21; the patch was deleted. The fork is standalone. Drop `ReloadAllMagazines` afterwards (the fork has reload-all). Its pry feature overlaps the 42.22 vanilla crowbar; commenters say both work. |
| More Traits [Legacy] 1299328280 (`1299328280/ToadTraits` + 3 sub-mods) | **Evolving Traits World 2914075159**, mod ids `EvolvingTraitsWorld` (+ `EvolvingTraitsWorldTraitSandbox`), updated 2026-11-26, 7.8 MB, 244k subs | The author of More Traits says it gets no more support and the maintained version lives inside ETW. Turn dynamic gain/loss off to use the static traits only. Re-add `UnifiedCarryWeightFramework` with it. |
| darlak H.E.C.U. 3452711271 (`H_E_C_U`) | **H.E.C.U. B42.20, 3737864976**, same mod id `H_E_C_U`, updated 2026-08-14, 20.2 MB, 29.6k subs | Old item is titled B41 and its author says it is not actively supported; he points to this one. |
| Simple Flashlight on Belt 3394588830 (`LightOnBelt`) | **Simple Belt Flashlight 3625933422**, mod id `FixedLightOnBeltAF`, updated 2025-12-28, 0.3 MB | Old page says NOT UPDATED ANY MORE. Optional: Better Flashlights already ships belt-ready lights, so you can just drop it. |

## Overlap verdicts against the Empire mods

| Mod | Verdict | Overlap with |
|---|---|---|
| ProximityInventory | CUT | EmpireQoL registry and find-item-in-base; competes with EmpireSortAll on container enumeration. |
| Neat_Crafting / Neat_Building (+2 AddonXP) | CUT | EmpireQoL craft/build/repair drawing from base storage; replacing the craft and build UIs fights those hooks. |
| CleanUI | TEST | Re-lays out inventory and loot window title bars; no transfer logic, but check it does not cover the EmpireSortAll button. |
| Neat_Rocco | TEST | Window restyle, overlaps CleanUI; keep one. Supported to 42.21 only. |
| ContainerFavorite | TEST | Check EmpireSortAll leaves favorited items alone. |
| OpenAllContainers | TEST | Per-tick container opening; check with EmpireSortAll and the base registry. |
| AccessibleContainers, ItemRarityUI, P4PickingMeister | TEST | Add inventory pane buttons or rows that EmpireSortAll also touches. |
| ReloadAllMagazines | TEST | Overrides doMagazineMenu; clashes with Common Sense B42.20+ reload-all and possibly Guns of 93. |
| KnownAndCollected vs P4HasBeenRead | TEST / KEEP | Both mark read books; keep P4HasBeenRead and test K&C (and its 42.13 patch) off. |
| AmmoLootDropGuns93B42 x3 | TEST | Empire ammo drops; run one source at a time. |
| AutoMechanics vs better-auto-mechanics | CUT / KEEP | Same feature; the older one is cut. |
| BetterGeneratorInfo vs GenRange | TEST | Generator range shown twice; keep one. |
| Water set: Waterpipes, TankWater, SomewhatWater, UsefulBarrelsMP | TEST | Four mods on fluid containers; test as a group (42.21 fluid strictness). |
| Backpack set: Authentic Z, Legendary x5, EFTBP, Cerberus, Lynx | TEST | Taste overlap only, not cut; 1.1 GB combined. |

## TASTE-HEAVY (pure content, 50 MB or more; none cut on taste)

| Item | Size MB | Verdict | Mod ids |
|---|---|---|---|
| Silent Hill Dynamic Music Replacement (3556702241) | 1627.1 | TEST | SHdynamicmusic |
| Authentic Z (2335368829) | 877.8 | TEST | AuthenticZBackpacks+ |
| [B42.15]Ahu's ToolWeapon Pack (3422418897) | 634.2 | TEST | Ahu'sToolWeapon |
| Erika's tiles (3346506593) | 290.7 | TEST | Erikas_Tiles |
| Legendary Backpacks (3538353228) | 168.1 | TEST | LBB42 |
| PertsPartyTiles (2837923608) | 144.5 | TEST | PertsPartyTiles |
| Vanilla Foods Expanded (3577903007) | 129.9 | TEST | VanillaFoodsExpanded |
| KATTAJ1 Military Pack [B41/B42MP] (3470426196) | 117.9 | TEST | KATTAJ1_Military |
| Guns of 93: B42 Test Build (3183820077) | 78.2 | TEST | guns93 |
| RV Interior Expansion [B42] (3618427553) | 72.2 | TEST | RVInteriorExpansion |
| Vanilla vehicles animated (3281755175) | 71.2 | TEST | VanillaVehiclesAnimated, VVA_cullseats, VVA_PikamyDelight, VVA_snapDoors, VVA_transparentWindows |
| Horse Mod [B42.20+/MP] (3661336777) | 58.5 | TEST | Horse |

All are TEST because 16 GB and per-mod heap make unmeasured heavy packs a performance risk. Measure frame time and RAM with and without each before the world starts. Biggest wins if you must trim: Silent Hill music (1,627 MB), Authentic Z (878 MB), Ahu (634 MB), Erika tiles (291 MB). Not taste-heavy but heavy: Neat Building 47 MB (cut), damnlib 43.6 MB, Take A Bath 40 MB, Tank Water 37 MB, My So-Called Snack 37 MB.

## Performance notes

- **Tempo** (`Tempo_PerfKit`) is the only KEEP performance mod. Skip its optional loose `.class` engine patches: the author says outdated class files must be removed when it updates, and TIS treats Java patches as unsupported (note of 2026-10-21).
- **KI5 stack.** The pack has 12 KI5-style vehicle mods (each adds an OnPlayerUpdate handler that runs every frame even on foot), tsarslib (asks for ModData every 100 ticks) and damnlib (builds a string key per loaded square). All are TEST. If you keep them, add the two Lua-only patches below. They are not in the presets because they are additions, not part of the 184.
  - KI5 Vehicle Performance Patch 3808100388, mod id `KI5PerfPatch`, updated 2026-09-25, 17 KB, unofficial, author built it with an AI assistant and promises no support. Installs after all mods load.
  - KI5 General Fixes 3789366983, mod id `KI5GeneralFixes`, updated 2026-10-15, 0.3 MB, load order does not matter.
- **RainCleansBlood** is KEEP; also set Blood to Low or Off in sandbox. **P4TidyUpMeister** is KEEP but is an item-return mod, not a corpse cleaner.
- **Java-loader mods:** KnoxSurvivors is the only one in the pack. No other pack mod mentions ZombieBuddy.
- **Era A that can fail outright on 42.22:** `ClimbDownRope` (42.22 removed the ClimbSheetRope state), tile or map mods (`Erikas_Tiles`, `PertsPartyTiles`, `muldraughmilitarybaseas24`, Take A Bath depth map, HydeCo doors, RV interiors; 42.22 moved tile definitions), and `SHdynamicmusic` (42.22 moved FMOD bank files).

## Unmapped, removed and local

- Unmapped Workshop ids: none (176 of 184 ids map to a Workshop item).
- Local, no Workshop item (8): EmpireEatAll, EmpireQoL, EmpireSortAll, EmpireLoot, EmpireProduction, EmpireZones (all KEEP), EmpireKSTune (CUT, tunes Knox), EmpireCommand (TEST, presumably Knox-linked; keep only if it works without Knox).
- Removed from Workshop (API result 9): 3667553980 `FE_CommonSensePatch`. Nothing else is hidden or banned.
- Titles flagged by author text: `[DEPRECATED]` Check Around, `NOT UPDATED ANY MORE` Light On Belt, `OUTDATED MAP` Erika Furniture Store, `[B41]` darlak H.E.C.U., `Legacy` More Traits. Items carrying the Workshop WIP tag (not a verdict by itself): NeatUI Framework, CleanUI, CleanHotBar, The Shortcut, Project Cook, Neat Crafting, Neat Building, HydeCo doors, Vest + Overalls, Realistic Professions Remastered, Vanilla Gear Expanded, [B42] Survival, Take A Bath And Shower, Generator Streetlights Restored.
- `SwapIt` (the preset builder logged `MISSING requirement errorMagnifier` twice) cannot enable as configured; it is CUT unless you add errorMagnifier 2896041179.

## Lines to add after you subscribe to the replacements

Add inside the `mods` block of either preset, near the position of the item they replace:

```
    mod = VB_CommonSense,
    mod = EvolvingTraitsWorld,
    mod = UnifiedCarryWeightFramework,   (only if ETW is used)
    mod = H_E_C_U,                         (only after swapping the item; same id)
    mod = FixedLightOnBeltAF,              (optional)
    mod = KI5PerfPatch,                    (only with KI5 vehicles)
    mod = KI5GeneralFixes,
```

## Not verified

- No Workshop dependency lists (keyless API returns 401). Frameworks without a named user (YAPZLib, TchernoLib, REDLIBRARY, DoggyLibrary) are TEST for that reason. On the PC, run the same `mod.info` `require=` parse as `build_stable_preset.py` over the final preset to prove closure.
- Nothing was loaded in the game: no 42.22.2 load test, no frame-time or RAM measurement, no check that a mod's scripts reference removed vanilla recipes. The 42.21 RuntimeException risk for recipe, fluid and translation references is flagged per mod but not tested.
- Whether the Empire mods hook the same functions as the cut UI mods: inferred from their described features, not from their code. EmpireQoL vehicle remove/replace on 42.22.2 (new permission check) is untested. Whether EmpireLoot already rolls Guns of 93 ammo is unknown.
- Comment threads (Steam discussion pages returned HTTP 429 earlier) were not available for most items, so breakage reports are second-hand where cited from the research notes.
- Guns of 93 is updated today and titled Test Build; its state on the 42.22.2 stable could change between this audit and your first launch.
- File sizes are Workshop upload sizes, not installed or in-memory sizes.
