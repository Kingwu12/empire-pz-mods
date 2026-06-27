-- Empire NPC - Fallen Recovery (closes the supply loop)
-- Survivors equip from your real base armory (6_Garrison Quartermaster), so without this every
-- death would bleed your finite Brita stockpile. When a managed survivor dies, this returns
-- their whole kit -- gun, magazine, ammo, armour, and anything they were carrying -- back into
-- your nearest base storage container. Net result: the SAME guns cycle armory -> survivor ->
-- (death) -> armory, so you don't run out. Caveat: if they die OUT in the field away from base,
-- there's no container to return to, so the kit stays on their corpse for you to loot (vanilla).

local RECOVER_RADIUS = 15

local function nearestBaseContainer(char)
    local cell = getCell(); if not cell then return nil end
    local px, py, pz = math.floor(char:getX()), math.floor(char:getY()), math.floor(char:getZ())
    for r = 0, RECOVER_RADIUS do
        for dx = -r, r do
            for dy = -r, r do
                local sq = cell:getGridSquare(px + dx, py + dy, pz)
                if sq then
                    local objs = sq:getObjects()
                    for i = 0, (objs and objs:size() or 0) - 1 do
                        local cont = nil
                        pcall(function() cont = objs:get(i):getContainer() end)
                        if cont then return cont end
                    end
                end
            end
        end
    end
    return nil
end

local function onDeath(character)
    if not character or character == getSpecificPlayer(0) then return end
    local isNPC = false
    pcall(function() isNPC = instanceof(character, "IsoPlayer") and not character:isLocalPlayer() end)
    if not isNPC then return end

    local dest = nearestBaseContainer(character)
    if not dest then return end   -- died in the field: kit stays on the corpse to loot

    local moved = 0
    pcall(function()
        local inv = character:getInventory()
        local items = inv:getItems()
        local list = {}
        for i = 0, items:size() - 1 do list[#list + 1] = items:get(i) end  -- snapshot first
        for _, it in ipairs(list) do
            pcall(function()
                inv:Remove(it)
                dest:AddItem(it)
                moved = moved + 1
            end)
        end
    end)

    if moved > 0 then
        local p = getSpecificPlayer(0)
        if p then pcall(function()
            HaloTextHelper.addText(p, "Recovered " .. moved .. " items from a fallen survivor", HaloTextHelper.getColorGreen())
        end) end
        print("[EmpireRecovery] returned " .. moved .. " items from a fallen survivor to base storage.")
    end
end

Events.OnCharacterDeath.Add(function(ch) pcall(onDeath, ch) end)
print("[EmpireNPC] Fallen Recovery loaded. Dead survivors' kit returns to base storage (closed supply loop).")
