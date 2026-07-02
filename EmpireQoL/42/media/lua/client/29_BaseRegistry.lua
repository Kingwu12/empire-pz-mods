-- EmpireQoL :: 29_BaseRegistry.lua
-- Empire base registry: the single source of truth for "what bases exist" and
-- "which base am I standing in". Base #1 ("Main") is seeded automatically from the
-- SuperbSurvivors base rectangle you already highlighted; extra bases live in our
-- own save data, so we support more than SSC's single base. Used by F9 sort, and
-- later by craft/build, to pool the WHOLE base (Fallout-style) only while you're in it.
-- Bounds shape: { name, x1, x2, y1, y2, z }.

EmpireBases = EmpireBases or {}

-- How many floors above AND below the one you're standing on a base sweep covers.
-- 2 = current floor +/- 2 (basement, ground, upper all reached from anywhere in the base).
EmpireBases.FLOOR_SPREAD = 2

-- How many floors BELOW the painted base to also sweep. The painted base usually only marks
-- the floor you walked ("define base as this building"), so a basement under the same
-- footprint never got scanned. Reaching down catches it. Empty floors sweep cheaply and the
-- container list is cached ~20s. Bump this if your basement is deeper than 6 levels.
EmpireBases.BASEMENT_REACH = 6

local function store()
    local t
    pcall(function() t = ModData.getOrCreate("EmpireBases") end)
    t = t or {}
    if type(t.list) ~= "table" then t.list = {} end
    return t
end

function EmpireBases.validBounds(b)
    if not b then return false end
    if not (b.x1 and b.x2 and b.y1 and b.y2) then return false end
    if b.x1 == 0 and b.x2 == 0 and b.y1 == 0 and b.y2 == 0 then return false end
    return true
end

-- Read the SuperbSurvivors base rectangle for the player's group, if any.
function EmpireBases.getSSCBase()
    local out
    pcall(function()
        if not SSM or not SSGM then return end
        local mySS = SSM:Get(0)
        if not mySS then return end
        local gid = mySS:getGroupID()
        if not gid then return end
        local group = SSGM:GetGroupById(gid)
        if not group then return end
        local b = group:getBounds()           -- {x1, x2, y1, y2, z}
        if b and b[1] ~= nil then
            out = { x1 = b[1], x2 = b[2], y1 = b[3], y2 = b[4], z = b[5] or 0 }
        end
    end)
    if out and EmpireBases.validBounds(out) then return out end
    return nil
end

-- Read the KnoxSurvivors base marker (centre + radius) as a rectangle. KS is what
-- this save actually runs (SuperbSurvivors is absent), so this is the real seed.
function EmpireBases.getKSBase()
    local out
    pcall(function()
        if not KS or not KS.GetPlayerBase then return end
        local p = getSpecificPlayer(0); if not p then return end
        local b = KS.GetPlayerBase(p)
        if not b or b.x == nil then return end
        local r = 24
        pcall(function()
            local sv = SandboxVars and SandboxVars.KnoxSurvivors
            if sv then r = sv.MaxBaseRadius or sv.BaseMarkerRadius or r end
        end)
        out = { x1 = b.x - r, x2 = b.x + r, y1 = b.y - r, y2 = b.y + r, z = b.z or 0 }
    end)
    if out and EmpireBases.validBounds(out) then return out end
    return nil
end

-- Re-sync "Main" to the current KS base (call after moving your KS base marker).
function EmpireBases.syncMainFromKS()
    local ks = EmpireBases.getKSBase()
    if not ks then return false end
    local t = store()
    for _, b in ipairs(t.list) do
        if b.name == "Main" then
            b.x1, b.x2, b.y1, b.y2, b.z = ks.x1, ks.x2, ks.y1, ks.y2, ks.z
            return true
        end
    end
    table.insert(t.list, { name = "Main", x1 = ks.x1, x2 = ks.x2,
                           y1 = ks.y1, y2 = ks.y2, z = ks.z })
    return true
end

-- Read OUR painted Empire Zones "base" zone as a rectangle + floor range. This is
-- the highlight-based base that replaces external markers (KS/SSC).
function EmpireBases.getEmpireZoneBase()
    local out
    pcall(function()
        if not EmpireZones or not EmpireZones.all or not EmpireZones.parseKey then return end
        local x1, x2, y1, y2, z1, z2
        for _, zone in pairs(EmpireZones.all()) do
            if zone and zone.type == "base" and zone.tiles then
                for k in pairs(zone.tiles) do
                    local x, y, zz = EmpireZones.parseKey(k)
                    if x then
                        x1 = x1 and math.min(x1, x) or x; x2 = x2 and math.max(x2, x) or x
                        y1 = y1 and math.min(y1, y) or y; y2 = y2 and math.max(y2, y) or y
                        z1 = z1 and math.min(z1, zz) or zz; z2 = z2 and math.max(z2, zz) or zz
                    end
                end
            end
        end
        if x1 then out = { x1 = x1, x2 = x2, y1 = y1, y2 = y2, z = z1, zmin = z1, zmax = z2 } end
    end)
    if out and EmpireBases.validBounds(out) then return out end
    return nil
end

-- The registered bases. Seeds "Main" from a painted base zone, else SSC.
function EmpireBases.list()
    local t = store()
    if #t.list == 0 then
        local seed = EmpireBases.getEmpireZoneBase() or EmpireBases.getSSCBase()
        if seed then
            table.insert(t.list, { name = "Main", x1 = seed.x1, x2 = seed.x2,
                                   y1 = seed.y1, y2 = seed.y2, z = seed.z })
        end
    end
    return t.list
end

-- Re-sync "Main" to the current SSC bounds (call after you re-highlight in SSC).
function EmpireBases.syncMainFromSSC()
    local ssc = EmpireBases.getSSCBase()
    if not ssc then return false end
    local t = store()
    for _, b in ipairs(t.list) do
        if b.name == "Main" then
            b.x1, b.x2, b.y1, b.y2, b.z = ssc.x1, ssc.x2, ssc.y1, ssc.y2, ssc.z
            return true
        end
    end
    table.insert(t.list, { name = "Main", x1 = ssc.x1, x2 = ssc.x2,
                           y1 = ssc.y1, y2 = ssc.y2, z = ssc.z })
    return true
end

-- Add a new base from an explicit rectangle.
function EmpireBases.addBase(name, x1, x2, y1, y2, z)
    local t = store()
    table.insert(t.list, { name = name or ("Base " .. (#t.list + 1)),
        x1 = math.min(x1, x2), x2 = math.max(x1, x2),
        y1 = math.min(y1, y2), y2 = math.max(y1, y2), z = z or 0 })
    return t.list[#t.list]
end

local function inRect(px, py, b)
    return px >= math.min(b.x1, b.x2) and px <= math.max(b.x1, b.x2)
       and py >= math.min(b.y1, b.y2) and py <= math.max(b.y1, b.y2)
end

-- Which base is the player standing in (rectangle test, any floor)? nil if none.
function EmpireBases.activeBase(playerObj)
    playerObj = playerObj or getSpecificPlayer(0)
    if not playerObj then return nil end
    local sq = playerObj:getCurrentSquare()
    if not sq then return nil end
    local px, py = sq:getX(), sq:getY()
    for _, b in ipairs(EmpireBases.list()) do
        if inRect(px, py, b) then return b end
    end
    return nil
end

function EmpireBases.inBase(playerObj)
    return EmpireBases.activeBase(playerObj) ~= nil
end

-- Point KnoxSurvivors' home base at OUR defined base and size its radius to cover
-- it, so survivors home to our base instead of KS's default tiny circle. KS only
-- supports centre+radius, so this matches our base as a circle that COVERS it --
-- not the exact shape (that needs overriding KS's private guard AI).
function EmpireBases.syncKSToOurBase(player)
    player = player or getSpecificPlayer(0)
    if not player or not KS or not KS.SetPlayerBase then return false end
    local zb = EmpireBases.getEmpireZoneBase()
    if not zb then return false end
    local cx = math.floor((zb.x1 + zb.x2) / 2)
    local cy = math.floor((zb.y1 + zb.y2) / 2)
    local cz = zb.zmin or 0
    local fit = math.max(math.ceil((zb.x2 - zb.x1) / 2), math.ceil((zb.y2 - zb.y1) / 2)) + 1
    local ok = false
    pcall(function()
        local cell = getCell()
        local sq = cell and cell:getGridSquare(cx, cy, cz)
        if not sq then return end
        local sv = SandboxVars and SandboxVars.KnoxSurvivors
        if sv then
            sv.MaxBaseRadius = math.max(sv.MaxBaseRadius or 24, fit)
            sv.BaseMarkerRadius = fit
        end
        local base = KS.SetPlayerBase(player, sq)
        if base then base.radius = fit; ok = true end
        if KS.RefreshBaseMarkers then KS.RefreshBaseMarkers(true) end
    end)
    return ok
end

-- Scan rectangle for sort/craft/build.
--   In a base -> the WHOLE base on the player's current floor.
--   Otherwise -> a radius box around the player (radiusFallback, default 12).
-- Returns: x1, x2, y1, y2, z1, z2, base(or nil)
function EmpireBases.scanBounds(playerObj, radiusFallback)
    playerObj = playerObj or getSpecificPlayer(0)
    if not playerObj then return nil end
    local sq = playerObj:getCurrentSquare()
    if not sq then return nil end
    local pz = sq:getZ()
    local px, py = sq:getX(), sq:getY()

    -- 1) live painted Empire Zones "base" zone (the highlight base) wins. Sweep the painted
    --    floors, plus a reach DOWN for basements and up by FLOOR_SPREAD, and always include
    --    the floor you're standing on.
    local zb = EmpireBases.getEmpireZoneBase()
    if zb and px >= zb.x1 and px <= zb.x2 and py >= zb.y1 and py <= zb.y2 then
        local down = EmpireBases.BASEMENT_REACH or 6
        local up   = EmpireBases.FLOOR_SPREAD or 2
        local lo = math.min((zb.zmin or pz) - down, pz)
        local hi = math.max((zb.zmax or pz) + up, pz)
        return zb.x1, zb.x2, zb.y1, zb.y2, lo, hi, zb
    end

    -- 2) a registered base rectangle (legacy/SSC) -> whole base, +/- floor spread
    local b = EmpireBases.activeBase(playerObj)
    if b then
        local spread = EmpireBases.FLOOR_SPREAD or 0
        return math.min(b.x1, b.x2), math.max(b.x1, b.x2),
               math.min(b.y1, b.y2), math.max(b.y1, b.y2),
               pz - spread, pz + spread, b
    end

    -- 3) no base defined -> radius box around you, current floor only
    local r = radiusFallback or 12
    return px - r, px + r, py - r, py + r, pz, pz, nil
end

-- DOCK CHECK: true if the vehicle sits within n tiles (Chebyshev) of ANY painted base
-- tile. Uses the freeform tile set directly (not the bounding box), so an L-shaped or
-- hollow base only counts tiles you actually painted. z is ignored on purpose -- a truck
-- on the street should dock to a multi-floor base. Cheap: runs once per right-click.
function EmpireBases.vehicleNearBase(veh, n)
    if not veh then return false end
    n = n or 8
    local vx, vy
    pcall(function() vx = veh:getX(); vy = veh:getY() end)
    if not vx or not vy then return false end
    if not (EmpireZones and EmpireZones.all and EmpireZones.parseKey) then return false end
    local found = false
    pcall(function()
        for _, zone in pairs(EmpireZones.all()) do
            if zone and zone.type == "base" and zone.tiles then
                for k in pairs(zone.tiles) do
                    local tx, ty = EmpireZones.parseKey(k)
                    if tx and math.abs(tx - vx) <= n and math.abs(ty - vy) <= n then
                        found = true; break
                    end
                end
            end
            if found then break end
        end
    end)
    return found
end

print("[EmpireBases] base registry loaded (seeds 'Main' from SSC bounds).")
