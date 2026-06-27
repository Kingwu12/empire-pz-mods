-- Empire NPC - Auto Garrison v3 (Equip & Deploy)
-- Auto-assigns a role to every base survivor, ARMS them (gun + ammo + backup melee), DRESSES
-- them in military kit, and DEPLOYS them to their job via SSC's own order system -- then keeps
-- them on the job instead of letting them idle/shuffle.
-- v3 vs v2: everyone (not just guards) is armed + dressed; jobs actually run via SurvivorOrder;
-- the old destructive "pin" (cleared tasks every few seconds, only set a mode flag) is GONE --
-- that is why nobody did their job. Arm/dress happen ONCE per survivor (flagged), no dupes.
-- Companions are skipped for deploy (7_Survival handles them) but still armed & dressed.
-- Built on SSC primitives: giveWeapon, WearThis, SurvivorOrder. All pcall'd.

require "EmpireNPC_Shared"

local R = EmpireNPC.Roles

-- Auto-deploy survivors to jobs? OFF = the empire still ARMS & DRESSES everyone but leaves
-- ORDERS to you: use the SSC survivor window (Page Up) to command them and the orders STICK
-- instead of being overridden every few seconds. Set true to let the empire auto-run jobs.
EmpireNPC.AUTO_DEPLOY = false

local GARRISON_ENABLED = true
local ASSIGN_INTERVAL  = 1500
local DEPLOY_INTERVAL  = 300
local THREAT_RADIUS    = 15
local FOOD_LOW         = 8
local SCAN_R           = 12

local LADDER = { R.GUARD, R.COOK, R.LOOTER, R.MEDIC, R.FARMER }

-- Role-appropriate outfits. Combat roles get real military protection (the vest + helmet actually
-- matter there); non-combat roles get a light protective baseline (leather = scratch/bite
-- resistance) -- no point dressing the cook like a soldier. Worn by NAME so it never depends on
-- the armory physically holding clothes within scan range (that dependency is why dressing used
-- to silently do nothing). Invalid names simply no-op.
local ROLE_KIT = {
    [R.GUARD]  = { "Base.Vest_BulletArmy", "Base.Jacket_ArmyCamoGreen", "Base.Tshirt_ArmyGreen", "Base.Trousers_CamoGreen", "Base.Shoes_ArmyBoots", "Base.Hat_ArmyHelmet" },
    [R.WARDEN] = { "Base.Vest_BulletArmy", "Base.Jacket_ArmyCamoGreen", "Base.Tshirt_ArmyGreen", "Base.Trousers_CamoGreen", "Base.Shoes_ArmyBoots", "Base.Hat_ArmyHelmet" },
    [R.MEDIC]  = { "Base.Jacket_Leather", "Base.Tshirt_WhiteTINT", "Base.Trousers", "Base.Shoes_TrainerTan" },
    [R.LOOTER] = { "Base.Jacket_Leather", "Base.Trousers", "Base.Shoes_ArmyBoots", "Base.Bag_NormalHikingBag" },
    [R.FARMER] = { "Base.Dungarees", "Base.Tshirt_WhiteLongSleeve", "Base.Shoes_ArmyBoots", "Base.Hat_Strawhat" },
    [R.COOK]   = { "Base.Apron", "Base.Tshirt_WhiteTINT", "Base.Trousers", "Base.Shoes_TrainerTan" },
    [R.NONE]   = { "Base.Jacket_Leather", "Base.Trousers", "Base.Shoes_TrainerTan" },
}

local ROLE_ORDER = {
    [R.GUARD]  = "Stand Ground",
    [R.FARMER] = "Farming",
    [R.LOOTER] = "Forage",
    [R.WARDEN] = "Stand Ground",
    [R.MEDIC]  = "Stand Ground",
    [R.NONE]   = "Stand Ground",
}

local IDLE_TASKS = {
    [""]=true, Idle=true, Wander=true, WanderInBase=true,
    WanderInBuilding=true, WanderInArea=true,
}

local function isCompanion(ss)
    local m; pcall(function() m = ss:getAIMode() end)
    if m == "Follow" then return true end
    local t; pcall(function() t = ss:getTaskManager():getCurrentTask() end)
    if t == "Follow" then return true end
    return false
end
EmpireNPC.isCompanion = isCompanion

local function zombiesNear(char, radius)
    local cell = getCell(); if not cell or not char then return false end
    local cx, cy, cz = math.floor(char:getX()), math.floor(char:getY()), math.floor(char:getZ())
    for dx = -radius, radius do
        for dy = -radius, radius do
            local sq = cell:getGridSquare(cx + dx, cy + dy, cz)
            if sq then
                local mo = sq:getMovingObjects()
                if mo then for i = 0, mo:size()-1 do if instanceof(mo:get(i), "IsoZombie") then return true end end end
            end
        end
    end
    return false
end

-- Iterate every storage container in the WHOLE DEFINED BASE (the EmpireBases rectangle you
-- highlighted in SSC), across the base's floors. Falls back to a radius box around the survivor
-- only if no base is defined. This is what makes food-counting and arming pull from the entire
-- base instead of whatever happened to be within a few tiles of one survivor.
local function eachContainerNear(char, radius, fn)
    local cell = getCell(); if not cell or not char then return end
    -- fast path: the maintained base index (deduped, junk-excluded; valid when you're at base)
    local idx
    pcall(function() if EmpireBaseCache and EmpireBaseCache.get then idx = EmpireBaseCache.get() end end)
    if idx and idx.containers and #idx.containers > 0 then
        for i = 1, #idx.containers do fn(idx.containers[i]) end
        return
    end
    local cz = math.floor(char:getZ())
    local b
    pcall(function()
        if EmpireBases and EmpireBases.activeBase then b = EmpireBases.activeBase(char) end
        if not b and EmpireBases and EmpireBases.list then local l = EmpireBases.list(); b = l and l[1] end
    end)
    local x1, x2, y1, y2, z1, z2
    if b then
        x1, x2 = math.min(b.x1, b.x2), math.max(b.x1, b.x2)
        y1, y2 = math.min(b.y1, b.y2), math.max(b.y1, b.y2)
        local spread = (EmpireBases and EmpireBases.FLOOR_SPREAD) or 0
        z1, z2 = cz - spread, cz + spread
    else
        local cx, cy = math.floor(char:getX()), math.floor(char:getY())
        x1, x2, y1, y2, z1, z2 = cx - radius, cx + radius, cy - radius, cy + radius, cz, cz
    end
    local seen = {}
    for z = z1, z2 do
        for x = x1, x2 do
            for y = y1, y2 do
                local sq = cell:getGridSquare(x, y, z)
                if sq then
                    local objs = sq:getObjects()
                    if objs then
                        for i = 0, objs:size() - 1 do
                            local c = nil
                            pcall(function() c = objs:get(i):getContainer() end)
                            if c and not seen[c] then seen[c] = true; fn(c) end
                        end
                    end
                end
            end
        end
    end
end

local function countBaseFood(char)
    local n = 0
    eachContainerNear(char, SCAN_R, function(cont)
        local items = cont:getItems()
        for i = 0, items:size()-1 do if instanceof(items:get(i), "Food") then n = n + 1 end end
    end)
    return n
end

local function announce(text, good)
    local p = getSpecificPlayer(0); if not p then return end
    pcall(function()
        HaloTextHelper.addText(p, text, good and HaloTextHelper.getColorGreen() or HaloTextHelper.getColorYellow())
    end)
end

local function alreadyArmed(ss, char)
    local has = false
    pcall(function() if ss.getGunWep and ss:getGunWep() then has = true end end)
    if has then return true end
    pcall(function()
        local items = char:getInventory():getItems()
        for i = 0, items:size()-1 do
            local it = items:get(i)
            if instanceof(it, "HandWeapon") and it:isAimedFirearm() then has = true; break end
        end
    end)
    return has
end

-- Quartermaster: move an existing item from a base container into the survivor's inventory.
local function pullToSurvivor(char, it, cont)
    pcall(function() cont:Remove(it) end)
    pcall(function() char:getInventory():AddItem(it) end)
end

-- Find the first firearm sitting in base storage near the survivor (so they arm at base).
local function findGunInStorage(char)
    local gun, gc = nil, nil
    eachContainerNear(char, SCAN_R, function(cont)
        if gun then return end
        local items = cont:getItems()
        for i = 0, items:size() - 1 do
            local it = items:get(i)
            local ok = false
            pcall(function() ok = instanceof(it, "HandWeapon") and it:isAimedFirearm() end)
            if ok then gun = it; gc = cont; return end
        end
    end)
    return gun, gc
end

-- How many of your BEST weapons of each type (gun / melee) to keep for yourself. The crew never
-- touches these -- they take the best of what's LEFT (a "medium" weapon). Raise to hoard more of
-- your top gear; set 0 to let them take the very best.
EmpireNPC.RESERVE_TOP_WEAPONS = 1

-- Pick a weapon for an NPC from base storage: rank all matching weapons by damage, skip your top
-- RESERVE_TOP_WEAPONS (reserved for you), and hand them the best of the rest. Returns nil if only
-- your reserved top-tier exists -- so they fall back to a basic spawned melee instead of raiding
-- your good stuff. wantGun=true -> firearms, false -> melee.
local function findWeaponForNpc(char, wantGun)
    local cands = {}
    eachContainerNear(char, SCAN_R, function(cont)
        local items = cont:getItems()
        for i = 0, items:size() - 1 do
            local it = items:get(i)
            local isWeap, isGun, score = false, false, 0
            pcall(function()
                if instanceof(it, "HandWeapon") then
                    isWeap = true
                    isGun  = it:isAimedFirearm()
                    score  = it:getMaxDamage() or 0
                end
            end)
            if isWeap and ((wantGun and isGun) or (not wantGun and not isGun)) then
                cands[#cands + 1] = { it = it, cont = cont, score = score }
            end
        end
    end)
    if #cands == 0 then return nil, nil end
    table.sort(cands, function(a, b) return a.score > b.score end)
    local reserve = EmpireNPC.RESERVE_TOP_WEAPONS or 0
    local pick = cands[reserve + 1]          -- best AFTER reserving your top N for yourself
    if not pick then return nil, nil end     -- only your reserved tier exists -> hands off
    return pick.it, pick.cont
end

-- Find a magazine of a given fulltype in storage.
local function findItemInStorage(char, fullType)
    local found, fc = nil, nil
    eachContainerNear(char, SCAN_R, function(cont)
        if found then return end
        local items = cont:getItems()
        for i = 0, items:size() - 1 do
            local it = items:get(i)
            local ft = nil; pcall(function() ft = it:getFullType() end)
            if ft == fullType then found = it; fc = cont; return end
        end
    end)
    return found, fc
end

-- Collect one wearable per body slot from base storage (his Brita armour + clothing).
local function collectWearables(char)
    local picks, usedLoc = {}, {}
    eachContainerNear(char, SCAN_R, function(cont)
        local items = cont:getItems()
        for i = 0, items:size() - 1 do
            local it = items:get(i)
            local bl = nil; pcall(function() bl = it:getBodyLocation() end)
            if bl and bl ~= "" and bl ~= "Bag" and not usedLoc[bl] then
                usedLoc[bl] = true
                picks[#picks + 1] = { it = it, cont = cont }
            end
        end
    end)
    return picks
end

local FALLBACK_MELEE = { "Base.BaseballBat", "Base.Crowbar", "Base.Axe", "Base.Machete", "Base.HandAxe" }

local function hasWeaponInHand(char)
    local ok, res = pcall(function()
        local w = char:getPrimaryHandItem()
        return w ~= nil and instanceof(w, "HandWeapon")
    end)
    return ok and res
end

-- ARM: real gun from the base armory first (closed loop -- recovered on death via 13_Recovery),
-- and they HOLD it so they actually open fire (SSC won't draw a reserved gun on its own -- it only
-- equips when the hand is empty). Gun users carry a backup melee in the bag; non-gun survivors hold
-- the best melee instead so nobody idles empty-handed.
local function armSurvivor(ss, char, settler)
    if alreadyArmed(ss, char) then settler.armed = true end

    if not settler.armed then
        local gun, gc = findWeaponForNpc(char, true)
        if gun then
            pullToSurvivor(char, gun, gc)
            pcall(function() ss:setGunWep(gun) end)
            pcall(function()                                    -- matching magazine from storage
                local mt = gun:getMagazineType()
                if mt then local mag, mc = findItemInStorage(char, mt); if mag then pullToSurvivor(char, mag, mc) end end
            end)
            pcall(function()                                    -- matching ammo box from storage
                local ammos = GetAmmoBullets(gun)
                if ammos and ammos[1] then
                    local box = GetAmmoBox(ammos[1]) or ammos[1]
                    local a, ac = findItemInStorage(char, box); if a then pullToSurvivor(char, a, ac) end
                end
            end)
            -- ACTUALLY HOLD + LOAD the gun. SSC only auto-equips a weapon when the hand is EMPTY and
            -- never swaps melee->gun on threat, so leaving a melee in hand meant they meleed forever.
            -- Put the gun in their hands and rack it so they open fire.
            pcall(function() char:setPrimaryHandItem(gun) end)
            pcall(function() if ss.ReadyGun then ss:ReadyGun(gun) end end)
            settler.armed  = true
            settler.hasGun = true
            local nm = "gun"; pcall(function() nm = gun:getName() end)
            announce((settler.name or "Survivor") .. " armed from armory: " .. tostring(nm), true)

            -- backup melee stashed in the BAG (not hand) so a gun user isn't helpless out of ammo
            pcall(function()
                local melee, mc = findWeaponForNpc(char, false)
                if melee then
                    pullToSurvivor(char, melee, mc)
                    if ss.setMeleWep then ss:setMeleWep(melee) end
                end
            end)
        end
    end

    -- Non-gun survivors (or anyone still empty-handed): give them the best melee in hand; only
    -- spawn a basic fallback if storage has none. NEVER overwrite a gun already in hand.
    if not settler.hasGun and not hasWeaponInHand(char) then
        local melee, mc = findWeaponForNpc(char, false)
        if melee then
            pullToSurvivor(char, melee, mc)
            pcall(function()
                char:setPrimaryHandItem(melee)
                if melee:isTwoHandWeapon() then char:setSecondaryHandItem(melee) end
                if ss.setMeleWep then ss:setMeleWep(melee) end
            end)
        end
        if not hasWeaponInHand(char) then
            local pick = FALLBACK_MELEE[ZombRand(#FALLBACK_MELEE) + 1] or "Base.BaseballBat"
            pcall(function() ss:giveWeapon(pick, true) end)
        end
        if not settler.armed and hasWeaponInHand(char) then
            settler.armed = true
            announce((settler.name or "Survivor") .. " armed", false)
        end
    end
end

-- DRESS by role -- spawns a role-appropriate kit by name. Reliable: no dependence on the armory
-- physically holding clothes within scan range (that was the silent-failure before). Combat roles
-- get military protection; everyone else a light protective baseline.
local function dressSurvivor(ss, char, settler)
    local role = settler.role or R.NONE
    if settler.dressedRole == role then return end     -- re-dress whenever the ROLE changes, not just once
    local kit = ROLE_KIT[role] or ROLE_KIT[R.NONE]
    for _, name in ipairs(kit) do
        pcall(function() ss:WearThis(name) end)
    end
    settler.dressedRole = role
    settler.dressed = true
    announce((settler.name or "Survivor") .. " kitted (" .. tostring(role) .. ")", true)
end

-- TRAIN combat skills. SSC survivors barely gain Aiming from fighting (spawn nudges it to ~2 and
-- it never really climbs), so guards stay terrible shots. Bring them to a competent baseline ONCE
-- per role. raisePerk only ever raises and stops at target, so repeat passes are free and never
-- downgrade anyone.
local TRAIN = {
    [R.GUARD]  = { Aiming = 6, Reloading = 5 },
    [R.WARDEN] = { Aiming = 6, Reloading = 5 },
}
local TRAIN_DEFAULT = { Aiming = 3, Reloading = 2 }   -- everyone can at least defend the base

-- Bravery = SSC's flee threshold. A survivor flees the moment (zombies-seen > bravery), and
-- vanilla bravery is ~0-2, so they bolt mid-reload the instant a zombie is within ~6 tiles --
-- which is why only you end up shooting. Crank it so guards hold the line and keep firing.
EmpireNPC.GUARD_BRAVERY = EmpireNPC.GUARD_BRAVERY or 30   -- guards: basically never panic
EmpireNPC.BASE_BRAVERY  = EmpireNPC.BASE_BRAVERY  or 10   -- everyone else: brave, but a true horde still breaks them

local function raisePerk(char, perkStr, target)
    pcall(function()
        local perk = Perks.FromString(perkStr)
        if not perk then return end
        local guard = 0
        while char:getPerkLevel(perk) < target and guard < 25 do
            char:LevelPerk(perk); guard = guard + 1
        end
    end)
end

local function trainSurvivor(ss, char, settler)
    local role = settler.role or R.NONE
    if settler.trainedRole == role then return end
    local plan = TRAIN[role] or TRAIN_DEFAULT
    for perkStr, lvl in pairs(plan) do raisePerk(char, perkStr, lvl) end
    -- Stop the panic-flee so they actually stand and shoot instead of running mid-reload.
    pcall(function()
        if ss.setBravePoints then
            local brave = (role == R.GUARD or role == R.WARDEN)
                and (EmpireNPC.GUARD_BRAVERY or 30) or (EmpireNPC.BASE_BRAVERY or 10)
            ss:setBravePoints(brave)
        end
    end)
    settler.trainedRole = role
end

local function equipSurvivor(ss, char, settler)
    if char == getSpecificPlayer(0) then return end   -- never arm/dress/train the player
    pcall(armSurvivor, ss, char, settler)
    pcall(dressSurvivor, ss, char, settler)
    pcall(trainSurvivor, ss, char, settler)
end
-- exposed so Guard Deploy can kit a guard up on demand right before an expedition
EmpireNPC.equipSurvivor = equipSurvivor

-- Force-upgrade EVERY survivor to the best gun + best melee currently in base storage, ignoring
-- the "already armed" flag. One-shot fix for a crew that spawned holding junk. Returns the count.
function EmpireNPC.rearmBest()
    if not SSM then return 0 end
    local n = 0
    for _, ss in ipairs(EmpireNPC.getActiveSurvivors()) do
        local ch = ss:Get()
        if ch and ch ~= getSpecificPlayer(0) and not ch:isDead() then
            local hasGun = false
            local gun, gc = findWeaponForNpc(ch, true)
            if gun then
                pullToSurvivor(ch, gun, gc)
                pcall(function() ss:setGunWep(gun) end)
                pcall(function()
                    local mt = gun:getMagazineType()
                    if mt then local mag, mc = findItemInStorage(ch, mt); if mag then pullToSurvivor(ch, mag, mc) end end
                end)
                pcall(function()
                    local ammos = GetAmmoBullets(gun)
                    if ammos and ammos[1] then
                        local box = GetAmmoBox(ammos[1]) or ammos[1]
                        local a, ac = findItemInStorage(ch, box); if a then pullToSurvivor(ch, a, ac) end
                    end
                end)
                pcall(function() ch:setPrimaryHandItem(gun) end)   -- HOLD it so they actually shoot
                pcall(function() if ss.ReadyGun then ss:ReadyGun(gun) end end)
                hasGun = true
            end
            local melee, mc2 = findWeaponForNpc(ch, false)
            if melee then
                pullToSurvivor(ch, melee, mc2)
                pcall(function()
                    if ss.setMeleWep then ss:setMeleWep(melee) end
                    if not hasGun then                            -- gun users keep the gun in hand; melee = bag backup
                        ch:setPrimaryHandItem(melee)
                        if melee:isTwoHandWeapon() then ch:setSecondaryHandItem(melee) end
                    end
                end)
            end
            n = n + 1
        end
    end
    return n
end

local function isIdle(ss)
    local cur = ""
    pcall(function() cur = ss:getTaskManager():getCurrentTask() or "" end)
    return IDLE_TASKS[cur] == true
end

local function deployToJob(ss, char, settler)
    if not EmpireNPC.AUTO_DEPLOY then return end       -- manual control: leave orders to the player
    if char == getSpecificPlayer(0) then return end   -- never deploy the player
    if zombiesNear(char, THREAT_RADIUS) then return end
    local role  = settler.role or R.NONE
    local order = ROLE_ORDER[role] or "Stand Ground"
    if settler.deployedOrder == order and not isIdle(ss) then return end
    if pcall(function() SurvivorOrder(true, char, order, nil) end) then
        settler.deployedOrder = order
    end
end

-- Fill ONLY unroled survivors toward a sensible baseline, in priority order; everyone else -> Guard.
-- Never reshuffles an existing role, so every assignment (manual OR prior auto) is permanent.
-- THIS is what kills the random role-churn.
local FILL_TARGETS = { { R.COOK, 1 }, { R.MEDIC, 1 }, { R.FARMER, 1 } }

local function roleCounts(base)
    local c = {}
    for _, ss in ipairs(base) do
        local s = EmpireNPC.getSettler(ss:getName() or "")
        if s and s.role and s.role ~= R.NONE then c[s.role] = (c[s.role] or 0) + 1 end
    end
    return c
end

local function nextFillRole(counts)
    for _, t in ipairs(FILL_TARGETS) do
        if (counts[t[1]] or 0) < t[2] then return t[1] end
    end
    return R.GUARD
end

local function computeNeeds(baseSurvivors)
    local threat = false
    for _, ss in ipairs(baseSurvivors) do
        local ch = ss:Get()
        if ch and zombiesNear(ch, THREAT_RADIUS) then threat = true; break end
    end
    local food, ref = 0, baseSurvivors[1] and baseSurvivors[1]:Get()
    if ref then food = countBaseFood(ref) end
    return { threat = threat, foodLow = (food < FOOD_LOW), food = food }
end

local function getBaseSurvivors()
    local out = {}
    for _, ss in ipairs(EmpireNPC.getActiveSurvivors()) do
        if not isCompanion(ss) then out[#out + 1] = ss end
    end
    return out
end

local function equipAll()
    if not SSM then return end
    for _, ss in ipairs(EmpireNPC.getActiveSurvivors()) do
        local name = ss:getName()
        if name and name ~= "" then
            local ch = ss:Get()
            if ch and not ch:isDead() then
                local s = EmpireNPC.getSettler(name); s.name = name
                pcall(equipSurvivor, ss, ch, s)
            end
        end
    end
end

local function autoAssign()
    if not SSM then return end
    local base = getBaseSurvivors()
    if #base == 0 then return end
    local needs  = computeNeeds(base)
    local counts = roleCounts(base)

    local changes = 0
    for _, ss in ipairs(base) do
        local name = ss:getName()
        if name and name ~= "" then
            local s = EmpireNPC.getSettler(name); s.name = name
            local ch = ss:Get()
            -- Assign a role ONLY to survivors who have none. Anyone already assigned -- by you or
            -- by a previous pass -- is left exactly as-is. No threat/food reshuffling, ever.
            if not s.role or s.role == R.NONE then
                local newRole = nextFillRole(counts)
                s.role = newRole
                counts[newRole] = (counts[newRole] or 0) + 1
                changes = changes + 1
                announce(name .. " assigned " .. newRole, true)
            end
            if ch and not ch:isDead() then
                pcall(equipSurvivor, ss, ch, s)
                pcall(deployToJob, ss, ch, s)
            end
        end
    end

    if needs.foodLow then
        for _, ss in ipairs(base) do
            local s = EmpireNPC.getSettler(ss:getName() or "")
            if s and s.role == R.LOOTER and not s.onRun then
                s.onRun = true; s.runReturnTick = 3600
                announce((s.name or "Looter") .. " sent for food (base low)", true)
                break
            end
        end
    end

    if changes > 0 then EmpireNPC.saveData() end
    if EMPIRE_DEBUG_ON ~= false then
        print(string.format("[EmpireGarrison] assign: base=%d newly-roled=%d (existing roles sticky) food=%d",
            #base, changes, needs.food))
    end
end

local function deployPass()
    if not SSM then return end
    for _, ss in ipairs(getBaseSurvivors()) do
        local name = ss:getName()
        if name and name ~= "" then
            local ch = ss:Get()
            if ch and not ch:isDead() then
                local s = EmpireNPC.getSettler(name); s.name = name
                pcall(deployToJob, ss, ch, s)
            end
        end
    end
end

local assignTick, deployTick = 0, 0
local function onTick()
    if not GARRISON_ENABLED then return end
    assignTick = assignTick + 1
    deployTick = deployTick + 1
    if assignTick >= ASSIGN_INTERVAL then
        assignTick, deployTick = 0, 0
        pcall(equipAll)
        pcall(autoAssign)
    elseif deployTick >= DEPLOY_INTERVAL then
        deployTick = 0
        pcall(deployPass)
    end
end
Events.OnTick.Add(onTick)

print("[EmpireNPC] Auto Garrison v4 loaded. Everyone armed (armory gun + melee backup) and dressed by role.")
