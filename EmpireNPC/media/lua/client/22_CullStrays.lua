-- Empire NPC - Cull Strays  (TEMPORARY recovery sweep)
-- The 40% spawn-rate session bred ~26 survivor records into the save. SSC simulates whatever's
-- in loaded chunks every tick -> the FPS crash. This clears every NON-CREW survivor (anyone not
-- in the player's group / Page-Up list) using SSC's own deleteSurvivor(). It runs once ~15s
-- after load, then periodically, to catch the backlog as chunks stream in while travelling.
-- This is a RECOVERY tool for King's over-spawn, NOT a permanent mechanic -- once the backlog
-- is gone and FPS is confirmed, this file gets switched back off so the world stays natural.
-- Crew (same group as the player) are NEVER touched. If the group can't be read, it does NOTHING.

require "EmpireNPC_Shared"

local function cull()
    -- DISABLED 2026-06-25: this TEMPORARY over-spawn recovery tool was deleting too aggressively.
    -- Its crew-protection ("if g == myGroup keep") FAILS OPEN: when a crew member's getGroupID()
    -- read transiently throws (expedition / chunk streaming), g stays nil, nil ~= myGroup, and the
    -- crew member gets DELETED -- corrupting the group (empty Page-Up list), orphaning followers
    -- (expedition guys scatter), and leaving nameless ghost bodies. Backlog already cleared (was
    -- 26, now ~8). Hard-OFF. Do NOT re-enable without rewriting the crew gate to FAIL CLOSED.
    do return end
    if not SSM or not SSM.SuperSurvivors then return end
    local mainID = nil
    pcall(function() mainID = SSM.MainPlayer end)
    local myGroup = nil
    -- nil-check the slot object BEFORE indexing it: SSM:Get() returns null while the player's
    -- survivor session isn't ready (chunk streaming), and :getGroupID() on null throws an
    -- exception the VM logs every time even under pcall. Splitting the call kills the spam.
    pcall(function()
        local mp = SSM:Get(mainID or 0)
        if mp then myGroup = mp:getGroupID() end
    end)
    -- SAFETY: no group reference = we cannot tell crew from stray. Abort rather than risk
    -- deleting Kristy or any recruited crew on a transient nil.
    if myGroup == nil then return end
    local playerObj = getSpecificPlayer(0)

    local removed = 0
    for id, ss in pairs(SSM.SuperSurvivors) do
        if ss and id ~= mainID then
            local skip = false
            local ch = nil
            pcall(function() ch = ss:Get() end)
            if ch == playerObj then skip = true end          -- never the human player
            if not skip then
                local g = nil
                pcall(function() g = ss:getGroupID() end)
                if g == myGroup then skip = true end          -- crew: keep
            end
            if not skip then
                local ok = pcall(function() ss:deleteSurvivor() end)
                SSM.SuperSurvivors[id] = nil
                if ok then removed = removed + 1 end
            end
        end
    end
    if removed > 0 then
        print("[EmpireCull] removed " .. removed .. " stray survivor(s) (non-crew).")
        local p = getSpecificPlayer(0)
        if p then pcall(function()
            HaloTextHelper.addText(p, "Cleared " .. removed .. " strays", HaloTextHelper.getColorWhite())
        end) end
    end
end

-- one-time pass ~15s after load (let SSC finish registering survivors first)
local started = nil
local function delayedFirst()
    if not started then started = getTimestampMs() end
    if getTimestampMs() - started >= 15000 then
        Events.OnTick.Remove(delayedFirst)
        pcall(cull)
    end
end
Events.OnTick.Add(delayedFirst)

-- periodic recovery sweep: catches the backlog as chunks stream in while travelling
local lastSweep = 0
Events.OnPlayerUpdate.Add(function()
    local now = getTimestampMs()
    if now - lastSweep < 20000 then return end
    lastSweep = now
    pcall(cull)
end)

print("[EmpireNPC] Cull Strays (recovery) loaded -- clearing the over-spawn backlog.")
