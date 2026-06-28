-- Empire QoL - Delete Item(s)
-- Right-click any inventory item -> "Delete" to permanently destroy it. Works on a single
-- item, a whole stack, or a multi-selection -- for clearing junk and over-stacked clutter fast.
-- Asks once to confirm by default so a misclick can't nuke your good gear. Set CONFIRM = false
-- below if you want instant deletes with no prompt.

local CONFIRM = true

-- Flatten whatever the context menu handed us (single items + stacks) into a flat item list.
-- PZ can hand us the SAME item twice -- once standalone and once inside its stack wrapper --
-- so we dedupe by item identity (a set), exactly like vanilla's ISRemoveItemTool. Without this,
-- a single item would count as 2.
local function collectItems(items)
    local seen, out = {}, {}
    local function add(it)
        if instanceof(it, "InventoryItem") and not seen[it] then
            seen[it] = true
            out[#out + 1] = it
        end
    end
    for _, v in ipairs(items) do
        if instanceof(v, "InventoryItem") then
            add(v)
        elseif type(v) == "table" and v.items then
            for _, it in ipairs(v.items) do add(it) end
        end
    end
    return out
end

local function doDelete(player, list)
    if not player or not list then return end
    local n = 0
    for _, it in ipairs(list) do
        pcall(function()
            -- drop it out of hands / off the body first so nothing keeps holding a reference
            if player:getPrimaryHandItem() == it then player:setPrimaryHandItem(nil) end
            if player:getSecondaryHandItem() == it then player:setSecondaryHandItem(nil) end
            local bl = nil; pcall(function() bl = it:getBodyLocation() end)
            if bl and bl ~= "" then pcall(function() player:setWornItem(bl, nil) end) end
            local c = it:getContainer()
            if c then c:Remove(it) end
            n = n + 1
        end)
    end
    if n > 0 then
        pcall(function()
            HaloTextHelper.addTextWithArrow(player, "Deleted " .. n .. " item" .. (n == 1 and "" or "s"), "[br/]", false, HaloTextHelper.getColorRed())
        end)
    end
end

local function onConfirm(target, button)
    if button and button.internal == "YES" then
        doDelete(target.player, target.list)
    end
end

local function onDelete(player, list)
    if not CONFIRM then doDelete(player, list); return end
    local label = #list .. " item" .. (#list == 1 and "" or "s")
    local w, h = 320, 130
    local x = (getCore():getScreenWidth() - w) / 2
    local y = (getCore():getScreenHeight() - h) / 2
    local modal = ISModalDialog:new(x, y, w, h,
        "Delete " .. label .. "?  This cannot be undone.", true,
        { player = player, list = list }, onConfirm)
    modal:initialise()
    modal:addToUIManager()
end

local function onFill(playerNum, context, items)
    local player = getSpecificPlayer(playerNum)
    if not player then return end
    local list = collectItems(items)
    if #list == 0 then return end
    local label = (#list == 1) and "Delete" or ("Delete " .. #list .. " items")
    context:addOption(label, player, onDelete, list)
end

Events.OnFillInventoryObjectContextMenu.Add(onFill)

print("[EmpireQoL] Delete Item(s) loaded: right-click inventory -> Delete.")
