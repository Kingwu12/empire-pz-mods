-- Empire QoL :: 41_VehicleUnstick.lua  (v2)
-- Right-click at a vehicle -> "Empire: Unstick vehicle". Fixes vehicles sunk into
-- the terrain and motorbikes fallen flat on their side.
--
-- v2 REWRITE: v1 used the War Thunder lib's java-reflection transform move, which
-- turns out to be DEBUG-MODE ONLY in B42 ("IllegalStateException: Not in debug").
-- v2 uses the recipe from the game's OWN vehicle-angles tool (ISVehicleAngles.lua):
--   setPhysicsActive(false) -> setAngles(level) -> setDebugZ(lift) -> setPhysicsActive(true)
-- Freezing physics, levelling the body, nudging it up off the ground plane, then
-- waking physics makes the engine re-settle the vehicle onto the terrain -- which
-- pops it out of the ground and stands a fallen bike back up. No reflection.

local PLAYER_RANGE = 5     -- must be this close to the vehicle to use it
local LIFT = 0.45          -- setDebugZ lift (0..1 of a tile) before physics wake

local function unstick(player, veh)
    if not player or not veh then return end
    local driver = nil
    pcall(function() driver = veh:getDriver() end)
    if driver then
        pcall(function() HaloTextHelper.addTextWithArrow(player, "Get out of the vehicle first", "[br/]", false, HaloTextHelper.getColorRed()) end)
        return
    end

    local okAngles = false
    pcall(function() veh:setPhysicsActive(false) end)
    -- level the body: zero roll & pitch, keep heading (rights a fallen bike).
    -- Units match vanilla: tsarslib feeds getAngleX/Y/Z straight back into setAngles.
    pcall(function() veh:setAngles(0, veh:getAngleY(), 0); okAngles = true end)
    -- nudge it up off the ground plane so the physics re-settle drops it ON the
    -- terrain instead of leaving it embedded. setDebugZ may not exist on every
    -- build -- pcall'd, and the angles+physics cycle alone fixes most cases.
    pcall(function() veh:setDebugZ(LIFT) end)
    pcall(function() veh:setPhysicsActive(true) end)

    if okAngles then
        pcall(function()
            HaloTextHelper.addTextWithArrow(player, "Vehicle uprighted + re-settled", "[br/]", false, HaloTextHelper.getColorGreen())
            player:Say("That should do it.")
        end)
    else
        pcall(function() HaloTextHelper.addTextWithArrow(player, "Couldn't adjust this vehicle", "[br/]", false, HaloTextHelper.getColorRed()) end)
    end
end

local function onFillWorldObjectContextMenu(playerNum, context, worldobjects, test)
    if test then return end
    local player = getSpecificPlayer(playerNum)
    if not player then return end
    local veh = nil
    pcall(function()
        if ISVehicleMenu and ISVehicleMenu.getVehicleToInteractWith then
            veh = ISVehicleMenu.getVehicleToInteractWith(player)
        end
    end)
    if not veh then return end
    local dist = math.huge
    pcall(function()
        local dxx, dyy = veh:getX() - player:getX(), veh:getY() - player:getY()
        dist = math.sqrt(dxx * dxx + dyy * dyy)
    end)
    if dist > PLAYER_RANGE then return end
    context:addOption("Empire: Unstick vehicle (lift + upright)", player, unstick, veh)
end
Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)

print("[EmpireQoL] Vehicle Unstick v2 loaded (vanilla physics-cycle technique; no debug reflection).")
