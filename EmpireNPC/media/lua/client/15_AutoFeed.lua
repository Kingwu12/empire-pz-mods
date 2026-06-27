-- Empire NPC - Auto Feed
-- SSC's native auto-eat is brittle: a survivor only eats when idle, with no zombie in sight,
-- inside the base bounds (or VERY hungry), AND already carrying food or able to path to a marked,
-- stocked FoodStorageArea. Miss any one and a hungry survivor just doesn't eat -- which is why it
-- feels random. This makes it reliable: every cycle, any base survivor that's hungry is handed
-- food from base storage and told to eat, skipping SSC's fragile gates (but never mid-combat).
-- Storage lookup goes through EmpireBaseCache, same as the cook/farmer.

require "EmpireNPC_Shared"

local FEED_MS    = 20000     -- check hunger every 20s
local HUNGER_AT  = 0.40      -- feed when hunger >= this (0 = full, 1 = starving)
local lastRun    = 0

-- don't interrupt these with eating
local SKIP_TASKS = {
    ["Attack"] = true, ["Pursue"] = true, ["Threaten"] = true,
    ["First Aide"] = true, ["Eat Food"] = true,
}

-- cache-first base container iterator (fast path: EmpireBaseCache; fallback: base-rect sweep)
local function forEachBaseContainer(char, fn)
    local idx
    pcall(function() if EmpireBaseCache and EmpireBaseCache.get then idx = EmpireBaseCache.get() end end)
    if idx and idx.containers and #idx.containers > 0 then
        for i = 1, #idx.containers do fn(idx.containers[i]) end
        return
    end
    local cell = getCell(); if not cell or not char then return end
    local cz = math.floor(char:getZ())
    local b
    pcall(function()
        if EmpireBases and EmpireBases.activeBase then b = EmpireBases.activeBase(char) end
        if not b and EmpireBases and EmpireBases.list then local l = EmpireBases.list(); b = l and l[1] end
    end)
    local x1, x2, y1, y2, z1, z2
    if b then
        x1, x2 = math.min(b.x1, b.x2), math.max(b.x1, b.x2)
        y1, y2 = math.min(b.y1, b.y2), math.max(b.y1, b.y2)
        local spread = (EmpireBases and EmpireBases.FLOOR_SPREAD) or 0
        z1, z2 = cz - spread, cz + spread
    else
        local cx, cy = math.floor(char:getX()), math.floor(char:getY())
        x1, x2, y1, y2, z1, z2 = cx - 12, cx + 12, cy - 12, cy + 12, cz, cz
    end
    local seen = {}
    for z = z1, z2 do for x = x1, x2 do for y = y1, y2 do
        local sq = cell:getGridSquare(x, y, z)
        if sq then
            local objs = sq:getObjects()
            if objs then for i = 0, objs:size() - 1 do
                local c = nil; pcall(function() c = objs:get(i):getContainer() end)
                if c and not seen[c] then seen[c] = true; fn(c) end
            end end
        end
    end end end
end

-- edible = real food that actually reduces hunger and isn't rotten
local function isEdible(it)
    local ok = false
    pcall(function()
        if not instanceof(it, "Food") then return end
        if it:isRotten() then return end
        if (it:getHungerChange() or 0) >= 0 then return end   -- must actually fill the belly
        ok = true
    end)
    return ok
end

-- pull one edible food item from base storage into the survivor's inventory; returns it or nil
local function pullFood(char)
    local moved
    forEachBaseContainer(char, function(cont)
        if moved then return end
        local items = nil; pcall(function() items = cont:getItems() end)
        if not items then return end
        for i = items:size() - 1, 0, -1 do
            local it = items:get(i)
            if isEdible(it) then
                local okMove = false
                pcall(function() cont:Remove(it); char:getInventory():AddItem(it); okMove = true end)
                if okMove then
                    moved = it
                    pcall(function() if EmpireBaseCache and EmpireBaseCache.invalidate then EmpireBaseCache.invalidate() end end)
                    return
                end
            end
        end
    end)
    return moved
end

local function feedHungry()
    local survs = (EmpireNPC.getActiveSurvivors and EmpireNPC.getActiveSurvivors()) or {}
    for _, ss in ipairs(survs) do
        pcall(function()
            local char = ss:Get()
            if not char or char:isDead() then return end
            if char:getStats():getHunger() < HUNGER_AT then return end           -- not hungry enough
            if ss:getDangerSeenCount and ss:getDangerSeenCount() > 0 then return end  -- threat near: don't stop to eat
            local tm = ss:getTaskManager()
            if tm and SKIP_TASKS[tm:getCurrentTask()] then return end             -- busy / already eating
            if ss.isInAction and ss:isInAction() then return end

            local food
            if ss:hasFood() then food = ss:getFood() else food = pullFood(char) end
            if food and tm then
                tm:AddToTop(EatFoodTask:new(ss, food))
            end
        end)
    end
end

local function onTick()
    local now = getTimestampMs()
    if now - lastRun < FEED_MS then return end
    lastRun = now
    pcall(feedHungry)
end

Events.OnTick.Add(onTick)
print("[EmpireNPC] Auto-feed loaded (reliable hunger feeding from base storage).")
