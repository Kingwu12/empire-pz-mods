-- Mock test for 16_AutoProduction.lua (D6) + the EmpireProduction registry + the sorter's node exclusion.
-- Run: node tests/chores/runner.js C/13_AutoChores.lua tests/chores/production_test.lua C/16_AutoProduction.lua EmpireProduction/.../EmpireProd_Core.lua EmpireSortAll/.../EmpireSortAll_Config.lua
local handlers = {}
Events = setmetatable({}, {__index=function(t,name)
  local e = {Add=function(f) handlers[name]=handlers[name] or {}; table.insert(handlers[name], f) end}
  rawset(t,name,e); return e end})
Keyboard = {KEY_NUMPAD5 = 76}
local halos = {}
HaloTextHelper = {addTextWithArrow=function(p,msg) table.insert(halos,msg) end, getColorGreen=function() return 1 end, getColorWhite=function() return 2 end}
local mdStore = {}
ModData = {getOrCreate = function(k) mdStore[k] = mdStore[k] or {}; return mdStore[k] end}
local gameHours = 100
function getGameTime() return {getWorldAgeHours = function() return gameHours end} end

local function obj(p, kind)
  local o = {p = p, kind = kind}
  return setmetatable(o, {__index = function(_, k) return function(self, ...) local v = p[k]; if type(v) == "function" then return v(self, ...) end; return v end end})
end
function instanceof(o, cls) return o ~= nil and type(o) == "table" and rawget(o, "kind") == cls end
local function item(ft, fav) return obj({getFullType = ft, getType = ft:gsub("^.-%.", ""), isFavorite = fav or false}) end
-- container with real add/remove, a capacity and a parent object
local function cont(name, cap)
  local c = {name = name, list = {}, cap = cap or 1000}
  c.getItems = function(self) return {size = function() return #c.list end, get = function(_, i) return c.list[i + 1] end} end
  c.addItem = function(self, it) c.list[#c.list + 1] = it end
  c.AddItem = function(self, ft) c.list[#c.list + 1] = item(ft) end
  c.Remove = function(self, it) for i, x in ipairs(c.list) do if x == it then table.remove(c.list, i); return end end end
  c.hasRoomFor = function(self, p, it) return #c.list < c.cap end
  c.count = function(self, ft) local n = 0; for _, x in ipairs(c.list) do if x.p.getFullType == ft then n = n + 1 end end return n end
  c.fill = function(self, ft, n, fav) for i = 1, n do c.list[#c.list + 1] = item(ft, fav) end return self end
  return c
end

-- a placed container object on a square, optionally a production node
local squares = {}
local function placeNode(x, y, z, recipeId, cap)
  local c = cont("node" .. x, cap)
  local md = {}
  if recipeId then md.EmpireProd = {recipe = recipeId, lastHour = gameHours} end
  local o = obj({getModData = md, getContainer = c, transmitModData = function() end, getSquare = function() return squares[x .. "," .. y .. "," .. z] end})
  o.cont = c; o.md = md
  c.p = nil
  local sq = {x = x, y = y, z = z, objs = {o}}
  sq.getX = function() return x end; sq.getY = function() return y end; sq.getZ = function() return z end
  sq.getObjects = function() return {size = function() return #sq.objs end, get = function(_, i) return sq.objs[i + 1] end} end
  squares[x .. "," .. y .. "," .. z] = sq
  -- the container knows its parent object (what the sorter config looks at)
  c.getParent = function() return o end
  return o, c, sq
end
function getCell() return {getGridSquare = function(_, x, y, z) return squares[x .. "," .. y .. "," .. z] end} end

local main = cont("main")
local P = {md = {}, visible = 0}
function P:isDead() return false end
function P:isAsleep() return false end
function P:getVehicle() return nil end
function P:getModData() return self.md end
function P:getInventory() return main end
function P:getStats() local s = self; return {getNumVisibleZombies = function() return s.visible end, getNumChasingZombies = function() return 0 end, getNumVeryCloseZombies = function() return 0 end} end
function getSpecificPlayer(i) return P end
ISTimedActionQueue = {isPlayerDoingAction = function() return false end}
local base = nil
EmpireBases = {activeBase = function(p) return base end}
local baseConts = {}
local byType = {}
EmpireBaseCache = {
  get = function() return base and {containers = baseConts} or nil end,
  invalidate = function() end,
  containersFor = function(ft) local out = {}; for _, c in ipairs(baseConts) do if c:count(ft) > 0 then out[#out + 1] = c end end return out end,
}
local sortCalls = {}
EmpireSortAll = {run = function(p, opts)
  sortCalls[#sortCalls + 1] = opts
  -- act like the real thing: move every matching item out of the source piles into the first base container
  for _, src in ipairs(opts.sources or {}) do
    local keep = {}
    for _, it in ipairs(src.list) do if opts.itemFilter(it) then baseConts[1]:addItem(it) else keep[#keep + 1] = it end end
    src.list = keep
  end
  return true end}
function getTimestampMs() return 0 end

local f, err = load(SRC, "13_AutoChores"); assert(f, err); f()
local f4, err4 = load(SRC4, "EmpireSortAll_Config"); assert(f4, err4); f4()
local f3, err3 = load(SRC3, "EmpireProd_Core"); assert(f3, err3); f3()
local f2, err2 = load(SRC2, "16_AutoProduction"); assert(f2, err2); f2()
local function fire(name, ...) for _, h in ipairs(handlers[name] or {}) do h(...) end end
local fails, n = 0, 0
local function expect(name, cond) n = n + 1; if cond then print("PASS " .. name) else fails = fails + 1; print("FAIL " .. name) end end
local S = EmpireAutoChores.state
local A = EmpireAutoProduction
local EP = EmpireProd
local function reset()
  squares = {}; mdStore = {}; baseConts[1] = cont("shelf"); baseConts[2] = cont("crate"); sortCalls = {}; halos = {}
  A.state.cursor = 0; A.state.waiting = {}; base = {x1 = 0, x2 = 50, y1 = 0, y2 = 50, name = "Main"}; gameHours = 100; main.list = {}
  A.cfg.ENABLED = true
end
local function run(inBase) if inBase == nil then inBase = true end return A.run(P, {beat = S.beat, inBase = inBase}) end
fire("OnGameStart")

-- 0 registration
local reg
for _, c in ipairs(EmpireAutoChores.chores) do if c.name == "production" then reg = c end end
expect("production chore registered at order 60", reg ~= nil and reg.order == 60)

-- 1 registry in the core
reset()
local o1, c1 = placeNode(10, 10, 0, "charcoal")
expect("register adds the node by square key", EP.register(o1) == "10,10,0" and EP.registry()["10,10,0"] == true)
expect("nodeOnSquare finds the node", EP.nodeOnSquare(squares["10,10,0"]) == o1)
EP.unregister(o1); expect("unregister removes it", EP.registry()["10,10,0"] == nil)
EP.register(o1)

-- 2 sorter config excludes node containers
local plainObj, plainCont = placeNode(20, 20, 0, nil)
expect("sorter config: a production node's container is excluded", EmpireSortConfig.isExcludedContainer(c1) == true)
expect("sorter config: an ordinary container is not", EmpireSortConfig.isExcludedContainer(plainCont) == false)

-- 3 guards
reset(); local ob, cb = placeNode(10, 10, 0, "charcoal"); EP.register(ob); baseConts[1]:fill("Base.Log", 30)
expect("not in the base -> nothing", run(false) == false and cb:count("Base.Log") == 0)
base = nil; expect("no active base -> nothing", run() == false)
base = {x1 = 0, x2 = 50, y1 = 0, y2 = 50}
A.cfg.ENABLED = false; expect("disabled -> nothing", run() == false and cb:count("Base.Log") == 0); A.cfg.ENABLED = true

-- 4 feeding
run()
expect("charcoal node topped up to 6 h of logs (rate 3/h = 18), real items moved", cb:count("Base.Log") == 18 and baseConts[1]:count("Base.Log") == 12)
expect("halo says what happened", halos[1] and halos[1]:find("stocked 18") ~= nil)
run(); expect("already stocked: nothing more moves", cb:count("Base.Log") == 18)
-- inputs spread over several containers, nothing of other types taken
reset(); ob, cb = placeNode(10, 10, 0, "charcoal"); EP.register(ob)
baseConts[1]:fill("Base.Log", 5); baseConts[2]:fill("Base.Log", 40); baseConts[2]:fill("Base.Plank", 10)
run(); expect("pulls from several base containers, only the input type", cb:count("Base.Log") == 18 and cb:count("Base.Plank") == 0 and baseConts[1]:count("Base.Log") + baseConts[2]:count("Base.Log") == 27)
-- favourites stay
reset(); ob, cb = placeNode(10, 10, 0, "charcoal"); EP.register(ob); baseConts[1]:fill("Base.Log", 10, true)
run(); expect("favourite items never taken", cb:count("Base.Log") == 0)
-- node full
reset(); ob, cb = placeNode(10, 10, 0, "charcoal", 5); EP.register(ob); baseConts[1]:fill("Base.Log", 30)
run(); expect("stops when the node container is full", cb:count("Base.Log") == 5)
-- several inputs share the per-beat budget
reset(); ob, cb = placeNode(10, 10, 0, "asm_9mm"); EP.register(ob)
baseConts[1]:fill("Base.GunPowder", 300); baseConts[1]:fill("Base.Lead", 300); baseConts[2]:fill("Base.BrassScrap", 300)
run(); local per = math.ceil(A.cfg.MAX_MOVE / 3)
expect("every input gets its share per beat (no input starves)", cb:count("Base.GunPowder") == per and cb:count("Base.Lead") == per and cb:count("Base.BrassScrap") == per)
for i = 1, 20 do run() end
expect("beats keep topping up to 6 h of each input (180)", cb:count("Base.GunPowder") == 180 and cb:count("Base.Lead") == 180 and cb:count("Base.BrassScrap") == 180)

-- 5 accrued production is settled before feeding
reset(); ob, cb = placeNode(10, 10, 0, "charcoal"); EP.register(ob); baseConts[1]:fill("Base.Log", 100)
run(); gameHours = gameHours + 2   -- two hours pass: 6 cycles -> 6 logs used, 12 charcoal made
run()
expect("accrual settled (12 charcoal made) then logs topped back up to 18", cb:count("Base.Charcoal") == 12 and cb:count("Base.Log") == 18)

-- 6 collect
reset(); ob, cb = placeNode(10, 10, 0, "charcoal"); EP.register(ob); cb:fill("Base.Log", 18); cb:fill("Base.Charcoal", 25)
sortCalls = {}; local did = run()
expect("25 finished items >= threshold: the sorter files them from the node", #sortCalls == 1 and sortCalls[1].sources[1] == cb and sortCalls[1].noCarried == true and sortCalls[1].carriedOnly == true)
expect("filter lets only the output type through", sortCalls[1].itemFilter(item("Base.Charcoal")) == true and sortCalls[1].itemFilter(item("Base.Log")) == false)
expect("output left the node, inputs stayed", cb:count("Base.Charcoal") == 0 and cb:count("Base.Log") == 18 and baseConts[1]:count("Base.Charcoal") == 25)
expect("a filing beat counts as the heavy chore", did == true)
reset(); ob, cb = placeNode(10, 10, 0, "charcoal"); EP.register(ob); cb:fill("Base.Log", 18); cb:fill("Base.Charcoal", 5)
run(); expect("small stack is not worth a trip yet", #sortCalls == 0)
for i = 1, A.cfg.COLLECT_MAX_BEATS do S.beat = S.beat + 1; run() end
expect("... but it is filed once it has waited long enough", #sortCalls == 1 and cb:count("Base.Charcoal") == 0)
reset(); ob, cb = placeNode(10, 10, 0, "charcoal"); EP.register(ob); cb:fill("Base.Log", 18); cb:fill("Base.Charcoal", 30)
local ob2, cb2 = placeNode(12, 12, 0, "planks"); EP.register(ob2); cb2:fill("Base.Log", 12); cb2:fill("Base.Plank", 30)
run(); expect("one sorter call per beat even with two full nodes", #sortCalls == 1)
run(); expect("the second node is filed on the next beat", #sortCalls == 2)

-- 7 manual node, outside the base, unloaded, vanished
reset(); ob, cb = placeNode(10, 10, 0, "charcoal"); EP.register(ob); ob.md.EmpireProd.manual = true; baseConts[1]:fill("Base.Log", 30); cb:fill("Base.Charcoal", 30)
run(); expect("a node switched to manual is left alone", cb:count("Base.Log") == 0 and #sortCalls == 0)
reset(); local fo, fc = placeNode(90, 90, 0, "charcoal"); EP.register(fo); baseConts[1]:fill("Base.Log", 30)
run(); expect("a node outside the active base is left alone", fc:count("Base.Log") == 0)
reset(); EP.registry()["5,5,0"] = true
run(); expect("a key whose square is not loaded is kept", EP.registry()["5,5,0"] == true)
local gone = placeNode(6, 6, 0, nil); EP.registry()["6,6,0"] = true
run(); expect("a loaded square with no node on it is dropped", EP.registry()["6,6,0"] == nil)
EP.registry()["garbage"] = true; run(); expect("a malformed key is dropped", EP.registry()["garbage"] == nil)

-- 8 round robin
reset()
local nodes = {}
for i = 1, 5 do local o, c = placeNode(i, i, 0, "charcoal"); EP.register(o); nodes[i] = c end
baseConts[1]:fill("Base.Log", 200)
run(); local fed1 = 0; for i = 1, 5 do if nodes[i]:count("Base.Log") > 0 then fed1 = fed1 + 1 end end
run(); local fed2 = 0; for i = 1, 5 do if nodes[i]:count("Base.Log") > 0 then fed2 = fed2 + 1 end end
expect("round robin: 3 nodes per beat, all five by the second beat", fed1 == A.cfg.NODES_PER_BEAT and fed2 == 5)

-- 9 missing production mod
local savedEP = EmpireProd; EmpireProd = nil
reset(); expect("EmpireProduction not installed -> chore is a no-op", run() == false); EmpireProd = savedEP

-- 10 a throwing source container is contained
reset(); ob, cb = placeNode(10, 10, 0, "charcoal"); EP.register(ob)
baseConts[1].getItems = function() error("boom") end
expect("a broken container does not throw out of the chore", pcall(run) == true)

print(string.format("%d checks, %d failed", n, fails))
if fails > 0 then error("production_test failed") end
