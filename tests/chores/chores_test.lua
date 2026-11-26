local handlers = {}
local function ev() return setmetatable({}, {__index=function(t,k) return nil end}) end
Events = setmetatable({}, {__index=function(t,name)
  local e = {Add=function(f) handlers[name]=handlers[name] or {}; table.insert(handlers[name], f) end}
  rawset(t,name,e); return e end})
Keyboard = {KEY_NUMPAD5 = 76}
local halos = {}
HaloTextHelper = {addTextWithArrow=function(p,msg) table.insert(halos,msg) end, getColorGreen=function() return 1 end, getColorWhite=function() return 2 end}
-- mock player
local P = {visible=0, chasing=0, close=0, asleep=false, veh=nil, dead=false, nInv=10, nBack=10, md={}}
function P:isDead() return self.dead end
function P:isAsleep() return self.asleep end
function P:getVehicle() return self.veh end
function P:getModData() return self.md end
function P:getStats() local s=self; return {getNumVisibleZombies=function() return s.visible end, getNumChasingZombies=function() return s.chasing end, getNumVeryCloseZombies=function() return s.close end} end
function P:getInventory() local s=self; return {getItems=function() return {size=function() return s.nInv end} end} end
function P:getClothingItem_Back() local s=self; return {getInventory=function() return {getItems=function() return {size=function() return s.nBack end} end} end} end
function getSpecificPlayer(i) return P end
local doing = false
ISTimedActionQueue = {isPlayerDoingAction=function(p) return doing end}
local base = nil
EmpireBases = {activeBase=function(p) return base end}
local calls = {loot=0, sort=0}
local vac = {grabbed=0, full=false, throw=false}
function EmpireQoL_Vacuum(o) calls.loot=calls.loot+1; assert(o and o.auto==true); if vac.throw then error("boom") end; return vac.grabbed, vac.full end
EmpireSortAll = {run=function(p) calls.sort=calls.sort+1; P.nInv = P.nInv - 3; return true end}

local clock = 0
function getTimestampMs() clock = clock + (_G.sortCost and 0 or 0); return clock end
function instanceof(o, cls) return o and o.isPlayer == true end
P.isPlayer = true; function P:isLocalPlayer() return true end
local unload = {n = 0, calls = 0}
EmpireSortAll.transferVehicle = function(p, veh, min) unload.calls = unload.calls + 1; if unload.n >= min then return unload.n end return 0 end
local vehCalls = {shutOff = 0, lights = 0}
local near = true
EmpireBases.vehicleNearBase = function(v, r) return near end
local function mkVeh(running) return {isEngineRunning=function() return running end, shutOff=function() vehCalls.shutOff=vehCalls.shutOff+1 end, setHeadlightsOn=function(_, on) vehCalls.lights=vehCalls.lights+1 end} end
local origRun = EmpireSortAll.run
EmpireSortAll.run = function(p) clock = clock + (_G.sortMs or 5); return origRun(p) end

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
-- 4 cooldown: new items but within cooldown
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
near = true; unload.n = 3; unload.calls = 0; S.lastVeh = mkVeh(false); fire("OnExitVehicle", P)
expect("engine already off: no shutOff call", vehCalls.shutOff == 0)
fire("EveryTenMinutes"); expect("tiny haul (below min) asked but declined", unload.calls == 1 and S.pendingUnload == nil)
-- driving again before the beat: skip until out of the vehicle
unload.n = 20; unload.calls = 0; S.lastVeh = mkVeh(false); fire("OnExitVehicle", P); P.veh = {}
fire("EveryTenMinutes"); expect("still in a vehicle -> unload waits", unload.calls == 0 and S.pendingUnload ~= nil)
P.veh = nil; fire("EveryTenMinutes"); expect("unload runs once out", unload.calls == 1)
-- slow sort backs the cooldown off
base = {name="Main"}; S.slowExtra = 0; _G.sortMs = 400; P.nInv = P.nInv + 20; S.lastSortBeat = -99; reset(); fire("EveryTenMinutes")
expect("slow sort lengthens cooldown", calls.sort == 1 and S.slowExtra == 3)
_G.sortMs = 5; P.nInv = P.nInv + 20; fire("EveryTenMinutes"); fire("EveryTenMinutes"); reset(); fire("EveryTenMinutes")
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
print(string.format("%d checks, %d failed", n, fails))
if fails > 0 then error("failures") end
