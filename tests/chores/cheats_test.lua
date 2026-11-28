-- Mock test for 50_Cheats.lua: the doors open the vanilla windows, nothing else.
local handlers = {}
Events = setmetatable({}, {__index = function(t, name)
  local e = {Add = function(f) handlers[name] = handlers[name] or {}; table.insert(handlers[name], f) end}
  rawset(t, name, e); return e end})
local function fire(name, ...) for _, h in ipairs(handlers[name] or {}) do h(...) end end
Keyboard = {KEY_NUMPAD4 = 75, KEY_NUMPAD6 = 77}
local P = {}
function getSpecificPlayer() return P end
local opened = {items = 0, veh = 0, vehDestroyed = 0, vehPlayer = nil}
ISItemsListViewer = {OnOpenPanel = function() opened.items = opened.items + 1 end}
ISSpawnVehicleUI = {new = function(self, x, y, w, h, p)
  local o = {destroy = function() opened.vehDestroyed = opened.vehDestroyed + 1 end}
  function o:initialise() end function o:addToUIManager() opened.veh = opened.veh + 1 end
  opened.vehPlayer = p; return o end}
ISContextMenu = {getNew = function() local m = {opts = {}}
  m.addOption = function(self, name, target, fn) local o = {name = name, target = target, fn = fn}; self.opts[#self.opts + 1] = o; return o end
  m.addSubMenu = function(self, opt, sub) opt.sub = sub end
  return m end}
local f = assert(load(SRC, "cheats")); f()
local n, fails = 0, 0
local function expect(name, c) n = n + 1; if c then print("PASS " .. name) else fails = fails + 1; print("FAIL " .. name) end end
fire("OnKeyPressed", 75)
expect("Numpad 4 opens the item list", opened.items == 1)
fire("OnKeyPressed", 77)
expect("Numpad 6 opens the spawn-vehicle window for player 1", opened.veh == 1 and opened.vehPlayer == P)
fire("OnKeyPressed", 77)
expect("a second open closes the first window", opened.veh == 2 and opened.vehDestroyed == 1)
fire("OnKeyPressed", 12)
expect("other keys ignored", opened.items == 1 and opened.veh == 2)
local menu = ISContextMenu:getNew()
fire("OnFillWorldObjectContextMenu", 0, menu, {}, false)
local top = menu.opts[1]
expect("right-click has Empire: Cheats with two entries", top and top.name == "Empire: Cheats" and #top.sub.opts == 2)
top.sub.opts[1].fn(top.sub.opts[1].target); top.sub.opts[2].fn(top.sub.opts[2].target)
expect("menu entries open both windows", opened.items == 2 and opened.veh == 3)
local m2 = ISContextMenu:getNew(); fire("OnFillWorldObjectContextMenu", 0, m2, {}, true)
expect("menu skipped on the test pass", #m2.opts == 0)
ISItemsListViewer = nil
expect("missing vanilla UI is handled, no throw", select(1, pcall(EmpireCheats.openItems)) == true and EmpireCheats.openItems() == false)
print(n .. " checks, " .. fails .. " failed"); if fails > 0 then error("failures") end
