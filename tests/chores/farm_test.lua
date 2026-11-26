-- Mock test for 15_AutoFarm.lua (D5: harvest + water plants inside painted farm zones).
-- Run: node tests/chores/runner.js EmpireQoL/42/media/lua/client/13_AutoChores.lua tests/chores/farm_test.lua EmpireQoL/42/media/lua/client/15_AutoFarm.lua
local handlers = {}
Events = setmetatable({}, {__index=function(t,name)
  local e = {Add=function(f) handlers[name]=handlers[name] or {}; table.insert(handlers[name], f) end}
  rawset(t,name,e); return e end})
Keyboard = {KEY_NUMPAD5 = 76}
local halos = {}
HaloTextHelper = {addTextWithArrow=function(p,msg) table.insert(halos,msg) end, getColorGreen=function() return 1 end, getColorWhite=function() return 2 end}

local function obj(p, kind)
  local o = {p = p, kind = kind}
  return setmetatable(o, {__index = function(_, k) return function(self, ...) local v = p[k]; if type(v) == "function" then return v(self, ...) end; return v end end})
end
function instanceof(o, cls) return o ~= nil and type(o) == "table" and rawget(o, "kind") == cls end
local function cont(name, items)
  local c = {name = name, list = items or {}}
  c.getItems = function(self) return {size = function() return #c.list end, get = function(_, i) return c.list[i + 1] end} end
  c.addItem = function(self, it) c.list[#c.list + 1] = it end
  c.Remove = function(self, it) for i, x in ipairs(c.list) do if x == it then table.remove(c.list, i); return end end end
  c.has = function(self, it) for _, x in ipairs(c.list) do if x == it then return true end end return false end
  return c
end

local main = cont("main")
local P = {md = {}, x = 100, y = 100, z = 0, visible = 0, hand = nil}
function P:isDead() return false end
function P:isAsleep() return false end
function P:getVehicle() return nil end
function P:getModData() return self.md end
function P:getPlayerNum() return 0 end
function P:getX() return self.x end
function P:getY() return self.y end
function P:getZ() return self.z end
function P:getPrimaryHandItem() return self.hand end
function P:getInventory() return main end
function P:getStats() local s = self; return {getNumVisibleZombies = function() return s.visible end, getNumChasingZombies = function() return 0 end, getNumVeryCloseZombies = function() return 0 end} end
function getSpecificPlayer(i) return P end
local queue = {}
ISTimedActionQueue = {isPlayerDoingAction = function(p) return false end, add = function(a) queue[#queue + 1] = a end}
local base = nil
EmpireBases = {activeBase = function(p) return base end}
local baseConts = {}
EmpireBaseCache = {get = function() if base then return {containers = baseConts} end return nil end, invalidate = function() end}
EmpireSortAll = {run = function() return true end}
function getTimestampMs() return 0 end

-- zones (tiles sets, like the real EmpireZones; zones may overlap)
local zones, zalls = {}, 0
EmpireZones = {
  version = 0,
  key = function(x, y, z) return math.floor(x) .. "," .. math.floor(y) .. "," .. math.floor(z) end,
  all = function() zalls = zalls + 1; return zones end,
}
local function addZone(ztype, x1, y1, x2, y2)
  local z = {type = ztype, tiles = {}}
  for x = x1, x2 do for y = y1, y2 do z.tiles[EmpireZones.key(x, y, 0)] = true end end
  zones[#zones + 1] = z; EmpireZones.version = EmpireZones.version + 1
end

-- farming registry
local plants, counts, refreshes = {}, 0, 0
CFarmingSystem = {instance = {
  getLuaObjectCount = function() counts = counts + 1; if #plants == 0 then return false end return #plants end,
  getLuaObjectByIndex = function(_, i) return plants[i] end}}
local function plant(o)
  local p = {x = o.x, y = o.y, z = o.z or 0, state = o.state or "seeded", waterLvl = o.water or 100, waterNeeded = o.need or 70,
             hasVegetable = o.ripe or false, exterior = o.exterior ~= false}
  function p:updateFromIsoObject() refreshes = refreshes + 1; if o.fresh then for k, v in pairs(o.fresh) do self[k] = v end end end
  function p:getIsoObject() if o.unloaded then return nil end return {} end
  function p:isAlive() return self.state ~= "dead" and self.state ~= "rotten" and self.state ~= "destroyed" and self.state ~= "harvested" end
  function p:canHarvest() return self:isAlive() and self.hasVegetable end
  function p:getSquare() return {px = self.x, py = self.y, blocked = o.blocked} end
  plants[#plants + 1] = p
  return p
end

-- vanilla surface
local walks = {}
ISFarmingMenu = {
  walkToPlant = function(p, sq) if sq.blocked then return false end walks[#walks + 1] = sq; return true end,
  getWaterUsesInteger = function(it)
    local fc = it.p.getFluidContainer
    if fc then local ft = fc.p.getPrimaryFluid.p.getFluidTypeString
      if ft == "Water" or ft == "TaintedWater" then return math.floor(fc.p.getAmount * 1000 / 200) end end
    return 0 end}
local raining = false
RainManager = {isRaining = function() return raining end}
ISHarvestPlantAction = {new = function(self, p, plant, t) return {kind = "harvest", plant = plant} end}
ISWaterPlantAction = {new = function(self, p, item, uses, sq, t) return {kind = "water", item = item, uses = uses, sq = sq} end}
ISEquipWeaponAction = {new = function(self, p, item, t, primary, two) return {kind = "equip", item = item, two = two} end}

local function container(o) -- water container item
  local fc = obj({getPrimaryFluid = obj({getFluidTypeString = o.fluid or "Water"}), getAmount = o.amount or 1.0, getCapacity = o.cap or 1.0})
  return obj({getFullType = "Base." .. (o.type or "Bottle"), getType = o.type or "Bottle", getDisplayName = o.type or "Bottle", getFluidContainer = fc, isFavorite = o.fav or false})
end

local f, err = load(SRC, "13_AutoChores"); assert(f, err); f()
local f2, err2 = load(SRC2, "15_AutoFarm"); assert(f2, err2); f2()
local function fire(name, ...) for _, h in ipairs(handlers[name] or {}) do h(...) end end
local fails, n = 0, 0
local function expect(name, cond) n = n + 1; if cond then print("PASS " .. name) else fails = fails + 1; print("FAIL " .. name) end end
local S = EmpireAutoChores.state
local F = EmpireAutoFarm
local function kinds(k) local c = 0; for _, a in ipairs(queue) do if a.kind == k then c = c + 1 end end return c end
local function reset() plants = {}; queue = {}; walks = {}; halos = {}; main.list = {}; baseConts[1] = cont("shed"); F.state.tended = {}; base = nil; raining = false; P.hand = nil; P.x, P.y = 100, 100; F.cfg.ENABLED = true end
local function run() return F.run(P, {beat = S.beat, inBase = base ~= nil}) end
fire("OnGameStart")

-- 0 registration + no zone
local reg
for _, c in ipairs(EmpireAutoChores.chores) do if c.name == "farm" then reg = c end end
expect("farm chore registered at order 50 (after loot 40)", reg ~= nil and reg.order == 50)
reset(); plant{x = 101, y = 100, ripe = true}
counts = 0; local r = run()
expect("no farm zone painted -> does nothing and does not even read the registry", r == false and counts == 0 and #queue == 0)
addZone("base", 90, 90, 110, 110)
counts = 0; run(); expect("a base zone is not a farm zone", counts == 0 and #queue == 0)
addZone("farm", 95, 95, 105, 105)

-- 1 harvest
reset()
local ripe = plant{x = 101, y = 100, ripe = true}
local outside = plant{x = 112, y = 100, ripe = true}          -- not in the farm zone
local far = plant{x = 130, y = 100, ripe = true}              -- beyond the reach radius (and outside the zone)
local otherZ = plant{x = 102, y = 100, z = 1, ripe = true}
local dead = plant{x = 103, y = 100, state = "dead", ripe = true}
local unloaded = plant{x = 104, y = 100, ripe = true, unloaded = true}
local stale = plant{x = 99, y = 99, ripe = false, fresh = {hasVegetable = true}}
local growing = plant{x = 98, y = 99, ripe = false}
S.vacuumedSince = 0
local did = run()
expect("ripe plants inside the farm zone are harvested", did == true and kinds("harvest") == 2)
expect("harvest queued for the right plants", queue[1].plant == ripe or queue[2].plant == ripe)
expect("stale registry row refreshed from the real plant before deciding", (queue[1].plant == stale) or (queue[2].plant == stale))
expect("outside the zone / too far / other floor / dead / not loaded: left alone", kinds("harvest") == 2 and not (queue[1].plant == outside or queue[2].plant == outside))
expect("walks to each plant first", #walks == 2)
expect("the crop is noted as new loot for the next sort", S.vacuumedSince == 2)
expect("halo tells what is happening", halos[1] == "Tending the farm: 2 to harvest, 0 to water")
expect("nearest plant first", queue[1].plant == ripe)

-- 2 not queued again right away
queue = {}; did = run()
expect("same plants are not queued twice in a row", did == false and #queue == 0)
S.beat = S.beat + F.cfg.RETEND_BEATS; did = run()
expect("after the retend gap they are looked at again", did == true and kinds("harvest") == 2)

-- 3 watering: tainted before clean, equip, restore
reset(); addZone("farm", 95, 95, 105, 105)
local thirsty = plant{x = 101, y = 101, water = 20, need = 70}
local fine    = plant{x = 102, y = 101, water = 60, need = 70}      -- 60 >= 70-15: not thirsty
local weapon  = obj({getContainer = {}, isRequiresEquippedBothHands = false, isTwoHandWeapon = true, getType = "Axe"})
P.hand = weapon
local tbottle = container{type = "TaintedBottle", fluid = "TaintedWater", amount = 1.0, cap = 1.0}
local bucket  = container{type = "Bucket", fluid = "Water", amount = 5.0, cap = 10}
main.list = {bucket, tbottle}
did = run()
expect("thirsty plant watered, the fine one skipped", did == true and kinds("water") == 1 and queue[#queue - 1].kind == "water" or kinds("water") == 1)
local waterAct; for _, a in ipairs(queue) do if a.kind == "water" then waterAct = a end end
expect("tainted water goes first (clean bucket kept)", waterAct and waterAct.item == tbottle)
expect("uses = what the plant needs (20 -> 75 = 6), capped by the bottle (5 uses)", waterAct and waterAct.uses == 5)
expect("equip before water, weapon back in hand after", queue[1].kind == "equip" and queue[1].item == tbottle and queue[#queue].kind == "equip" and queue[#queue].item == weapon and queue[#queue].two == true)

-- 4 small clean bottles stay for drinking
reset(); addZone("farm", 95, 95, 105, 105); plant{x = 101, y = 101, water = 10}
main.list = {container{type = "SmallWater", fluid = "Water", amount = 1.0, cap = 1.0}}
did = run(); expect("clean drinking-size bottle is not used on crops", did == false and kinds("water") == 0)
F.cfg.USE_DRINKING_WATER = true; did = run(); expect("... unless switched on", did == true and kinds("water") == 1); F.cfg.USE_DRINKING_WATER = false

-- 5 one container, several plants
reset(); addZone("farm", 95, 95, 105, 105)
for i = 1, 3 do plant{x = 100 + i, y = 100, water = 30, need = 70} end
local big = container{type = "Bucket", fluid = "Water", amount = 5.0, cap = 10}      -- 25 uses
main.list = {big}
did = run()
expect("three thirsty plants share one bucket: one equip, three waterings", kinds("equip") == 1 and kinds("water") == 3)
local sum = 0; for _, a in ipairs(queue) do if a.kind == "water" then sum = sum + a.uses end end
expect("each plant gets what it needs (30 -> 75 = 5 uses)", sum == 15)

-- 6 running dry: second container
reset(); addZone("farm", 95, 95, 105, 105)
for i = 1, 3 do plant{x = 100 + i, y = 100, water = 10, need = 70} end
local small = container{type = "Jug", fluid = "Water", amount = 2.0, cap = 2.0}    -- 10 uses
local jug2 = container{type = "Jug2", fluid = "Water", amount = 3.0, cap = 3.0}    -- 15 uses
main.list = {small, jug2}
did = run()
expect("runs dry -> switches to the next container", kinds("water") == 3 and kinds("equip") >= 2)

-- 7 rain
reset(); addZone("farm", 95, 95, 105, 105)
plant{x = 101, y = 100, water = 10, exterior = true}; plant{x = 102, y = 100, water = 10, exterior = false}
main.list = {container{type = "Bucket", amount = 5, cap = 10}}; raining = true
did = run(); expect("raining: rain-fed (outdoor) plants are left, indoor ones watered", did == true and kinds("water") == 1)

-- 8 harvests first, then water; the cap
reset(); addZone("farm", 95, 95, 105, 105)
plant{x = 101, y = 100, water = 10}
for i = 1, 12 do plant{x = 96 + (i % 9), y = 96 + math.floor(i / 9), ripe = true} end
main.list = {container{type = "Bucket", amount = 5, cap = 10}}
did = run()
expect("at most MAX_TASKS plants per beat", kinds("harvest") + kinds("water") == F.cfg.MAX_TASKS)
expect("harvests come before water", kinds("water") == 0)

-- 9 base stock
reset(); addZone("farm", 95, 95, 105, 105); plant{x = 101, y = 100, water = 10}
local shed = container{type = "Bucket", amount = 5, cap = 10}; baseConts[1].list = {shed}
did = run(); expect("outside the base the shed bucket is out of reach", did == false)
base = {name = "Main"}; did = run()
expect("at base: takes the bucket from base storage (real item moved)", did == true and main:has(shed) and not baseConts[1]:has(shed) and kinds("water") == 1)
F.cfg.BASE_STOCK = false; reset(); addZone("farm", 95, 95, 105, 105); plant{x = 101, y = 100, water = 10}; baseConts[1].list = {shed}; base = {name = "Main"}
did = run(); expect("BASE_STOCK=false keeps the shed shut", did == false); F.cfg.BASE_STOCK = true

-- 10 blocked tile / favourite container
reset(); addZone("farm", 95, 95, 105, 105); plant{x = 101, y = 100, ripe = true, blocked = true}
did = run(); expect("no free tile next to the plant -> skipped, nothing queued", did == false and #queue == 0)
reset(); addZone("farm", 95, 95, 105, 105); plant{x = 101, y = 100, water = 10}
main.list = {container{type = "Bucket", amount = 5, cap = 10, fav = true}}
did = run(); expect("favourite container never used", did == false)

-- 11 zone cache
reset(); zalls = 0; plant{x = 101, y = 100, ripe = true}
run(); run(); run()
expect("zone list read once per zone change, not per beat", zalls <= 1)

-- 12 switches
reset(); plant{x = 101, y = 100, ripe = true}
F.cfg.HARVEST = false; did = run(); expect("HARVEST=false leaves ripe plants", did == false); F.cfg.HARVEST = true
F.cfg.ENABLED = false; did = run(); expect("ENABLED=false does nothing", did == false); F.cfg.ENABLED = true

-- 13 through the real beat: harvest now, file the crop next beat at base
reset(); plant{x = 101, y = 100, ripe = true}; base = {name = "Main"}
S.vacuumedSince = 0; S.lastSortBeat = S.beat - 99; S.carriedAtSort = 0
local sorts = 0; EmpireSortAll.run = function() sorts = sorts + 1; return true end
fire("EveryTenMinutes"); expect("beat: farm chore queues the harvest", kinds("harvest") == 1 and sorts == 0)
queue = {}; fire("EveryTenMinutes"); expect("next beat: auto-sort files the crop (before more farm work)", sorts == 1)

-- 14 throwing registry is contained
reset(); CFarmingSystem.instance.getLuaObjectCount = function() error("boom") end
did = run(); expect("a registry error is contained (no throw, no action)", did == false)

print(string.format("%d checks, %d failed", n, fails))
if fails > 0 then error("farm_test failed") end
