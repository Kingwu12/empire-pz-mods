local handlers = {}
local function ev() return setmetatable({}, {__index=function(t,k) return nil end}) end
Events = setmetatable({}, {__index=function(t,name)
  local e = {Add=function(f) handlers[name]=handlers[name] or {}; table.insert(handlers[name], f) end}
  rawset(t,name,e); return e end})
Keyboard = {KEY_NUMPAD5 = 76}
local halos = {}
HaloTextHelper = {addTextWithArrow=function(p,msg) table.insert(halos,msg) end, getColorGreen=function() return 1 end, getColorWhite=function() return 2 end}
-- mock player
local P = {visible=0, chasing=0, close=0, asleep=false, veh=nil, dead=false, nInv=10, nBack=10, md={}, x=0, y=0, extra={}}
function P:getX() return self.x end
function P:getY() return self.y end
function P:isDead() return self.dead end
function P:isAsleep() return self.asleep end
function P:getVehicle() return self.veh end
function P:getModData() return self.md end
function P:getStats() local s=self; return {getNumVisibleZombies=function() return s.visible end, getNumChasingZombies=function() return s.chasing end, getNumVeryCloseZombies=function() return s.close end} end
-- body inventory: nInv top-level items, one of them the worn bag holding nBack items (faithful to the game),
-- plus P.extra: real mock items (with ids) on top
local function mkItems(n, bagCount, extra)
  extra = extra or {}
  local list = {size=function() return n + #extra end}
  list.get = function(_, i)
    if i >= n then return extra[i - n + 1] end
    if bagCount and i == 0 then return {isBag=true, getInventory=function() return {getItems=function() return mkItems(bagCount) end} end} end
    return {}
  end
  return list
end
local INV = {isInCharacterInventory=function(_, p) return true end}
function INV:getItems() return mkItems(P.nInv, P.nBack, P.extra) end
function P:getInventory() return INV end
-- an item with an id; inBag = the bag item it sits in (nil = loose on him)
local function mkItem(id, inBag)
  local it = {id=id}
  function it:getID() return self.id end
  function it:getContainer() return {getContainingItem=function() return inBag end, isInCharacterInventory=function() return true end} end
  return it
end
-- vanilla's transfer action (only transferItem matters): moves the item onto him
ISInventoryTransferAction = {transferItem=function(self, item) self.item = item end}
function getSpecificPlayer(i) return P end
local doing = false
ISTimedActionQueue = {isPlayerDoingAction=function(p) return doing end}
local base = nil
EmpireBases = {activeBase=function(p) return base end}
local calls = {loot=0, sort=0}
local vac = {grabbed=0, full=false, throw=false}
function EmpireQoL_Vacuum(o) calls.loot=calls.loot+1; assert(o and o.auto==true); if vac.throw then error("boom") end; return vac.grabbed, vac.full end
EmpireSortAll = {run=function(p, opts) calls.sort=calls.sort+1; calls.lastOpts = opts; P.nInv = P.nInv - 3; return true end}

local clock = 0
function getTimestampMs() clock = clock + (_G.sortCost and 0 or 0); return clock end
function instanceof(o, cls)
  if cls == "InventoryContainer" then return o and o.isBag == true end
  if cls == "IsoDeadBody" then return o and o.isCorpse == true end
  return o and o.isPlayer == true
end
P.isPlayer = true; function P:isLocalPlayer() return true end
local unload = {n = 0, calls = 0}
EmpireSortAll.transferVehicle = function(p, veh, min) unload.calls = unload.calls + 1; if unload.n >= min then return unload.n end return 0 end
local vehCalls = {shutOff = 0, lights = 0}
local near = true
EmpireBases.vehicleNearBase = function(v, r) return near end
local function mkVeh(running, x) return {isEngineRunning=function() return running end, shutOff=function() vehCalls.shutOff=vehCalls.shutOff+1 end, setHeadlightsOn=function(_, on) vehCalls.lights=vehCalls.lights+1 end,
  getX=function() return x or 5 end, getY=function() return 0 end} end
local origRun = EmpireSortAll.run
EmpireSortAll.run = function(p, opts) clock = clock + (_G.sortMs or 5); return origRun(p, opts) end

local f, err = load(SRC, "13_AutoChores"); assert(f, err); f()
local function fire(name, ...) for _,h in ipairs(handlers[name] or {}) do h(...) end end
local fails, n = 0, 0
local function expect(name, cond) n=n+1; if cond then print("PASS "..name) else fails=fails+1; print("FAIL "..name) end end
local function reset() calls.loot, calls.sort = 0, 0; halos = {} end
local S = EmpireAutoChores.state

fire("OnGameStart")
expect("baseline recorded", S.carriedAtSort == 20)
-- 1 in base, nothing new -> no sort, but loot attempted
base = {name="Main"}; reset(); fire("EveryTenMinutes")
expect("idle beat (no kill) does NOT scan corpses", calls.loot == 0)
fire("OnZombieDead"); reset(); fire("EveryTenMinutes")
expect("at base, no new loot -> no sort", calls.sort == 0)
expect("loot attempted after a kill when quiet", calls.loot == 1)
expect("kill counter reset after the attempt", S.kills == 0)
reset(); fire("EveryTenMinutes"); expect("no second look without a new kill", calls.loot == 0)
-- 2 loot grabs items in the field
base = nil; vac.grabbed = 12; fire("OnZombieDead"); fire("OnZombieDead"); expect("kills counted", S.kills == 2); S.lastLootBeat = -99; reset(); fire("EveryTenMinutes")
expect("field: loot ran, sort did not", calls.loot == 1 and calls.sort == 0)
expect("vacuumedSince counted", S.vacuumedSince == 12)
-- 3 walk home -> sort fires
base = {name="Main"}; vac.grabbed = 0; reset(); fire("EveryTenMinutes")
expect("home with loot -> sorted once", calls.sort == 1)
expect("one heavy chore per beat", calls.loot == 0)
expect("state reset after sort", S.vacuumedSince == 0 and S.packFull == false)
-- 4 cooldown: home from another trip (section 12 covers how a trip starts) with new items, within the cooldown
S.away = true
P.nInv = P.nInv + 9; reset(); fire("EveryTenMinutes")
expect("cooldown blocks immediate re-sort", calls.sort == 0)
fire("EveryTenMinutes"); fire("EveryTenMinutes"); fire("EveryTenMinutes")
expect("after cooldown, growth >=5 -> exactly one sort", calls.sort == 1)
-- 5 zombies visible -> nothing
P.visible = 2; reset(); P.nInv = P.nInv + 20; S.lastSortBeat = -99; fire("EveryTenMinutes")
expect("zombie visible -> no chores", calls.loot == 0 and calls.sort == 0)
P.visible = 0
-- 6 mid-action / vehicle / asleep
doing = true; reset(); fire("EveryTenMinutes"); expect("busy action -> nothing", calls.loot==0 and calls.sort==0); doing=false
P.veh = {}; reset(); fire("EveryTenMinutes"); expect("in vehicle -> nothing", calls.loot==0 and calls.sort==0); P.veh=nil
P.asleep = true; reset(); fire("EveryTenMinutes"); expect("asleep -> nothing", calls.loot==0 and calls.sort==0); P.asleep=false
-- 7 pack full stops loot until a sort
base = nil; S.packFull=false; vac.full = true; vac.grabbed = 3; fire("OnZombieDead"); S.lastLootBeat = -99; reset(); fire("EveryTenMinutes")
expect("full flag set", S.packFull == true)
fire("OnZombieDead"); reset(); fire("EveryTenMinutes"); expect("no loot while pack full", calls.loot == 0)
-- 8 circuit breaker
S.packFull=false; vac.throw = true; vac.full=false; S.lastLootBeat=-99
for i=1,4 do fire("OnZombieDead"); S.lastLootBeat=-99; fire("EveryTenMinutes") end
expect("loot disables itself after 3 throws", S.off.loot == true)
fire("OnZombieDead"); reset(); fire("EveryTenMinutes"); expect("disabled loot not called", calls.loot == 0)
-- 8b parking at the dock
P.nInv = 10; S.packFull=false; S.lastSortBeat = S.beat; base = nil
local v = mkVeh(true)
P.veh = v; fire("OnEnterVehicle", P); expect("remembered vehicle on enter", S.lastVeh == v); P.veh = nil
S.lastVeh = v; near = true; unload.n = 14; fire("OnExitVehicle", P)
expect("docked exit: engine shut off", vehCalls.shutOff == 1)
expect("docked exit: headlights off", vehCalls.lights == 1)
expect("docked exit: unload queued for next beat", S.pendingUnload == v)
reset(); fire("EveryTenMinutes")
expect("beat unloads the truck once", unload.calls == 1 and S.pendingUnload == nil)
reset(); fire("EveryTenMinutes"); expect("no repeat unload", unload.calls == 1)
-- far from the dock: nothing
S.lastVeh = mkVeh(true); near = false; vehCalls.shutOff, vehCalls.lights = 0, 0; fire("OnExitVehicle", P)
expect("not docked -> engine/lights untouched, no unload", vehCalls.shutOff == 0 and vehCalls.lights == 0 and S.pendingUnload == nil)
-- tiny haul: transferVehicle declines
near = true; unload.n = 3; unload.calls = 0; S.away = true; S.lastVeh = mkVeh(false); fire("OnExitVehicle", P)
expect("engine already off: no shutOff call", vehCalls.shutOff == 0)
fire("EveryTenMinutes"); expect("tiny haul (below min) asked but declined", unload.calls == 1 and S.pendingUnload == nil)
-- BUG HUNT R2 #2: a park that went stale never unloads somewhere else (the old test here expected the
-- unload to wait through the drive and fire at the next exit, wherever that was)
local function haloHas(s) for _, h in ipairs(halos) do if h:find(s, 1, true) then return true end end return false end
local truck = mkVeh(false)
unload.n = 20; unload.calls = 0; S.away = true; S.lastVeh = truck; near = true; fire("OnExitVehicle", P)
expect("docked exit after a trip arms the unload", S.pendingUnload == truck)
P.veh = truck; fire("OnEnterVehicle", P); expect("gate stop: getting back in drops the park", S.pendingUnload == nil)
fire("EveryTenMinutes"); P.veh = nil; near = false; S.lastVeh = truck; fire("OnExitVehicle", P)
reset(); fire("EveryTenMinutes"); expect("exit at the loot site: nothing unloads, no 'Unloaded' halo", unload.calls == 0 and not haloHas("Unloaded"))
-- a beat that finds him driving drops it too (if OnEnterVehicle was ever missed)
S.away = true; near = true; S.lastVeh = truck; fire("OnExitVehicle", P); P.veh = truck
fire("EveryTenMinutes"); expect("a beat in a vehicle drops the park", S.pendingUnload == nil); P.veh = nil
fire("EveryTenMinutes"); expect("... and nothing unloads after", unload.calls == 0)
-- the truck left the dock before the beat
S.lastVeh = truck; fire("OnExitVehicle", P); near = false
fire("EveryTenMinutes"); expect("truck no longer at the dock: no unload", unload.calls == 0 and S.pendingUnload == nil)
-- truck still docked, but he walked off: outside the base and far from it
near = true; S.lastVeh = truck; fire("OnExitVehicle", P); P.x = 200
fire("EveryTenMinutes"); expect("far from the truck and outside the base: no unload", unload.calls == 0)
-- far from the truck but inside the base (walked in from the dock): unloads
S.lastVeh = truck; fire("OnExitVehicle", P); base = {name="Main"}
reset(); fire("EveryTenMinutes"); expect("walked into the base from the dock: unloads once", unload.calls == 1 and haloHas("Unloaded"))
expect("an unload ends the trip", S.away == false)
base = nil; P.x = 0
-- the unload asks transferVehicle to leave held items alone
local seenOpts
EmpireSortAll.transferVehicle = function(p, veh, min, o) seenOpts = o; unload.calls = unload.calls + 1; return 0 end
S.away = true; S.lastVeh = truck; fire("OnExitVehicle", P); reset(); fire("EveryTenMinutes")
expect("the unload passes the held-items filter", seenOpts and type(seenOpts.itemFilter) == "function")
expect("nothing moved (transferVehicle 0): no 'Unloaded' halo", not haloHas("Unloaded"))
-- a gate stop on the way OUT (no trip yet): parked, but the trip's supplies stay in the truck
S.away = false; S.lastVeh = truck; vehCalls.lights = 0; fire("OnExitVehicle", P)
expect("leaving base, stop at the gate: lights off, nothing armed", vehCalls.lights == 1 and S.pendingUnload == nil)
-- slow sort backs the cooldown off
base = {name="Main"}; S.slowExtra = 0; _G.sortMs = 400; S.away = true; P.nInv = P.nInv + 20; S.lastSortBeat = -99; reset(); fire("EveryTenMinutes")
expect("slow sort lengthens cooldown", calls.sort == 1 and S.slowExtra == 3)
_G.sortMs = 5; S.away = true; P.nInv = P.nInv + 20; fire("EveryTenMinutes"); fire("EveryTenMinutes"); reset(); fire("EveryTenMinutes")
expect("cooldown is longer after a slow sort (3+3 beats)", calls.sort == 0)
S.slowExtra = 0

-- 9 toggle
fire("OnKeyPressed", 76)
expect("numpad5 toggles OFF", S.on == false and P.md.EmpireAutoChoresOff == true)
reset(); base={}; P.nInv=P.nInv+30; S.lastSortBeat=-99; fire("EveryTenMinutes")
expect("master OFF -> nothing runs", calls.loot==0 and calls.sort==0)
fire("OnKeyPressed", 76)
expect("numpad5 toggles ON and re-arms", S.on == true and S.off.loot == false and P.md.EmpireAutoChoresOff == nil)
fire("OnKeyPressed", 1)
-- 10 persistence across load
P.md.EmpireAutoChoresOff = true; S.on = true; fire("OnGameStart"); expect("saved OFF restored on load", S.on == false)

-- 11 the chore registry (14_..17_ ride on it)
S.on = true; for k in pairs(S.off) do S.off[k] = false end; for k in pairs(S.fails) do S.fails[k] = 0 end
expect("auto sort asks for the carried-only fast path", calls.lastOpts and calls.lastOpts.carriedOnly == true)
local ran = {}
EmpireAutoChores.register("t_first", 5, function(p, ctx) ran[#ran+1] = "first"; return false end)
EmpireAutoChores.register("t_heavy", 6, function(p, ctx) ran[#ran+1] = "heavy"; return true end)
EmpireAutoChores.register("t_after", 7, function(p, ctx) ran[#ran+1] = "after"; return false end)
base = nil; reset(); fire("EveryTenMinutes")
expect("registry runs in order and a heavy chore ends the beat", table.concat(ran, ",") == "first,heavy")
expect("registered chore has its own fail/off slot", S.fails.t_heavy == 0 and S.off.t_heavy == false)
EmpireAutoChores.register("t_heavy", 6, function(p, ctx) ran[#ran+1] = "heavy2"; return false end)
ran = {}; fire("EveryTenMinutes")
expect("re-registering a name replaces it (no duplicates)", table.concat(ran, ",") == "first,heavy2,after")
EmpireAutoChores.register("t_base", 8, function(p, ctx) ran[#ran+1] = "base"; return false end, {needsBase = true})
ran = {}; base = nil; fire("EveryTenMinutes")
expect("needsBase chore skipped away from base", table.concat(ran, ","):find("base") == nil)
base = {name="Main"}; ran = {}; fire("EveryTenMinutes")
expect("needsBase chore runs at base", table.concat(ran, ","):find("base") ~= nil)
local gate = false
EmpireAutoChores.register("t_cfg", 9, function() ran[#ran+1] = "cfg"; return false end, {enabled = function() return gate end})
ran = {}; fire("EveryTenMinutes"); expect("opts.enabled=false skips the chore", table.concat(ran, ","):find("cfg") == nil)
gate = true; ran = {}; fire("EveryTenMinutes"); expect("opts.enabled=true runs the chore", table.concat(ran, ","):find("cfg") ~= nil)
-- circuit breaker for a registered chore
EmpireAutoChores.register("t_boom", 4, function() error("kaboom") end)
for i = 1, 4 do fire("EveryTenMinutes") end
expect("a throwing registered chore disables itself after 3", S.off.t_boom == true)
fire("OnKeyPressed", 76); fire("OnKeyPressed", 76)
expect("Numpad 5 off/on re-arms registered chores", S.off.t_boom == false and S.fails.t_boom == 0)
-- base edge: was in base last beat, not now
local seen
EmpireAutoChores.register("t_edge", 3, function(p, ctx) seen = ctx.justLeft; return false end)
EmpireAutoChores.register("t_boom", 4, function() return false end)
base = {name="Main"}; fire("EveryTenMinutes"); expect("in base: no leave edge", seen == false)
base = nil; fire("EveryTenMinutes"); expect("first beat outside base: justLeft", seen == true)
fire("EveryTenMinutes"); fire("EveryTenMinutes"); expect("edge still usable for 2 beats", seen == true)
fire("EveryTenMinutes"); expect("edge expires after LEAVE_BEATS", seen == false)
base = {name="Main"}; fire("EveryTenMinutes"); base = nil
EmpireAutoChores.register("t_edge", 3, function(p, ctx) ctx.consumeLeave(); seen = ctx.justLeft; return false end)
fire("EveryTenMinutes"); fire("EveryTenMinutes")
expect("consumeLeave clears the edge for the next beat", seen == false)
-- edge survives a busy beat (zombie near when crossing the border)
base = {name="Main"}; fire("EveryTenMinutes"); base = nil; P.visible = 1; fire("EveryTenMinutes"); P.visible = 0
EmpireAutoChores.register("t_edge", 3, function(p, ctx) seen = ctx.justLeft; return false end)
fire("EveryTenMinutes"); expect("edge noticed on a busy beat is still there when idle", seen == true)
-- noteLoot feeds the sorter trigger
S.vacuumedSince = 0; EmpireAutoChores.noteLoot(7); expect("noteLoot bumps vacuumedSince", S.vacuumedSince == 7)
-- recursive carried count: bag contents count, not just top-level
P.nInv, P.nBack = 10, 10; expect("carriedCount sees worn-bag contents", EmpireAutoChores.carriedCount(P) == 20)

-- 12 BUG HUNT R2 #3: what he takes from base storage is not loot. Trips arm the arrival sort.
for _, nm in ipairs({"t_first", "t_heavy", "t_after", "t_base", "t_cfg", "t_boom", "t_edge"}) do
  EmpireAutoChores.register(nm, 99, function() return false end)
end
S.vacuumedSince = 0; S.packFull = false; S.slowExtra = 0; S.pendingUnload = nil
base = {name="Main"}; fire("EveryTenMinutes"); S.away = false; S.lastSortBeat = -99; reset()
S.carriedAtSort = EmpireAutoChores.carriedCount(P)   -- as right after a sort
P.nInv = P.nInv + 12; fire("EveryTenMinutes"); fire("EveryTenMinutes")
expect("home all along: +12 off the shelves (a packed bag) -> no auto sort", calls.sort == 0)
base = nil; fire("EveryTenMinutes"); fire("EveryTenMinutes")
expect("2 beats outside (gate, dock, a perimeter wall): not a trip", S.away == false)
fire("EveryTenMinutes"); expect("3rd beat outside: a trip", S.away == true)
expect("the trip's baseline is what he left with", S.carriedAtSort == EmpireAutoChores.carriedCount(P))
base = {name="Main"}; reset(); fire("EveryTenMinutes")
expect("home from a trip with nothing new: no sort, and home again", calls.sort == 0 and S.away == false)
P.nInv = P.nInv + 8; reset(); fire("EveryTenMinutes"); expect("...so what he takes after that is not filed", calls.sort == 0)
base = nil; for _ = 1, 3 do fire("EveryTenMinutes") end
P.nInv = P.nInv + 6; base = {name="Main"}; reset(); fire("EveryTenMinutes")
expect("home from a trip with 6 new items: sorted once", calls.sort == 1 and S.away == false)
local filt = calls.lastOpts and calls.lastOpts.itemFilter
expect("the auto sort passes the held-items filter", type(filt) == "function")
base = nil; fire("EveryTenMinutes"); base = {name="Main"}; P.nInv = P.nInv + 10; S.lastSortBeat = -99; reset(); fire("EveryTenMinutes")
expect("a step out to the gate and back is not a trip: no sort", calls.sort == 0)
-- auto-loot at home still files (corpses at the fence are loot)
S.vacuumedSince = 4; S.lastSortBeat = -99; reset(); fire("EveryTenMinutes"); expect("auto-looted at home: sorted", calls.sort == 1)

-- 13 holds: the quartermaster's fetch, King's own grabs off the shelves, bags, and the end of a hold
local hammer, nails, apple = mkItem(501), mkItem(502), mkItem(503)
EmpireAutoChores.hold(hammer); EmpireAutoChores.hold(nails)
expect("quartermaster fetch is held", EmpireAutoChores.isHeld(hammer) and EmpireAutoChores.isHeld(nails))
expect("the sort filter leaves held items alone", filt(hammer) == false and filt(nails) == false)
expect("the sort filter lets loot through", filt(apple) == true)
local bag = mkItem(600); local inside = mkItem(601, bag)
EmpireAutoChores.hold(bag); expect("a held bag holds what is inside it", EmpireAutoChores.isHeld(inside))
P.extra = {hammer, nails, apple}
expect("held items do not count as new loot", EmpireAutoChores.carriedCount(P) - EmpireAutoChores.carriedCount(P, true) == 2)
-- mid-build: he is home, the quartermaster pulled 5+ items, a harvest says "file the crop": the sort runs
-- but the fetched tools stay (filter), and they never trigger it on their own
S.vacuumedSince = 0; S.lastSortBeat = -99; S.away = false; reset()
for i = 1, 6 do local x = mkItem(700 + i); EmpireAutoChores.hold(x); table.insert(P.extra, x) end
fire("EveryTenMinutes"); expect("6 fetched items at home: no sort", calls.sort == 0)
S.away = true; S.lastSortBeat = -99; reset(); fire("EveryTenMinutes")
expect("even right after a trip, held items alone do not trigger a sort", calls.sort == 0)
-- vanilla transfers: off a base shelf onto him while in the base -> held; a corpse, outside the base,
-- or between his own bags -> not held
local shelf = {isInCharacterInventory=function() return false end, getParent=function() return nil end}
local corpse = {isInCharacterInventory=function() return false end, getParent=function() return {isCorpse=true} end}
local function grab(src, it)
  local act = setmetatable({character=P, srcContainer=src, destContainer=INV}, {__index=ISInventoryTransferAction})
  act:transferItem(it)
  return EmpireAutoChores.isHeld(it)
end
base = {name="Main"}
expect("grab off a base shelf in the base: held", grab(shelf, mkItem(801)) == true)
expect("loot off a corpse in the base: not held", grab(corpse, mkItem(802)) == false)
expect("between his own bags: not held", grab(INV, mkItem(803)) == false)
base = nil
expect("a shelf outside the base (a house): not held", grab(shelf, mkItem(804)) == false)
-- holds end when a trip starts: what is left of a trip is filed at home
base = {name="Main"}; fire("EveryTenMinutes"); base = nil
fire("EveryTenMinutes"); fire("EveryTenMinutes"); expect("holds survive a step outside", EmpireAutoChores.isHeld(hammer))
fire("EveryTenMinutes"); expect("a trip releases every hold", not EmpireAutoChores.isHeld(hammer) and EmpireAutoChores.heldCount() == 0)
P.extra = {}
fire("OnGameStart"); S.on = true
base = {name="Main"}; expect("after another game start the transfer hook still holds", grab(shelf, mkItem(806)) == true)
fire("OnGameStart"); S.on = true; expect("a game start clears holds", EmpireAutoChores.heldCount() == 0)
print(string.format("%d checks, %d failed", n, fails))
if fails > 0 then error("failures") end
