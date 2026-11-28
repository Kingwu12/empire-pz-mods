# Riverside base and waypoint travel (28 Nov 2026, B42.22)

King's base pick: the Riverside police station, fire station and post office compound by the lake
(map tooltip `6032x5238`, cell 23x20). Chain-link fences and water on the sides, everything a base needs
inside. The compound is about 6,200 tiles from Echo Creek, so we travel by waypoint instead of driving.

## Using it (`EmpireQoL/42/media/lua/client/18_Waypoints.lua` + `20_TravelMenu.lua`)

- **Numpad 1 opens the Travel window** (28 Nov 2026, King: "just make a better one, allow me to input coordinates
  and save places"). Top: where you are, a tick box "Take the Tatra815 along" (only shown when a truck qualifies),
  **Go Home** and **Back to where I left from**. Middle: your saved places with coordinates, distance and a "truck
  spot" tag; click one to select it (it fills the form below), double-click or **Go to place** to travel, **Delete**
  asks twice and Base can't be deleted. Bottom: **X / Y / Z + Name** form: **Go to coordinates**, **Save coordinates**
  (saving under an existing name edits that place), **Save my spot here** (also keeps the truck's parking spot).
  Z empty = ground floor. The map tooltip shows a spot as `6032x5238`: type 6032 and 5238.
- **Shift + Numpad 1** is the old one-press loop: away from the base it takes you home (the waypoint called `Base`);
  at the base it takes you back to where the last trip started, truck parked on the exact spot you left it.
- **Numpad 0 opens the Empire menu** (`21_EmpireMenu.lua`): the Travel window, sort, find, corpse loot, top-off
  mags, auto-chores on/off, set / show / hide the base zone, and the cheat windows, each as a button with its key.
- Right-click the ground > **Empire: Travel** still lists every waypoint ("Go to X with the Tatra815" / "on foot"),
  "Back to where I left from", "Save a waypoint here...", "Delete a waypoint", and now "Open the Travel window".
- **From the world map (no need to be there):** open the map, right-click a spot > "Empire: Travel here" (or "with the <truck>", or "Save a waypoint here..."). Vanilla only offers "Teleport Here" on the map in debug mode; this works without debug. Save a waypoint named `Base` from the exact parking lot on the map to replace the seed.
- A first-run waypoint `Base` is seeded at the map-tooltip coordinates (6032, 5238). It has no truck spot yet.
- **Which truck comes:** the one you sit in, or the last vehicle you got into if it is within 14 tiles. From the
  right-click menu and the Travel window the nearest vehicle within 8 tiles can be picked too. A random wreck is never
  taken by Shift+Numpad 1. A vehicle with a trailer must be detached first.
- **Saving a truck spot:** stand beside (or sit in) the truck, parked where you want it, and use **Save my spot
  here** (or right-click > Save a waypoint here). Saving again under the same name updates it. With a truck spot, the
  truck lands exactly there and you land beside it on the same side (or are put back in the driver's seat if you were
  driving). Without one (typed coordinates, map points), the truck keeps its layout around you.
- Blocked while a zombie is chasing or very close. If the arrival square is water, a wall or a tree you are
  moved to the nearest free tile. After a truck arrives at the base the auto-chores unload it into base storage.
- Waypoints are saved in the world (ModData `EmpireWaypoints`): they survive death and a new character.

**UI references (King's rule: copy proven designs).** Travel window: the waypoint screens of map mods (Xaero's
World Map / Minimap: list of places with coordinates and distance, picking one fills an edit form with X / Y / Z and
name, saving under the same name edits it) plus TomTom-style typed coordinates. Empire menu: the quick-actions
panel of mod menus (short grouped verbs, key written on the button). Both are built from vanilla ISUI classes
(`ISCollapsableWindow`, `ISScrollingListBox`, `ISTextEntryBox`, `ISTickBox`, `ISButton`), checked against the
42.22.2 Lua. Mock-tested; how it looks is judged in the game (clipped text, spacing).

## How the truck comes along

No vanilla Lua moves a vehicle. The game jar exposes `BaseVehicle.setWorldTransform(Transform)`, whose
bytecode calls `Bullet.teleportVehicle(id, x, y, z, quat)`: the engine's own physics teleport. We shift the
transform origin by the world delta and call it in the same call as `IsoGameCharacter.teleportTo` (which also
steps you out of the truck), before the old area unloads. A short OnTick (at most 15 s) then finds the truck by
id near its target (it may be a fresh object loaded from the vehicle database), seats you, and reports.

**First real trip (28 Nov 2026, console.txt):** the truck did move, but landed 69.3 tiles from its target (about
49 tiles off on each axis) and the old code reported "did not come along". Cause (probable): the physics frame
re-centres when the player teleports, so the shifted origin is read back with a different offset. Fix: the
arrival check now measures where the truck really is once the destination has loaded and shifts it again by the
error (up to 3 times, `VEHICLE_FIXES`), then looks again. The log shows every step:

- `move first/fix N: world (x,y,z) physics origin (...) shifted by (...)`
- `check N: vehicle ... found at (x,y), D tiles from target (tx,ty) fixes=F`
- `fix N: ... was D tiles off at (x,y); shifted onto (tx,ty)`

If it still ends away from the target the message now says how far it is and where (it no longer claims the
truck stayed behind). Mock-tested with a re-centring physics frame; not yet seen in the real engine.

## First trip, step by step

1. Quit the game. On the PC: `git pull` in `C:\Users\user\Zomboid\mods` (or copy `18_Waypoints.lua` and
   `13_AutoChores.lua` into `EmpireQoL/42/media/lua/client/`).
2. Load the save. At Echo Creek (with or without the truck) right-click > Empire: Travel > "Save a waypoint
   here..." and name it `Echo Creek` (stand beside the truck to save its spot too).
3. Numpad 1, then **Go Home** (tick "Take the Tatra815 along"). You arrive at the seed `Base` spot. Look around: if it is inside a building or fence, walk to the
   compound's open parking area, park the truck there, and save a waypoint named `Base` (it replaces the seed).
4. Numpad 1 > **Back to where I left from** returns to Echo Creek with the truck; **Go Home** brings you back.
   (Shift+Numpad 1 does the same in one press.)

## Making the compound a base

1. Paint the **base zone** over the compound with EmpireZones (right-click > zone tools): the fenced area, plus
   the dock where the truck parks. Base storage, sort, auto-unload and the crew all key off this zone.
2. **Player builds**: `ZombieLore.ThumpOnConstruction` is `true` in the EmpirePlay preset, so zombies can break
   what you build. Right-click the ground > **Empire: Cheats > Zombies attack my walls** flips it to `false` in the
   live world (no debug mode needed; it is the same call the game's own sandbox panel makes). Map fences are not documented as indestructible: close the
   gate gaps with player builds and re-check the fence after the first night.
3. Storage: welding crates (level 2 = 80 capacity) along a wall for ammo (about 28 Marz 7.62 cartons each),
   metal shelves for the rest. The truck beds (Tatra 815 bed 850) are the transport, not the storage.
4. Crew (NPC Crew, up to 12): they work only while loaded near you (about 76 tiles), so they pause while you are
   away on a trip and resume when you return. They do not follow a teleport.
