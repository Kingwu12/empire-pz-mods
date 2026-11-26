-- Mock test for 17_PreTripRestock.lua (D7).
-- Run: node tests/chores/runner.js EmpireQoL/42/media/lua/client/13_AutoChores.lua tests/chores/restock_test.lua EmpireQoL/42/media/lua/client/17_PreTripRestock.lua
local handlers = {}
Events = setmetatable({}, {__index = function(t, name)
  local e = {Add = function(f) handlers[name] = handlers[name] or {}; table.insert(handlers[name], f) end}
  rawset(t, name, e); return e end})
Keyboard = {KEY_NUMPAD5 = 76}
local halos = {}
HaloTextHelper = {addTextWithArrow = function(p, msg) table.insert(halos, msg) end, getColorGreen = function() return 1 end, getColorWhite = function() return 2 end}

local function obj(p, kind)
  local o = {p = p, kind = kind}
  return setmetatable(o, {__index = function(_, k) return function(self, ...) local v = p[k]; if type(v) == "function" then return v(self, ...) end; return v end end})
end
function instanceof(o, cls) return o ~= nil and type(o) == "table" and rawget(o, "kind") == cls end
local function item(ft, opts)
  opts = opts or {}
  return obj({getFullType = ft, getType = ft:gsub("^.-%.", ""), isFavorite = opts.fav or false, getCurrentAmmoCount = opts.ammo or 0})
end
-- container with real add/remove; `parentLoaded` false = the object's square is not loaded
local function cont(name, parentLoaded)
  local c = {name = name, list = {}, parentLoaded = parentLoaded ~= false}
  c.getItems = function(self) return {size = function() return #c.list end, get = function(_, i) return c.list[i + 1] end} end
  c.addItem = function(self, it) c.list[#c.list + 1] = it end
  c.Remove = function(self, it) for i, x in ipairs(c.list) do if x == it then table.remove(c.list, i); return end end end
  c.count = function(self, ft) local n = 0; for _, x in ipairs(c.list) do if x.p.getFullType == ft then n = n + 1 end end return n end
  c.fill = function(self, ft, n, opts) for i = 1, n do c.list[#c.list + 1] = item(ft, opts) end return self end
  c.getParent = function(self) return {getSquare = function() return c.parentLoaded and {} or nil end} end
  return c
end
local function gun(magType, ammoKey)
  return obj({isRanged = true, getMagazineType = magType, getAmmoType = ammoKey and obj({getItemKey = ammoKey}) or nil}, "HandWeapon")
end
local function bag(inner) return obj({getInventory = inner}, "InventoryContainer") end

local main = cont("main")
local P = {primary = nil, secondary = nil, weight = 1, maxw = 20, x = 25, y = 25, md = {}}
function P:isDead() return false end
function P:getInventory() return main end
function P:getPrimaryHandItem() return self.primary end
function P:getSecondaryHandItem() return self.secondary end
function P:getPlayerNum() return 0 end
function P:getInventoryWeight() return self.weight end
function P:getMaxWeight() return self.maxw end
function P:getX() return self.x end
function P:getY() return self.y end
function P:isLocalPlayer() return true end
function P:getModData() return self.md end
local hotbar = {}
function getPlayerHotbar(n) return {attachedItems = hotbar} end
function getSpecificPlayer(i) return P end
function getTimestampMs() return 0 end

local base = {x1 = 0, x2 = 50, y1 = 0, y2 = 50, name = "Main"}
EmpireBases = {
  activeBase = function(p) return base end,
  getEmpireZoneBase = function() return {x1 = 0, x2 = 50, y1 = 0, y2 = 50} end,
  list = function() return {} end,
}
local baseConts = {}
local lookups = 0
local function index(ft) local out = {}; for _, c in ipairs(baseConts) do if c:count(ft) > 0 then out[#out + 1] = c end end return out end
local peekNil = false
EmpireBaseCache = {
  invalidate = function() end,
  containersFor = function(ft) lookups = lookups + 1; return index(ft) end,
  peek = function()
    if peekNil then return nil end
    local bt = setmetatable({}, {__index = function(t, ft) local c = index(ft); if #c == 0 then return nil end return {containers = c} end})
    return {base = "Main", byType = bt, containers = baseConts}
  end,
}
local topCalls, topQueued = {}, 0
EmpireQoL_TopOffMags = function(p, opts) topCalls[#topCalls + 1] = opts; return topQueued end

local f, err = load(SRC, "13_AutoChores"); assert(f, err); f()
local f2, err2 = load(SRC2, "17_PreTripRestock"); assert(f2, err2); f2()
local function fire(name, ...) for _, h in ipairs(handlers[name] or {}) do h(...) end end
local fails, n = 0, 0
local function expect(name, cond) n = n + 1; if cond then print("PASS " .. name) else fails = fails + 1; print("FAIL " .. name) end end
local S = EmpireAutoChores.state
local A = EmpireAutoRestock
local B9, R9 = "Base.9mmClip", "Base.Bullets9mm"
local B223, R223 = "Base.223Clip", "Base.Bullets223"
local function reset()
  main.list = {}; hotbar = {}; P.primary = nil; P.secondary = nil; P.weight = 1; P.x, P.y = 25, 25
  baseConts[1] = cont("shelf"); baseConts[2] = cont("crate"); for i = #baseConts, 3, -1 do baseConts[i] = nil end
  lookups = 0; topCalls = {}; topQueued = 0; halos = {}; peekNil = false
  A.state.backoff = {}; A.state.lastTopOff = -99; A.state.last = nil
  A.cfg.ENABLED = true; A.cfg.MAX_MOVE = 150
  S.on = true; S.off.restock = false; S.beat = 100
end
local lefts = 0
local function ctx(inBase, justLeft) return {beat = S.beat, inBase = inBase, justLeft = justLeft or false, consumeLeave = function() lefts = lefts + 1 end} end
local function run(inBase, justLeft) return A.run(P, ctx(inBase, justLeft)) end
fire("OnGameStart")

-- 0 registration
local reg
for _, c in ipairs(EmpireAutoChores.chores) do if c.name == "restock" then reg = c end end
expect("restock chore registered at order 70", reg ~= nil and reg.order == 70)
expect("boarding handler registered", handlers["OnEnterVehicle"] ~= nil and #handlers["OnEnterVehicle"] >= 1)

-- 1 no guns -> nothing
reset(); baseConts[1]:fill(B9, 5, {ammo = 15}):fill(R9, 100)
run(true)
expect("no gun in hands or on the hotbar -> nothing is packed", main:count(B9) == 0 and main:count(R9) == 0)
P.primary = obj({isRanged = false}, "HandWeapon")
run(true); expect("a melee weapon is not a gun", main:count(R9) == 0)

-- 2 pistol in hand: fullest 3 mags + 40 rounds, real items moved
reset(); P.primary = gun(B9, R9)
baseConts[1]:fill(B9, 1, {ammo = 15}):fill(B9, 1, {ammo = 3}):fill(B9, 1, {ammo = 15})
baseConts[2]:fill(B9, 1, {ammo = 9}):fill(B9, 1, {ammo = 15}):fill(R9, 100)
topQueued = 2
local heavy = run(true)
expect("3 spare mags taken", main:count(B9) == 3)
local fullest = true
for _, it in ipairs(main.list) do if it.p.getFullType == B9 and it.p.getCurrentAmmoCount ~= 15 then fullest = false end end
expect("the three fullest mags (15 rounds each) were chosen", fullest)
expect("40 loose rounds taken", main:count(R9) == 40)
expect("moved, not spawned (base lost exactly that)", baseConts[1]:count(B9) + baseConts[2]:count(B9) == 2 and baseConts[1]:count(R9) + baseConts[2]:count(R9) == 60)
expect("mag top-off queued once (quiet) and the beat is heavy", #topCalls == 1 and topCalls[1].quiet == true and heavy == true)
expect("halo says what was packed", halos[1] and halos[1]:find("3 mags") ~= nil and halos[1]:find("40 rounds") ~= nil)
-- 3 already stocked
local before = #main.list
S.beat = 101; heavy = run(true)
expect("already stocked: nothing more moves", #main.list == before)
expect("nothing moved + recently topped off -> no second top-off, beat not heavy", #topCalls == 1 and heavy == false)
S.beat = 107; topQueued = 0; heavy = run(true)
expect("six beats later the top-off check runs again (nothing queued -> not heavy)", #topCalls == 2 and heavy == false)

-- 4 partial stock, mags inside a worn bag count
reset(); P.primary = gun(B9, R9)
local pack = cont("pack"); pack:fill(B9, 1, {ammo = 15}):fill(R9, 30)
main:addItem(bag(pack))
baseConts[1]:fill(B9, 5, {ammo = 15}):fill(R9, 100)
run(true)
expect("tops up to the target counting what the bag holds (2 mags, 10 rounds)", main:count(B9) == 2 and main:count(R9) == 10)

-- 5 hotbar gun, second gun with other ammo, shared ammo counted once
reset(); P.primary = gun(B9, R9); hotbar = {gun(B9, R9), gun(B223, R223), gun(nil, "Base.ShotgunShells")}
baseConts[1]:fill(B9, 4, {ammo = 15}):fill(R9, 100):fill(B223, 4, {ammo = 30}):fill(R223, 100):fill("Base.ShotgunShells", 50)
run(true)
expect("two guns with the same ammo share one target (3 mags, 40 rounds)", main:count(B9) == 3 and main:count(R9) == 40)
expect("a hotbar rifle gets its own mags and rounds", main:count(B223) == 3 and main:count(R223) == 40)
expect("a gun without a magazine type gets only rounds", main:count("Base.ShotgunShells") == 40)

-- 6 favourites stay
reset(); P.primary = gun(B9, R9); baseConts[1]:fill(B9, 4, {ammo = 15, fav = true}):fill(R9, 50, {fav = true})
run(true); expect("favourite mags and rounds are never taken", #main.list == 0)

-- 7 no stock backs off
reset(); P.primary = gun(B9, R9)
run(true); local l1 = lookups
expect("the base has none -> looked for both types once", l1 == 2)
S.beat = 101; run(true); expect("backoff: not looked for again next beat", lookups == l1)
S.beat = 107; run(true); expect("backoff over: looked again after 6 beats", lookups > l1)

-- 8 weight guard
reset(); P.primary = gun(B9, R9); baseConts[1]:fill(B9, 4, {ammo = 15}):fill(R9, 100); P.weight = 19
run(true); expect("over 90% of carry weight -> nothing packed", #main.list == 0)

-- 9 budget
reset(); P.primary = gun(B9, R9); A.cfg.MAX_MOVE = 5; baseConts[1]:fill(B9, 4, {ammo = 15}):fill(R9, 100)
run(true); expect("MAX_MOVE caps one restock (mags first)", #main.list == 5 and main:count(B9) == 3 and main:count(R9) == 2)

-- 10 not in base, not just left
reset(); P.primary = gun(B9, R9); baseConts[1]:fill(B9, 4, {ammo = 15}):fill(R9, 100)
run(false, false); expect("outside the base and not just left -> nothing", #main.list == 0)
A.cfg.ENABLED = false; run(true); expect("disabled -> nothing", #main.list == 0); A.cfg.ENABLED = true

-- 11 just left the base: catch-up
reset(); P.primary = gun(B9, R9); baseConts[1]:fill(B9, 4, {ammo = 15}):fill(R9, 100); lefts = 0
heavy = run(false, true)
expect("just left and still close: packed from the last base index", main:count(B9) == 3 and main:count(R9) == 40)
expect("the departure is consumed (one catch-up per leave)", lefts == 1)
expect("the catch-up does not queue a top-off", #topCalls == 0 and heavy == false)
reset(); P.primary = gun(B9, R9); baseConts[1]:fill(B9, 4, {ammo = 15}):fill(R9, 100); P.x = 200; lefts = 0
run(false, true); expect("just left but 150 tiles away -> nothing", #main.list == 0 and lefts == 1)
reset(); P.primary = gun(B9, R9); baseConts[1]:fill(B9, 4, {ammo = 15}):fill(R9, 100); peekNil = true
run(false, true); expect("no remembered base index -> nothing", #main.list == 0)
reset(); P.primary = gun(B9, R9); baseConts[1] = cont("shelf", false); baseConts[1]:fill(B9, 4, {ammo = 15}):fill(R9, 100)
baseConts[2]:fill(R9, 100)
run(false, true)
expect("a container whose square is no longer loaded is never touched", baseConts[1]:count(B9) == 4 and baseConts[1]:count(R9) == 100 and main:count(R9) == 40 and main:count(B9) == 0)

-- 12 boarding a vehicle at base
reset(); P.primary = gun(B9, R9); baseConts[1]:fill(B9, 4, {ammo = 15}):fill(R9, 100)
fire("OnEnterVehicle", P)
expect("boarding inside the base packs the guns, no top-off", main:count(B9) == 3 and main:count(R9) == 40 and #topCalls == 0)
reset(); P.primary = gun(B9, R9); baseConts[1]:fill(B9, 4, {ammo = 15}):fill(R9, 100); base = nil
fire("OnEnterVehicle", P); base = {x1 = 0, x2 = 50, y1 = 0, y2 = 50, name = "Main"}
expect("boarding outside any base -> nothing", #main.list == 0)
reset(); P.primary = gun(B9, R9); baseConts[1]:fill(B9, 4, {ammo = 15}):fill(R9, 100); S.off.restock = true
fire("OnEnterVehicle", P); expect("restock switched off -> boarding does nothing", #main.list == 0)
reset(); P.primary = gun(B9, R9); baseConts[1]:fill(B9, 4, {ammo = 15}):fill(R9, 100); S.on = false
fire("OnEnterVehicle", P); expect("master switch off -> boarding does nothing", #main.list == 0); S.on = true
reset(); P.primary = gun(B9, R9); baseConts[1]:fill(B9, 4, {ammo = 15}):fill(R9, 100)
local other = {isLocalPlayer = function() return false end}
fire("OnEnterVehicle", other); expect("someone else boarding -> nothing", #main.list == 0)

-- 13 a restock that throws never escapes the vehicle handler
reset(); P.primary = gun(B9, R9); EmpireBaseCache.containersFor = function() error("boom") end
local ok = pcall(fire, "OnEnterVehicle", P)
expect("an error inside boarding is swallowed", ok == true)

print(string.format("%d checks, %d failed", n, fails))
if fails > 0 then os.exit(1) end
