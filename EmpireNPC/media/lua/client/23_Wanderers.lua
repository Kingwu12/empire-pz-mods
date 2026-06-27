-- Empire NPC - Wanderers (settlers find your base and join)
-- The missing population SOURCE. CullStrays caps the world to your crew; Garrison arms &
-- assigns your crew. This brings friendly survivors TO the base when you're short-handed and
-- home, then immediately enrolls them in your crew so (a) the cull spares them and (b) the
-- garrison auto-arms/dresses/deploys them. No cheat-click: they arrive on their own, drawn to
-- an established settlement, capped at your group max. Built entirely on SSC's own spawn
-- primitives (SuperSurvivorSpawnNpcAtSquare / setHostile / group:addMember). All pcall'd.

EmpireWanderers = EmpireWanderers or {}
EmpireWanderers.ENABLED = true

local TARGET_CREW   = 10    -- keep the settlement at up to this many (incl. you). Your group max.
local ARRIVAL_PCT   = 40    -- % chance per in-game hour that a settler arrives while you're short & home
local DIST_MIN      = 8     -- they appear at the edge of view and walk in, not on top of you
local DIST_MAX      = 14

local function playerSS()
    if not SSM then return nil end
    local me = nil
    pcall(function() me = SSM:Get(SSM.MainPlayer or 0) end)
    return me
end
-- the player's crew group (create one with you as leader if you don't have a group yet)
local function getCrewGroup()
    local me = playerSS()
    if not me then return nil, nil end
    local g, gid
    pcall(function() g = me:getGroup() end)
    pcall(function() gid = me:getGroupID() end)
    if g and gid then return g, gid end
    pcall(function()
        g = SSGM:newGroup()
        if g then
            g:addMember(me, "Leader")
            if g.setLeader then pcall(function() g:setLeader(0) end) end
        end
    end)
    pcall(function() gid = me:getGroupID() end)
    return g, gid
end

-- how many survivors are currently in your crew (counts you)
local function crewCount(gid)
    local n = 0
    if not (SSM and SSM.SuperSurvivors) then return 0 end
    for _, ss in pairs(SSM.SuperSurvivors) do
        if ss then
            local g = nil
            pcall(function() g = ss:getGroupID() end)
            if g == gid then n = n + 1 end
        end
    end
    return n
end

-- only bring settlers while you're actually at a defined base
local function atBase(p)
    if not (EmpireBases and EmpireBases.activeBase) then return true end
    local b = nil
    pcall(function() b = EmpireBases.activeBase(p) end)
    return b ~= nil
end

-- a free tile a short distance from you, so they walk in from the edge
local function pickSpawnSquare(p)
    local cell = getCell(); if not cell then return nil end
    local px, py, pz = math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ())
    for _ = 1, 30 do
        local dist = ZombRand(DIST_MIN, DIST_MAX + 1)
        local ang  = ZombRand(0, 360) * math.pi / 180
        local sq = cell:getGridSquare(px + math.floor(dist * math.cos(ang)),
                                      py + math.floor(dist * math.sin(ang)), pz)
        local free = false
        pcall(function() free = sq and sq:isFree(true) end)
        if free then return sq end
    end
    return nil
end
-- spawn ONE friendly settler at a base-edge tile and enroll them in your crew
local function spawnSettler(p, group)
    local sq = pickSpawnSquare(p)
    if not sq then return false end
    local npc = nil
    pcall(function() npc = SuperSurvivorSpawnNpcAtSquare(sq) end)
    if not npc then return false end
    pcall(function() npc:setHostile(false) end)                       -- friendly, never attacks you
    pcall(function() if npc.player then npc.player:getModData().isRobber = false end end)
    pcall(function() Equip_SS_RandomNpc(npc, false) end)
    pcall(function() GetRandomSurvivorSuit(npc) end)
    pcall(function() npc:setName("Settler " .. npc:getName()) end)
    pcall(function() group:addMember(npc, "Follower") end)            -- crew: cull spares them, garrison equips them
    pcall(function() npc:NPCTask_DoWander() end)
    return true
end

-- the organic trickle: while you're home and short-handed, a settler may wander in each hour
local function maintain()
    if not EmpireWanderers.ENABLED then return end
    if not (SSM and SSGM) then return end
    local p = getSpecificPlayer(0)
    if not p or p:isDead() then return end
    if not atBase(p) then return end
    local group, gid = getCrewGroup()
    if not group or not gid then return end
    if crewCount(gid) >= TARGET_CREW then return end
    if ZombRand(0, 100) >= ARRIVAL_PCT then return end
    if spawnSettler(p, group) then
        pcall(function()
            HaloTextHelper.addText(p, "A settler found your base", HaloTextHelper.getColorGreen())
        end)
        print("[EmpireWanderers] a settler arrived and joined the crew.")
    end
end

Events.EveryHours.Add(maintain)

-- Manual verify/top-up: run EmpireBringSettlers(n) to pull up to n settlers in now (respects the
-- cap). Use it once to confirm they spawn friendly and join; the hourly trickle does the rest.
function EmpireBringSettlers(n)
    n = tonumber(n) or 1
    local p = getSpecificPlayer(0); if not p then return end
    local group, gid = getCrewGroup()
    if not group or not gid then print("[EmpireWanderers] no crew group yet."); return end
    local brought = 0
    for _ = 1, n do
        if crewCount(gid) >= TARGET_CREW then break end
        if spawnSettler(p, group) then brought = brought + 1 end
    end
    print("[EmpireWanderers] brought " .. brought .. " settler(s). Crew now " .. crewCount(gid) .. "/" .. TARGET_CREW)
    if brought > 0 then pcall(function()
        HaloTextHelper.addText(p, "Brought " .. brought .. " settler(s)", HaloTextHelper.getColorGreen())
    end) end
end

print("[EmpireNPC] Wanderers loaded -- settlers arrive when you're home & short-handed (cap " .. TARGET_CREW .. ").")