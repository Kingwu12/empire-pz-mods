-- Mock test for 21_EmpireMenu.lua (28 Nov 2026): the Empire menu (every feature as a button).
-- Run: node tests/chores/runner.js EmpireQoL/42/media/lua/client/21_EmpireMenu.lua tests/chores/empiremenu_test.lua
local handlers = {}
Events = setmetatable({}, {__index = function(t, name)
  local e = {Add = function(f) handlers[name] = handlers[name] or {}; table.insert(handlers[name], f) end,
             Remove = function(f) for i, h in ipairs(handlers[name] or {}) do if h == f then table.remove(handlers[name], i); return end end end}
  rawset(t, name, e); return e end})
local function fire(name, ...) for _, h in ipairs({table.unpack(handlers[name] or {})}) do h(...) end end
Keyboard = {KEY_NUMPAD0 = 82}
ISContextMenu = {}
local P = {}
function P:isDead() return false end function P:getPlayerNum() return 0 end
function getSpecificPlayer() return P end

UIFont = {Small = "Small"}
function getTextManager() return {getFontHeight = function() return 14 end, MeasureStringX = function(_, f, t) return #tostring(t) * 7 end} end
function getPlayerScreenLeft() return 0 end function getPlayerScreenTop() return 0 end
function getPlayerScreenWidth() return 1920 end function getPlayerScreenHeight() return 1080 end
local uiManager = {}
local function class(base) local c = {}; c.__index = c; if base then setmetatable(c, {__index = base}) end; function c:derive() return class(self) end; return c end
ISCollapsableWindow = class()
function ISCollapsableWindow:new(x, y, w, h) local o = {x = x, y = y, width = w, height = h, children = {}, visible = true}; setmetatable(o, self); self.__index = self; return o end
function ISCollapsableWindow:initialise() self:createChildren() end
function ISCollapsableWindow:createChildren() end
function ISCollapsableWindow:titleBarHeight() return 16 end
function ISCollapsableWindow:addChild(c) self.children[#self.children + 1] = c end
function ISCollapsableWindow:setHeight(h) self.height = h end function ISCollapsableWindow:setWidth(w) self.width = w end
function ISCollapsableWindow:setX(x) self.x = x end function ISCollapsableWindow:setY(y) self.y = y end
function ISCollapsableWindow:setResizable() end function ISCollapsableWindow:bringToTop() end
function ISCollapsableWindow:setVisible(v) self.visible = v end function ISCollapsableWindow:isVisible() return self.visible end
function ISCollapsableWindow:addToUIManager() uiManager[self] = true end function ISCollapsableWindow:removeFromUIManager() uiManager[self] = nil end
ISLabel = class()
function ISLabel:new(x, y, h, name) return setmetatable({x = x, y = y, name = name}, self) end
function ISLabel:initialise() end function ISLabel:instantiate() end
ISButton = class()
function ISButton:new(x, y, w, h, title, target, onclick) return setmetatable({x = x, y = y, width = w, title = title, target = target, onclick = onclick, enable = true}, self) end
function ISButton:initialise() end function ISButton:instantiate() end
function ISButton:setEnable(e) self.enable = e end function ISButton:setTitle(t) self.title = t end function ISButton:enableCancelColor() end
local function click(b) assert(b.enable ~= false, "clicked a disabled button: " .. tostring(b.title)); b.onclick(b.target, b) end

assert(load(SRC, "empiremenu"))()
local M, UI = EmpireMenu, EmpireMenuUI
local n, fails = 0, 0
local function expect(name, c) n = n + 1; if c then print("PASS " .. name) else fails = fails + 1; print("FAIL " .. name) end end
local function btn(win, text) for _, b in ipairs(win.buttons) do if b.title:find(text, 1, true) then return b end end error("no button " .. text) end
local function close() if UI.instance then UI.instance:close() end end

-- 1. nothing else installed: opens, every feature button greyed, no errors
fire("OnKeyPressed", 82)
local win = UI.instance
expect("Numpad 0 opens the menu", win and win:isVisible() and uiManager[win])
expect("menu is centred and sized by its content", win.x > 300 and win.height > 300 and win.height < 800)
local allOff = true
for _, b in ipairs(win.buttons) do if b.enable then allOff = false end end
expect("with no feature installed every button is greyed out", allOff and #win.buttons == 13)
fire("OnKeyPressed", 82)
expect("Numpad 0 again closes it", not win:isVisible() and not uiManager[win] and UI.instance == nil)
fire("OnKeyPressed", 12)
expect("other keys ignored", UI.instance == nil)

-- 2. features installed (stubs record the calls)
local calls = {}
local function rec(name) return function(...) calls[#calls + 1] = name; return 0 end end
EmpireWaypoints = {openUI = rec("travel"), homeOrBack = rec("home")}
EmpireSortAll = {run = rec("sort")}
EmpireQoL_FindPrompt = rec("find"); EmpireQoL_Vacuum = rec("vacuum"); EmpireQoL_TopOffMags = rec("mags")
local chores = {state = {on = true}}
chores.toggle = function() chores.state.on = not chores.state.on; calls[#calls + 1] = "chores" end
EmpireAutoChores = chores
local baseExists = false
EmpireZonesPaint = {baseZone = function() return baseExists and {} or nil end,
  autoDetect = function(p) baseExists = true; calls[#calls + 1] = "zone:" .. tostring(p) end,
  show = rec("show"), hide = rec("hide")}
local thump = true
EmpireCheats = {openItems = rec("items"), openVehicles = rec("vehicles"), thumpOn = function() return thump end,
  toggleThump = function() thump = not thump; calls[#calls + 1] = "thump" end}

M.open(P); win = UI.instance
local enabled = 0
for _, b in ipairs(win.buttons) do if b.enable then enabled = enabled + 1 end end
expect("with everything installed all but 'Show outline' are on", enabled == 12 and btn(win, "Show the outline").enable == false)
expect("no label is wider than its button", (function()
  for _, b in ipairs(win.buttons) do if #b.title * 7 + 12 > b.width then return false end end return true end)())

click(btn(win, "Sort the base"))
expect("an action button runs the feature and closes the menu", calls[#calls] == "sort" and not win:isVisible() and UI.instance == nil)
for _, t in ipairs({{"Find an item", "find"}, {"Loot corpses", "vacuum"}, {"Top off mags", "mags"}, {"Item list", "items"},
                    {"Spawn vehicle", "vehicles"}, {"Travel window", "travel"}, {"Home / Back", "home"}}) do
  M.open(P); win = UI.instance; click(btn(win, t[1]))
  expect("button '" .. t[1] .. "' calls " .. t[2], calls[#calls] == t[2] and UI.instance == nil)
end

-- 3. state buttons re-label in place and keep the window open
M.open(P); win = UI.instance
expect("auto-chores shows ON", btn(win, "Auto-chores").title:find("ON"))
click(btn(win, "Auto-chores"))
expect("toggling auto-chores flips the label and keeps the menu", calls[#calls] == "chores" and btn(win, "Auto-chores").title:find("OFF") and win:isVisible())
click(btn(win, "Auto-chores"))
expect("and flips back", btn(win, "Auto-chores").title:find("ON"))
expect("walls button shows the live state", btn(win, "Zombies").title:find("attack my walls: ON"))
click(btn(win, "Zombies"))
expect("walls toggle flips the label", thump == false and btn(win, "Zombies").title:find("leave my walls alone"))
expect("zone button offers to set the base first", btn(win, "Set the base here"))
click(btn(win, "Set the base here"))
expect("zone detect runs for player 0, stays open, label becomes re-detect", calls[#calls] == "zone:0" and win:isVisible() and btn(win, "Re-detect the base here"))
expect("the outline buttons are available once a base exists", btn(win, "Show the outline").enable and btn(win, "Hide the outline").enable)
click(btn(win, "Show the outline")); click(btn(win, "Hide the outline"))
expect("show and hide run and keep the menu", calls[#calls - 1] == "show" and calls[#calls] == "hide" and win:isVisible())

-- 4. a failing feature does not break the menu
EmpireSortAll.run = function() error("boom") end
click(btn(win, "Sort the base"))
expect("a throwing feature is caught", not win:isVisible() and UI.instance == nil)

-- 5. walls switch unavailable (setting not found): greyed
EmpireCheats.thumpOn = function() return nil end
M.open(P); win = UI.instance
expect("walls button greyed when the setting is missing", btn(win, "Zombies and my walls").enable == false)
close()

-- 6. right-click entry; reopening leaves one window
local menu = {opts = {}}
function menu:addOption(name, target, fn) self.opts[#self.opts + 1] = {name = name, target = target, fn = fn} end
fire("OnFillWorldObjectContextMenu", 0, menu, {}, false)
expect("right-click has Empire: Menu", menu.opts[1] and menu.opts[1].name:find("Empire: Menu"))
menu.opts[1].fn(menu.opts[1].target); local w1 = UI.instance
menu.opts[1].fn(menu.opts[1].target)
expect("opening twice leaves exactly one window", UI.instance ~= w1 and not w1:isVisible() and not uiManager[w1])
fire("OnFillWorldObjectContextMenu", 0, menu, {}, true)
expect("skipped on the test pass", #menu.opts == 1)
expect("no per-frame handlers", #(handlers.OnTick or {}) == 0)

print(n .. " checks, " .. fails .. " failed"); if fails > 0 then error("failures") end
