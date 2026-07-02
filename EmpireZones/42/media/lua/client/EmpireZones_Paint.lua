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

    -- MINIMAL MENU (King's directive): the smart define does the heavy lifting;
    -- everything else is patch / trim / verify / reset. The room, building,
    -- two-corner and per-type painters were clutter and are gone -- existing zone
    -- DATA of other types still works, only their paint options were removed.

    -- 1) THE smart define: flood-fill the walled area, stamp every real floor
    sub:addOption("AUTO-DETECT base here (walled area, all floors + basement)", pl, function()
        local tiles, n = floodDetect(sq, true)
        local mode = "doors passed"
        if not tiles then
            tiles, n = floodDetect(sq, false)
            mode = "strict -- fill leaked through an open gate/door, so doors blocked this run"
        end
        if not tiles then
            halo(pl, "Area not enclosed (fill escaped even with doors blocked). Close the perimeter and retry.")
            return
        end
        local zone = ensureBaseZone()
        local down = (EmpireBases and EmpireBases.BASEMENT_REACH) or 6
        local up   = (EmpireBases and EmpireBases.FLOOR_SPREAD) or 2
        local cell2 = getCell()
        local painted = 0
        for _, t in ipairs(tiles) do
            for z2 = z - down, z + up do
                local okz = (z2 == z)
                if not okz then
                    local s2 = cell2:getGridSquare(t[1], t[2], z2)
                    if s2 then
                        local fl = nil
                        pcall(function() fl = s2:getFloor() end)
                        okz = fl ~= nil
                    end
                end
                if okz then EZ.addTile(zone.id, t[1], t[2], z2); painted = painted + 1 end
            end
        end
        showZone(playerNum, zone)
        halo(pl, "Auto-detected " .. #tiles .. " footprint tiles -> " .. painted .. " painted incl. basement (" .. mode .. "). Total: " .. EZ.tileCount(zone) .. ".")
        pcall(function() if EmpireBases and EmpireBases.syncKSToOurBase then EmpireBases.syncKSToOurBase(pl) end end)
    end)

    -- 2) patch a hole the fill missed (tree shadows etc.)
    sub:addOption("Patch: add 5x5 here", pl, function()
        local zone = ensureBaseZone()
        EZ.addBlock(zone.id, x, y, z, 2)
        showZone(playerNum, zone)
        halo(pl, "Patched 5x5 (" .. EZ.tileCount(zone) .. " tiles total)")
    end)

    -- 3) trim: carve a rectangle out of the base
    if not subPending then
        sub:addOption("Trim: cutout corner 1 here", pl, function()
            subPending = { x = x, y = y, z = z }
            halo(pl, "Cutout corner 1 set - right-click the opposite corner.")
        end)
    else
        sub:addOption("Trim: FINISH cutout here", pl, function()
            local c = subPending; subPending = nil
            local zone = ensureBaseZone()
            local ax1, ax2 = math.min(c.x, x), math.max(c.x, x)
            local ay1, ay2 = math.min(c.y, y), math.max(c.y, y)
            for ax = ax1, ax2 do for ay = ay1, ay2 do EZ.removeTile(zone.id, ax, ay, z) end end
            showZone(playerNum, zone)
            halo(pl, "Cutout removed: " .. (ax2 - ax1 + 1) .. "x" .. (ay2 - ay1 + 1) .. " (" .. EZ.tileCount(zone) .. " left)")
            pcall(function() if EmpireBases and EmpireBases.syncKSToOurBase then EmpireBases.syncKSToOurBase(pl) end end)
        end)
        sub:addOption("Trim: cancel", pl, function() subPending = nil; halo(pl, "Cancelled.") end)
    end

    -- 4) verify
    sub:addOption("Show base highlight", pl, function()
        showZone(playerNum, ensureBaseZone())
    end)
    sub:addOption("Hide highlight", pl, function() clearShown(playerNum) end)

    -- 5) reset
    sub:addOption("Delete base zone (start over)", pl, function()
        clearShown(playerNum)
        for id, zz in pairs(EZ.all()) do
            if zz.type == "base" then EZ.delete(zz.id or id) end
        end
        halo(pl, "Base zone deleted -- run AUTO-DETECT to redefine.")
    end)
end

Events.OnFillWorldObjectContextMenu.Add(onFill)
print("[EmpireZones] layer 1 loaded. Right-click a tile -> Empire Zones.")
