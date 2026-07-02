-- EmpireQoL :: 44_CraftFromBase.lua -- build & craft straight from base storage (B42 entity system)
-- THE quartermaster: stand in your base, open Build or a crafting panel, and every
-- container in the base counts as yours -- no hauling planks and nails by hand.
--
-- B42.19 moved building/crafting onto the entity-recipe system. All material gathering
-- funnels through ISInventoryPaneContextMenu.getContainers(player), called inside a
-- handful of panel methods. We do NOT wrap that global -- it also serves every inventory
-- right-click, and augmenting it there is exactly the context-menu lag that killed the
-- previous (now-obsolete) 24/30/32 suite. Instead: SCOPED SHIM -- swap the gatherer in,
-- run the panel's own method, swap it back. Base containers exist only for the duration
-- of the panel's refresh.
--
-- Containers come from EmpireBaseCache (31): event-invalidated, debounced index of the
-- base you're standing in. Not inside a registered base -> no-op, pure vanilla.
-- The recipe engine reads AND consumes from the real container objects we hand it, so
-- counts are live-accurate and nothing can dupe.

local function baseContainers()
    local out = nil
    pcall(function()
        if EmpireBaseCache and EmpireBaseCache.get then
            local cache = EmpireBaseCache.get()
            if cache and cache.containers then out = cache.containers end
        end
    end)
    return out
end

-- append base containers to a vanilla getContainers result (java ArrayList), dedup by identity
local function augment(list)
    local extra = baseContainers()
    if not list or not extra then return list end
    pcall(function()
        local seen = {}
        for i = 0, list:size() - 1 do seen[list:get(i)] = true end
        for _, c in ipairs(extra) do
            if c and not seen[c] then list:add(c); seen[c] = true end
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

Events.OnGameStart.Add(function()
    shim("ISBuildPanel", "updateContainers")        -- build menu material counts
    shim("ISBuildPanel", "createBuildIsoEntity")    -- build placement / consume start
    shim("ISHandCraftPanel", "updateContainers")    -- handcraft panel counts
    shim("ISHandCraftPanel", "setSeeAllRecipe")     -- recipe list refresh path
    shim("ISCraftLogicPanel", "updateContainers")   -- crafting-station logic panel
    print("[EmpireQoL] CraftFromBase active: build & craft panels see the whole base")
end)
