-- Empire QoL :: 13_AutoChores.lua  (26 Nov 2026, B42.22)
-- King: "i love empire building but dont like the sorting and small things".
-- The two chores he did by hand every trip, now automatic:
--   AUTO-LOOT  zombies gone + corpses in reach + worn pack has room   -> Corpse Vacuum (was Numpad7)
--   AUTO-SORT  standing in the base + new loose loot to file           -> Smart Sort + consolidate (was Numpad3)
--   AUTO-PARK  park within the base dock: engine + headlights off, then unload the haul
--              (was: right-click truck -> "Transfer loot to base"; parked headlights drain the battery)
-- All still work by hand; this only presses the key for him at the right moment.
--
-- This file is also the CHORE REGISTRY (27 Nov 2026): 14_AutoNeeds (eat/drink), 15_AutoFarm,
-- 16_AutoProduction and 17_PreTripRestock call EmpireAutoChores.register(name, order, fn, opts)
-- and ride the same single beat, the same busy/zombie guards, the same per-chore breaker and
-- the same Numpad 5 master switch. One heavy chore per beat.
--
-- PERFORMANCE (the whole point of this rewrite): ONE heartbeat on Events.EveryTenMinutes
-- (game time, ~25 real seconds at the default day length). NO OnTick / OnPlayerUpdate /
-- OnPlayerMove handler, so there is no per-frame cost at all. The only other handlers are
-- one-shot events that do a counter bump or remember a vehicle: OnZombieDead (kills += 1),
-- OnEnterVehicle / OnExitVehicle. Each beat runs a handful of O(1)
-- guards first (alive, not driving, not mid-action, no zombies) and only then touches the
-- heavy code, and that code is the same already-tuned Vacuum/SmartSort the keys call.
-- A chore that throws 3 beats in a row switches itself off for the session and says so.
--
-- SAFETY: never runs with a zombie visible/chasing/very close, in a vehicle, asleep, or while a
-- timed action (eating, crafting, reading...) is in progress. Sort inherits SmartSort's own
-- protection: favourited, equipped and hotbar/holstered items and "Keep this bag" bags are never
-- moved. Star (favourite) anything you want to keep carrying.
--
-- TRIPS AND HOLDS (27 Nov 2026, bug hunt round 2). The sort used to treat every item that arrived on
-- him as loot, so a bag packed from the base shelves, or the quartermaster's hammer, planks and nails
-- mid-build, were filed straight back; and a park at the dock stayed armed after he drove off, so the
-- truck (and what he carried) were "unloaded" at the next stop. Now:
--   * a TRIP starts after TRIP_BEATS beats outside the base. Only a trip arms the arrival sort and the
--     dock unload; staying home, or a step out to the gate / dock / a perimeter wall, arms nothing.
--   * items he takes from base storage are HELD (the quartermasters 44/45/47/48 and the vanilla
--     transfer hook below mark them): an auto sort never moves them and they do not count as new loot.
--     Holds end when a trip starts, so what is left of a trip is filed when he gets home.
--   * a pending unload belongs to that truck at that dock: getting back into a vehicle drops it, an exit
--     away from the dock drops it, and the beat re-checks the dock and that he is still home.
-- Numpad 3 by hand still files everything (no holds).
--
-- Numpad 5 = master switch (saved per character). Config below.

local CFG = {
    LOOT_ENABLED    = true,   -- auto corpse vacuum
    SORT_ENABLED    = true,   -- auto smart sort at base
    SORT_CARRIED_ONLY = true, -- auto sorts file only what you carry (fast); the Numpad 3 key still does the whole base
    SORT_MIN_NEW    = 5,      -- carried item count must grow by this many since the last sort
    SORT_COOLDOWN   = 3,      -- beats (10 game-min each) between auto sorts
    LOOT_COOLDOWN   = 1,      -- beats between auto-loot attempts that found nothing
    MAX_FAILS       = 3,      -- consecutive throws before a chore disables itself
    LOOT_NEEDS_KILL = true,   -- only look for corpses after something died (idle beats cost nothing)
    UNLOAD_ENABLED  = true,   -- auto "Transfer loot to base" when you park at the base dock
    UNLOAD_MIN_ITEMS= 6,      -- the truck must hold this many items (a spare tire never triggers it)
    DOCK_RADIUS     = 8,      -- tiles from any painted base tile (same as the right-click option)
    PARK_ENABLED    = true,   -- engine + headlights off when you leave a vehicle at the dock
    SORT_SLOW_MS    = 250,    -- an auto sort slower than this lengthens the cooldown (hitch guard)
    LEAVE_BEATS     = 2,      -- a "just left the base" edge stays usable for this many beats
    TRIP_BEATS      = 3,      -- beats outside the base before it counts as a trip (~75 s; the gate, the dock and a perimeter wall are not trips)
    UNLOAD_AFTER_TRIP = true, -- only a truck coming home from a trip unloads (a gate stop on the way out never does)
    UNLOAD_REACH    = 16,     -- at the unload beat he must be in the base or within this many tiles of the truck
    HOLD_MAX        = 2000,   -- runaway guard for the held-items list (never reached in play)
}

local state = {
    beat           = 0,
    on             = true,
    lastSortBeat   = -99,
    lastLootBeat   = -99,
    kills          = 0,     -- zombies that died since the last loot attempt (OnZombieDead)
    lastVeh        = nil,   -- the vehicle the player is in (OnExitVehicle fires after they left it)
    pendingUnload  = nil,   -- a parked vehicle to unload on the next beat
    slowExtra      = 0,     -- extra cooldown beats after slow sorts
    carriedAtSort  = nil,   -- carried item count (all worn bags included) right after the last sort (or at start)
    vacuumedSince  = 0,     -- items auto-looted / harvested since the last sort
    packFull       = false, -- vacuum reported "did not fit"; wait for a sort to free room
    wasInBase      = false, -- in the base at the previous beat (edge detection for the pre-trip restock)
    leftBeat       = nil,   -- beat on which we noticed we had just left the base
    outBeats       = 0,     -- consecutive beats outside the base (TRIP_BEATS of them start a trip)
    away           = false, -- a trip happened since the last auto sort / unload: what he carries may be loot
    fails          = { loot = 0, sort = 0, unload = 0 },
    off            = { loot = false, sort = false, unload = false },
}
EmpireAutoChores = { cfg = CFG, state = state }   -- exposed for AutoTest / debugging

local function say(player, msg, good)
    pcall(function()
        HaloTextHelper.addTextWithArrow(player, msg, "[br/]", false,
            good and HaloTextHelper.getColorGreen() or HaloTextHelper.getColorWhite())
    end)
end

-- ---- HELD items: taken from base storage, so not loot ----
-- Keyed by item id, for this session only. Set by EmpireAutoChores.hold (quartermasters, the transfer
-- hook); cleared when a trip starts. A held bag holds what is inside it (a packed bag stays packed).
local held, heldN = {}, 0
local function itemId(it)
    local id = nil
    pcall(function() id = it:getID() end)
    return id
end
function EmpireAutoChores.hold(it)
    local id = itemId(it)
    if id == nil or held[id] then return end
    if heldN >= CFG.HOLD_MAX then held, heldN = {}, 0 end
    held[id] = true
    heldN = heldN + 1
end
function EmpireAutoChores.isHeld(it)
    if heldN == 0 or it == nil then return false end
    local cur = it
    for _ = 0, 4 do
        local id = itemId(cur)
        if id ~= nil and held[id] then return true end
        local bag = nil
        pcall(function() local c = cur:getContainer(); bag = c and c:getContainingItem() end)
        if not bag or bag == cur then return false end
        cur = bag
    end
    return false
end
EmpireAutoChores.heldCount = function() return heldN end
local function releaseHolds() held, heldN = {}, 0 end
-- the auto sort's itemFilter: everything may move except held items
local function notHeld(it) return not EmpireAutoChores.isHeld(it) end

-- Number of items on the player: the body inventory plus everything inside worn bags / rigs
-- (they are items of the body inventory), nested up to 3 deep. A cheap "did loot arrive"
-- signal; only evaluated at base after the cooldown, never per frame.
-- skipHeld: held items (and what is inside a held bag) are not counted.
local function countIn(cont, depth, skipHeld)
    local items, sz = nil, 0
    pcall(function() items = cont:getItems(); sz = items:size() end)
    if not items then return 0 end
    local n = sz
    if depth < 3 or skipHeld then
        for i = 0, sz - 1 do
            pcall(function()
                local it = items:get(i)
                if skipHeld then
                    local id = itemId(it)
                    if id ~= nil and held[id] then n = n - 1; return end
                end
                if depth < 3 and instanceof(it, "InventoryContainer") then
                    local sub = it:getInventory()
                    if sub and sub ~= cont then n = n + countIn(sub, depth + 1, skipHeld) end
                end
            end)
        end
    end
    return n
end
local function carriedCount(player, skipHeld)
    local n = 0
    pcall(function() n = countIn(player:getInventory(), 0, skipHeld == true and heldN > 0) end)
    return n
end

local function zombiesAround(player)
    local near = false
    pcall(function()
        local s = player:getStats()
        near = s:getNumVisibleZombies() > 0 or s:getNumChasingZombies() > 0 or s:getNumVeryCloseZombies() > 0
    end)
    return near
end

local function busy(player)
    if not player or player:isDead() then return true end
    local b = false
    pcall(function() b = player:isAsleep() end)
    if b then return true end
    pcall(function() b = player:getVehicle() ~= nil end)
    if b then return true end
    pcall(function()
        b = ISTimedActionQueue ~= nil and ISTimedActionQueue.isPlayerDoingAction ~= nil
            and ISTimedActionQueue.isPlayerDoingAction(player)
    end)
    if b then return true end
    return zombiesAround(player)
end

-- Returns ok, result. A chore that throws MAX_FAILS beats in a row switches itself off.
local function guard(name, fn, player, ctx)
    local ok, res = pcall(fn, player, ctx)
    if ok then
        state.fails[name] = 0
        return true, res
    end
    state.fails[name] = (state.fails[name] or 0) + 1
    print("[EmpireAutoChores] " .. name .. " threw: " .. tostring(res))
    if state.fails[name] >= CFG.MAX_FAILS then
        state.off[name] = true
        say(player, "Auto-" .. name .. " switched itself off (see console). Numpad 5 to re-arm.", false)
    end
    return false, nil
end

local function nowMs()
    local t = 0
    pcall(function() t = getTimestampMs() end)
    return t
end

local function inBase(player)
    local b = nil
    pcall(function() b = EmpireBases and EmpireBases.activeBase and EmpireBases.activeBase(player) end)
    return b ~= nil
end

-- ---- the chore registry ----
-- Every automation is a chore: EmpireAutoChores.register(name, order, fn, opts).
--   fn(player, ctx) runs on the 10-minute beat, only when the player is idle and safe (busy()
--   above). It returns true when it did heavy work: the beat then ends (one heavy chore per beat).
--   ctx = { beat, inBase, justLeft, consumeLeave() }.
--   opts.needsBase = true -> skipped unless the player is inside the base.
--   opts.enabled   = function() -> false to skip (config switch).
-- Lower order runs first: needs 10, unload 20, sort 30, loot 40, farm 50, production 60, restock 70.
local chores = {}
function EmpireAutoChores.register(name, order, fn, opts)
    for i = #chores, 1, -1 do if chores[i].name == name then table.remove(chores, i) end end
    chores[#chores + 1] = { name = name, order = order or 100, fn = fn, opts = opts or {} }
    table.sort(chores, function(a, b) return a.order < b.order end)
    if state.fails[name] == nil then state.fails[name] = 0 end
    if state.off[name] == nil then state.off[name] = false end
end
EmpireAutoChores.chores = chores
-- shared helpers for the chore modules (14_..17_)
EmpireAutoChores.say, EmpireAutoChores.busy, EmpireAutoChores.zombiesAround = say, busy, zombiesAround

-- ---- shared helpers for the chore modules (so 14_..17_ do not each carry a copy) ----
local unpack = unpack or table.unpack
-- m(obj, "method", args...) -> the value, or nil if the object is nil / has no such method / it throws
function EmpireAutoChores.m(obj, name, ...)
    if obj == nil then return nil end
    local args = { ... }
    local ok, v = pcall(function() return obj[name](obj, unpack(args)) end)
    if ok then return v end
    return nil
end
local m = EmpireAutoChores.m

-- Every container the survivor carries: the body inventory plus worn bags / rigs, nested up to 4 deep.
function EmpireAutoChores.carriedContainers(player)
    local out, seen = {}, {}
    local function rec(cont, depth)
        if not cont or seen[cont] or depth > 4 then return end
        seen[cont] = true
        out[#out + 1] = cont
        local items = nil
        pcall(function() items = cont:getItems() end)
        if not items then return end
        for i = 0, (m(items, "size") or 0) - 1 do
            local it = m(items, "get", i)
            local isBag = false
            pcall(function() isBag = instanceof(it, "InventoryContainer") end)
            if isBag then
                local sub = m(it, "getInventory")
                if sub and sub ~= cont then rec(sub, depth + 1) end
            end
        end
    end
    rec(m(player, "getInventory"), 0)
    return out
end

-- The base's storage containers (EmpireBaseCache: nil outside the base, so out of reach = nil here too).
function EmpireAutoChores.baseContainers()
    local list = nil
    pcall(function()
        local c = EmpireBaseCache and EmpireBaseCache.get and EmpireBaseCache.get()
        if c and c.containers and #c.containers > 0 then list = c.containers end
    end)
    return list
end

-- Move a REAL item from a base container into the body inventory, instantly, the way the quartermaster
-- (44_CraftFromBase) does: timed actions need the item on the player, nothing is spawned.
function EmpireAutoChores.fetch(player, it, cont)
    local main = m(player, "getInventory")
    if not main or cont == main then return true end
    local ok = pcall(function() main:addItem(it); cont:Remove(it) end)
    if ok then
        pcall(function() EmpireBaseCache.invalidate() end)
        pcall(function() if EmpireSortAll and EmpireSortAll.refreshUI then EmpireSortAll.refreshUI() end end)
    end
    return ok
end
EmpireAutoChores.inBase, EmpireAutoChores.carriedCount, EmpireAutoChores.nowMs = inBase, carriedCount, nowMs
-- loot that arrived by other means (harvest...) so the next beat at base files it
function EmpireAutoChores.noteLoot(n) state.vacuumedSince = state.vacuumedSince + (tonumber(n) or 0) end

-- ---- built-in chores ----
local function doLoot(player)
    if type(EmpireQoL_Vacuum) ~= "function" then return false end
    state.kills = 0   -- one look per fight: the next kill re-arms it
    local grabbed, full = EmpireQoL_Vacuum({ auto = true })
    grabbed = tonumber(grabbed) or 0
    if grabbed > 0 then state.vacuumedSince = state.vacuumedSince + grabbed end
    if full then state.packFull = true end
    return grabbed > 0
end

local function doSort(player)
    if not (EmpireSortAll and EmpireSortAll.run) then return end
    local t0 = nowMs()
    EmpireSortAll.run(player, { carriedOnly = CFG.SORT_CARRIED_ONLY, itemFilter = notHeld })
    local ms = nowMs() - t0
    -- a sort is one synchronous frame: if it hitched, wait longer before the next one
    if ms > CFG.SORT_SLOW_MS then state.slowExtra = math.min(state.slowExtra + 3, 12) end
    print("[EmpireAutoChores] auto-sort took " .. ms .. " ms (extra cooldown " .. state.slowExtra .. " beats)")
    state.lastSortBeat  = state.beat
    state.vacuumedSince = 0
    state.packFull      = false
    state.away          = false
    state.carriedAtSort = carriedCount(player, true)
end

local function vehicleDocked(veh)
    local docked = false
    pcall(function() docked = EmpireBases and EmpireBases.vehicleNearBase and EmpireBases.vehicleNearBase(veh, CFG.DOCK_RADIUS) end)
    return docked == true
end

local function nearVehicle(player, veh, r)
    local near = false
    pcall(function()
        local dx, dy = player:getX() - veh:getX(), player:getY() - veh:getY()
        near = (dx * dx + dy * dy) <= r * r
    end)
    return near
end

local function doUnload(player)
    local veh = state.pendingUnload
    state.pendingUnload = nil
    if not veh or not (EmpireSortAll and EmpireSortAll.transferVehicle) then return end
    -- the park must still be true: that truck still at the dock, and him still home (in the base or by
    -- the truck). A park that went stale never unloads the truck, or his pack, from somewhere else.
    if not vehicleDocked(veh) then return end
    if not (inBase(player) or nearVehicle(player, veh, CFG.UNLOAD_REACH)) then return end
    local n = EmpireSortAll.transferVehicle(player, veh, CFG.UNLOAD_MIN_ITEMS, { itemFilter = notHeld })
    if n and n > 0 then
        say(player, "Unloaded the vehicle into base storage (" .. n .. " items)", true)
        state.vacuumedSince = 0   -- the truck unload also filed what was carried
        state.packFull = false
        state.away = false
        state.carriedAtSort = carriedCount(player, true)
    end
end

-- a vehicle was parked at the dock: unload it (this is the heavy chore of the beat)
EmpireAutoChores.register("unload", 20, function(player)
    if not state.pendingUnload then return false end
    if CFG.UNLOAD_ENABLED then doUnload(player) else state.pendingUnload = nil end
    return true
end)

-- sort when we are home: files whatever the last trip brought in
EmpireAutoChores.register("sort", 30, function(player, ctx)
    if not CFG.SORT_ENABLED or not ctx.inBase then return false end
    -- home since the last sort and nothing auto-looted: whatever arrived on him came off the base's
    -- own shelves (a bag packed for a trip, a quartermaster fetch, a can opener), not loot
    if not state.away and state.vacuumedSince <= 0 then return false end
    if (state.beat - state.lastSortBeat) < (CFG.SORT_COOLDOWN + state.slowExtra) then return false end
    local now = carriedCount(player, true)
    local grew = now - (state.carriedAtSort or now)
    if state.vacuumedSince > 0 or grew >= CFG.SORT_MIN_NEW then
        doSort(player)
        say(player, "Auto-sorted your loot into base storage", true)
        return true
    end
    -- home from a trip with nothing worth filing: from here on, what he picks up at home is his own stock
    state.away = false
    return false
end)

-- loot nearby corpses once it is quiet (skipped while the pack is full: nothing to gain)
EmpireAutoChores.register("loot", 40, function(player)
    if not CFG.LOOT_ENABLED or state.packFull then return false end
    if not (state.kills > 0 or not CFG.LOOT_NEEDS_KILL) then return false end
    if (state.beat - state.lastLootBeat) < CFG.LOOT_COOLDOWN then return false end
    state.lastLootBeat = state.beat
    return doLoot(player)
end)

local function onBeat()
    state.beat = state.beat + 1
    if not state.on then return end
    local player = getSpecificPlayer(0)
    if not player or player:isDead() then return end
    -- base edge tracking happens before the busy check so a busy beat does not lose it
    local nowIn = inBase(player)
    if state.wasInBase and not nowIn then state.leftBeat = state.beat end
    if nowIn then state.leftBeat = nil; state.outBeats = 0 else state.outBeats = state.outBeats + 1 end
    if state.outBeats == CFG.TRIP_BEATS then
        -- a trip starts: what he left with is his kit, not loot, and the holds on what he took end here
        state.away = true
        releaseHolds()
        state.carriedAtSort = carriedCount(player)
    end
    state.wasInBase = nowIn
    -- back in a vehicle: the park is over (OnEnterVehicle normally clears it already)
    if state.pendingUnload then
        local inVeh = false
        pcall(function() inVeh = player:getVehicle() ~= nil end)
        if inVeh then state.pendingUnload = nil end
    end
    if busy(player) then return end
    local ctx = {
        beat = state.beat, inBase = nowIn,
        justLeft = (not nowIn) and state.leftBeat ~= nil and (state.beat - state.leftBeat) <= CFG.LEAVE_BEATS,
        consumeLeave = function() state.leftBeat = nil end,
    }
    for _, c in ipairs(chores) do
        local o = c.opts
        if not state.off[c.name] and not (o.needsBase and not nowIn)
           and not (o.enabled and not o.enabled()) then
            local ok, heavy = guard(c.name, c.fn, player, ctx)
            if not ok or heavy then return end
        end
    end
end

Events.EveryTenMinutes.Add(onBeat)

-- OnZombieDead: a counter bump and nothing else (fires for every zombie that dies).
Events.OnZombieDead.Add(function() state.kills = state.kills + 1 end)

-- ---- parking at the base dock ----
-- OnExitVehicle fires AFTER the player left the vehicle (getVehicle() is already nil), so
-- remember it on entry. Same pattern as the old 4_AutoEngineOff.
local function isLocal(ch)
    local ok = false
    pcall(function() ok = ch ~= nil and instanceof(ch, "IsoPlayer") and ch:isLocalPlayer() end)
    return ok
end

Events.OnEnterVehicle.Add(function(ch)
    if isLocal(ch) then
        state.pendingUnload = nil   -- driving again: the park is over (the next docked exit re-arms it)
        pcall(function() state.lastVeh = ch:getVehicle() end)
    end
end)

local function onExitVehicle(ch)
    local veh = state.lastVeh
    state.lastVeh = nil
    state.pendingUnload = nil       -- only this exit can arm an unload, and only at the dock
    if not veh or not state.on then return end
    if not vehicleDocked(veh) then return end
    if CFG.PARK_ENABLED then
        local running = false
        pcall(function() running = veh:isEngineRunning() end)
        if running then pcall(function() veh:shutOff() end) end
        pcall(function() veh:setHeadlightsOn(false) end)   -- a parked car's lights drain the battery
        if running then say(ch, "Parked: engine off", false) end
    end
    -- unload a truck coming home from a trip; a stop at the gate on the way out keeps the trip's supplies
    if CFG.UNLOAD_ENABLED and not state.off.unload and (state.away or not CFG.UNLOAD_AFTER_TRIP) then
        state.pendingUnload = veh
    end
end

Events.OnExitVehicle.Add(function(ch)
    if isLocal(ch) then pcall(onExitVehicle, ch) end
end)

-- ---- taking things off the base's own shelves: hold them ----
-- Vanilla moves every item through ISInventoryTransferAction:transferItem (drag, grab, "transfer all",
-- a vanilla craft gathering its ingredients). From a container that is not his onto him, while he is in
-- the base: that came out of his own storage, so it is held. A corpse is loot and is never held.
local function noteTransfer(action)
    local p, src, it = action.character, action.srcContainer, action.item
    if not (it and src and isLocal(p)) then return end
    local dst = nil
    pcall(function() dst = it:getContainer() end)
    if not (dst and dst:isInCharacterInventory(p)) then return end
    if src:isInCharacterInventory(p) then return end
    if instanceof(src:getParent(), "IsoDeadBody") then return end
    if inBase(p) then EmpireAutoChores.hold(it) end
end
local transferWrapped = false
Events.OnGameStart.Add(function()
    local T = ISInventoryTransferAction
    if transferWrapped or not (T and T.transferItem) then return end
    local orig = T.transferItem
    T.transferItem = function(self, ...)
        local r = orig(self, ...)
        pcall(noteTransfer, self)
        return r
    end
    transferWrapped = true
end)

-- ---- master switch (Numpad 5), saved per character ----
local function modData(player)
    local md = nil
    pcall(function() md = player:getModData() end)
    return md
end

local function applyToggle(player, on)
    state.on = on
    for k in pairs(state.off) do state.off[k] = false end
    for k in pairs(state.fails) do state.fails[k] = 0 end
    local md = modData(player)
    if md then md.EmpireAutoChoresOff = (not on) or nil end
    say(player, on and "Auto-chores ON (needs, loot, sort, farm, production, restock)" or "Auto-chores OFF", on)
end
EmpireAutoChores.toggle = function()
    local p = getSpecificPlayer(0)
    if p and not p:isDead() then applyToggle(p, not state.on) end
end

Events.OnKeyPressed.Add(function(key)
    local k5 = 76   -- lwjgl KEY_NUMPAD5
    pcall(function() if Keyboard and Keyboard.KEY_NUMPAD5 then k5 = Keyboard.KEY_NUMPAD5 end end)
    if key == k5 then pcall(EmpireAutoChores.toggle) end
end)

Events.OnGameStart.Add(function()
    local p = getSpecificPlayer(0)
    if not p then return end
    local md = modData(p)
    if md and md.EmpireAutoChoresOff then state.on = false end
    -- baseline so loading a save inside the base does not trigger a sort of what was already carried
    state.carriedAtSort = carriedCount(p)
    state.beat, state.lastSortBeat, state.lastLootBeat = 0, -99, -99
    state.kills, state.lastVeh, state.pendingUnload, state.slowExtra = 0, nil, nil, 0
    state.wasInBase, state.leftBeat = inBase(p), nil
    state.outBeats, state.away = 0, not state.wasInBase   -- loaded outside the base: on a trip
    releaseHolds()
    local names = {}
    for _, c in ipairs(chores) do names[#names + 1] = c.name end
    print("[EmpireQoL] AutoChores loaded: one 10-min beat, " .. (state.on and "ON" or "OFF")
        .. " (Numpad 5 toggles). chores=" .. table.concat(names, ","))
end)
