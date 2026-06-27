-- Empire NPC - Fill Crew (manual, key-triggered recovery spawner)
-- The CullStrays incident deleted real crew; those specific survivors are gone. This restores
-- HEADCOUNT. Stand at base and press the key: it spawns fresh survivors STRAIGHT INTO YOUR
-- GROUP until you're back to TARGET, using SSC's own verified spawn + addMember path (the same
-- one the wife-spawn uses). ADDITIVE ONLY -- it never deletes. It NEVER runs on its own; you
-- trigger it. Spawned crew start as followers -- reassign them (garrison/farm/cook) via the
-- normal Empire role menu afterwards.

local TARGET        = 10                   -- bring the group up to this many
local SPAWN_KEY     = Keyboard.KEY_INSERT  -- press at base to top up
local MAX_PER_PRESS = 10                   -- hard safety cap per press

local function currentCrew()
    local n = 0
    pcall(function()
        if EmpireNPC and EmpireNPC.getActiveSurvivors then
            n = #EmpireNPC.getActiveSurvivors()
        end
    end)
    return n
end

-- Spawn ONE survivor straight into the player's group. Mirrors SSC's own wife-spawn path
-- exactly, so it uses only APIs SSC itself relies on. Fully guarded: any failure spawns nobody
-- rather than corrupting anything.
local function spawnAlly(player)
    local ok = false
    pcall(function()
        local sq = player:getCurrentSquare()
        if not sq then return end
        local ss = SSM:spawnSurvivor(nil, sq)      -- nil = random gender
        if not ss then return end
        local ch = ss:Get()
        if ch then
            local md = ch:getModData()
            md.MetPlayer = true
            md.isHostile = false
        end
        -- get the player's group, or create it with the player as Leader (SSC's pattern)
        local Group
        local mp = SSM:Get(0)
        if not mp then return end
        if mp:getGroupID() == nil then
            Group = SSGM:newGroup()
            Group:addMember(mp, "Leader")
        else
            Group = SSGM:GetGroupById(mp:getGroupID())
        end
        if not Group then return end
        Group:addMember(ss, Get_SS_JobText("Companion"))
        -- follow so they're clearly yours and walk home with you; reassign roles afterwards
        local ft = FollowTask:new(ss, getSpecificPlayer(0))
        if ft then
            ss:setAIMode("Follow")
            ss:getTaskManager():AddToTop(ft)
        end
        ok = true
    end)
    return ok
end

local function fillCrew()
    local player = getSpecificPlayer(0)
    if not player or player:isDead() then return end
    if not (SSM and SSGM) then
        print("[EmpireNPC FillCrew] SSC not ready -- try again in a few seconds.")
        return
    end
    local have = currentCrew()
    local need = TARGET - have
    if need <= 0 then
        pcall(function() HaloTextHelper.addText(player, "Crew already at " .. have, HaloTextHelper.getColorWhite()) end)
        return
    end
    if need > MAX_PER_PRESS then need = MAX_PER_PRESS end
    local made = 0
    for i = 1, need do
        if spawnAlly(player) then made = made + 1 end
    end
    print("[EmpireNPC FillCrew] spawned " .. made .. " into your group (had " .. have .. ", target " .. TARGET .. ").")
    pcall(function()
        HaloTextHelper.addText(player, "Recruited " .. made .. " -- crew ~" .. (have + made), HaloTextHelper.getColorGreen())
    end)
end

local function onKey(key)
    if key == SPAWN_KEY then pcall(fillCrew) end
end
Events.OnKeyPressed.Add(onKey)

print("[EmpireNPC] Fill Crew loaded -- press INSERT at base to top your group up to " .. TARGET .. " (additive, never deletes).")
