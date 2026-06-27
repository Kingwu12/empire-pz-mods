-- Empire NPC - Role Sync (drives the SSC Page-Up survivor table)
-- Instead of floating text, this writes each survivor's empire role into SSC's own GroupRole
-- field -- which is exactly the column SSC's Page-Up survivor window already displays. So you
-- open Page-Up and see every survivor with their role (Guard / Medic / Warden / Looter /
-- Farmer), live, in SSC's native table. Survivors with no empire role yet are set to "Worker"
-- so SSC's AI auto-works them (forage/sort/guard-area) instead of standing idle.
--
-- Recognised SSC roles (Guard, Worker, Doctor) also trigger SSC's matching AI; the rest just
-- display + fall back to EmpireNPC's own role behaviour (2_RoleBehaviours) + generic wander.

require "EmpireNPC_Shared"

local SYNC_MS = 8000
local lastSync = 0

-- empire role -> the string we write into SSC GroupRole (shown in the Page-Up table)
local function sscRoleFor(empireRole)
    if empireRole == nil or empireRole == "" or empireRole == "Settler" then
        local w = "Worker"
        pcall(function() if Get_SS_JobText then w = Get_SS_JobText("Worker") end end)
        return w
    end
    if empireRole == "Medic" then
        local d = "Doctor"
        pcall(function() if Get_SS_JobText then d = Get_SS_JobText("Doctor") end end)
        return d   -- Doctor = SSC's healer AI; EmpireNPC medic behaviour also runs
    end
    return empireRole   -- Guard / Warden / Looter / Farmer -- displayed as-is
end

local function isFollowing(ss)
    local m; pcall(function() m = ss:getAIMode() end)
    return m == "Follow"
end

local function onTick()
    local now = getTimestampMs()
    if now - lastSync < SYNC_MS then return end
    lastSync = now
    local survs = (EmpireNPC.getActiveSurvivors and EmpireNPC.getActiveSurvivors()) or {}
    for _, ss in ipairs(survs) do
        if not isFollowing(ss) then
            pcall(function()
                local name = ss:getName() or ""
                local settler = (name ~= "" and EmpireNPC.getSettler) and EmpireNPC.getSettler(name) or nil
                local empRole = settler and settler.role or nil
                local target = sscRoleFor(empRole)
                local cur = ss:getGroupRole()
                if cur ~= target then ss:setGroupRole(target) end
            end)
        end
    end
end

Events.OnPlayerUpdate.Add(function() pcall(onTick) end)
print("[EmpireNPC] Role Sync loaded. Empire roles now show in the SSC Page-Up survivor table.")
