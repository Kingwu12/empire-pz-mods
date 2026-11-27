-- ============================================================
-- Empire Stockpiles (B42)
-- Make ammo and guns abundant in the places where it makes sense, while the
-- rest of the world stays tight. Pairs with sandbox AmmoLootNew / RangedWeaponLootNew
-- at 1.0 (normal): scarcity comes from WHERE things are, not from a global dial.
--
-- Pure data edit of vanilla ProceduralDistributions / room tables, run once while
-- the distributions load. No events at runtime, no per-tick cost.
-- Every list name below was checked against the vanilla 42.22.2 files; a name that
-- does not exist is skipped silently, so a game update cannot break this.
--
-- How the numbers work: each list has `rolls`; every roll gives each entry its
-- weight as a percent chance. Doubling rolls doubles what a shelf holds.
-- ============================================================

local CFG = {
    -- stockpile places: multiply the list's rolls (4 -> 10 at x2.5)
    rolls = {
        -- gun shops (counter, shelves, cases, mag racks)
        GunStoreAmmunition  = 2.5,
        GunStoreMagsAmmo    = 2.0,
        GunStoreGuns        = 1.5,
        GunStorePistols     = 1.5,
        GunStoreRifles      = 1.5,
        GunStoreShotguns    = 1.5,
        GunStoreCases       = 1.5,
        GunStoreDisplayCase = 1.5,
        GunStoreShelf       = 1.5,
        PawnShopGuns        = 1.25,
        -- police
        PoliceStorageAmmunition = 3.0,
        PoliceStorageGuns       = 2.0,
        PoliceEvidence          = 3.0,
        -- army and surplus
        ArmyStorageAmmunition = 3.0,
        ArmyStorageGuns       = 2.0,
        ArmySurplusAmmoBoxes  = 2.0,
        ArmySurplusCases      = 1.5,
        -- gun owners' own spots
        GarageFirearms = 1.5,
        HuntingLockers = 1.5,
    },

    -- homes: multiply the chance of gun and ammo entries already in these lists
    homeArmsWeight = {
        GarageFirearms = 1.5, HuntingLockers = 1.5, ClosetShelfGeneric = 2.0,
        WardrobeRedneck = 2.0, BedroomDresser = 1.5, BedroomDresserRedneck = 1.5,
        BedroomSidetable = 1.5,
    },
    -- homes: and the odd box of ammo, which vanilla homes never carry. {list, item, weight}
    homeAmmo = {
        { "BedroomSidetable",       "Bullets9mmBox",     0.30 },
        { "BedroomSidetable",       "Bullets38Box",      0.25 },
        { "BedroomDresserRedneck",  "ShotgunShellsBox",  0.40 },
        { "BedroomDresserRedneck",  "Bullets45Box",      0.20 },
        { "ClosetShelfGeneric",     "ShotgunShellsBox",  0.30 },
        { "ClosetShelfGeneric",     "Bullets9mmBox",     0.20 },
        { "WardrobeRedneck",        "ShotgunShellsBox",  0.60 },
        { "WardrobeRedneck",        "3030Box",           0.30 },
        { "GarageFirearms",         "Bullets9mmBox",     4.00 },
        { "GarageFirearms",         "ShotgunShellsBox",  5.00 },
        { "GarageFirearms",         "Bullets38Box",      3.00 },
        { "HuntingLockers",         "308Box",            4.00 },
        { "HuntingLockers",         "3030Box",           4.00 },
        { "HuntingLockers",         "ShotgunShellsBox",  4.00 },
    },

    -- Louisville port: rooms the vanilla tables have no entry for, so they used to
    -- hold only generic crate junk. Map them onto vanilla tables, and let the cargo
    -- rooms carry the odd military or gun-trade shipment.
    portAlias = {
        armyhanger  = "armystorage",       -- army hangar -> army storage
        gunstorage  = "gunstorestorage",   -- gun-store back room
    },
    -- cargo rooms: a warehouse copy plus a chance (percent, per container) of a shipment
    portCargoRooms = { "industrialstorage" },
    portCargo = {
        { "ArmyStorageAmmunition", 12 },
        { "GunStoreAmmunition",     8 },
        { "ArmyStorageGuns",        4 },
        { "PoliceStorageAmmunition", 4 },
    },
}

local done = false

-- vanilla gun ids that home lists carry (Guns of Marz and Guns of '93 swap these for their own *_Spawner items on creation)
local VANILLA_GUNS = {
    Pistol = true, Pistol2 = true, Pistol3 = true, Revolver = true, Revolver_Long = true,
    Revolver_Short = true, Shotgun = true, DoubleBarrelShotgun = true,
    DoubleBarrelShotgunSawnoff = true, HuntingRifle = true, VarmintRifle = true,
    JS14_Rifle = true, L94_Rifle = true, AssaultRifle = true, AssaultRifle2 = true,
}

local function isArms(name)
    if type(name) ~= "string" then return false end
    if VANILLA_GUNS[name] then return true end
    return string.find(name, "Bullets", 1, true) or string.find(name, "ShotgunShells", 1, true)
        or string.find(name, "^%d+Box$") or string.find(name, "^%d+Carton$")
        or string.find(name, "Spawner$") or string.find(name, "AmmoBox", 1, true)
        or string.find(name, "AmmoStrap", 1, true)
end

local function deepCopy(t)
    if type(t) ~= "table" then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = deepCopy(v) end
    return c
end

local function apply()
    if done then return end
    local PD = ProceduralDistributions
    if not PD or not PD.list then return end
    done = true

    local nRolls, nHome, nAmmo, nRooms = 0, 0, 0, 0

    for name, mult in pairs(CFG.rolls) do
        local l = PD.list[name]
        if l and type(l.rolls) == "number" then
            local r = math.floor(l.rolls * mult + 0.5)
            if r < 1 then r = 1 end
            l.rolls = r
            nRolls = nRolls + 1
        end
    end

    for name, mult in pairs(CFG.homeArmsWeight) do
        local l = PD.list[name]
        if l and type(l.items) == "table" then
            for i = 1, #l.items - 1, 2 do
                if isArms(l.items[i]) and type(l.items[i + 1]) == "number" then
                    l.items[i + 1] = l.items[i + 1] * mult
                end
            end
            nHome = nHome + 1
        end
    end

    for _, e in ipairs(CFG.homeAmmo) do
        local l = PD.list[e[1]]
        if l and type(l.items) == "table" then
            table.insert(l.items, e[2])
            table.insert(l.items, e[3])
            nAmmo = nAmmo + 1
        end
    end

    -- port rooms (room table lives in Distributions[1]; SuburbsDistributions is the same table)
    local rooms = (Distributions and Distributions[1]) or SuburbsDistributions
    if rooms then
        for room, target in pairs(CFG.portAlias) do
            if rooms[target] and not rooms[room] then
                rooms[room] = rooms[target]
                nRooms = nRooms + 1
            end
        end
        local wh = rooms.warehouse
        if wh then
            for _, room in ipairs(CFG.portCargoRooms) do
                if not rooms[room] then
                    local copy = deepCopy(wh)
                    for _, cont in pairs(copy) do
                        if type(cont) == "table" and cont.procedural and type(cont.procList) == "table" then
                            for _, c in ipairs(CFG.portCargo) do
                                if PD.list[c[1]] then
                                    table.insert(cont.procList, { name = c[1], min = 0, max = 1, weightChance = c[2] })
                                end
                            end
                        end
                    end
                    rooms[room] = copy
                    nRooms = nRooms + 1
                end
            end
        end
    end

    print("[EmpireStockpiles] applied: rolls on " .. nRolls .. " lists, home weights on " .. nHome
        .. " lists, " .. nAmmo .. " home ammo entries, " .. nRooms .. " port rooms")
end

-- Run when the distributions are about to merge: every mod's files have loaded by then
-- (so entries other mods add, like Guns of Marz's MarzGuns.*_Spawner items, are in place), and the game has not yet
-- read the tables. Vanilla's own room aliases hook the same event. apply() runs once.
if Events and Events.OnPreDistributionMerge then Events.OnPreDistributionMerge.Add(apply) end
if Events and Events.OnPostDistributionMerge then Events.OnPostDistributionMerge.Add(apply) end
