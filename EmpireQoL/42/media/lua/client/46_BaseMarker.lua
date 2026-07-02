-- EmpireQoL :: 46_BaseMarker.lua -- define the whole base with two right-clicks
-- The base registry stores rectangles, but the only ways to CREATE one were seeds
-- from NPC mods (SuperbSurvivors / KnoxSurvivors) that this save doesn't run -- so
-- no base was ever registered and everything base-gated silently fell back.
-- This is the missing front door: right-click the ground at one corner of your
-- property, "Mark base corner 1"; walk to the OPPOSITE corner (diagonal), right-click,
-- "Mark corner 2 & SAVE". The rectangle between them IS the base -- building, yard,
-- parking, everything -- on every floor (FLOOR_SPREAD/BASEMENT_REACH handle vertical).
-- Saved into the save's ModData: permanent until you redefine it. Redefining replaces
-- "Main" in place, so you can re-mark any time you expand.

local function pendingStore()
    local t
    pcall(function() t = ModData.getOrCreate("EmpireBasePending") end)
    return t or {}
end

local function clickedSquare(worldobjects, playerObj)
    if worldobjects then
        for _, wo in ipairs(worldobjects) do
            local sq = nil
            pcall(function() sq = wo:getSquare() end)
            if sq then return sq end
        end
    end
    return playerObj and playerObj:getCurrentSquare() or nil
end

local function halo(playerObj, msg, good)
    pcall(function()
        local col = good and HaloTextHelper.getColorGreen() or HaloTextHelper.getColorRed()
        HaloTextHelper.addTextWithArrow(playerObj, msg, "[br/]", false, col)
    end)
end

local function saveMain(x1, y1, x2, y2, z)
    -- EmpireBases.list() returns the LIVE ModData-backed table: mutate in place to replace.
    local nx1, nx2 = math.min(x1, x2), math.max(x1, x2)
    local ny1, ny2 = math.min(y1, y2), math.max(y1, y2)
    local lst = EmpireBases.list()
    for _, b in ipairs(lst) do
        if b.name == "Main" then
            b.x1, b.x2, b.y1, b.y2, b.z = nx1, nx2, ny1, ny2, z or 0
            return b
        end
    end
    return EmpireBases.addBase("Main", nx1, nx2, ny1, ny2, z or 0)
end

local function onFillMenu(playerNum, context, worldobjects, test)
    if test then return end
    if not EmpireBases then return end
    local playerObj = getSpecificPlayer(playerNum)
    if not playerObj then return end
    local sq = clickedSquare(worldobjects, playerObj)
    if not sq then return end

    local sub = context:getNew(context)
    local opt = context:addOption("Empire Base", nil, nil)
    context:addSubMenu(opt, sub)

    local pend = pendingStore()
    if pend.x == nil then
        sub:addOption("Mark base corner (1 of 2) here", nil, function()
            local p = pendingStore()
            p.x, p.y, p.z = sq:getX(), sq:getY(), sq:getZ()
            halo(playerObj, "Corner 1 marked. Walk to the OPPOSITE corner and mark corner 2.", true)
        end)
    else
        sub:addOption("Mark corner 2 & SAVE base (diagonal from corner 1)", nil, function()
            local p = pendingStore()
            local b = saveMain(p.x, p.y, sq:getX(), sq:getY(), math.min(p.z or 0, sq:getZ() or 0))
            p.x, p.y, p.z = nil, nil, nil
            local w = math.abs(b.x2 - b.x1) + 1
            local h = math.abs(b.y2 - b.y1) + 1
            pcall(function() if EmpireBaseCache and EmpireBaseCache.invalidate then EmpireBaseCache.invalidate() end end)
            halo(playerObj, "Base 'Main' saved: " .. w .. "x" .. h .. " tiles. Whole compound now pools for sort/craft/build/mechanics.", true)
            print("[EmpireQoL] BaseMarker: Main = (" .. b.x1 .. "," .. b.y1 .. ") -> (" .. b.x2 .. "," .. b.y2 .. ")")
        end)
        sub:addOption("Cancel pending corner", nil, function()
            local p = pendingStore()
            p.x, p.y, p.z = nil, nil, nil
            halo(playerObj, "Pending corner cleared.", true)
        end)
    end

    sub:addOption("Where am I? (base check)", nil, function()
        local b = EmpireBases.activeBase(playerObj)
        if b then
            local w = math.abs(b.x2 - b.x1) + 1
            local h = math.abs(b.y2 - b.y1) + 1
            halo(playerObj, "Inside base '" .. tostring(b.name) .. "' (" .. w .. "x" .. h .. " tiles)", true)
        else
            halo(playerObj, "Not inside any registered base", false)
        end
    end)
end

Events.OnFillWorldObjectContextMenu.Add(onFillMenu)
print("[EmpireQoL] BaseMarker loaded: right-click ground -> Empire Base -> mark two corners")
