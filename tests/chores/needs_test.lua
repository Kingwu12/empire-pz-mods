-- Mock test for 14_AutoNeeds.lua (D4: eat / drink on autopilot).
-- Run: node tests/chores/runner.js EmpireQoL/42/media/lua/client/13_AutoChores.lua tests/chores/needs_test.lua EmpireQoL/42/media/lua/client/14_AutoNeeds.lua
local handlers = {}
Events = setmetatable({}, {__index=function(t,name)
  local e = {Add=function(f) handlers[name]=handlers[name] or {}; table.insert(handlers[name], f) end}
  rawset(t,name,e); return e end})
Keyboard = {KEY_NUMPAD5 = 76}
local halos = {}
HaloTextHelper = {addTextWithArrow=function(p,msg) table.insert(halos,msg) end, getColorGreen=function() return 1 end, getColorWhite=function() return 2 end}
CharacterStat = {HUNGER="HUNGER", THIRST="THIRST"}
MoodleType = {FOOD_EATEN="FOOD_EATEN"}

-- generic mock object: every method name returns p[name] (a function gets called with self)
local function obj(p, kind)
  local o = {p = p, kind = kind}
  return setmetatable(o, {__index = function(_, k) return function(self, ...) local v = p[k]; if type(v) == "function" then return v(self, ...) end; return v end end})
end
function instanceof(o, cls) return o ~= nil and type(o) == "table" and rawget(o, "kind") == cls end

-- containers
local function cont(name, items)
  local c = {name = name, list = items or {}}
  c.getItems = function(self) return {size = function() return #c.list end, get = function(_, i) return c.list[i + 1] end} end
  c.addItem = function(self, it) c.list[#c.list + 1] = it end
  c.Remove = function(self, it) for i, x in ipairs(c.list) do if x == it then table.remove(c.list, i); return end end end
  c.has = function(self, it) for _, x in ipairs(c.list) do if x == it then return true end end return false end
  return c
end

local main = cont("main")
local P = {md = {}, hunger = 0, thirst = 0, stuffed = 0, moving = false, visible = 0}
function P:isDead() return false end
function P:isAsleep() return false end
function P:getVehicle() return nil end
function P:getModData() return self.md end
function P:getPlayerNum() return 0 end
function P:isPlayerMoving() return self.moving end
function P:isKnownPoison(it) return it.p.poison == true end
function P:getInventory() return main end
function P:getMoodles() local s = self; return {getMoodleLevel = function(_, which) return s.stuffed end} end
function P:getStats() local s = self; return {
  getNumVisibleZombies = function() return s.visible end, getNumChasingZombies = function() return 0 end, getNumVeryCloseZombies = function() return 0 end,
  get = function(_, which) if which == "HUNGER" then return s.hunger elseif which == "THIRST" then return s.thirst end return 0 end} end
function getSpecificPlayer(i) return P end
local doing = false
ISTimedActionQueue = {isPlayerDoingAction = function(p) return doing end}
local base = nil
EmpireBases = {activeBase = function(p) return base end}
local baseConts = {}
local invalidated = 0
EmpireBaseCache = {get = function() if base then return {containers = baseConts} end return nil end, invalidate = function() invalidated = invalidated + 1 end}
EmpireSortAll = {run = function() return true end}
function getTimestampMs() return 0 end

-- vanilla surface used by 14_
local eats, drinks = {}, {}
local effect = true   -- eating/drinking really lowers the stat (set false to simulate "it did not take")
ISInventoryPaneContextMenu = {
  getContainers = function(p) return {} end,
  eatItem = function(item, pct, pnum, recipe, eatPct) eats[#eats + 1] = {item = item, pct = pct, recipe = recipe, eatPct = eatPct}; if effect then P.hunger = 0 end end,
  onDrinkFluid = function(item, pct, p, recipe, real) drinks[#drinks + 1] = {item = item, pct = pct, recipe = recipe}; if effect then P.thirst = 0 end end,
}
local scripts = {OpenCan = {name = "OpenCan"}, OpenBottle = {name = "OpenBottle"}}
function getScriptManager() return {getCraftRecipe = function(_, name) return scripts[name] end} end
local function hasOpenerCarried()
  local function scan(c, d)
    for _, it in ipairs(c.list) do
      if it.p.getType == "TinOpener" then return true end
      if it.kind == "InventoryContainer" and d < 3 and scan(it.p.getInventory, d + 1) then return true end
    end
    return false
  end
  return scan(main, 0)
end
HandcraftLogic = {new = function()
  local L = {}
  function L:setContainers(c) end
  function L:setRecipeFromContextClick(recipe, item) self.recipe = recipe end
  function L:canPerformCurrentRecipe()
    if self.recipe == scripts.OpenBottle then return true end   -- bottle caps need no tool
    return hasOpenerCarried()                                   -- cans need the opener in the inventory
  end
  return L
end}

-- item builders
local function food(o)
  o = o or {}
  return obj({
    getFullType = o.ft or ("Base." .. (o.type or "Food")), getType = o.type or "Food", getDisplayName = o.name or o.type or "Food",
    getHungChange = o.hung or -0.4, getOffAgeMax = o.off or 100000, getAge = o.age or 0, getUnhappyChange = o.unhappy or 0,
    isBurnt = o.burnt or false, isRotten = o.rotten or false, isFrozen = o.frozen or false, isSpice = false, isTainted = o.tainted or false,
    isFavorite = o.fav or false, isAlcoholic = false, isbDangerousUncooked = o.raw or false, isCooked = o.cooked or false,
    getScriptItem = obj({isCantEat = o.sealed or false}),
    getOpeningRecipe = o.sealed and "OpenCan" or nil, poison = o.poison,
  }, "Food")
end
local function bottle(o)
  o = o or {}
  local fc = obj({isEmpty = (o.amount == 0), getPrimaryFluid = obj({getFluidTypeString = o.fluid or "Water"}), isTaintedStatusKnown = o.known or false,
    getAmount = o.amount or 1.0, getCapacity = o.cap or 1.0})
  return obj({getFullType = o.ft or ("Base." .. (o.type or "WaterBottle")), getType = o.type or "WaterBottle", getDisplayName = o.name or "Water bottle",
    getFluidContainer = fc, isFavorite = o.fav or false, isSealed = o.sealed or false, getOpeningRecipe = o.sealed and "OpenBottle" or nil})
end
local function opener() return obj({getFullType = "Base.TinOpener", getType = "TinOpener", getDisplayName = "Tin opener"}) end
local function bag(inner) return obj({getFullType = "Base.Bag", getType = "Bag", getInventory = inner, getDisplayName = "Bag"}, "InventoryContainer") end

local f, err = load(SRC, "13_AutoChores"); assert(f, err); f()
local f2, err2 = load(SRC2, "14_AutoNeeds"); assert(f2, err2); f2()
local function fire(name, ...) for _, h in ipairs(handlers[name] or {}) do h(...) end end
local fails, n = 0, 0
local function expect(name, cond) n = n + 1; if cond then print("PASS " .. name) else fails = fails + 1; print("FAIL " .. name) end end
local S = EmpireAutoChores.state
local N = EmpireAutoNeeds
local function clear()
  main.list = {}; baseConts[1] = cont("fridge"); baseConts[2] = cont("shelf"); eats, drinks = {}, {}; halos = {}
  P.hunger, P.thirst, P.stuffed, P.moving = 0, 0, 0, false; N.state.nextTry = {eat = 0, drink = 0}; N.state.strikes = {eat = 0, drink = 0}; N.state.last = nil; N.state.said = {}
  base = nil; doing = false
end
fire("OnGameStart")

-- 0 registration
local reg = nil
for _, c in ipairs(EmpireAutoChores.chores) do if c.name == "needs" then reg = c end end
expect("needs chore registered", reg ~= nil)
expect("needs runs first (order 10, before unload/sort/loot)", reg and reg.order == 10 and EmpireAutoChores.chores[1].name == "needs")

-- 1 nothing needed
clear(); main.list = {food{type = "Bread"}}; P.hunger = 0.10; fire("EveryTenMinutes")
expect("not hungry -> nothing eaten", #eats == 0 and #drinks == 0)

-- 2 spoilage first
clear(); P.hunger = 0.60
local rice  = food{type = "Rice", name = "Rice", off = 10, age = 1}      -- 9 days left
local bread = food{type = "Bread", name = "Bread", off = 3, age = 2.5}   -- 0.5 day left
local beans = food{type = "Beans", name = "Beans"}                       -- never spoils
main.list = {rice, beans, bread}
fire("EveryTenMinutes")
expect("eats the food closest to spoiling", #eats == 1 and eats[1].item == bread)
expect("big hunger -> whole item", eats[1] and eats[1].pct == 1)
expect("halo says what happened", halos[1] == "Eating Bread")

-- 3 portion size
clear(); P.hunger = 0.22; main.list = {food{type = "Stew", hung = -0.6}}
fire("EveryTenMinutes"); expect("small hunger -> half portion of a big meal", #eats == 1 and eats[1].pct == 0.5)
clear(); P.hunger = 0.22; main.list = {food{type = "Apple", hung = -0.1}}
fire("EveryTenMinutes"); expect("small food is eaten whole", #eats == 1 and eats[1].pct == 1)

-- 4 safety filters
clear(); P.hunger = 0.5
main.list = {food{type = "Fav", fav = true}, food{type = "Rot", rotten = true}, food{type = "Burnt", burnt = true}, food{type = "Frozen", frozen = true},
             food{type = "Taint", tainted = true}, food{type = "Poison", poison = true}, food{type = "Raw", raw = true}, food{type = "Full", hung = 0}}
fire("EveryTenMinutes")
expect("favourite, rotten, burnt, frozen, tainted, known-poison, dangerous-raw and zero-value food never eaten", #eats == 0)
expect("nothing suitable: stand down for the backoff", N.state.nextTry.eat == S.beat + N.cfg.BACKOFF_BEATS)
main.list = {food{type = "Fine"}}
local before = S.beat; fire("EveryTenMinutes")
expect("backoff: no retry on the next beat even with food", #eats == 0)
for i = 1, N.cfg.BACKOFF_BEATS do fire("EveryTenMinutes") end
expect("after the backoff it eats again", #eats >= 1)
clear(); P.hunger = 0.5; main.list = {food{type = "Cooked", cooked = true, raw = true}}
fire("EveryTenMinutes"); expect("cooked 'dangerous when raw' food is fine", #eats == 1)
clear(); P.hunger = 0.5; main.list = {food{type = "Sad", unhappy = 5, off = 50, age = 1}, food{type = "Happy", off = 55, age = 1}}
fire("EveryTenMinutes"); expect("unhappy food loses to nice food of similar freshness (10-day penalty)", #eats == 1 and eats[1].item.p.getType == "Happy")

-- 5 worn bag contents count; base stock only at base
clear(); P.hunger = 0.5
local bagCont = cont("pack", {food{type = "BagBar"}}); main.list = {bag(bagCont)}
fire("EveryTenMinutes"); expect("food in a worn bag is carried food", #eats == 1 and eats[1].item.p.getType == "BagBar")
clear(); P.hunger = 0.5
local fridgeFood = food{type = "Cheese", off = 5, age = 1}; baseConts[1].list = {fridgeFood}
fire("EveryTenMinutes"); expect("outside the base: base stock is out of reach", #eats == 0)
clear(); P.hunger = 0.5; base = {name = "Main"}; fridgeFood = food{type = "Cheese", off = 5, age = 1}; baseConts[1].list = {fridgeFood}
invalidated = 0; fire("EveryTenMinutes")
expect("at base: takes the food from the fridge (real item moved)", #eats == 1 and eats[1].item == fridgeFood and main:has(fridgeFood) and not baseConts[1]:has(fridgeFood))
expect("base cache invalidated after the move", invalidated >= 1)
clear(); P.hunger = 0.5; base = {name = "Main"}; main.list = {food{type = "Carried"}}; baseConts[1].list = {food{type = "Fridge", off = 1, age = 0.9}}
fire("EveryTenMinutes"); expect("carried food first, base stock only when nothing is carried", #eats == 1 and eats[1].item.p.getType == "Carried" and #baseConts[1].list == 1)
N.cfg.BASE_STOCK = false; clear(); P.hunger = 0.5; base = {name = "Main"}; baseConts[1].list = {food{type = "Fridge"}}
fire("EveryTenMinutes"); expect("BASE_STOCK=false keeps the fridge shut", #eats == 0); N.cfg.BASE_STOCK = true

-- 6 sealed cans
clear(); P.hunger = 0.5; base = {name = "Main"}
local can = food{type = "CannedBeans", name = "Beans (can)", sealed = true}
main.list = {can}
fire("EveryTenMinutes"); expect("sealed can with no opener anywhere -> not eaten", #eats == 0)
clear(); P.hunger = 0.5; base = {name = "Main"}
can = food{type = "CannedBeans", name = "Beans (can)", sealed = true}; main.list = {can, opener()}
fire("EveryTenMinutes")
expect("can + opener carried -> open-and-eat through the opening recipe", #eats == 1 and eats[1].item == can and eats[1].recipe == scripts.OpenCan and eats[1].eatPct ~= nil)
clear(); P.hunger = 0.5; base = {name = "Main"}
can = food{type = "CannedBeans", name = "Beans (can)", sealed = true}; main.list = {can}; local op = opener(); baseConts[2].list = {op}
fire("EveryTenMinutes")
expect("opener fetched from base stock, can opened and eaten", #eats == 1 and eats[1].item == can and main:has(op))
clear(); P.hunger = 0.5; base = {name = "Main"}
can = food{type = "CannedBeans", name = "Beans (can)", sealed = true}; baseConts[1].list = {can}; op = opener(); main.list = {op}
fire("EveryTenMinutes")
expect("can in base stock, opener carried -> can fetched then opened", #eats == 1 and eats[1].item == can and main:has(can) and eats[1].recipe == scripts.OpenCan)
clear(); P.hunger = 0.5; base = nil
can = food{type = "CannedBeans", name = "Beans (can)", sealed = true}; main.list = {can}; baseConts[2].list = {opener()}
fire("EveryTenMinutes"); expect("away from base the opener on the shelf is out of reach", #eats == 0)
clear(); P.hunger = 0.5; base = {name = "Main"}
main.list = {food{type = "CannedBeans", sealed = true}, food{type = "Cracker"}}
fire("EveryTenMinutes"); expect("plain food is preferred over opening a can", #eats == 1 and eats[1].item.p.getType == "Cracker" and eats[1].recipe == nil)

-- 7 drinking
clear(); P.thirst = 0.50
local clean, tainted, juice = bottle{type = "WaterBottle", amount = 1.0}, bottle{type = "TaintBottle", fluid = "TaintedWater", amount = 1.0}, bottle{type = "Bleach", fluid = "Bleach", amount = 1.0}
local empty, fav = bottle{type = "EmptyBottle", amount = 0}, bottle{type = "FavBottle", amount = 1, fav = true}
main.list = {tainted, juice, empty, fav, clean}
fire("EveryTenMinutes")
expect("drinks clean water only", #drinks == 1 and drinks[1].item == clean)
expect("drink size = what the thirst needs (thirst 0.5 = 1 L)", drinks[1] and math.abs(drinks[1].pct - 1.0) < 1e-6)
clear(); P.thirst = 0.25; main.list = {bottle{type = "WaterBottle", amount = 1.0}}
fire("EveryTenMinutes"); expect("small thirst -> a part of the bottle", #drinks == 1 and math.abs(drinks[1].pct - 0.5) < 1e-6)
clear(); P.thirst = 0.25; main.list = {bottle{type = "Bucket", amount = 5, cap = 10, ft = "Base.BucketWater"}, bottle{type = "Small", amount = 0.6, cap = 1, ft = "Base.Small"}}
fire("EveryTenMinutes"); expect("bottle before bucket", #drinks == 1 and drinks[1].item.p.getType == "Small")
clear(); P.thirst = 0.25; main.list = {bottle{type = "Bucket", amount = 5, cap = 10, ft = "Base.BucketWater"}}
fire("EveryTenMinutes"); expect("bucket only when nothing else (and only a sip)", #drinks == 1 and drinks[1].pct <= 0.2)
clear(); P.thirst = 0.40; base = {name = "Main"}; local stock = bottle{type = "WaterBottle", amount = 1.0}; baseConts[2].list = {stock}
fire("EveryTenMinutes"); expect("at base: takes a bottle from base stock", #drinks == 1 and drinks[1].item == stock and main:has(stock))
clear(); P.thirst = 0.40; main.list = {bottle{type = "SealedBottle", amount = 1.0, sealed = true}}
fire("EveryTenMinutes"); expect("sealed bottle: opened through its opening recipe", #drinks == 1 and drinks[1].recipe == scripts.OpenBottle)
clear(); P.thirst = 0.40; main.list = {bottle{type = "SodaWater", fluid = "CarbonatedWater", amount = 0.5}}
fire("EveryTenMinutes"); expect("sparkling water counts", #drinks == 1)

-- 8 both needs: thirst first, one need per beat
clear(); P.thirst = 0.6; P.hunger = 0.4; main.list = {food{type = "Bread"}, bottle{type = "WaterBottle", amount = 1.0}}
fire("EveryTenMinutes"); expect("thirst >= hunger: drinks first, one need per beat", #drinks == 1 and #eats == 0)
fire("EveryTenMinutes"); expect("hunger gets its turn next beat", #eats == 1)
clear(); P.thirst = 0.6; P.hunger = 0.4; main.list = {food{type = "Bread"}}
fire("EveryTenMinutes"); expect("no water: falls through to food in the same beat", #drinks == 0 and #eats == 1)

-- 9 guards
clear(); P.hunger = 0.5; main.list = {food{type = "Bread"}}; doing = true
fire("EveryTenMinutes"); expect("busy with another action -> do not touch the queue", #eats == 0); doing = false
P.visible = 3; fire("EveryTenMinutes"); expect("zombies around -> not now", #eats == 0); P.visible = 0
P.hunger = 0.3; P.moving = true; fire("EveryTenMinutes"); expect("walking and only peckish -> keep walking", #eats == 0)
P.hunger = 0.7; fire("EveryTenMinutes"); expect("walking but starving -> eat anyway", #eats == 1)
clear(); P.hunger = 0.5; P.stuffed = 3; main.list = {food{type = "Bread"}}
fire("EveryTenMinutes"); expect("stuffed moodle -> no eating", #eats == 0)
clear(); P.hunger = 0.5; P.stuffed = 0; main.list = {food{type = "Bread"}}
S.on = false; fire("EveryTenMinutes"); expect("master switch off -> nothing", #eats == 0); S.on = true
N.cfg.ENABLED = false; fire("EveryTenMinutes"); expect("needs disabled in config -> nothing", #eats == 0); N.cfg.ENABLED = true

-- 10 it did not take: three strikes then stand down
effect = false
clear(); P.hunger = 0.5; main.list = {}
for i = 1, 6 do main.list[#main.list + 1] = food{type = "Bread" .. i} end
for i = 1, 3 do fire("EveryTenMinutes") end
expect("hunger never drops (e.g. nausea): three tries", #eats == 3)
fire("EveryTenMinutes")
expect("fourth beat: stands down instead of trying again", #eats == 3 and N.state.nextTry.eat == S.beat + N.cfg.BACKOFF_BEATS)
effect = true

-- 11 one throw does not kill the chore; many do (breaker)
clear(); P.hunger = 0.5; main.list = {food{type = "Bread"}}
ISInventoryPaneContextMenu.eatItem = function() error("boom") end
for i = 1, 3 do fire("EveryTenMinutes") end
expect("a throwing eat is contained and the chore switches itself off after 3", S.off.needs == true)
fire("OnKeyPressed", 76); fire("OnKeyPressed", 76)
expect("Numpad 5 off/on re-arms the needs chore", S.off.needs == false)

print(string.format("%d checks, %d failed", n, fails))
if fails > 0 then error("needs_test failed") end
