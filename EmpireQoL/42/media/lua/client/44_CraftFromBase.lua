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
        print("[EmpireQoL] CraftFromBase v3 active (late-installed): cache + proximity fallback (r=" .. RADIUS .. ")")
    end
    Events.OnTick.Add(install)
end)
