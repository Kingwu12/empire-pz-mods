-- Empire NPC - NPC Scanner (robust enumeration)
-- Enumerates SSC's loaded survivors via pairs() over SSM.SuperSurvivors instead of a numeric
-- 0..SurvivorCount loop. SSC stores survivors in a table keyed by ID; deaths leave nil holes
-- and recruited/spawned survivors can sit at high/sparse IDs, so the numeric loop was missing
-- them and registering NOBODY. pairs() catches every loaded survivor regardless of ID. We skip
-- only the actual human player (SSM.MainPlayer slot / the local player character) -- nothing
-- else is excluded. A count line prints each scan so we can confirm it's finding your crew.

require "EmpireNPC_Shared"

local SCAN_INTERVAL = 300
local scanTick = 0
local lastReported = -1

local function getActiveSurvivors()
    local survivors = {}
    if not SSM or not SSM.SuperSurvivors then return survivors end
    local playerObj = getSpecificPlayer(0)
    local mainID = nil
    pcall(function() mainID = SSM.MainPlayer end)   -- player's slot (usually 0)
    -- ONLY manage YOUR crew: survivors in the player's group (the Page-Up list). Random map
    -- wanderers (not recruited) are ignored -- we never arm/dress/role/tag them.
    local myGroup = nil
    -- SSM:Get(slot) returns null when the player has no survivor session in that slot yet
    -- (early load, or not in an SSC group). Calling :getGroupID() on that null is what spammed
    -- "attempted index: getGroupID of non-table: null" every tick -- pcall caught it but the VM
    -- logs caught exceptions anyway, so we nil-check the object instead of just wrapping it.
    pcall(function()
        local mp = SSM:Get(mainID or 0)
        if mp then myGroup = mp:getGroupID() end
    end)

    for id, ss in pairs(SSM.SuperSurvivors) do
        if ss and id ~= mainID then
            local skip, dead, ch = false, false, nil
            pcall(function() ch = ss:Get() end)
            if ch == playerObj then skip = true end          -- never the human player
            -- group gate: must share the player's group, else it's a random survivor
            if not skip then
                local g = nil
                pcall(function() g = ss:getGroupID() end)
                if myGroup == nil or g == nil or g ~= myGroup then skip = true end
            end
            if not skip then pcall(function() dead = ss:isDead() end) end
            -- require a loaded character so we only manage survivors actually in the world
            if not skip and not dead and ch then
                table.insert(survivors, ss)
            end
        end
    end
    return survivors
end

EmpireNPC.getActiveSurvivors = getActiveSurvivors

local function syncSurvivors()
    if not SSM then return end
    local survivors = getActiveSurvivors()
    local n = 0
    for _, ss in ipairs(survivors) do
        pcall(function()
            local name = ss:getName() or ""
            if name ~= "" then
                local s = EmpireNPC.getSettler(name)
                s.name = name
                n = n + 1
            end
        end)
    end
    if n ~= lastReported then
        lastReported = n
        print("[EmpireNPC] Scanner: " .. n .. " survivor(s) registered & managed.")
    end
end

EmpireNPC.syncSurvivors = syncSurvivors

local function onTick()
    scanTick = scanTick + 1
    if scanTick < SCAN_INTERVAL then return end
    scanTick = 0
    pcall(syncSurvivors)
end
Events.OnTick.Add(onTick)

Events.OnGameStart.Add(function()
    EmpireNPC.loadData()
    local initTick = 0
    local function initScan()
        initTick = initTick + 1
        if initTick > 180 then
            pcall(syncSurvivors)
            Events.OnTick.Remove(initScan)
        end
    end
    Events.OnTick.Add(initScan)
end)

print("[EmpireNPC] NPC Scanner loaded (pairs-enumeration).")
