-- EmpireQoL :: 45_MechanicFromBase.lua -- the mechanic's quartermaster
-- Vehicle mechanics reads ONLY the player inventory (no container chokepoint like the
-- craft/build panels), so illusion-free base visibility is impossible there. Instead:
-- when you right-click a part in the mechanics window, the quartermaster PHYSICALLY
-- hands you what that part needs BEFORE vanilla builds the menu -- the replacement
-- part itself plus the install/uninstall tools -- pulled from nearby base storage
-- (same source as CraftFromBase: registry cache, else proximity scan). Vanilla then
-- sees them in your inventory and enables its options; consume works untouched.
-- Leftover tools go back on the shelves with the next Numpad3 -- that's the sorter's job.

-- fixing scripts sometimes name items without a module ("Screws"): try as-is, then Base.
local function typeVariants(ft)
    if ft:find("%.", 1, false) then return { ft } end
    return { "Base." .. ft, ft }
end

local function firstFromStorage(fullType)
    local conts = nil
    pcall(function() conts = EmpireQoL_BaseContainers(nil) end)
    if not conts then return nil, nil end
    for _, v in ipairs(typeVariants(fullType)) do
        for _, c in ipairs(conts) do
            local it = nil
            pcall(function() it = c:getFirstTypeRecurse(v) end)
            if it then
                local broken = false
                pcall(function() broken = it:isBroken() end)
                if not broken then return it, c end
            end
        end
    end
    return nil, nil
end

local function countTypeInInv(inv, fullType)
    local n = 0
    for _, v in ipairs(typeVariants(fullType)) do
        local c = 0
        pcall(function() c = inv:getCountTypeRecurse(v) or 0 end)
        if c > n then n = c end
    end
    return n
end

local function firstTagFromStorage(tag)
    local conts = nil
    pcall(function() conts = EmpireQoL_BaseContainers(nil) end)
    if not conts then return nil, nil end
    local pred = function(it2)
        local ok = true
        pcall(function() ok = not it2:isBroken() end)
        return ok
    end
    for _, c in ipairs(conts) do
        local it = nil
        pcall(function() it = c:getFirstTagEvalRecurse(tag, pred) end)
        if it then return it, c end
    end
    return nil, nil
end

local function moveToPlayer(it, from, playerInv, fetched)
    local ok = pcall(function() from:Remove(it); playerInv:addItem(it) end)
    if ok then
        local nm = "item"
        pcall(function() nm = it:getDisplayName() end)
        fetched[#fetched+1] = nm
    end
    return ok
end

-- one entry per token: "Base.Jack" (full type) or "Tag.JackTool" (tag)
local function fetchToken(token, playerInv, fetched)
    if not token or token == "" then return end
    token = token:gsub("^%s+", ""):gsub("%s+$", "")
    if token == "" then return end
    if token:sub(1, 4) == "Tag." then
        local tag = token:sub(5)
        local have = nil
        pcall(function() have = playerInv:getFirstTagEvalRecurse(tag, function() return true end) end)
        if have then return end
        local it, from = firstTagFromStorage(tag)
        if it then moveToPlayer(it, from, playerInv, fetched) end
    else
        local have = nil
        pcall(function() have = playerInv:getFirstTypeRecurse(token) end)
        if have then return end
        local it, from = firstFromStorage(token)
        if it then moveToPlayer(it, from, playerInv, fetched) end
    end
end

local function fetchForPart(playerObj, part)
    if not playerObj or not part then return end
    local playerInv = playerObj:getInventory()
    local fetched = {}
    -- telemetry: prove whether the storage source is live at fetch time
    pcall(function()
        local src = EmpireQoL_BaseContainers(playerObj)
        print("[EmpireQoL] MechanicFromBase: storage source = " .. tostring(src and #src or 0) .. " containers")
    end)
    -- 1) the replacement part item itself (first acceptable type found in storage),
    --    only when the slot is empty (installing) and you don't already carry one
    pcall(function()
        local types = part:getItemType()
        if types and not types:isEmpty() and not part:getInventoryItem() then
            local carrying = false
            for i = 0, types:size() - 1 do
                local ft = types:get(i)
                local have = nil
                pcall(function() have = playerInv:getFirstTypeRecurse(ft) end)
                if have then carrying = true; break end
            end
            if not carrying then
                for i = 0, types:size() - 1 do
                    local it, from = firstFromStorage(types:get(i))
                    if it then moveToPlayer(it, from, playerInv, fetched); break end
                end
            end
        end
    end)
    -- 2) tools from the part's install AND uninstall tables ("Base.Jack;Tag.Wrench;...")
    for _, tbl in ipairs({ "install", "uninstall" }) do
        pcall(function()
            local t = part:getTable(tbl)
            if t and t.tools and type(t.tools) == "string" then
                for token in string.gmatch(t.tools, "[^;]+") do
                    fetchToken(token, playerInv, fetched)
                end
            end
        end)
    end
    if #fetched > 0 then
        pcall(function()
            HaloTextHelper.addTextWithArrow(playerObj, "Quartermaster: " .. table.concat(fetched, ", "), "[br/]", false, HaloTextHelper.getColorGreen())
        end)
        print("[EmpireQoL] MechanicFromBase fetched: " .. table.concat(fetched, ", "))
    end
end

-- REPAIR MATERIALS, ON DEMAND. The Repair submenu greys its options against the
-- player's own inventory, so materials must be carried BEFORE the menu opens --
-- but pre-fetching every fixer for every fixing flooded the inventory. Instead:
-- an explicit "Stock repair materials" option per part fetches, on one click,
-- each fixing's global tool + fixers (correct B42 API: getNumberOfUse, fixer
-- types qualified by the fixing's own module).
local function fetchRepairMaterials(playerObj, part)
    if not playerObj or not part then return end
    local playerInv = playerObj:getInventory()
    local fetched = {}
    pcall(function()
        local invItem = part:getInventoryItem()
        if not invItem then return end
        local fixingList = FixingManager.getFixes(invItem)
        if not fixingList or fixingList:isEmpty() then return end
        for i = 0, fixingList:size() - 1 do
            local fixing = fixingList:get(i)
            local moduleName = nil
            pcall(function() moduleName = fixing:getModule():getName() end)
            pcall(function()
                local gi = fixing:getGlobalItem()
                if gi then
                    local gt = nil
                    pcall(function() gt = gi:getFixerName() end)
                    if gt and gt ~= "" then fetchToken(gt, playerInv, fetched) end
                end
            end)
            local fixers = nil
            pcall(function() fixers = fixing:getFixers() end)
            if fixers then
                for j = 0, fixers:size() - 1 do
                    local fixer = fixers:get(j)
                    local ft, cnt = nil, 1
                    pcall(function() ft = fixer:getFixerName() end)
                    pcall(function() if fixer.getNumberOfUse then cnt = fixer:getNumberOfUse() or 1 end end)
                    if ft and ft ~= "" then
                        if moduleName and not ft:find("%.", 1, false) then ft = moduleName .. "." .. ft end
                        if cnt > 4 then cnt = 4 end
                        while countTypeInInv(playerInv, ft) < cnt do
                            local it2, from2 = firstFromStorage(ft)
                            if not it2 then break end
                            if not moveToPlayer(it2, from2, playerInv, fetched) then break end
                        end
                    end
                end
            end
        end
    end)
    if #fetched > 0 then
        pcall(function()
            HaloTextHelper.addTextWithArrow(playerObj, "Quartermaster: " .. table.concat(fetched, ", "), "[br/]", false, HaloTextHelper.getColorGreen())
        end)
        print("[EmpireQoL] MechanicFromBase repair stock: " .. table.concat(fetched, ", "))
    else
        print("[EmpireQoL] MechanicFromBase repair stock: nothing missing or nothing in base")
        pcall(function()
            HaloTextHelper.addTextWithArrow(playerObj, "Quartermaster: nothing to fetch", "[br/]", false, HaloTextHelper.getColorWhite())
        end)
    end
end

-- INSTALL ONE TICK LATE: AutoMechanics (active in this save) touches the same
-- mechanics UI. Installing after everyone's OnGameStart means we wrap whatever won.
local function installMechShim()
    if not (ISVehicleMechanics and type(ISVehicleMechanics.doPartContextMenu) == "function") then
        print("[EmpireQoL] MechanicFromBase: ISVehicleMechanics:doPartContextMenu not found -- skipped")
        return
    end
    local orig = ISVehicleMechanics.doPartContextMenu
    ISVehicleMechanics.doPartContextMenu = function(self, part, x, y)
        local pid = "?"
        pcall(function() pid = part:getId() end)
        print("[EmpireQoL] MechanicFromBase: part right-click fired (" .. tostring(pid) .. ")")
        pcall(function()
            local playerObj = getSpecificPlayer(self.playerNum) or self.chr
            fetchForPart(playerObj, part)
        end)
        local r = orig(self, part, x, y)
        -- inject "Stock repair materials" when this part has any fixing recipes
        pcall(function()
            local playerObj = getSpecificPlayer(self.playerNum) or self.chr
            local invItem = part:getInventoryItem()
            if playerObj and invItem and self.context then
                local fixingList = FixingManager.getFixes(invItem)
                if fixingList and not fixingList:isEmpty() then
                    self.context:addOption("Empire: Stock repair materials", playerObj, fetchRepairMaterials, part)
                end
            end
        end)
        return r
    end
    -- BELT: when a specific repair IS clickable, top up that exact fixing from
    -- base before the action validates (covers a global tool sitting in base).
    if ISInventoryPaneContextMenu and type(ISInventoryPaneContextMenu.onFix) == "function" then
        local prevFix = ISInventoryPaneContextMenu.onFix
        ISInventoryPaneContextMenu.onFix = function(brokenObject, player, fixingNum, fixerNum, vehiclePart, ...)
            pcall(function()
                if vehiclePart then
                    local playerObj = getSpecificPlayer(player)
                    if playerObj then fetchRepairMaterials(playerObj, vehiclePart) end
                end
            end)
            return prevFix(brokenObject, player, fixingNum, fixerNum, vehiclePart, ...)
        end
        print("[EmpireQoL] MechanicFromBase: onFix belt armed")
    end
    print("[EmpireQoL] MechanicFromBase v3 active: right-click = part + tools only; repair materials via explicit menu option")
end

-- ATA / tsarslib TUNING window: it keeps its own container list (containerListLua,
-- inventory + open loot windows only). Append base storage after its own gather, so
-- HasAllRequiredItems and the ingredient panel see the whole base. Same source,
-- same dedup, prints what it added.
local _tuneNote = 0
local function installTuningShim()
    if not (ISVehicleTuning2 and type(ISVehicleTuning2.getContainers) == "function") then
        print("[EmpireQoL] TuningFromBase: ISVehicleTuning2 not present -- skipped")
        return
    end
    local orig = ISVehicleTuning2.getContainers
    ISVehicleTuning2.getContainers = function(self, ...)
        local r = orig(self, ...)
        pcall(function()
            if not self.containerListLua then return end
            local extra = EmpireQoL_BaseContainers(self.character)
            if not extra then
                local nowT = getTimestampMs()
                if nowT - _tuneNote > 10000 then
                    _tuneNote = nowT
                    print("[EmpireQoL] TuningFromBase: storage source = 0 containers")
                end
                return
            end
            local seen, added = {}, 0
            for _, c in ipairs(self.containerListLua) do seen[c] = true end
            for _, c in ipairs(extra) do
                if c and not seen[c] then
                    self.containerListLua[#self.containerListLua + 1] = c
                    seen[c] = true
                    added = added + 1
                end
            end
            local nowT = getTimestampMs()
            if nowT - _tuneNote > 10000 then
                _tuneNote = nowT
                print("[EmpireQoL] TuningFromBase: +" .. added .. " storage containers visible to tuning window")
            end
        end)
        return r
    end
    print("[EmpireQoL] TuningFromBase active: ATA tuning window sees base storage")
end

-- TUNING QUARTERMASTER: the window counts materials against base storage (shim
-- above), but onInstallPart fetches through ISInventoryTransferAction, which
-- range-validates the source container -- far shelves fail SILENTLY and the
-- install starves. So on install click, BEFORE the mod's own transfer pass,
-- instant-pull the recipe's use+tools items (fullType or tag match) from base
-- storage into the player. The mod's transferItems then finds them already on
-- the player and skips its transfers.
local function installTuningQuartermaster()
    if not (ISVehicleTuning2 and type(ISVehicleTuning2.onInstallPart) == "function") then
        print("[EmpireQoL] TuningQM: ISVehicleTuning2.onInstallPart not found -- skipped")
        return
    end
    local function tagOf(itemTag)
        local t = nil
        if itemTag then pcall(function() t = ItemTag.get(ResourceLocation.of(itemTag)) end) end
        return t
    end
    local function pullList(player, list, fetched)
        if not list then return end
        local inv = player:getInventory()
        local src = EmpireQoL_BaseContainers(player)
        if not src or #src == 0 then return end
        for _, req in pairs(list) do
            local fullType, need = req.fullType, req.count or 1
            local tagObj = tagOf(req.itemTag)
            local have = 0
            if fullType then pcall(function() have = inv:getAllTypeRecurse(fullType):size() end) end
            if have == 0 and tagObj then pcall(function() have = inv:getAllTag(tagObj):size() end) end
            local missing = need - have
            while missing > 0 do
                local got, from = nil, nil
                for _, c in ipairs(src) do
                    pcall(function()
                        local items = c:getItems()
                        for i = 0, items:size() - 1 do
                            local it = items:get(i)
                            if it then
                                local ok = false
                                if fullType then pcall(function() ok = it:getFullType() == fullType end) end
                                if not ok and tagObj then pcall(function() ok = it:hasTag(tagObj) end) end
                                if ok then got = it; from = c; break end
                            end
                        end
                    end)
                    if got then break end
                end
                if not got then break end
                local ok2 = pcall(function() from:Remove(got); inv:addItem(got) end)
                if not ok2 then break end
                local nm = fullType or req.itemTag or "?"
                pcall(function() nm = got:getDisplayName() end)
                fetched[#fetched + 1] = nm
                missing = missing - 1
            end
        end
    end
    local prev = ISVehicleTuning2.onInstallPart
    ISVehicleTuning2.onInstallPart = function(self, button, ...)
        pcall(function()
            print("[EmpireQoL] TuningQM: install click received")
            local player = self.character
            local box = self.getRecipeListBox and self:getRecipeListBox()
            local RecipeItem = box and box.items and box.items[box.selected] and box.items[box.selected].item
            if not RecipeItem then
                print("[EmpireQoL] TuningQM: selected recipe did not resolve (listbox state) -- fetch skipped")
            else
                local valid = nil
                pcall(function() valid = self:IsRecipeValid(RecipeItem) end)
                print("[EmpireQoL] TuningQM: recipe '" .. tostring(RecipeItem.name or RecipeItem.partName or "?")
                    .. "' type=" .. tostring(RecipeItem.type)
                    .. " IsRecipeValid=" .. tostring(valid)
                    .. (RecipeItem.error and (" | error: " .. tostring(RecipeItem.error)) or ""))
            end
            if player and RecipeItem then
                local fetched = {}
                pullList(player, RecipeItem.use, fetched)
                pullList(player, RecipeItem.tools, fetched)
                if #fetched > 0 then
                    pcall(function()
                        HaloTextHelper.addTextWithArrow(player, "Quartermaster: " .. table.concat(fetched, ", "), "[br/]", true, HaloTextHelper.getColorGreen())
                    end)
                    print("[EmpireQoL] TuningQM: quartermaster fetched " .. #fetched .. " item(s) for tuning install")
                    pcall(function() if EmpireBaseCache and EmpireBaseCache.invalidate then EmpireBaseCache.invalidate() end end)
                else
                    print("[EmpireQoL] TuningQM: install click, nothing to fetch (already carried or not in base)")
                end
            end
        end)
        return prev(self, button, ...)
    end
    print("[EmpireQoL] TuningQM: install-click quartermaster armed (ISVehicleTuning2.onInstallPart)")
end

Events.OnGameStart.Add(function()
    local installed = false
    local function install()
        if installed then return end
        installed = true
        Events.OnTick.Remove(install)
        installMechShim()
        installTuningShim()
        installTuningQuartermaster()
    end
    Events.OnTick.Add(install)
end)
