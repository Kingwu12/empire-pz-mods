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

local function onFill(player, context, worldobjects)
    local pl = pObj(player); if not pl then return end
    local sq = clickedSquare(worldobjects, player); if not sq then return end
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    local playerNum = pNum(player)

    local opt = context:addOption("Empire Zones", nil, nil)
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(opt, sub)

    local here = EZ.zoneAt(x, y, z)
    if here then
        sub:addOption("Add this tile (" .. here.name .. ")", nil, function()
            EZ.addTile(here.id, x, y, z); halo(pl, here.name .. ": " .. EZ.tileCount(here) .. " tiles")
        end)
        sub:addOption("Add 5x5 here (" .. here.name .. ")", nil, function()
            EZ.addBlock(here.id, x, y, z, 2); halo(pl, here.name .. ": " .. EZ.tileCount(here) .. " tiles")
        end)
        sub:addOption("Remove this tile", nil, function()
            EZ.removeTile(here.id, x, y, z); halo(pl, "Removed (" .. EZ.tileCount(here) .. " left)")
        end)
        sub:addOption("Show " .. here.name, nil, function() showZone(playerNum, here) end)
        sub:addOption("Hide zones", nil, function() clearShown(playerNum) end)
        sub:addOption("Delete " .. here.name, nil, function()
            clearShown(playerNum); EZ.delete(here.id); halo(pl, "Zone deleted")
        end)
    else
        for _, t in ipairs(EZ.TYPES) do
            sub:addOption("New " .. t .. " zone here", nil, function()
                local id = EZ.newZone(t:sub(1,1):upper() .. t:sub(2) .. " " .. x .. "_" .. y, t)
                EZ.addTile(id, x, y, z); halo(pl, "Started " .. t .. " zone (1 tile)")
            end)
        end
        sub:addOption("Hide zones", nil, function() clearShown(playerNum) end)
    end
end

Events.OnFillWorldObjectContextMenu.Add(onFill)
print("[EmpireZones] layer 1 loaded. Right-click a tile -> Empire Zones.")
