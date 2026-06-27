-- Empire NPC - Follow Cap v1
-- Caps how many survivors follow you at once at MAX_FOLLOWERS. Once you're at the cap, asking
-- another to follow is politely refused (so a big colony doesn't become a 20-survivor conga
-- line). Catches every follow path -- our menu, the SSC panel, the Follow hotkey -- by gating
-- SSC's own SurvivorOrder. Existing followers are never kicked; re-commanding a current
-- follower is always allowed. Change MAX_FOLLOWERS below to taste.

require "EmpireNPC_Shared"

local MAX_FOLLOWERS = 3   -- you + 3 followers = a full 4-seat car for expeditions

local function countFollowers()
    if not EmpireNPC.getActiveSurvivors then return 0 end
    local n = 0
    for _, ss in ipairs(EmpireNPC.getActiveSurvivors()) do
        local m; pcall(function() m = ss:getAIMode() end)
        if m == "Follow" then n = n + 1 end
    end
    return n
end

local function isGuard(ss)
    local s = EmpireNPC.getSettler(ss:getName() or "")
    return s and s.role == EmpireNPC.Roles.GUARD
end

-- Free a slot for a guard by recalling one non-guard follower. Returns true if it bumped someone.
local function bumpOneNonGuard()
    if not EmpireNPC.getActiveSurvivors then return false end
    for _, ss in ipairs(EmpireNPC.getActiveSurvivors()) do
        local m; pcall(function() m = ss:getAIMode() end)
        if m == "Follow" and not isGuard(ss) then
            local ch; pcall(function() ch = ss:Get() end)
            if ch then
                pcall(function() SurvivorOrder(true, ch, "Stand Ground", nil) end)
                local p = getSpecificPlayer(0)
                if p then pcall(function() HaloTextHelper.addText(p, "Guard takes priority -- a civilian held back", HaloTextHelper.getColorYellow()) end) end
                return true
            end
        end
    end
    return false
end

local function install()
    if type(SurvivorOrder) ~= "function" then
        print("[EmpireNPC] Follow Cap: SurvivorOrder missing, not hooked.")
        return
    end
    local orig = SurvivorOrder
    SurvivorOrder = function(test, playerChar, order, orderParam)
        if order == "Follow" and playerChar then
            local already, reqIsGuard = false, false
            pcall(function()
                local ss = SSM:Get(playerChar:getModData().ID)
                if ss then
                    if ss:getAIMode() == "Follow" then already = true end
                    local s = EmpireNPC.getSettler(ss:getName() or "")
                    if s and s.role == EmpireNPC.Roles.GUARD then reqIsGuard = true end
                end
            end)
            if not already and countFollowers() >= MAX_FOLLOWERS then
                -- Guards get priority for the escort: bump a non-guard to make room. A non-guard
                -- asking while full is refused (so guards always win the 3 seats).
                local madeRoom = reqIsGuard and bumpOneNonGuard()
                if not madeRoom then
                    local p = getSpecificPlayer(0)
                    if p then
                        pcall(function()
                            HaloTextHelper.addText(p, "Follow squad full (" .. MAX_FOLLOWERS .. " max)", HaloTextHelper.getColorRed())
                        end)
                    end
                    return
                end
            end
        end
        local result = orig(test, playerChar, order, orderParam)
        -- Kit anyone actually sent to Follow: military dress + armory gun + melee, exactly like
        -- the HOME deploy. This makes the UP-arrow / SSC-panel follow paths arm & dress your
        -- escort too -- no more civvies-with-no-gun followers. (Pulls the gun from base storage,
        -- so form your escort at base.) Runs on the allowed path only, never on a refused one.
        if order == "Follow" and playerChar and EmpireNPC and EmpireNPC.equipSurvivor then
            pcall(function()
                local ss = SSM:Get(playerChar:getModData().ID)
                if ss then
                    local nm = ss:getName()
                    local settler = nm and EmpireNPC.getSettler(nm)
                    if settler then EmpireNPC.equipSurvivor(ss, playerChar, settler) end
                end
            end)
        end
        return result
    end
    print("[EmpireNPC] Follow Cap v1 loaded (max " .. MAX_FOLLOWERS .. " followers).")
end

Events.OnGameStart.Add(install)
