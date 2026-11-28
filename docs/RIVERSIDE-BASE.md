# Riverside base and waypoint travel (28 Nov 2026, B42.22)

King's base pick: the Riverside police station, fire station and post office compound by the lake
(map tooltip `6032x5238`, cell 23x20). Chain-link fences and water on the sides, everything a base needs
inside. The compound is about 6,200 tiles from Echo Creek, so we travel by waypoint instead of driving.

## Using it (`EmpireQoL/42/media/lua/client/18_Waypoints.lua`)

- **Right-click the ground > Empire: Travel.** Lists every waypoint ("Go to X with the Tatra815" / "on foot"),
  "Back to where I left from", "Save a waypoint here...", "Delete a waypoint".
- **Numpad 1** is the one-press loop. Away from the base it takes you home (the waypoint called `Base`).
  At the base it takes you back to where the last trip started, truck parked on the exact spot you left it.
- **From the world map (no need to be there):** open the map, right-click a spot > "Empire: Travel here" (or "with the <truck>", or "Save a waypoint here..."). Vanilla only offers "Teleport Here" on the map in debug mode; this works without debug. Save a waypoint named `Base` from the exact parking lot on the map to replace the seed.
- A first-run waypoint `Base` is seeded at the map-tooltip coordinates (6032, 5238). It has no truck spot yet.
- **Which truck comes:** the one you sit in, or the last vehicle you got into if it is within 14 tiles. From the
  right-click menu the nearest vehicle within 8 tiles can be picked too. A random wreck is never taken by
  Numpad 1. A vehicle with a trailer must be detached first.
- **Saving a truck spot:** stand beside (or sit in) the truck, parked where you want it, and save the waypoint.
  Saving again under the same name updates it. With a truck spot, the truck lands exactly there and you land
  beside it on the same side (or are put back in the driver's seat if you were driving). Without one, the truck
  keeps its layout around you.
- Blocked while a zombie is chasing or very close. If the arrival square is water, a wall or a tree you are
  moved to the nearest free tile. After a truck arrives at the base the auto-chores unload it into base storage.
- Waypoints are saved in the world (ModData `EmpireWaypoints`): they survive death and a new character.

## How the truck comes along

No vanilla Lua moves a vehicle. The game jar exposes `BaseVehicle.setWorldTransform(Transform)`, whose
bytecode calls `Bullet.teleportVehicle(id, x, y, z, quat)`: the engine's own physics teleport. We shift the
transform origin by the world delta and call it in the same call as `IsoGameCharacter.teleportTo` (which also
steps you out of the truck), before the old area unloads. A short OnTick (at most 15 s) then finds the truck by
id near its target (it may be a fresh object loaded from the vehicle database), seats you, and reports.

Untested in the real engine. Every outcome is printed as `[EmpireWaypoints]` lines in `console.txt`
(`travel to ...`, `check N: vehicle ... found X tiles from target`). Worst case the truck stays parked where you
left it: nothing is deleted. If it does, send the console lines and the transform step gets fixed.

## First trip, step by step

1. Quit the game. On the PC: `git pull` in `C:\Users\user\Zomboid\mods` (or copy `18_Waypoints.lua` and
   `13_AutoChores.lua` into `EmpireQoL/42/media/lua/client/`).
2. Load the save. At Echo Creek (with or without the truck) right-click > Empire: Travel > "Save a waypoint
   here..." and name it `Echo Creek` (stand beside the truck to save its spot too).
3. Numpad 1. You arrive at the seed `Base` spot. Look around: if it is inside a building or fence, walk to the
   compound's open parking area, park the truck there, and save a waypoint named `Base` (it replaces the seed).
4. Numpad 1 again goes back to Echo Creek with the truck. Numpad 1 once more brings you home.

## Making the compound a base

1. Paint the **base zone** over the compound with EmpireZones (right-click > zone tools): the fenced area, plus
   the dock where the truck parks. Base storage, sort, auto-unload and the crew all key off this zone.
2. **Player builds**: `ZombieLore.ThumpOnConstruction` is `true` in the EmpirePlay preset, so zombies can break
   what you build. Debug mode (`Project Zomboid DEBUG` shortcut) > right-click > Debug > Main > Sandbox settings
   lets you flip it to `false` in the live world. Map fences are not documented as indestructible: close the
   gate gaps with player builds and re-check the fence after the first night.
3. Storage: welding crates (level 2 = 80 capacity) along a wall for ammo (about 28 Marz 7.62 cartons each),
   metal shelves for the rest. The truck beds (Tatra 815 bed 850) are the transport, not the storage.
4. Crew (NPC Crew, up to 12): they work only while loaded near you (about 76 tiles), so they pause while you are
   away on a trip and resume when you return. They do not follow a teleport.
