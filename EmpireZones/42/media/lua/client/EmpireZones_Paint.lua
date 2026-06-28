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
local function ensureBaseZone()
    for _, z in pairs(EZ.all()) do if z.type == "base" then return z end end
    return EZ.get(EZ.newZone("Base", "base"))
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
