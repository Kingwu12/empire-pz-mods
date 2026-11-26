-- Empire QoL :: 13_AutoChores.lua  (26 Nov 2026, B42.22)
-- King: "i love empire building but dont like the sorting and small things".
-- The two chores he did by hand every trip, now automatic:
--   AUTO-LOOT  zombies gone + corpses in reach + worn pack has room   -> Corpse Vacuum (was Numpad7)
--   AUTO-SORT  standing in the base + new loose loot to file           -> Smart Sort + consolidate (was Numpad3)
--   AUTO-PARK  park within the base dock: engine + headlights off, then unload the haul
--              (was: right-click truck -> "Transfer loot to base"; parked headlights drain the battery)
-- All still work by hand; this only presses the key for him at the right moment.
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
-- Numpad 5 = master switch (saved per character). Config below.

local CFG = {
    LOOT_ENABLED    = true,   -- auto corpse vacuum
    SORT_ENABLED    = true,   -- auto smart sort at base
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
    carriedAtSort  = nil,   -- carried top-level item count right after the last sort (or at start)
    vacuumedSince  = 0,     -- items auto-looted since the last sort
    packFull       = false, -- vacuum reported "did not fit"; wait for a sort to free room
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

-- number of top-level items in the body inventory + the worn back bag: a cheap "did loot arrive" signal
local function carriedCount(player)
    local n = 0
    pcall(function() n = n + player:getInventory():getItems():size() end)
    pcall(function()
        local back = player:getClothingItem_Back()
        if back and back.getInventory then n = n + back:getInventory():getItems():size() end
    end)
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

local function guard(name, fn, player)
    local ok, err = pcall(fn, player)
    if ok then
        state.fails[name] = 0
        return true
    end
    state.fails[name] = state.fails[name] + 1
    print("[EmpireAutoChores] " .. name .. " threw: " .. tostring(err))
    if state.fails[name] >= CFG.MAX_FAILS then
        state.off[name] = true
        say(player, "Auto-" .. name .. " switched itself off (see console). Numpad 5 to re-arm.", false)
    end
    return false
end

local function doLoot(player)
    if type(EmpireQoL_Vacuum) ~= "function" then return end
    state.kills = 0   -- one look per fight: the next kill re-arms it
    local grabbed, full = EmpireQoL_Vacuum({ auto = true })
    grabbed = tonumber(grabbed) or 0
    if grabbed > 0 then state.vacuumedSince = state.vacuumedSince + grabbed end
    if full then state.packFull = true end
end

local function nowMs()
    local t = 0
    pcall(function() t = getTimestampMs() end)
    return t
end

local function doSort(player)
    if not (EmpireSortAll and EmpireSortAll.run) then return end
    local t0 = nowMs()
    EmpireSortAll.run(player)
    local ms = nowMs() - t0
    -- a whole-base sort is one synchronous frame: if it hitched, wait longer before the next one
    if ms > CFG.SORT_SLOW_MS then state.slowExtra = math.min(state.slowExtra + 3, 12) end
    print("[EmpireAutoChores] auto-sort took " .. ms .. " ms (extra cooldown " .. state.slowExtra .. " beats)")
    state.lastSortBeat  = state.beat
    state.vacuumedSince = 0
    state.packFull      = false
    state.carriedAtSort = carriedCount(player)
end

local function inBase(player)
    local b = nil
    pcall(function() b = EmpireBases and EmpireBases.activeBase and EmpireBases.activeBase(player) end)
    return b ~= nil
end

local function doUnload(player)
    local veh = state.pendingUnload
    state.pendingUnload = nil
    if not veh or not (EmpireSortAll and EmpireSortAll.transferVehicle) then return end
    local n = EmpireSortAll.transferVehicle(player, veh, CFG.UNLOAD_MIN_ITEMS)
    if n and n > 0 then
        say(player, "Unloaded the vehicle into base storage (" .. n .. " items)", true)
        state.vacuumedSince = 0   -- the truck unload also filed what was carried
        state.packFull = false
        state.carriedAtSort = carriedCount(player)
    end
end

local function onBeat()
    state.beat = state.beat + 1
    if not state.on then return end
    local player = getSpecificPlayer(0)
    if busy(player) then return end

    -- 0) a vehicle was parked at the dock: unload it (one heavy chore this beat)
    if state.pendingUnload then
        if CFG.UNLOAD_ENABLED and not state.off.unload then
            guard("unload", doUnload, player)
        else
            state.pendingUnload = nil
        end
        return
    end

    -- 1) sort first when we are home: files whatever the last trip brought in
    if CFG.SORT_ENABLED and not state.off.sort
       and (state.beat - state.lastSortBeat) >= (CFG.SORT_COOLDOWN + state.slowExtra) and inBase(player) then
        local grew = carriedCount(player) - (state.carriedAtSort or carriedCount(player))
        if state.vacuumedSince > 0 or grew >= CFG.SORT_MIN_NEW then
            if guard("sort", doSort, player) then
                say(player, "Auto-sorted your loot into base storage", true)
            end
            return   -- one heavy chore per beat
        end
    end

    -- 2) loot nearby corpses once it is quiet (skipped while the pack is full: nothing to gain)
    if CFG.LOOT_ENABLED and not state.off.loot and not state.packFull
       and (state.kills > 0 or not CFG.LOOT_NEEDS_KILL)
       and (state.beat - state.lastLootBeat) >= CFG.LOOT_COOLDOWN then
        state.lastLootBeat = state.beat
        guard("loot", doLoot, player)
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
    if isLocal(ch) then pcall(function() state.lastVeh = ch:getVehicle() end) end
end)

local function onExitVehicle(ch)
    local veh = state.lastVeh
    state.lastVeh = nil
    if not veh or not state.on then return end
    local docked = false
    pcall(function() docked = EmpireBases and EmpireBases.vehicleNearBase and EmpireBases.vehicleNearBase(veh, CFG.DOCK_RADIUS) end)
    if not docked then return end
    if CFG.PARK_ENABLED then
        local running = false
        pcall(function() running = veh:isEngineRunning() end)
        if running then pcall(function() veh:shutOff() end) end
        pcall(function() veh:setHeadlightsOn(false) end)   -- a parked car's lights drain the battery
        if running then say(ch, "Parked: engine off", false) end
    end
    if CFG.UNLOAD_ENABLED and not state.off.unload then state.pendingUnload = veh end
end

Events.OnExitVehicle.Add(function(ch)
    if isLocal(ch) then pcall(onExitVehicle, ch) end
end)

-- ---- master switch (Numpad 5), saved per character ----
local function modData(player)
    local md = nil
    pcall(function() md = player:getModData() end)
    return md
end

local function applyToggle(player, on)
    state.on = on
    state.off.loot, state.off.sort, state.off.unload = false, false, false
    state.fails.loot, state.fails.sort, state.fails.unload = 0, 0, 0
    local md = modData(player)
    if md then md.EmpireAutoChoresOff = (not on) or nil end
    say(player, on and "Auto-chores ON (auto-loot corpses, auto-sort at base)" or "Auto-chores OFF", on)
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
    print("[EmpireQoL] AutoChores loaded: one 10-min beat, " .. (state.on and "ON" or "OFF")
        .. " (Numpad 5 toggles). loot=" .. tostring(CFG.LOOT_ENABLED) .. " sort=" .. tostring(CFG.SORT_ENABLED))
end)
