-- Mock test for 20_TravelMenu.lua (28 Nov 2026): the Empire Travel window on top of 18_Waypoints.lua.
-- Logic only: the UI classes below are small stand-ins written from the 42.22.2 vanilla ISUI sources (method names and
-- call signatures checked against them); how the window LOOKS is judged in the game.
-- Run: node tests/chores/runner.js EmpireQoL/42/media/lua/client/18_Waypoints.lua tests/chores/travelmenu_test.lua \
--          EmpireQoL/42/media/lua/client/20_TravelMenu.lua
local handlers = {}
Events = setmetatable({}, {__index = function(t, name)
  local e = {
    Add = function(f) handlers[name] = handlers[name] or {}; table.insert(handlers[name], f) end,
    Remove = function(f)
      for i, h in ipairs(handlers[name] or {}) do if h == f then table.remove(handlers[name], i); return end end
    end}
  rawset(t, name, e); return e end})
local function fire(name, ...) for _, h in ipairs({table.unpack(handlers[name] or {})}) do h(...) end end

Keyboard = {KEY_NUMPAD1 = 79}
local shiftDown = false
function isShiftKeyDown() return shiftDown end
local halos = {}
HaloTextHelper = {
  addTextWithArrow = function(p, msg) halos[#halos + 1] = msg end,
  getColorGreen = function() return 1 end, getColorWhite = function() return 2 end, getColorRed = function() return 3 end}
local function lastHalo() return halos[#halos] or "" end
local mdStore = {}
ModData = {getOrCreate = function(k) mdStore[k] = mdStore[k] or {}; return mdStore[k] end}
ISTimedActionQueue = {clear = function() end}
IsoFlagType = {water = "water"}
local lastMenu
ISContextMenu = {getNew = function(_, parent) local m = {opts = {}}
  m.addOption = function(self, name, target, fn, ...) local o = {name = name, target = target, fn = fn, args = {...}}; self.opts[#self.opts + 1] = o; return o end
  m.addSubMenu = function(self, opt, sub) opt.sub = sub end
  return m end}
ISWorldMap = nil

local mapInvalid = false
function getWorld() return {getMetaGrid = function() return {isValidChunk = function() return not mapInvalid end} end} end

-- ---- physics + vehicles (same idea as waypoints_test.lua, trimmed) ----
local OFFX, OFFY = 1000, 2000
local function vec(x, y, z) local v = {X = x, Y = y, Z = z}
  function v:x() return self.X end function v:y() return self.Y end function v:z() return self.Z end
  function v:set(a, b, c) self.X, self.Y, self.Z = a, b, c; return self end
  return v end
Transform = {new = function() local t = {origin = vec(0, 0, 0)}; function t:getOrigin() return self.origin end; return t end}
local world = {loaded = true, vehicles = {}}
function getCell() return {
  getVehicles = function() return {iterator = function() local i = 0; return {hasNext = function() return i < #world.vehicles end,
      next = function() i = i + 1; return world.vehicles[i] end} end} end,
  getGridSquare = function(_, x, y, z)
    if not world.loaded then return nil end
    return {isFree = function() return true end, hasFloor = function() return true end, HasTree = function() return false end,
            hasWater = function() return false end, getProperties = function() return {Is = function() return false end} end}
  end} end
local function newVehicle(id, name, x, y)
  local v = {id = id, name = name, x = x, y = y, z = 0, moves = {}, entered = nil}
  function v:getId() return self.id end
  function v:getScriptName() return "Base." .. self.name end
  function v:getX() if self.phys then return self.phys.x + OFFX end return self.x end
  function v:getY() if self.phys then return self.phys.y + OFFY end return self.y end
  function v:getZ() return self.z end
  function v:setX(a) self.x = a end function v:setY(a) self.y = a end function v:setZ(a) self.z = a end
  function v:getWorldTransform(t) t.origin:set(self:getX() - OFFX, self.z, self:getY() - OFFY); return t end
  function v:setWorldTransform(t) local o = t.origin; self.phys = {x = o:x(), y = o:z()}; self.z = o:y(); self.moves[#self.moves + 1] = true end
  function v:setPhysicsActive() end
  function v:getVehicleTowing() return nil end function v:getVehicleTowedBy() return nil end
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
EmpireAutoChores = {armUnload = function() end}

-- ---- UI class stand-ins ----
UIFont = {Small = "Small"}
function getTextManager() return {getFontHeight = function() return 14 end, MeasureStringX = function(_, f, t) return #tostring(t) * 7 end} end
function getPlayerScreenLeft() return 0 end function getPlayerScreenTop() return 0 end
function getPlayerScreenWidth() return 1920 end function getPlayerScreenHeight() return 1080 end

local uiManager = {}
local function noop() end
local function class(base)
  local c = {}; c.__index = c
  if base then setmetatable(c, {__index = base}) end
  function c:derive(name) return class(self) end
  return c
end
ISCollapsableWindow = class()
function ISCollapsableWindow:new(x, y, w, h)
  local o = {x = x, y = y, width = w, height = h, children = {}, visible = true}
  setmetatable(o, self); self.__index = self; return o end
function ISCollapsableWindow:initialise() self:createChildren() end
function ISCollapsableWindow:createChildren() self.baseChildren = true end
function ISCollapsableWindow:titleBarHeight() return 16 end
function ISCollapsableWindow:addChild(c) self.children[#self.children + 1] = c end
function ISCollapsableWindow:setHeight(h) self.height = h end
function ISCollapsableWindow:setX(x) self.x = x end function ISCollapsableWindow:setY(y) self.y = y end
function ISCollapsableWindow:setResizable() end
function ISCollapsableWindow:bringToTop() end
function ISCollapsableWindow:setVisible(v) self.visible = v end
function ISCollapsableWindow:isVisible() return self.visible end
function ISCollapsableWindow:addToUIManager() uiManager[self] = true end
function ISCollapsableWindow:removeFromUIManager() uiManager[self] = nil end
function ISCollapsableWindow:close() self:setVisible(false) end

ISLabel = class()
function ISLabel:new(x, y, h, name) return setmetatable({x = x, y = y, name = name}, self) end
function ISLabel:initialise() end function ISLabel:instantiate() end
function ISLabel:setName(n) self.name = n end

ISButton = class()
function ISButton:new(x, y, w, h, title, target, onclick) return setmetatable({x = x, y = y, width = w, title = title, target = target, onclick = onclick, enable = true, borderColor = {}}, self) end
function ISButton:initialise() end function ISButton:instantiate() end
function ISButton:setEnable(e) self.enable = e end
function ISButton:setTitle(t) self.title = t end
function ISButton:enableAcceptColor() self.accept = true end
function ISButton:enableCancelColor() self.cancel = true end
local function click(b) assert(b.enable ~= false, "clicked a disabled button: " .. tostring(b.title)); b.onclick(b.target, b) end

ISTextEntryBox = class()
function ISTextEntryBox:new(title, x, y, w, h) return setmetatable({text = title, x = x, y = y, width = w, focused = false}, self) end
function ISTextEntryBox:initialise() end function ISTextEntryBox:instantiate() end
function ISTextEntryBox:setOnlyNumbers() self.numbers = true end
function ISTextEntryBox:getText() return self.text end
function ISTextEntryBox:setText(t) self.text = t or "" end
function ISTextEntryBox:isFocused() return self.focused end

ISScrollingListBox = class()
function ISScrollingListBox:new(x, y, w, h) return setmetatable({x = x, y = y, width = w, height = h, items = {}, count = 0, selected = 1, itemheight = 20,
  borderColor = {r = 1, g = 1, b = 1}, drawn = {}}, self) end
function ISScrollingListBox:initialise() end function ISScrollingListBox:instantiate() end
function ISScrollingListBox:addItem(name, item) local i = {text = name, item = item, height = self.itemheight}; self.items[#self.items + 1] = i; self.count = self.count + 1; return i end
function ISScrollingListBox:clear() self.items = {}; self.selected = 1; self.count = 0 end
function ISScrollingListBox:setOnMouseDownFunction(t, f) self.onmousedown = f; self.target = t end
function ISScrollingListBox:setOnMouseDoubleClick(t, f) self.onmousedblclick = f; self.target = t end
function ISScrollingListBox:getYScroll() return 0 end function ISScrollingListBox:getWidth() return self.width end
function ISScrollingListBox:isMouseOver() return false end function ISScrollingListBox:isMouseOverScrollBar() return false end
function ISScrollingListBox:drawSelection() self.drawn[#self.drawn + 1] = "selection" end
function ISScrollingListBox:drawMouseOverHighlight() end function ISScrollingListBox:drawRectBorder() end
function ISScrollingListBox:drawText(t) self.drawn[#self.drawn + 1] = t end
local function pickRow(win, i) win.list.selected = i; win.list.onmousedown(win.list.target, win.list.items[i].item) end

ISTickBox = class()
function ISTickBox:new(x, y, w, h, name, target, method) return setmetatable({options = {}, selected = {}, disabled = {}, target = target, method = method}, self) end
function ISTickBox:initialise() end
function ISTickBox:clearOptions() self.options = {}; self.selected = {}; self.disabled = {} end
function ISTickBox:addOption(name) self.options[#self.options + 1] = name; return #self.options end
function ISTickBox:setSelected(i, s) if not self.options[i] then error("invalid index") end self.selected[i] = s end
function ISTickBox:isSelected(i) if not self.options[i] then error("invalid index") end return self.selected[i] == true end
function ISTickBox:disableOption(name, d) self.disabled[name] = d end

-- ---- load both files ----
assert(load(SRC, "waypoints"))()
assert(load(SRC2, "travelmenu"))()
local W = EmpireWaypoints
local UI = EmpireTravelUI

local n, fails = 0, 0
local function expect(name, c) n = n + 1; if c then print("PASS " .. name) else fails = fails + 1; print("FAIL " .. name) end end
local function ticks(k) for _ = 1, k do fire("OnTick") end end
local function count(name) return #(handlers[name] or {}) end
local function reset()
  world.vehicles = {}; world.loaded = true; P.tp = {}; P.vehicle = nil; P.chased = 0; P.x, P.y, P.z = 100, 100, 0
  halos = {}; mdStore.EmpireWaypoints = nil; handlers.OnTick = {}; shiftDown = false; mapInvalid = false
  if UI.instance then UI.instance:close() end
  for k in pairs(uiManager) do uiManager[k] = nil end
end
local function open() W.openUI(P); return UI.instance end
local function titles(win) local t = {} for _, c in ipairs(win.children) do if c.title then t[#t + 1] = c.title end end return table.concat(t, "|") end

-- 1. Numpad 1 opens and closes the window
reset(); fire("OnGameStart")
fire("OnKeyPressed", 79)
local win = UI.instance
expect("Numpad 1 opens the Travel window", win and win:isVisible() and uiManager[win] and #P.tp == 0)
expect("window is centred on the screen", win.x > 400 and win.y >= 10 and win.x + win.width < 1920)
expect("window sized by its content", win.height > 300 and win.height < 700)
fire("OnKeyPressed", 79)
expect("Numpad 1 again closes it and takes it out of the UI manager", not win:isVisible() and not uiManager[win] and UI.instance == nil)
shiftDown = true; fire("OnKeyPressed", 79)
expect("Shift+Numpad 1 is the one-press trip, no window", #P.tp == 1 and P.tp[1].x == 6032 and UI.instance == nil)
ticks(20); shiftDown = false

-- 2. contents: status, home, seeded Base row
reset(); fire("OnGameStart"); P.x, P.y = 2636, 10877
win = open()
expect("status line says where you are", win.hereLabel.name:find("You are at 2636, 10877"))
expect("one row per saved place, Base seeded", #win.list.items == 1 and win.list.items[1].item.wp.name == "Base")
expect("distance text on the row", win.list.items[1].item.distText:find("k tiles"))
expect("Home button is on and names the base", win.homeBtn.enable and win.homeBtn.title:find("Base"))
expect("Back is off before any trip", win.backBtn.enable == false)
expect("Go to place is off until a row is picked", win.goBtn.enable == false)
expect("no truck near: option says so and is disabled", win.truckTick.options[1]:find("No truck") and win.truckTick.disabled[win.truckTick.options[1]] and win.takeTruck == false)

-- 3. picking a row fills the form; Base cannot be deleted
pickRow(win, 1)
expect("picking fills X, Y and name", win.xEntry.text == "6032" and win.yEntry.text == "5238" and win.zEntry.text == "" and win.nameEntry.text == "Base")
expect("Go to place names the pick", win.goBtn.enable and win.goBtn.title == "Go to Base")
expect("Base cannot be deleted from the window", win.delBtn.enable == false and win.delBtn.title:find("Base"))

-- 4. Go Home on foot closes the window and travels
click(win.homeBtn)
expect("Go Home teleports to the base and closes the window", #P.tp == 1 and P.tp[1].x == 6032 and not win:isVisible() and UI.instance == nil)
ticks(20)
expect("Back is on after a trip", (function() local w2 = open(); local ok = w2.backBtn.enable; w2:close(); return ok end)())

-- 5. typed coordinates
reset(); fire("OnGameStart"); win = open()
win.xEntry:setText("3010"); win.yEntry:setText("4020"); win.zEntry:setText("")
click(win.goXYBtn)
expect("Go to coordinates travels there at ground level", #P.tp == 1 and P.tp[1].x == 3010 and P.tp[1].y == 4020 and P.tp[1].z == 0 and not win:isVisible())
ticks(20)
reset(); fire("OnGameStart"); win = open()
win.xEntry:setText(""); win.yEntry:setText("4020")
click(win.goXYBtn)
expect("missing X: asks for it, no travel, window stays", #P.tp == 0 and lastHalo():find("Type the X and Y") and win:isVisible())
win.xEntry:setText("3010"); mapInvalid = true
click(win.goXYBtn)
expect("outside the map is refused", #P.tp == 0 and lastHalo():find("outside the map"))
mapInvalid = false
win.zEntry:setText("2")
click(win.goXYBtn)
expect("height is passed on", #P.tp == 1 and P.tp[1].z == 2)
ticks(20)

-- 6. save coordinates (and edit by saving over the same name)
reset(); fire("OnGameStart"); win = open()
win.xEntry:setText("7000"); win.yEntry:setText("8000"); win.nameEntry:setText("Far farm")
click(win.saveXYBtn)
local saved = W.store().list[2]
expect("Save coordinates adds a place", saved and saved.name == "Far farm" and saved.x == 7000 and saved.y == 8000 and saved.hasV == false and saved.typed)
expect("list rebuilt with the new row", #win.list.items == 2)
pickRow(win, 2)
win.xEntry:setText("7100")
click(win.saveXYBtn)
expect("saving under the same name edits it in place", #W.store().list == 2 and W.store().list[2].x == 7100)
win.nameEntry:setText("   ")
click(win.saveXYBtn)
expect("blank name refused", #W.store().list == 2 and lastHalo():find("needs a name"))
expect("the pick survives a rebuild", win:picked() and win:picked().name == "Far farm")

-- 7. save my spot here keeps the truck spot
reset(); fire("OnGameStart")
local truck = newVehicle(7, "Tatra815", 103, 100); P.x, P.y = 106, 100
win = open()
win.nameEntry:setText("Echo Creek")
click(win.saveHereBtn)
expect("Save my spot here stores position and truck spot", W.store().list[2] and W.store().list[2].name == "Echo Creek" and W.store().list[2].hasV and W.store().list[2].vx == 103)
expect("row shows the truck spot tag", (function()
  local l = win.list; local it = l.items[2]; l.drawn = {}; UI.drawRow(l, 0, it, false)
  return table.concat(l.drawn, "|"):find("truck spot") and table.concat(l.drawn, "|"):find("Echo Creek") and table.concat(l.drawn, "|"):find("106, 100")
end)())

-- 8. delete asks twice
pickRow(win, 2)
expect("Delete is armed only after the first click", win.delBtn.title == "Delete")
click(win.delBtn)
expect("first click asks 'Really delete'", win.delBtn.title:find("Really delete Echo Creek") and #W.store().list == 2)
pickRow(win, 2); click(win.delBtn); click(win.delBtn)
expect("second click deletes it", #W.store().list == 1 and #win.list.items == 1)
W.saveHere(P, "A"); win:refresh(); pickRow(win, 2); click(win.delBtn); pickRow(win, 1)
expect("picking another row disarms the delete", win.delBtn.title ~= "Really delete A?" and #W.store().list == 2)

-- 9. the truck tick box
reset(); fire("OnGameStart")
truck = newVehicle(7, "Tatra815", 100, 100); P.vehicle = truck
win = open()
expect("truck near: tick box offers it, ticked by default", win.truckTick.options[1] == "Take the Tatra815 along" and win.truckTick:isSelected(1) and win:wantTruck())
win:onTruckTick(1, false)
click(win.homeBtn)
expect("tick off: Go Home leaves the truck behind", #P.tp == 1 and #truck.moves == 0)
ticks(20)
reset(); fire("OnGameStart")
truck = newVehicle(7, "Tatra815", 100, 100); P.vehicle = truck
win = open()
click(win.homeBtn)
expect("tick on: Go Home takes the truck", #truck.moves == 1 and #P.tp == 1)
ticks(20)
expect("truck came along and the driver is seated", truck.entered and truck.entered.seat == 0 and lastHalo():find("with the Tatra815"))
-- reopening remembers the choice
reset(); fire("OnGameStart"); truck = newVehicle(7, "Tatra815", 100, 100); P.vehicle = truck
win = open(); win:onTruckTick(1, false); win:refresh()
expect("a refresh keeps the tick state", win.truckTick:isSelected(1) == false and win:wantTruck() == false)

-- 10. double click goes, Back after a trip
reset(); fire("OnGameStart"); W.saveAt(P, "Mall", 4000, 4100); win = open()
pickRow(win, 2)
win.list.onmousedblclick(win.list.target, win.list.items[2].item)
expect("double-click on a row travels there", #P.tp == 1 and P.tp[1].x == 4000 and P.tp[1].y == 4100 and not win:isVisible())
ticks(20)
win = open()
click(win.backBtn)
expect("Back to where I left from returns to the start", #P.tp == 2 and P.tp[2].x == 100 and P.tp[2].y == 100)
ticks(20)

-- 11. already home, chased
reset(); fire("OnGameStart"); P.x, P.y = 6040, 5240; win = open()
click(win.homeBtn)
expect("at home: says so, no teleport", #P.tp == 0 and lastHalo():find("already home") and win:isVisible())
P.x, P.y = 100, 100; P.chased = 2
click(win.homeBtn)
expect("chased: travel refused and the window stays open", #P.tp == 0 and lastHalo():find("Zombies") and win:isVisible())

-- 12. typing in a box keeps Numpad 1 from toggling the window
reset(); fire("OnGameStart"); win = open()
win.xEntry.focused = true
fire("OnKeyPressed", 79)
expect("a focused text box swallows Numpad 1", win:isVisible() and UI.instance == win)
win.xEntry.focused = false
fire("OnKeyPressed", 79)
expect("unfocused: Numpad 1 closes it", not win:isVisible())

-- 13. right-click menu entry; opening twice keeps one window
reset(); fire("OnGameStart")
local menu = ISContextMenu:getNew(nil)
fire("OnFillWorldObjectContextMenu", 0, menu, {}, false)
local sub = menu.opts[1].sub
expect("right-click submenu starts with the Travel window", sub.opts[1].name:find("Open the Travel window"))
sub.opts[1].fn(sub.opts[1].target)
local w1 = UI.instance
W.openUI(P)
expect("opening twice leaves exactly one window", UI.instance ~= w1 and not w1:isVisible() and not uiManager[w1] and uiManager[UI.instance])

-- 14. the old engine still works without the window file loaded: openUI exists only here
expect("no per-frame handlers registered by the window", count("OnTick") == 0)

print(n .. " checks, " .. fails .. " failed"); if fails > 0 then error("failures") end
