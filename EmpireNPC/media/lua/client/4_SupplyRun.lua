-- Empire NPC - Supply Run Handler v2
-- A settler sent on a supply run returns and DEPOSITS supplies into base storage:
-- the group's storage zones (drawn in the Page-Up panel) first, else a nearby base
-- container. It NEVER puts loot into the player's inventory.

local runTick = 0
local RUN_CHECK = 60

local SUPPLY_LOOT = {
    food = { "Base.Chips", "Base.TinnedBeans", "Base.TinnedSardines",
             "Base.Crackers", "Base.CannedCorn", "Base.Rice", "Base.Pasta",
             "Base.CannedPeas", "Base.CannedChili", "Base.CannedBolognese",
             "Base.CannedMushroomSoup", "Base.Dogfood" },
    med  = { "Base.Bandage", "Base.Painkillers", "Base.Disinfectant",
             "Base.AdhesiveBandage", "Base.Antibiotics", "Base.Pills" },
    ammo = { "Base.Bullets9mm", "Base.ShotgunShells", "Base.Bullets308",
             "Base.Bullets556mm", "Base.Bullets45", "Base.Bullets38" },
    water = { "Base.WaterBottleFull", "Base.Pop", "Base.Pop2" },
}

-- Consumables only -- supply runs top up what actually gets USED UP. Food is weighted
-- heaviest, then meds + ammo, with the odd drink. Tools/junk are deliberately gone: the
-- base crafts its own and you don't need a 51st saw.
local LOOT_ROLL = { "food", "food", "food", "food", "med", "med", "ammo", "ammo", "water" }

local function getRandomLoot()
    local cat = LOOT_ROLL[ZombRand(#LOOT_ROLL) + 1]
    local items = SUPPLY_LOOT[cat]
    return items[ZombRand(#items) + 1]
end

-- find the live SSC survivor object for one of our settlers, by name
local function findSurvivor(name)
    local found
    pcall(function()
        for _, ss in ipairs(EmpireNPC.getActiveSurvivors()) do
            if ss:getName() == name then found = ss; return end
        end
    end)
    return found
end

-- first storage container in the WHOLE DEFINED BASE (EmpireBases rectangle), across its floors.
-- Falls back to an 8-tile box only if no base is defined. Used as the deposit target when the
-- SSC group storage zone can't take the item.
local function nearbyContainer(char)
    local best
    -- fast path: first container from the maintained base index (valid when you're at base)
    pcall(function()
        if EmpireBaseCache and EmpireBaseCache.get then
            local idx = EmpireBaseCache.get()
            if idx and idx.containers and #idx.containers > 0 then best = idx.containers[1] end
        end
    end)
    if best then return best end
    pcall(function()
        local cell = getCell(); if not cell then return end
        local cz = math.floor(char:getZ())
        local b
        if EmpireBases and EmpireBases.activeBase then b = EmpireBases.activeBase(char) end
        if not b and EmpireBases and EmpireBases.list then local l = EmpireBases.list(); b = l and l[1] end
        local x1, x2, y1, y2, z1, z2
        if b then
            x1, x2 = math.min(b.x1, b.x2), math.max(b.x1, b.x2)
            y1, y2 = math.min(b.y1, b.y2), math.max(b.y1, b.y2)
            local spread = (EmpireBases and EmpireBases.FLOOR_SPREAD) or 0
            z1, z2 = cz - spread, cz + spread
        else
            local cx, cy = math.floor(char:getX()), math.floor(char:getY())
            x1, x2, y1, y2, z1, z2 = cx - 8, cx + 8, cy - 8, cy + 8, cz, cz
        end
        for z = z1, z2 do
            for x = x1, x2 do
                for y = y1, y2 do
                    local sq = cell:getGridSquare(x, y, z)
                    if sq then
                        local objs = sq:getObjects()
                        for i = 0, objs:size() - 1 do
                            local c = nil
                            pcall(function() c = objs:get(i):getContainer() end)
                            if c then best = c; return end
                        end
                    end
                end
            end
        end
    end)
    return best
end

-- pick deposit container: prefer the group's designated storage area, else a base container near the survivor
local function depositContainerFor(ss, anchorChar, item)
    local dest
    pcall(function()
        local grp = ss and ss:getGroup()
        if grp then
            local d = grp:getBestGroupAreaContainerForItem(item)
            if instanceof(d, "IsoObject") and d:getContainer() then dest = d:getContainer() end
        end
    end)
    if not dest then dest = nearbyContainer(anchorChar) end
    return dest
end

local function processReturningRunners()
    local player = getSpecificPlayer(0)
    if not player then return end

    for name, settler in pairs(EmpireNPC.settlers) do
        if settler.onRun then
            settler.runReturnTick = (settler.runReturnTick or 3600) - RUN_CHECK
            if settler.runReturnTick <= 0 then
                settler.onRun = false
                settler.runReturnTick = nil

                local ss = findSurvivor(name)
                local anchor = (ss and ss:Get()) or player   -- deposit where the survivor is (base), not on the player
                local lootCount = ZombRand(3) + 2
                local lootNames = {}
                local toGround = false

                for i = 1, lootCount do
                    local item = instanceItem(getRandomLoot())
                    if item then
                        local cont = depositContainerFor(ss, anchor, item)
                        if cont then
                            cont:AddItem(item)
                        elseif ss and ss:Get() then
                            ss:Get():getInventory():AddItem(item)   -- survivor carries it; still never the player
                        else
                            local sq = anchor:getCurrentSquare()
                            if sq then sq:AddWorldInventoryItem(item, 0.5, 0.5, 0.0); toGround = true end
                        end
                        lootNames[#lootNames + 1] = item:getDisplayName()
                    end
                end

                pcall(function() if EmpireBaseCache and EmpireBaseCache.invalidate then EmpireBaseCache.invalidate() end end)

                local lootStr = table.concat(lootNames, ", ")
                local where = toGround and "dropped supplies at base" or "stocked the base with"
                HaloTextHelper.addText(player, name .. " " .. where .. ": " .. lootStr,
                    HaloTextHelper.getColorGreen())
                pcall(function()
                    local sayer = (ss and ss:Get()) or player
                    sayer:Say(name .. " is back from the supply run.")
                end)
                EmpireNPC.saveData()
            end
        end
    end
end

local function onTick()
    runTick = runTick + 1
    if runTick < RUN_CHECK then return end
    runTick = 0
    pcall(processReturningRunners)
end

Events.OnTick.Add(onTick)
print("[EmpireNPC] Supply Run Handler v2 loaded (loot -> base storage, never the player).")
