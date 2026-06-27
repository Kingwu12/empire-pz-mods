-- Empire QoL :: 39_TopOffMags.lua
-- Downtime one-click: fill every empty/partial magazine in your inventory from your
-- loose rounds. Combat reload stays 100% vanilla (the tension) -- this only kills the
-- click-grind of loading mags at base.
--
-- SAFE BY DESIGN: it never moves/edits ammo itself. It just queues the GAME'S OWN
-- ISLoadBulletsInMagazine action per mag (the same one vanilla's right-click uses),
-- so rounds are consumed by engine logic -- no dupe, no loss. A per-caliber pool is
-- tracked so two mags of the same caliber never get promised the same rounds.
--
-- Scope: your main inventory + any bag carried INSIDE it (getItemCountRecurse). Worn
-- backpacks / base storage aren't counted yet -- pull that ammo onto you first, or ask
-- to extend it to nearby containers.

local TOPOFF_KEY = Keyboard.KEY_NUMPAD8   -- Numpad 8 = top off all mags (NumLock ON)

local function isMagazine(it)
    local ok = false
    pcall(function()
        if it and it.getMaxAmmo and it:getMaxAmmo() and it:getMaxAmmo() > 0
           and it.getAmmoType and it:getAmmoType() then
            local isGun = false
            pcall(function() isGun = instanceof(it, "HandWeapon") end)
            ok = not isGun
        end
    end)
    return ok
end

local function collectMags(inv, out, seen, depth)
    if not inv or depth > 4 then return end
    local items = nil; pcall(function() items = inv:getItems() end)
    if not items then return end
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if it and not seen[it] then
            seen[it] = true
            if isMagazine(it) then
                local cur, mx = 0, 0
                pcall(function() cur = it:getCurrentAmmoCount() end)
                pcall(function() mx = it:getMaxAmmo() end)
                if mx > 0 and cur < mx then out[#out + 1] = it end
            end
            if instanceof(it, "InventoryContainer") then
                local sub = nil; pcall(function() sub = it:getInventory() end)
                if sub then collectMags(sub, out, seen, depth + 1) end
            end
        end
    end
end

local function topOff(player)
    if not player then player = getSpecificPlayer(0) end
    if not player then return end
    local inv = player:getInventory()
    if not inv then return end

    local mags, seen = {}, {}
    collectMags(inv, mags, seen, 0)
    if #mags == 0 then
        HaloTextHelper.addTextWithArrow(player, "No empty mags on you", "[br/]", false, HaloTextHelper.getColorWhite())
        return
    end

    local pool = {}            -- itemKey -> remaining loose rounds available
    local queued, filled = 0, 0
    for _, mag in ipairs(mags) do
        local cur, mx = 0, 0
        pcall(function() cur = mag:getCurrentAmmoCount() end)
        pcall(function() mx = mag:getMaxAmmo() end)
        local space = mx - cur
        if space > 0 then
            local itemKey = nil
            pcall(function() itemKey = mag:getAmmoType():getItemKey() end)
            if itemKey then
                if pool[itemKey] == nil then
                    local c = 0
                    pcall(function() c = inv:getItemCountRecurse(itemKey) end)
                    pool[itemKey] = c
                end
                local n = math.min(space, pool[itemKey])
                if n > 0 then
                    local ok = false
                    pcall(function()
                        ISTimedActionQueue.add(ISLoadBulletsInMagazine:new(player, mag, n))
                        ok = true
                    end)
                    if ok then
                        pool[itemKey] = pool[itemKey] - n
                        queued = queued + 1
                        filled = filled + n
                    end
                end
            end
        end
    end

    if queued == 0 then
        HaloTextHelper.addTextWithArrow(player, "No loose rounds on you to fill mags", "[br/]", false, HaloTextHelper.getColorRed())
        player:Say("No loose rounds on me to top off mags.")
    else
        HaloTextHelper.addTextWithArrow(player, "Topping off " .. queued .. " mag(s) - " .. filled .. " rounds", "[br/]", false, HaloTextHelper.getColorGreen())
        player:Say("Topping off " .. queued .. " magazines.")
    end
end

-- ---- triggers: Numpad 8, plus a right-click option on guns/mags ----
Events.OnKeyPressed.Add(function(key)
    if key == TOPOFF_KEY then pcall(topOff) end
end)

Events.OnFillInventoryObjectContextMenu.Add(function(player, context, items)
    local playerObj = player
    if type(player) == "number" then playerObj = getSpecificPlayer(player) end
    if not playerObj then return end
    local actual = nil
    pcall(function() actual = ISInventoryPane.getActualItems(items) end)
    local relevant = false
    if actual then
        for _, it in ipairs(actual) do
            local ok = false
            pcall(function() ok = isMagazine(it) or (instanceof(it, "HandWeapon") and it:isRanged()) end)
            if ok then relevant = true; break end
        end
    end
    if relevant then
        context:addOption("Top off all my mags (Numpad 8)", playerObj, function() pcall(function() topOff(playerObj) end) end)
    end
end)

print("[EmpireQoL] Top Off Mags loaded. Numpad 8 (or right-click a gun/mag) fills all your mags from loose rounds. Combat reload stays vanilla.")
