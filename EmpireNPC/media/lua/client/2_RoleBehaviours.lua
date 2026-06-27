-- Empire NPC - Role Behaviours v3 (Warden removed; real base-wide Farmer)
-- Guard:  holds post / attacks on threat (only when AUTO_DEPLOY is on).
-- Farmer: a REAL farmer built on PZ's CFarmingSystem -- harvests ripe crops, waters dry ones,
--         FERTILIZES growing crops (compost/fertilizer from storage), and SOWS empty plowed
--         plots using seeds from base storage. Works over the whole
--         defined base footprint on the FLOOR THE FARMER STANDS ON, so a rooftop farm is
--         tended just by stationing the farmer up on the roof.
-- All calls pcall'd.

local ROLE_TICK = 600
local roleTick = 0
local GUARD_RADIUS = 20

-- ---------- base helpers (the base YOU defined, via EmpireBases) ----------
local function baseRect(char)
    local b
    pcall(function()
        if EmpireBases and EmpireBases.activeBase then b = EmpireBases.activeBase(char) end
        if not b and EmpireBases and EmpireBases.list then local l = EmpireBases.list(); b = l and l[1] end
    end)
    return b
end

-- iterate every storage container in the whole defined base (fallback: 12-tile box)
local function eachBaseContainer(char, fn)
    local cell = getCell(); if not cell or not char then return end
    -- fast path: the maintained base index (valid when you're at base)
    local idx
    pcall(function() if EmpireBaseCache and EmpireBaseCache.get then idx = EmpireBaseCache.get() end end)
    if idx and idx.containers and #idx.containers > 0 then
        for i = 1, #idx.containers do fn(idx.containers[i]) end
        return
    end
    local cz = math.floor(char:getZ())
    local b = baseRect(char)
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
                local c = nil
                pcall(function() c = objs:get(i):getContainer() end)
                if c and not seen[c] then seen[c] = true; fn(c) end
            end end
        end
    end end end
end

-- ---------- guard (unchanged; only acts when AUTO_DEPLOY is on) ----------
local function runGuardBehaviour(ss, settler)
    if not EmpireNPC.AUTO_DEPLOY then return end
    local char = ss:Get()
    if not char or char:isDead() then return end

    local post = settler.guardPost
    if post then
        local dx = char:getX() - post.x
        local dy = char:getY() - post.y
        if math.sqrt(dx*dx + dy*dy) > 8 then
            char:setX(post.x); char:setY(post.y); char:setZ(post.z)
        end
    end

    local px, py, pz = math.floor(char:getX()), math.floor(char:getY()), math.floor(char:getZ())
    local threat = false
    for x = px - GUARD_RADIUS, px + GUARD_RADIUS do
        for y = py - GUARD_RADIUS, py + GUARD_RADIUS do
            local sq = getCell():getGridSquare(x, y, pz)
            if sq then
                local objs = sq:getObjects()
                for i = 0, objs:size() - 1 do
                    if instanceof(objs:get(i), "IsoZombie") then threat = true; break end
                end
            end
            if threat then break end
        end
        if threat then break end
    end

    EmpireNPC.stats.threatLevel = threat and 1 or 0
    if ss.setAIMode then
        if threat then ss:setAIMode("Attack") else ss:setAIMode("StandGround") end
    end
end

-- ---------- farmer (REAL, base-wide, rooftop-aware) ----------
local FARM_RANGE       = 25     -- box around the farmer, clipped to the base footprint
local FARM_WATER_MIN   = 40     -- water a growing crop below this water level
local FARM_MAX_ACTIONS = 6      -- jobs per cycle, so it never hangs on a giant farm

-- seed item fullType -> { crop = conf key, need = seeds required }, built once from PZ's config
local SEED_MAP
local function buildSeedMap()
    if SEED_MAP then return SEED_MAP end
    SEED_MAP = {}
    pcall(function()
        if not farming_vegetableconf or not farming_vegetableconf.props then return end
        for key, prop in pairs(farming_vegetableconf.props) do
            local sn = prop.seedName
            if sn then SEED_MAP[sn] = { crop = key, need = prop.seedsRequired or 1 } end
        end
    end)
    return SEED_MAP
end

-- remove up to n seeds of fullType from base storage; returns how many were removed
local function consumeSeeds(char, fullType, n)
    local removed = 0
    eachBaseContainer(char, function(cont)
        if removed >= n then return end
        local items = cont:getItems()
        for i = items:size() - 1, 0, -1 do
            if removed >= n then break end
            local it = items:get(i)
            local ft = nil; pcall(function() ft = it:getFullType() end)
            if ft == fullType then pcall(function() cont:Remove(it) end); removed = removed + 1 end
        end
    end)
    if removed > 0 then pcall(function() if EmpireBaseCache and EmpireBaseCache.invalidate then EmpireBaseCache.invalidate() end end) end
    return removed
end

-- pick one fertilizer item (Fertilizer or CompostBag) from base storage
local FERT_MAX = 4   -- max plants fertilized per cycle, so it never burns through your compost
local function findFertilizer(char)
    local found
    eachBaseContainer(char, function(cont)
        if found then return end
        local items = cont:getItems()
        for i = 0, items:size() - 1 do
            local it = items:get(i)
            local t = nil; pcall(function() t = it:getType() end)
            if t == "CompostBag" or t == "Fertilizer" then found = { item = it, cont = cont }; return end
        end
    end)
    return found
end

local function runFarmerBehaviour(ss, settler)
    local char = ss:Get()
    if not char or char:isDead() then return end
    -- If a FarmingArea is marked, SSC's REAL animated farmer handles the farm (walk/water/plow/
    -- harvest/replant + haul to FoodStorageArea). Stand down so we don't double up on it.
    local hasFarmArea = false
    pcall(function()
        local grp = ss:getGroup()
        if grp and grp:getGroupAreaCenterSquare("FarmingArea") then hasFarmArea = true end
    end)
    if hasFarmArea then return end
    if not CFarmingSystem or not CFarmingSystem.instance then return end
    local cell = getCell(); if not cell then return end

    local fx, fy, fz = math.floor(char:getX()), math.floor(char:getY()), math.floor(char:getZ())
    local x1, x2 = fx - FARM_RANGE, fx + FARM_RANGE
    local y1, y2 = fy - FARM_RANGE, fy + FARM_RANGE
    local b = baseRect(char)
    if b then
        x1 = math.max(x1, math.min(b.x1, b.x2)); x2 = math.min(x2, math.max(b.x1, b.x2))
        y1 = math.max(y1, math.min(b.y1, b.y2)); y2 = math.min(y2, math.max(b.y1, b.y2))
    end

    local harvest, dry, empty, unfert = {}, {}, {}, {}
    for x = x1, x2 do
        for y = y1, y2 do
            local sq = cell:getGridSquare(x, y, fz)   -- the floor the farmer stands on (rooftop = roof)
            if sq then
                local plant
                pcall(function() plant = CFarmingSystem.instance:getLuaObjectOnSquare(sq) end)
                if plant then
                    local canH = false; pcall(function() canH = plant.canHarvest and plant:canHarvest() end)
                    local st = plant.state
                    if canH then
                        harvest[#harvest + 1] = sq
                    elseif st == "seeded" then                 -- a growing crop
                        if (plant.waterLvl or 100) < FARM_WATER_MIN then
                            dry[#dry + 1] = { sq = sq, w = plant.waterLvl or 0 }
                        end
                        if not plant.fertilizer then            -- not yet fertilized this growth
                            unfert[#unfert + 1] = sq
                        end
                    elseif st == "plow" then                    -- plowed, empty
                        empty[#empty + 1] = sq
                    end
                end
            end
        end
    end

    local budget, did = FARM_MAX_ACTIONS, 0

    -- 1) harvest ripe crops
    for _, sq in ipairs(harvest) do
        if budget <= 0 then break end
        pcall(function() CFarmingSystem.instance:sendCommand(char, 'harvest', { x = sq:getX(), y = sq:getY(), z = sq:getZ() }) end)
        budget = budget - 1; did = did + 1
    end

    -- 2) water dry crops
    for _, d in ipairs(dry) do
        if budget <= 0 then break end
        local uses = math.ceil((100 - d.w) / 5)
        if uses > 20 then uses = 20 elseif uses < 1 then uses = 1 end
        pcall(function() CFarmingSystem.instance:sendCommand(char, 'water', { x = d.sq:getX(), y = d.sq:getY(), z = d.sq:getZ(), uses = uses }) end)
        budget = budget - 1; did = did + 1
    end

    -- 3) sow empty plowed plots with seeds from base storage
    if budget > 0 and #empty > 0 then
        local map = buildSeedMap()
        local avail = {}
        eachBaseContainer(char, function(cont)
            local items = cont:getItems()
            for i = 0, items:size() - 1 do
                local it = items:get(i); local ft = nil; pcall(function() ft = it:getFullType() end)
                if ft and map[ft] then avail[ft] = (avail[ft] or 0) + 1 end
            end
        end)
        local bestFt
        for ft, cnt in pairs(avail) do
            if cnt >= (map[ft].need or 1) and (not bestFt or cnt > avail[bestFt]) then bestFt = ft end
        end
        if bestFt then
            local info = map[bestFt]
            local plots = math.min(#empty, budget, math.floor(avail[bestFt] / info.need))
            if plots > 0 then
                local removed = consumeSeeds(char, bestFt, plots * info.need)
                local doable = math.floor(removed / info.need)
                for i = 1, doable do
                    local sq = empty[i]
                    pcall(function() CFarmingSystem.instance:sendCommand(char, 'seed', { x = sq:getX(), y = sq:getY(), z = sq:getZ(), typeOfSeed = info.crop }) end)
                    did = did + 1
                end
            end
        end
    end

    -- 4) fertilize growing crops that haven't been fertilized yet (compost/fertilizer from storage)
    if #unfert > 0 then
        local fert = findFertilizer(char)
        local fertLeft = FERT_MAX
        for _, sq in ipairs(unfert) do
            if fertLeft <= 0 or not fert then break end
            pcall(function() CFarmingSystem.instance:sendCommand(char, 'fertilize', { x = sq:getX(), y = sq:getY(), z = sq:getZ() }) end)
            did = did + 1; fertLeft = fertLeft - 1
            -- drain one use of the bag; remove it when empty, then grab another
            local depleted = false
            pcall(function()
                local ud = (fert.item.getUseDelta and fert.item:getUseDelta()) or 0
                if ud and ud > 0 and fert.item.getUsedDelta then
                    fert.item:Use()
                    if fert.item:getUsedDelta() <= 0 then fert.cont:Remove(fert.item); depleted = true end
                else
                    fert.cont:Remove(fert.item); depleted = true
                end
            end)
            if depleted then fert = findFertilizer(char) end
        end
    end

    if did > 0 then
        pcall(function() if EmpireBaseCache and EmpireBaseCache.invalidate then EmpireBaseCache.invalidate() end end)
        local p = getSpecificPlayer(0)
        if p then HaloTextHelper.addText(p, (settler.name or "Farmer") .. " worked the farm (" .. did .. ")", HaloTextHelper.getColorGreen()) end
    end
end

-- ---------- dispatch ----------
local function runRoleBehaviours()
    if not SSM or not SSM.SuperSurvivors then return end
    local count = SSM.SurvivorCount or 0
    for i = 0, count + 1 do
        local ss = SSM.SuperSurvivors[i]
        if ss and not ss:isDead() then
            local name = ss:getName() or ""
            if name ~= "" then
                local settler = EmpireNPC.getSettler(name)
                settler.name = name
                local role = settler.role or EmpireNPC.Roles.NONE
                if role == EmpireNPC.Roles.GUARD then
                    pcall(runGuardBehaviour, ss, settler)
                elseif role == EmpireNPC.Roles.FARMER then
                    pcall(runFarmerBehaviour, ss, settler)
                end
            end
        end
    end
end

local function onTick()
    roleTick = roleTick + 1
    if roleTick < ROLE_TICK then return end
    roleTick = 0
    pcall(runRoleBehaviours)
end

Events.OnTick.Add(onTick)
print("[EmpireNPC] Role Behaviours v3.1 loaded (Warden removed; real Farmer + fertilizer/compost).")
