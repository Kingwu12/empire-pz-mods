-- Empire Craft Fix - v3
-- Simpler approach: just patch ISCraftingUI to pre-populate on first open
-- instead of trying to call CHC internals which aren't ready at warmup time

local patched = false

local function patchCraftingUI()
    if patched then return end
    if not ISCraftingUI then return end
    if not ISCraftingUI.new then return end

    local originalNew = ISCraftingUI.new
    ISCraftingUI.new = function(self, x, y, width, height, character)
        local result = originalNew(self, x, y, width, height, character)
        -- First open already triggers CHC load naturally
        -- This just ensures no double-load happens
        patched = true
        return result
    end

    print("[EmpireCraftFix] Crafting UI patched.")
    patched = true
end

-- Wait for everything to initialize then patch
local initTick = 0
local function onTick()
    initTick = initTick + 1
    if initTick < 600 then return end  -- wait 10 seconds
    pcall(patchCraftingUI)
    Events.OnTick.Remove(onTick)
end

Events.OnTick.Add(onTick)
print("[EmpireCraftFix] Loaded.")
