# Empire playthrough pack: Build 42.22.2 (researched 26 Nov 2026)

Performance comes first in every choice below. Ratings are *risk of frame-time cost*, from mod pages, comments and source where we could read it. **Nothing here is measured on the Ryzen 5 3600 / RTX 3060 PC.** The bake-off at the bottom is how we measure it.

**Ready to play? Start with [`PLAY-READY.md`](PLAY-READY.md): the decisions made from this research and the one command (`tools/ready-to-play.ps1`) that checks the pack.**

## 1. Version facts

- **Build 43 does not exist.** No date, no beta. It is the build meant to add vanilla human NPCs. Until then, NPCs are mods.
- **Stable is 42.22.2** (default branch since 9 Nov 2026; Steam auto-updates to it). 42.21 stays selectable under Properties > Game Versions & Betas. [Steam news](https://store.steampowered.com/news/app/108600).
- **42.19 saves cannot be converted to 42.20+.** So the old empire save is closed and the next run is a fresh save. 42.22 converts 42.20/42.21 saves and writes a `_backup`.
- **Java mods are officially unsupported** (TIS, 21 Oct 2026) and the game jar is signed from 42.22.1. Prefer Lua-only mods; every Java mod is a "may break on any update" item.
- Our suite was last built and tested on **42.19**. Treat everything in section 6 as untested on 42.22.2 until the self-test (Numpad 9) passes.

## 2. Launch config (`ProjectZomboid64.json`)

State on 26 Nov (read from the PC): Steam has overwritten the 28 Jun tuning, so the file is **stock again: `-Xmx3072m`, ZGC, no `-Xms`**. The old 8 GB heap was too big anyway: process memory runs well above the heap (5.3-7.6 GB RSS with a 4 GB heap in one author's tests), so 8 GB on a 16 GB PC with Windows, Discord and a browser invites paging.

**One command re-applies the target after any update** (idempotent, keeps a backup, close the game first): `tools\apply-jvm-tuning.ps1` in this repo (`-Check` only reports). It was tested on a copy of the real file; the file itself has not been changed yet.

- Keep every stock argument. Keep `-XX:+UseZGC` (it is already generational on the bundled Java 25; do **not** add `-XX:+ZGenerational`).
- Change the heap to `-Xms2048m -Xmx6144m`. Raise to 7168 only if a GC log shows the live set above ~60-70% of 6 GB, or `OutOfMemoryError` / ZGC "Allocation Stall" lines.
- For the bake-off only, add `-Xlog:gc*:file=gc.log:time,uptime`, then remove it.
- Steam updates and "verify files" can overwrite this file. Check it after each update.
- Do not use: Java injectors (PZO, Lugli, Zed's Better FPS, PZ_Optimization), Multi-Cpu Enhance (its ParallelGC added 290-390 ms pauses), memory-cleaner mods, `-Xms16g`/GraalVM/`DisableExplicitGC`/`AlwaysPreTouch` guides.

Source for the numbers: [PZ_Optimization findings](https://github.com/xD3I/PZ_Optimization/tree/master/docs) (one author's 9800X3D/4090 rig; GC was 0.3-0.4% of frame time, so heap size is margin, not FPS).

## 3. Settings that move the needle

In order of effect (the game thread is single-core bound; hordes dominate):

1. Lower zombie population and respawn. Fewer zombies is the biggest lever, and it also shrinks the cost of every NPC mod (they treat NPCs as zombies).
2. Fewer NPCs, no NPC vehicles, no RV-interior mods.
3. Texture compression **off** on the RTX 3060. UI offscreen rendering **on**. Moderate zoom.
4. Watch `console.txt` for per-frame Lua error spam and remove the mod that causes it. Any mod calling `collectgarbage` costs 118-320 ms per call.
5. Back up the save before the 42.22 conversion; check for duplicated animals near the base.

## 4. NPC layer: one per save

NPC mods share zombie bodies, so run **one** at a time. No NPC mod has clean performance evidence. Ranked for an empire run:

| Variant | Mods | What the evidence says |
|---|---|---|
| **A: Crew** | [Bandits NPC](https://steamcommunity.com/sharedfiles/filedetails/?id=3268487204) + [NPC Crew](https://steamcommunity.com/sharedfiles/filedetails/?id=3800132623) | Lua only, no Java loader, updated 24 Nov. Best colony features among Lua mods (beacon, zones, sorters, farmer, builder, hunter, animal keeper, loot runs). The developer's own test (25 Nov, per one reading of the comments): 300 zombies, 55 FPS without it, 33 FPS with it, even with no crew. Cost scales with zombie count, so lower population. Use the "No hostile bandits" option. |
| **B: Knox** | [ZombieBuddy 2.3.4](https://steamcommunity.com/sharedfiles/filedetails/?id=3619862853) + [Knox Survivors](https://steamcommunity.com/sharedfiles/filedetails/?id=3749727604) + EmpireCommand + EmpireKSTune | What we used before. Maintained, "verified on 42.22". Java loader. Players report 1-2 s freezes every 7-15 s on 4, 7 and 24 Nov; author says population was the cause and calls his 10 Nov change "another attempt". His advice: population 200-400, survivor caps on. Our own June commits found that raising NPC body-count knobs cost FPS. |
| **C: Companion** | [Stay With Me](https://steamcommunity.com/sharedfiles/filedetails/?id=3800989007) | One companion, not a colony. Best-documented performance work (update-rate caps). The cheap fallback. |
| Control | none | Baseline for the bake-off. |

Not recommended: [Project A-Life](https://steamcommunity.com/sharedfiles/filedetails/?id=3803984183) (a world simulation, 490 MB, comments report stutter every few seconds), [Project Remnants](https://steamcommunity.com/sharedfiles/filedetails/?id=3738362476) (Workshop build broken on 42.22, closed-source installer), True Companions (abandoned since August), Bandits Week One / The Ark (story mods, author says they cost a lot), Superb Survivors (Build 41 only).

**Default if there is no time to test:** Variant A with "No hostile bandits" and lower zombie population, because it avoids the Java loader and its cost is predictable. **Switching away from Knox Survivors drops the EmpireCommand roster window** (it reads Knox's data).

## 5. Core pack (no NPC), load order top to bottom

Empire mods load **last**. Risk is frame-time risk.

| # | Mod | Why | Risk |
|---|---|---|---|
| 1 | [tsarslib](https://steamcommunity.com/sharedfiles/filedetails/?id=3402491515) | Library for ATA vehicle tuning | med; no 42.22 statement |
| 2 | [that DAMN Library](https://steamcommunity.com/sharedfiles/filedetails/?id=3171167894) | KI5 vehicle dependency | med |
| 3 | Our KI5 vehicles | Maintained through Nov. About 20 cars each add a per-frame handler, so keep the car list short | med-high |
| 4 | [KI5 Vehicle Performance Patch](https://steamcommunity.com/sharedfiles/filedetails/?id=3808100388) | Lua-only, 17 KB | low |
| 5 | [KI5 General Fixes](https://steamcommunity.com/sharedfiles/filedetails/?id=3789366983) | Fixes vehicle-load stutter and container-id log spam | low |
| 6 | [Vehicle Repair Overhaul](https://steamcommunity.com/sharedfiles/filedetails/?id=2757712197) | Update 64 (16 Nov), patched for 42.22 | low-med |
| 7 | [ATA tuning port (Fjord Mustard)](https://steamcommunity.com/sharedfiles/filedetails/?id=3405178154) | Last updated May; no 42.22 evidence | med |
| 8 | [Real Firearms](https://steamcommunity.com/sharedfiles/filedetails/?id=3238830225) | Update #52 (18 Nov) labelled 42.22.2 | med |
| 9 | [Skill Recovery Journal](https://steamcommunity.com/sharedfiles/filedetails/?id=2503622437) | Updated 17 Nov | low |
| 10 | [Common Sense B42.20+](https://steamcommunity.com/sharedfiles/filedetails/?id=3750253491) | One variant only | low |
| 11 | [Better Sorting](https://steamcommunity.com/sharedfiles/filedetails/?id=2313387159) | Data-only; test against EmpireSortAll | low |
| 12 | [Plysken Solar](https://steamcommunity.com/sharedfiles/filedetails/?id=3725311427) | Power for the base | low-med |
| 13 | [Generator Powered Buildings](https://steamcommunity.com/sharedfiles/filedetails/?id=3597471949) | WIP, 42.22-oriented | med |
| 14 | [More Builds](https://steamcommunity.com/sharedfiles/filedetails/?id=515555911) | Base building | med |
| 15 | [Farming Zone](https://steamcommunity.com/sharedfiles/filedetails/?id=3838784593) | Check overlap with EmpireZones | low |
| 16 | [Stutter Watch](https://steamcommunity.com/sharedfiles/filedetails/?id=3823894801) | Diagnostic only; enable while hunting stutter | n/a |
| last | Empire mods (section 6) | Ours | see below |

**Maybe:** [Proximity Inventory](https://steamcommunity.com/sharedfiles/filedetails/?id=3740165370) (low, but overlaps EmpireQoL), [Better Containers](https://steamcommunity.com/sharedfiles/filedetails/?id=3586216562) (stuttered with huge item counts), [Basement Building](https://steamcommunity.com/sharedfiles/filedetails/?id=3806513504), [True Music B42](https://steamcommunity.com/sharedfiles/filedetails/?id=3397198968), [Tempo](https://steamcommunity.com/sharedfiles/filedetails/?id=3736629791) Lua part only (fixes the right-click menu width cost; overlaps our `02_MenuWidthCache`, so **never run both without testing**), [Undying Optimizer](https://steamcommunity.com/sharedfiles/filedetails/?id=3777958977) (not together with Tempo). [Vanilla Foods Expanded](https://steamcommunity.com/sharedfiles/filedetails/?id=3577903007): hold off, its 25 Nov update crashed servers and was hotfixed.

**Avoid:** Papa_Chad M998 (comments report FPS falling to 2-15; use [KI5's M998](https://steamcommunity.com/sharedfiles/filedetails/?id=2642541073)), PZO, Zed's Better FPS, Inventory Tetris (conflicts with our crafting and sorting mods; Neat Crafting / Neat Building were first listed here but are **not** avoided, see section 5b), Logistics Zones and the VRO Nearby Containers fork (duplicate EmpireQoL), B41-only Hydrocraft / Arsenal[26] / original Brita.

**Empire-goal scaffolding:** no light, proven mod exists. [The Mission](https://steamcommunity.com/sharedfiles/filedetails/?id=3640172314) and [Living World](https://steamcommunity.com/sharedfiles/filedetails/?id=3837614147) are the least-bad, neither shown to be light. Our own EmpireZones + EmpireProduction are the empire layer for now.

## 5b. The real 184-mod pack, audited (26 Nov 2026)

Section 5 is the 16-mod third-party core. King's actual preset is `EmpireStable` (184 mod ids, about 5.4 GB). Each id was checked against live Steam data (`GetPublishedFileDetails`, 26 Nov) and the research above. Full table: [`PACK-AUDIT-2026-11-26.md`](PACK-AUDIT-2026-11-26.md) and `presets/pack-audit.csv`.

| Preset (copy into `Zomboid/mods/`) | Mods | Use |
|---|---|---|
| [`presets/EmpirePlay.txt`](presets/EmpirePlay.txt) | 175 | **The chosen one.** The full pack plus the Louisville Shipping Port with its tile packs and the 7 additions (Bandits NPC, NPC Crew, VB_CommonSense, Evolving Traits World, H.E.C.U. B42, two KI5 patches). Needs those subscribed first; see [`PLAY-READY.md`](PLAY-READY.md). |
| [`presets/EmpireB42-22.txt`](presets/EmpireB42-22.txt) | 163 | KEEP + TEST with what is installed today: no NPCs, old Common Sense stays out. Works without any new subscription. |
| [`presets/EmpireB42-22-lean.txt`](presets/EmpireB42-22-lean.txt) | 35 | KEEP only, no heavy content packs. The performance baseline and the bake-off control. |

- **Verdicts:** KEEP 37 (updated on or after 28 Sep, the first build that throws on missing recipes and fluids; maintained; light), TEST 127 (plausible but unverified on 42.22.2), CUT 13 after my amendment and the Tank Water cut, REPLACE 7. Every one of the 53 pre-July ids is TEST at best; none is KEEP.
- **Cut:** Knox Survivors + EmpireKSTune (Java loader, 1-2 s freezes in Nov), ProximityInventory (duplicates EmpireQoL and fights EmpireSortAll), Check Around (deprecated), SwapIt (needs errorMagnifier, absent), AutoMechanics (duplicate of Better Auto Mechanics), UBPropFix, P4OnTheDoor, Military_Tool_Kit (orphan, 31 MB), Erika's Furniture Store (author says outdated map), Unified Carry Weight Framework (idle), FE_CommonSensePatch (removed from Workshop).
- **Replace (subscribe first, then add the line):** Common Sense -> [VB_CommonSense 3750253491](https://steamcommunity.com/sharedfiles/filedetails/?id=3750253491) (the old one throws on the Alcohol fluid since 42.21; drop ReloadAllMagazines with it); More Traits Legacy -> [Evolving Traits World 2914075159](https://steamcommunity.com/sharedfiles/filedetails/?id=2914075159); H.E.C.U. -> 3737864976 (same mod id); Simple Flashlight on Belt -> 3625933422 or just drop it. Ids to add are listed at the end of the audit.
- **Neat Crafting / Neat Building are TEST, not cut.** The worker cut them for "fighting the Empire hooks", but `44_CraftFromBase` has shims written for those panels and they are the windows in use. Batch crafting regressed in November, so test bulk ammo crafting early.
- **Heavy content, none cut on taste (about 4.3 GB):** Silent Hill music 1.6 GB, Authentic Z 878 MB, Ahu 634 MB, Erika's tiles 291 MB. Measure with and without before the world starts; these are the first things to drop if frame time or RAM disappoints.
- **Per-frame risk:** the 12 KI5-style vehicles add an `OnPlayerUpdate` handler each, tsarslib asks for ModData every 100 ticks, damnlib builds a string per loaded square. All TEST. If kept, add KI5 Vehicle Performance Patch (3808100388) and KI5 General Fixes (3789366983). Tempo is the only performance mod kept (skip its `.class` patches).
- **Likeliest outright breaks on 42.22:** ClimbDownRope (rope-climb state removed), tile/map mods (Erika's tiles, PertsPartyTiles, muldraugh military base, Take A Bath, RV interiors; tile definitions moved), Silent Hill music (FMOD banks moved).
- **Nothing here was loaded in the game.** No dependency closure either: run the `mod.info` `require=` parse from `build_stable_preset.py` over the final preset on the PC.

**Sorting and chore mods on the Workshop** ([`research/automation-mods-2026-11-26.md`](research/automation-mods-2026-11-26.md)): none auto-sorts; every one runs on a button, a trip, pipes or a drop box, so `EmpireSortAll` plus `13_AutoChores` is ahead. Cheap and recent, worth trying: Better Sorting (2313387159, data only), Tidy Up Meister, Rain Wash, Automatic Refueling (3632134603), AutoLights (3737087835), Farming Zone (3838784593, check against EmpireZones). Avoid: Auto Loot (3392699932), Safehouse Inventory, Neat Storage Networks, Connected Base. Vanilla 42.20-42.22 already does faster stack transfers, auto-drink, item return after actions and ripping while walking.

## 6. Our own mods on 42.22.2

| Mod | Status | Note |
|---|---|---|
| EmpireQoL | Enable | **New: `13_AutoChores.lua`** (auto corpse looting, auto sort at base, auto park + unload at the dock; Numpad 5 switch; one 10-minute beat, no per-frame handler; see README). Base-zone lookup cached, right-click width formula fixed for 42.22, FindItem's permanent per-frame handler removed. The self-test (`49_AutoTest.lua`, Numpad 9) now also checks every vanilla function we call or wrap (new T1b block) and prints the game version. Run it first on a new save. Vehicle Quick repair / Quick replace need a real vehicle test. |
| EmpireSortAll | Enable | Now also called by auto-chores (`EmpireSortAll.run`, `.transferVehicle`). Test against Better Sorting. Watch `[EmpireAutoChores] auto-sort took N ms` in the console after the first session. |
| EmpireZones | Enable | |
| EmpireProduction | Enable | |
| EmpireAmmoDrop | Enable | Uses `OnZombieDead`; no signature change found in the notes. |
| EmpireEatAll | Enable | |
| EmpireLoot | Enable | Per-frame handler is now registered only between entering a vehicle and the next tick. |
| EmpireRFGunFix | Enable only with Real Firearms | It registers `RF_AR15SAIGRY` and `RF_G36K`. Real Firearms update #52 (18 Nov) may already cover them, so check the console before keeping it. |
| EmpireCommand + EmpireKSTune | Variant B only | Read Knox Survivors data; Knox rebuilt its runtime on 22 Sep, so verify the roster window still opens. |
| EmpireCraftFix | **Do not enable** | Its only code wraps `ISCraftingUI.new` and returns the original result unchanged (the comment says it "just ensures no double-load"), so it fixes nothing. It also has no `42/` folder. The real crafting-menu work lives in EmpireQoL. |
| EmpireNPC, EmpirePerf, EmpireAmmo | **Do not enable** | Build 41 only (Superb Survivors layer, B41 engine patches, ammo recipes that are switched off). Kept for history. |

**What changed in 42.20 to 42.22 that could hit us** (from release notes and the PZ-Umbrella stub diff; signatures only, not behaviour):

- A missing recipe, item or translation reference now throws instead of logging (42.21). Watch `console.txt` for recipe errors after enabling EmpireQoL, EmpireProduction and EmpireAmmoDrop.
- Changed signatures: `ItemContainer.canItemFit` / `canHumanCorpseFit`, `CraftRecipeData.populateInputs`, the item-transaction globals, `ISInventoryPaneContextMenu.onCustomFunction`, `ISWorldObjectContextMenu.onCustomFunction`. A grep found none of these names in our active mods.
- 42.22 made the server-side `vehicle remove` command need a permission check. It broke Vehicle Repair Overhaul's *whole-vehicle salvage* in multiplayer (fixed in its Update 63). Our Quick replace swaps parts through the vanilla part menu in single player, so we do not expect it, but test it.
- `becomeCorpseSilently` removed, `PZArrayList` removed, `loadstring` briefly removed in 42.20.4 and restored in 42.21. None used by our active mods.
- Unverified and high-impact: the stub diff showed `server/recipecode.lua` and `client/Context/*` disappearing. This may be a stub-generator change. If a recipe `OnCreate` or context menu fails, diff against the installed 42.22.2 Lua first.

## 7. Bake-off protocol (about 90 minutes total)

1. New sandbox save on 42.22.2, same character and start, same zombie-population settings for every run. Add the GC log flag.
2. Run order: Control, then A, then B, then C. Same route each time: walk 10 minutes through the densest town, open the crafting menu and a large container, stand 5 minutes in a crowd of 100+ zombies, drive a KI5 car for 2 minutes.
3. Record: felt freezes per 10 minutes (the main number), minimum FPS from an overlay (Steam or NVIDIA), and any "Allocation Stall" / long pause in `gc.log`. Ignore differences under about 5%.
4. If a variant adds more than a few noticeable freezes over Control, drop it or lower population until it does not.
5. Bisect any remaining stutter on a copy of the save, one mod at a time, with Stutter Watch on.

## 8. Not verified

- Any FPS on this PC.
- The NPC Crew developer's 55-to-33 FPS reply and the Knox Survivors freeze reports come from workers reading Workshop comments; Steam rate-limited a re-check, so they are single-read.
- NPC Crew and Knox sandbox option names for NPC caps and simulation distance (not readable without installing).
- 42.22.2 status of tsarslib, ATA ports, KI5 cars, Tempo, Undying Optimizer.
- Whether Knox Survivors' data API that EmpireCommand reads survived its September runtime rebuild.
- The 42.22.2 animal-facing crash (one source only).
