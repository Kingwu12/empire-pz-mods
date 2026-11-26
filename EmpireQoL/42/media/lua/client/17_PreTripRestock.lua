-- Empire QoL :: 17_PreTripRestock.lua  (27 Nov 2026, B42.22)
-- King: "i love empire building but dont like the sorting and small things".
-- PRE-TRIP RESTOCK: before he heads out, the survivor's guns are stocked from base storage, the way a crew
-- member checks a kit before a run. For every ranged weapon in his hands or on his hotbar (the same guns
-- the sorter already protects as "loadout"):
--   * MAG_TARGET spare magazines of that gun's magazine type (fullest first),
--   * ROUND_TARGET loose rounds of its ammo type,
-- taken from base storage into the body inventory (real items moved, never spawned), then the vanilla
-- load actions fill the mags (39_TopOffMags, the game's own ISLoadBulletsInMagazine).
-- Three moments, none per frame:
--   BASE    every 10-minute beat while he is inside the base (only does anything when a gun is short),
--   VEHICLE the moment he gets into a vehicle inside the base (one-shot OnEnterVehicle; instant moves only),
--   EDGE    a beat or two after he walked out of the base, if he is still close and the base's storage is
--           still loaded: catches the case where he left before the beat came round (uses the last base
--           index, EmpireBaseCache.peek(); every container is checked to still sit on a loaded square).
-- It never takes guns, never takes favourites, never goes over 90% of his carry weight, and backs off for
-- an hour of game time per ammo type the base has none of.
--
-- PERFORMANCE: the check is a walk over what he carries (a few dozen items) once per beat, plus a base index
-- lookup only when something is short. No scan of the world, no per-frame handler.

local CFG = {
    ENABLED       = true,
    MAG_TARGET    = 3,    -- spare mags per magazine type
    ROUND_TARGET  = 40,   -- loose rounds per ammo type
    MAX_MOVE      = 150,  -- items moved per restock (instant list moves; three guns need ~130)
    BACKOFF_BEATS = 6,    -- an ammo type the base has none of is not looked for again for this many beats
    WEIGHT_LIMIT  = 0.9,  -- do not pack more above this fraction of max carry weight
    EDGE_REACH    = 30,   -- tiles from the base rectangle within which the EDGE catch-up still runs
    TOPOFF        = true, -- queue the vanilla mag-loading afterwards (BASE path only)
    TOPOFF_EVERY  = 6,    -- beats between "are any mags part-empty?" checks when nothing was restocked
}

local AC = EmpireAutoChores
local m = AC.m

local state = { backoff = {}, lastTopOff = -99, last = nil }
EmpireAutoRestock = { cfg = CFG, state = state }

local function lower(s) return tostring(s or ""):lower() end

local function isRangedGun(w)
    local g = false
    pcall(function() g = w ~= nil and instanceof(w, "HandWeapon") and w:isRanged() == true end)
    return g
end

-- ammo item full type of a gun / magazine (vanilla reads it as getAmmoType():getItemKey())
local function ammoKey(x)
    local at = m(x, "getAmmoType")
    if at == nil then return nil end
    if type(at) == "string" then return at ~= "" and at or nil end
    local k = m(at, "getItemKey")
    return k and tostring(k) or nil
end

-- the ranged weapons he is actually carrying ready: hands + hotbar (the sorter's own loadout set)
local function guns(player)
    local out, seen = {}, {}
    local function add(w) if w and not seen[w] and isRangedGun(w) then seen[w] = true; out[#out + 1] = w end end
    add(m(player, "getPrimaryHandItem")); add(m(player, "getSecondaryHandItem"))
    pcall(function()
        local hb = getPlayerHotbar(player:getPlayerNum())
        if hb and hb.attachedItems then for _, it in pairs(hb.attachedItems) do add(it) end end
    end)
    return out
end

-- what the guns want: wantMag[fullType] = target, wantRound[fullType] = target
local function wants(gs)
    local wm, wr = {}, {}
    for _, g in ipairs(gs) do
        local mt = m(g, "getMagazineType")
        if type(mt) == "string" and mt ~= "" then wm[mt] = CFG.MAG_TARGET end
        local ak = ammoKey(g)
        if ak then wr[ak] = CFG.ROUND_TARGET end
    end
    return wm, wr
end

local function weightRatio(player)
    local r = 0
    pcall(function()
        local w, mx = player:getInventoryWeight(), player:getMaxWeight()
        if w and mx and mx > 0 then r = w / mx end
    end)
    return r
end

-- carried counts of the wanted types (lower-cased full type -> n), over every carried container
local function carriedCounts(player, wm, wr)
    local cm, cr = {}, {}
    local lm, lr = {}, {}
    for ft in pairs(wm) do lm[lower(ft)] = ft end
    for ft in pairs(wr) do lr[lower(ft)] = ft end
    for _, cont in ipairs(AC.carriedContainers(player)) do
        local items = nil
        pcall(function() items = cont:getItems() end)
        local n = items and (m(items, "size") or 0) or 0
        for i = 0, n - 1 do
            local it = m(items, "get", i)
            local ft = it and lower(m(it, "getFullType"))
            if ft then
                if lm[ft] then cm[lm[ft]] = (cm[lm[ft]] or 0) + 1 end
                if lr[ft] then cr[lr[ft]] = (cr[lr[ft]] or 0) + 1 end
            end
        end
    end
    return cm, cr
end

-- is this base container still safe to take from (its object sits on a loaded square)?
local function live(cont)
    local parent = m(cont, "getParent")
    return parent ~= nil and m(parent, "getSquare") ~= nil
end

local function sourcesFor(ft, how)
    local list = {}
    if how == "edge" then
        local pk = nil
        pcall(function() pk = EmpireBaseCache.peek() end)
        local rec = pk and pk.byType and pk.byType[ft]
        for _, c in ipairs(rec and rec.containers or {}) do if live(c) then list[#list + 1] = c end end
    else
        pcall(function() list = EmpireBaseCache.containersFor(ft) or {} end)
    end
    return list
end

-- take up to `n` items of exact type `ft` from `srcs` into the body inventory; mags fullest first
local function take(player, ft, n, srcs, isMag)
    local cands = {}
    for _, src in ipairs(srcs) do
        local items = nil
        pcall(function() items = src:getItems() end)
        local c = items and (m(items, "size") or 0) or 0
        for i = 0, c - 1 do
            local it = m(items, "get", i)
            if it and m(it, "getFullType") == ft and not m(it, "isFavorite") then
                cands[#cands + 1] = { item = it, src = src, ammo = isMag and (tonumber(m(it, "getCurrentAmmoCount")) or 0) or 0 }
            end
        end
    end
    if isMag then table.sort(cands, function(a, b) return a.ammo > b.ammo end) end
    local got = 0
    for _, c in ipairs(cands) do
        if got >= n then break end
        if AC.fetch(player, c.item, c.src) then got = got + 1 else break end
    end
    return got
end

-- Returns mags, rounds moved. how = "base" | "vehicle" | "edge".
local function restock(player, how)
    local gs = guns(player)
    if #gs == 0 then return 0, 0 end
    if weightRatio(player) >= CFG.WEIGHT_LIMIT then return 0, 0 end
    local wm, wr = wants(gs)
    local cm, cr = carriedCounts(player, wm, wr)
    local beat = AC.state.beat or 0
    local budget, magsMoved, roundsMoved = CFG.MAX_MOVE, 0, 0

    local function step(want, have, isMag)
        for ft, target in pairs(want) do
            local deficit = target - (have[ft] or 0)
            if deficit > 0 and budget > 0 and (state.backoff[ft] or 0) <= beat then
                local srcs = sourcesFor(ft, how)
                local got = (#srcs > 0) and take(player, ft, math.min(deficit, budget), srcs, isMag) or 0
                budget = budget - got
                if got == 0 then state.backoff[ft] = beat + CFG.BACKOFF_BEATS end
                if isMag then magsMoved = magsMoved + got else roundsMoved = roundsMoved + got end
            end
        end
    end
    step(wm, cm, true)
    step(wr, cr, false)
    if magsMoved + roundsMoved > 0 then
        state.last = { how = how, beat = beat, mags = magsMoved, rounds = roundsMoved }
        AC.say(player, string.format("Packed for the trip: %d mags, %d rounds", magsMoved, roundsMoved), true)
        print(string.format("[EmpireAutoRestock] %s: +%d mags +%d rounds", how, magsMoved, roundsMoved))
    end
    return magsMoved, roundsMoved
end
EmpireAutoRestock.restock = restock

-- ---- EDGE: still close to the base after leaving it? ----
local function baseRect(name)
    local b = nil
    pcall(function() b = EmpireBases.getEmpireZoneBase() end)
    if b and (name == nil or name == "Main" or b.name == name) then return b end
    pcall(function()
        for _, x in ipairs(EmpireBases.list()) do if x.name == name then b = x; break end end
    end)
    return b
end

local function nearBase(player)
    local pk = nil
    pcall(function() pk = EmpireBaseCache.peek() end)
    if not pk then return false end
    local b = baseRect(pk.base)
    if not b then return false end
    local px, py = 0, 0
    pcall(function() px, py = player:getX(), player:getY() end)
    local dx = math.max(math.min(b.x1, b.x2) - px, 0, px - math.max(b.x1, b.x2))
    local dy = math.max(math.min(b.y1, b.y2) - py, 0, py - math.max(b.y1, b.y2))
    return math.max(dx, dy) <= CFG.EDGE_REACH
end

-- ---- the beat chore ----
local function chore(player, ctx)
    if not CFG.ENABLED then return false end
    local how = nil
    if ctx.inBase then how = "base"
    elseif ctx.justLeft then how = "edge"
    else return false end
    if how == "edge" then
        ctx.consumeLeave()          -- one catch-up per departure
        if not nearBase(player) then return false end
    end
    local mags, rounds = restock(player, how)
    if how ~= "base" or not CFG.TOPOFF or type(EmpireQoL_TopOffMags) ~= "function" then return false end
    -- fill the mags with the vanilla load actions: right after a restock, else now and then
    local beat = ctx.beat
    if (mags + rounds) == 0 and (beat - state.lastTopOff) < CFG.TOPOFF_EVERY then return false end
    state.lastTopOff = beat
    local queued = 0
    pcall(function() queued = EmpireQoL_TopOffMags(player, { quiet = true }) or 0 end)
    return queued > 0               -- timed actions queued: that is the heavy work of this beat
end
EmpireAutoRestock.run = chore

-- ---- VEHICLE: boarding inside the base (one-shot event, instant moves only) ----
local function isLocal(player)
    local ok = false
    pcall(function() ok = (player == getSpecificPlayer(0)) or (player:isLocalPlayer() == true) end)
    return ok
end
local function onEnterVehicle(player)
    if not CFG.ENABLED or not isLocal(player) then return end
    local on = true
    pcall(function() on = AC.state.on ~= false and not AC.state.off.restock end)
    if not on then return end
    local inBase = false
    pcall(function() inBase = EmpireBases.activeBase(player) ~= nil end)
    if not inBase then return end
    pcall(restock, player, "vehicle")
end
Events.OnEnterVehicle.Add(onEnterVehicle)

if AC and AC.register then
    AC.register("restock", 70, chore, { enabled = function() return CFG.ENABLED end })
end

print("[EmpireQoL] PreTripRestock loaded: stocks hand/hotbar guns with spare mags + rounds from base storage (base beat, vehicle boarding, just-left-base).")
