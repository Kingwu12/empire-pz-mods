# Project Zomboid B42.22: mods and vanilla features that automate chores (research, 2026-11-26)

Scope: what already exists on B42.22 (stable since 2026-11-09; 42.21 selectable) that automates or removes micromanagement, judged for performance and fit next to King's own Lua mods (EmpireQoL, EmpireSortAll, EmpireZones, EmpireProduction; repo `Kingwu12/empire-pz-mods`). Nothing was installed or subscribed.

Evidence grades used below:
- [V] verified: Steam API fields (date, size, subs), official patch notes, source code I read, or an author's own statement in comments.
- [A] anecdote: one or a few user comments. Real, but not measured.
- [P] promotional: the mod page's own claims ("light", "fast", "100% vanilla"). Not evidence.
- [U] could not verify.

Workshop URL pattern for every id below: `https://steamcommunity.com/sharedfiles/filedetails/?id=<ID>`. Dates are the Steam API `time_updated`. "Subs" is current subscriptions from the API.

---------------------------------------------------------------------------------------------------

## 0. Bottom line

1. Nothing on the Workshop does what King wants end to end ("sort automatically, on arrival, with no button"). Every sorter I found is button-triggered, walk-to-container, or pipe/drop-box based. EmpireSortAll is already ahead on the one-button case; the gap is the trigger. Make our sorter fire by itself (container close, arriving in a base zone, drop into a "drop box" container) and steal the ideas below. KEEP-IT-OURS.
2. Proven, cheap, USE-THEIRS items: Tidy Up Meister (2769706949), Better Sorting (2313387159, data only), Rain Wash (3813773958), Better Corpse Burning (3790089095), Auto Mechanics/Tailoring/Cook/Reload by the same author (3387539308, 3388183573, 3388721641, 3389448389), Automatic Refueling (3632134603, with one Viewpoint caveat), Farming Zone (3838784593, test overlap with EmpireZones).
3. NPC chore workers: NPC Crew (3800132623) is the only Lua-only mod with real colony jobs. It costs FPS and needs Bandits NPC. Treat as an opt-in bake-off, not a default. Knox Survivors, Project A-Life, Project Remnants: AVOID for this goal.
4. Vanilla already removed some chores (section 8). It has no auto-sort, no labels, no NPC workers.
5. Measure before adopting: Stutter Watch (3823894801) is a small diagnostic mod that charges frame time to the mod, file and function. Use it on our own modules and on any adopted mod. The only hard stutter number I found (Better Containers, about 1 s in one call with a huge stored-item count) came from it.
6. Shared pitfall for our own sorter and vacuum: the same vanilla error `hasTag of non-table: null` in `ISWearClothing.isAlreadyEquipped` shows up in both Auto Loot (Aug, 42.20.2) and Tidy Up Meister (Nov, 42.22.2) when a mod moves items while the player wears clothing. Guard against nil items in any code that transfers then equips.
7. Biggest evidence gap: no Reddit or Indie Stone forum data (blocked, section 10), and Steam comment scraping was rate-limited, so stutter evidence is thin and mostly anecdotal.

---------------------------------------------------------------------------------------------------

## 1. Auto sorting, stashing, tidying

### 1.1 Candidate table

| Mod (id) | Updated | Subs | What it automates | Trigger | B42.22 status | Verdict |
|---|---|---|---|---|---|---|
| Tidy Up Meister (2769706949) | 2026-11-23 | 1.12M | Restores equipment and returns temporarily moved items after an action; fills gaps vanilla 42.8 auto-return leaves (some firearm actions, putting items back where they were on the ground) | Automatic, after actions | Updated 3 days ago, B41+B42. Comments [A]: revolver/.44 reload failure after 42.22 which the author says is a vanilla 42.22 bug (20 Nov); `hasTag of non-table` error in vanilla `ISWearClothing.isAlreadyEquipped` on 10 Nov (workaround reported: remove ALICE Belt and Suspenders); one user heard car idle engine sound across the map with it on 170+ mods (17 Oct, unconfirmed); screwdriver dismantle did not re-equip (11 Oct) | USE-THEIRS, but test firearm reload on 42.22 first. Author asks for debug-log bug reports and answers fast |
| Better Sorting (2313387159) | 2026-09-12 | 3.31M | Data only: ~60 display categories instead of "Item" | Passive | Works; author says safe to add/remove | USE-THEIRS (test against EmpireSortAll category names) |
| Better Sorting Reborn (3774523641) | 2026-08-01 | 10.5k | Same idea, "clean-room successor", B41+B42 | Passive | 42.20 stable stated | Pick one of the two, not both. Original has 300x the users |
| Tidy Up - Auto Item Placer (3841742290) | 2026-11-18 | 267 | Normal Drop becomes "walk to nearest table, lay items in grouped grid"; no table means line along wall; zombies in sight means normal drop; hold Left Alt to bypass | Automatic on Drop | Created 18 Nov, untested by crowd | Optional toy, low priority. Drops are rare in our flow. Note the zombie-in-sight guard (good pattern) |
| Smarter Storage (3290232938) | 2026-09-03 | 764k | Container button name, icon, colour, presets | Manual labelling | Fine | KEEP-IT-OURS for labels (EmpireSortAll labels). Reference for preset UI only |
| Container Tags (3066276504) | 2026-09-26 | 95.6k | Text tags on containers, faction-shared tags | Manual | Comments [A]: tags vanish or do not save on hosted coop (host IP changing), reset with Open All Containers (3465040406), not supported by Project Viewpoint (context-menu based) | KEEP-IT-OURS (we have labels tied to sorting) |
| Auto Sort - FR/EN (3786013783) | 2026-08-22 | 136 | Mark container with categories, press RANGER, character really walks to each marked container nearby and deposits; auto-detects category of empty container; presets; per-item "never sort" mark | Button | Few users | Ideas only (presets, per-item exclude) |
| Categorical Auto Sort (3803953826) | 2026-10-08 | 296 | Input crate: dump mixed items, right-click "sort contents automatically"; empty crates get named by category; full category gets a new empty overflow crate; per-player range 5-30 tiles; vehicle trunk as source (v1.5.0); recipe button pulls missing ingredients from crates within 25 tiles | Button on input crate | Active (Oct) | Ideas: overflow crate, input crate |
| Ente's Auto Sorter (3827432728) | 2026-11-07 | 2.76k | "One click": empties pockets, backpack and car into right containers, fetches items back | Button | 7 MB, newer | KEEP-IT-OURS. Overlaps EmpireSortAll |
| Stockroom - Auto Unload (3830007154) | 2026-11-21 | 567 | Right-click container, set up storage by 22 categories or exact items; right-click car or press V, Unload vehicle, character does trips until empty | Button | Updated 5 days ago | Idea: trunk unload with trips and zombie stop. KEEP-IT-OURS |
| Loot Hauler NPC (3834665011) | 2026-11-17 | 75 | Drop box plus a hired NPC who sorts the box contents into containers you mark "storage" with category filters; exact items beat categories | Automatic after you drop in the box | Brand new, tiny base; 14 Nov comment: not compatible with Companion Dogs NPC fix, the dogs attack the hauler (dedicated MP) [A] | Best model for "automatic": drop box + worker. Needs NPC engine (zombie body). Not recommended to run; copy the model with no NPC (instant move or timed action) |
| AutoSort Network (3815138688) | 2026-10-12 | 135 | Pipes link containers with filters (whitelist first, catch-all last); overflow chains; "Sort Whole Network" one click; optional request boxes to call items from every chest | Automatic when items change | New, 135 subs | Strongest design for true automation. Author claims event-driven ("server only works when something changes", big piles spread over seconds) [P]. Source not read. Steal the model |
| Rob's Smart Storage (3791930234) | 2026-09-12 | 4.08k | Item pipes and splitters, per-link filters (whitelist/blacklist/category/item), transfer speed 1x-30x | Automatic | Fine | Same family. 30x speed multiplier option is a red flag for per-tick cost [U] |
| Neat Storage Networks - Area Edition (3792546519) | 2026-09-03 | 382 | PC terminal, area-based storage networks, Smart Deposit/Smart Sort with previews, server-authoritative MP | Terminal actions | v1.2.0 | AVOID for SP (heavy model, small base). Earlier doc already lists Neat family as avoid |
| Connected Base (3836322561) | 2026-11-08 | 569 | Applied-Energistics style: storage towers + powered deposit crate; tablet search; Connected Crafting adds crafting from towers; needs a tablet mod and a base area; 22 MB | Automatic deposit crate | New | Interesting model (deposit crate), but adds new items, tablets, power. KEEP-IT-OURS |
| Safehouse Storage Manager (3778481720) | 2026-08-13 | 750 | Chinese enhancement patch for Safehouse Inventory: "store" button finds suitable box, walks, deposits; prefers box with same item | Button | Depends on stale parent | AVOID (parent stale) |
| Safehouse Inventory (3740163599) | 2026-06-09 | 6.47k | One tab for the whole safehouse, cook/craft from the whole base (character walks to crates), drag onto tab to auto-put-back, doors you open close behind you, house badge on items you already own | Manual drag, passive tab | Last update 2026-06-09, five months before 42.22; B42.22 untested [U]. Comments [A]: auto-close-door breaks multi-tile garage doors (7 Sep, 27 Sep, 16 Oct); opening the tab with ~2000 weight of stored items tanks FPS (1 Nov); SP error on View Safehouse because `getRole()` is nil outside MP (29 Sep, 13 Oct); MP zones did not work for non-creators (26 Sep) | AVOID. Overlaps our registry; stale and buggy. Do not copy its door auto-close without handling multi-tile doors |

### 1.2 How the proximity/safehouse tab family is built (source read)

Source: https://github.com/DevL0rd/Zomboid-ProximityInventory (the 3740165370 fork; the original is `mxswat/pz-ProximityInventory`, still found on GitHub code search).
- It hooks the vanilla B42.20 event `Events.OnRefreshInventoryWindowContainers(invSelf, state)` with states `begin`, `buttonsAdded`, `end`. [V, source]
- In `buttonsAdded` it builds a synthetic container and calls `getItems():addAll(items)` over every container in `invSelf.backpacks` (the vanilla loot-panel container set). Scan radius is therefore the vanilla loot-panel reach, not a custom radius. [V]
- `ISInventoryPage:update()` runs every frame while the proximity tab is open and re-applies `setHighlighted` to every source container. This is the one per-frame cost I found. [V]
- It wraps `ISInventoryTransferAction` update/perform in `pcall`. [V]
- Cost scales with number of items in nearby containers (the merge copies item references on every refresh). Big corpse piles or a packed warehouse are the worst case. [inference from the code]

Why this matters for King: our EmpireQoL/EmpireSortAll could use the same event to trigger auto-sort cheaply (one handler on `end`), while avoiding the per-frame highlight loop and the full `addAll` merge.

### 1.3 Performance evidence for tab-style mods
- Proximity Inventory fork (3740165370, 42k subs, updated 2026-06-09): per-frame highlight loop and merge copy are code facts [V]. User comments [A]: taking items from a car trunk makes the character run to the car door and jitter (4 Aug, 3 Oct); "so many bugs" (10 Sep, 10 Oct, 11 Nov); a MP file-mismatch error (7 Aug). A separate fix mod exists, "Proximity Inventory - Vehicle Fix" (3797176052, 1.3k subs). No FPS numbers.
- Proximity Inventory B42.20+ (2847184718, 2.28M subs, updated 2026-08-30): not re-read. King's own earlier doc (`docs/PLAYTHROUGH-B42.22.md`) lists it as "maybe (overlaps EmpireQoL)".
- Better Containers (3586216562, 118k subs, updated 2026-10-30, 15.7 MB): the best hard number I found. On 26 Oct a user posted output of the profiler mod Stutter Watch (3823894801): BetterContainers Lua cost 2161 ms in the game-update step over 2 calls, worst call 1089 ms, "while trying to move in front of a HUGE amount of stored items" [A, user-posted profiler output, cut off in my scrape]. The author said he could not reproduce it and discounted it because the user ran Java mods; the user replied the lag is the same without the Java mod. 12 Nov: another user reports FPS drops when transferring stacked items with nested-container/proximity features on. 25 Oct: the author changed it to touch only DisplayCategory, which broke other sorting mods that read its categories. Conclusion: a real cost that scales with stored item count; consistent with the earlier "huge item counts" note.
- Neat Crafting (3502080466, 898k subs, 2026-11-19, 4.3 MB, needs NeatUI Framework 3508537032): comments [A] say batch crafting breaks or times out when thousands of input items (about 3000) are nearby (a 900-frame wait expires while returning unused inputs); the "all" toggle runs once then sticks; it moves inputs into the inventory instead of using them in place (wasted time). Author v1.7.8 on 19 Nov improves interrupted/cancelled actions and answers quickly. Cost scales with nearby item count.
- Take-away: every tab/crafting UI that merges containers has a cost proportional to nearby item count. That supports a designed-in cap or per-zone scope for our own registry, and measuring with Stutter Watch before and after.
- Stutter Watch (3823894801, 322 subs, 2026-10-21, 82 KB, Build 42): diagnostic mod; logs frames slower than 40 ms and charges Lua time to mod, file and function; writes `Zomboid/RukxStutterWatch/stutters_<date>.log`, `summary_<date>.log`, `totals_latest.txt` [V, description]. Cheap way to profile our EmpireQoL modules and any adopted mod. I did not read its source, so its own overhead is unverified.

---------------------------------------------------------------------------------------------------

## 2. Hauling and looting automation

| Mod (id) | Updated | Subs | What | Evidence | Verdict |
|---|---|---|---|---|---|
| Auto Loot (3392699932) | 2026-10-30 | 65.5k | Auto-picks up configured loot (filters, priorities, instant pickup) | Comments [A]: items bound/stuck after pickup when combined with a PDA selling mod (23 Nov); cannot be told to ignore main inventory (14 Oct); conflict with Knox Immersion (Aug); `isAlreadyEquipped` hasTag nil error on inventory transfer plus clothing wear (Aug); duplicate-bug reports in MP only | AVOID as a default. Our corpse vacuum plus sort covers it. Bug trail is long |
| Auto All (3777237134) | 2026-11-08 | 59k | Modules: cook, medicine, read, VHS, rip clothes, tailoring, mechanics, farming ("tend crops"), disinfect, exercise; speed up to x40 | Comments [A]: any follower mod's NPC is counted as a zombie, which stops auto tasks (21 Oct, 2 Nov, mention of Stay With Me); "zombie nearby" false positives; reload errors with slings (Nov); speed does not return to normal after some tasks; farming says "nothing to do" while plants are dry (25 Nov); crashes with Viewpoint (17 Oct) | USE-THEIRS for a few modules only if no NPC mod is active. Pick the same-author "real one" series instead (see 4) |
| Mulch (3795893288) | 2026-09-21 | 6.98k | Tow a wood chipper to a corpse pile, feed bodies, get compost; loud | Adds vehicle item (25 MB). [P] | Optional. Our corpse vacuum is cheaper |
| Better Corpse Burning (3790089095) | 2026-10-29 | 62.9k | Faster/safer burning of piled corpses, fire duration setting, protects favourite fire starters | Large, recent user base [V] | USE-THEIRS if burning is the cleanup route |
| Stockroom (3830007154) | see 1.1 | | Trunk unload in trips | | idea only |

Trunk and trailer unload: Ente's Auto Sorter (3827432728), Stockroom (3830007154) and Categorical Auto Sort (3803953826, trunk as source in v1.5.0) all do car-to-containers by walking trips on a button press. None triggers on arrival. Vanilla has nothing here.

---------------------------------------------------------------------------------------------------

## 3. Using nearby containers

| Mod | Approach | Scan mechanism | Stutter | Verdict |
|---|---|---|---|---|
| Proximity Inventory (2847184718 and 3740165370) | One merged loot-window tab | Vanilla `backpacks` set via `OnRefreshInventoryWindowContainers`; per-frame highlight loop [V] | Per-frame loop and merge cost [V code]; user reports [A] | KEEP-IT-OURS (our registry does base-wide, event-driven) |
| Safehouse Inventory (3740163599) | Merged base tab, walk-to-crate crafting | Safehouse zone scan; source not read | [U] | AVOID (stale 2026-06-09) |
| Logistics Zones (3786332184) | Define up to 40x40 zone; contents available for craft/build; SP only; disables in MP | Zone scan [P] | A commenter (24 Aug) guesses it "could save performance, not like others smart containers and proximity stuff" [A, speculation, not measured] | KEEP-IT-OURS. King's EmpireZones plus registry covers it. Earlier doc lists as avoid. Positive user comments: "lets you craft without needing containers nearby" |
| Zone Crafting (3786669030) | Home Inventory zones feed crafting; character walks and collects, returns to start; prefers inventory items | Zone based | 1,077 subs [U] | KEEP-IT-OURS |
| Vehicle Repair Overhaul + Nearby Containers (3792113124) | VRO fork that reads nearby containers | Client repair logic | 203 subs [U] | KEEP-IT-OURS (we have vehicle repair from base) |
| Neat Crafting (3502080466) | Crafting UI with ingredient choice and queue (up to 1000) | Needs NeatUI | [A] earlier doc | AVOID, but note a contradiction inside our own docs: the PLAYTHROUGH doc lists Neat Building/Crafting as "avoid", while our `44_CraftFromBase` shims target the Neat panels (`suite-audit.md`). Settle which one before building more on 44 |
| Common Sense B42.20+ (3750253491) | Omnibus: pry open doors/windows/vehicles with crowbars, collect garbage off the ground, reload all magazines at once, ammo counter, open cans with scissors, replace dirty bandages, equip from ground, easier fuel transfer | None container-scan; no "nearby containers" | 410k subs; author says "no incompatibilities" [P] | Careful: overlaps vanilla 42.22 crowbar forcing of locked doors (patch notes). Our `EmpireQoL` has corpse vacuum and ammo features, check duplicates before enabling |

---------------------------------------------------------------------------------------------------

## 4. Survival chores

| Chore | Mod (id) | Updated | Subs | Notes | Verdict |
|---|---|---|---|---|---|
| Auto-train mechanics | Auto Mechanics (3387539308) | 2026-08-17 | 461k | Right-click part, Train Mechanics; needs tools and book. Description says "the real one, not the AI copies" [P] | USE-THEIRS |
| Tailoring | Auto Tailoring (3388183573) | 2026-11-04 | 253k | One button trains tailoring and patches holes; inventory handled automatically incl. equipped bags | USE-THEIRS |
| Cooking | Auto Cook (3388721641) | 2026-11-02 | 157k | Evolved recipes: right-click bowl/pan; config in Character Info "Cook" tab | USE-THEIRS (low risk). Overlaps King's eat-all only partly |
| Reload training | Auto Reload (3389448389) | 2026-09-07 | 175k | Trains reload speed while walking | USE-THEIRS, if wanted |
| Refuel | Automatic Refueling (3632134603) | 2026-10-13 | 47k | Walk away while pump runs; stops when full or car moved | USE-THEIRS. Conflict with Viewpoint/Project Viewpoint QOL (radial menu harvest chain) was fixed on a staging build per author 12 Oct; some users still report MP error notifications to other players. SP is fine [A] |
| Auto-eat | Auto-Eat (3795435563) | 2026-10-06 | 274 | Eats only the needed partial portion of safe, ready-to-eat solid food at 10 % hunger, background, no animation. Few users | Trial. Or add the same trigger to our eat-all (KEEP-IT-OURS) |
| Auto-drink | Vanilla; Auto-Drink Revert (3737205872, 8.97k subs, 2026-11-23) | | | Vanilla 42.19 changed auto-drink to "water only"; Revert restores old behaviour; Auto Drink Animation (3803045908, 2.3k subs, 2026-11-08) gives it a 4 s animation | Optional |
| Fishing | Auto Fishing (3827179765) | 2026-10-28 | 180 | Auto spot, bait, cast; modes: one attempt, until depleted | Trial. Karas Fully Automatic Fishing (3642554378, 9.7k subs) last updated 2026-01-16; comments 3 and 8 Aug ask for an update; context menu shows raw references on 42.19 [A] | Prefer the newer, avoid Karas |
| Wash blood | Rain Wash (3813773958) | 2026-10-29 | 10.1k | Rain slowly washes blood off ground, walls, vehicles, and characters outdoors; only what rain touches; 51 KB | USE-THEIRS (tiny) |
| Lights | AutoLights (3737087835) | 2026-10-29 | 1.35k | Time- or sunset-based on/off for lights; saves generator fuel and bulbs | USE-THEIRS (trial) |
| Doors | Safehouse Inventory closes doors you open (see 1.1) | | | Standalone auto-close-door mods exist (tiny) but were not individually vetted | [U] |
| Rain barrel | Rain Barrel Pour All (3768913712, 838 subs, 2026-07-21) | | | Button to pour all water into barrel | Optional, tiny |
| Generators | Nick's Generator Manager (3794099205, 1.97k subs) | | | Pin appliances to specific generator | Optional |

Keep in mind: Auto All, the "Auto X" family and others check for "zombie nearby" and treat NPC mod bodies as zombies [A, several comments].

---------------------------------------------------------------------------------------------------

## 5. Farming and animals (B42 husbandry)

| Mod (id) | Updated | Subs | What | Evidence | Verdict |
|---|---|---|---|---|---|
| Farming Zone (3838784593) | 2026-11-25 | 7.5k | Register fields as zones, one list row per crop, water/fertilize/treat/harvest/remove from the list; shows only what vanilla plant info shows | Same author line as Livestock Panel Plus (below); updated yesterday; comment 23 Nov says Fruity Farmer fruit trees tested briefly [A] | USE-THEIRS, test overlap with EmpireZones (we own freeform zones) |
| Batch Farming (3721577741) | 2026-09-28 | 2.2k | Drag-select area, auto-detect each tile's need, chains till, sow, water, fertilize, harvest, disease | [P]; tiny user base | Trial or KEEP-IT-OURS (EmpireProduction nodes) |
| Water Pump Irrigation (3791943076) | 2026-09-03 | 1.3k | Smart irrigation: connect rain barrels to plots | [P] | Optional |
| Livestock Panel Plus (3783623999) | 2026-11-02 | 103k | Status table for the whole herd from the livestock zone panel, tend from rows | Author fixed a rebuild-per-frame issue in v1.17 ("table rebuilt only when needed" for many animals) [V, description]. Earlier lag reports: 24 Oct "LOT of lag with many animals"; 25 Oct 100 animals spikes; author 200 chickens no lag [A]. Two overlapping livestock zones make panel lose animals (author-confirmed 13 Nov) [V] | USE-THEIRS with: no overlapping zones |
| ST Additions - Better Hutches (3721829036) | 2026-11-24 | 141k | Woodchip sack slows hutch dirt; shows fertilized eggs; sandbox options | Updated yesterday | USE-THEIRS |

Vanilla 42.22.2 note: animal fixes for animals dying when the cell unloads and chickens in full hutches deleted (patch notes) [V].

---------------------------------------------------------------------------------------------------

## 6. NPC jobs

NPC mods use zombie bodies (IsoZombie). Rule from the authors themselves: one NPC mod per save [V, A-Life and ProjectSurvivors descriptions]. They also confuse any mod that has a "zombie nearby" safety check (Auto All, ours if we have one).

| Mod (id) | Updated | Subs | Needs | Jobs that exist (V = description; works = user reports) | Performance evidence | Verdict |
|---|---|---|---|---|---|---|
| NPC Crew (3800132623) | 2026-11-24 | 7.9k | Bandits NPC (3268487204, 1.03M subs, updated 2026-11-21); Lua only | Beacon, zones; sorters filing loot into category crates; unload-car zones; farmer, animal keeper, cook, builder, tailor, reloader, blacksmith, hunter, fishing, forestry, water, corpse cleanup and burning, loot runs [V description]. Walkthrough page 3822355628 exists | Author says the server-side check loops over all loaded zombies about 4 times per second [V, author statement]; one user claimed 55 to 33 FPS [A, single read]; "No hostile bandits" option removes raiders/camps (cuts simulated entities) | USE-THEIRS only as a bake-off with low population and no hostile bandits. First NPC option |
| Stay With Me (3800989007) | 2026-11-18 | 35k | none (Lua) | One companion with work menu: cut trees, clear plants, move corpses, loot, put loot away, gardening, animal care (v0.6.8) | Author notes: update-rate cap (60/50/40/30 Hz) added 11 Nov, call reductions up to 66 percent; no FPS complaints seen in newest 50 comments (sibling research) | USE-THEIRS if one helper is enough. Best performance work |
| ProjectSurvivors (3810955553) | 2026-11-25 | 2.4k | Lua; SP only; WIP | Guard, carry corpses, scavenge, chop, saw planks, board windows, plant/harvest, fishing, cook, tend animals, empty trunks, mechanic | Nothing stated; author says "only roughly tested" | Promising but small. Bake-off candidate |
| Knox Survivors (3749727604) | 2026-11-11 | 22.2k | Java loader (ZombieBuddy) | Recruit, base jobs, schedules, off-screen sim | Freezes every 7-15 s in Nov comments [A]; author conceded population system perf problems [V per sibling research]; rewrite in progress | AVOID (Java, TIS says Java mods unsupported) |
| Project A-Life (3803984183) | 2026-11-25 | 336k | Lua, 489 MB | World sim, factions, companions (up to 5); settlers/defended base is roadmap 1.6 | Comments: "lagged my pc out too much" [A]; no NPC cap documented | AVOID for chores (it is a world sim, not a chore mod) |
| Project Remnants (3738362476) | 2026-09-23 | 45.8k | Java agent plus admin installer .exe | Party and safehouse jobs | Workshop build broken on 42.22 (sibling research) | AVOID |
| True Companions (3751199292) | 2026-08-25 | 34k | Bandits NPC | Beacon recruits | Comments call it dead (sibling research) | AVOID |
| Loot Hauler NPC (3834665011) | 2026-11-17 | 75 | NPC engine | Drop box sorter | tiny | Idea only |
| SettleZ (3811901499) | 2026-11-25 | 1.3k | WIP | Story/settlement generator, 18 MB | none | Not a chore mod |

Note on the earlier King doc ranking (A Bandits+NPC Crew, B Knox, C Stay With Me): I agree with A first and C as the cheap fallback; I rank Knox last of the three because of the Java loader and the freeze reports.

NPC Crew details to verify before trust: `https://steamcommunity.com/sharedfiles/filedetails/?id=3800132623` comments (the WebFetch banner "removed for violating Steam guidelines" on NPC Crew and ProjectSurvivors contradicts the API, which says banned=0, visibility=0, updated 24/25 Nov. I treat that as a fetch misparse).

---------------------------------------------------------------------------------------------------

## 7. Which of King's mods stay ours, and what to steal

KEEP-IT-OURS: smart sort, base container registry, craft/build/vehicle-repair from base storage, corpse vacuum, find-item-in-base, zones, production nodes, zombie ammo drops, one-click eat-all, auto engine start. No found mod beats these as a set, and all the rivals are button-triggered or tab-based.

Ideas worth stealing, in order of payoff:
1. Make EmpireSortAll automatic: fire on container close, on entering a base zone, or when items land in a designated "drop box" container. Use `Events.OnRefreshInventoryWindowContainers` (state `end`) as a cheap trigger instead of per-frame polling. Add a cooldown and a zombie-in-sight guard (Tidy Up Auto Item Placer does the guard).
2. Drop box plus worker model (Loot Hauler NPC, Categorical Auto Sort input crate, Connected Base deposit crate): one container is the intake, everything routes from it. No NPC needed; use a timed action or a batched move.
3. Overflow chain / new empty crate for full categories (Categorical Auto Sort, AutoSort Network).
4. Per-item "never sort" mark and presets (Auto Sort 3786013783).
5. Trunk unload by trips with zombie stop (Stockroom).
6. A per-container "storage" flag that makes the container count for crafting (Safehouse Inventory and Logistics Zones both do this by zone; ours does it through the registry, so only the per-container flag is new). Note: "Quartermaster" in our own suite is `44_CraftFromBase`, not a Workshop mod (`suite-audit.md`).
7. Door auto-close (Safehouse Inventory does it): trivial to add.

---------------------------------------------------------------------------------------------------

## 8. Vanilla B42.20 to 42.22 features that already remove chores [V, official patch notes via Steam news API, appid 108600]

- 42.8: items temporarily moved for an action are automatically returned (described in Tidy Up Meister's page; patch note not re-read).
- Auto-drink is vanilla; 42.19 narrowed it to water-only sources (per the Auto-Drink Revert page, a mod author's account of the Java change, not a patch note I read).
- 42.20.0: "Reworked transferring stackable items", "significantly reduce the time required to transfer large stacks". Also fixed items not auto-transferring on entering a vehicle seat with more than 5.0 encumbrance.
- 42.22.2: more actions can be taken while walking: open/close umbrella, rip clothing/sheets, open ammo boxes (50, 20) and shotgun shell boxes, remove/insert battery, extinguish candle/lantern, remove/insert propane bottle, add/take cigarette from pack.
- 42.22: vanilla crowbar forcing of locked doors/windows/gates (overlaps Common Sense pry feature); animal fixes (cell-unload deaths, hutch deletions); Sow/Harvest movement fix on furrows.
- 42.21: bag re-equip feature (Auto All's exercise module did not follow it, per a comment).
- Not in vanilla: auto-sort, container labels with automation, NPC workers, auto-eat.

---------------------------------------------------------------------------------------------------

## 9. Performance summary

- Cheap, passive: Better Sorting (data), Rain Wash (51 KB), Auto-Eat (150 KB), Tidy Up Meister (event driven).
- Medium: Proximity-style tabs (per-frame highlight loop, merge copy on every refresh) [V code].
- Scales with entities: all NPC mods. NPC Crew author states a 4 Hz loop over all loaded zombies [V author statement].
- UI rebuild risk: Livestock Panel Plus with many animals (improved in v1.17; earlier lag reports).
- Best hard number: Better Containers 2161 ms Lua in two game-update calls (worst 1089 ms) with a huge stored-item count, from a user-posted Stutter Watch log [A]. Safehouse Inventory: FPS tanks opening a tab with ~2000 weight of items [A]. Neat Crafting: batch crafting times out near ~3000 input items [A].
- Unmeasured: every other FPS claim in this doc is an anecdote. No controlled benchmark of any candidate was found.

---------------------------------------------------------------------------------------------------

## 10. What I could not verify

- Reddit (403), Indie Stone forum (403 to curl), pzwiki and projectzomboid.com via WebFetch (403): zero evidence from those sites. WebSearch with reddit.com also blocked.
- Steam comment pages returned HTTP 429 repeatedly. Comments (newest 50 to 100, first ~300 characters each) were read for 14 mods: Auto All, Auto Loot, Automatic Refueling, Karas Fishing, Farming Zone, Livestock Panel Plus, Logistics Zones, Better Containers, Tidy Up Meister, Neat Crafting, Container Tags, Proximity Inventory fork, Safehouse Inventory, Loot Hauler NPC. Not obtained: Better Sorting (0 comments returned), Better Sorting Reborn, Smarter Storage, Proximity Inventory B42.20+ (2847184718) and every mod with under 300 subs.
- Source code was read only for the Proximity Inventory fork. All other "how it works" notes come from mod descriptions [P].
- Mod change notes pages (429): last-updated dates come from the API, not changelogs.
- The "55 to 33 FPS" NPC Crew figure is a single comment.
- B42.22 compatibility is inferred from update dates (updated after 9 Nov counts as likely working). Stale ones: Safehouse Inventory and its patch (Jun and Aug), Karas Fishing (Jan), Proximity Inventory fork (Jun).
- Standalone auto-close-door and "fast ripping clothes" mods: not individually vetted; vanilla 42.22.2 now lets you rip while walking.

---------------------------------------------------------------------------------------------------

## 11. Source list

- Steam Workshop API (POST): `https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/` for all ids above.
- Official news and patch notes: `https://store.steampowered.com/news/app/108600` (42.20.0, 42.21 stable, 42.22 pre, 42.22.2 stable 2026-11-09; "A Note on Java Mods and Modding" 2026-10-21).
- Proximity Inventory fork source: https://github.com/DevL0rd/Zomboid-ProximityInventory ; original: https://github.com/mxswat/pz-ProximityInventory
- King's repo: https://github.com/Kingwu12/empire-pz-mods (README, `docs/PLAYTHROUGH-B42.22.md`).
- Sibling research in the same scratchpad: `research-npc.md` (NPC variants, Java loader, Remnants broken on 42.22).
- Workshop pages: each id above at `https://steamcommunity.com/sharedfiles/filedetails/?id=<ID>`; walkthrough page for NPC Crew at id 3822355628.
