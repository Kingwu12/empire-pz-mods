-- EmpireQoL :: 47_QuickRepair.lua -- one-click vehicle repair from base stock
-- Right-click a vehicle at base -> "Empire: Quick repair from base".
-- For every damaged repairable part: score every valid fixer by BASE STOCK and
-- pick the most plentiful one (plentiful = cheap in the base economy), but only
-- if using it leaves at least RESERVE units on the shelves -- a quick repair
-- must never drain the last of anything. Fetch exactly what the chosen fix
-- needs (fixers + the fixing's global tool), then queue the vanilla fix action
-- with a path-to-part in front. One fix per part per run; run it again for
-- another pass. Skips are reported with reasons.

local RESERVE = 4          -- never let base stock of a material drop below this
local COND_THRESHOLD = 96  -- only bother with parts below this condition

local function qualify(ft, moduleName)
    if not ft or ft == "" then return nil end
    if ft:find("%.", 1, false) then return ft end
    return (moduleName or "Base") .. "." .. ft
end

local function baseCount(ft)
    local total = 0
    pcall(function()
        local conts = EmpireQoL_BaseContainers(nil)
        if not conts then return end
        for _, c in ipairs(conts) do
            local n = 0
            pcall(function() n = c:getCountTypeRecurse(ft) or 0 end)
            total = total + n
        end
    end)
    return total
end

local function invCount(inv, ft)
    local n = 0
    pcall(function() n = inv:getCountTypeRecurse(ft) or 0 end)
    return n
end

local function pullFromBase(playerInv, ft, need, fetched)
    while invCount(playerInv, ft) < need do
        local got, from = nil, nil
        pcall(function()
            local conts = EmpireQoL_BaseContainers(nil)
            if not conts then return end
            for _, c in ipairs(conts) do
                local it = c:getFirstTypeRecurse(ft)
                if it then got = it; from = c; break end
            end
        end)
        if not got then return false end
        local ok = pcall(function() from:Remove(got); playerInv:addItem(got) end)
        if not ok then return false end
        local nm = ft
        pcall(function() nm = got:getDisplayName() end)
        fetched[#fetched + 1] = nm
    end
    return true
end

local function quickRepair(playerObj, vehicle)
    if not playerObj or not vehicle then return end
    local playerInv = playerObj:getInventory()
    local fetched = {}
    local repaired, skipReserve, skipNoFix, skipGate = {}, 0, 0, 0
    local queued = false

    local partCount = 0
    pcall(function() partCount = vehicle:getPartCount() end)
    for p = 0, partCount - 1 do
        local part = nil
        pcall(function() part = vehicle:getPartByIndex(p) end)
        local invItem, cond, repairable = nil, 100, false
        if part then
            pcall(function() invItem = part:getInventoryItem() end)
            pcall(function() cond = part:getCondition() or 100 end)
            pcall(function() repairable = part:getScriptPart() and part:getScriptPart():isRepairMechanic() end)
        end
        if part and invItem and repairable and cond < COND_THRESHOLD then
            local fixingList = nil
            pcall(function() fixingList = FixingManager.getFixes(invItem) end)
            if fixingList and not fixingList:isEmpty() then
                -- pick (fixingNum, fixerNum) with the most plentiful base stock
                -- that clears the reserve rule
                local best = nil  -- {fixingNum, fixerNum, ft, need, stock, toolFt}
                for i = 0, fixingList:size() - 1 do
                    local fixing = fixingList:get(i)
                    local moduleName = nil
                    pcall(function() moduleName = fixing:getModule():getName() end)
                    local toolFt = nil
                    pcall(function()
                        local gi = fixing:getGlobalItem()
                        if gi then toolFt = qualify(gi:getFixerName(), moduleName) end
                    end)
                    -- a fixing whose global tool exists neither on us nor in base is dead
                    local toolOk = true
                    if toolFt then
                        toolOk = (invCount(playerInv, toolFt) > 0) or (baseCount(toolFt) > 0)
                    end
                    if toolOk then
                        local fixers = nil
                        pcall(function() fixers = fixing:getFixers() end)
                        if fixers then
                            for j = 0, fixers:size() - 1 do
                                local fixer = fixers:get(j)
                                local ft, need = nil, 1
                                pcall(function() ft = qualify(fixer:getFixerName(), moduleName) end)
                                pcall(function() if fixer.getNumberOfUse then need = fixer:getNumberOfUse() or 1 end end)
                                if ft then
                                    local carried = invCount(playerInv, ft)
                                    local stock = baseCount(ft)
                                    -- reserve rule counts what must LEAVE the base
                                    local fromBase = need - carried
                                    if fromBase < 0 then fromBase = 0 end
                                    if (carried + stock) >= need and (stock - fromBase) >= RESERVE then
                                        if (not best) or stock > best.stock then
                                            best = { fixingNum = i, fixerNum = j, ft = ft, need = need, stock = stock, toolFt = toolFt }
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
                if best then
                    local ok = pullFromBase(playerInv, best.ft, best.need, fetched)
                    if ok and best.toolFt and invCount(playerInv, best.toolFt) == 0 then
                        ok = pullFromBase(playerInv, best.toolFt, 1, fetched)
                    end
                    if ok then
                        -- mirror vanilla onFix's own gate before queueing
                        local items = nil
                        pcall(function()
                            local fixing = fixingList:get(best.fixingNum)
                            local fixer = fixing:getFixers():get(best.fixerNum)
                            items = fixing:getRequiredItems(playerObj, fixer, invItem)
                        end)
                        if items ~= nil then
                            pcall(function()
                                local area = part:getArea()
                                if area then
                                    ISTimedActionQueue.add(ISPathFindAction:pathToVehicleArea(playerObj, vehicle, area))
                                end
                                ISTimedActionQueue.add(ISFixVehiclePartAction:new(playerObj, part, best.fixingNum, best.fixerNum))
                                queued = true
                                local pid = "part"
                                pcall(function() pid = part:getId() end)
                                repaired[#repaired + 1] = pid .. " (" .. cond .. "%)"
                            end)
                        else
                            skipGate = skipGate + 1  -- skill or requirement gate said no
                        end
                    else
                        skipReserve = skipReserve + 1
                    end
                else
                    skipReserve = skipReserve + 1  -- nothing plentiful enough / reserve rule
                end
            else
                skipNoFix = skipNoFix + 1
            end
        end
    end

    print("[EmpireQoL] QuickRepair: queued=" .. #repaired
        .. " reserveOrStockSkips=" .. skipReserve
        .. " skillGateSkips=" .. skipGate
        .. " noFixRecipe=" .. skipNoFix
        .. (#fetched > 0 and (" | fetched: " .. table.concat(fetched, ", ")) or ""))
    if #repaired > 0 then
        pcall(function()
            HaloTextHelper.addTextWithArrow(playerObj, "Quick repair: " .. #repaired .. " part(s) queued", "[br/]", true, HaloTextHelper.getColorGreen())
        end)
        print("[EmpireQoL] QuickRepair parts: " .. table.concat(repaired, ", "))
    else
        pcall(function()
            HaloTextHelper.addTextWithArrow(playerObj, "Quick repair: nothing repairable (see console)", "[br/]", false, HaloTextHelper.getColorWhite())
        end)
    end
end

Events.OnFillWorldObjectContextMenu.Add(function(playerNum, context, worldobjects, test)
    if test then return end
    pcall(function()
        local player = getSpecificPlayer(playerNum)
        if not (player and ISVehicleMenu and ISVehicleMenu.getVehicleToInteractWith) then return end
        local veh = nil
        pcall(function() veh = ISVehicleMenu.getVehicleToInteractWith(player) end)
        if not veh then return end
        -- only offer where base storage is actually reachable
        local src = nil
        pcall(function() src = EmpireQoL_BaseContainers(player) end)
        if not src or #src == 0 then return end
        context:addOption("Empire: Quick repair from base", player, quickRepair, veh)
    end)
end)

print("[EmpireQoL] QuickRepair loaded: right-click vehicle -> repair every damaged part from base stock (most plentiful material, reserve " .. RESERVE .. " kept)")
