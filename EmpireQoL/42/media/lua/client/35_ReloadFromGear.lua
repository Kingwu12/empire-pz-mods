-- Empire QoL :: 35_ReloadFromGear.lua -- reload straight from your worn gear.
-- Vanilla reload only searches your MAIN pockets (getInventory():getItems() / FindAndReturn),
-- never recursing into worn backpacks, webbing or mag pouches -- so mags in your tactical rig
-- are invisible and you have to drag them to your main inventory by hand. There are several
-- reload paths (semi-auto / shotgun / revolver / magazine) and a Java "new reloading" mode,
-- so instead of rewriting each search we do ONE universal thing: the instant you hit reload,
-- pull the right magazine (and loose ammo) out of any worn container into your main inventory.
-- Whatever reload system is active then finds it normally. Moves are synchronous + dupe-safe
-- (Remove from the pouch, then add the SAME item object to main).

local function personalContainers(player)
    local out, seen = {}, {}
    local function addCont(c)
        if c and not seen[c] then seen[c] = true; out[#out + 1] = c end
    end
    local main = player:getInventory()
    addCont(main)
    -- container items sitting in your main inventory (held bags etc.)
    local items = main:getItems()
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if it and instanceof(it, "InventoryContainer") and it:getInventory() then
            addCont(it:getInventory())
        end
    end
    -- worn clothing/bags with containers: webbing, tactical pouches, backpack, holster...
    local worn = player:getWornItems()
    if worn then
        for i = 0, worn:size() - 1 do
            local wi = worn:get(i)
            local it = wi and wi:getItem()
            if it and it.getInventory and it:getInventory() then
                addCont(it:getInventory())
            end
        end
    end
    return out, main
end

-- Pull the needed magazine + loose ammo from worn gear into main inventory, synchronously.
local function sweepGearToInv(player)
    local w = player:getPrimaryHandItem()
    if not w or not instanceof(w, "HandWeapon") then return end
    local ranged = false
    pcall(function() ranged = w:isRanged() end)
    if not ranged then return end

    local magType, ammoType
    pcall(function() magType = w:getMagazineType() end)
    pcall(function() ammoType = w:getAmmoType() end)
    local hasMag = magType and magType ~= ""
    local hasAmmo = ammoType and ammoType ~= ""
    if not hasMag and not hasAmmo then return end

    local conts, main = personalContainers(player)
    local movedAny = false

    -- 1) mag-fed guns: move the FULLEST matching magazine from a pouch (one per reload)
    if hasMag then
        local bestMag, bestCont, bestAmmo = nil, nil, -1
        for _, c in ipairs(conts) do
            if c ~= main then
                local items = c:getItems()
                for i = 0, items:size() - 1 do
                    local it = items:get(i)
                    if it and it:getFullType() == magType then
                        local amt = 0
                        pcall(function() amt = it:getCurrentAmmoCount() end)
                        if amt > bestAmmo then bestAmmo = amt; bestMag = it; bestCont = c end
                    end
                end
            end
        end
        if bestMag and bestCont then
            bestCont:Remove(bestMag); main:addItem(bestMag); movedAny = true
        end
    end

    -- 2) loose ammo (easy mode + topping up mags): move matching rounds from pouches
    if hasAmmo then
        for _, c in ipairs(conts) do
            if c ~= main then
                local grab = {}
                local items = c:getItems()
                for i = 0, items:size() - 1 do
                    local it = items:get(i)
                    if it and it:getFullType() == ammoType then grab[#grab + 1] = it end
                end
                for _, it in ipairs(grab) do c:Remove(it); main:addItem(it); movedAny = true end
            end
        end
    end

    if movedAny then ISInventoryPage.dirtyUI() end
end

local function install()
    -- Trigger 1: the Reload key (works for both old and new reloading systems).
    Events.OnKeyPressed.Add(function(key)
        local reloadKey = nil
        pcall(function() reloadKey = getCore():getKey("ReloadWeapon") end)
        if reloadKey and key == reloadKey then
            local p = getSpecificPlayer(0)
            if p then pcall(function() sweepGearToInv(p) end) end
        end
    end)

    -- Trigger 2: reloading from the inventory UI (right-click weapon -> Reload), old system.
    if ISReloadManager and ISReloadManager.startReloadFromUi then
        local orig = ISReloadManager.startReloadFromUi
        function ISReloadManager:startReloadFromUi(item)
            local p = getSpecificPlayer(self.playerid or 0)
            if p then pcall(function() sweepGearToInv(p) end) end
            return orig(self, item)
        end
    end

    print("[EmpireQoL] Reload From Gear loaded. Reloading now pulls mags/ammo from your worn pouches automatically.")
end

Events.OnGameStart.Add(install)
