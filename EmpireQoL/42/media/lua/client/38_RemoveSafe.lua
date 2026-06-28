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
local SCRAP_GIVEN  = 3                                  -- ScrapMetal returned per safe (0 = none)
local SAFE_DEBUG   = true                               -- true -> adds an "identify object" probe

local function spriteName(obj)
    local n = ""
    pcall(function() n = obj:getSprite():getName() or "" end)
    return n
end

local function isSafe(obj)
    if not obj then return false end
    local n = spriteName(obj):lower()
    if n ~= "" then
        for _, w in ipairs(SAFE_SPRITES) do if n:find(w, 1, true) then return true end end
    end
    -- also catch a container literally typed "safe"
    local ct = nil
    pcall(function() local c = obj:getContainer(); if c then ct = c:getType() end end)
    if ct and tostring(ct):lower():find("safe", 1, true) then return true end
    return false
end

local function removeSafe(player, obj)
    if not player or not obj then return end
    local sq = nil; pcall(function() sq = obj:getSquare() end)
    if not sq then return end
    -- dump any (inaccessible) container contents onto the floor so nothing is silently lost.
    -- Fully guarded: if the drop call mismatches, we just skip dumping and still remove.
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
    -- a heavy metal box is worth some scrap
    if SCRAP_GIVEN > 0 then
        pcall(function()
            for _ = 1, SCRAP_GIVEN do player:getInventory():AddItem("Base.ScrapMetal") end
        end)
    end
    -- remove the object from the world (standard square removal path)
    pcall(function() sq:transmitRemoveItemFromSquare(obj) end)
    pcall(function() HaloTextHelper.addTextWithArrow(player, "Safe removed", "[br/]", false, HaloTextHelper.getColorGreen()) end)
end

local function identify(player, list)
    for _, obj in ipairs(list) do
        local ct = nil; pcall(function() local c = obj:getContainer(); if c then ct = c:getType() end end)
        print("[EmpireQoL][safe-id] sprite='" .. spriteName(obj) .. "' container=" .. tostring(ct))
    end
    pcall(function() HaloTextHelper.addTextWithArrow(player, "Object sprites logged to console", "[br/]", false, HaloTextHelper.getColorWhite()) end)
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
    for _, obj in ipairs(safes) do
        context:addOption("Empire: Remove safe", player, removeSafe, obj)
    end
    -- discovery probe: only while debugging, and only when nothing was auto-detected on this
    -- tile (so once detection works for your safes, this never clutters the menu again).
    if SAFE_DEBUG and #safes == 0 and #all > 0 then
        context:addOption("Empire: identify object (log)", player, identify, all)
    end
end

Events.OnFillWorldObjectContextMenu.Add(onFill)

print("[EmpireQoL] Remove Safe loaded: right-click a safe -> Empire: Remove safe.")
