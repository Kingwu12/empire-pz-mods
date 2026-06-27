-- Empire NPC - Auto Guard Ring (hands-off perimeter defense, FPS-light)
-- No manual posts. Every Guard-role survivor auto-takes an evenly-spaced slot in a ring around the
-- base centre and holds it via SSC's own GuardTask. Recomputed on a slow timer (cheap), combat-
-- aware (a guard in a fight, or one you've sent to escort via HOME, is left alone), and stationary
-- -- so the AI throttle keeps them nearly free on FPS. Assign someone Guard and they join the ring.

require "EmpireNPC_Shared"

EmpireGuardRing = EmpireGuardRing or {}
EmpireGuardRing.ENABLED = true
EmpireGuardRing.RADIUS  = 11        -- tiles from base centre (perimeter). Raise to push the ring out.

local RECOMPUTE_MS = 15000          -- re-assign posts every 15s (slow = cheap)
local ARRIVE_DIST  = 2             -- within this many tiles of the slot = "holding it"
local GUARD        = EmpireNPC.Roles.GUARD
local lastRun = 0

-- Base centre = the FIXED rectangle you defined (EmpireBases "Main"), NOT SSC's group centre
-- (which tracks the group/you and is why the ring formed around you). Falls back to SSC's group
-- base centre only if no rectangle is registered. Never the player.
local function baseCenter(player)
    local cell = getCell()
    if cell and EmpireBases and EmpireBases.list then
        local b
        pcall(function() local l = EmpireBases.list(); b = l and l[1] end)
        if b and b.x1 and b.x2 and b.y1 and b.y2 then
            local cx = math.floor((b.x1 + b.x2) / 2)
            local cy = math.floor((b.y1 + b.y2) / 2)
            local cz = math.floor(b.z or 0)
            local sq = cell:getGridSquare(cx, cy, cz)
            if sq then return sq end          -- nil if base chunk isn't loaded (you're away) => dormant
        end
    end
    local sq = nil
    pcall(function()
        local me = SSM:Get(0)
        local g  = me and me:getGroup()
        if g then sq = g:getBaseCenter() end
    end)
    return sq
end

-- a standable tile at/near the target ring point
local function validSquare(cx, cy, z)
    local cell = getCell(); if not cell then return nil end
    for _, off in ipairs({ {0,0},{1,0},{-1,0},{0,1},{0,-1},{1,1},{-1,-1},{1,-1},{-1,1} }) do
        local sq = cell:getGridSquare(cx + off[1], cy + off[2], z)
        if sq then
            local solid = true
            pcall(function() solid = sq:isSolid() or sq:isSolidTrans() end)
            if not solid then return sq end
        end
    end
    return nil
end

-- all living Guard-role survivors, in a stable order so slots don't reshuffle each pass
local function guards()
    local out = {}
    pcall(function()
        for _, ss in ipairs(EmpireNPC.getActiveSurvivors()) do
            local nm; pcall(function() nm = ss:getName() end)
            if nm and nm ~= "" then
                local s  = EmpireNPC.getSettler(nm)
                local ch; pcall(function() ch = ss:Get() end)
                local dead = true; pcall(function() dead = ch:isDead() end)
                if s and s.role == GUARD and ch and not dead then
                    out[#out + 1] = { ss = ss, ch = ch, name = nm }
                end
            end
        end
    end)
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

local function distTiles(ch, sq)
    local dx = ch:getX() - sq:getX()
    local dy = ch:getY() - sq:getY()
    return math.sqrt(dx * dx + dy * dy)
end

-- send one guard to its slot, unless it's fighting or you've sent it to escort you
local function postGuard(g, sq)
    local danger = 0; pcall(function() danger = g.ss:getDangerSeenCount() end)
    if danger ~= 0 then return end                       -- in a fight: leave it
    local follow = false; pcall(function() follow = g.ss:needToFollow() end)
    if follow then return end                            -- escorting you (HOME deploy): leave it
    local task = ""; pcall(function() task = g.ss:getTaskManager():getCurrentTask() or "" end)
    if task == "Follow" then return end
    if distTiles(g.ch, sq) <= ARRIVE_DIST then return end  -- already holding its slot
    pcall(function()
        local tm = g.ss:getTaskManager()
        tm:clear()
        tm:AddToTop(GuardTask:new(g.ss, sq))
    end)
end

local function recompute()
    if not EmpireGuardRing.ENABLED then return end
    local player = getSpecificPlayer(0)
    if not player or player:isDead() then return end
    if not SSM then return end

    -- Resolve the REAL base centre. If SSC hasn't pinned one (e.g. the base chunk is unloaded
    -- because you're away), bail -- baseCenter() no longer falls back to the player, so this is
    -- the safety that stops guards being ringed around a roaming you.
    local center = baseCenter(player); if not center then return end
    local cx, cy, cz = center:getX(), center:getY(), math.floor(center:getZ())

    -- Run while you're at/over the base (any floor -- so the roof counts); dormant once you've
    -- travelled away, so an expedition never triggers re-posting. Centre is the fixed rectangle,
    -- so even if this runs while you're out, guards arrange around the BASE, never around you.
    local pdx, pdy = player:getX() - cx, player:getY() - cy
    local NEAR = (EmpireGuardRing.RADIUS or 11) + 25
    if (pdx * pdx + pdy * pdy) > (NEAR * NEAR) then return end

    local gs = guards()
    local n  = #gs
    if n == 0 then return end

    local R = EmpireGuardRing.RADIUS or 11
    for i = 1, n do
        local ang = (2 * math.pi) * (i - 1) / n
        local px  = math.floor(cx + math.cos(ang) * R)
        local py  = math.floor(cy + math.sin(ang) * R)
        local sq  = validSquare(px, py, cz)
        if sq then postGuard(gs[i], sq) end
    end
end

Events.OnTick.Add(function()
    local now = getTimestampMs()
    if now - lastRun < RECOMPUTE_MS then return end
    lastRun = now
    pcall(recompute)
end)

print("[EmpireNPC] Auto Guard Ring loaded -- guards self-arrange around the base, no posts to place.")
