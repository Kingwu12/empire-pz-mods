-- Empire Loot - Auto Engine Start
-- (Trimmed 2026-07-02: the Numpad5 loot filter and Numpad6 trailer transfer were
--  REMOVED by request -- King loots and loads manually. The Loot-All hook that the
--  filter wrapped around ISInventoryPaneContextMenu.transferAllItems is gone too,
--  so Loot All is pure vanilla again. Numpad5/6 are now free keys.)

EmpireLoot = EmpireLoot or {}

-- =============================================
-- AUTO ENGINE START ON ENTRY
-- =============================================
-- Defer the engine start to the next tick. Entering fires this event DURING the
-- enter-vehicle animation (alongside Superb Survivors + the DAMN anim library), and
-- starting the engine synchronously there threw an error on every entry. One tick
-- later the seat/driver state is settled, so we gate on the same checks the base
-- game's start-engine action uses -- no more error spam, and it actually starts.
local pendingEngineStart = nil

local function onPlayerEnterVehicle(player)
    if player and player:getPlayerNum() == 0 then
        pendingEngineStart = player
    end
end

local function tryPendingEngineStart()
    local player = pendingEngineStart
    if not player then return end
    pendingEngineStart = nil
    pcall(function()
        local vehicle = player:getVehicle()
        if not vehicle then return end
        if not vehicle:isDriver(player) then return end                       -- driver only
        if vehicle:isEngineRunning() or vehicle:isEngineStarted() then return end
        ISVehicleMenu.onStartEngine(player)
        HaloTextHelper.addTextWithArrow(player, "Engine on", "[br/]", false, HaloTextHelper.getColorWhite())
    end)
end

Events.OnTick.Add(tryPendingEngineStart)
if Events.OnEnterVehicle then Events.OnEnterVehicle.Add(onPlayerEnterVehicle) end

print("[EmpireLoot] Loaded (auto engine start only; loot filter + trailer transfer retired).")
