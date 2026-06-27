-- Empire NPC - Farm Gate
-- BUG: SSC's FarmingTask scans the whole painted FarmingArea rectangle and plows ANY empty
-- tile (FarmingTask:getAPlantThatNeeds("Plowing") / getASquareToPlow) with NO floor-type check.
-- On a striped roof farm (dirt rows + concrete gaps) the farmer happily furrows the concrete.
-- FIX: override the two plow-tile pickers so they only ever return DIRT/GRASS ground, skipping
-- concrete and any constructed floor. Lives here (not the SSC workshop file) so SSC updates
-- don't revert it. Reimplements ONLY the plow scan; all other farming logic stays SSC's.

EmpireFarmGate = EmpireFarmGate or {}

-- Sprite-name fragments that mark natural, diggable ground. Lowercased substring match.
-- Covers vanilla dirt/grass/sand families + the player-placed "dirt" floor. Concrete/road
-- ("street"), interior, carpentry, industry and roof sprites contain none of these.
EmpireFarmGate.DIRT_HINTS = EmpireFarmGate.DIRT_HINTS or {
    "blends_natural", "_natural_", "d_generic", "dirt", "grass", "newgrass", "sand", "gravel",
}

-- Set true to make the farmer print the sprite name of every tile it SKIPS (for tuning).
EmpireFarmGate.DEBUG = EmpireFarmGate.DEBUG or false

function EmpireFarmGate.floorName(sq)
    local name
    pcall(function()
        local floor = sq:getFloor()
        local spr = floor and floor:getSprite()
        name = spr and spr:getName()
    end)
    return name
end

function EmpireFarmGate.isDirt(sq)
    if not sq then return false end
    local name = EmpireFarmGate.floorName(sq)
    if not name then return false end
    name = string.lower(name)
    for _, frag in ipairs(EmpireFarmGate.DIRT_HINTS) do
        if string.find(name, frag, 1, true) then return true end
    end
    if EmpireFarmGate.DEBUG then print("[EmpireFarmGate] skip non-dirt tile: " .. name) end
    return false
end

-- ---- Overrides, installed after SSC's FarmingTask exists ----
function EmpireFarmGate.install()
    if not FarmingTask then return false end
    if EmpireFarmGate._installed then return true end

    -- Active plow picker used by FarmingTask:update(). Reimplements ONLY the "Plowing" branch
    -- (dirt-gated); everything else delegates to SSC's original untouched.
    local origNeeds = FarmingTask.getAPlantThatNeeds
    function FarmingTask:getAPlantThatNeeds(needs)
        if needs ~= "Plowing" then return origNeeds(self, needs) end
        local area = self.group and self.group:getGroupArea("FarmingArea")
        if not area then return nil end
        for x = area[1], area[2] do
            for y = area[3], area[4] do
                local sq = getCell():getGridSquare(x, y, area[5])
                if (sq) and EmpireFarmGate.isDirt(sq) then
                    local plant = self:getPlant(sq)
                    if (not plant) or (plant and (not plant:isAlive())) then
                        return sq
                    end
                end
            end
        end
        return nil
    end

    -- Secondary/legacy plow picker, dirt-gated too (cheap insurance).
    function FarmingTask:getASquareToPlow()
        local area = self.group and self.group:getGroupArea("FarmingArea")
        if not area then return nil end
        for x = area[1], area[2] do
            for y = area[3], area[4] do
                local sq = getCell():getGridSquare(x, y, area[5])
                if (sq) and (sq:isFree(false)) and (x % 2 == 0) and (y % 2 ~= 0)
                    and EmpireFarmGate.isDirt(sq) then
                    local plant = self:getPlant(sq)
                    if (plant == nil) then return sq end
                end
            end
        end
        return nil
    end

    EmpireFarmGate._installed = true
    print("[EmpireNPC] Farm gate installed (farmer only plows dirt/grass, skips concrete).")
    return true
end

Events.OnGameBoot.Add(function() EmpireFarmGate.install() end)
Events.OnGameStart.Add(function() EmpireFarmGate.install() end)
