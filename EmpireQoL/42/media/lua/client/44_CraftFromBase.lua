-- EmpireQoL :: 44_CraftFromBase.lua (v2) -- build & craft straight from nearby storage
-- v1 sourced containers ONLY from EmpireBaseCache, which needs the base to be
-- registered in EmpireBases -- King's isn't (or the marker misses the workshop), so
-- every shim silently no-op'd. v2: cache first, then PROXIMITY FALLBACK -- scan all
-- containers within RADIUS tiles on every floor (the sorter/FindItem pattern), cached
-- for a short TTL. Works anywhere your storage physically is, no registry required.
--
-- Scoped shims (unchanged): swap ISInventoryPaneContextMenu.getContainers only for
-- the duration of the build/craft panel methods. The global stays vanilla -- that's
-- what keeps right-click menus lag-free.

local RADIUS   = 16
local TTL_MS   = 10000
local _cache, _cacheKey, _cacheAt = nil, nil, 0

local function proximityContainers(player)
    local sq = player and player:getSquare()
    if not sq then return nil end
    local px, py = sq:getX(), sq:getY()
    local key = math.floor(px / 8) .. ":" .. math.floor(py / 8)
    local now = getTimestampMs()
    if _cache and _cacheKey == key and (now - _cacheAt) < TTL_MS then return _cache end
    local out, seen = {}, {}
    local cell = getCell()
    for z = 0, 7 do
        for x = px - RADIUS, px + RADIUS do
            for y = py - RADIUS, py + RADIUS do
                local s = cell:getGridSquare(x, y, z)
                if s then
                    local objs = s:getObjects()
                    if objs then
                        for i = 0, objs:size() - 1 do
                            local o = objs:get(i)
                            local n = 0
                            pcall(function() n = o:getContainerCount() or 0 end)
                            if n and n > 0 then
                                for ci = 0, n - 1 do
                                    local c = nil
                                    pcall(function() c = o:getContainerByIndex(ci) end)
                                    if c and not seen[c] then seen[c] = true; out[#out+1] = c end
                                end
                            else
                                -- objects without getContainerCount (or reporting 0): single-container path
                                local c = nil
                                pcall(function() c = o:getContainer() end)
                                if c and not seen[c] then seen[c] = true; out[#out+1] = c end
                            end
                        end
                    end
                end
            end
        end
    end
    _cache, _cacheKey, _cacheAt = out, key, now
    return out
end

-- Shared source: cache when the base registry knows where we are, proximity otherwise.
-- Exported: 45_MechanicFromBase (and anything else) reuses this exact source.
function EmpireQoL_BaseContainers(player)
    local out = nil
    pcall(function()
        if EmpireBaseCache and EmpireBaseCache.get then
            local cache = EmpireBaseCache.get()
            if cache and cache.containers and #cache.containers > 0 then out = cache.containers end
        end
    end)
    if out then return out end
    local p = player
    if not p then pcall(function() p = getSpecificPlayer(0) end) end
    local prox = nil
    pcall(function() prox = proximityContainers(p) end)
    return prox
end

local _lastNote = 0
local function augment(list)
    local extra = EmpireQoL_BaseContainers(nil)
    if not list or not extra then return list end
    pcall(function()
        local seen, added = {}, 0
        for i = 0, list:size() - 1 do seen[list:get(i)] = true end
        for _, c in ipairs(extra) do
            if c and not seen[c] then list:add(c); seen[c] = true; added = added + 1 end
        end
        local now = getTimestampMs()
        if added > 0 and (now - _lastNote) > 5000 then
            _lastNote = now
            print("[EmpireQoL] CraftFromBase: +" .. added .. " storage containers visible to this panel")
        end
    end)
    return list
end

-- BUILD QUARTERMASTER: Neat resolves build TOOLS strictly from the player's own
-- inventory (getAllTypeEvalRecurse on inventory), and consume is only reliable with
-- everything on you. So on build click, BEFORE the ghost cursor is created, pull the
-- selected recipe's missing tools AND input materials from base storage into the
-- player's inventory. Instant move, same pattern as the mechanics quartermaster.
-- Exported: one quartermaster for every window. Pulls the recipe's tools + input
-- materials (x times, for batch crafts) from base storage into the player's inventory.
function EmpireQoL_FetchForRecipe(playerObj, recipe, times)
    if not playerObj or not recipe then return end
    times = times or 1
    local inv = playerObj:getInventory()
    local src = EmpireQoL_BaseContainers(playerObj)
    if not src or #src == 0 then return end
    local fetched = {}

    local function haveCount(ft)
        local n = 0
        pcall(function()
            local res = inv:getAllTypeRecurse(ft)
            n = res and res:size() or 0
        end)
        return n
    end
    local function pullOne(ft)
        for _, c in ipairs(src) do
            local got = nil
            pcall(function()
                local items = c:getItems()
                for i = 0, items:size() - 1 do
                    local it = items:get(i)
                    if it and it:getFullType() == ft then got = it; break end
                end
            end)
            if got then
                local ok = pcall(function() c:Remove(got); inv:addItem(got) end)
                if ok then
                    local nm = ft
                    pcall(function() nm = got:getDisplayName() end)
                    fetched[#fetched + 1] = nm
                    return true
                end
            end
        end
        return false
    end
    local function ensureInput(inputScript)
        if not inputScript then return end
        local possible = nil
        pcall(function() possible = inputScript:getPossibleInputItems() end)
        if not possible or possible:size() == 0 then return end
        local need = nil
        pcall(function() need = inputScript:getIntAmount() end)
        if (not need) or need < 1 then pcall(function() need = inputScript:getAmount() end) end
        if (not need) or need < 1 then need = 1 end
        need = need * times
        local have = 0
        local types = {}
        for m = 0, possible:size() - 1 do
            local ft = nil
            pcall(function() ft = possible:get(m):getFullName() end)
            if ft then types[#types + 1] = ft; have = have + haveCount(ft) end
        end
        local missing = need - have
        while missing > 0 do
            local pulled = false
            for _, ft in ipairs(types) do
                if pullOne(ft) then pulled = true; break end
            end
            if not pulled then break end
            missing = missing - 1
        end
    end
    pcall(function() ensureInput(recipe:getToolBoth()) end)
    pcall(function() ensureInput(recipe:getToolRight()) end)
    pcall(function() ensureInput(recipe:getToolLeft()) end)
    pcall(function()
        local ins = recipe:getInputs()
        for i = 0, ins:size() - 1 do
            local input = ins:get(i)
            local auto = false
            pcall(function() auto = input:isAutomationOnly() end)
            if not auto then ensureInput(input) end
        end
    end)
    if #fetched > 0 then
        pcall(function()
            HaloTextHelper.addTextWithArrow(playerObj, "Quartermaster: " .. table.concat(fetched, ", "), "[br/]", true, HaloTextHelper.getColorGreen())
        end)
        print("[EmpireQoL] CraftFromBase: build quartermaster fetched " .. #fetched .. " item(s) to player")
        pcall(function() if EmpireBaseCache and EmpireBaseCache.invalidate then EmpireBaseCache.invalidate() end end)
    end
end

local function fetchForBuild(panel)
    local playerObj = panel and panel.player
    if not playerObj then return end
    local recipe = nil
    pcall(function() recipe = panel.logic and panel.logic:getRecipe() end)
    if not recipe then return end
    EmpireQoL_FetchForRecipe(playerObj, recipe, 1)
end

local function shim(klassName, methodName)
    local k = _G[klassName]
    if not k or type(k[methodName]) ~= "function" then
        print("[EmpireQoL] CraftFromBase: " .. klassName .. ":" .. methodName .. " not found -- skipped (game update?)")
        return
    end
    local origMethod = k[methodName]
    k[methodName] = function(self, ...)
        local now = getTimestampMs()
        if (now - _lastNote) > 5000 then
            _lastNote = now
            local src = nil
            pcall(function() src = EmpireQoL_BaseContainers(nil) end)
            print("[EmpireQoL] CraftFromBase: " .. klassName .. ":" .. methodName .. " fired; storage source = " .. tostring(src and #src or 0) .. " containers")
        end
        local gc = ISInventoryPaneContextMenu.getContainers
        ISInventoryPaneContextMenu.getContainers = function(...)
            return augment(gc(...))
        end
        local r = { pcall(origMethod, self, ...) }
        ISInventoryPaneContextMenu.getContainers = gc   -- always restore, even on error
        if not r[1] then error(r[2]) end
        return r[2], r[3], r[4]
    end
    print("[EmpireQoL] CraftFromBase: shimmed " .. klassName .. ":" .. methodName)
end

-- INSTALL ONE TICK LATE: other mods (UI overhauls etc.) replace these same class
-- methods inside their own OnGameStart. If we install at OnGameStart too, load order
-- decides who survives. One tick later, everyone else has finished -- we wrap the winner.
Events.OnGameStart.Add(function()
    local installed = false
    local function install()
        if installed then return end
        installed = true
        Events.OnTick.Remove(install)
        shim("ISBuildPanel", "updateContainers")        -- build menu material counts
        shim("ISBuildPanel", "createBuildIsoEntity")    -- build placement / consume start
        shim("ISHandCraftPanel", "updateContainers")    -- handcraft panel counts
        shim("ISHandCraftPanel", "setSeeAllRecipe")     -- recipe list refresh path
        shim("ISCraftLogicPanel", "updateContainers")   -- crafting-station logic panel
        -- v4: the sites ABOVE never fired in live play (telemetry-proven) -- the real
        -- flows route through these two: world right-click Build clicks land in
        -- ISEntityBuildMenu.onBuildEntity, and craft windows count via the
        -- ISCraftInputItems widget. Shim the live doors, keep the old ones as belt.
        shim("ISEntityBuildMenu", "onBuildEntity")      -- LIVE: world build-menu click -> place/consume
        shim("ISCraftInputItems", "updateContainers")   -- LIVE: craft window ingredient counting
        -- v5: King's ACTUAL windows are the Neat Rocco suite -- Neat_Building and
        -- Neat_Crafting replace the vanilla UIs entirely (telemetry: vanilla doors
        -- installed-but-silent, tuning window +52 proved the source is alive).
        -- Same getContainers chokepoint, the right classes this time:
        shim("NB_BuildingPanel", "updateContainers")        -- Neat build menu counts
        shim("NB_BuildingPanel", "createBuildIsoEntity")    -- Neat build place/consume
        shim("NC_CraftLogicPanel", "updateContainers")      -- Neat craft-station logic
        shim("NC_HandCraftPanel", "updateContainers")       -- Neat handcraft window
        -- v6: quartermaster fetch runs FIRST on build click, then the shimmed original
        local nb = _G["NB_BuildingPanel"]
        if nb and type(nb.createBuildIsoEntity) == "function" then
            local prev = nb.createBuildIsoEntity
            nb.createBuildIsoEntity = function(self, ...)
                pcall(function() fetchForBuild(self) end)
                -- re-resolve: the logic picked its input items BEFORE the fetch (they
                -- pointed at far base shelves and fail range checks at action time).
                -- Refreshing containers makes selection land on the items now carried.
                pcall(function() if self.updateContainers then self:updateContainers() end end)
                pcall(function()
                    if self.logic and self.logic.canPerformCurrentRecipe then
                        print("[EmpireQoL] build QM: post-fetch canPerform = " .. tostring(self.logic:canPerformCurrentRecipe()))
                    end
                end)
                return prev(self, ...)
            end
            print("[EmpireQoL] CraftFromBase: build quartermaster armed (tools + materials fetched from base on build click)")
        end
        -- v7: same quartermaster on the CRAFT button (handcraft + craft stations).
        -- startHandcraft carries the batch quantity, so batch crafts fetch enough.
        local ncap = _G["NC_CraftActionPanel"]
        if ncap and type(ncap.startHandcraft) == "function" then
            local prevSH = ncap.startHandcraft
            ncap.startHandcraft = function(self, force, craftTimes, ...)
                pcall(function()
                    local rec = self.logic and self.logic:getRecipe()
                    if rec then EmpireQoL_FetchForRecipe(self.player, rec, craftTimes or 1) end
                end)
                -- re-resolve selection onto the freshly-carried items (see build note)
                pcall(function()
                    if self.logic then
                        local list = ISInventoryPaneContextMenu.getContainers(self.player)
                        self.logic:setContainers(augment(list))
                    end
                end)
                pcall(function()
                    if self.logic and self.logic.canPerformCurrentRecipe then
                        print("[EmpireQoL] craft QM: post-fetch canPerform = " .. tostring(self.logic:canPerformCurrentRecipe()))
                    end
                end)
                return prevSH(self, force, craftTimes, ...)
            end
            print("[EmpireQoL] CraftFromBase: craft quartermaster armed (materials fetched from base on craft click, batch-aware)")
        end
        -- v9: CONSUME-TIME CONTAINER RESET. Telemetry proved canPerform=true at
        -- click but "ISBuildIsoEntity -> consume failed" at action completion:
        -- the logic rides to the build site carrying our AUGMENTED container list
        -- (base shelves included). performCurrentRecipe re-resolves inputs against
        -- that list and shelf items fail range validation at the build spot -- the
        -- fetched items on the player never get picked. Fix: right before consume,
        -- reset the logic to the vanilla in-range container set (player inventory
        -- is always in range; QM already put the materials there).
        local bie = _G["ISBuildIsoEntity"]
        if bie and type(bie.create) == "function" then
            local prevCreate = bie.create
            bie.create = function(self, ...)
                pcall(function()
                    local ch = self.character
                    if ch and self.buildPanelLogic then
                        self.buildPanelLogic:setContainers(ISInventoryPaneContextMenu.getContainers(ch))
                        local ok = nil
                        pcall(function() ok = self.buildPanelLogic:canPerformCurrentRecipe() end)
                        print("[EmpireQoL] build QM: consume-time reset to in-range containers; canPerform = " .. tostring(ok))
                        if ok == false then
                            -- stale manual selection can survive the reset: drop to
                            -- auto-select so java re-picks from carried items
                            pcall(function() self.buildPanelLogic:setManualSelectInputs(false) end)
                            pcall(function() ok = self.buildPanelLogic:canPerformCurrentRecipe() end)
                            print("[EmpireQoL] build QM: fallback auto-select; canPerform = " .. tostring(ok))
                        end
                    end
                end)
                return prevCreate(self, ...)
            end
            print("[EmpireQoL] CraftFromBase: consume-time container reset armed (ISBuildIsoEntity.create)")
        end
        -- same medicine for CRAFT: ISHandcraftAction:start() rebuilds its logic
        -- from a containers snapshot captured at click time (our augmented list).
        -- In SP, fixMovedItems never runs (isClient-only), so stale refs survive.
        -- Recompute the snapshot fresh + in-range at action start.
        local hca = _G["ISHandcraftAction"]
        if hca and type(hca.start) == "function" then
            local prevStart = hca.start
            hca.start = function(self, ...)
                pcall(function()
                    if self.character then
                        self.containers = ISInventoryPaneContextMenu.getContainers(self.character)
                        print("[EmpireQoL] craft QM: action-start containers reset to in-range set")
                    end
                    -- v10: manualInputs hold refs to the EXACT items picked at click
                    -- time -- shelf copies, while QM fetched different copies of the
                    -- same types onto the player. Vanilla only remaps moved items in
                    -- MP (fixMovedItems is isClient-gated). Do the SP equivalent:
                    -- keep refs that are on the player, substitute same-fullType
                    -- carried items for any ref that is not.
                    if self.manualInputs and self.character then
                        local inv = self.character:getInventory()
                        local remapped, unresolved = 0, 0
                        local usedIds = {}
                        for _, items in pairs(self.manualInputs) do
                            if items and items.size then
                                for i = 0, items:size() - 1 do
                                    local item = items:get(i)
                                    if item then
                                        local onMe = nil
                                        pcall(function() onMe = inv:getItemById(item:getID()) end)
                                        if onMe then
                                            usedIds[item:getID()] = true
                                        else
                                            local ft, sub = nil, nil
                                            pcall(function() ft = item:getFullType() end)
                                            if ft then
                                                local cand = nil
                                                pcall(function() cand = inv:getAllTypeRecurse(ft) end)
                                                if cand then
                                                    for j = 0, cand:size() - 1 do
                                                        local c2 = cand:get(j)
                                                        if c2 and not usedIds[c2:getID()] then sub = c2; break end
                                                    end
                                                end
                                            end
                                            if sub then
                                                items:set(i, sub)
                                                usedIds[sub:getID()] = true
                                                remapped = remapped + 1
                                            else
                                                unresolved = unresolved + 1
                                            end
                                        end
                                    end
                                end
                            end
                        end
                        if remapped > 0 or unresolved > 0 then
                            print("[EmpireQoL] craft QM: manual inputs remapped onto carried items = " .. remapped .. ", unresolved = " .. unresolved)
                        end
                    end
                end)
                return prevStart(self, ...)
            end
            print("[EmpireQoL] CraftFromBase: action-start container reset + manual-input remap armed (ISHandcraftAction.start)")
        end
        -- v10: last-line rescue at the consume moment. If the recipe still cannot
        -- perform with the manual selection, drop to auto-select -- the logic then
        -- re-picks from the in-range containers (the carried QM items). Only fires
        -- when the craft would otherwise produce NOTHING, so it strictly improves.
        if hca and type(hca.performRecipe) == "function" then
            local prevPR = hca.performRecipe
            hca.performRecipe = function(self, ...)
                pcall(function()
                    if self.logic and self.logic.canPerformCurrentRecipe then
                        local ok = self.logic:canPerformCurrentRecipe()
                        print("[EmpireQoL] craft QM: consume-time canPerform = " .. tostring(ok))
                        if ok == false then
                            pcall(function() self.logic:setManualSelectInputs(false) end)
                            pcall(function() ok = self.logic:canPerformCurrentRecipe() end)
                            print("[EmpireQoL] craft QM: fallback auto-select; canPerform = " .. tostring(ok))
                        end
                    end
                end)
                -- OUTPUT IDENTITY LOG: every created item passes through
                -- Actions.addOrDropItem inside vanilla performRecipe. Capture it
                -- to print the item the game ACTUALLY made -- internal fullType,
                -- display name, condition -- so crafted-vs-required identity can
                -- be compared against the PART AUTOPSY line by line.
                local addOrig = Actions and Actions.addOrDropItem
                if addOrig then
                    Actions.addOrDropItem = function(chr, item, ...)
                        pcall(function()
                            print("[EmpireQoL] craft OUTPUT: " .. tostring(item:getFullType())
                                .. " '" .. tostring(item:getDisplayName()) .. "'"
                                .. " cond=" .. tostring(item:getCondition()))
                        end)
                        return addOrig(chr, item, ...)
                    end
                end
                local r = { pcall(prevPR, self, ...) }
                if addOrig then Actions.addOrDropItem = addOrig end
                if not r[1] then error(r[2]) end
                return r[2], r[3]
            end
            print("[EmpireQoL] CraftFromBase: consume-time rescue armed (ISHandcraftAction.performRecipe)")
        end
        print("[EmpireQoL] CraftFromBase v3 active (late-installed): cache + proximity fallback (r=" .. RADIUS .. ")")
    end
    Events.OnTick.Add(install)
end)
