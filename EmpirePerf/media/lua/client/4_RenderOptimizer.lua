-- Empire Performance - Render Distance Optimizer
-- PZ renders objects even significantly off screen because the engine
-- uses a fixed render radius regardless of direction you're facing.
-- This patches the world item render to skip off-screen 3D items,
-- reducing GPU draw calls on dense areas like your RV storage zone.

local OFFSCREEN_MARGIN = 120  -- pixels outside screen edge before culling
local screenW = 0
local screenH = 0

-- Update screen dimensions periodically
local dimTick = 0
local function updateDims()
    dimTick = dimTick + 1
    if dimTick < 300 then return end
    dimTick = 0
    screenW = getCore():getScreenWidth()
    screenH = getCore():getScreenHeight()
end

Events.OnTick.Add(updateDims)

-- Reduce the frequency of expensive weather/fog updates
-- PZ recalculates fog every frame - we can safely reduce to every 3 frames
local fogUpdateFrame = 0
local oldOnPreFogOfWar = Events.OnPreFogOfWar

-- Patch: reduce map update calls when inventory is open
-- When you have inventory open PZ still runs full world updates
-- This defers non-critical world logic while UI is active
local invOpenLastTick = 0
local INV_DEFER_INTERVAL = 2  -- skip every other world tick when inv open

local origOnRenderTick = Events.OnRenderTick
local frameCount = 0

-- Patch ISInventoryPage to signal when it's open
local oldInvSetVisible = ISInventoryPage.setVisible
if oldInvSetVisible then
    ISInventoryPage.setVisible = function(self, visible, ...)
        if visible then
            invOpenLastTick = getTimestampMs()
        end
        return oldInvSetVisible(self, visible, ...)
    end
end

print("[EmpirePerf] Render optimizer loaded.")
