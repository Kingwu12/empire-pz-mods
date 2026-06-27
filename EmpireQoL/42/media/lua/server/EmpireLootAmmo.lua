-- ============================================================
-- Empire Loot : ammo  (server-side distribution buff)
-- Makes the places that SHOULD be stocked actually feel stocked:
-- gun stores, police armouries, military storage.
--
-- HOW IT APPLIES: edits the procedural distribution tables in memory.
-- Containers roll their loot the first time their cell is loaded, so this
-- affects every gun store / police station / military site you HAVEN'T
-- visited yet. No new save needed. Already-explored buildings keep the loot
-- they already rolled (respawn settings can still refill them over time).
--
-- TUNING (keep it sane -- loot is easy to over-cook):
--   ROLL_MULT   = extra pulls per container for gun-store ammo tables
--   POLICE_MULT / ARMY_MULT = same idea, gentler
--   AMMO_BOOST  = weight multiplier on the box/carton ammo already in a table
-- Only existing (vanilla-valid) item names are touched -- nothing invented.
-- ============================================================

local ROLL_MULT   = 3.5    -- GunStore ammo: rolls 4 -> 14 (rare location = real jackpot)
local POLICE_MULT = 2.5    -- PoliceStorageAmmunition: 4 -> 10 (armory + basement)
local ARMY_MULT   = 1.5    -- ArmyStorageAmmunition (already rich): light touch
local AMMO_BOOST  = 3.0    -- gun-store/police box+carton weight x3
local ARMY_BOOST  = 1.3

local GUN_AMMO  = { "GunStoreAmmunition", "GunStoreMagsAmmo" }
local GUN_OTHER = { "GunStoreCounter", "GunStoreDisplayCase", "GunStoreShelf" }
local POLICE    = { "PoliceStorageAmmunition" }
local ARMY      = { "ArmyStorageAmmunition" }

local applied = false

local function bumpRolls(t, mult)
    if t and type(t.rolls) == "number" then
        t.rolls = math.max(t.rolls, math.floor(t.rolls * mult + 0.5))
    end
end

-- boost the weight of ammo that already exists in the table (box / carton).
-- copying nothing, inventing nothing -- just makes stocked calibers heavier.
local function boostAmmo(t, mult)
    if not t or not t.items then return end
    local items = t.items
    for i = 1, #items - 1, 2 do
        local name = items[i]
        if type(name) == "string" then
            local low = name:lower()
            if low:find("box") or low:find("carton") or low:find("ammo") then
                local w = items[i + 1]
                if type(w) == "number" then
                    items[i + 1] = math.max(w, math.floor(w * mult + 0.5))
                end
            end
        end
    end
end

local function applyBuff()
    local L = ProceduralDistributions and ProceduralDistributions.list
    if not L then return false end
    if applied then return true end

    for _, n in ipairs(GUN_AMMO)  do bumpRolls(L[n], ROLL_MULT);   boostAmmo(L[n], AMMO_BOOST) end
    for _, n in ipairs(GUN_OTHER) do bumpRolls(L[n], 2.0) end
    for _, n in ipairs(POLICE)    do bumpRolls(L[n], POLICE_MULT); boostAmmo(L[n], AMMO_BOOST) end
    for _, n in ipairs(ARMY)      do bumpRolls(L[n], ARMY_MULT);   boostAmmo(L[n], ARMY_BOOST) end

    applied = true
    print("[EmpireLoot] ammo buff applied (gun stores / police / military). rollMult=" .. ROLL_MULT)
    return true
end

-- Apply at load if the proc list is ready; otherwise fold into the pre-merge
-- pass so the changes are baked into the distribution. Idempotent either way.
if not applyBuff() then
    Events.OnPreDistributionMerge.Add(function() pcall(applyBuff) end)
end
