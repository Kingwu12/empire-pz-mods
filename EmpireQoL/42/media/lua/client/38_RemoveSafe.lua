-- Empire QoL - Remove Safe
-- Police-station safes (and other safe/vault/strongbox objects) you can't open or pick up
-- are just map clutter. Right-click one -> "Empire: Remove safe" to disassemble it, clear
-- the tile, and get a little scrap metal back.
--
-- Detection is by SPRITE NAME, so the option only ever appears on actual safe-type objects,
-- never on your walls or storage. If a safe in YOUR game isn't caught: leave SAFE_DEBUG = true,
-- right-click it, choose "Empire: identify object (log)", and read the sprite name printed to
-- the console -- then add that substring to SAFE_SPRITES below (and flip SAFE_DEBUG off).

local SAFE_SPRITES = { "safe", "vault", "strongbox" }  -- sprite-name substrings (lowercased)
-- EXACT sprite names for decorative "safes" that are just map tiles (no container, no name
-- with "safe" in it). Must be exact -- the bank tilesheet also holds walls/floors/counters,
-- so we can't match the prefix. Add more here as you identify them with the probe.
local SAFE_SPRITES_EXACT = {
    ["location_business_bank_01_68"] = true,   -- police/bank decorative safe (variant A)
    ["location_business_bank_01_69"] = true,   -- police/bank decorative safe (variant B, upstairs)
}
local SCRAP_GIVEN  = 3                                  -- ScrapMetal returned per safe (0 = none)
local SAFE_DEBUG   = true                               -- true -> adds an "identify object" probe

local function spriteName(obj)
    local n = ""
    pcall(function() n = obj:getSprite():getName() or "" end)
    return n
end

local function isSafe(obj)
    if not obj then return false end
    local raw = spriteName(obj)
    if SAFE_SPRITES_EXACT[raw] then return true end   -- exact decorative-safe tiles
    local n = raw:lower()
    if n ~= "" then
        for _, w in ipairs(SAFE_SPRITES) do if n:find(w, 1, true) then return true end end
    end
    -- also catch a container literally typed "safe"
    local ct = nil
    pcall(function() local c = obj:getContainer(); if c then ct = c:getType() end end)
    if ct and tostring(ct):lower():find("safe", 1, true) then return true end
    return false
end

-- is `obj` still listed on the square's object stack? (used to verify a removal worked)
local function stillOnSquare(sq, obj)
    local found = false
    pcall(function()
        local objs = sq:getObjects()
        for i = 0, objs:size() - 1 do if objs:get(i) == obj then found = true; break end end
    end)
    return found
end

local function removeOne(player, sq, obj)
    -- dump any container contents first so nothing is silently lost (these safes are
    -- container=nil, but guard anyway). Fully pcall'd.
    pcall(function()
        local c = obj:getContainer()
        if c then
            local items = c:getItems()
            for i = items:size() - 1, 0, -1 do
                local it = items:get(i)
                pcall(function() sq:AddWorldInventoryItem(it, 0.5, 0.5, 0); c:Remove(it) end)
            end
        end
    end)
    local sprite = spriteName(obj)
    pcall(function() sq:transmitRemoveItemFromSquare(obj) end)          -- 1) standard persisting removal
    if stillOnSquare(sq, obj) then pcall(function() sq:RemoveTileObject(obj) end) end  -- 2) local stack removal
    if stillOnSquare(sq, obj) then                                       -- 3) last-ditch
        pcall(function() sq:transmitRemoveItemFromSquare(obj) end)
        pcall(function() obj:removeFromWorld() end)
        pcall(function() obj:removeFromSquare() end)
    end
    local gone = not stillOnSquare(sq, obj)
    print("[EmpireQoL][safe-rm] sprite='" .. sprite .. "' removed=" .. tostring(gone))
    return gone
end

local function removeSafe(player, obj)
    if not player or not obj then return end
    local sq = nil; pcall(function() sq = obj:getSquare() end)
    if not sq then
        pcall(function() HaloTextHelper.addTextWithArrow(player, "No square under that object", "[br/]", false, HaloTextHelper.getColorRed()) end)
        return
    end
    -- remove EVERY safe-matching object on the square (covers 2-tile / stacked safes)
    local targets = { obj }
    pcall(function()
        local objs = sq:getObjects()
        for i = 0, objs:size() - 1 do
            local o = objs:get(i)
            if o ~= obj and isSafe(o) then targets[#targets + 1] = o end
        end
    end)
    local removed = 0
    for _, o in ipairs(targets) do if removeOne(player, sq, o) then removed = removed + 1 end end
    if removed > 0 and SCRAP_GIVEN > 0 then
        pcall(function() for _ = 1, SCRAP_GIVEN do player:getInventory():AddItem("Base.ScrapMetal") end end)
    end
    pcall(function()
        local ok  = removed > 0
        local col = ok and HaloTextHelper.getColorGreen() or HaloTextHelper.getColorRed()
        local msg = ok and ("Safe removed (" .. removed .. ")") or "Couldn't remove - see console [safe-rm]"
        HaloTextHelper.addTextWithArrow(player, msg, "[br/]", false, col)
    end)
end

local function identify(player, list)
    print("[EmpireQoL][safe-id] ---- tile dump: " .. #list .. " object(s) ----")
    for i, obj in ipairs(list) do
        local ct = nil; pcall(function() local c = obj:getContainer(); if c then ct = c:getType() end end)
        local pos = "?"
        pcall(function() local s = obj:getSquare(); if s then pos = s:getX()..","..s:getY()..","..s:getZ() end end)
        print("[EmpireQoL][safe-id]   ["..i.."] sprite='" .. spriteName(obj) .. "' container=" .. tostring(ct)
            .. " isSafe=" .. tostring(isSafe(obj)) .. " sq=" .. pos)
    end
    pcall(function() HaloTextHelper.addTextWithArrow(player, #list .. " object(s) logged to console", "[br/]", false, HaloTextHelper.getColorWhite()) end)
end

local function onFill(playerNum, context, worldobjects, test)
    if test then return end
    local player = getSpecificPlayer(playerNum)
    if not player then return end
    -- de-dupe objects under the cursor; collect any safes
    local safes, all, seen = {}, {}, {}
    for _, obj in ipairs(worldobjects) do
        if obj and not seen[obj] then
            seen[obj] = true
            all[#all + 1] = obj
            if isSafe(obj) then safes[#safes + 1] = obj end
        end
    end
    if #safes > 0 then
        -- one option; removeSafe clears every safe-matching object on that square
        context:addOption("Empire: Remove safe", player, removeSafe, safes[1])
    end
    -- discovery probe: available whenever debugging, so you can inspect a tile even when the
    -- Remove option already shows (e.g. it appears but removal silently fails on a baked tile).
    if SAFE_DEBUG and #all > 0 then
        context:addOption("Empire: identify object (log)", player, identify, all)
    end
end

Events.OnFillWorldObjectContextMenu.Add(onFill)

print("[EmpireQoL] Remove Safe loaded: right-click a safe -> Empire: Remove safe.")
