-- ============================================================
-- Empire Ammo Drop  (B42, event-driven)
-- Zombies drop ammo on death -- bypasses the broken loot-distribution injection
-- entirely by adding ammo straight to the corpse via OnZombieDead.
--
-- TUNE EVERYTHING IN THE CONFIG BLOCK BELOW. Numbers are designed to be
-- "realistic but fun": most people aren't armed, but Kentucky is gun-heavy, and
-- dead cops/soldiers/hunters are worth looting.
-- ============================================================

local CFG = {
    -- ordinary zombie: chance to carry ANY ammo, and how much (loose rounds)
    normalCarryChance = 0.20,     -- ~1 in 5 ON-BODY carry. Kentucky is gun-heavy, but most
                                  -- guns are AT HOME (-> house loot), not on a shambling
                                  -- corpse. A minority carrying keeps ammo a real resource.
    normalMin         = 4,
    normalMax         = 11,       -- a carrier has roughly a partial mag's worth (~7 avg):
                                  -- what was loaded + a couple spares, not a single round.
    normalBoxChance   = 0.05,     -- occasional: a civilian with a small box

    -- special zombies by outfit (a dead cop SHOULD have mags)
    cop   = { chance = 0.80, min = 12, max = 34, boxChance = 0.25, pool = "pistol", shotgunChance = 0.15 },
    army  = { chance = 0.85, min = 20, max = 60, boxChance = 0.30, pool = "rifle",  shotgunChance = 0.05 },
    hunter= { chance = 0.60, min = 6,  max = 20, boxChance = 0.15, pool = "rifle",  shotgunChance = 0.40 },
    guard = { chance = 0.55, min = 8,  max = 20, boxChance = 0.10, pool = "pistol", shotgunChance = 0.10 },

    -- hard cap so a mass-kill never dumps absurd amounts
    maxRoundsPerZombie = 70,
}

-- ---- candidate ammo (validated at game start; missing ones are dropped silently) ----
-- weight = how common. pistol/shotgun common, rifle rarer. covers vanilla + Guns of '93.
local POOLS_RAW = {
    pistol = {
        {"Base.Bullets9mm",10},{"Base.Bullets45",6},{"Base.Bullets38",6},{"Base.Bullets357",4},
        {"Base.Bullets44",3},{"Base.380Bullets",4},{"Base.40Bullets",4},{"Base.10mmBullets",2},
        {"Base.22Bullets",5},{"Base.45LCBullets",2},
        {"guns93.380Bullets",4},{"guns93.40Bullets",4},{"guns93.10mmBullets",2},{"guns93.45LCBullets",2},{"guns93.22Bullets",5},
    },
    shotgun = {
        {"Base.ShotgunShells",10},
    },
    rifle = {
        {"Base.556Bullets",6},{"Base.308Bullets",5},{"Base.3030Bullets",5},{"Base.3006Bullets",4},
        {"Base.76239Bullets",4},{"Base.30CarBullets",2},{"Base.792Bullets",2},{"Base.223Bullets",4},
        {"guns93.76239Bullets",4},{"guns93.3006Bullets",4},{"guns93.30CarBullets",2},{"guns93.792Bullets",2},
    },
}
-- box candidates (validated too; if none exist we just drop more loose rounds)
local BOX_RAW = {
    "Base.Bullets9mmBox","Base.Bullets45Box","Base.Bullets38Box","Base.Bullets357Box",
    "Base.ShotgunShellsBox","Base.556Box","Base.308Box","Base.3030Box",
}

local POOLS = { pistol = {}, shotgun = {}, rifle = {} }
local BOXES = {}
local ready = false

local function itemExists(ft)
    -- use the script manager (returns nil for missing) instead of CreateItem -- other
    -- mods (ZuperCart) override CreateItem to THROW on a missing item, which spammed a
    -- logged error per missing type at startup. getItem never instantiates and never throws.
    local ok, res = pcall(function() return getScriptManager():getItem(ft) end)
    return ok and res ~= nil
end

local function buildPools()
    if ready then return end
    for kind, list in pairs(POOLS_RAW) do
        for _, e in ipairs(list) do
            if itemExists(e[1]) then
                POOLS[kind][#POOLS[kind] + 1] = { type = e[1], w = e[2] }
            end
        end
    end
    for _, ft in ipairs(BOX_RAW) do
        if itemExists(ft) then BOXES[#BOXES + 1] = ft end
    end
    ready = true
    local np = #POOLS.pistol + #POOLS.shotgun + #POOLS.rifle
    print("[EmpireAmmoDrop] ready. valid ammo types=" .. np .. " boxes=" .. #BOXES)
end

-- weighted pick from a validated pool ({type=,w=})
local function pickWeighted(pool)
    if not pool or #pool == 0 then return nil end
    local total = 0
    for _, e in ipairs(pool) do total = total + e.w end
    local r = ZombRand(total) + 1
    local acc = 0
    for _, e in ipairs(pool) do
        acc = acc + e.w
        if r <= acc then return e.type end
    end
    return pool[1].type
end

-- classify a zombie by its outfit into a profile key, or nil for "normal"
local function profileOf(zombie)
    local outfit = nil
    pcall(function() outfit = zombie:getOutfitName() end)
    if not outfit then return nil end
    outfit = tostring(outfit):lower()
    if outfit:find("police") or outfit:find("swat") or outfit:find("officer")
        or outfit:find("deput") or outfit:find("cop") then return "cop" end
    if outfit:find("army") or outfit:find("military") or outfit:find("soldier") or outfit:find("camo") then return "army" end
    if outfit:find("ranger") or outfit:find("hunt") or outfit:find("farmer") or outfit:find("camou") then return "hunter" end
    if outfit:find("secur") or outfit:find("guard") then return "guard" end
    return nil
end

local function addRounds(inv, ft, n)
    if not ft or n <= 0 then return 0 end
    local added = 0
    for _ = 1, n do
        local ok = false
        pcall(function() if inv:AddItem(ft) then ok = true end end)
        if ok then added = added + 1 end
    end
    return added
end

local function dropForProfile(inv, prof)
    local chance, min, max, boxChance, poolName, shotgunChance
    if prof == "cop"   then local c=CFG.cop;    chance,min,max,boxChance,poolName,shotgunChance = c.chance,c.min,c.max,c.boxChance,c.pool,c.shotgunChance
    elseif prof=="army" then local c=CFG.army;  chance,min,max,boxChance,poolName,shotgunChance = c.chance,c.min,c.max,c.boxChance,c.pool,c.shotgunChance
    elseif prof=="hunter" then local c=CFG.hunter; chance,min,max,boxChance,poolName,shotgunChance = c.chance,c.min,c.max,c.boxChance,c.pool,c.shotgunChance
    elseif prof=="guard" then local c=CFG.guard; chance,min,max,boxChance,poolName,shotgunChance = c.chance,c.min,c.max,c.boxChance,c.pool,c.shotgunChance
    else
        chance,min,max,boxChance,poolName,shotgunChance = CFG.normalCarryChance,CFG.normalMin,CFG.normalMax,CFG.normalBoxChance,nil,0
    end

    -- roll: does this zombie carry anything?
    if ZombRandFloat(0,1) > chance then return end

    -- pick which caliber family
    local pool
    if poolName == "rifle" then pool = POOLS.rifle
    elseif poolName == "pistol" then pool = POOLS.pistol
    else
        -- normal civilian: mostly pistol, some shotgun, occasional rifle/.22
        local r = ZombRand(100)
        if r < 55 then pool = POOLS.pistol elseif r < 80 then pool = POOLS.shotgun else pool = POOLS.rifle end
    end
    -- special: a chance to instead drop shotgun shells (cop/hunter etc.)
    if shotgunChance and shotgunChance > 0 and ZombRandFloat(0,1) < shotgunChance and #POOLS.shotgun > 0 then
        pool = POOLS.shotgun
    end

    local ft = pickWeighted(pool)
    if not ft then ft = pickWeighted(POOLS.pistol) end
    if not ft then return end

    local n = min + ZombRand(max - min + 1)
    if n > CFG.maxRoundsPerZombie then n = CFG.maxRoundsPerZombie end
    addRounds(inv, ft, n)

    -- maybe a box too
    if boxChance and boxChance > 0 and #BOXES > 0 and ZombRandFloat(0,1) < boxChance then
        local box = BOXES[ZombRand(#BOXES) + 1]
        pcall(function() inv:AddItem(box) end)
    end
end

local function onZombieDead(zombie)
    if not ready then buildPools() end
    if not zombie then return end
    local inv = nil
    pcall(function() inv = zombie:getInventory() end)
    if not inv then return end
    local prof = profileOf(zombie)
    pcall(function() dropForProfile(inv, prof) end)
end

-- guard against double-registration if the file is hot-reloaded mid-session, which would
-- otherwise add a second OnZombieDead handler and double every drop.
if not EmpireAmmoDrop_Registered then
    EmpireAmmoDrop_Registered = true
    Events.OnGameStart.Add(buildPools)
    Events.OnZombieDead.Add(onZombieDead)
end

print("[EmpireAmmoDrop] loaded -- zombies drop ammo on death (~20% of normals carry ~4-11 rounds, cops/soldiers rich). Disable the AmmoLootDrop workshop mods to avoid double-up.")
