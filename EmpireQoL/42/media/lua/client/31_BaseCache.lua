-- EmpireQoL :: 31_BaseCache.lua
-- Live material index for the base you're standing in. Built when you enter a base,
-- kept warm by a background heartbeat, and rebuilt on demand if read while stale.
-- Craft/build/sort read this instead of sweeping the world every click.
--   EmpireBaseCache.get()            -> { base, byType, containers, totalItems } or nil
--   EmpireBaseCache.count(fullType)  -> how many of that item are in the base
--   EmpireBaseCache.containersFor(ft)-> list of containers holding that item
--   EmpireBaseCache.invalidate()     -> mark stale; next read rebuilds
-- Counts are item-instance counts; the actual consume step re-verifies before taking.

EmpireBaseCache = EmpireBaseCache or {}
EmpireBaseCache.DEBUG = true       -- one console line per rebuild (mute by setting false)

local REFRESH_MS = 300000           -- SAFETY NET ONLY (5 min). Real freshness is event-driven: the cache
                                    -- is marked dirty the moment items move (transfer/sort/loot/craft/build),
                                    -- so it rebuilds on the next read after a change -- not on a clock.

local MIN_REBUILD_MS = 2000         -- DEBOUNCE. Even when items have moved, never run a full base re-sweep
                                    -- more than once per this window. On a busy base (NPCs feeding, auto-sort,
                                    -- looting) multiple consumers reading back-to-back each used to force their
                                    -- own ~84ms / 17k-item rebuild; this caps the whole base to one rebuild per
                                    -- window. Counts can be momentarily stale; every consume re-verifies before
                                    -- taking, and a real rebuild follows within the window, so nothing breaks.

local state = {
    baseName = nil, builtMs = 0, dirty = true,
    byType = {}, containers = {}, totalItems = 0,
}

-- Sweep the base (player floor +/- FLOOR_SPREAD) and build a fresh index.
local function enumerate(base, playerObj)
    local idx = { byType = {}, containers = {}, totalItems = 0 }
    local sq = playerObj:getCurrentSquare()
    if not sq then return idx end
    local cell = getCell()
    if not cell then return idx end
    local pz = sq:getZ()
    local spread = (EmpireBases and EmpireBases.FLOOR_SPREAD) or 0
    local x1 = math.min(base.x1, base.x2)
    local x2 = math.max(base.x1, base.x2)
    local y1 = math.min(base.y1, base.y2)
    local y2 = math.max(base.y1, base.y2)
    local seen = {}
    for z = pz - spread, pz + spread do
        for x = x1, x2 do
            for y = y1, y2 do
                local s = cell:getGridSquare(x, y, z)
                if s then
                    local objs = s:getObjects()
                    for i = 0, objs:size() - 1 do
                        local obj = objs:get(i)
                        local c = nil
                        pcall(function() c = obj:getContainer() end)
                        if c and not seen[c] then
                            seen[c] = true
                            local excluded = false
                            pcall(function()
                                if EmpireSortConfig and EmpireSortConfig.isExcludedContainer then
                                    excluded = EmpireSortConfig.isExcludedContainer(c)
                                end
                            end)
                            if not excluded then
                                idx.containers[#idx.containers + 1] = c
                                local items = nil
                                pcall(function() items = c:getItems() end)
                                if items then
                                    for k = 0, items:size() - 1 do
                                        local it = items:get(k)
                                        local ft = nil
                                        pcall(function() ft = it:getFullType() end)
                                        if not ft then pcall(function() ft = it:getType() end) end
                                        if ft then
                                            local rec = idx.byType[ft]
                                            if not rec then rec = { count = 0, containers = {}, seenC = {} }; idx.byType[ft] = rec end
                                            rec.count = rec.count + 1
                                            if not rec.seenC[c] then rec.seenC[c] = true; rec.containers[#rec.containers + 1] = c end
                                            idx.totalItems = idx.totalItems + 1
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return idx
end

-- Rebuild the index for `base` and store it. Returns nothing.
local function rebuild(base, playerObj)
    local t0 = getTimestampMs()
    local idx = enumerate(base, playerObj)
    state.baseName   = base.name
    state.byType     = idx.byType
    state.containers = idx.containers
    state.totalItems = idx.totalItems
    state.builtMs    = getTimestampMs()
    state.dirty      = false
    if EmpireBaseCache.DEBUG then
        local types = 0; for _ in pairs(idx.byType) do types = types + 1 end
        print(string.format("[EmpireBaseCache] %s: %d items / %d containers / %d types (built in %dms)",
            tostring(base.name), idx.totalItems, #idx.containers, types, getTimestampMs() - t0))
    end
end

local function activeBaseFor(playerObj)
    if not (EmpireBases and EmpireBases.activeBase) then return nil end
    return EmpireBases.activeBase(playerObj)
end

-- Get the live index for the base you're in, rebuilding if stale. nil if not in a base.
function EmpireBaseCache.get(force)
    local p = getSpecificPlayer(0)
    if not p then return nil end
    local base = activeBaseFor(p)
    if not base then return nil end
    local now = getTimestampMs()
    -- Always rebuild immediately on: explicit force, switching to a different base, an empty
    -- index, or the 5-min safety net. For an ordinary "items moved" dirty flag, DEBOUNCE -- a
    -- busy base can't trigger back-to-back full re-sweeps; rebuild at most once per MIN_REBUILD_MS.
    local mustRebuild = force or state.baseName ~= base.name
        or #state.containers == 0 or (now - state.builtMs) >= REFRESH_MS
    local debouncedDirty = state.dirty and (now - state.builtMs) >= MIN_REBUILD_MS
    if mustRebuild or debouncedDirty then rebuild(base, p) end
    return { base = base, byType = state.byType, containers = state.containers, totalItems = state.totalItems }
end

function EmpireBaseCache.count(fullType)
    local c = EmpireBaseCache.get()
    if not c then return 0 end
    local rec = c.byType[fullType]
    return rec and rec.count or 0
end

function EmpireBaseCache.containersFor(fullType)
    local c = EmpireBaseCache.get()
    if not c then return {} end
    local rec = c.byType[fullType]
    return rec and rec.containers or {}
end

function EmpireBaseCache.invalidate()
    state.dirty = true
end

-- Cheap in-place adjustment: a build consume removes a KNOWN number of a KNOWN type from the
-- base, so we just decrement the cached count instead of forcing a full re-sweep of the whole
-- base on the next read. The live consume re-verifies real instances before taking, and any
-- small drift is corrected on the next real rebuild (transfer / craft / 5-min safety net).
-- This is what lets you build fence after fence without the base re-indexing each time.
function EmpireBaseCache.noteConsumed(fullType, n)
    if not fullType or not n or n <= 0 then return end
    if state.dirty then return end          -- nothing trustworthy cached; next read rebuilds anyway
    local rec = state.byType[fullType]
    if rec then
        rec.count = rec.count - n
        if rec.count < 0 then rec.count = 0 end
    end
    state.totalItems = state.totalItems - n
    if state.totalItems < 0 then state.totalItems = 0 end
end

-- prints a one-line status on demand (for testing)
function EmpireBaseCache.status()
    local c = EmpireBaseCache.get()
    local p = getSpecificPlayer(0)
    if not c then
        if p then HaloTextHelper.addTextWithArrow(p, "Not in a base", "[br/]", false, HaloTextHelper.getColorWhite()) end
        print("[EmpireBaseCache] not in a base")
        return
    end
    local types = 0; for _ in pairs(c.byType) do types = types + 1 end
    if p then
        HaloTextHelper.addTextWithArrow(p, "BASE CACHE: " .. c.totalItems .. " items / " .. #c.containers .. " stores", "[br/]", false, HaloTextHelper.getColorGreen())
    end
    print(string.format("[EmpireBaseCache] %s: %d items / %d containers / %d types",
        tostring(c.base.name), c.totalItems, #c.containers, types))
end

-- Background heartbeat: keep the active base's index warm so reads are instant.
-- Rebuilds on entering a base, and on the REFRESH_MS throttle while inside it.
local function heartbeat()
    local p = getSpecificPlayer(0)
    if not p or p:isDead() then return end
    local base = activeBaseFor(p)
    if not base then
        if state.baseName ~= nil then
            state.baseName = nil; state.byType = {}; state.containers = {}; state.totalItems = 0; state.dirty = true
        end
        return
    end
    local now = getTimestampMs()
    if state.baseName ~= base.name or state.dirty or (now - state.builtMs) >= REFRESH_MS then
        rebuild(base, p)
    end
end
-- Heartbeat OFF by default: the cache builds ON DEMAND (only when sort/craft/build
-- actually reads it), so it costs nothing while you're just walking around the base.
-- Set EmpireBaseCache.HEARTBEAT = true to pre-warm it in the background instead.
EmpireBaseCache.HEARTBEAT = false
if EmpireBaseCache.HEARTBEAT then
    Events.EveryOneMinute.Add(heartbeat)
end

print("[EmpireBaseCache] base material cache loaded (on-demand mode).")

-- ============================================================
-- EVENT-DRIVEN INVALIDATION
-- The cache only rebuilds when the base actually changes. We mark it dirty whenever
-- items move: any inventory transfer (manual grab, auto-sort, looting, crafting haul-in)
-- and any craft or build consume. After that, the next read rebuilds once -- and only once.
-- ============================================================
Events.OnGameStart.Add(function()
    -- every item transfer between containers
    if ISInventoryTransferAction and ISInventoryTransferAction.perform then
        local origT = ISInventoryTransferAction.perform
        ISInventoryTransferAction.perform = function(self)
            origT(self)
            -- Skip invalidation for AMMO. "Grab 200 bullets" is 200 separate transfer actions;
            -- ammo counts don't drive sort/craft/build, so we must NOT mark the whole base dirty
            -- (which forces a full ~17k-item re-sweep on the next read) once per round moved.
            local skip = false
            pcall(function()
                local it = self.item
                local ft = it and (it:getFullType() or "")
                if ft and (string.find(ft, "Bullets", 1, true)
                        or string.find(ft, "ShotgunShells", 1, true)
                        or string.find(ft, "Ammo", 1, true)) then
                    skip = true
                end
            end)
            if not skip then pcall(function() EmpireBaseCache.invalidate() end) end
        end
    end
    -- vanilla single craft consume (our instant batch invalidates itself)
    if ISCraftAction and ISCraftAction.perform then
        local origC = ISCraftAction.perform
        ISCraftAction.perform = function(self)
            origC(self)
            pcall(function() EmpireBaseCache.invalidate() end)
        end
    end
    -- NOTE: building no longer blanket-invalidates the cache. SmartBuild's consume reports the
    -- exact materials it pulled via EmpireBaseCache.noteConsumed(), so the count is decremented
    -- in place instead of re-sweeping the ENTIRE base after every single placement -- that full
    -- per-build re-sweep was the lag between consecutive builds on a big base.
    print("[EmpireBaseCache] event-driven invalidation armed (transfer / craft; build = in-place decrement).")
end)
