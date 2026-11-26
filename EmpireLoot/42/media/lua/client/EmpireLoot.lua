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
local tickArmed = false
local tryPendingEngineStart  -- forward decl: armed from the enter event, removes itself after one run

-- Perf (42.22 pass): the tick handler used to sit on OnTick for the whole session doing a
-- nil check every frame. It is now registered only between "entered a vehicle" and the one
-- tick that follows, so it costs nothing while walking, building or fighting.
local function onPlayerEnterVehicle(player)
    if player and player:getPlayerNum() == 0 then
        pendingEngineStart = player
        if not tickArmed then
            tickArmed = true
            Events.OnTick.Add(tryPendingEngineStart)
        end
    end
end

tryPendingEngineStart = function()
    Events.OnTick.Remove(tryPendingEngineStart)
    tickArmed = false
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

if Events.OnEnterVehicle then Events.OnEnterVehicle.Add(onPlayerEnterVehicle) end

print("[EmpireLoot] Loaded (auto engine start only; loot filter + trailer transfer retired).")
