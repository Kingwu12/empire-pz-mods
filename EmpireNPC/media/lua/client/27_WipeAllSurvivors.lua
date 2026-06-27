-- Empire NPC - Wipe All Survivors (clean-slate reset, via KILL not delete)
-- Deleting a loaded survivor rips their tile away; if they were mid-swing the queued attack event
-- fires next frame on a tile-less character -> hard crash. SSC has no safe mass-remove of its own.
-- So instead of deleting, we KILL: death is the engine's own removal path, the body stays ON its
-- tile (so the null-tile crash can't occur), and SSC drops them from the roster on death. We empty
-- their inventory first so there's no loot pile. Two-step: BACKSPACE once = count + arm; again
-- within 8s = wipe. Killed a few per tick so there's no frame spike.

local WIPE_KEY      = Keyboard.KEY_BACK
local ARM_WINDOW_MS = 8000
local PER_TICK      = 3

local armed, armedAt = false, 0
local job = nil

local function notify(t, c)
    local p = getSpecificPlayer(0)
    if p then pcall(function() HaloTextHelper.addText(p, t, c) end) end
end

-- living, loaded SSC survivors, excluding you
local function loadedSurvivors()
    local out, player = {}, getSpecificPlayer(0)
    if not (SSM and SSM.SuperSurvivors) then return out end
    for _, ss in pairs(SSM.SuperSurvivors) do
        if ss then
            local ch; pcall(function() ch = ss:Get() end)
            local dead = true; pcall(function() dead = ch:isDead() end)
            if ch and ch ~= player and not dead then out[#out + 1] = ss end
        end
    end
    return out
end

-- empty their pockets (no loot pile), then kill -- body stays on tile, SSC removes from roster
local function killOff(ss)
    local ch; pcall(function() ch = ss:Get() end)
    if not ch then return end
    pcall(function() ch:getInventory():emptyIt() end)
    pcall(function() ch:setPrimaryHandItem(nil) end)
    pcall(function() ch:setSecondaryHandItem(nil) end)
    pcall(function() ch:setHealth(0) end)
    pcall(function() ch:Kill(getSpecificPlayer(0)) end)
end

-- staggered kill loop: runs only while a wipe job is active
Events.OnTick.Add(function()
    if not job then return end
    local done = 0
    while done < PER_TICK do
        local ss = table.remove(job.list)
        if not ss then
            job = nil
            notify("Survivors wiped -- press INSERT to rebuild crew", HaloTextHelper.getColorGreen())
            print("[EmpireNPC WipeAll] wipe complete.")
            return
        end
        killOff(ss)
        done = done + 1
    end
end)

local function run()
    if job then notify("Wipe already running...", HaloTextHelper.getColorRed()); return end
    local list = loadedSurvivors()
    local n = #list
    local now = getTimestampMs()

    if not armed or (now - armedAt) > ARM_WINDOW_MS then
        armed, armedAt = true, now
        if n == 0 then
            notify("No survivors loaded to wipe", HaloTextHelper.getColorGreen()); armed = false
        else
            notify("WIPE ALL " .. n .. " survivors? Press BACKSPACE again to confirm.", HaloTextHelper.getColorRed())
        end
        return
    end

    armed = false
    job = { list = loadedSurvivors() }
    notify("Wiping " .. #job.list .. " survivors...", HaloTextHelper.getColorRed())
    print("[EmpireNPC WipeAll] killing " .. #job.list .. " survivors, staggered.")
end

local function onKey(key)
    if key ~= WIPE_KEY then return end
    local p = getSpecificPlayer(0)
    if not p or p:isDead() then return end
    if not (SSM and type(SSM.SuperSurvivors) == "table") then return end
    pcall(run)
end
Events.OnKeyPressed.Add(onKey)

print("[EmpireNPC] Wipe All Survivors loaded (kill-based, crash-safe) -- BACKSPACE x2 to wipe.")
