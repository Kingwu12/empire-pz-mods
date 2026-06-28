-- EmpireQoL: Walk-Through Furniture (AUTOMATIC)
-- B42 stamps a full-tile collision flag on furniture whose sprite only covers half the tile
-- (B41 let you stand on / pass many pieces). Lockers in tight rooms become impassable.
-- This clears the movement-collision flags off blocking FURNITURE as the map streams in --
-- zero clicks, whole world. Walls, windows, doors, fences and anything player-built are
-- structure and are NEVER touched, so your base shell + gates stay solid. Mirrors exactly
-- what the game does when you pick furniture up (strip the flags, recalc the tile) -- not a hack.
--
-- TRADEOFF (honest): collision is collision for everyone, so any piece this frees up, zombies
-- can also path through and you can visually clip into it. King uses gates/walls for defense,
-- not furniture, so that's the intended trade. Right-click "keep this furniture solid" is an
-- escape hatch for any single piece. Reversible: disable this file + restart and sprites
-- reload with their original collision.

local WT_DEBUG = false   -- true -> adds an "identify furniture (log)" probe to the right-click menu

-- movement-collision flags we strip for walkability
local COLLIDE_FLAGS = { "solid", "solidtrans", "collideN", "collideW" }
-- wall/window/door/fence flags: if an object has ANY of these we NEVER touch it
local WALL_FLAGS = { "WallN","WallW","WallNW","WallSE","DoorWallN","DoorWallW","WindowN","WindowW","HoppableN","HoppableW" }

local function flag(name) return IsoFlagType[name] end

-- PropertyContainer exposes Is/Set/UnSet (Java caps); some builds also expose lower-case.
-- Try caps first, fall back to lower, all pcall'd so a missing overload is safe.
local function pIs(props, fl)
    local r = false
    if not pcall(function() r = props:Is(fl) end) then pcall(function() r = props:is(fl) end) end
    return r and true or false
end
local function pUnset(props, fl)
    if not pcall(function() props:UnSet(fl) end) then pcall(function() props:unset(fl) end) end
end
local function pSet(props, fl)
    if not pcall(function() props:Set(fl) end) then pcall(function() props:set(fl) end) end
end

local function spriteName(obj)
    local n = ""
    pcall(function() n = obj:getSprite():getName() or "" end)
    return n
end
local function spriteProps(obj)
    local p = nil
    pcall(function() p = obj:getSprite():getProperties() end)
    return p
end
-- props for a sprite NAME (used at game start), via the same manager the game uses
local function propsForName(name)
    local p = nil
    pcall(function() p = IsoSpriteManager.instance:getSprite(name):getProperties() end)
    return p
end

local function hasAny(props, list)
    if not props then return false end
    for _, f in ipairs(list) do
        local fl = flag(f)
        if fl and pIs(props, fl) then return true end
    end
    return false
end

-- free this object? it blocks movement, but is NOT a wall/window/door/fence/player-build
local function isBlockingFurniture(obj)
    if not obj then return false end
    local props = spriteProps(obj)
    if not props then return false end
    if not hasAny(props, COLLIDE_FLAGS) then return false end   -- doesn't block -> nothing to do
    if hasAny(props, WALL_FLAGS) then return false end          -- structure -> never touch
    local bad = false
    pcall(function()
        if instanceof(obj, "IsoWindow") or instanceof(obj, "IsoDoor")
            or instanceof(obj, "IsoWindowFrame") or instanceof(obj, "IsoThumpable") then bad = true end
    end)
    return not bad
end

-- persistent state: stripped[name]="solid,collideW" (originals), solid[name]=true (forced solid)
local function store()
    local m = ModData.getOrCreate("EmpireWalkThrough")
    m.stripped = m.stripped or {}
    m.solid    = m.solid or {}
    return m
end

-- strip collide flags off a furniture sprite (records originals once). true if changed.
local function makeWalkable(obj)
    local name = spriteName(obj)
    if name == "" then return false end
    local m = store()
    if m.solid[name] then return false end
    local props = spriteProps(obj)
    if not props then return false end
    if not m.stripped[name] then
        local orig = {}
        for _, f in ipairs(COLLIDE_FLAGS) do
            local fl = flag(f)
            if fl and pIs(props, fl) then orig[#orig+1] = f end
        end
        if #orig == 0 then return false end
        m.stripped[name] = table.concat(orig, ",")
    end
    for _, f in ipairs(COLLIDE_FLAGS) do
        local fl = flag(f); if fl then pUnset(props, fl) end
    end
    return true
end

-- restore a single sprite to solid + blacklist it from future stripping
local function makeSolid(obj)
    local name = spriteName(obj)
    if name == "" then return false end
    local m = store()
    m.solid[name] = true
    local props = spriteProps(obj)
    local orig = m.stripped[name]
    if props and orig then
        for f in orig:gmatch("[^,]+") do
            local fl = flag(f); if fl then pSet(props, fl) end
        end
    end
    m.stripped[name] = nil
    local sq = nil
    pcall(function() sq = obj:getSquare() end)
    if sq then sq:RecalcProperties(); sq:RecalcAllWithNeighbours(true) end
    return true
end

-- AUTO pass: clear blocking furniture on every square as it streams in
local function processSquare(square)
    if not square then return end
    local objs = nil
    pcall(function() objs = square:getObjects() end)
    if not objs then return end
    local m = store()
    local changed = false
    for i = 0, objs:size() - 1 do
        local obj = objs:get(i)
        local name = spriteName(obj)
        if name ~= "" and not m.solid[name] then
            if m.stripped[name] then
                changed = true                 -- already stripped globally; refresh this tile's cache
            elseif isBlockingFurniture(obj) then
                if makeWalkable(obj) then changed = true end
            end
        end
    end
    if changed then
        square:RecalcProperties()
        square:RecalcAllWithNeighbours(true)
    end
end
Events.LoadGridsquare.Add(processSquare)

-- re-assert known strips at game start (sprites reload with original flags each launch);
-- the auto pass catches everything else as the map loads.
Events.OnGameStart.Add(function()
    local m = store()
    local n = 0
    for name, _ in pairs(m.stripped) do
        local props = propsForName(name)
        if props then
            for _, f in ipairs(COLLIDE_FLAGS) do
                local fl = flag(f); if fl then pUnset(props, fl) end
            end
            n = n + 1
        end
    end
    print(("[EmpireWalkThrough] ready. re-cleared %d known furniture sprite(s); auto-clears the rest as the map loads."):format(n))
end)

-- right-click escape hatch (+ optional identify probe under WT_DEBUG)
local function onFill(player, context, worldobjects, test)
    if test then return end
    local seen = {}
    for _, obj in ipairs(worldobjects) do
        local name = spriteName(obj)
        if name ~= "" and not seen[name] then
            seen[name] = true
            local m = store()
            if m.stripped[name] then
                context:addOption("Empire: keep this furniture solid", obj, function(o) makeSolid(o) end)
            end
            if WT_DEBUG then
                context:addOption("Empire: identify furniture (log)", obj, function(o)
                    print(("[wt-id] sprite=%s block=%s stripped=%s solid=%s"):format(
                        name, tostring(isBlockingFurniture(o)),
                        tostring(store().stripped[name] ~= nil), tostring(store().solid[name] == true)))
                end)
            end
        end
    end
end
Events.OnFillWorldObjectContextMenu.Add(onFill)

print("[EmpireWalkThrough] loaded.")
