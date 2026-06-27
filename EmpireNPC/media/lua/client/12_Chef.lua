-- Empire NPC - Cook role
-- A REAL job done by a REAL survivor. Assign a crew member the Cook role (right-click survivor
-- -> Empire Role -> Cook, or the auto-garrison fills it). While that Cook is alive and at base,
-- once a minute they work the kitchen: cooking raw food across the WHOLE defined base into
-- ready-to-eat meals for the whole community AND you. No Cook assigned = nobody cooks. The
-- meals stay in the same shelves they were in -- now cooked. Halo appears over the Cook.
-- Reads the base via EmpireBaseCache (the maintained index) and only sweeps tiles as a fallback.

require "EmpireNPC_Shared"

local SCAN_R  = 10        -- tiles around the cook (fallback only: when away / no base defined)
local COOK_MS = 60000     -- a kitchen pass every minute
local MAX_PER = 30        -- meals per pass (anti-lag)
local lastRun = 0
local hintedNoCook = false

local function isRawMeal(it)
    local ok = false
    pcall(function()
        if not instanceof(it, "Food") then return end
        if it:isCooked() then return end
        if it:isRotten() then return end
        if it:isFrozen() then return end
        if it:getThirstChange() and it:getThirstChange() < 0 then return end
        if (it:getHungerChange() or 0) >= 0 then return end
        ok = true
    end)
    return ok
end

-- find the crew's Cook (a live survivor with the Cook role), if any
local function findCook()
    local survs = (EmpireNPC.getActiveSurvivors and EmpireNPC.getActiveSurvivors()) or {}
    for _, ss in ipairs(survs) do
        local name = ""; pcall(function() name = ss:getName() or "" end)
        local settler = (name ~= "" and EmpireNPC.getSettler) and EmpireNPC.getSettler(name) or nil
        if settler and settler.role == EmpireNPC.Roles.COOK then
            local ch = nil; pcall(function() ch = ss:Get() end)
            if ch and not ch:isDead() then return ss, ch, name end
        end
    end
    return nil, nil, nil
end

-- iterate every storage container in the WHOLE defined base.
-- Fast path: EmpireBaseCache (the maintained, deduped index -- valid when you're at base).
-- Fallback: sweep the EmpireBases rectangle around the cook (or a 10-tile box if no base).
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
        x1, x2, y1, y2, z1, z2 = cx - SCAN_R, cx + SCAN_R, cy - SCAN_R, cy + SCAN_R, cz, cz
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

local function cookAround(char, cookName)
    local cooked = 0
    forEachBaseContainer(char, function(cont)
        if cooked >= MAX_PER then return end
        local items = nil; pcall(function() items = cont:getItems() end)
        if items then
            for j = 0, items:size() - 1 do
                if cooked >= MAX_PER then break end
                local it = items:get(j)
                if isRawMeal(it) then
                    pcall(function() it:setCooked(true) end)
                    cooked = cooked + 1
                end
            end
        end
    end)
    if cooked > 0 then
        pcall(function()
            HaloTextHelper.addText(char, (cookName or "Cook") .. " cooked " .. cooked .. " meals", HaloTextHelper.getColorGreen())
        end)
        print("[EmpireCook] " .. tostring(cookName) .. " cooked " .. cooked .. " meals.")
    end
    return cooked
end

local function onTick()
    local now = getTimestampMs()
    if now - lastRun < COOK_MS then return end
    lastRun = now
    local ss, char, name = findCook()
    if not char then
        if not hintedNoCook then
            hintedNoCook = true
            local p = getSpecificPlayer(0)
            if p then pcall(function()
                HaloTextHelper.addText(p, "No Cook assigned -- assign one to keep the larder fed", HaloTextHelper.getColorWhite())
            end) end
        end
        return
    end
    hintedNoCook = false
    pcall(function() cookAround(char, name) end)
end

Events.OnPlayerUpdate.Add(function() pcall(onTick) end)
print("[EmpireNPC] Cook role loaded. Assign a survivor as Cook -> they keep the larder cooked.")
