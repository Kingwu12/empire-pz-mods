-- Empire QoL - Roof Plumbing
-- Vanilla only lets you plumb a sink when a rain collector sits on the EXACT tile directly
-- above it. This widens that: a sink can be plumbed if there's a rain collector anywhere
-- ABOVE it within the same building (up on the roof / an upper floor). Water still comes
-- from above through the building, so it stays believable -- you just don't have to stack a
-- barrel on the precise tile over every tap.
--
-- The actual connect reuses the vanilla plumb action (ISPlumbItem) untouched, so a plumbed
-- sink behaves exactly like vanilla. We only widen WHEN the option is offered.

local SCAN_FLOORS_UP = 4   -- floors above the sink to search for a collector

-- Is this world object a sink/tap that vanilla considers pipeable, and not already plumbed?
local function isPlumbableSink(obj)
    if not obj then return false end
    local piped = false
    pcall(function()
        local props = obj:getProperties()
        if props and props:has(IsoFlagType.waterPiped) then piped = true end
    end)
    if not piped then
        local md = obj:getModData()
        if md and md.canBeWaterPiped == true then piped = true end
    end
    if not piped then return false end
    local already = false
    pcall(function() if obj:getUsesExternalWaterSource() then already = true end end)
    return not already
end

-- Footprint of the sink's building (falls back to a tight box if it isn't a mapped building).
local function buildingBox(sq)
    local r = 10
    local x0, y0, x1, y1 = sq:getX()-r, sq:getY()-r, sq:getX()+r, sq:getY()+r
    pcall(function()
        local bld = sq:getBuilding()
        local def = bld and bld:getDef()
        if def then
            local bx, by, bw, bh = def:getX(), def:getY(), def:getW(), def:getH()
            if bx and by and bw and bh then
                x0, y0, x1, y1 = bx, by, bx + bw - 1, by + bh - 1
            end
        end
    end)
    return x0, y0, x1, y1
end

-- A rain collector barrel stores waterMax in its modData (see SRainBarrelSystem object keys).
local function isRainCollector(o)
    local md = o:getModData()
    return md and md.waterMax ~= nil
end

-- Any rain collector on a floor above this sink, inside the building footprint?
local function hasRoofCollector(sink)
    local sq = sink:getSquare(); if not sq then return false end
    local cell = getCell(); if not cell then return false end
    local x0, y0, x1, y1 = buildingBox(sq)
    local z0 = sq:getZ() + 1
    for z = z0, z0 + SCAN_FLOORS_UP - 1 do
        for x = x0, x1 do
            for y = y0, y1 do
                local s = cell:getGridSquare(x, y, z)
                if s then
                    local objs = s:getObjects()
                    for i = 0, objs:size() - 1 do
                        if isRainCollector(objs:get(i)) then return true end
                    end
                end
            end
        end
    end
    return false
end

local function hasPipeWrench(playerObj)
    local inv = playerObj:getInventory()
    if inv:containsTypeRecurse("PipeWrench") then return true end
    local ok, r = pcall(function() return inv:containsTagRecurse("PipeWrench") end)
    return ok and r or false
end

local function onFill(player, context, worldobjects, test)
    local playerObj = getSpecificPlayer(player)
    if not playerObj then return end
    -- find a plumbable sink among the clicked objects
    local sink = nil
    for _, o in ipairs(worldobjects) do
        if isPlumbableSink(o) then sink = o; break end
    end
    if not sink then return end
    if not hasPipeWrench(playerObj) then return end
    if not hasRoofCollector(sink) then return end
    -- reuse the vanilla plumb handler: onPlumbItem(worldobjects, player, itemToPipe)
    context:addOption("Empire: Plumb to roof tank", worldobjects,
        ISWorldObjectContextMenu.onPlumbItem, player, sink)
end

Events.OnFillWorldObjectContextMenu.Add(onFill)

print("[EmpireQoL] Roof Plumbing loaded: plumb a sink from a collector anywhere above it in the building.")
