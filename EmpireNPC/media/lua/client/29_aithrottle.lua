-- Empire NPC - Idle AI Throttle (FPS optimization, guarded)
-- SSC runs AIManager(taskManager) -- the full decide/scan brain -- for EVERY survivor EVERY update.
-- For a survivor just standing around at base with nothing nearby, that re-evaluation is wasted
-- CPU: their current task (guard/idle) keeps running regardless. So we wrap AIManager and, for
-- clearly-idle, danger-free, non-following survivors, run the heavy brain only 1 update in N and
-- skip the rest. The current TASK still updates every tick (they keep guarding/standing), and the
-- instant ANY danger is seen we stop throttling -- so combat reactions are never delayed.
-- Fail-open: any uncertainty -> run the real brain. Disable live with EmpireAIThrottle.ENABLED=false.

EmpireAIThrottle = EmpireAIThrottle or {}
EmpireAIThrottle.ENABLED    = true
EmpireAIThrottle.RUN_ONE_IN = 5     -- idle+safe survivors run the full brain 1 update in 5 (~80% less)

-- "standing around" tasks -- safe to throttle. Anything else (Attack/Pursue/Flee/Follow/Farming/
-- Forage/Walk/Find This/Eat/Heal...) always gets the full brain every tick.
local IDLE_TASKS = {
    ["None"] = true, ["Guard"] = true, ["Stand Ground"] = true,
    ["Wander In Area"] = true, ["Wander In Base"] = true, ["Relax"] = true,
}

local function shouldSkip(tm)
    if not EmpireAIThrottle.ENABLED then return false end
    if not tm then return false end
    local npc = tm.parent
    if not npc then return false end

    -- never throttle followers/companions -- they must stay responsive
    local follow = false;    pcall(function() follow = npc:needToFollow() end)
    if follow then return false end
    local companion = false;  pcall(function() companion = (npc:getGroupRole() == "Companion") end)
    if companion then return false end

    -- ANY danger seen -> full brain (this is the reactivity guarantee)
    local danger = 1;        pcall(function() danger = npc:getDangerSeenCount() end)
    if danger ~= 0 then return false end
    if npc.LastEnemeySeen ~= nil then return false end

    -- only throttle when genuinely standing around
    local task = "None";     pcall(function() task = tm:getCurrentTask() end)
    if not IDLE_TASKS[task] then return false end

    -- mid-action (eating, reloading, bandaging...) -> don't throttle
    local inAction = true;   pcall(function() inAction = npc:isInAction() end)
    if inAction then return false end

    -- run the full brain 1 update in N, skip the rest
    npc.__empAiTick = (npc.__empAiTick or 0) + 1
    if (npc.__empAiTick % EmpireAIThrottle.RUN_ONE_IN) == 0 then return false end
    return true
end

-- install the wrapper once, after SSC has defined the global AIManager
local function install()
    if EmpireAIThrottle._installed then return end
    if type(AIManager) ~= "function" then
        print("[EmpireNPC] AI Throttle: AIManager not found yet -- not installed.")
        return
    end
    local original = AIManager
    AIManager = function(tm)
        if shouldSkip(tm) then
            return tm            -- skip the brain; TaskManager still runs the current task. Return tm to match SSC.
        end
        return original(tm)
    end
    EmpireAIThrottle._installed = true
    print("[EmpireNPC] AI Throttle installed -- idle survivors run full AI 1 update in " .. EmpireAIThrottle.RUN_ONE_IN .. ".")
end

-- belt-and-suspenders on load order: try at boot and again at game start (install is idempotent)
Events.OnGameBoot.Add(install)
Events.OnGameStart.Add(install)
