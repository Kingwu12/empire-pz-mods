-- ============================================================
-- Empire Zones : painting (client) - layer 1
-- Right-click a tile -> Empire Zones: start a zone, add the exact tile (irregular
-- shapes), add a 5x5 block (bulk), remove, show/hide highlight, delete.
-- Tiles use the clicked square's REAL z, so rooftops and basements paint correctly
-- (no ground-floor miscalc). Drag-paint cursor is layer 2.
-- ============================================================

local EZ = EmpireZones

local function pObj(player) if type(player) == "number" then return getSpecificPlayer(player) end return player end
local function pNum(player) if type(player) == "number" then return player end return 0 end

local function halo(playerObj, text)
    pcall(function() HaloTextHelper.addTextWithArrow(playerObj, text, "[br/]", false, HaloTextHelper.getColorGreen()) end)
end

-- the exact right-clicked square (correct z); fall back to the tile under the player
local function clickedSquare(worldobjects, player)
    for _, o in ipairs(worldobjects) do
        local sq = nil
        pcall(function() sq = o.getSquare and o:getSquare() or nil end)
        if sq then return sq end
    end
    local pl = pObj(player)
    return pl and pl:getCurrentSquare() or nil
end

-- on-demand highlight of a zone's currently-loaded tiles (not per-frame)
local shown = {}
local function clearShown(playerNum)
    for _, fl in ipairs(shown) do pcall(function() fl:setHighlighted(playerNum, false, false) end) end
    shown = {}
end
local function showZone(playerNum, zone)
    clearShown(playerNum)
    local cell = getCell()
    EZ.forEachTile(zone, function(x, y, z)
        local sq = cell and cell:getGridSquare(x, y, z)
        local fl = sq and sq:getFloor()
        if fl then
            pcall(function() fl:setHighlighted(playerNum, true, false) end)
            shown[#shown + 1] = fl
        end
    end)
end

-- two-corner BASE definition (reliable rectangle; same result as SSC drag-select)
local basePending = nil
local subPending = nil      -- two-corner CUTOUT (subtract rectangle from base)
local function ensureBaseZone()
    for _, z in pairs(EZ.all()) do if z.type == "base" then return z end end
    return EZ.get(EZ.newZone("Base", "base"))
end

-- AUTO-DETECT: flood fill outward from the clicked tile across THIS floor. Walls and
-- fences stop the fill (isBlockedTo); doors and windows are passed so interior rooms
-- join the yard. A perimeter gate standing OPEN leaks the fill into the world -- the
-- tile cap catches that and we retry in STRICT mode (doors block too) and say so.
-- Trees can block isBlockedTo and leave holes behind them: patch holes with the
-- existing Add-tile / Add-5x5 smoothing tools afterwards.
local MAX_FILL = 6000
local function floodDetect(startSq, passDoors)
    local cell = getCell()
    local z = startSq:getZ()
    local visited = {}
    local order = {}
    local queue = { { startSq:getX(), startSq:getY() } }
    visited[EZ.key(startSq:getX(), startSq:getY(), z)] = true
    while #queue > 0 do
        local cur = table.remove(queue)
        order[#order + 1] = cur
        if #order > MAX_FILL then return nil, #order end
        local csq = cell:getGridSquare(cur[1], cur[2], z)
        if csq then
            for _, d in ipairs({ {1,0}, {-1,0}, {0,1}, {0,-1} }) do
                local nx, ny = cur[1] + d[1], cur[2] + d[2]
                local k = EZ.key(nx, ny, z)
                if not visited[k] then
                    local nsq = cell:getGridSquare(nx, ny, z)
                    if nsq then
                        local blocked = false
                        pcall(function() blocked = csq:isBlockedTo(nsq) end)
                        if blocked and passDoors then
                            local dw = false
                            pcall(function() dw = csq:isDoorTo(nsq) or csq:isWindowTo(nsq) end)
                            if dw then blocked = false end
                        end
                        if not blocked then
                            visited[k] = true
                            queue[#queue + 1] = { nx, ny }
                        end
                    end
                end
            end
        end
    end
    return order, #order
end

local function onFill(player, context, worldobjects)
    local pl = pObj(player); if not pl then return end
    local sq = clickedSquare(worldobjects, player); if not sq then return end
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    local playerNum = pNum(player)

    local opt = context:addOption("Empire Zones", nil, nil)
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(opt, sub)

    -- BASE: pick two corners -> rectangle base, highlighted, and KS follows it
    if not basePending then
        sub:addOption("Define base: corner 1 here", pl, function()
            basePending = { x = x, y = y, z = z }
            halo(pl, "Base corner 1 set - right-click the opposite corner.")
        end)
    else
        sub:addOption("Define base: FINISH rectangle here", pl, function()
            local c = basePending; basePending = nil
            local zone = ensureBaseZone()
            local ax1, ax2 = math.min(c.x, x), math.max(c.x, x)
            local ay1, ay2 = math.min(c.y, y), math.max(c.y, y)
            for ax = ax1, ax2 do for ay = ay1, ay2 do EZ.addTile(zone.id, ax, ay, z) end end
            showZone(playerNum, zone)
            halo(pl, "Base set: " .. (ax2 - ax1 + 1) .. "x" .. (ay2 - ay1 + 1) .. " (this floor)")
            pcall(function() if EmpireBases and EmpireBases.syncKSToOurBase then EmpireBases.syncKSToOurBase(pl) end end)
        end)
        sub:addOption("Define base: cancel", pl, function() basePending = nil; halo(pl, "Cancelled.") end)
    end

    -- BASE: AUTO-DETECT the walled area around the clicked tile in one click.
    -- Fill this floor, paint every reached tile into the base zone, highlight it.
    -- Run it again on other floors (and in the basement) to add them the same way.
    sub:addOption("AUTO-DETECT base here (walled area, this floor)", pl, function()
        local tiles, n = floodDetect(sq, true)
        local mode = "doors passed"
        if not tiles then
            tiles, n = floodDetect(sq, false)
            mode = "strict -- fill leaked through an open gate/door, so doors blocked this run"
        end
        if not tiles then
            halo(pl, "Area not enclosed (fill escaped even with doors blocked). Close the perimeter and retry, or use corners/rooms.")
            return
        end
        local zone = ensureBaseZone()
        for _, t in ipairs(tiles) do EZ.addTile(zone.id, t[1], t[2], z) end
        showZone(playerNum, zone)
        halo(pl, "Auto-detected " .. #tiles .. " tiles (" .. mode .. "). Total: " .. EZ.tileCount(zone) .. ". Smooth with Add tile / 5x5 / Cutout; repeat on other floors + basement.")
        pcall(function() if EmpireBases and EmpireBases.syncKSToOurBase then EmpireBases.syncKSToOurBase(pl) end end)
    end)

    -- BASE: add a whole ROOM in one click (exact irregular footprint, this floor).
    -- Uses PZ room detection: walk the room's def bounding box, keep only squares whose
    -- room IS this room. Unions into the single base zone (non-destructive).
    local room = nil; pcall(function() room = sq.getRoom and sq:getRoom() or nil end)
    local roomDef = nil; if room then pcall(function() roomDef = room:getRoomDef() end) end
    if roomDef then
        sub:addOption("Add this whole ROOM to base", pl, function()
            local zone = ensureBaseZone()
            local cell = getCell()
            local rx1, ry1, rx2, ry2 = roomDef:getX(), roomDef:getY(), roomDef:getX2(), roomDef:getY2()
            local n = 0
            for ax = rx1, rx2 do for ay = ry1, ry2 do
                local s2 = cell and cell:getGridSquare(ax, ay, z)
                local r2 = nil; if s2 then pcall(function() r2 = s2.getRoom and s2:getRoom() or nil end) end
                if r2 and r2 == room then EZ.addTile(zone.id, ax, ay, z); n = n + 1 end
            end end
            showZone(playerNum, zone)
            halo(pl, "Added room: " .. n .. " tiles (" .. EZ.tileCount(zone) .. " total)")
            pcall(function() if EmpireBases and EmpireBases.syncKSToOurBase then EmpireBases.syncKSToOurBase(pl) end end)
        end)
    end

    -- BASE: add the whole BUILDING (this floor) in one click. Union the bounding boxes
    -- of every room def, then keep only squares that belong to THIS building's ID -- so
    -- the exact multi-room footprint on this floor is added, no neighbours bleed in.
    -- (Multi-floor: repeat this on each floor, same as the rectangle flow.)
    local building = nil; pcall(function() building = sq.getBuilding and sq:getBuilding() or nil end)
    if building then
        sub:addOption("Add this whole BUILDING to base (this floor)", pl, function()
            local zone = ensureBaseZone()
            local cell = getCell()
            local bid = nil; pcall(function() bid = building:getID() end)
            local bdef = nil; pcall(function() bdef = building.getDef and building:getDef() or nil end)
            local x1, y1, x2, y2
            if bdef and bdef.getRooms then
                local rooms = bdef:getRooms()
                for i = 0, rooms:size() - 1 do
                    local rd = rooms:get(i)
                    local a1, b1, a2, b2 = rd:getX(), rd:getY(), rd:getX2(), rd:getY2()
                    x1 = x1 and math.min(x1, a1) or a1
                    y1 = y1 and math.min(y1, b1) or b1
                    x2 = x2 and math.max(x2, a2) or a2
                    y2 = y2 and math.max(y2, b2) or b2
                end
            end
            local n = 0
            if x1 and bid then
                for ax = x1, x2 do for ay = y1, y2 do
                    local s2 = cell and cell:getGridSquare(ax, ay, z)
                    local b2 = nil; if s2 then pcall(function() b2 = s2.getBuilding and s2:getBuilding() or nil end) end
                    local id2 = nil; if b2 then pcall(function() id2 = b2:getID() end) end
                    if id2 and id2 == bid then EZ.addTile(zone.id, ax, ay, z); n = n + 1 end
                end end
            end
            showZone(playerNum, zone)
            halo(pl, "Added building floor: " .. n .. " tiles (" .. EZ.tileCount(zone) .. " total)")
            pcall(function() if EmpireBases and EmpireBases.syncKSToOurBase then EmpireBases.syncKSToOurBase(pl) end end)
        end)
    end

    -- BASE: subtract a rectangle (carve a cutout, e.g. exclude a courtyard interior).
    if not subPending then
        sub:addOption("Base cutout: corner 1 here", pl, function()
            subPending = { x = x, y = y, z = z }
            halo(pl, "Cutout corner 1 set - right-click the opposite corner.")
        end)
    else
        sub:addOption("Base cutout: FINISH rectangle here", pl, function()
            local c = subPending; subPending = nil
            local zone = ensureBaseZone()
            local ax1, ax2 = math.min(c.x, x), math.max(c.x, x)
            local ay1, ay2 = math.min(c.y, y), math.max(c.y, y)
            for ax = ax1, ax2 do for ay = ay1, ay2 do EZ.removeTile(zone.id, ax, ay, z) end end
            showZone(playerNum, zone)
            halo(pl, "Cutout removed: " .. (ax2 - ax1 + 1) .. "x" .. (ay2 - ay1 + 1) .. " (" .. EZ.tileCount(zone) .. " left)")
            pcall(function() if EmpireBases and EmpireBases.syncKSToOurBase then EmpireBases.syncKSToOurBase(pl) end end)
        end)
        sub:addOption("Base cutout: cancel", pl, function() subPending = nil; halo(pl, "Cancelled.") end)
    end

    local here = EZ.zoneAt(x, y, z)
    if here then
        sub:addOption("Add this tile (" .. here.name .. ")", pl, function()
            EZ.addTile(here.id, x, y, z); showZone(playerNum, here)
            halo(pl, here.name .. ": " .. EZ.tileCount(here) .. " tiles")
        end)
        sub:addOption("Add 5x5 here (" .. here.name .. ")", pl, function()
            EZ.addBlock(here.id, x, y, z, 2); showZone(playerNum, here)
            halo(pl, here.name .. ": " .. EZ.tileCount(here) .. " tiles")
        end)
        sub:addOption("Remove this tile", pl, function()
            EZ.removeTile(here.id, x, y, z); showZone(playerNum, here)
            halo(pl, "Removed (" .. EZ.tileCount(here) .. " left)")
        end)
        sub:addOption("Show " .. here.name, pl, function() showZone(playerNum, here) end)
        sub:addOption("Hide zones", pl, function() clearShown(playerNum) end)
        sub:addOption("Delete " .. here.name, pl, function()
            clearShown(playerNum); EZ.delete(here.id); halo(pl, "Zone deleted")
        end)
    else
        for _, t in ipairs(EZ.TYPES) do
            local ztype = t
            sub:addOption("New " .. ztype .. " zone here", pl, function()
                local id = EZ.newZone(ztype:sub(1,1):upper() .. ztype:sub(2) .. " " .. x .. "_" .. y, ztype)
                EZ.addTile(id, x, y, z); showZone(playerNum, EZ.get(id))
                halo(pl, "Started " .. ztype .. " zone (1 tile)")
            end)
        end
        sub:addOption("Hide zones", pl, function() clearShown(playerNum) end)
    end
end

Events.OnFillWorldObjectContextMenu.Add(onFill)
print("[EmpireZones] layer 1 loaded. Right-click a tile -> Empire Zones.")
