-- ============================================================
-- Empire Find Item  v2
-- F11  (or right-click inventory -> "Find item in base...") -> type a name, press Enter.
-- Scans EVERY storage within RADIUS tiles, all floors, HIGHLIGHTS each
-- container holding a match green, and reports count + distance/direction.
-- Highlights auto-clear after a while, or on the next search.
-- READ-ONLY locator: it never moves or touches a single item.
-- ============================================================

local RADIUS       = 14       -- a touch wider than Smart Sort's 12
local HIGHLIGHT_MS = 30000    -- auto-clear the glow after 30s
local FIND_KEY     = Keyboard.KEY_NUMPAD2   -- numpad 2 = find item in base (NumLock ON)

local litObjects = {}         -- objects we've lit up
local clearAt    = nil        -- timestamp to auto-clear at
local activeMatch = nil       -- function(item)->bool while a find is live; tints matching rows in any open container

-- D: clear the green row-tint inside any open loot/inventory window
local function clearPaneHighlights()
    local pages = {}
    pcall(function() pages[#pages+1] = getPlayerLoot(0) end)
    pcall(function() pages[#pages+1] = getPlayerInventory(0) end)
    for _, page in ipairs(pages) do
        if page and page.inventoryPane then
            pcall(function() page.inventoryPane:setItemsToHighlight(page, nil) end)
        end
    end
end

local function clearHighlights()
    for _, o in ipairs(litObjects) do
        pcall(function() o:setHighlighted(false) end)
    end
    litObjects = {}
    clearAt = nil
    activeMatch = nil
    pcall(clearPaneHighlights)
end

-- D: when a container is open during a live find, tint the rows that match.
-- Uses vanilla ISInventoryPane:setItemsToHighlight (auto-clears when the window closes).
local function applyHighlight(page)
    if not activeMatch or not page or not page.inventoryPane then return end
    local pane = page.inventoryPane
    local inv = pane.inventory
    if not inv then return end
    local items = nil
    pcall(function() items = inv:getItems() end)
    if not items then return end
    local map, any = {}, false
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        local ok = false
        pcall(function() ok = activeMatch(it) end)
        if ok then map[it] = true; any = true end
    end
    if any then
        pcall(function() pane:setItemsToHighlight(page, map) end)
    else
        pcall(function() pane:setItemsToHighlight(page, nil) end)
    end
end

-- re-tint whatever's open right now (called at the end of a find)
local function applyHighlightToOpen()
    pcall(function() applyHighlight(getPlayerLoot(0)) end)
    pcall(function() applyHighlight(getPlayerInventory(0)) end)
end

-- 8-way compass from player to a square (PZ: +x = east, +y = south)
local function compass(dx, dy)
    local ns = ""
    if dy <= -3 then ns = "N" elseif dy >= 3 then ns = "S" end
    local ew = ""
    if dx >= 3 then ew = "E" elseif dx <= -3 then ew = "W" end
    local c = ns .. ew
    if c == "" then return "right next to you" end
    return c
end

-- collect every container within RADIUS on every floor (mirrors Smart Sort's scan)
local function nearbyContainers(player)
    local out = {}
    local sq = player:getCurrentSquare()
    if not sq then return out, 0, 0 end
    local cell = getCell()
    local px, py = sq:getX(), sq:getY()
    local seen = {}
    for z = 0, 7 do
        for x = px - RADIUS, px + RADIUS do
            for y = py - RADIUS, py + RADIUS do
                local s = cell:getGridSquare(x, y, z)
                if s then
                    local objs = s:getObjects()
                    for i = 0, objs:size() - 1 do
                        local obj = objs:get(i)
                        local c = nil
                        pcall(function() c = obj:getContainer() end)
                        if c and not seen[c] then
                            seen[c] = true
                            local holder = obj
                            pcall(function() local pa = c:getParent(); if pa then holder = pa end end)
                            out[#out + 1] = { c = c, obj = holder, x = x, y = y }
                        end
                    end
                end
            end
        end
    end
    return out, px, py
end

-- match query against the item's display name AND its script type (so "lighter"
-- hits both the readable name and the raw "Lighter" type, modded items included)
local function itemMatches(it, q)
    local hit = false
    pcall(function()
        local n = (it:getName() or ""):lower()
        if n:find(q, 1, true) then hit = true; return end
        local t = (it:getType() or ""):lower()
        if t:find(q, 1, true) then hit = true end
    end)
    return hit
end

local function doFind(player, query)
    if not player then player = getSpecificPlayer(0) end
    if not player or not query then return end
    query = tostring(query):gsub("^%s+", ""):gsub("%s+$", ""):lower()
    if query == "" then clearHighlights(); return end

    clearHighlights()
    activeMatch = function(it) return itemMatches(it, query) end

    local stores, px, py = nearbyContainers(player)
    local hc = nil
    pcall(function() hc = getCore():getGoodHighlitedColor() end)

    local spots, total = {}, 0
    for _, st in ipairs(stores) do
        local n, items = 0, nil
        pcall(function() items = st.c:getItems() end)
        if items then
            for i = 0, items:size() - 1 do
                if itemMatches(items:get(i), query) then n = n + 1 end
            end
        end
        if n > 0 then
            total = total + n
            pcall(function()
                if hc then st.obj:setHighlightColor(hc) end
                st.obj:setHighlighted(true, false)
            end)
            litObjects[#litObjects + 1] = st.obj
            local dx, dy = st.x - px, st.y - py
            local dist = math.floor(math.sqrt(dx * dx + dy * dy) + 0.5)
            local ct = ""; pcall(function() ct = st.c:getType() or "" end)
            spots[#spots + 1] = { n = n, dist = dist, dir = compass(dx, dy), ct = ct }
        end
    end

    if total == 0 then
        HaloTextHelper.addTextWithArrow(player, "No '" .. query .. "' in storage within " .. RADIUS .. " tiles", "[br/]", false, HaloTextHelper.getColorRed())
        player:Say("No " .. query .. " stored nearby.")
        return
    end

    HaloTextHelper.addTextWithArrow(player, "FOUND " .. total .. " '" .. query .. "' in " .. #spots .. " spot(s) - lit green", "[br/]", false, HaloTextHelper.getColorGreen())
    table.sort(spots, function(a, b) return a.dist < b.dist end)
    print("[EmpireFind] query='" .. query .. "' total=" .. total .. " spots=" .. #spots)
    for _, s in ipairs(spots) do
        print(string.format("[EmpireFind]   %dx in %s - %d tiles %s", s.n, (s.ct ~= "" and s.ct or "container"), s.dist, s.dir))
    end
    local nr = spots[1]
    player:Say(string.format("Found %d. Nearest: %d in a %s, %d tiles %s.", total, nr.n, (nr.ct ~= "" and nr.ct or "container"), nr.dist, nr.dir))

    clearAt = getTimestampMs() + HIGHLIGHT_MS
    pcall(applyHighlightToOpen)
end

-- ---- find a gun's magazine / ammo by the gun's OWN type (read-only locator) ----
-- Reuses the same scan + green highlight as Find Item, but matches the exact mag
-- (or ammo) the right-clicked gun uses -- so you never read or memorise the type.
local function locateTypes(player, wantTypes, label)
    if not player then return end
    clearHighlights()
    activeMatch = function(it)
        local ft, tp = "", ""
        pcall(function() ft = (it:getFullType() or ""):lower() end)
        pcall(function() tp = (it:getType() or ""):lower() end)
        return (wantTypes[ft] or wantTypes[tp]) == true
    end
    local stores, px, py = nearbyContainers(player)
    local hc = nil
    pcall(function() hc = getCore():getGoodHighlitedColor() end)
    local spots, total = {}, 0
    for _, st in ipairs(stores) do
        local n, items = 0, nil
        pcall(function() items = st.c:getItems() end)
        if items then
            for i = 0, items:size() - 1 do
                local it = items:get(i)
                local ft, tp = "", ""
                pcall(function() ft = (it:getFullType() or ""):lower() end)
                pcall(function() tp = (it:getType() or ""):lower() end)
                if wantTypes[ft] or wantTypes[tp] then n = n + 1 end
            end
        end
        if n > 0 then
            total = total + n
            pcall(function()
                if hc then st.obj:setHighlightColor(hc) end
                st.obj:setHighlighted(true, false)
            end)
            litObjects[#litObjects + 1] = st.obj
            local dx, dy = st.x - px, st.y - py
            local dist = math.floor(math.sqrt(dx * dx + dy * dy) + 0.5)
            local ct = ""; pcall(function() ct = st.c:getType() or "" end)
            spots[#spots + 1] = { n = n, dist = dist, dir = compass(dx, dy), ct = ct }
        end
    end
    if total == 0 then
        HaloTextHelper.addTextWithArrow(player, "No " .. label .. " in storage within " .. RADIUS .. " tiles", "[br/]", false, HaloTextHelper.getColorRed())
        player:Say("No " .. label .. " stored nearby.")
        return
    end
    HaloTextHelper.addTextWithArrow(player, "FOUND " .. total .. " " .. label .. " in " .. #spots .. " spot(s) - lit green", "[br/]", false, HaloTextHelper.getColorGreen())
    table.sort(spots, function(a, b) return a.dist < b.dist end)
    local nr = spots[1]
    player:Say(string.format("Found %d %s. Nearest: %d in a %s, %d tiles %s.", total, label, nr.n, (nr.ct ~= "" and nr.ct or "container"), nr.dist, nr.dir))
    clearAt = getTimestampMs() + HIGHLIGHT_MS
    pcall(applyHighlightToOpen)
end

local function addTypeForms(set, raw)
    if not raw or raw == "" then return end
    local s = tostring(raw):lower()
    set[s] = true
    local dot = s:find("%.")
    if dot then set[s:sub(dot + 1)] = true else set["base." .. s] = true end
end

-- readable display name from a type string (mag type, or ammo item key)
local function readableFromType(t)
    if not t then return nil end
    local s = tostring(t)
    if s == "" then return nil end
    local forms = { s }
    if not s:find("%.") then forms[#forms + 1] = "Base." .. s end
    for _, f in ipairs(forms) do
        local nm = nil
        pcall(function() nm = getItemNameFromFullType(f) end)
        if nm and nm ~= "" and nm ~= f then return nm end
    end
    return (s:gsub("^.*%.", ""))   -- fallback: strip module prefix
end

-- what a gun feeds on -> { want=typeset, name=readable, kind="magazine"/"ammo" }
-- mag-fed: getMagazineType() is a type string. ammo-fed: getAmmoType() is an
-- object, so pull its item key (the string the inventory APIs actually use).
local function resolveGunAmmo(gun)
    if not gun then return nil end
    local magType = nil
    pcall(function() magType = gun:getMagazineType() end)
    if magType and tostring(magType) ~= "" then
        local want = {}; addTypeForms(want, magType)
        return { want = want, name = readableFromType(magType), kind = "magazine" }
    end
    local ammoKey = nil
    pcall(function() ammoKey = gun:getAmmoType():getItemKey() end)
    if ammoKey and tostring(ammoKey) ~= "" then
        local want = {}; addTypeForms(want, ammoKey)
        return { want = want, name = readableFromType(ammoKey), kind = "ammo" }
    end
    return nil
end

-- count matching mags/ammo in nearby storage. Cached by type-signature with a
-- short TTL so repeat right-clicks near the hoard don't re-run the grid scan.
local MAG_COUNT_TTL = 6000
local magCountCache = {}

local function wantSig(want)
    local keys = {}
    for k in pairs(want) do keys[#keys + 1] = k end
    table.sort(keys)
    return table.concat(keys, "|")
end

local function countNearby(player, want)
    local stores = nearbyContainers(player)
    local total = 0
    for _, st in ipairs(stores) do
        local items = nil
        pcall(function() items = st.c:getItems() end)
        if items then
            for i = 0, items:size() - 1 do
                local it = items:get(i)
                local ft, tp = "", ""
                pcall(function() ft = (it:getFullType() or ""):lower() end)
                pcall(function() tp = (it:getType() or ""):lower() end)
                if want[ft] or want[tp] then total = total + 1 end
            end
        end
    end
    return total
end

local function countNearbyCached(player, want)
    local sig = wantSig(want)
    local now = getTimestampMs()
    local c = magCountCache[sig]
    if c and (now - c.at) < MAG_COUNT_TTL then return c.count end
    local n = countNearby(player, want)
    magCountCache[sig] = { count = n, at = now }
    return n
end

local function findGunMag(player, gun, res)
    if not player or not gun then return end
    res = res or resolveGunAmmo(gun)
    if res and res.want then
        local label = (res.kind == "magazine") and "magazines for this gun" or "ammo for this gun"
        locateTypes(player, res.want, label)
    else
        HaloTextHelper.addTextWithArrow(player, "This gun takes no detachable mag/ammo", "[br/]", false, HaloTextHelper.getColorWhite())
    end
end

-- ---- text-input prompt ----
local function onPromptClick(target, button)
    if button.internal ~= "OK" then return end
    local txt = ""
    pcall(function() txt = button.parent.entry:getText() end)
    pcall(function() doFind(getSpecificPlayer(0), txt) end)
end

local function openPrompt()
    local player = getSpecificPlayer(0)
    if not player or player:isDead() then return end
    local modal = ISTextBox:new(0, 0, 340, 120, "Find item in base (name or part of it):", "", nil, onPromptClick, 0)
    modal:initialise()
    -- Enter submits, exactly like clicking OK. ISTextEntryBox:onCommandEntered is the
    -- engine's Return hook -- empty by default, which is why you had to click OK. We route
    -- it through the normal OK button (modal.yes, internal="OK") so it also closes the box.
    pcall(function()
        modal.entry.onCommandEntered = function()
            pcall(function() modal:onClick(modal.yes) end)
        end
    end)
    modal:addToUIManager()
    pcall(function() modal:setAlwaysOnTop(true) end)
end

-- ---- triggers ----
local function onKeyPressed(key)
    if key == FIND_KEY then pcall(openPrompt) end
end
Events.OnKeyPressed.Add(onKeyPressed)

local function onFillInv(player, context, items)
    local playerObj = player
    if type(player) == "number" then playerObj = getSpecificPlayer(player) end
    if not playerObj then return end
    context:addOption("Find item in base...", playerObj, function() pcall(openPrompt) end)
    -- if a gun is right-clicked, offer "Find its magazine" (highlights storage holding it)
    local actual = nil
    pcall(function() actual = ISInventoryPane.getActualItems(items) end)
    if actual then
        for _, it in ipairs(actual) do
            local isGun = false
            pcall(function() isGun = instanceof(it, "HandWeapon") and it:isRanged() end)
            if isGun then
                local res = resolveGunAmmo(it)
                local label = "Find its magazine"
                if res then
                    local cnt = countNearbyCached(playerObj, res.want)
                    local verb = (res.kind == "magazine") and "Find its magazine" or "Find its ammo"
                    local nm = res.name or ((res.kind == "magazine") and "magazine" or "ammo")
                    label = string.format("%s (%s \194\183 %d nearby)", verb, nm, cnt)
                end
                local capturedRes = res
                context:addOption(label, playerObj, function() pcall(function() findGunMag(playerObj, it, capturedRes) end) end)
                break
            end
        end
    end
    if #litObjects > 0 then
        context:addOption("Clear find highlights", playerObj, function() pcall(clearHighlights) end)
    end
end
Events.OnFillInventoryObjectContextMenu.Add(onFillInv)

local function onTick()
    if clearAt and getTimestampMs() >= clearAt then pcall(clearHighlights) end
end
Events.OnTick.Add(onTick)

-- D: every time a loot/inventory window finishes refreshing (open a container,
-- switch tab, proximity remerge), re-tint the rows matching the live find.
local function onWindowRefresh(page, state)
    if state ~= "end" then return end
    if not activeMatch then return end
    pcall(function() applyHighlight(page) end)
end
Events.OnRefreshInventoryWindowContainers.Add(onWindowRefresh)

print("[EmpireFind] v2 loaded. F11 or right-click inventory -> 'Find item in base...' (Enter submits). Lights up nearby storage holding the item; auto-clears in " .. (HIGHLIGHT_MS / 1000) .. "s.")
