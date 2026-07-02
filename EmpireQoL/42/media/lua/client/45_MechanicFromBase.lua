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
    -- 3) REPAIR ("increase part health") materials: the Repair submenu is built from
    --    the Fixing system -- FixingManager.getFixes(partItem) -> fixings -> fixers.
    --    Fetch each fixer item (up to its required count, clamped) plus the fixing's
    --    global tool (e.g. blowtorch) so the repair options light up.
    pcall(function()
        local invItem = part:getInventoryItem()
        if not invItem then return end
        local fixingList = FixingManager.getFixes(invItem)
        if not fixingList or fixingList:isEmpty() then return end
        for i = 0, fixingList:size() - 1 do
            local fixing = fixingList:get(i)
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
                    pcall(function() cnt = fixer:getNumberOfItems() or 1 end)
                    if ft and ft ~= "" then
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
        print("[EmpireQoL] MechanicFromBase fetched: " .. table.concat(fetched, ", "))
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
        return orig(self, part, x, y)
    end
    print("[EmpireQoL] MechanicFromBase active (late-installed): right-click a part -> quartermaster hands you part + tools")
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

Events.OnGameStart.Add(function()
    local installed = false
    local function install()
        if installed then return end
        installed = true
        Events.OnTick.Remove(install)
        installMechShim()
        installTuningShim()
    end
    Events.OnTick.Add(install)
end)
