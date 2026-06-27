-- Empire NPC - Guard Deploy
-- One key sends your GUARDS -- and only your guards -- out as a kitted escort, and brings them
-- back, WITHOUT pulling your farmer/cook/looter off their jobs. Press HOME to toggle:
--   DEPLOY  -> each Guard arms/dresses (military kit + armory gun + melee) and Follows you
--   RECALL  -> each Guard holds the base (Stand Ground)  [recall while you're AT base]
-- Guards = survivors whose role is Guard (assign via the role menu). The 3-follower cap caps the
-- escort at a carload. ADDITIVE ONLY: it issues Follow / Stand Ground orders, never deletes.

require "EmpireNPC_Shared"

local TOGGLE_KEY = Keyboard.KEY_HOME
local R = EmpireNPC.Roles
local deployed = false

-- every living survivor whose role is Guard
local function guards()
    local out = {}
    for _, ss in ipairs(EmpireNPC.getActiveSurvivors()) do
        local name = ss:getName()
        if name and name ~= "" then
            local s = EmpireNPC.getSettler(name)
            if s and s.role == R.GUARD then
                local ch = ss:Get()
                if ch and not ch:isDead() then out[#out + 1] = { ss = ss, ch = ch, settler = s } end
            end
        end
    end
    return out
end

local function order(char, ord)
    pcall(function() SurvivorOrder(true, char, ord, nil) end)
end

local function notify(text, color)
    local p = getSpecificPlayer(0)
    if p then pcall(function() HaloTextHelper.addText(p, text, color) end) end
end

local function deploy()
    local list = guards()
    if #list == 0 then
        notify("No guards assigned (set a survivor's role to Guard)", HaloTextHelper.getColorRed())
        return
    end
    local n = 0
    for _, g in ipairs(list) do
        -- kit up NOW: top up gun/ammo + military dress before heading out
        if EmpireNPC.equipSurvivor then pcall(function() EmpireNPC.equipSurvivor(g.ss, g.ch, g.settler) end) end
        order(g.ch, "Follow")
        n = n + 1
    end
    deployed = true
    notify("Guards deployed: " .. n .. " escorting", HaloTextHelper.getColorGreen())
    print("[EmpireNPC GuardDeploy] deployed " .. n .. " guard(s) to Follow.")
end

local function recall()
    local list = guards()
    local n = 0
    for _, g in ipairs(list) do
        order(g.ch, "Stand Ground")
        n = n + 1
    end
    deployed = false
    notify("Guards recalled: " .. n .. " holding base", HaloTextHelper.getColorYellow())
    print("[EmpireNPC GuardDeploy] recalled " .. n .. " guard(s) to Stand Ground.")
end

local function onKey(key)
    if key ~= TOGGLE_KEY then return end
    local p = getSpecificPlayer(0)
    if not p or p:isDead() then return end
    if not (SSM and type(SurvivorOrder) == "function") then return end
    if deployed then recall() else deploy() end
end
Events.OnKeyPressed.Add(onKey)

print("[EmpireNPC] Guard Deploy loaded -- HOME toggles guards between escort (Follow) and base (Stand Ground).")
