-- Empire QoL :: 41_VehicleUnstick.lua
-- Right-click at a vehicle -> "Empire: Unstick vehicle". Fixes the two classic
-- physics screws: (1) vehicle sunk into the ground and immovable, (2) motorbike
-- fallen flat on its side with no way to right it.
--
-- GROUNDED: position move uses the exact world-transform technique from the War
-- Thunder Vehicle Library's HeliMove.lua (running live in this mod list) --
-- reflect into BaseVehicle.jniTransform, shift the transform origin, write it
-- back. Transform axes: (worldX, HEIGHT, worldY). Uprighting uses setAngles(),
-- the same call tsarslib / Military Tool Kit use on their vehicles.
-- Singleplayer scope (direct transform write; no MP transmit).

local LIFT = 0.85          -- how far to pop the vehicle UP out of the terrain
local SEARCH_R = 6         -- ring-search radius for the nearest clear square
local PLAYER_RANGE = 5     -- must be this close to the vehicle to use it

-- ---- transform move (WT-lib technique) ----
local _wtFieldNum = nil
local function getJavaFieldNum(object, fieldName)
    for i = 0, getNumClassFields(object) - 1 do
        local javaField = getClassField(object, i)
        if luautils.stringEnds(tostring(javaField), '.' .. fieldName) then
            return i
        end
    end
end

local function moveVehicle(vehicle, x_delta, up_delta, y_delta)
    if _wtFieldNum == nil then
        _wtFieldNum = getJavaFieldNum(vehicle, "jniTransform")
    end
    if not _wtFieldNum then return false end
    local ok = pcall(function()
        local tmpTransform = getClassFieldVal(vehicle, getClassField(vehicle, _wtFieldNum))
        local wTransform = vehicle:getWorldTransform(tmpTransform)
        local origin = getClassFieldVal(wTransform, getClassField(wTransform, 1))
        origin:set(origin:x() + x_delta, origin:y() + up_delta, origin:z() + y_delta)
        vehicle:setWorldTransform(wTransform)
    end)
    return ok
end

-- ---- nearest clear square: ring search out from the vehicle ----
local function findClearSquare(vx, vy, vz)
    local cell = getCell()
    if not cell then return nil end
    local cx, cy = math.floor(vx), math.floor(vy)
    for r = 1, SEARCH_R do
        for dx = -r, r do
            for dy = -r, r do
                if math.max(math.abs(dx), math.abs(dy)) == r then   -- ring shell only
                    local sq = cell:getGridSquare(cx + dx, cy + dy, vz)
                    if sq then
                        local free = false
                        pcall(function() free = sq:isFree(false) end)
                        if free then
                            -- don't drop it onto another parked vehicle
                            local hasVeh = false
                            pcall(function() hasVeh = sq:getVehicleContainer() ~= nil end)
                            if not hasVeh then return sq end
                        end
                    end
                end
            end
        end
    end
    return nil
end

local function unstick(player, veh)
    if not player or not veh then return end
    -- never yank a vehicle someone is driving
    local driver = nil
    pcall(function() driver = veh:getDriver() end)
    if driver then
        HaloTextHelper.addTextWithArrow(player, "Get out of the vehicle first", "[br/]", false, HaloTextHelper.getColorRed())
        return
    end
    local vx, vy, vz = 0, 0, 0
    pcall(function() vx = veh:getX(); vy = veh:getY(); vz = math.floor(veh:getZ()) end)
    if vz < 0 then vz = 0 end

    local sq = findClearSquare(vx, vy, vz)
    local dx, dy = 0, 0
    if sq then
        dx = (sq:getX() + 0.5) - vx
        dy = (sq:getY() + 0.5) - vy
    end
    -- move to the clear square (or just straight up if none found) + pop out of terrain
    local movedOk = moveVehicle(veh, dx, LIFT, dy)
    -- UPRIGHT: zero roll & pitch, keep the heading -- rights a fallen bike.
    pcall(function() veh:setAngles(0, veh:getAngleY(), 0) end)

    if movedOk then
        HaloTextHelper.addTextWithArrow(player, "Vehicle unstuck - lifted, uprighted" .. (sq and ", moved to clear ground" or ""), "[br/]", false, HaloTextHelper.getColorGreen())
        player:Say("That should do it.")
    else
        -- transform reflection failed (API shift?) -- at least the upright ran
        HaloTextHelper.addTextWithArrow(player, "Uprighted only - couldn't shift position", "[br/]", false, HaloTextHelper.getColorWhite())
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

print("[EmpireQoL] Vehicle Unstick loaded. Right-click at a stuck/sunk/fallen vehicle -> 'Empire: Unstick vehicle'.")
