-- Empire Performance - Corpse Cleanup Auto-trigger
-- Dead bodies are a major FPS sink in PZ - they keep ticking, drawing flies,
-- and consuming render passes even off-screen. This auto-burns/clears corpses
-- near your base after 2 in-game days so they never accumulate.
-- Only fires when you're safe (no zombies nearby, not in combat).

local CORPSE_CHECK_INTERVAL = 3600  -- every minute real time
local CORPSE_BASE_RADIUS = 25       -- tiles around player
local CORPSE_AGE_DAYS = 2           -- auto-clear after 2 in-game days
local corpseTick = 0

local function clearOldCorpses()
    local player = getSpecificPlayer(0)
    if not player or player:isDead() then return end
    if player:getStats():getNumChasingZombies() > 0 then return end

    local px = math.floor(player:getX())
    local py = math.floor(player:getY())
    local pz = math.floor(player:getZ())
    local cleared = 0
    local gameTime = getGameTime()
    local currentDay = gameTime and gameTime:getNightsSurvived() or 0

    for x = px - CORPSE_BASE_RADIUS, px + CORPSE_BASE_RADIUS do
        for y = py - CORPSE_BASE_RADIUS, py + CORPSE_BASE_RADIUS do
            local sq = getCell():getGridSquare(x, y, pz)
            if sq then
                local objs = sq:getObjects()
                for i = objs:size() - 1, 0, -1 do
                    local obj = objs:get(i)
                    if obj and instanceof(obj, "IsoDeadBody") then
                        local md = obj:getModData()
                        if not md.corpseDay then
                            md.corpseDay = currentDay
                        elseif (currentDay - md.corpseDay) >= CORPSE_AGE_DAYS then
                            -- Remove the corpse
                            obj:removeFromWorld()
                            obj:removeFromSquare()
                            cleared = cleared + 1
                        end
                    end
                end
            end
        end
    end

    if cleared > 0 then
        HaloTextHelper.addText(player,
            "Cleared " .. cleared .. " old corpses (FPS boost)",
            HaloTextHelper.getColorGreen())
    end
end

local function onTick()
    corpseTick = corpseTick + 1
    if corpseTick < CORPSE_CHECK_INTERVAL then return end
    corpseTick = 0
    pcall(clearOldCorpses)
end

Events.OnTick.Add(onTick)
print("[EmpirePerf] Auto corpse cleanup loaded.")
