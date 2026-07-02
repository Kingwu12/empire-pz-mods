-- EmpireQoL :: 48_QuickReplace.lua -- one-click part replacement from base spares
-- Right-click vehicle -> "Empire: Quick replace from base spares".
-- Vanilla only lets you REPAIR parts that have fixing recipes; destroyed (0%)
-- and recipe-less parts are replace-only. This sweeps every part and, when a
-- better spare exists in base storage, swaps it in via the vanilla flows
-- (ISVehiclePartMenu.onUninstallPart / onInstallPart -- pathing, timing and
-- skill checks included). The worn part comes back to your inventory when the
-- action completes; the next sort files it to base -- total part count is
-- preserved, so no spare-count reserve is needed.
--
-- Replace policy per part:
--   missing part          -> install best spare
--   condition <= WRECKED  -> swap for best spare
--   condition <  UPGRADE  -> swap only if the spare beats it by >= MIN_GAIN
-- Skipped (named): wheels/tires/battery/gas tank (specialized vanilla flows:
-- jack, charge, siphon), parts gated by skill/recipe, parts with no spare.

local WRECKED  = 25   -- at or below: replace unconditionally if a spare exists
local UPGRADE  = 60   -- below this, consider an upgrade swap
local MIN_GAIN = 25   -- upgrade swap must improve condition by at least this

local SPECIAL = { "tire", "wheel", "battery", "gastank", "gas_tank" }
local function isSpecialPart(pid)
    local s = tostring(pid):lower()
    for _, k in ipairs(SPECIAL) do
        if s:find(k, 1, true) then return true end
    end
    return false
end

local function bestSpare(part, minCond)
    local best, bestCond, bestCont = nil, minCond, nil
    pcall(function()
        local types = part:getItemType()
        if not types or types:isEmpty() then return end
        local conts = EmpireQoL_BaseContainers(nil)
        if not conts then return end
        for t = 0, types:size() - 1 do
            local ft = types:get(t)
            for _, c in ipairs(conts) do
                pcall(function()
                    local list = c:getAllTypeRecurse(ft)
                    if list then
                        for i = 0, list:size() - 1 do
                            local it = list:get(i)
                            local cond = it:getCondition() or 0
                            if cond > bestCond then best, bestCond, bestCont = it, cond, c end
                        end
                    end
                end)
            end
        end
    end)
    return best, bestCond, bestCont
end

local function quickReplace(playerObj, vehicle)
    if not playerObj or not vehicle then return end
    local inv = playerObj:getInventory()
    local replaced, skips = {}, {}
    local function skip(pid, cond, why)
        skips[#skips + 1] = tostring(pid) .. " (" .. tostring(cond) .. "%): " .. why
    end

    local partCount = 0
    pcall(function() partCount = vehicle:getPartCount() end)
    for p = 0, partCount - 1 do
        local part = nil
        pcall(function() part = vehicle:getPartByIndex(p) end)
        if part then
            local pid = "part"
            pcall(function() pid = part:getId() end)
            local hasInstall = false
            pcall(function() hasInstall = part:getTable("install") ~= nil end)
            local invItem, cond = nil, nil
            pcall(function() invItem = part:getInventoryItem() end)
            pcall(function() if invItem then cond = part:getCondition() or 0 end end)

            local wants = false
            local minCond = 0
            if hasInstall and not isSpecialPart(pid) then
                if not invItem then
                    wants, minCond = true, 0
                elseif cond and cond <= WRECKED then
                    wants, minCond = true, cond
                elseif cond and cond < UPGRADE then
                    wants, minCond = true, cond + MIN_GAIN - 1
                end
            elseif isSpecialPart(pid) and ((not invItem) or (cond and cond <= WRECKED)) then
                skip(pid, cond or "missing", "specialized part (jack/charge/siphon flow) -- do manually")
            end

            if wants then
                local spare, spareCond, fromCont = bestSpare(part, minCond)
                if not spare then
                    if (not invItem) or (cond and cond <= WRECKED) then
                        skip(pid, cond or "missing", "no spare in base")
                    end
                else
                    -- gates BEFORE touching anything
                    local canIn, canOut = false, true
                    pcall(function() canIn = vehicle:canInstallPart(playerObj, part) end)
                    if invItem then
                        pcall(function() canOut = vehicle:canUninstallPart(playerObj, part) end)
                    end
                    if not (canIn and canOut) then
                        skip(pid, cond or "missing", "skill/recipe gate")
                    else
                        local ok = pcall(function() fromCont:Remove(spare); inv:addItem(spare) end)
                        if ok then
                            pcall(function()
                                if invItem then ISVehiclePartMenu.onUninstallPart(playerObj, part) end
                                ISVehiclePartMenu.onInstallPart(playerObj, part, spare)
                            end)
                            replaced[#replaced + 1] = tostring(pid) .. " " .. tostring(cond or "missing") .. "%->" .. tostring(spareCond) .. "%"
                        end
                    end
                end
            end
        end
    end

    print("[EmpireQoL] QuickReplace: queued=" .. #replaced
        .. (#replaced > 0 and (" | " .. table.concat(replaced, ", ")) or ""))
    if #skips > 0 then
        print("[EmpireQoL] QuickReplace skips: " .. table.concat(skips, " | "))
    end
    if #replaced > 0 then
        pcall(function()
            HaloTextHelper.addTextWithArrow(playerObj, "Quick replace: " .. #replaced .. " part(s) queued (worn parts ride back in your bag)", "[br/]", true, HaloTextHelper.getColorGreen())
        end)
    else
        pcall(function()
            HaloTextHelper.addTextWithArrow(playerObj, "Quick replace: nothing to swap (see console)", "[br/]", false, HaloTextHelper.getColorWhite())
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
        local src = nil
        pcall(function() src = EmpireQoL_BaseContainers(player) end)
        if not src or #src == 0 then return end
        context:addOption("Empire: Quick replace from base spares", player, quickReplace, veh)
    end)
end)

print("[EmpireQoL] QuickReplace loaded: right-click vehicle -> swap wrecked/missing parts for the best spares in base")
