-- Empire QoL - Corpse Vacuum (F1)
-- One key: instantly pull every worthwhile item off all corpses within RANGE into your
-- WORN BACKPACK, VALUE-FIRST: guns/ammo/mags/parts -> meds/food -> melee/tools -> junk.
-- Skips clothing (the bulky junk). Loot goes into your bag, NEVER your body inventory --
-- so it never weighs your character down. No animation per item -- direct transfers, same
-- trick the F9 sort uses -- so a cleared horde is looted in one press. Then F9 sorts it.

-- ===== CONFIG =====
local RANGE      = 7      -- tiles each direction to sweep for corpses
local GRAB_CLOTHING = false  -- false = leave the rags; true = take clothing too (for sheets)
local MAX_ITEMS  = 250    -- safety cap per press
-- ==================

-- Items worth grabbing. Default: everything EXCEPT clothing/bags, weight permitting.
local SKIP_DISP = { Clothing=true, Accessory=true, Appearance=true }
local function wanted(it)
    local keep = true
    pcall(function()
        if instanceof(it, "InventoryContainer") then keep = false; return end  -- leave bags as bags
        if not GRAB_CLOTHING then
            if instanceof(it, "Clothing") then keep = false; return end
            local disp = it:getDisplayCategory()
            if disp and SKIP_DISP[disp] then keep = false; return end
        end
    end)
    return keep
end

-- Value tiers: lower number = grabbed first, so a full pack fills with the good stuff
-- and only leftover weight goes to junk. Rags are already skipped by wanted().
local function tierOf(it)
    local t = 99
    pcall(function()
        local disp = it:getDisplayCategory() or ""
        local typ  = it:getType() or ""
        -- Tier 1: guns, ammo, magazines, gun parts
        if instanceof(it, "Ammo") or disp == "Ammo" then t = 1; return end
        if typ:find("Magazine") or typ:find("Clip") then t = 1; return end
        if instanceof(it, "WeaponPart") then t = 1; return end
        if instanceof(it, "HandWeapon") and it:isRanged() then t = 1; return end
        -- Tier 2: meds, food, water
        if disp == "FirstAid" then t = 2; return end
        if instanceof(it, "Food") then t = 2; return end
        if it.isWaterSource and it:isWaterSource() then t = 2; return end
        -- Tier 3: melee weapons, tools, electronics
        if instanceof(it, "HandWeapon") then t = 3; return end
        if disp == "Tool" or disp == "ToolWeapon" then t = 3; return end
        if disp == "Electronics" or disp == "Communications" then t = 3; return end
        -- Tier 4 (default 99): everyday junk, taken last if weight remains
    end)
    return t
end

-- The bag we drop loot into: the worn backpack first, then any other worn bag (roomiest).
-- We deliberately NEVER use the main (body) inventory -- loot there just slows you down.
-- No bag = warn and grab nothing.
local function getBagContainer(player)
    local cont = nil
    -- 1) the backpack on your back
    pcall(function()
        local back = player:getClothingItem_Back()
        if back then cont = back:getInventory() end
    end)
    if cont then return cont end
    -- 2) any other worn bag, pick the roomiest
    pcall(function()
        local worn = player:getWornItems()
        if worn then
            local best, bestCap = nil, -1
            for i = 0, worn:size() - 1 do
                local it = nil
                pcall(function() it = worn:getItemByIndex(i) end)
                if it and instanceof(it, "InventoryContainer") then
                    local c = it:getInventory()
                    if c then
                        local cap = c:getCapacity() or 0
                        if cap > bestCap then best, bestCap = c, cap end
                    end
                end
            end
            cont = best
        end
    end)
    return cont
end

local function corpsesNear(player)
    local out = {}
    local cell = getCell()
    if not cell then return out end
    local z  = player:getZ()
    local cx = math.floor(player:getX())
    local cy = math.floor(player:getY())
    for x = cx - RANGE, cx + RANGE do
        for y = cy - RANGE, cy + RANGE do
            local sq = cell:getGridSquare(x, y, z)
            if sq then
                -- corpses register as static moving objects (same path the loot panel reads)
                local sobs = sq:getStaticMovingObjects()
                for i = 0, sobs:size() - 1 do
                    local o = sobs:get(i)
                    if instanceof(o, "IsoDeadBody") then
                        local c = nil
                        pcall(function() c = o:getContainer() end)
                        if c then out[#out+1] = c end
                    end
                end
                -- belt and braces: square's single dead body, if not already caught
                local body = nil
                pcall(function() body = sq:getDeadBody() end)
                if body then
                    local c = nil
                    pcall(function() c = body:getContainer() end)
                    if c then out[#out+1] = c end
                end
            end
        end
    end
    return out
end

local function doVacuum()
    local player = getSpecificPlayer(0)
    if not player or player:isDead() then return end

    local s = player:getStats()
    if s:getNumChasingZombies() > 0 or s:getNumVeryCloseZombies() > 0 then
        HaloTextHelper.addTextWithArrow(player, "Not now - zombies on you", "[br/]", false, HaloTextHelper.getColorRed())
        return
    end

    local bag = getBagContainer(player)
    if not bag then
        HaloTextHelper.addTextWithArrow(player, "No backpack equipped - equip a bag to vacuum loot", "[br/]", false, HaloTextHelper.getColorRed())
        return
    end

    local conts = corpsesNear(player)
    if #conts == 0 then
        HaloTextHelper.addTextWithArrow(player, "No corpses in reach", "[br/]", false, HaloTextHelper.getColorWhite())
        return
    end

    -- gather every worthwhile item across all corpses, tag each with its value tier
    local pool, seen = {}, {}
    for _, c in ipairs(conts) do
        if not seen[c] then
            seen[c] = true
            local items = nil
            pcall(function() items = c:getItems() end)
            if items then
                for i = 0, items:size() - 1 do
                    local it = items:get(i)
                    if wanted(it) then pool[#pool+1] = { it = it, c = c, tier = tierOf(it) } end
                end
            end
        end
    end

    -- value-first: guns/ammo/meds/food go in before junk
    table.sort(pool, function(a, b) return a.tier < b.tier end)

    local grabbed, full = 0, false
    for _, e in ipairs(pool) do
        if grabbed >= MAX_ITEMS then break end
        local fits = false
        pcall(function() fits = bag:hasRoomFor(player, e.it) end)
        if fits then
            local ok = pcall(function() bag:addItem(e.it); e.c:Remove(e.it) end)
            if ok then grabbed = grabbed + 1 end
        else
            full = true  -- keep going: a lighter high-value item may still fit
        end
    end

    if grabbed > 0 then
        HaloTextHelper.addTextWithArrow(player, "Looted " .. grabbed .. " items into your pack from " .. #conts .. " corpses", "[br/]", false, HaloTextHelper.getColorGreen())
        player:Say("Stripped " .. grabbed .. " bodies' worth. F9 to sort it.")
        if full then
            HaloTextHelper.addTextWithArrow(player, "Backpack full - empty it and F1 again", "[br/]", false, HaloTextHelper.getColorRed())
        end
    elseif full then
        HaloTextHelper.addTextWithArrow(player, "Backpack full - nothing grabbed", "[br/]", false, HaloTextHelper.getColorRed())
    else
        HaloTextHelper.addTextWithArrow(player, "Nothing worth taking on these corpses", "[br/]", false, HaloTextHelper.getColorWhite())
    end
end

local function onKeyPressed(key)
    if key == Keyboard.KEY_NUMPAD7 then pcall(doVacuum) end
end
Events.OnKeyPressed.Add(onKeyPressed)

print("[EmpireQoL] Corpse Vacuum loaded (value-first, into backpack). F1 = strip nearby corpses (range " .. RANGE .. ", clothing " .. tostring(GRAB_CLOTHING) .. ").")
