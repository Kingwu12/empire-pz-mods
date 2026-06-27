-- Empire QoL - No Sleep Confirmation
-- Skips the "Do you want to sleep?" popup. Choosing Sleep on a bed just sleeps
-- (walks to the bed first if needed) -- exactly as if you clicked Yes.

Events.OnGameStart.Add(function()
    if not (ISWorldObjectContextMenu and ISWorldObjectContextMenu.onSleep
            and ISWorldObjectContextMenu.onConfirmSleep) then return end
    local orig = ISWorldObjectContextMenu.onSleep
    ISWorldObjectContextMenu.onSleep = function(bed, player)
        local ok = pcall(function()
            ISWorldObjectContextMenu.onConfirmSleep(nil, { internal = "YES" }, player, bed)
        end)
        if not ok then orig(bed, player) end
    end
    print("[EmpireQoL] No Sleep Confirmation loaded.")
end)
