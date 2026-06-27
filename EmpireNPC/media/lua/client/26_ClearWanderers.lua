-- Empire NPC - Clear Wanderers (SAFE, manual, dry-run-first)
-- Removes random wanderer survivors OUT in the world while making your crew physically
-- impossible to touch. This does NOT use group membership (that data got corrupted by the old
-- cull and is exactly why it deleted crew). It gates on LOCATION instead:
--   KEEP (never removed): the player; anyone following; anyone within SAFE_RADIUS of you;
--                         anyone inside the base rectangle; any assigned crew (by name+role);
--                         anyone whose position can't be read (fail-CLOSED -- doubt = keep).
--   REMOVE: only survivors confirmed FAR from you and OUTSIDE the base.
-- You must be standing AT YOUR BASE to run it (so "near you" == "at base" and every worker is
-- protected). Two-step: press DELETE once = DRY RUN (counts, deletes nothing); press again
-- within 8s = execute. Uses SSC's own deleteSurvivor (no manual table-nil -> no ghosts).

require "EmpireNPC_Shared"

local CLEAR_KEY     = Keyboard.KEY_DELETE
local SAFE_RADIUS   = 40      -- tiles from you; anyone closer is KEPT
local BASE_MARGIN   = 6       -- expand the base rectangle by this many tiles for safety
local ARM_WINDOW_MS = 8000    -- confirm window after a dry run

local armed, armedAt = false, 0

local function activeBase(player)
    local b
    pcall(function() if EmpireBases and EmpireBases.activeBase then b = EmpireBases.activeBase(player) end end)
    return b
end

local function inBase(b, cx, cy)
    if not b then return false end
    local x1 = math.min(b.x1, b.x2) - BASE_MARGIN
    local x2 = math.max(b.x1, b.x2) + BASE_MARGIN
    local y1 = math.min(b.y1, b.y2) - BASE_MARGIN
    local y2 = math.max(b.y1, b.y2) + BASE_MARGIN
    return cx >= x1 and cx <= x2 and cy >= y1 and cy <= y2
end

-- Build the removable list. Every gate defaults to KEEP; a survivor only makes the list if it
-- positively clears EVERY safety check. Requires you to be at base (else returns nil = refuse).
local function removable()
    local player = getSpecificPlayer(0)
    if not player then return nil end
    local base = activeBase(player)
    if not base then return nil end            -- not at base -> refuse (can't protect workers)
    if not (SSM and SSM.SuperSurvivors) then return {} end
    local px, py = player:getX(), player:getY()
    local R2 = SAFE_RADIUS * SAFE_RADIUS
    local out = {}
    for id, ss in pairs(SSM.SuperSurvivors) do
        if ss then
            local keep = false
            local ch = nil
            pcall(function() ch = ss:Get() end)
            if not ch or ch == player then keep = true end                 -- unreadable/player -> KEEP
            if not keep then
                local mode; pcall(function() mode = ss:getAIMode() end)
                if mode == "Follow" then keep = true end                   -- escort -> KEEP
            end
            if not keep then
                local nm; pcall(function() nm = ss:getName() end)
                if nm and nm ~= "" and EmpireNPC.getSettler then
                    local s = EmpireNPC.getSettler(nm)
                    if s and s.role and s.role ~= EmpireNPC.Roles.NONE then keep = true end  -- assigned crew -> KEEP
                end
            end
            if not keep then
                local cx, cy, okpos
                pcall(function() cx = ch:getX(); cy = ch:getY(); okpos = (cx ~= nil and cy ~= nil) end)
                if not okpos then keep = true                              -- no position -> KEEP
                else
                    local dx, dy = cx - px, cy - py
                    if (dx*dx + dy*dy) <= R2 then keep = true end          -- near you -> KEEP
                    if not keep and inBase(base, cx, cy) then keep = true end -- in base -> KEEP
                end
            end
            if not keep then out[#out + 1] = ss end
        end
    end
    return out
end

local function notify(text, color)
    local p = getSpecificPlayer(0)
    if p then pcall(function() HaloTextHelper.addText(p, text, color) end) end
end

local function run()
    local list = removable()
    if list == nil then
        notify("Stand at your base to clear wanderers", HaloTextHelper.getColorRed())
        armed = false
        return
    end
    local n = #list
    local now = getTimestampMs()

    -- DRY RUN (first press, or confirm window expired): report only, delete nothing
    if not armed or (now - armedAt) > ARM_WINDOW_MS then
        armed, armedAt = true, now
        if n == 0 then
            notify("No distant wanderers to clear -- world's clean", HaloTextHelper.getColorGreen())
            armed = false
        else
            notify("Would clear " .. n .. " wanderers. Press DELETE again to confirm.", HaloTextHelper.getColorYellow())
            print("[EmpireNPC ClearWanderers] DRY RUN: " .. n .. " removable (far from base, not crew).")
        end
        return
    end

    -- CONFIRM (second press within window): recompute fresh, then remove via SSC's own delete
    armed = false
    local fresh = removable() or {}
    local removed = 0
    for _, ss in ipairs(fresh) do
        local ok = pcall(function() ss:deleteSurvivor() end)   -- SSC handles cleanup; no manual nil
        if ok then removed = removed + 1 end
    end
    notify("Cleared " .. removed .. " wanderers", HaloTextHelper.getColorGreen())
    print("[EmpireNPC ClearWanderers] removed " .. removed .. " wanderer(s).")
end

local function onKey(key)
    if key ~= CLEAR_KEY then return end
    local p = getSpecificPlayer(0)
    if not p or p:isDead() then return end
    if not (SSM and type(SSM.SuperSurvivors) == "table") then return end
    pcall(run)
end
Events.OnKeyPressed.Add(onKey)

print("[EmpireNPC] Clear Wanderers loaded -- DELETE at base: 1st press counts, 2nd press confirms. Crew is location-protected.")
