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

-- The registered bases. Seeds "Main" from SSC the first time SSC bounds are valid.
function EmpireBases.list()
    local t = store()
    if #t.list == 0 then
        local ssc = EmpireBases.getSSCBase()
        if ssc then
            table.insert(t.list, { name = "Main", x1 = ssc.x1, x2 = ssc.x2,
                                   y1 = ssc.y1, y2 = ssc.y2, z = ssc.z })
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
    local b = EmpireBases.activeBase(playerObj)
    if b then
        local spread = EmpireBases.FLOOR_SPREAD or 0
        return math.min(b.x1, b.x2), math.max(b.x1, b.x2),
               math.min(b.y1, b.y2), math.max(b.y1, b.y2),
               pz - spread, pz + spread, b
    end
    local r = radiusFallback or 12
    local px, py = sq:getX(), sq:getY()
    return px - r, px + r, py - r, py + r, pz, pz, nil
end

print("[EmpireBases] base registry loaded (seeds 'Main' from SSC bounds).")
