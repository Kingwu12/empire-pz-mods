-- Empire QoL :: 18_Waypoints.lua  (28 Nov 2026, B42.22)
-- King: "we want the teleportation... the base location is good its just super far from anything... when we
-- teleport we want the vehicle together". Base = the Riverside police / fire station compound by the lake.
--
-- WHAT IT DOES
--   Save places ("waypoints") and jump between them in one click, taking your truck along.
--   Right-click the ground -> "Empire: Travel" -> pick a place, or "Save a waypoint here...".
--   Numpad 1 = one-press round trip: away from the base it takes you HOME (waypoint "Base"); at the base
--   it takes you BACK to where you left from, truck parked on the exact spot you left it.
--
-- HOW IT IS BUILT (all verified against the 42.22.2 game jar, read-only):
--   * Player: IsoGameCharacter.teleportTo(x,y,z) is vanilla Lua-callable in single player (the game's own
--     Zombie Population map uses it) and calls ensureNotInVehicle() first, so you step out of the truck.
--   * Vehicle: no vanilla Lua moves a vehicle, but BaseVehicle.setWorldTransform(Transform) is exposed and
--     its bytecode calls Bullet.teleportVehicle(id, x, y, z, quat): the engine's own physics teleport. We read
--     the current transform (getWorldTransform), shift its origin by the world delta and write it back. The
--     origin maps x -> world X, z -> world Y, y -> height (BaseVehicle.update does exactly that mapping).
--   * The old area unloads right after the jump, so the vehicle is moved in the SAME call, before the engine
--     re-centres its chunk map. X/Y/Z are also set directly so a vehicle saved while unloading is saved at
--     the destination (the vehicle database stores the position). A short-lived OnTick then finds the vehicle
--     by its id near the target (it may be a fresh object loaded from the database), puts you back in the
--     driver's seat if you were driving, and tells you if it did not make it.
--   * Every outcome is printed to console.txt as [EmpireWaypoints] lines, so the first real trip settles
--     what the engine really does. WORST CASE: the truck stays parked where you left it (nothing is deleted).
--
-- PERFORMANCE: no per-frame work at rest. The only handlers are the right-click menu (runs when you open it),
-- one key, OnEnterVehicle (remembers which vehicle is yours) and OnGameStart. During a trip a short OnTick
-- (<= 15 s, every 20th tick does anything) runs and removes itself.
--
-- SAFETY: blocked while a zombie is chasing or very close. Queued timed actions are cleared. A trailer or
-- tow must be detached first (a one-sided move would snap the tow constraint). The arrival square is checked
-- once the area loads: water, a wall or a tree and you are moved to the nearest free tile.
-- Waypoints live in the world's ModData ("EmpireWaypoints"), so they survive a death and a new character.

EmpireWaypoints = EmpireWaypoints or {}
local W = EmpireWaypoints

local CFG = {
    MAX_WAYPOINTS  = 12,
    VEHICLE_REACH  = 14,    -- tiles: YOUR vehicle this close (or the one you sit in) travels with you
    NEAREST_REACH  = 8,     -- tiles: from the menu any vehicle this close can be picked, and named in the entry
    HOME_NAME      = "Base",
    HOME_RADIUS    = 60,    -- tiles from the Base waypoint that count as "at home" for Numpad 1
    BLOCK_WHEN_CHASED = true,
    VERIFY_TICKS   = 900,   -- the arrival check gives up after this many ticks (~15 s)
    VERIFY_EVERY   = 20,    -- and only does anything on every Nth tick
    VEHICLE_TOL    = 6,     -- tiles: the vehicle counts as arrived when it is this close to its target
    VEHICLE_TRIES  = 4,     -- looks for the vehicle after the destination loaded, before reporting it missing
    VEHICLE_FIXES  = 3,     -- times the vehicle is shifted onto its target again when it landed off (see onTick)
    SAFE_RADIUS    = 10,    -- tiles searched for a free square when the arrival square is blocked
    SEED = { name = "Base", x = 6032, y = 5238, z = 0 },  -- Riverside police / fire station compound (King's map pick)
}
W.CFG = CFG

local TAG = "[EmpireWaypoints] "
local pending = nil     -- the trip being verified (nil when idle)

-- ---------- small helpers ----------

local function say(player, msg, kind)
    if player then
        pcall(function()
            local c = HaloTextHelper.getColorWhite()
            if kind == "ok" then c = HaloTextHelper.getColorGreen()
            elseif kind == "bad" then c = HaloTextHelper.getColorRed() end
            HaloTextHelper.addTextWithArrow(player, msg, "[br/]", false, c)
        end)
    end
    print(TAG .. msg)
end

W.say = say

local function store()
    local d = ModData.getOrCreate("EmpireWaypoints")
    d.list = d.list or {}
    return d
end
W.store = store

local function lower(s) return string.lower(tostring(s or "")) end

local function indexOf(d, name)
    local n = lower(name)
    for i, w in ipairs(d.list) do
        if lower(w.name) == n then return i, w end
    end
    return nil
end

local function dist(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end

local function eachVehicle(fn)
    local set = nil
    pcall(function() set = getCell():getVehicles() end)
    if not set then return end
    -- IsoCell.getVehicles() returns a java.util.Set in 42.22: there is no get(i), and calling it makes the engine
    -- log a Java stack on every right-click. Iterate; size()/get(i) is only a last resort.
    local ok = pcall(function()
        local it = set:iterator()
        while it:hasNext() do fn(it:next()) end
    end)
    if not ok then
        pcall(function()
            for i = 1, set:size() do fn(set:get(i - 1)) end
        end)
    end
end

local function vehId(v)
    local id = nil
    pcall(function() id = v:getId() end)
    return id
end

local function vehName(v)
    local n = "vehicle"
    pcall(function() n = (tostring(v:getScriptName() or n):gsub("^Base%.", "")) end)
    return n
end
W.vehicleName = vehName

local function isTowing(v)
    local t = false
    pcall(function() t = (v:getVehicleTowing() ~= nil) or (v:getVehicleTowedBy() ~= nil) end)
    return t
end

-- Which vehicle comes along. The one you sit in; else YOUR vehicle (the last one you drove) if it is within
-- VEHICLE_REACH; else, only when `anyNearby`, the nearest vehicle within NEAREST_REACH (menu picks).
local function pickVehicle(player, anyNearby)
    local v = nil
    pcall(function() v = player:getVehicle() end)
    if not v then
        local mine = store().mine
        local px, py = player:getX(), player:getY()
        if mine then
            eachVehicle(function(c)
                if vehId(c) == mine and dist(c:getX(), c:getY(), px, py) <= CFG.VEHICLE_REACH then v = c end
            end)
        end
        if not v and anyNearby then
            local bd = CFG.NEAREST_REACH
            eachVehicle(function(c)
                local d = dist(c:getX(), c:getY(), px, py)
                if d <= bd then v, bd = c, d end
            end)
        end
    end
    if not v then return nil end
    if isTowing(v) then return nil, "trailer" end
    return v
end
W.pickVehicle = pickVehicle

local function canTravel(player)
    if not player or player:isDead() then return false, "You can't travel right now" end
    if pending then return false, "Still arriving, give it a second" end
    if CFG.BLOCK_WHEN_CHASED then
        local near = false
        pcall(function()
            local s = player:getStats()
            near = s:getNumChasingZombies() > 0 or s:getNumVeryCloseZombies() > 0
        end)
        if near then return false, "Zombies are on you: lose them first (travel is blocked while chased)" end
    end
    return true
end

-- ---------- moving a vehicle ----------

-- BaseVehicle.setWorldTransform -> Bullet.teleportVehicle. The transform origin is (worldX, height, worldY)
-- in the physics frame, so we shift it by the world delta instead of relying on the engine's offsets.
-- 28 Nov 2026, first real trip: the truck landed 69 tiles from the target (about 49 on each axis), because the
-- physics frame re-centres when the player teleports. The arrival check therefore calls this again, from where
-- the truck actually is once the destination has loaded (closed loop), and every call logs what it saw.
local function moveVehicle(veh, x, y, z, why)
    local ok = false
    pcall(function()
        -- allocTransform is STATIC in the jar (class BaseVehicle); Transform.new() is the public constructor
        local t, pooled = nil, false
        pcall(function() t = Transform.new() end)
        if not t then pcall(function() t = BaseVehicle.allocTransform(); pooled = true end) end
        if not t then return end
        veh:getWorldTransform(t)
        local o = t:getOrigin()
        local ox, oy, oz = o:x(), o:y(), o:z()
        local vx, vy, vz = veh:getX(), veh:getY(), veh:getZ()
        local dx, dy, dz = x - vx, y - vy, z - vz
        o:set(ox + dx, oy + dz, oz + dy)
        veh:setWorldTransform(t)
        if pooled then pcall(function() BaseVehicle.releaseTransform(t) end) end
        ok = true
        print(string.format(TAG .. "move%s: world (%.1f,%.1f,%.1f) physics origin (%.1f,%.1f,%.1f) shifted by (%.1f,%.1f,%.1f)",
            why and (" " .. why) or "", vx, vy, vz, ox, oy, oz, dx, dy, dz))
    end)
    -- also write the fields: if the chunk unloads before the next physics update the vehicle database
    -- saves the vehicle where these say it is (the destination), not where it was
    pcall(function() veh:setX(x); veh:setY(y); veh:setZ(z) end)
    pcall(function() veh:setPhysicsActive(true) end)
    return ok
end
W.moveVehicle = moveVehicle

-- ---------- arrival check (short-lived OnTick) ----------

local onTick   -- forward

local function finish(p, msg, kind)
    if msg then say(getSpecificPlayer(0), msg, kind) end
    pending = nil
    Events.OnTick.Remove(onTick)
end

local function freeSquare(sq)
    if not sq then return false end
    local free = false
    pcall(function() free = sq:isFree(false) and sq:hasFloor() end)
    pcall(function() if sq:hasWater() then free = false end end)
    pcall(function()
        if IsoFlagType and IsoFlagType.water and sq:getProperties():Is(IsoFlagType.water) then free = false end
    end)
    pcall(function() if sq:HasTree() then free = false end end)
    return free
end

local function safeLanding(player, p)
    local sq = nil
    pcall(function() sq = getCell():getGridSquare(p.ptx, p.pty, p.ptz) end)
    if freeSquare(sq) then return end
    local cx, cy, cz = math.floor(p.ptx), math.floor(p.pty), math.floor(p.ptz)
    for r = 1, CFG.SAFE_RADIUS do
        for dx = -r, r do
            for dy = -r, r do
                if math.max(math.abs(dx), math.abs(dy)) == r then
                    local s = nil
                    pcall(function() s = getCell():getGridSquare(cx + dx, cy + dy, cz) end)
                    if freeSquare(s) then
                        pcall(function() player:teleportTo(cx + dx + 0.5, cy + dy + 0.5, cz) end)
                        print(TAG .. "arrival square blocked, moved " .. dx .. "," .. dy)
                        return
                    end
                end
            end
        end
    end
    print(TAG .. "arrival square blocked and no free square within " .. CFG.SAFE_RADIUS)
end

local function findVehicle(id)
    local found = nil
    eachVehicle(function(c) if vehId(c) == id then found = c end end)
    return found
end

onTick = function()
    local p = pending
    if not p then Events.OnTick.Remove(onTick); return end
    p.ticks = p.ticks + 1
    local timeout = p.ticks >= CFG.VERIFY_TICKS
    if p.ticks % CFG.VERIFY_EVERY ~= 0 and not timeout then return end
    local player = getSpecificPlayer(0)
    if not player then return finish(p) end
    local sq = nil
    pcall(function() sq = getCell():getGridSquare(p.ptx, p.pty, p.ptz) end)
    if not sq then
        if timeout then finish(p, "Arrival area never loaded (" .. p.name .. "). Try again.", "bad") end
        return
    end
    if not p.landed then
        p.landed = true
        if not p.seated then safeLanding(player, p) end
    end
    if not p.vid then
        return finish(p, "Arrived at " .. p.name, "ok")
    end
    p.tries = p.tries + 1
    local v = findVehicle(p.vid)
    local d, vx, vy = nil, nil, nil
    if v then pcall(function() vx, vy = v:getX(), v:getY(); d = dist(vx, vy, p.vtx, p.vty) end) end
    print(TAG .. "check " .. p.tries .. ": vehicle " .. p.vname .. " id=" .. tostring(p.vid)
        .. ((v and d) and string.format(" found at (%.0f,%.0f), %.1f tiles from target (%.0f,%.0f)", vx, vy, d, p.vtx, p.vty)
            or " not in the loaded world")
        .. " fixes=" .. tostring(p.fixes) .. " ticks=" .. p.ticks)
    if v and d and d <= CFG.VEHICLE_TOL then
        pcall(function() v:setPhysicsActive(true) end)
        local msg = "Arrived at " .. p.name .. " with the " .. p.vname
        if p.seated then
            local entered = false
            pcall(function() entered = v:enter(0, player) end)
            if not entered then msg = msg .. " (take the driver's seat)" end
        end
        pcall(function()
            if EmpireAutoChores and EmpireAutoChores.armUnload then EmpireAutoChores.armUnload(v) end
        end)
        return finish(p, msg, "ok")
    end
    if v and d and p.fixes < CFG.VEHICLE_FIXES and not timeout then
        -- it is here but not where it should be: shift it by the error we can now measure, then look again
        p.fixes = p.fixes + 1
        local moved = moveVehicle(v, p.vtx, p.vty, p.vtz, "fix " .. p.fixes)
        print(string.format(TAG .. "fix %d: %s was %.1f tiles off at (%.0f,%.0f); shifted onto (%.0f,%.0f) moved=%s",
            p.fixes, p.vname, d, vx, vy, p.vtx, p.vty, tostring(moved)))
        p.tries = p.tries - 1     -- a correction does not use up a look
        return
    end
    if p.tries >= CFG.VEHICLE_TRIES or timeout then
        local msg
        if v and d then
            msg = string.format("Arrived at %s, but the %s ended up %d tiles away (%d,%d). Walk over to it, or try the trip again.",
                p.name, p.vname, math.floor(d + 0.5), math.floor(vx), math.floor(vy))
        else
            local back = store().back
            msg = "Arrived at " .. p.name .. ", but the " .. p.vname .. " has not shown up here"
                .. (back and (" (it may still be at " .. math.floor(back.vx or back.x) .. "," .. math.floor(back.vy or back.y) .. ")") or "") .. "."
        end
        return finish(p, msg, "bad")
    end
end

-- ---------- travel ----------

-- wp = {name, x, y, z, hasV, vx, vy, vz}. withVeh: bring the vehicle (when one qualifies).
function W.travel(player, wp, withVeh)
    local ok, why = canTravel(player)
    if not ok then say(player, why, "bad"); return false end
    if not wp or not wp.x or not wp.y then say(player, "That waypoint has no position", "bad"); return false end

    local seated = false
    pcall(function() seated = player:getVehicle() ~= nil end)
    local veh, vwhy = nil, nil
    if withVeh then veh, vwhy = pickVehicle(player, true) end
    if withVeh and vwhy == "trailer" then
        say(player, "Detach the trailer first (or travel on foot): a one-sided move would snap the tow", "bad")
        return false
    end

    local p0x, p0y, p0z = player:getX(), player:getY(), player:getZ()
    local ptx, pty, ptz = wp.x, wp.y, wp.z or 0
    local v0x, v0y, v0z, vtx, vty, vtz
    if veh then
        v0x, v0y, v0z = veh:getX(), veh:getY(), veh:getZ()
        if wp.hasV and wp.vx and wp.vy then
            vtx, vty, vtz = wp.vx, wp.vy, wp.vz or ptz
            ptx, pty = vtx + (p0x - v0x), vty + (p0y - v0y)    -- you keep your place beside it
        else
            vtx, vty, vtz = ptx + (v0x - p0x), pty + (v0y - p0y), ptz    -- same layout around the spot
        end
        if seated then ptx, pty, ptz = vtx, vty, vtz end       -- you are put back in the seat on arrival
    end

    -- remember where this trip started so "Back" / Numpad 1 returns you (and the truck) to the same spot
    local d = store()
    d.back = { name = "Back", x = p0x, y = p0y, z = p0z, hasV = veh ~= nil, vx = v0x, vy = v0y, vz = v0z }

    pcall(function() ISTimedActionQueue.clear(player) end)
    local moved = nil
    if veh then moved = moveVehicle(veh, vtx, vty, vtz, "first") end
    local okTp = pcall(function() player:teleportTo(ptx, pty, ptz) end)
    if not okTp then
        say(player, "The teleport call failed (see console)", "bad")
        return false
    end

    print(string.format(TAG .. "travel to %s: player (%.0f,%.0f,%.0f)%s", tostring(wp.name), ptx, pty, ptz,
        veh and string.format(", %s id=%s -> (%.0f,%.0f,%.0f) moved=%s seated=%s", vehName(veh), tostring(vehId(veh)),
            vtx, vty, vtz, tostring(moved), tostring(seated)) or ", on foot"))
    pending = {
        name = tostring(wp.name), ptx = ptx, pty = pty, ptz = ptz, seated = seated and veh ~= nil,
        vid = veh and vehId(veh) or nil, vname = veh and vehName(veh) or nil,
        vtx = vtx, vty = vty, vtz = vtz, ticks = 0, tries = 0, fixes = 0, landed = false,
    }
    Events.OnTick.Add(onTick)
    return true
end

function W.travelTo(player, name, withVeh)
    local d = store()
    local _, wp = indexOf(d, name)
    if not wp then say(player, "No waypoint called " .. tostring(name), "bad"); return false end
    return W.travel(player, wp, withVeh)
end

function W.back(player, withVeh)
    local b = store().back
    if not b then say(player, "Nowhere to go back to yet", "bad"); return false end
    return W.travel(player, b, withVeh)
end

-- ---------- saving ----------

local function putWaypoint(player, name, wp, veh)
    local d = store()
    local i = indexOf(d, name)
    if not i and #d.list >= CFG.MAX_WAYPOINTS then
        say(player, "Waypoint list is full (" .. CFG.MAX_WAYPOINTS .. "): delete one first", "bad")
        return false
    end
    wp.name = name
    if i then d.list[i] = wp else d.list[#d.list + 1] = wp end
    say(player, (i and "Updated" or "Saved") .. " waypoint " .. name
        .. (wp.hasV and (" (truck spot saved: " .. vehName(veh) .. ")")
            or ((wp.fromMap or wp.typed) and " (coordinates only)" or " (on foot: stand next to your truck to save a truck spot)")), "ok")
    return true
end

local function cleanName(name)
    name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    return name
end

function W.saveHere(player, name)
    name = cleanName(name)
    if name == "" then say(player, "A waypoint needs a name", "bad"); return false end
    local wp = { x = player:getX(), y = player:getY(), z = player:getZ(), hasV = false }
    local veh = pickVehicle(player, true)
    if veh then
        wp.hasV, wp.vx, wp.vy, wp.vz = true, veh:getX(), veh:getY(), veh:getZ()
    end
    return putWaypoint(player, name, wp, veh)
end

-- a point picked on the world map: no truck spot (the truck keeps its layout around you on arrival)
function W.saveAt(player, name, x, y)
    name = cleanName(name)
    if name == "" then say(player, "A waypoint needs a name", "bad"); return false end
    return putWaypoint(player, name, { x = x, y = y, z = 0, hasV = false, fromMap = true }, nil)
end

-- typed coordinates (the Travel window's form): same as a map point, with a height
function W.saveXYZ(player, name, x, y, z)
    name = cleanName(name)
    if name == "" then say(player, "A waypoint needs a name", "bad"); return false end
    if not (tonumber(x) and tonumber(y)) then say(player, "A waypoint needs X and Y", "bad"); return false end
    return putWaypoint(player, name, { x = tonumber(x), y = tonumber(y), z = tonumber(z) or 0, hasV = false, typed = true }, nil)
end

function W.travelXY(player, x, y, withVeh)
    return W.travel(player, { name = "the map point", x = x, y = y, z = 0, hasV = false }, withVeh)
end

function W.delete(player, name)
    local d = store()
    local i = indexOf(d, name)
    if not i then return false end
    table.remove(d.list, i)
    say(player, "Deleted waypoint " .. tostring(name), "ok")
    return true
end

-- ---------- Numpad 1: home / back ----------

function W.homeOrBack(player)
    local d = store()
    local _, home = indexOf(d, CFG.HOME_NAME)
    if not home then say(player, "No \"" .. CFG.HOME_NAME .. "\" waypoint yet", "bad"); return false end
    if dist(player:getX(), player:getY(), home.x, home.y) <= CFG.HOME_RADIUS then
        -- at home: Numpad 1 goes back to where the last trip started, if that was somewhere else
        if d.back and dist(d.back.x, d.back.y, home.x, home.y) > CFG.HOME_RADIUS then
            return W.back(player, true)
        end
        say(player, "You are home. Right-click > Empire: Travel to pick a destination", nil)
        return false
    end
    return W.travel(player, home, true)
end

-- ---------- right-click menu ----------

local function onSaveName(target, button, playerNum, x, y)
    if button.internal ~= "OK" then return end
    local p = getSpecificPlayer(playerNum or 0)
    local nm = nil
    pcall(function() nm = button.parent.entry:getText() end)
    if not (p and nm) then return end
    if x and y then W.saveAt(p, nm, x, y) else W.saveHere(p, nm) end
end

-- x, y given: the point was picked on the world map
local function promptSave(player, x, y)
    local pn = 0
    pcall(function() pn = player:getPlayerNum() end)
    local modal = ISTextBox:new(0, 0, 300, 180, "Waypoint name (same name updates it):",
        "", nil, onSaveName, pn, pn, x, y)
    modal:initialise()
    modal:addToUIManager()
end

local function onFill(playerNum, context, worldobjects, test)
    if test then return end
    local player = getSpecificPlayer(playerNum)
    if not player or player:isDead() then return end
    local d = store()
    local veh = pickVehicle(player, true)
    local opt = context:addOption("Empire: Travel")
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(opt, sub)
    if W.openUI then sub:addOption("Open the Travel window (Numpad 1)", player, W.openUI) end
    for _, wp in ipairs(d.list) do
        if veh then
            sub:addOption("Go to " .. wp.name .. " with the " .. vehName(veh), player, W.travel, wp, true)
            sub:addOption("Go to " .. wp.name .. " on foot", player, W.travel, wp, false)
        else
            sub:addOption("Go to " .. wp.name, player, W.travel, wp, false)
        end
    end
    if d.back then
        sub:addOption("Back to where I left from" .. (d.back.hasV and " (with the truck)" or ""),
            player, W.back, d.back.hasV and veh ~= nil)
    end
    sub:addOption("Save a waypoint here...", player, promptSave)
    if #d.list > 0 then
        local delOpt = sub:addOption("Delete a waypoint")
        local delSub = ISContextMenu:getNew(sub)
        sub:addSubMenu(delOpt, delSub)
        for _, wp in ipairs(d.list) do
            delSub:addOption(wp.name, player, W.delete, wp.name)
        end
    end
end
Events.OnFillWorldObjectContextMenu.Add(onFill)

-- ---------- world map right-click ----------
-- Vanilla's map menu (Teleport Here -> player:teleportTo(x, y, 0)) only exists in debug mode. Outside debug we
-- add our own: right-click a spot on the world map to travel there, with your truck, or save it as a waypoint.
local function wrapWorldMap()
    if not (ISWorldMap and ISWorldMap.onRightMouseUp) or ISWorldMap.empireWaypointsWrapped then return end
    ISWorldMap.empireWaypointsWrapped = true
    local orig = ISWorldMap.onRightMouseUp
    ISWorldMap.onRightMouseUp = function(self, x, y)
        local r = orig(self, x, y)
        if r then return r end                               -- the map symbols UI used the click
        local debug = false
        pcall(function() debug = getDebug() end)
        if debug then return r end                           -- debug mode keeps the vanilla menu
        local player = getSpecificPlayer(0)
        if not player or player:isDead() then return r end
        local wx, wy, valid = nil, nil, false
        pcall(function()
            wx, wy = self.mapAPI:uiToWorldX(x, y), self.mapAPI:uiToWorldY(x, y)
            valid = getWorld():getMetaGrid():isValidChunk(wx / 10, wy / 10)
        end)
        if not (wx and valid) then return r end
        local ok = pcall(function()
            local context = ISContextMenu.get(0, x + self:getAbsoluteX(), y + self:getAbsoluteY())
            local veh = pickVehicle(player, false)
            if veh then
                context:addOption("Empire: Travel here with the " .. vehName(veh), player, W.travelXY, wx, wy, true)
            end
            context:addOption("Empire: Travel here" .. (veh and " on foot" or ""), player, W.travelXY, wx, wy, false)
            context:addOption("Empire: Save a waypoint here...", player, promptSave, wx, wy)
        end)
        return ok
    end
end
Events.OnGameStart.Add(wrapWorldMap)
pcall(wrapWorldMap)

-- ---------- keys, vehicle memory, first-run seed ----------

-- Numpad 1 opens the Travel window (20_TravelMenu.lua); Shift+Numpad 1 is the old one-press home / back.
-- A text box with focus in that window keeps its own keys.
Events.OnKeyPressed.Add(function(key)
    local k1 = 79   -- lwjgl KEY_NUMPAD1
    pcall(function() if Keyboard and Keyboard.KEY_NUMPAD1 then k1 = Keyboard.KEY_NUMPAD1 end end)
    if key ~= k1 then return end
    local p = getSpecificPlayer(0)
    if not p or p:isDead() then return end
    local typing = false
    pcall(function()
        local ui = EmpireTravelUI and EmpireTravelUI.instance
        if ui and ui:isVisible() then
            for _, e in ipairs({ ui.xEntry, ui.yEntry, ui.zEntry, ui.nameEntry }) do
                if e and e:isFocused() then typing = true end
            end
        end
    end)
    if typing then return end
    local shift = false
    pcall(function() shift = isShiftKeyDown() end)
    if shift or not W.toggleUI then
        pcall(W.homeOrBack, p)
    else
        W.toggleUI(p)
    end
end)

-- YOUR vehicle = the last one you got into. Numpad 1 only ever takes that one, never a random wreck.
Events.OnEnterVehicle.Add(function(ch)
    local p = getSpecificPlayer(0)
    if not p or ch ~= p then return end
    local v = nil
    pcall(function() v = ch:getVehicle() end)
    local id = v and vehId(v) or nil
    if id then store().mine = id end
end)

Events.OnGameStart.Add(function()
    pending = nil
    Events.OnTick.Remove(onTick)
    local d = store()
    if not d.seeded then
        d.seeded = true
        if not indexOf(d, CFG.SEED.name) then
            d.list[#d.list + 1] = { name = CFG.SEED.name, x = CFG.SEED.x, y = CFG.SEED.y, z = CFG.SEED.z, hasV = false }
        end
    end
    local names = {}
    for _, w in ipairs(d.list) do names[#names + 1] = w.name end
    print(TAG .. "loaded: " .. #d.list .. " waypoints (" .. table.concat(names, ", ")
        .. "); Numpad 1 = Travel window, Shift+Numpad 1 = home/back, right-click > Empire: Travel")
end)
