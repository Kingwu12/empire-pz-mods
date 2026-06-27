-- Empire NPC - Garrison Control v1
-- Explicit "who's base vs who follows me" control, so you don't have to fight SSC's order
-- menu. Right-click a survivor:
--   * "Send to Base"   -> stations them (StandGround). Garrison then auto-assigns a role,
--                         pins them (no more shuffling) and arms guards from storage.
--   * "Make Companion" -> sets them to Follow you. The Survival layer then auto-retreats
--                         them when low HP.
--   * "Send ALL to Base" -> does the above for every survivor at once.
-- It also sets settler.garrisoned (true=base / false=companion) so the choice is remembered.
-- Additive only: a separate context-menu handler, no changes to existing files.

require "EmpireNPC_Shared"

local function halo(text)
    local p = getSpecificPlayer(0); if not p then return end
    pcall(function() HaloTextHelper.addText(p, text, HaloTextHelper.getColorGreen()) end)
end

local function sendToBase(ss)
    local name = ss:getName(); if not name or name == "" then return end
    local s = EmpireNPC.getSettler(name); s.name = name
    s.garrisoned = true
    s.autoAssigned = nil          -- let Garrison (re)assign a fresh role
    EmpireNPC.saveData()
    pcall(function() ss:getTaskManager():clear() end)
    pcall(function() ss:setAIMode("StandGround") end)
    halo(name .. " sent to base (auto-managed)")
end

local function makeCompanion(ss)
    local name = ss:getName(); if not name or name == "" then return end
    local s = EmpireNPC.getSettler(name); s.name = name
    s.garrisoned = false
    s.role = EmpireNPC.Roles.NONE
    EmpireNPC.saveData()
    -- Route through SSC's own proven follow order: it clears tasks, permits walking, sets the
    -- Companion role, and -- the piece our bare setAIMode was missing -- adds a FollowTask that
    -- targets YOU (getSpecificPlayer(0)). "Follow" AI-mode with no task just makes them stand.
    local ok = pcall(function() SurvivorOrder(true, ss:Get(), "Follow", nil) end)
    if not ok then pcall(function() ss:setAIMode("Follow") end) end
    halo(name .. " is now a companion (follows you)")
end

local function sendAllToBase()
    if not SSM then return end
    local n = 0
    for _, ss in ipairs(EmpireNPC.getActiveSurvivors()) do
        if ss and not ss:isDead() then sendToBase(ss); n = n + 1 end
    end
    halo("Sent " .. n .. " survivors to base")
end

local function tag(s)
    if s.garrisoned == true then return " (Base)" end
    if s.garrisoned == false then return " (Companion)" end
    return ""
end

local function onFill(player, context, worldObjects, test)
    if test then return end
    if player ~= 0 then return end
    if not SSM then return end
    local square = GetMouseSquare(); if not square then return end
    local movingObjs = square:getMovingObjects(); if not movingObjs then return end
    for i = 0, movingObjs:size() - 1 do
        local obj = movingObjs:get(i)
        if obj and instanceof(obj, "IsoPlayer") then
            local md = obj:getModData()
            if md and md.ID ~= nil and md.ID ~= SSM:getRealPlayerID() then
                local ss = SSM:Get(md.ID)
                if ss and not ss:isDead() then
                    local name = ss:getName() or "Survivor"
                    local s = EmpireNPC.getSettler(name)
                    local opt = context:addOption("[Empire] " .. name .. tag(s), nil, nil)
                    local sub = ISContextMenu:getNew(context)
                    context:addSubMenu(opt, sub)
                    sub:addOption("Send to Base (auto-manage)", nil, function() sendToBase(ss) end)
                    sub:addOption("Make Companion (follow me)", nil, function() makeCompanion(ss) end)
                    sub:addOption("Send ALL survivors to Base", nil, function() sendAllToBase() end)
                    break
                end
            end
        end
    end
end

Events.OnFillWorldObjectContextMenu.Add(onFill)

-- One-key RECALL: send your whole follow squad (and anyone deployed) back to base in one press.
-- sendToBase re-stations each survivor (StandGround) and clears their auto-role so Garrison
-- re-arms them and puts them back on guard duty -- i.e. "everyone home, back on the wall".
-- Default key = HOME (semantically "go home"); change RECALL_KEY below if it clashes with anything.
local RECALL_KEY = Keyboard.KEY_HOME
local function onRecallKey(key)
    if key ~= RECALL_KEY then return end
    local p = getSpecificPlayer(0)
    if not p or p:isDead() then return end
    pcall(sendAllToBase)
end
Events.OnKeyPressed.Add(onRecallKey)

print("[EmpireNPC] Garrison Control loaded. Right-click survivors -> Send to Base / Make Companion. HOME = recall all to base.")
