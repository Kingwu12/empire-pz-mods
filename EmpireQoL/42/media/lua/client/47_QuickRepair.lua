-- EmpireQoL :: 47_QuickRepair.lua -- one-click vehicle repair from base stock
-- Right-click a vehicle at base -> "Empire: Quick repair from base".
-- For every damaged repairable part: score every valid fixer by PREDICTED
-- CONDITION GAIN (FixingManager.getCondRepaired -- the exact number the vanilla
-- tooltip shows as "Potential repair"), so Fix-a-Flat beats duct tape on a tire
-- automatically. Ties break toward the most plentiful base stock, but only
-- if using it leaves at least RESERVE units on the shelves -- a quick repair
-- must never drain the last of anything. Fetch exactly what the chosen fix
-- needs (fixers + the fixing's global tool), then queue the vanilla fix action
-- with a path-to-part in front. One fix per part per run; run it again for
-- another pass. Skips are reported with reasons.
--
-- v3: Vehicle Repair Overhaul integration. VRO runs a PARALLEL repair system
-- (VRO.Recipes + VRO.DoFixAction) that never touches FixingManager, and it
-- flips isRepairMechanic lazily only when a part's menu is opened -- so most
-- VRO-fixable parts were invisible here. Now: parts vanilla can't fix are
-- matched against VRO recipes, materials are pre-fetched from base, and the
-- part's REAL context menu is built off-screen so the best enabled repair
-- option can be invoked programmatically -- the exact code path of a manual
-- click, zero reimplementation drift.

local RESERVE = 4          -- never let base stock of a material drop below this
local COND_THRESHOLD = 96  -- only bother with parts below this condition
local MIN_GAIN = 3         -- skip fixes predicted to restore less than this %

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

----------------------------------------------------------------
-- VRO integration helpers
----------------------------------------------------------------
local VROCore = nil
pcall(function() VROCore = require "VRO/Core" end)

local function vroExpandRequire(entry, out, seen)
    seen = seen or {}
    local t = type(entry)
    if t == "string" then
        if entry:sub(1, 1) == "@" then
            local key = entry:sub(2)
            if key ~= "" and not seen[key] and VROCore and type(VROCore.PartLists) == "table" then
                seen[key] = true
                local lst = VROCore.PartLists[key]
                if type(lst) == "table" then
                    for i = 1, #lst do out[lst[i]] = true end
                end
            end
        else
            out[entry] = true
        end
    elseif t == "table" then
        local key = entry.list or entry.requireList
        if type(key) == "string" then
            vroExpandRequire("@" .. key, out, seen)
        else
            for i = 1, #entry do vroExpandRequire(entry[i], out, seen) end
        end
    end
end

local function vroMatchedRecipes(ft, pid)
    local matched = {}
    if not (VROCore and type(VROCore.Recipes) == "table") then return matched end
    for _, rec in ipairs(VROCore.Recipes) do
        local set = {}
        pcall(function()
            if rec.require ~= nil then vroExpandRequire(rec.require, set) end
            if rec.requireLists ~= nil then
                if type(rec.requireLists) == "string" then
                    vroExpandRequire("@" .. rec.requireLists, set)
                elseif type(rec.requireLists) == "table" then
                    for i = 1, #rec.requireLists do vroExpandRequire("@" .. tostring(rec.requireLists[i]), set) end
                end
            end
        end)
        if (ft and set[ft]) or (pid and set[pid]) then matched[#matched + 1] = rec end
    end
    return matched
end

local function vroTagObj(tagName)
    local t = nil
    if tagName then
        pcall(function()
            local sName = tostring(tagName)
            if not sName:find(":", 1, true) then sName = "base:" .. sName end
            t = ItemTag.get(ResourceLocation.of(sName))
        end)
    end
    return t
end

local function vroPullByTag(playerInv, tagName, fetched)
    local tg = vroTagObj(tagName)
    if not tg then return false end
    local carried = nil
    pcall(function() carried = playerInv:getFirstTagRecurse(tg) end)
    if carried then return true end
    local got, from = nil, nil
    pcall(function()
        local conts = EmpireQoL_BaseContainers(nil)
        if not conts then return end
        for _, c in ipairs(conts) do
            local items = c:getItems()
            for i = 0, items:size() - 1 do
                local it = items:get(i)
                local ok = false
                pcall(function() ok = it:hasTag(tg) end)
                if ok then got = it; from = c; break end
            end
            if got then break end
        end
    end)
    if not got then return false end
    local ok2 = pcall(function() from:Remove(got); playerInv:addItem(got) end)
    if ok2 then
        local nm = tostring(tagName)
        pcall(function() nm = got:getDisplayName() end)
        fetched[#fetched + 1] = nm
    end
    return ok2
end

local function vroPullSpec(playerInv, spec, fetched)
    -- spec shapes: "Base.X" | { item=... } | { tag=... } | { tags={...} }
    if type(spec) == "string" then
        if invCount(playerInv, spec) == 0 then pullFromBase(playerInv, spec, 1, fetched) end
        return
    end
    if type(spec) ~= "table" then return end
    if spec.item then
        if invCount(playerInv, spec.item) == 0 then pullFromBase(playerInv, spec.item, 1, fetched) end
    elseif spec.tag then
        vroPullByTag(playerInv, spec.tag, fetched)
    elseif type(spec.tags) == "table" then
        for _, tg in ipairs(spec.tags) do
            if vroPullByTag(playerInv, tg, fetched) then break end
        end
    end
end

local function vroPrefetch(playerObj, playerInv, recipes, fetched)
    for _, rec in ipairs(recipes) do
        local gl = {}
        if rec.globalItem then gl[#gl + 1] = rec.globalItem end
        if type(rec.globalItems) == "table" then
            for _, g in ipairs(rec.globalItems) do gl[#gl + 1] = g end
        end
        for _, g in ipairs(gl) do vroPullSpec(playerInv, g, fetched) end
        if type(rec.equip) == "table" then
            for _, k in ipairs({ "primary", "secondary", "wear" }) do
                if rec.equip[k] then vroPullSpec(playerInv, rec.equip[k], fetched) end
            end
            if rec.equip.primaryTag then vroPullByTag(playerInv, rec.equip.primaryTag, fetched) end
            if rec.equip.secondaryTag then vroPullByTag(playerInv, rec.equip.secondaryTag, fetched) end
            if rec.equip.wearTag then vroPullByTag(playerInv, rec.equip.wearTag, fetched) end
        end
        if type(rec.fixers) == "table" then
            for _, fx in ipairs(rec.fixers) do
                local skillsOk = true
                if type(fx.skills) == "table" then
                    for perkName, lvl in pairs(fx.skills) do
                        local have = 0
                        pcall(function()
                            local perk = Perks.FromString(perkName)
                            if perk then have = playerObj:getPerkLevel(perk) end
                        end)
                        if have < lvl then skillsOk = false; break end
                    end
                end
                if skillsOk then
                    if fx.item then
                        -- uses live on drainables, so carrying uses-many ITEMS
                        -- always suffices; cap the haul at 4
                        local target = math.min(fx.uses or 1, 4)
                        while invCount(playerInv, fx.item) < target do
                            if baseCount(fx.item) - 1 < RESERVE then break end
                            if not pullFromBase(playerInv, fx.item, invCount(playerInv, fx.item) + 1, fetched) then break end
                        end
                    elseif fx.tag or fx.tags then
                        vroPullSpec(playerInv, { tag = fx.tag, tags = fx.tags }, fetched)
                    end
                    if fx.globalItem then vroPullSpec(playerInv, fx.globalItem, fetched) end
                    if type(fx.equip) == "table" then
                        for _, k in ipairs({ "primary", "secondary", "wear" }) do
                            if fx.equip[k] then vroPullSpec(playerInv, fx.equip[k], fetched) end
                        end
                    end
                end
            end
        end
    end
end

-- Build the part's REAL context menu off-screen and click the best enabled
-- repair option programmatically. Reuses VRO's (and vanilla's) entire option
-- pipeline -- availability, item bundles, equip chain, timed action.
local function vroTryPart(playerObj, playerInv, vehicle, part, cond, fetched, repaired, noteSkip)
    if not VROCore then return false end
    local invItem = nil
    pcall(function() invItem = part:getInventoryItem() end)
    local ft, pid = nil, nil
    pcall(function() if invItem then ft = invItem:getFullType() end end)
    pcall(function() pid = part:getId() end)
    local matched = vroMatchedRecipes(ft, pid)
    if #matched == 0 then return false end
    vroPrefetch(playerObj, playerInv, matched, fetched)

    local playerNum = 0
    pcall(function() playerNum = playerObj:getPlayerNum() end)
    local ctx = nil
    pcall(function() ctx = ISContextMenu.get(playerNum, 0, 0) end)
    if not ctx then return false end
    local fake = {
        playerNum = playerNum,
        chr = playerObj,
        character = playerObj,
        vehicle = vehicle,
        context = ctx,
        getAbsoluteX = function() return 0 end,
        getAbsoluteY = function() return 0 end,
        doMenuTooltip = function() end,
        -- AutoMechanics and WarThunderVehicleLibrary both wrap
        -- doPartContextMenu, both crash on this stand-in self, and both honor
        -- this inhibit flag (Panzer copied AutoMechanics' code). No-op methods
        -- kept as a second line of defense.
        inhibitAutoMechanics_doPartContextMenu = true,
        addAutoMechanicsButtons = function() end,
        noEnginePart = function() end,
    }
    pcall(function() ISVehicleMechanics.doPartContextMenu(fake, part, 0, 0) end)

    local queuedHere, handled = false, false
    pcall(function()
        local repairTxt = getText("ContextMenu_Repair")
        local parentOpt = nil
        for i = 1, #ctx.options do
            local o = ctx.options[i]
            if o and o.name == repairTxt and o.subOption then parentOpt = o; break end
        end
        if not parentOpt then return end
        local sub = ctx:getSubMenu(parentOpt.subOption)
        if not (sub and sub.options) then return end
        local bestOpt, bestScore = nil, -1
        local blocked = {}
        for i = 1, #sub.options do
            local o = sub.options[i]
            if o and o.notAvailable then
                blocked[#blocked + 1] = tostring(o.name)
            elseif o and o.onSelect then
                -- rank by tooltip percentages (success chance + potential repair)
                local score = 0
                pcall(function()
                    local d = (o.toolTip and o.toolTip.description) or ""
                    for num in string.gmatch(d, "(%d+)%%") do
                        score = score + (tonumber(num) or 0)
                    end
                end)
                if score > bestScore then bestScore, bestOpt = score, o end
            end
        end
        if bestOpt then
            bestOpt.onSelect(bestOpt.target, bestOpt.param1, bestOpt.param2, bestOpt.param3,
                bestOpt.param4, bestOpt.param5, bestOpt.param6, bestOpt.param7,
                bestOpt.param8, bestOpt.param9, bestOpt.param10)
            repaired[#repaired + 1] = tostring(pid or "part") .. " (" .. cond .. "% VRO: " .. tostring(bestOpt.name) .. ")"
            queuedHere = true
            handled = true
        elseif #blocked > 0 then
            noteSkip(part, cond, "VRO option(s) blocked -- fixers seen: " .. table.concat(blocked, " / "))
            handled = true
        end
    end)
    pcall(function() ctx:hideAndChildren() end)
    pcall(function() ctx:setVisible(false) end)
    if handled then end -- (blocked parts are named above; vanilla still gets a shot)
    return queuedHere
end

local MAX_PASSES = 4
local _watcher = nil

local function queueEmpty(playerObj)
    local empty = true
    pcall(function()
        local q = ISTimedActionQueue.getTimedActionQueue(playerObj)
        empty = (not q) or (not q.queue) or (#q.queue == 0)
    end)
    return empty
end

local function quickRepair(playerObj, vehicle, pass)
    pass = pass or 1
    if not playerObj or not vehicle then return end
    local playerInv = playerObj:getInventory()
    local fetched = {}
    local repaired, skipReserve, skipNoFix, skipGate = {}, 0, 0, 0
    local skipNames = {}   -- "PartId: reason" per skipped part
    local replaceOnly = 0  -- damaged but the game only allows replacing, not repairing
    local function noteSkip(part, cond, reason)
        local pid = "part"
        pcall(function() pid = part:getId() end)
        skipNames[#skipNames + 1] = pid .. " (" .. tostring(cond) .. "%): " .. reason
    end
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
        -- NOTE: isRepairMechanic() is NOT consulted -- VRO flips that flag
        -- lazily only when a part's menu is opened, so it lies for any part
        -- the player hasn't clicked this session (bus seat bug, 2026-07-03).
        if part and invItem and cond <= 0 then
            -- vanilla cannot fix 0% parts, but VRO recipes often can: try VRO
            -- first; only if VRO has nothing is this truly a replace job
            if not vroTryPart(playerObj, playerInv, vehicle, part, cond, fetched, repaired, noteSkip) then
                replaceOnly = replaceOnly + 1
                noteSkip(part, cond, "destroyed, no VRO recipe -- use Quick replace")
            end
        elseif part and invItem and cond < COND_THRESHOLD then
            local vanillaQueued = false
            -- VRO FIRST: its lua recipes supersede (and deliberately hide)
            -- several script fixings that FixingManager still returns -- the
            -- welding ones need torch USES, which item-counting cannot see,
            -- and queueing them produced "bugged action, cleared queue" wipes.
            local vroQueued = vroTryPart(playerObj, playerInv, vehicle, part, cond, fetched, repaired, noteSkip)
            local fixingList = nil
            if not vroQueued then
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
                                -- skill gate FIRST: never fetch for a fix the
                                -- character cannot perform (vanilla tooltip API)
                                local skillsOk = true
                                pcall(function()
                                    local sk = fixer:getFixerSkills()
                                    if sk then
                                        for s = 0, sk:size() - 1 do
                                            local req = sk:get(s)
                                            local perk = Perks.FromString(req:getSkillName())
                                            if perk and playerObj:getPerkLevel(perk) < req:getSkillLevel() then
                                                skillsOk = false
                                                break
                                            end
                                        end
                                    end
                                end)
                                if ft and skillsOk then
                                    local carried = invCount(playerInv, ft)
                                    local stock = baseCount(ft)
                                    -- reserve rule counts what must LEAVE the base
                                    local fromBase = need - carried
                                    if fromBase < 0 then fromBase = 0 end
                                    if (carried + stock) >= need and (stock - fromBase) >= RESERVE then
                                        -- predicted % restored: same java call the vanilla
                                        -- fix tooltip uses ("Potential repair"). Accounts
                                        -- for fixer strength, skill and times-repaired.
                                        local gain, failCh = 5, nil
                                        pcall(function() gain = FixingManager.getCondRepaired(invItem, playerObj, fixing, fixer) or 5 end)
                                        pcall(function() failCh = FixingManager.getChanceOfFail(invItem, playerObj, fixing, fixer) end)
                                        if (not best) or gain > best.gain
                                            or (gain == best.gain and stock > best.stock) then
                                            best = { fixingNum = i, fixerNum = j, ft = ft, need = need, stock = stock, toolFt = toolFt, gain = gain, failCh = failCh }
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
                if best and best.gain < MIN_GAIN then
                    -- even the BEST fixer barely moves the needle: repairing is
                    -- a waste of materials, replacing is the real answer.
                    replaceOnly = replaceOnly + 1
                    noteSkip(part, cond, "best fixer only +" .. math.floor(best.gain) .. "% -- use Quick replace")
                elseif best then
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
                                vanillaQueued = true
                                local pid = "part"
                                pcall(function() pid = part:getId() end)
                                local failTxt = best.failCh and (" fail " .. math.ceil(best.failCh) .. "%") or ""
                                repaired[#repaired + 1] = pid .. " (" .. cond .. "% +" .. math.floor(best.gain) .. "% via " .. best.ft .. failTxt .. ")"
                            end)
                        else
                            skipGate = skipGate + 1  -- skill or requirement gate said no
                            noteSkip(part, cond, "skill/requirements")
                        end
                    else
                        skipReserve = skipReserve + 1
                        noteSkip(part, cond, "not enough stock above reserve")
                    end
                else
                    skipReserve = skipReserve + 1  -- nothing plentiful enough / reserve rule
                    noteSkip(part, cond, "no material clears skill+reserve")
                end
            end
            end
            if (not vroQueued) and (not vanillaQueued)
                and not (fixingList and not fixingList:isEmpty()) then
                skipNoFix = skipNoFix + 1
                noteSkip(part, cond, "no vanilla or VRO repair recipe -- replace-only")
            end
        end
    end

    print("[EmpireQoL] QuickRepair pass " .. pass .. ": queued=" .. #repaired
        .. " reserveOrStockSkips=" .. skipReserve
        .. " skillGateSkips=" .. skipGate
        .. " noFixRecipe=" .. skipNoFix
        .. " replaceOnlyParts=" .. replaceOnly
        .. (#fetched > 0 and (" | fetched: " .. table.concat(fetched, ", ")) or ""))
    if #skipNames > 0 then
        print("[EmpireQoL] QuickRepair skips: " .. table.concat(skipNames, " | "))
    end
    if #repaired > 0 then
        pcall(function()
            HaloTextHelper.addTextWithArrow(playerObj, "Quick repair pass " .. pass .. ": " .. #repaired .. " part(s) queued", "[br/]", true, HaloTextHelper.getColorGreen())
        end)
        print("[EmpireQoL] QuickRepair parts: " .. table.concat(repaired, ", "))
        -- MULTI-PASS: repairs heal partial condition per fix. When the action
        -- queue drains, run the next pass automatically until a pass queues 0.
        if pass < MAX_PASSES then
            if _watcher then Events.OnTick.Remove(_watcher); _watcher = nil end
            local ticks = 0
            _watcher = function()
                ticks = ticks + 1
                if ticks % 30 ~= 0 then return end  -- check twice a second, not every tick
                if queueEmpty(playerObj) then
                    Events.OnTick.Remove(_watcher); _watcher = nil
                    quickRepair(playerObj, vehicle, pass + 1)
                end
            end
            Events.OnTick.Add(_watcher)
        end
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
        context:addOption("Empire: Quick repair from base", player, function(p, v)
            -- run OUTSIDE ISContextMenu.onMouseUp: vroTryPart reuses the
            -- context-menu singleton, and mutating it mid-click crashed
            local fired = false
            local once
            once = function()
                if fired then return end
                fired = true
                Events.OnTick.Remove(once)
                quickRepair(p, v)
            end
            Events.OnTick.Add(once)
        end, veh)
    end)
end)

-- exported for the combined FIX flow in 48_QuickReplace (replace, then repair);
-- the FIX watcher already calls this from OnTick, outside any menu handler
EmpireQoL_QuickRepair = quickRepair

print("[EmpireQoL] QuickRepair loaded: vanilla + VRO repair from base stock (best gain wins, min gain " .. MIN_GAIN .. "%, reserve " .. RESERVE .. ", VRO " .. (VROCore and "detected" or "absent") .. ")")
