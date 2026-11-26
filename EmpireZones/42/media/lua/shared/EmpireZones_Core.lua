-- ============================================================
-- Empire Zones : core (shared)
-- A zone is a freeform SET of tiles, each stored as "x,y,z" so it spans floors
-- and undergrounds naturally - irregular shapes, multiple bases, satellites.
-- Persisted in global ModData (saves with the world). No radius anywhere.
-- ============================================================

EmpireZones = EmpireZones or {}
local EZ = EmpireZones

EZ.TYPES = { "base", "farm", "guard", "workshop", "storage" }

-- Bumped by every mutator below. Readers that derive something expensive from the tiles
-- (EmpireBases.getEmpireZoneBase walks every tile of every base zone) cache it against this
-- number instead of recomputing on each call. Mutate zones only through these functions.
EZ.version = 0

local function store()
    local d = ModData.getOrCreate("EmpireZones")
    d.zones = d.zones or {}
    d.nextId = d.nextId or 1
    return d
end
EZ.store = store

function EZ.key(x, y, z) return math.floor(x) .. "," .. math.floor(y) .. "," .. math.floor(z) end

function EZ.parseKey(k)
    local x, y, z = k:match("(-?%d+),(-?%d+),(-?%d+)")
    return tonumber(x), tonumber(y), tonumber(z)
end

function EZ.all() return store().zones end
function EZ.get(id) return store().zones[tostring(id)] end

function EZ.tileCount(zone)
    local n = 0
    if zone and zone.tiles then for _ in pairs(zone.tiles) do n = n + 1 end end
    return n
end

function EZ.newZone(name, ztype)
    local d = store()
    local id = tostring(d.nextId)
    d.nextId = d.nextId + 1
    d.zones[id] = { id = id, name = name or ("Zone " .. id), type = ztype or "base", tiles = {} }
    EZ.version = EZ.version + 1
    return id
end

function EZ.addTile(id, x, y, z)
    local zone = EZ.get(id); if not zone then return end
    zone.tiles[EZ.key(x, y, z)] = true
    EZ.version = EZ.version + 1
end

function EZ.addBlock(id, cx, cy, z, r)
    for dx = -r, r do for dy = -r, r do EZ.addTile(id, cx + dx, cy + dy, z) end end
end

function EZ.removeTile(id, x, y, z)
    local zone = EZ.get(id); if not zone then return end
    zone.tiles[EZ.key(x, y, z)] = nil
    EZ.version = EZ.version + 1
end

function EZ.zoneAt(x, y, z)
    local k = EZ.key(x, y, z)
    for _, zone in pairs(store().zones) do
        if zone.tiles[k] then return zone end
    end
    return nil
end

function EZ.delete(id) store().zones[tostring(id)] = nil; EZ.version = EZ.version + 1 end

-- iterate a zone's tiles as numbers: EZ.forEachTile(zone, function(x,y,z) end)
function EZ.forEachTile(zone, fn)
    if not zone or not zone.tiles then return end
    for k in pairs(zone.tiles) do
        local x, y, z = EZ.parseKey(k)
        if x then fn(x, y, z) end
    end
end
