-- ============================================================
-- Empire Sort - UI refresh shim  (separate file: does NOT touch the sorter)
-- ------------------------------------------------------------
-- F9 Smart Sort / END Consolidate move items into containers directly in Lua
-- (addItem / Remove). That correctly updates the container DATA -- which is why a
-- diag shows the shelf full -- but an inventory/loot window that is ALREADY OPEN
-- keeps drawing its cached (stale) item list, so a shelf you just filled still
-- shows as empty until you close + reopen it.
--
-- The sorter already calls container:setDrawDirty(true), but that only flags the
-- container's own redraw; the loot PAGE needs refreshBackpacks() to rebuild its
-- view. This shim does exactly that, a couple of ticks after F9/END (i.e. after
-- the sort has finished), so the open window updates on its own. Pure display --
-- it never reads, moves, or touches a single item.
-- ============================================================

-- Refresh BOTH layers of an open inventory page:
--   refreshBackpacks()             -> rebuilds the container/backpack tab buttons
--   inventoryPane:refreshContainer -> rebuilds the VISIBLE item list (this is the part that stayed
--                                     stale -- a shelf you just filled kept drawing its old, empty
--                                     item list until you closed + reopened it)
local function refreshOne(page)
    if not page then return end
    pcall(function() page:refreshBackpacks() end)
    pcall(function()
        if page.inventoryPane then page.inventoryPane:refreshContainer() end
    end)
end

local function refreshInventoryUI()
    refreshOne(getPlayerLoot(0))       -- right-hand loot window (the shelf you're looking into)
    refreshOne(getPlayerInventory(0))  -- left-hand player inventory
end

-- Deferred fire: arm a tiny countdown on F9/END, refresh when it hits 0. Deferring
-- a couple ticks guarantees we run AFTER the sorter's own key handler completes,
-- no matter which handler the engine fires first.
local ticksLeft = 0

local function onTick()
    if ticksLeft <= 0 then return end          -- idle: one int compare per frame
    ticksLeft = ticksLeft - 1
    if ticksLeft == 0 then refreshInventoryUI() end
end
Events.OnTick.Add(onTick)

local function onKeyPressed(key)
    if key == Keyboard.KEY_NUMPAD3 or key == Keyboard.KEY_NUMPAD4 then
        local p = getSpecificPlayer(0)
        if p and not p:isDead() then ticksLeft = 2 end
    end
end
Events.OnKeyPressed.Add(onKeyPressed)

print("[EmpireSortAll] UI-refresh shim loaded (open inventory window refreshes after F9/END).")
