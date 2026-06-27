-- Empire NPC - Farming Bridge
-- SSC ships a REAL animated farming task: the survivor walks to the marked FarmingArea, equips a
-- shovel + water, and runs the actual game actions -- water, plow, harvest, replant -- then hauls
-- the crops to the marked FoodStorageArea. It has been DEAD on B41 because it calls
-- basicFarming.getCurrentPlanting(sq): a global that was never defined anywhere (leftover from an
-- old farming API). Every plant lookup hit a nil and killed the task instantly.
-- This shim bridges that one call to B41's CFarmingSystem, which brings SSC's farmer to life.

basicFarming = basicFarming or {}

if not basicFarming.getCurrentPlanting then
    function basicFarming.getCurrentPlanting(sq)
        if not sq then return nil end
        if not CFarmingSystem or not CFarmingSystem.instance then return nil end
        local plant = nil
        pcall(function() plant = CFarmingSystem.instance:getLuaObjectOnSquare(sq) end)
        return plant
    end
end

print("[EmpireNPC] Farming bridge loaded (revives SSC's animated farmer via CFarmingSystem).")
