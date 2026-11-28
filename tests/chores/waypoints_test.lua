-- Mock test for 18_Waypoints.lua (28 Nov 2026). Logic only: the real engine behaviour (does the truck really
-- come along) is settled by the [EmpireWaypoints] lines in console.txt on the first trip.
-- Run: node tests/chores/runner.js EmpireQoL/42/media/lua/client/18_Waypoints.lua tests/chores/waypoints_test.lua
local handlers = {}
Events = setmetatable({}, {__index = function(t, name)
  local e = {
    Add = function(f) handlers[name] = handlers[name] or {}; table.insert(handlers[name], f) end,
    Remove = function(f)
      for i, h in ipairs(handlers[name] or {}) do if h == f then table.remove(handlers[name], i); return end end
    end}
  rawset(t, name, e); return e end})
local function fire(name, ...) for _, h in ipairs({table.unpack(handlers[name] or {})}) do h(...) end end
local function count(name) return #(handlers[name] or {}) end

Keyboard = {KEY_NUMPAD1 = 79}
local halos = {}
HaloTextHelper = {
  addTextWithArrow = function(p, msg) halos[#halos + 1] = msg end,
  getColorGreen = function() return 1 end, getColorWhite = function() return 2 end, getColorRed = function() return 3 end}
local function lastHalo() return halos[#halos] or "" end
local mdStore = {}
ModData = {getOrCreate = function(k) mdStore[k] = mdStore[k] or {}; return mdStore[k] end}
ISTimedActionQueue = {clear = function() end}
IsoFlagType = {water = "water"}
-- context menu mock
local lastMenu
ISContextMenu = {getNew = function(_, parent) local m = {opts = {}, subs = {}}
  m.addOption = function(self, name, target, fn, ...) local o = {name = name, target = target, fn = fn, args = {...}}; self.opts[#self.opts + 1] = o; return o end
  m.addSubMenu = function(self, opt, sub) opt.sub = sub end
  return m end}

-- physics offsets: the transform origin is (worldX - OFFX, height, worldY - OFFY)
local OFFX, OFFY = 1000, 2000
local function vec(x, y, z) local v = {X = x, Y = y, Z = z}
  function v:x() return self.X end function v:y() return self.Y end function v:z() return self.Z end
  function v:set(a, b, c) self.X, self.Y, self.Z = a, b, c; return self end
  return v end
Transform = {new = function() local t = {origin = vec(0, 0, 0)}; function t:getOrigin() return self.origin end; return t end}

local world = {loaded = true, vehicles = {}, blocked = {}}
local function sqFor(x, y, z)
  if not world.loaded then return nil end
  local key = math.floor(x) .. "," .. math.floor(y)
  return {isFree = function() return not world.blocked[key] end, hasFloor = function() return true end,
          HasTree = function() return false end, hasWater = function() return world.water and world.water[key] or false end,
          getProperties = function() return {Is = function() return false end} end}
end
function getCell() return {
  getVehicles = function() return {size = function() return #world.vehicles end, get = function(_, i) return world.vehicles[i + 1] end} end,
  getGridSquare = function(_, x, y, z) return sqFor(x, y, z) end} end

local function newVehicle(id, name, x, y)
  local v = {id = id, name = name, x = x, y = y, z = 0, moves = {}, entered = nil, towing = false}
  function v:getId() return self.id end
  function v:getScriptName() return "Base." .. self.name end
  function v:getX() return self.x end function v:getY() return self.y end function v:getZ() return self.z end
  function v:setX(a) self.x = a end function v:setY(a) self.y = a end function v:setZ(a) self.z = a end
  function v:getWorldTransform(t) t.origin:set(self.x - OFFX, self.z, self.y - OFFY); return t end
  function v:setWorldTransform(t) local o = t.origin
    self.moves[#self.moves + 1] = {x = o:x() + OFFX, y = o:z() + OFFY, z = o:y()} end
  function v:setPhysicsActive() end
  function v:getVehicleTowing() return self.towing and {} or nil end
  function v:getVehicleTowedBy() return nil end
  function v:enter(seat, ch) self.entered = {seat = seat, ch = ch}; return true end
  world.vehicles[#world.vehicles + 1] = v
  return v
end

local P = {x = 100, y = 100, z = 0, chased = 0, vehicle = nil, tp = {}}
function P:isDead() return false end
function P:getX() return self.x end function P:getY() return self.y end function P:getZ() return self.z end
function P:getVehicle() return self.vehicle end
function P:getPlayerNum() return 0 end
function P:getStats() local s = self; return {getNumChasingZombies = function() return s.chased end, getNumVeryCloseZombies = function() return 0 end} end
function P:teleportTo(x, y, z) self.tp[#self.tp + 1] = {x = x, y = y, z = z}; self.x, self.y, self.z = x, y, z; self.vehicle = nil end
function getSpecificPlayer() return P end

local armed = {}
EmpireAutoChores = {armUnload = function(v) armed[#armed + 1] = v end}

local f = assert(load(SRC, "waypoints")); f()
local W = EmpireWaypoints
local n, fails = 0, 0
local function expect(name, c) n = n + 1; if c then print("PASS " .. name) else fails = fails + 1; print("FAIL " .. name) end end
local function near(a, b) return math.abs(a - b) < 1e-6 end
local function ticks(k) for _ = 1, k do fire("OnTick") end end
local function reset()
  world.vehicles = {}; world.loaded = true; world.blocked = {}; P.tp = {}; P.vehicle = nil; P.chased = 0
  P.x, P.y, P.z = 100, 100, 0; armed = {}; halos = {}
  mdStore.EmpireWaypoints = nil; handlers.OnTick = {}
end

-- 1. first run seeds Base
reset(); fire("OnGameStart")
local d = W.store()
expect("seed: Base waypoint at the Riverside compound", #d.list == 1 and d.list[1].name == "Base" and d.list[1].x == 6032 and d.list[1].y == 5238)
fire("OnGameStart")
expect("seed only once", #W.store().list == 1)
expect("OnGameStart leaves no tick handler", count("OnTick") == 0)

-- 2. save: on foot, then with a truck beside you; same name updates in place
reset(); fire("OnGameStart")
expect("save on foot", W.saveHere(P, "Echo Creek") and W.store().list[2].name == "Echo Creek" and W.store().list[2].hasV == false)
local truck = newVehicle(7, "Tatra815", 103, 100)
P.x = 106; P.y = 100
expect("save with truck near saves its spot", W.saveHere(P, "echo creek") and #W.store().list == 2
  and W.store().list[2].hasV and W.store().list[2].vx == 103 and W.store().list[2].x == 106)
for i = 1, 20 do W.saveHere(P, "wp" .. i) end
expect("list capped at MAX_WAYPOINTS", #W.store().list == W.CFG.MAX_WAYPOINTS)
expect("blank name refused", W.saveHere(P, "   ") == false)

-- 3. guards
reset(); fire("OnGameStart"); P.chased = 2
expect("chased: travel refused", W.travelTo(P, "Base", false) == false and #P.tp == 0 and lastHalo():find("Zombies"))
P.chased = 0

-- 4. travel on foot
expect("on foot travel teleports the player", W.travelTo(P, "Base", false) and #P.tp == 1 and P.tp[1].x == 6032 and P.tp[1].y == 5238)
expect("travel arms the arrival tick", count("OnTick") == 1)
expect("second trip blocked while arriving", W.travelTo(P, "Base", false) == false)
ticks(20)
expect("on foot arrival message and tick removed", lastHalo():find("Arrived at Base") and count("OnTick") == 0)
expect("back remembers the departure spot", W.store().back and W.store().back.x == 100 and W.store().back.hasV == false)

-- 5. travel with the truck you sit in: relative layout (waypoint has no truck spot)
reset(); fire("OnGameStart")
truck = newVehicle(7, "Tatra815", 100, 100); P.vehicle = truck
world.loaded = false
expect("seated travel starts", W.travelTo(P, "Base", true))
local mv = truck.moves[1]
expect("truck physics-teleported by the world delta (offsets respected)", mv and near(mv.x, 6032) and near(mv.y, 5238) and near(mv.z, 0))
expect("truck fields also written", near(truck.x, 6032) and near(truck.y, 5238))
expect("player teleported to the truck spot", P.tp[1].x == 6032 and P.tp[1].y == 5238)
ticks(60)
expect("destination not loaded: still waiting, nothing entered", count("OnTick") == 1 and truck.entered == nil)
world.loaded = true
ticks(20)
expect("loaded + truck found: driver put back in seat 0", truck.entered and truck.entered.seat == 0 and truck.entered.ch == P)
expect("arrival says it came with the truck", lastHalo():find("with the Tatra815"))
expect("unload armed on the truck", armed[1] == truck)
expect("tick removed when done", count("OnTick") == 0)

-- 6. saved truck spot + player on foot beside it: keeps the same side
reset(); fire("OnGameStart")
W.store().list[#W.store().list + 1] = {name = "Yard", x = 500, y = 500, z = 0, hasV = true, vx = 505, vy = 502, vz = 0}
truck = newVehicle(9, "Defender", 104, 100)   -- 4 east of the player
expect("on-foot with truck", W.travelTo(P, "Yard", true))
mv = truck.moves[1]
expect("truck lands on the saved spot", mv and near(mv.x, 505) and near(mv.y, 502))
expect("you land beside it, same side", near(P.tp[1].x, 501) and near(P.tp[1].y, 502))
ticks(20)
expect("not seated: not put in the seat", truck.entered == nil and lastHalo():find("Arrived at Yard with"))

-- 7. the truck does not make it across
reset(); fire("OnGameStart")
truck = newVehicle(11, "Tatra815", 100, 100); P.vehicle = truck
W.travelTo(P, "Base", true)
for i = #world.vehicles, 1, -1 do table.remove(world.vehicles, i) end   -- the engine dropped it
ticks(20 * 4)
expect("missing truck is reported, trip ends", lastHalo():find("did not come along") and count("OnTick") == 0)

-- 8. trailer refuses
reset(); fire("OnGameStart")
truck = newVehicle(12, "Tatra815", 100, 100); truck.towing = true; P.vehicle = truck
expect("towing: travel with the vehicle refused", W.travelTo(P, "Base", true) == false and #P.tp == 0 and lastHalo():find("trailer"))
expect("towing: on foot still works", W.travelTo(P, "Base", false) == true)

-- 9. which vehicle comes
reset(); fire("OnGameStart")
local wreck = newVehicle(20, "Wreck", 105, 100)
expect("random nearby vehicle is not picked by default", W.pickVehicle(P, false) == nil)
expect("menu pick finds the nearest within reach", W.pickVehicle(P, true) == wreck)
fire("OnEnterVehicle", P)   -- not seated: nothing remembered
local mine = newVehicle(21, "Tatra815", 110, 100); P.vehicle = mine
fire("OnEnterVehicle", P); P.vehicle = nil
expect("last vehicle you got into becomes yours", W.store().mine == 21)
expect("your vehicle within reach is picked without the menu", W.pickVehicle(P, false) == mine)
mine.x = 400
expect("your vehicle out of reach is not", W.pickVehicle(P, false) == nil)

-- 10. Numpad 1
reset(); fire("OnGameStart")
P.x, P.y = 3600, 10925
fire("OnKeyPressed", 79)
expect("Numpad 1 away from home goes home", #P.tp == 1 and P.tp[1].x == 6032)
ticks(20)
fire("OnKeyPressed", 79)
expect("Numpad 1 at home goes back to the departure spot", #P.tp == 2 and near(P.tp[2].x, 3600) and near(P.tp[2].y, 10925))
ticks(20)
W.store().back = nil
P.x, P.y = 6040, 5240; local before = #P.tp
fire("OnKeyPressed", 79)
expect("Numpad 1 at home with nowhere to go back to does nothing", #P.tp == before and lastHalo():find("home"))
fire("OnKeyPressed", 12)
expect("other keys ignored", #P.tp == before)

-- 11. blocked arrival square (a wall, or water) moves you to the nearest free tile
reset(); fire("OnGameStart")
world.water = {["6032,5238"] = true}
W.travelTo(P, "Base", false)
ticks(20)
local last = P.tp[#P.tp]
expect("blocked arrival: moved to a free neighbour", #P.tp == 2 and (math.floor(last.x) ~= 6032 or math.floor(last.y) ~= 5238))

-- 12. right-click menu
reset(); fire("OnGameStart")
W.saveHere(P, "Mall")
local menu = ISContextMenu:getNew(nil)
fire("OnFillWorldObjectContextMenu", 0, menu, {}, false)
local top = menu.opts[1]
expect("menu has Empire: Travel with a submenu", top and top.name == "Empire: Travel" and top.sub)
local names = {}
for _, o in ipairs(top.sub.opts) do names[#names + 1] = o.name end
local joined = table.concat(names, "|")
expect("menu lists waypoints, save and delete", joined:find("Go to Base") and joined:find("Go to Mall") and joined:find("Save a waypoint here") and joined:find("Delete a waypoint"))
fire("OnFillWorldObjectContextMenu", 0, menu, {}, true)
expect("menu skipped on the test pass", #menu.opts == 1)
W.delete(P, "Mall")
expect("delete removes it", #W.store().list == 1)

print(n .. " checks, " .. fails .. " failed"); if fails > 0 then error("failures") end
