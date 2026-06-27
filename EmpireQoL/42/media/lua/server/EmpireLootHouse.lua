-- ============================================================
-- Empire Loot : houses  (gun-country residential loot)
-- ~Half of Kentucky households own a gun -- but it lives AT HOME in a drawer or
-- closet, not on a shambling corpse. This gives residential containers a
-- realistic chance to hold a firearm + a box of ammo, scaled by house type:
--   Redneck / rural  -> most armed (shotguns, hunting + .22, revolvers)
--   Generic / avg    -> a pistol or shotgun
--   Classy / wealthy -> a home-defense handgun
--   Child rooms      -> NEVER (left untouched on purpose)
--
-- Weights are a % of each table's OWN total weight, so per-container odds stay
-- stable no matter how much junk a table holds. The *_GUN_PCT below is the
-- approx per-roll chance of *any* gun in that container; with ~4 rolls and a
-- few containers per house it lands near the target household rate.
-- No new save needed -- applies to houses in cells you haven't loaded yet.
-- ============================================================

local REDNECK_GUN_PCT = 0.030   -- rural homes ~half armed across a house
local GENERIC_GUN_PCT = 0.012   -- average homes: noticeably fewer
local CLASSY_GUN_PCT  = 0.012   -- wealthy: a handgun, rarely a long gun
local AMMO_PCT        = 0.020   -- box of ammo per-roll chance (redneck); scaled down elsewhere

local REDNECK = { "BedroomDresserRedneck","BedroomSidetableRedneck","WardrobeRedneck","LivingRoomShelfRedneck","LivingRoomSideTableRedneck" }
local GENERIC = { "BedroomDresser","DresserGeneric","WardrobeGeneric","BedroomSidetable","LivingRoomShelf","LivingRoomSideTable" }
local CLASSY  = { "BedroomDresserClassy","BedroomSidetableClassy","WardrobeClassy","LivingRoomShelfClassy","LivingRoomSideTableClassy" }

local GUNS_REDNECK = { "Shotgun","DoubleBarrelShotgun","HuntingRifle","VarmintRifle","Revolver_Long","Pistol" }
local GUNS_GENERIC = { "Pistol","Shotgun" }
local GUNS_CLASSY  = { "Pistol2","Pistol3","Revolver_Short" }
local AMMO_BOXES   = { "ShotgunShellsBox","Bullets9mmBox","Bullets38Box","Bullets357Box","3030Box","308Box" }

local applied = false

local function tableTotal(t)
    local sum = 0
    if t and t.items then
        for i = 2, #t.items, 2 do
            local w = t.items[i]
            if type(w) == "number" then sum = sum + w end
        end
    end
    return sum
end

local function appendWeighted(t, name, weight)
    if not t or not t.items or weight <= 0 then return end
    t.items[#t.items + 1] = name
    t.items[#t.items + 1] = weight
end

-- seed guns (cumulative per-roll chance = gunPct, split across the gun list)
-- and ammo boxes (cumulative = ammoPct, split across boxes) into each table.
local function arm(L, tableNames, guns, gunPct, ammoPct)
    for _, tn in ipairs(tableNames) do
        local t = L[tn]
        if t and t.items then
            local total = tableTotal(t)
            if total <= 0 then total = 50 end
            local gw = (total * gunPct) / math.max(1, #guns)
            for _, g in ipairs(guns) do appendWeighted(t, g, gw) end
            local aw = (total * ammoPct) / math.max(1, #AMMO_BOXES)
            for _, a in ipairs(AMMO_BOXES) do appendWeighted(t, a, aw) end
        end
    end
end

local function applyBuff()
    local L = ProceduralDistributions and ProceduralDistributions.list
    if not L then return false end
    if applied then return true end

    arm(L, REDNECK, GUNS_REDNECK, REDNECK_GUN_PCT, AMMO_PCT)
    arm(L, GENERIC, GUNS_GENERIC, GENERIC_GUN_PCT, AMMO_PCT * 0.6)
    arm(L, CLASSY,  GUNS_CLASSY,  CLASSY_GUN_PCT,  AMMO_PCT * 0.6)

    applied = true
    print("[EmpireLootHouse] residential firearms seeded (redneck>generic>classy, child rooms skipped).")
    return true
end

if not applyBuff() then
    Events.OnPreDistributionMerge.Add(function() pcall(applyBuff) end)
end
