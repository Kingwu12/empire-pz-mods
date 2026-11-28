-- Empire QoL :: 20_TravelMenu.lua  (28 Nov 2026, B42.22)
-- King: "tab 1 you just got it wrong... make a better one, allow me to input coordinates and save places, like
-- just a good menu... same for base and everything".  This is the window; 18_Waypoints.lua is the engine.
--
--   Numpad 1            opens / closes the Empire Travel window.
--   Shift + Numpad 1    the old one-press trip: away from the base = home, at the base = back where you left.
--   Right-click > Empire: Travel > "Open the Travel window".
--
-- WHAT THE WINDOW HAS (pattern: the waypoint screens of map mods, e.g. Xaero's World Map / TomTom: a list of
-- places with their coordinates and distance, picking one fills an edit form with its X / Y / Z and name, and
-- saving under the same name updates it; plus one big Home button, which is what you press 90% of the time):
--   * a status line with where you are, and one tick box "Take the <truck> along" (only when a truck qualifies)
--   * [Go Home] and [Back to where I left from]
--   * the saved places: name, coordinates, distance, "truck spot" tag. Click selects, double-click goes.
--     Selecting fills the form below. [Go to place] [Delete] (Delete asks once more; Base can't be deleted)
--   * form: X, Y, Z (Z empty = ground floor) and Name -> [Go to coordinates] [Save coordinates]
--     [Save my spot here] (that one also keeps the truck's parking spot, like the right-click save).
--
-- PERFORMANCE: nothing runs per frame except the engine's own drawing of the window while it is open. The list
-- is rebuilt only on open and after a save / delete. The window is removed from the UI manager when closed.

if not (ISCollapsableWindow and ISButton and ISLabel and ISTextEntryBox and ISScrollingListBox and ISTickBox
        and EmpireWaypoints and getTextManager) then
    print("[EmpireQoL] Travel menu: UI classes or waypoint engine missing, window not installed")
    return
end

local W = EmpireWaypoints
local CFG = W.CFG
local TAG = "[EmpireTravelMenu] "

EmpireTravelUI = ISCollapsableWindow:derive("EmpireTravelUI")
local UI = EmpireTravelUI

local FONT = UIFont.Small
local FONT_HGT = getTextManager():getFontHeight(FONT)
local PAD = 10
local BTN_H = FONT_HGT + 8
local ROW_H = FONT_HGT * 2 + 8
local LIST_ROWS = 5
local WIN_W = 500

-- ---------- helpers ----------

local function fmtDist(d)
    if d < 1 then return "here" end
    if d >= 10000 then return string.format("%dk tiles", math.floor(d / 1000 + 0.5)) end
    if d >= 1000 then return string.format("%.1fk tiles", d / 1000) end
    return string.format("%d tiles", math.floor(d + 0.5))
end

local function coordText(wp)
    return string.format("%d, %d%s", math.floor(wp.x), math.floor(wp.y), (wp.z and wp.z ~= 0) and (", floor " .. math.floor(wp.z)) or "")
end

local function tagsOf(wp)
    local t = {}
    if wp.name and wp.name:lower() == CFG.HOME_NAME:lower() then t[#t + 1] = "home" end
    if wp.hasV then t[#t + 1] = "truck spot" end
    if wp.fromMap or wp.typed then t[#t + 1] = "coordinates only" end
    return table.concat(t, " · ")
end

local function button(parent, x, y, w, title, fn)
    local b = ISButton:new(x, y, w, BTN_H, title, parent, fn)
    b:initialise()
    b:instantiate()
    b.borderColor = { r = 1, g = 1, b = 1, a = 0.1 }
    parent:addChild(b)
    return b
end

local function label(parent, x, y, text, r, g, b)
    local l = ISLabel:new(x, y, BTN_H, text, r or 1, g or 1, b or 1, 1, FONT, true)
    l:initialise()
    l:instantiate()
    parent:addChild(l)
    return l
end

local function entry(parent, x, y, w, text, numbers)
    local e = ISTextEntryBox:new(text or "", x, y, w, BTN_H)
    e:initialise()
    e:instantiate()
    if numbers then e:setOnlyNumbers(true) end
    parent:addChild(e)
    return e
end

local function player0()
    local p = getSpecificPlayer(0)
    if p and not p:isDead() then return p end
    return nil
end

-- ---------- window ----------

function UI:createChildren()
    ISCollapsableWindow.createChildren(self)
    local x = PAD
    local w = self.width - PAD * 2
    local y = self:titleBarHeight() + PAD

    self.hereLabel = label(self, x, y, "You are at ...")
    y = y + BTN_H + 2

    self.truckTick = ISTickBox:new(x, y, w, BTN_H, "", self, UI.onTruckTick)
    self.truckTick:initialise()
    self:addChild(self.truckTick)
    self.truckTick:addOption("No truck near you")
    self.truckY = y
    y = y + BTN_H + PAD

    local half = math.floor((w - PAD) / 2)
    self.homeBtn = button(self, x, y, half, "Go Home", UI.onHome)
    self.homeBtn:enableAcceptColor()
    self.backBtn = button(self, x + half + PAD, y, w - half - PAD, "Back to where I left from", UI.onBack)
    y = y + BTN_H + PAD

    label(self, x, y, "Saved places (click to pick, double-click to go)", 0.75, 0.75, 0.75)
    y = y + BTN_H

    self.list = ISScrollingListBox:new(x, y, w, ROW_H * LIST_ROWS)
    self.list:initialise()
    self.list:instantiate()
    self.list.itemheight = ROW_H
    self.list.selected = 0
    self.list.font = FONT
    self.list.drawBorder = true
    self.list.doDrawItem = UI.drawRow
    self.list:setOnMouseDownFunction(self, UI.onPick)
    self.list:setOnMouseDoubleClick(self, UI.onGoPlace)
    self:addChild(self.list)
    y = y + ROW_H * LIST_ROWS + PAD

    self.goBtn = button(self, x, y, half, "Go to place", UI.onGoPlace)
    self.delBtn = button(self, x + half + PAD, y, w - half - PAD, "Delete", UI.onDelete)
    y = y + BTN_H + PAD

    label(self, x, y, "Coordinates (the map tooltip shows them as 6032x5238)", 0.75, 0.75, 0.75)
    y = y + BTN_H

    local ex = x
    label(self, ex, y, "X"); ex = ex + 14
    self.xEntry = entry(self, ex, y, 84, "", true); ex = ex + 84 + PAD
    label(self, ex, y, "Y"); ex = ex + 14
    self.yEntry = entry(self, ex, y, 84, "", true); ex = ex + 84 + PAD
    label(self, ex, y, "Z"); ex = ex + 14
    self.zEntry = entry(self, ex, y, 44, "", true)
    y = y + BTN_H + 6

    label(self, x, y, "Name")
    self.nameEntry = entry(self, x + 46, y, w - 46, "", false)
    y = y + BTN_H + PAD

    local third = math.floor((w - PAD * 2) / 3)
    self.goXYBtn = button(self, x, y, third, "Go to coordinates", UI.onGoCoords)
    self.saveXYBtn = button(self, x + third + PAD, y, third, "Save coordinates", UI.onSaveCoords)
    self.saveHereBtn = button(self, x + (third + PAD) * 2, y, w - (third + PAD) * 2, "Save my spot here", UI.onSaveHere)
    y = y + BTN_H + PAD

    self.closeBtn = button(self, x, y, w, "Close", UI.close)
    self.closeBtn:enableCancelColor()
    y = y + BTN_H + PAD

    self:setHeight(y)
    self.takeTruck = true
    self:refresh()
end

function UI:onTruckTick(index, selected)
    self.takeTruck = selected and true or false
end

-- one list row: name + distance, then coordinates + tags
function UI.drawRow(list, y, item, alt)
    if not item.height then item.height = list.itemheight end
    if item.height <= 0 then return y + item.height end
    if (y + list:getYScroll() + list.itemheight < 0) or (y + list:getYScroll() >= list.height) then
        return y + item.height
    end
    if list.selected == item.index then
        list:drawSelection(0, y, list:getWidth(), item.height - 1)
    elseif list.mouseoverselected == item.index and list:isMouseOver() and not list:isMouseOverScrollBar() then
        list:drawMouseOverHighlight(0, y, list:getWidth(), item.height - 1)
    end
    list:drawRectBorder(0, y, list:getWidth(), item.height, 0.5, list.borderColor.r, list.borderColor.g, list.borderColor.b)
    local row = item.item
    local right = list:getWidth() - 14
    if list.vscroll and list.vscroll:isVisible() then right = right - 14 end
    list:drawText(row.wp.name, 12, y + 4, 1, 1, 1, 1, FONT)
    local dt = row.distText
    local dw = getTextManager():MeasureStringX(FONT, dt)
    list:drawText(dt, right - dw, y + 4, 0.85, 0.85, 0.85, 1, FONT)
    local sub = coordText(row.wp)
    local tags = tagsOf(row.wp)
    if tags ~= "" then sub = sub .. "   " .. tags end
    list:drawText(sub, 12, y + 4 + FONT_HGT, 0.6, 0.75, 0.6, 1, FONT)
    return y + item.height
end

-- the place currently picked in the list (the wp table), or nil
function UI:picked()
    local it = self.list.items and self.list.items[self.list.selected]
    return it and it.item and it.item.wp or nil
end

function UI:refresh()
    local p = player0()
    local d = W.store()
    local px, py = 0, 0
    if p then px, py = p:getX(), p:getY() end
    if p then
        self.hereLabel:setName(string.format("You are at %d, %d%s", math.floor(px), math.floor(py),
            (p:getZ() and p:getZ() ~= 0) and (", floor " .. math.floor(p:getZ())) or ""))
    end

    -- the truck that would come along
    local veh, why = nil, nil
    if p then veh, why = W.pickVehicle(p, true) end
    self.truck = veh
    local had = self.takeTruck
    local text, usable = "No truck near you (drive it or park it within 8 tiles)", false
    if veh then
        text, usable = "Take the " .. W.vehicleName(veh) .. " along", true
    elseif why == "trailer" then
        text = "Detach the trailer to take the truck along"
    end
    self.truckTick:clearOptions()
    self.truckTick:addOption(text)
    if usable then
        self.truckTick:setSelected(1, had ~= false)
        self.takeTruck = had ~= false
    else
        self.truckTick:disableOption(text, true)
        self.takeTruck = false
    end

    -- keep the pick across a rebuild
    local keep = self:picked() and self:picked().name or nil
    self.list:clear()
    self.list.selected = 0
    for _, wp in ipairs(d.list) do
        local row = { wp = wp, distText = fmtDist(math.sqrt((wp.x - px) ^ 2 + (wp.y - py) ^ 2)) }
        local it = self.list:addItem(wp.name, row)
        it.index = #self.list.items
        if keep and wp.name == keep then self.list.selected = it.index end
    end
    for i, it in ipairs(self.list.items) do it.index = i end
    self.delConfirm = nil
    self:updateButtons()
end

function UI:updateButtons()
    local wp = self:picked()
    local d = W.store()
    local _, home = nil, nil
    for _, w in ipairs(d.list) do if w.name:lower() == CFG.HOME_NAME:lower() then home = w end end
    self.homeBtn:setEnable(home ~= nil)
    self.homeBtn:setTitle(home and ("Go Home (" .. home.name .. ")") or "Go Home (save a place called Base)")
    self.backBtn:setEnable(d.back ~= nil)
    self.goBtn:setEnable(wp ~= nil)
    self.goBtn:setTitle(wp and ("Go to " .. wp.name) or "Go to place")
    local isHome = wp and wp.name:lower() == CFG.HOME_NAME:lower()
    self.delBtn:setEnable(wp ~= nil and not isHome)
    if self.delConfirm and wp and self.delConfirm == wp.name then
        self.delBtn:setTitle("Really delete " .. wp.name .. "?")
    else
        self.delBtn:setTitle(isHome and "Base: save over it to move it" or "Delete")
    end
end

-- picking a row fills the form with that place: change a number and Save coordinates to edit it
function UI:onPick(row)
    local wp = row and row.wp
    if not wp then return end
    self.xEntry:setText(tostring(math.floor(wp.x)))
    self.yEntry:setText(tostring(math.floor(wp.y)))
    self.zEntry:setText((wp.z and wp.z ~= 0) and tostring(math.floor(wp.z)) or "")
    self.nameEntry:setText(wp.name)
    self.delConfirm = nil
    self:updateButtons()
end

-- ---------- actions ----------

-- the truck goes only when it qualifies and the tick box is on
function UI:wantTruck()
    return (self.truck ~= nil) and (self.takeTruck == true)
end

local function done(self, ok)
    if ok then self:close() else self:refresh() end
end

function UI:onHome()
    local p = player0(); if not p then return end
    local _, home = nil, nil
    for _, w in ipairs(W.store().list) do if w.name:lower() == CFG.HOME_NAME:lower() then home = w end end
    if not home then return end
    if math.sqrt((p:getX() - home.x) ^ 2 + (p:getY() - home.y) ^ 2) <= CFG.HOME_RADIUS then
        W.say(p, "You are already home", nil)
        return
    end
    done(self, W.travel(p, home, self:wantTruck()))
end

function UI:onBack()
    local p = player0(); if not p then return end
    done(self, W.back(p, self:wantTruck()))
end

function UI:onGoPlace()
    local p = player0(); if not p then return end
    local wp = self:picked()
    if not wp then return end
    done(self, W.travel(p, wp, self:wantTruck()))
end

function UI:onDelete()
    local wp = self:picked()
    if not wp or wp.name:lower() == CFG.HOME_NAME:lower() then return end
    if self.delConfirm ~= wp.name then
        self.delConfirm = wp.name
        self:updateButtons()
        return
    end
    local p = player0()
    W.delete(p, wp.name)
    self.list.selected = 0
    self:refresh()
end

-- X / Y / Z from the form. Returns x, y, z or nil, why
function UI:readCoords()
    local x, y = tonumber(self.xEntry:getText()), tonumber(self.yEntry:getText())
    if not x or not y then return nil, "Type the X and Y coordinates first" end
    local z = tonumber(self.zEntry:getText()) or 0
    local valid = true
    pcall(function() valid = getWorld():getMetaGrid():isValidChunk(math.floor(x / 10), math.floor(y / 10)) end)
    if not valid then return nil, "That spot is outside the map" end
    return x, y, z
end

function UI:onGoCoords()
    local p = player0(); if not p then return end
    local x, y, z = self:readCoords()
    if not x then W.say(p, y, "bad"); return end
    local nm = self.nameEntry:getText()
    done(self, W.travel(p, { name = (nm and nm ~= "") and nm or string.format("%d, %d", x, y), x = x, y = y, z = z, hasV = false },
        self:wantTruck()))
end

function UI:onSaveCoords()
    local p = player0(); if not p then return end
    local x, y, z = self:readCoords()
    if not x then W.say(p, y, "bad"); return end
    if W.saveXYZ(p, self.nameEntry:getText(), x, y, z) then self:refresh() end
end

function UI:onSaveHere()
    local p = player0(); if not p then return end
    if W.saveHere(p, self.nameEntry:getText()) then self:refresh() end
end

function UI:close()
    self:setVisible(false)
    self:removeFromUIManager()
    if UI.instance == self then UI.instance = nil end
end

function UI:new(x, y, playerNum)
    local o = ISCollapsableWindow.new(self, x, y, WIN_W, 600)
    o.playerNum = playerNum or 0
    o.title = "Empire Travel"
    o:setResizable(false)
    o.takeTruck = true
    return o
end

-- ---------- opening ----------

function W.openUI(player)
    if UI.instance then pcall(function() UI.instance:close() end) end
    local pn = 0
    pcall(function() pn = player and player:getPlayerNum() or 0 end)
    local ok, err = pcall(function()
        local win = UI:new(0, 0, pn)
        win:initialise()
        win:addToUIManager()
        -- centred on the player's screen, after createChildren worked out the height
        local x, y = 100, 60
        pcall(function()
            x = getPlayerScreenLeft(pn) + (getPlayerScreenWidth(pn) - win.width) / 2
            y = getPlayerScreenTop(pn) + math.max(10, (getPlayerScreenHeight(pn) - win.height) / 2)
        end)
        win:setX(x); win:setY(y)
        win:bringToTop()
        UI.instance = win
    end)
    if not ok then
        print(TAG .. "could not open the window: " .. tostring(err))
        return false
    end
    return true
end

function W.toggleUI(player)
    if UI.instance and UI.instance:isVisible() then
        UI.instance:close()
        return false
    end
    return W.openUI(player)
end

print("[EmpireQoL] Travel menu loaded: Numpad 1 = Travel window, Shift+Numpad 1 = home / back")
