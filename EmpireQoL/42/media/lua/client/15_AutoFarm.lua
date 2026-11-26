-- Empire QoL :: 15_AutoFarm.lua  (27 Nov 2026, B42.22)
-- King: "i love empire building but dont like the sorting and small things".
-- AUTO-TEND THE FARM: the farm zone King paints with EmpireZones (type "farm") finally does something.
-- On the 10-minute beat, when he is idle and safe, a competent farmhand tends the plants inside a
-- painted farm zone that are close by:
--   * ripe plants are harvested (real vanilla ISHarvestPlantAction, walking there first),
--   * thirsty plants are watered (real vanilla ISWaterPlantAction) from a water container he carries or
--     that sits in base storage, filled just past what the crop needs; rain-fed plants are left alone.
-- Water choice: tainted water first (crops do not mind, he keeps the clean stuff), then big clean
-- containers (bucket, jug, watering can). Small clean bottles stay for drinking (CFG.USE_DRINKING_WATER).
-- The previous hand item is put back in his hands afterwards.
-- NOT done on purpose: sowing, ploughing, fertilising, composting, curing disease, weeding, pulling dead
-- plants. Those are decisions (what to plant, where), not chores. The produce lands in the body
-- inventory like a normal harvest, and noteLoot() makes the next beat at base file it.
--
-- PERFORMANCE: no tile scan, no per-frame handler. It walks the vanilla farming registry
-- (CFarmingSystem.instance: one entry per plant the game already tracks) once per beat, and only when a
-- farm zone exists at all (cached against EmpireZones.version). Per beat at most MAX_TASKS plants are queued.
-- The registry rows are refreshed from the real object (updateFromIsoObject) only for plants that are
-- both inside the reach radius and inside a farm zone.
--
-- Numpad 5 (13_AutoChores) switches it off with everything else.

local CFG = {
    ENABLED            = true,
    HARVEST            = true,
    WATER              = true,
    REACH              = 20,    -- tiles: plants farther than this from him are left for later
    MAX_TASKS          = 8,     -- plants queued per beat (harvests first)
    MAX_SCAN           = 600,   -- registry rows looked at per beat
    WATER_MARGIN       = 15,    -- water a plant when waterLvl < waterNeeded - this
    WATER_OVER         = 5,     -- ... and give it enough to reach waterNeeded + this
    RETEND_BEATS       = 2,     -- do not queue the same plant again within this many beats
    BASE_STOCK         = true,  -- may take a water container from base storage while inside the base
    USE_DRINKING_WATER = false, -- true: small clean-water bottles may be poured on crops too
    BIG_CONTAINER      = 2.0,   -- litres: clean water counts as "farm water" from this capacity up
    PREFER_TAINTED     = true,
    DEFAULT_NEED       = 70,    -- waterNeeded when the plant row has none
}

local AC = EmpireAutoChores
local m, fetch = AC.m, AC.fetch

local state = { tended = {}, zonesVersion = -1, farms = {}, lastTasks = 0 }
EmpireAutoFarm = { cfg = CFG, state = state }

local function now() return (EmpireAutoChores.state and EmpireAutoChores.state.beat) or 0 end

-- ---- farm zones (the farm-type zones are cached against the zone version, so a save with no farm
-- zone costs one number compare per beat). Zones may overlap (a farm painted inside the base), so
-- this looks at the farm zones' own tiles instead of EmpireZones.zoneAt, which returns just one zone. ----
local function farmZones()
    local EZ = EmpireZones
    if not (EZ and EZ.all) then return nil end
    if state.zonesVersion == EZ.version then return state.farms end
    local list = {}
    pcall(function()
        for _, z in pairs(EZ.all()) do if z.type == "farm" and z.tiles then list[#list + 1] = z end end
    end)
    state.zonesVersion, state.farms = EZ.version, list
    return list
end

local function inFarmZone(x, y, z)
    local farms = state.farms
    if not farms or #farms == 0 then return false end
    local key = nil
    pcall(function() key = EmpireZones.key(x, y, z) end)
    if not key then return false end
    for i = 1, #farms do if farms[i].tiles[key] then return true end end
    return false
end

local function raining()
    local r = false
    pcall(function() r = RainManager.isRaining() end)
    return r
end

-- ---- water sources ----
local function waterUses(it)
    local u = 0
    pcall(function() u = ISFarmingMenu.getWaterUsesInteger(it) or 0 end)
    return u
end

-- one eligible source: { item, cont, uses, tainted, from }
local function survey(conts, from, out)
    for _, cont in ipairs(conts or {}) do
        local items = nil
        pcall(function() items = cont:getItems() end)
        local n = items and (m(items, "size") or 0) or 0
        for i = 0, n - 1 do
            local it = m(items, "get", i)
            if it and not m(it, "isFavorite") then
                local fc = m(it, "getFluidContainer")
                if fc or m(it, "isWaterSource") then
                    local uses = waterUses(it)
                    if uses > 0 then
                        local fluid = fc and m(m(fc, "getPrimaryFluid"), "getFluidTypeString") or nil
                        local tainted = (fluid == "TaintedWater")
                        local cap = fc and (tonumber(m(fc, "getCapacity")) or 0) or 99
                        if tainted or CFG.USE_DRINKING_WATER or cap >= CFG.BIG_CONTAINER then
                            out[#out + 1] = { item = it, cont = cont, uses = uses, tainted = tainted, from = from }
                        end
                    end
                end
            end
        end
    end
    return out
end

local function waterSources(player, ctx)
    local list = survey(AC.carriedContainers(player), "carried", {})
    if CFG.BASE_STOCK and ctx.inBase then
        local bc = AC.baseContainers()
        if bc then survey(bc, "base", list) end
    end
    table.sort(list, function(a, b)
        if CFG.PREFER_TAINTED and a.tainted ~= b.tainted then return a.tainted end
        if a.from ~= b.from then return a.from == "carried" end
        return a.uses > b.uses
    end)
    return list
end

-- ---- the chore ----
local function dist(px, py, x, y) return math.max(math.abs(px - x), math.abs(py - y)) end

local function gather(player)
    local sys = CFarmingSystem and CFarmingSystem.instance
    if not sys then return nil end
    local count = nil
    pcall(function() count = sys:getLuaObjectCount() end)
    if not count or count < 1 then return nil end
    local ux, uy, uz = 0, 0, 0
    pcall(function() ux, uy, uz = player:getX(), player:getY(), math.floor(player:getZ()) end)
    local beat = now()
    local harvest, water = {}, {}
    for i = 1, math.min(count, CFG.MAX_SCAN) do
        local pl = nil
        pcall(function() pl = sys:getLuaObjectByIndex(i) end)
        if pl and pl.x and pl.y and pl.z == uz and dist(ux, uy, pl.x, pl.y) <= CFG.REACH
           and inFarmZone(pl.x, pl.y, pl.z) then
            local key = pl.x .. "," .. pl.y .. "," .. pl.z
            local last = state.tended[key]
            if not (last and (beat - last) < CFG.RETEND_BEATS) then
                -- the registry row can be stale: refresh from the real plant (vanilla does the same before acting)
                local live = false
                pcall(function() pl:updateFromIsoObject(); live = pl:getIsoObject() ~= nil end)
                local alive = false
                pcall(function() alive = live and pl.state == "seeded" and pl:isAlive() end)
                if alive then
                    local d = dist(ux, uy, pl.x, pl.y)
                    local ripe = false
                    pcall(function() ripe = pl:canHarvest() end)
                    if ripe then
                        if CFG.HARVEST then harvest[#harvest + 1] = { plant = pl, key = key, d = d } end
                    elseif CFG.WATER then
                        local need = tonumber(pl.waterNeeded) or CFG.DEFAULT_NEED
                        local lvl = tonumber(pl.waterLvl) or 100
                        if lvl < need - CFG.WATER_MARGIN and not (pl.exterior and raining()) then
                            water[#water + 1] = { plant = pl, key = key, d = d, want = math.min(100, need + CFG.WATER_OVER) - lvl }
                        end
                    end
                end
            end
        end
    end
    local byDist = function(a, b) return a.d < b.d end
    table.sort(harvest, byDist); table.sort(water, byDist)
    return harvest, water
end

-- The first container (in preference order) with at least half of what the plant needs: no crumbs, no
-- one-use trips. When none has that much, the fullest one left.
local function pickSource(sources, need)
    local half, best = math.ceil(need / 2), nil
    for _, s in ipairs(sources) do
        if s.uses >= half then return s end
        if s.uses > 0 and (not best or s.uses > best.uses) then best = s end
    end
    return best
end

local function squareOf(pl)
    local sq = nil
    pcall(function() sq = pl:getSquare() end)
    return sq
end

local function walkTo(player, sq)
    local ok, res = pcall(ISFarmingMenu.walkToPlant, player, sq)
    return ok and res and true or false
end

local function run(player, ctx)
    if not CFG.ENABLED then return false end
    local farms = farmZones()
    if not farms or #farms == 0 then return false end
    if ctx.beat % 30 == 0 then   -- forget old "already tended" marks
        for k, b in pairs(state.tended) do if ctx.beat - b > 30 then state.tended[k] = nil end end
    end
    local harvest, water = gather(player)
    if not harvest or (#harvest == 0 and #water == 0) then return false end

    local beat, tasks, harvested, watered = ctx.beat, 0, 0, 0

    for _, h in ipairs(harvest) do
        if tasks >= CFG.MAX_TASKS then break end
        local sq = squareOf(h.plant)
        if sq and walkTo(player, sq) then
            ISTimedActionQueue.add(ISHarvestPlantAction:new(player, h.plant, 100))
            state.tended[h.key] = beat
            tasks, harvested = tasks + 1, harvested + 1
        end
    end

    if #water > 0 and tasks < CFG.MAX_TASKS then
        local sources = waterSources(player, ctx)
        local prev = m(player, "getPrimaryHandItem")
        local cur = nil
        for _, w in ipairs(water) do
            if tasks >= CFG.MAX_TASKS then break end
            local need = math.min(math.ceil(w.want / 10), 10)
            local src = pickSource(sources, need)   -- preference order, but not a near-empty one
            if not src then break end
            local sq = squareOf(w.plant)
            if sq then
                local uses = math.min(src.uses, math.ceil(w.want / 10), 10)
                if uses >= 1 then
                    if not src.ready then
                        src.ready = fetch(player, src.item, src.cont)   -- real item to the body inventory
                        if src.ready then src.cont = m(player, "getInventory") end
                    end
                    if src.ready then
                        if cur ~= src.item and m(player, "getPrimaryHandItem") ~= src.item then
                            ISTimedActionQueue.add(ISEquipWeaponAction:new(player, src.item, 50, true))
                        end
                        cur = src.item
                        if walkTo(player, sq) then
                            ISTimedActionQueue.add(ISWaterPlantAction:new(player, src.item, uses, sq, 20 + 6 * uses))
                            src.uses = src.uses - uses
                            state.tended[w.key] = beat
                            tasks, watered = tasks + 1, watered + 1
                        end
                    else
                        src.uses = 0   -- could not take it: try the next container
                    end
                end
            end
        end
        -- put the weapon / tool he was holding back in his hands
        if cur and prev and prev ~= cur and (m(prev, "getContainer") ~= nil) then
            local two = (m(prev, "isRequiresEquippedBothHands") == true) or (m(prev, "isTwoHandWeapon") == true)
            ISTimedActionQueue.add(ISEquipWeaponAction:new(player, prev, 50, true, two))
        end
    end

    state.lastTasks = tasks
    if tasks == 0 then return false end
    if harvested > 0 then AC.noteLoot(harvested) end   -- the crop is in the pack: the next beat at base files it
    AC.say(player, "Tending the farm: " .. harvested .. " to harvest, " .. watered .. " to water", true)
    print(string.format("[EmpireAutoFarm] queued %d harvest, %d water (%d plants in reach needing work)", harvested, watered, #harvest + #water))
    return true
end
EmpireAutoFarm.run = run

if AC and AC.register then
    AC.register("farm", 50, run, { enabled = function() return CFG.ENABLED end })
end

print("[EmpireQoL] AutoFarm loaded: harvests and waters plants inside painted farm zones on the 10-min beat (no per-frame handler, no tile scans).")
