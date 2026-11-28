-- Empire QoL :: 21_EmpireMenu.lua  (28 Nov 2026, B42.22)
-- King: "make a better one... same for base and everything... is it possible for you to create menus and good UIs".
-- One window that holds every Empire feature as a labelled button, so nothing needs a numpad key you forgot
-- or a right-click submenu you have to hunt for. The keys still work; each button shows its key.
--
--   Numpad 0   opens / closes the Empire menu          Right-click the ground > "Empire: Menu"
--
--   Travel      Travel window (coordinates, saved places)   Go Home (the Base waypoint)
--   Base        Sort the base now     Find an item...     Loot nearby corpses     Top off magazines
--               Auto-chores ON/OFF (the 10-minute beat: unload the truck, sort, loot, farm, production)
--   Base zone   Set the base here (flood-fills the walled area you stand in)     Show / Hide the outline
--   Cheats      Item list     Spawn a vehicle     Zombies attack my walls ON/OFF
--
-- Pattern: the command-palette / quick-actions panel of mod menus (a short grouped list of verbs with their
-- keys written on the button), two columns so the whole thing is one screen. State buttons (auto-chores, walls)
-- re-label themselves in place and keep the window open; action buttons close it and run.
--
-- Everything it calls is a public entry the features already had or got for this menu: EmpireSortAll.run,
-- EmpireQoL_Vacuum, EmpireQoL_TopOffMags, EmpireQoL_FindPrompt, EmpireAutoChores.toggle, EmpireZonesPaint,
-- EmpireCheats, EmpireWaypoints. A feature that is not installed shows its button greyed out.
-- PERFORMANCE: nothing per frame; the window removes itself from the UI manager when closed.

if not (ISCollapsableWindow and ISButton and ISLabel and getTextManager) then
    print("[EmpireQoL] Empire menu: UI classes missing, window not installed")
    return
end

EmpireMenu = EmpireMenu or {}
local M = EmpireMenu
local TAG = "[EmpireMenu] "

EmpireMenuUI = ISCollapsableWindow:derive("EmpireMenuUI")
local UI = EmpireMenuUI

local FONT = UIFont.Small
local FONT_HGT = getTextManager():getFontHeight(FONT)
local PAD = 10
local BTN_H = FONT_HGT + 10
local GAP = 6
local WIN_W = 480

local function player0()
    local p = getSpecificPlayer(0)
    if p and not p:isDead() then return p end
    return nil
end

local function has(name) return type(_G[name]) == "function" end

local function choresOn()
    local on = true
    pcall(function() on = EmpireAutoChores.state.on end)
    return on
end

-- ---------- what the buttons are ----------
-- label: string or function -> string. run(player). keep: stay open afterwards. ok(): false greys it out.
local SECTIONS = {
    { title = "Travel", items = {
        { label = "Travel window   [Numpad 1]",
          ok = function() return EmpireWaypoints ~= nil and EmpireWaypoints.openUI ~= nil end,
          run = function(p) EmpireWaypoints.openUI(p) end },
        { label = "Home / Back   [Shift+Numpad 1]",
          ok = function() return EmpireWaypoints ~= nil end,
          run = function(p) EmpireWaypoints.homeOrBack(p) end },
    } },
    { title = "Base", items = {
        { label = "Sort the base   [Numpad 3]",
          ok = function() return EmpireSortAll ~= nil and EmpireSortAll.run ~= nil end,
          run = function(p) EmpireSortAll.run(p) end },
        { label = "Find an item   [Numpad 2]", ok = function() return has("EmpireQoL_FindPrompt") end,
          run = function() EmpireQoL_FindPrompt() end },
        { label = "Loot corpses   [Numpad 7]", ok = function() return has("EmpireQoL_Vacuum") end,
          run = function() EmpireQoL_Vacuum(nil) end },
        { label = "Top off mags   [Numpad 8]", ok = function() return has("EmpireQoL_TopOffMags") end,
          run = function() EmpireQoL_TopOffMags() end },
        { label = function() return "Auto-chores: " .. (choresOn() and "ON" or "OFF") .. "   [Numpad 5]" end, keep = true,
          ok = function() return EmpireAutoChores ~= nil and EmpireAutoChores.toggle ~= nil end,
          run = function() EmpireAutoChores.toggle() end },
    } },
    { title = "Base zone (stand inside the walled area first)", items = {
        { label = function()
              local has_ = EmpireZonesPaint and EmpireZonesPaint.baseZone and EmpireZonesPaint.baseZone()
              return has_ and "Re-detect the base here" or "Set the base here"
          end,
          ok = function() return EmpireZonesPaint ~= nil and EmpireZonesPaint.autoDetect ~= nil end, keep = true,
          run = function(p) EmpireZonesPaint.autoDetect(0) end },
        { label = "Show the outline", keep = true,
          ok = function() return EmpireZonesPaint ~= nil and EmpireZonesPaint.baseZone ~= nil and EmpireZonesPaint.baseZone() ~= nil end,
          run = function() EmpireZonesPaint.show(0) end },
        { label = "Hide the outline", keep = true,
          ok = function() return EmpireZonesPaint ~= nil and EmpireZonesPaint.hide ~= nil end,
          run = function() EmpireZonesPaint.hide(0) end },
    } },
    { title = "Cheats", items = {
        { label = "Item list   [Numpad 4]",
          ok = function() return EmpireCheats ~= nil and EmpireCheats.openItems ~= nil end,
          run = function() EmpireCheats.openItems() end },
        { label = "Spawn vehicle   [Numpad 6]",
          ok = function() return EmpireCheats ~= nil and EmpireCheats.openVehicles ~= nil end,
          run = function() EmpireCheats.openVehicles() end },
        { label = function()
              local cur = EmpireCheats and EmpireCheats.thumpOn and EmpireCheats.thumpOn()
              if cur == nil then return "Zombies and my walls" end
              return cur and "Zombies attack my walls: ON (click: stop)" or "Zombies leave my walls alone: ON (click: undo)"
          end, keep = true,
          ok = function() return EmpireCheats ~= nil and EmpireCheats.thumpOn ~= nil and EmpireCheats.thumpOn() ~= nil end,
          run = function(p) EmpireCheats.toggleThump(p) end },
    } },
}
M.SECTIONS = SECTIONS

-- ---------- window ----------

local function titleOf(item)
    if type(item.label) == "function" then
        local ok, t = pcall(item.label)
        return ok and t or "?"
    end
    return item.label
end

local function itemOk(item)
    if not item.ok then return true end
    local ok, r = pcall(item.ok)
    return ok and r and true or false
end

function UI:createChildren()
    ISCollapsableWindow.createChildren(self)
    -- wide enough that no two-column label is clipped
    local half = math.floor((WIN_W - PAD * 3) / 2)
    for _, sec in ipairs(SECTIONS) do
        for i, item in ipairs(sec.items) do
            if not (i == #sec.items and i % 2 == 1) then
                half = math.max(half, getTextManager():MeasureStringX(FONT, titleOf(item)) + 24)
            end
        end
    end
    self:setWidth(half * 2 + PAD * 3)
    local x = PAD
    local w = self.width - PAD * 2
    local y = self:titleBarHeight() + PAD
    self.buttons = {}
    for _, sec in ipairs(SECTIONS) do
        local l = ISLabel:new(x, y, BTN_H, sec.title, 0.75, 0.75, 0.75, 1, FONT, true)
        l:initialise(); l:instantiate()
        self:addChild(l)
        y = y + BTN_H
        for i, item in ipairs(sec.items) do
            local col = (i - 1) % 2
            local bx = x + col * (half + PAD)
            local bw = half
            if i == #sec.items and col == 0 then bw = w end      -- a lone last button takes the whole row
            local b = ISButton:new(bx, y, bw, BTN_H, titleOf(item), self, UI.onItem)
            b:initialise(); b:instantiate()
            b.borderColor = { r = 1, g = 1, b = 1, a = 0.1 }
            b.item = item
            self:addChild(b)
            self.buttons[#self.buttons + 1] = b
            if col == 1 or i == #sec.items then y = y + BTN_H + GAP end
        end
        y = y + PAD - GAP
    end
    local hint = ISLabel:new(x, y, BTN_H, "Numpad keys still work too (NumLock ON).", 0.6, 0.6, 0.6, 1, FONT, true)
    hint:initialise(); hint:instantiate()
    self:addChild(hint)
    y = y + BTN_H
    self.closeBtn = ISButton:new(x, y, w, BTN_H, "Close", self, UI.close)
    self.closeBtn:initialise(); self.closeBtn:instantiate()
    self.closeBtn.borderColor = { r = 1, g = 1, b = 1, a = 0.1 }
    self.closeBtn:enableCancelColor()
    self:addChild(self.closeBtn)
    y = y + BTN_H + PAD
    self:setHeight(y)
    self:refresh()
end

function UI:refresh()
    for _, b in ipairs(self.buttons or {}) do
        b:setTitle(titleOf(b.item))
        b:setEnable(itemOk(b.item))
    end
end

function UI:onItem(button)
    local item = button and button.item
    if not item then return end
    local p = player0()
    if not p then return end
    if not item.keep then self:close() end
    local ok, err = pcall(item.run, p)
    if not ok then print(TAG .. "button '" .. tostring(titleOf(item)) .. "' failed: " .. tostring(err)) end
    if item.keep and UI.instance == self then self:refresh() end
end

function UI:close()
    self:setVisible(false)
    self:removeFromUIManager()
    if UI.instance == self then UI.instance = nil end
end

function UI:new(x, y, playerNum)
    local o = ISCollapsableWindow.new(self, x, y, WIN_W, 600)
    o.playerNum = playerNum or 0
    o.title = "Empire Menu"
    o:setResizable(false)
    return o
end

function M.open(player)
    if UI.instance then pcall(function() UI.instance:close() end) end
    local pn = 0
    pcall(function() pn = player and player:getPlayerNum() or 0 end)
    local ok, err = pcall(function()
        local win = UI:new(0, 0, pn)
        win:initialise()
        win:addToUIManager()
        local x, y = 100, 60
        pcall(function()
            x = getPlayerScreenLeft(pn) + (getPlayerScreenWidth(pn) - win.width) / 2
            y = getPlayerScreenTop(pn) + math.max(10, (getPlayerScreenHeight(pn) - win.height) / 2)
        end)
        win:setX(x); win:setY(y)
        win:bringToTop()
        UI.instance = win
    end)
    if not ok then print(TAG .. "could not open the window: " .. tostring(err)); return false end
    return true
end

function M.toggle(player)
    if UI.instance and UI.instance:isVisible() then UI.instance:close(); return false end
    return M.open(player)
end

-- ---------- Numpad 0 and the right-click entry ----------

Events.OnKeyPressed.Add(function(key)
    local k0 = 82   -- lwjgl KEY_NUMPAD0
    pcall(function() if Keyboard and Keyboard.KEY_NUMPAD0 then k0 = Keyboard.KEY_NUMPAD0 end end)
    if key ~= k0 then return end
    local p = player0()
    if p then pcall(M.toggle, p) end
end)

Events.OnFillWorldObjectContextMenu.Add(function(playerNum, context, worldobjects, test)
    if test then return end
    local p = getSpecificPlayer(playerNum)
    if not p or p:isDead() then return end
    context:addOption("Empire: Menu (Numpad 0)", p, M.open)
end)

print("[EmpireQoL] Empire menu loaded: Numpad 0 = every Empire feature in one window")
