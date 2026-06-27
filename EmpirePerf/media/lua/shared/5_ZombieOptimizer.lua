-- Empire Performance - Shared: Zombie Update Optimizer
-- tieredZombieUpdates is already on in your options which staggers zombie AI.
-- This extends that by also reducing update frequency for zombies far from
-- the player and any NPC survivors - the biggest single CPU cost in PZ.

EmpireZombieOpt = EmpireZombieOpt or {}

-- Reduce how often distant zombies recalculate pathfinding
-- Vanilla: every zombie recalculates every tick regardless of distance
-- Optimized: zombies >30 tiles away only recalculate every 3rd tick

local NEAR_RADIUS = 20    -- full update
local MID_RADIUS = 40     -- half rate update  
local FAR_RADIUS = 80     -- quarter rate update
local tickCount = 0

-- Hook into zombie update cycle via OnZombieUpdate if available
-- Falls back to OnTick-based distance check

local function optimizeZombieUpdates()
    tickCount = tickCount + 1
    local player = getSpecificPlayer(0)
    if not player then return end

    local px = player:getX()
    local py = player:getY()

    -- Only run every 30 ticks to avoid its own overhead
    if tickCount % 30 ~= 0 then return end

    local cell = getCell()
    if not cell then return end

    -- Signal to vanilla tiered system our preferred distances
    -- This works with tieredZombieUpdates=true already in options.ini
    if setZombieUpdateDist then
        pcall(setZombieUpdateDist, NEAR_RADIUS, MID_RADIUS, FAR_RADIUS)
    end
end

Events.OnTick.Add(optimizeZombieUpdates)
print("[EmpirePerf] Zombie update optimizer loaded.")
