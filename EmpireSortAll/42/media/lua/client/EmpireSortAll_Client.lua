-- ============================================================
-- Empire Smart Sort v3  (type affinity + tags + respect-existing)
-- F9 / right-click inventory -> "Smart Sort Base".
-- Right-click any storage in the world -> "Empire Storage" to LOCK it to a
-- category (e.g. the gun cabinet = Guns & Ammo). The lock persists in your save.
--
-- How it decides, per container:
--   * Cold storage (fridge/freezer)  -> holds ONLY perishable food. Anything else
--     gets evicted to its proper home. No more electronics in the freezer.
--   * Tagged container               -> holds ONLY its tagged categories. The gun
--     cabinet keeps guns/ammo; nothing else creeps in, nothing gets pulled out.
--   * A few distinctive furniture types auto-claim a category (wardrobe = clothes)
--     so you needn't tag the obvious ones.
--   * EVERY other container (plain crates/shelves) is left exactly as you arranged
--     it -- the sort never shuffles your organised storage around.
-- Loose loot in your inventory + worn bags is filed into the right homes.
-- ============================================================

local RADIUS = 12
local EMPIRE_SORT_DEBUG = true   -- TEMP: prints a full breakdown to console on each sort (revert when done)

-- ---- item categorisation ----
local DRY_FOOD = {
    TinnedBeans=true, TinnedSardines=true, TinnedCorn=true, TinnedPeas=true,
    CannedCorn=true, CannedPeas=true, CannedTomato=true, CannedBolognese=true,
    CannedChili=true, CannedCarrots=true, CannedMushroomSoup=true,
    TinnedSoup=true, CornedBeef=true, TunaTin=true, Dogfood=true,
    Rice=true, RiceUncooked=true, Pasta=true, PastaUncooked=true,
    Crackers=true, Chips=true, Crisps=true, Sugar=true, Flour=true,
    Cereal=true, Coffee=true, Honey=true, Salt=true, Pop=true,
    CandyPackage=true, BeefJerky=true, Twiggies=true,
}

-- The game tags every item with a DisplayCategory (its own in-game label). We read
-- that and fold the 50-odd game labels into clean storage buckets. Anything we don't
-- explicitly map keeps its raw game label as its own bucket -- so nothing lands in a
-- generic pile, and MODDED items auto-sort by whatever label their mod gave them.
local CAT_MAP = {
    -- ===== FOOD (mapped to "Food" -> split into Perishable / DryFood below by spoilage) =====
    Food="Food",
    FoodP="Food", FoodB="Food", FoodN="Food", FoodS="Food", FoodC="Food", -- Hydrocraft food families
    AnimalDead="Food",                              -- HC carcasses / butchered meat -> fridge
    -- ===== DRINK =====
    Water="Water", WaterContainer="Water",
    -- ===== COOKING =====
    Cooking="Cooking", CookRef="Cooking",
    -- ===== COMBAT =====
    Weapon="Weapon", WeaponCrafted="Weapon", WepMelee="Weapon", WepShield="Weapon", WepBow="Weapon",
    WepRange="Gun", WepFire="Gun",
    MilitaryFirearms="Gun", CivilianFirearms="Gun", PoliceFirearms="Gun",
    WeaponPart="GunParts", WepPart="GunParts", FirearmPart="GunParts",
    Ammo="Ammo", WepAmmoMag="Ammo", AmmoBox="Ammo", AmmoCarton="Ammo",
    Bullets="Ammo", Casings="Ammo", Magazine="Ammo",
    Explosives="Explosives", WepBomb="Explosives",
    -- ===== MEDICAL (incl. HC drugs/pills, which are Type=Food but belong with meds) =====
    FirstAid="Medical", Bandage="Medical", Medical="Medical", Drugs="Medical",
    -- ===== TOOLS / TECH / VEHICLE =====
    Tool="Tools", ToolWeapon="Tools",
    VehicleMaintenance="VehicleParts",
    Electronics="Electronics", Communications="Electronics", CraftElec="Electronics", -- HC CraftElec = electronics
    Devices="Electronics",
    Tuning="VehicleParts", TuningService="VehicleParts",
    LightSource="Light", FireSource="Light",
    -- ===== OUTDOORS / SURVIVAL (HC Sur* family + manure -> gardening) =====
    Gardening="Gardening", SurFarm="Gardening", SurFor="Gardening", SurApi="Gardening", AnimalPoop="Gardening",
    Fishing="Fishing", SurFish="Fishing", SurBug="Fishing",
    Trapping="Trapping", SurTrap="Trapping", SurHunt="Trapping",
    Camping="Camping", SurCamp="Camping",
    -- ===== MATERIALS / CRAFTING (HC Craft* metalwork/carpentry/masonry/mining/bone/gem/etc.) =====
    Material="Materials", RecipeResource="Materials", Paint="Materials", Mineral="Materials", Fuel="Materials", Tile="Materials",
    Craft="Materials", Crafting="Materials", CraftMet="Materials", CraftMetal="Materials",
    CraftCarp="Materials", CraftMas="Materials", CraftMine="Materials", CraftBone="Materials",
    CraftGem="Materials", CraftRec="Materials", CraftRef="Materials", CraftInd="Materials",
    CraftMisc="Materials", CraftAmmo="Materials", CraftCom="Materials", CraftDist="Materials",
    -- ===== CHEMICALS (own shelf -- HC CraftChem is 300+ lab/chemistry items) =====
    CraftChem="Chemicals",
    -- ===== ANIMALS (live animals, cages, animal misc) =====
    Animal="Animals", AnimalMisc="Animals", AnimalEnc="Animals",
    -- ===== BOOKS / READING (HC LitR recipe mags, LitE books) =====
    Literature="Books", Cartography="Books", LitR="Books", LitE="Books", LitW="Books",
    SkillBook="SkillBooks",
    -- ===== ENTERTAINMENT (toys, instruments, sports, fitness) =====
    Entertainment="Entertainment", Sports="Entertainment", Toy="Entertainment",
    Instrument="Entertainment", Fitness="Entertainment",
    -- ===== CLOTHING (HC Cloth* families + appearance/accessories) =====
    Clothing="Clothing", ClothP="Clothing", ClothN="Clothing", ClothM="Clothing",
    Accessory="Accessory",
    Appearance="Household", Appear="Household",
    -- ARMOUR (body armour / protective gear -> its own shelf with the combat kit)
    ProtectiveGear="Armor", BulletproofVest="Armor",
    -- ===== CONTAINERS / FURNITURE / HOUSEHOLD =====
    Bag="Bags", Container="Bags",
    Furniture="Furniture",
    Household="Household", Cleaning="Household",
    -- ===== JUNK / MISC (HC Useless/Trash/Money + vanilla corpse/body labels) =====
    Misc="Misc", Junk="Misc", Useless="Misc", Trash="Misc", Money="Misc", Item="Misc", Memento="Misc",
    Corpse="Misc", MaleBody="Misc", Wound="Misc", ZedDmg="Misc", Hidden="Misc", Security="Misc",
    -- ===== ANIMAL PARTS (butchered parts -- vanilla labels each species separately) =====
    AnimalPart="AnimalParts",
    Badger="AnimalParts", Beaver="AnimalParts", Bunny="AnimalParts", Fox="AnimalParts",
    Hedgehog="AnimalParts", Mole="AnimalParts", Raccoon="AnimalParts", Squirrel="AnimalParts",
}

-- ===== improvised weapons -> stored by FUNCTION, not the armoury =====
-- A frying pan / shovel / bat / axe is wielded as a weapon (DisplayCategory "<X>Weapon")
-- but you STORE it where it's used. Map each suffix label to its real home. Only a
-- DESIGNED weapon (DisplayCategory Weapon/WeaponCrafted) goes to the weapon locker.
local IMPROV_WEAPON_BASE = {
    ToolWeapon="Tools", CookingWeapon="Cooking", HouseholdWeapon="Household",
    GardeningWeapon="Gardening", SportsWeapon="Entertainment", FishingWeapon="Fishing",
    InstrumentWeapon="Entertainment", JunkWeapon="Misc", MaterialWeapon="Materials",
    AnimalPartWeapon="AnimalParts", FirstAidWeapon="Medical",
    VehicleMaintenanceWeapon="VehicleParts",
}

-- ===== drink split (used inside the food branch) =====
-- Alcohol and soft drinks come off the food shelves into their own homes. Plain water
-- is mapped to "Water" before the food branch, so it never reaches here.
local ALCOHOL_WORDS = { "beer","wine","whiskey","whisky","vodka","bourbon","tequila",
    "brandy","liquor","cognac","scotch","moonshine","champagne","spiced rum" }
local DRINK_TYPES  = { Pop=true, PopBottle=true }
local DRINK_WORDS  = { "soda","cola","juice","lemonade","energydrink","energy drink",
    "softdrink","soft drink","kool","gatorade","sports drink","iced tea" }
local function hayHas(hay, words)
    for _, w in ipairs(words) do if hay:find(w, 1, true) then return true end end
    return false
end

-- ===== FREEZER vs FRIDGE (how a real survivor sorts cold storage) =====
-- Raw protein / fish / ice cream goes to the FREEZER (frozen = zero spoilage, long-term).
-- Cooked meals, dairy, produce, drinks stay in the FRIDGE (short-term, eat soon).
local FREEZE_FOODTYPES = { Meat=true, Beef=true, Poultry=true, Fish=true, Seafood=true, Sausage=true, Venison=true, Pork=true }
local FROZEN_WORDS = { "ice cream", "icecream", "popsicle", "gelato", "frozen" }
local function isFreezerFood(item, hay)
    if hayHas(hay, FROZEN_WORDS) then return true end
    local ft = nil
    pcall(function() ft = item:getFoodType() end)
    if ft and FREEZE_FOODTYPES[tostring(ft)] then
        local cooked = false
        pcall(function() cooked = item:isCooked() end)
        if not cooked then return true end   -- raw protein -> freeze it; cooked -> fridge
    end
    return false
end

-- ===== animal-part labels: vanilla fragments these into one bucket PER SPECIES =====
local ANIMAL_WORDS = { "raccoon","fox","badger","beaver","bunny","rabbit","hedgehog",
    "mole","squirrel","deer","possum","skunk","carcass","pelt","antler","hoof","talon" }

-- ===== pattern fallback =====
-- Unmapped labels resolve by keyword so a NEW mod self-classifies instead of spawning a
-- junk bucket per mod (the main cause of category sprawl). Common cases fold together;
-- only a genuinely novel label still falls through to its own bucket downstream.
local function patternBucket(disp)
    if not disp or disp == "" then return nil end
    local d = disp:lower()
    if d:find("firearm", 1, true) then return "Gun" end
    if d:find("ammo", 1, true) or d:find("bullet", 1, true) or d:find("casing", 1, true)
        or d:find("magazine", 1, true) or d:find("shell", 1, true) then return "Ammo" end
    if d:find("bulletproof", 1, true) or d:find("protection", 1, true)
        or d:find("armor", 1, true) or d:find("armour", 1, true)
        or d:find("plate carrier", 1, true) or d:find("kevlar", 1, true) then return "Armor" end
    if d:find("frockin", 1, true) then return "Clothing" end
    if d:find("first aid", 1, true) or d:find("firstaid", 1, true) or d:find("medic", 1, true) then return "Medical" end
    if d:find("tuning", 1, true) then return "VehicleParts" end
    if d:find("device", 1, true) then return "Electronics" end
    if d:find("journal", 1, true) or d:find("skillbook", 1, true) then return "SkillBooks" end
    if d:find("recipe", 1, true) or d:find("scrap", 1, true) then return "Materials" end
    for _, w in ipairs(ANIMAL_WORDS) do if d:find(w, 1, true) then return "AnimalParts" end end
    return nil
end

local function categoryOfRaw(item)
    local result = "Misc"
    pcall(function()
        if not item then return end
        -- firearms first: a ranged hand weapon is a Gun no matter what label it carries
        if instanceof(item, "HandWeapon") then
            local ranged = false
            pcall(function() ranged = item:isRanged() end)
            if ranged then result = "Gun"; return end
            -- Real melee weapon? Two ways to qualify:
            --   1. it's a DESIGNED weapon (DisplayCategory Weapon/WeaponCrafted) -- machete,
            --      katana, hunting knife, spears, and most modded (Brita) weapons; or
            --   2. it actually hits hard (max damage > 1.0) -- catches bats (labelled Sports),
            --      crowbars, axes, and modded weapons with odd labels.
            -- Everything weaker (pen 0.1, fork 0.1, rolling pin 0.5, kitchen knife 0.7,
            -- screwdriver 0.7, hammer 1.0) is NOT treated as a weapon -- it falls through to
            -- its real category (household/tools/cooking) so junk never clogs the weapon locker.
            local d = nil
            pcall(function() d = item:getDisplayCategory() end)
            if d == "Weapon" or d == "WeaponCrafted" then result = "Weapon"; return end
            -- improvised weapon (pan/shovel/bat/axe/crowbar): store by FUNCTION, not the
            -- armoury -- a "<X>Weapon" label maps to its real home (ToolWeapon->Tools etc.).
            if d and IMPROV_WEAPON_BASE[d] then result = IMPROV_WEAPON_BASE[d]; return end
            local dmg = 0
            pcall(function() dmg = item:getMaxDamage() end)
            if dmg > 1.0 then result = "Weapon"; return end
            -- not a real weapon: do NOT return -- fall through to normal mapping below
        end
        if instanceof(item, "Ammo") then result = "Ammo"; return end
        -- gun magazines / clips hold rounds -> file them with ammo. They are NOT
        -- HandWeapons so they slip past the gun check above; getMaxAmmo > 0 = a magazine.
        local maxAmmo = 0
        pcall(function() maxAmmo = item:getMaxAmmo() end)
        if maxAmmo and maxAmmo > 0 then result = "Ammo"; return end

        -- WEARABLES (armour + clothing). Brita's Armor Pack is 549 clothing pieces + 101
        -- wearable plate-carrier *containers*, and most carry NO DisplayCategory -- so they
        -- used to fall through to Misc/Bags and never get sorted. Catch any worn item:
        -- a Clothing instance, OR anything with a real body location (covers the armour
        -- vests that are Type=Container but worn). Worn bags/backpacks are excluded -- they
        -- aren't Clothing instances and report no body location, so they still sort to Bags.
        do
            local worn = instanceof(item, "Clothing")
            local bl = nil
            pcall(function() bl = item:getBodyLocation() end)
            if not worn and bl and bl ~= "" and bl ~= "Bag" then worn = true end
            if worn then
                local d = nil
                pcall(function() d = item:getDisplayCategory() end)
                -- ARMOUR: body armour / protective gear -> stored with combat kit
                if d == "ProtectiveGear" or d == "BulletproofVest" or patternBucket(d) == "Armor" then
                    result = "Armor"; return
                end
                local nm = ""; pcall(function() nm = (item:getName() or ""):lower() end)
                if nm:find("bulletproof",1,true) or nm:find("kevlar",1,true)
                   or nm:find("plate carrier",1,true) or nm:find(" vest",1,true) then
                    result = "Armor"; return
                end
                -- ACCESSORY: jewellery / watches / belts / glasses -> their own shelf
                if d == "Accessory" then result = "Accessory"; return end
                local accSlots = { Necklace=true, Necklace_Long=true, Ears=true, EarTop=true,
                    Nose=true, BellyButton=true, Right_MiddleFinger=true, Left_MiddleFinger=true,
                    Right_RingFinger=true, Left_RingFinger=true, Belt=true, BeltExtra=true,
                    Wrist=true, Eyes=true }
                if bl and accSlots[bl] then result = "Accessory"; return end
                result = "Clothing"; return
            end
        end

        local disp = nil
        pcall(function() disp = item:getDisplayCategory() end)
        local mapped = disp and CAT_MAP[disp] or nil

        -- food: split fresh from long-life so fresh routes to the fridge/freezer
        if mapped == "Food" or (not mapped and instanceof(item, "Food")) then
            local t = item:getType() or ""
            local hay = t:lower()
            pcall(function() hay = (t .. " " .. (item:getName() or "")):lower() end)
            -- ALCOHOL: the engine flag is authoritative -- trust it first.
            local alc = false
            pcall(function() alc = item:isAlcoholic() end)
            if alc then result = "Alcohol"; return end
            -- Keyword matching is a backup, but it's substring-based so it needs a guard:
            -- "chocolate" contains "cola", "baking soda" contains "soda", "butterscotch"
            -- contains "scotch", "root beer" contains "beer". These are food, not drinks.
            local foodGuard = hay:find("choc",1,true) or hay:find("cocoa",1,true)
                or hay:find("baking",1,true) or hay:find("scotch",1,true)
                or hay:find("licoric",1,true) or hay:find("root beer",1,true)
                or hay:find("rootbeer",1,true) or hay:find("ginger beer",1,true)
                or hay:find("gingerbeer",1,true)
            if not foodGuard then
                if hayHas(hay, ALCOHOL_WORDS) then result = "Alcohol"; return end
                if DRINK_TYPES[t] or hayHas(hay, DRINK_WORDS) then result = "Drinks"; return end
            end
            -- remaining food: long-life (pantry) vs fresh (fridge)
            if DRY_FOOD[t] then result = "DryFood"; return end
            local off = 0
            pcall(function() off = item:getOffAgeMax() or 0 end)
            if off > 200000 then result = "DryFood"; return end
            -- fresh: raw protein / fish / ice cream -> FREEZER (long-term); else fridge.
            if isFreezerFood(item, hay) then result = "Frozen" else result = "Perishable" end
            return
        end

        if mapped then result = mapped; return end
        -- unmapped: try keyword patterns so new/modded labels self-classify (firearm->Gun,
        -- frockin->Clothing, protection->Armor, animal names->AnimalParts, etc.) instead of
        -- each mod spawning its own junk bucket.
        local pb = patternBucket(disp)
        if pb then result = pb; return end
        -- BEVERAGE RESCUE: modded energy drinks / sodas can be defined OUTSIDE the Food
        -- class (even vanilla Pop lives in normal.txt), so they skip the food branch above
        -- and would fall to Misc. Catch them by name keyword here, guarded against food
        -- false-positives (chocolate/baking soda/root beer/butterscotch).
        do
            local nm = ""
            pcall(function() nm = ((item:getName() or "") .. " " .. (item:getType() or "")):lower() end)
            local guard = nm:find("choc", 1, true) or nm:find("cocoa", 1, true)
                or nm:find("baking", 1, true) or nm:find("scotch", 1, true)
                or nm:find("root beer", 1, true) or nm:find("rootbeer", 1, true)
                or nm:find("ginger beer", 1, true) or nm:find("gingerbeer", 1, true)
            if not guard then
                if hayHas(nm, ALCOHOL_WORDS) then result = "Alcohol"; return end
                if hayHas(nm, DRINK_WORDS) then result = "Drinks"; return end
            end
        end
        -- still novel: keep the game's own label as a bucket (rare long-tail)
        if disp and disp ~= "" then result = disp; return end
        -- last resort: the item's broad type category
        local cat = item:getCategory() or "Misc"
        if cat == "Weapon" then result = "Weapon"
        elseif cat == "Ammo" then result = "Ammo"
        elseif cat == "Literature" then result = "Books"
        elseif cat == "Container" then result = "Bags"
        else result = "Misc" end
    end)
    return result
end

-- Per-F9-run memo cache. The same item gets classified several times in one sort
-- (countByCat, home-cat build, eviction, magnets, apply, DIAG). categoryOfRaw makes
-- ~8 engine calls each, so on a Hydrocraft base (thousands of items x several passes)
-- that classifier dominates F9 time. Caching by item identity collapses it to ONE
-- classification per item per sort. smartSort resets this table at the start of each run.
local _catCache = {}
local function categoryOf(item)
    if item == nil then return "Misc" end
    local c = _catCache[item]
    if c ~= nil then return c end
    c = categoryOfRaw(item)
    _catCache[item] = c
    return c
end

-- Items we must NEVER auto-move: anything you've favourited (the star) or equipped.
-- A favourite getting yanked into a bin is unacceptable, so this guards every move loop.
local function isProtected(it)
    local p = false
    pcall(function() p = it:isFavorite() end)
    if p then return true end
    pcall(function() p = it:isEquipped() end)
    if p then return true end
    -- holstered / on the hotbar (pistol in a holster, knife on the belt) is part of your
    -- active loadout, even though it isn't "equipped" in-hand -- never auto-sort it.
    -- getAttachedSlot() is an INT index; -1 = not attached (matches vanilla ISHotbar:
    -- it checks == -1 / ~= -1 and sets -1 on detach). The old "~= ''" string compare was
    -- ALWAYS true for the int -1, so every inventory item read as protected and nothing
    -- ever sorted off the player. Compare to -1, and also accept the string slot-type as
    -- a belt-and-suspenders signal.
    pcall(function() local s = it:getAttachedSlot(); p = (type(s) == "number" and s ~= -1) end)
    if not p then pcall(function() local t = it:getAttachedSlotType(); p = (t ~= nil and t ~= "") end) end
    return p == true
end

-- ---- container helpers ----
local function containerType(cont)
    local ctype = ""
    pcall(function() ctype = cont:getType() or "" end)
    return ctype
end
local function isFreezer(ct)
    ct = (ct or ""):lower()
    return ct == "freezer" or ct == "icecream" or ct:find("freezer", 1, true) ~= nil
end
local function isFridge(ct)
    ct = (ct or ""):lower()
    return ct == "fridge" or ct:find("fridge", 1, true) ~= nil
end

-- Distinctive furniture that auto-claims a category. Kept deliberately small --
-- generic crates/shelves/lockers are NOT here, because you have many of them and
-- they have no single meaning. You tag those.
local TYPE_AFFINITY = {
    wardrobe="Clothing", clothingrack="Clothing", dresser="Clothing",
    medicine="Medical",
}
local function affinityOf(ct)
    ct = (ct or ""):lower()
    if ct == "" then return nil end
    if TYPE_AFFINITY[ct] then return TYPE_AFFINITY[ct] end
    for key, cat in pairs(TYPE_AFFINITY) do
        if ct:find(key, 1, true) then return cat end
    end
    return nil
end

-- SMART-BY-DEFAULT via ROOM: PZ container TYPES are mostly generic (crate/shelf/
-- locker), but the ROOM a container sits in encodes purpose. So an untagged box in
-- a kitchen attracts food, a bedroom box attracts clothes, etc. This is a soft
-- filing preference (loose items flow here) -- it does NOT evict, so it never rips
-- out things you deliberately stored. Tag a container for strict food-only eviction.
local ROOM_CATS = {
    kitchen  = { Perishable = true, DryFood = true, Cooking = true },
    pantry   = { DryFood = true, Perishable = true, Cooking = true },
    bedroom  = { Clothing = true },
    closet   = { Clothing = true },
    wardrobe = { Clothing = true },
    bathroom = { Medical = true, Household = true },
    garage   = { Tools = true, VehicleParts = true, Materials = true },
    shed     = { Tools = true, Gardening = true, Materials = true },
    toolshed = { Tools = true, Materials = true },
    medical  = { Medical = true },
    clinic   = { Medical = true },
    pharmacy = { Medical = true },
    office   = { Books = true, Household = true },
    library  = { Books = true, SkillBooks = true },
}
local function roomCatsOf(cont)
    local name = nil
    pcall(function()
        local sq
        local pa = cont:getParent(); if pa then sq = pa:getSquare() end
        if not sq and cont.getSquare then sq = cont:getSquare() end
        local room = sq and sq:getRoom()
        if room and room.getName then name = room:getName() end
    end)
    if not name or name == "" then return nil end
    name = name:lower()
    if ROOM_CATS[name] then return ROOM_CATS[name] end
    for key, cats in pairs(ROOM_CATS) do
        if name:find(key, 1, true) then return cats end
    end
    return nil
end

-- ---- tags (persisted on the furniture object's ModData, survives save/load) ----
local VALID = {
    Perishable=true, Frozen=true, DryFood=true, Water=true, Drinks=true, Alcohol=true, Cooking=true, Compost=true,
    Gun=true, Weapon=true, Ammo=true, GunParts=true, Explosives=true, Armor=true,
    Medical=true, Tools=true, VehicleParts=true, Materials=true, Chemicals=true, Electronics=true,
    Light=true, Gardening=true, Fishing=true, Trapping=true, Camping=true, Animals=true, AnimalParts=true,
    Books=true, SkillBooks=true, Entertainment=true,
    Clothing=true, Accessory=true, Bags=true, Furniture=true, Household=true, Misc=true,
}

-- Tags live in ONE persisted global table keyed by the container's WORLD POSITION
-- (+ its type), NOT on the furniture object's ModData. This is the RV/vehicle fix:
-- the object you right-click and the object the F9 scan finds can be different Lua
-- instances that do NOT share ModData, so a lock set via the menu was invisible to the
-- sorter ("nothing to move"). A position key resolves identically from both paths.
local function tagTable()
    local t = nil
    pcall(function() t = ModData.getOrCreate("EmpireStorageTags") end)
    return t or {}
end
local function containerKey(c)
    if not c then return nil end
    local sq = nil
    pcall(function() local pa = c:getParent(); if pa then sq = pa:getSquare() end end)
    if not sq then pcall(function() sq = c:getSquare() end) end
    if not sq then return nil end
    local x, y, z = 0, 0, 0
    pcall(function() x = sq:getX(); y = sq:getY(); z = sq:getZ() end)
    local ct = ""; pcall(function() ct = c:getType() or "" end)
    return x .. "|" .. y .. "|" .. z .. "|" .. ct
end
local function readTagSet(c)
    local key = containerKey(c)
    if not key then return nil end
    local raw = tagTable()[key]
    if not raw or raw == "" then return nil end
    local set, any = {}, false
    for part in tostring(raw):gmatch("[^,]+") do
        part = part:gsub("%s+", "")
        if VALID[part] then set[part] = true; any = true end
    end
    if not any then return nil end
    return set
end
local function writeTag(c, str)
    local key = containerKey(c)
    if not key then return end
    local t = tagTable()
    if str == nil or str == "" then t[key] = nil else t[key] = str end
end

-- ---- storage-scan cache: containers don't move, so re-sweeping the whole base on
-- every F9 was the lag. Scan once, reuse for a short TTL, then auto-rescan. ----
local _ss_cache, _ss_cacheKey, _ss_cacheAt = nil, nil, 0
local SS_CACHE_TTL_MS = 20000   -- reuse the scanned container list for up to 20s
local SS_MAX_SPAN     = 64      -- runaway guard: never sweep a box bigger than this

-- ---- gather every storage within radius, on every floor ----
-- Returns list of { c=container, obj=ownerObject, ctype=string, tag=set|nil }.
local function collectStorages(player)
    local out, seen = {}, {}
    local sq = player:getCurrentSquare()
    if not sq then return out end
    local cell = getCell()
    -- SCAN AREA: the WHOLE defined base when you're standing in one (Fallout-style
    -- shared pool); otherwise a radius box around you (the old behaviour). Base sweep
    -- still runs on the floor you're on -- stand on each level and F9 for multi-floor.
    local bx1, bx2, by1, by2, bz1, bz2
    if EmpireBases and EmpireBases.scanBounds then
        bx1, bx2, by1, by2, bz1, bz2 = EmpireBases.scanBounds(player, RADIUS)
    end
    if not bx1 then
        local px, py = sq:getX(), sq:getY()
        bx1, bx2, by1, by2, bz1, bz2 = px - RADIUS, px + RADIUS, py - RADIUS, py + RADIUS, sq:getZ(), sq:getZ()
    end
    -- runaway guard: clamp an over-large base sweep to a box around the player
    local _cpx, _cpy = sq:getX(), sq:getY()
    if (bx2 - bx1) > SS_MAX_SPAN then bx1, bx2 = _cpx - 32, _cpx + 32 end
    if (by2 - by1) > SS_MAX_SPAN then by1, by2 = _cpy - 32, _cpy + 32 end
    -- cache: same scan box within TTL -> reuse the list, skip the whole sweep
    local _sskey = bx1 .. "," .. bx2 .. "," .. by1 .. "," .. by2 .. "," .. bz1 .. "," .. bz2
    if _ss_cache and _ss_cacheKey == _sskey and (getTimestampMs() - _ss_cacheAt) < SS_CACHE_TTL_MS then
        return _ss_cache
    end
    for z = bz1, bz2 do
        for x = bx1, bx2 do
            for y = by1, by2 do
                local s = cell:getGridSquare(x, y, z)
                if s then
                    local objs = s:getObjects()
                    for i = 0, objs:size() - 1 do
                        local obj = objs:get(i)
                        -- One object can carry MORE THAN ONE container -- e.g. an
                        -- industrial fridge is a single object with a fridge compartment
                        -- AND a freezer compartment. getContainer() returns only the first,
                        -- so the other half was invisible to the sort. Enumerate them all
                        -- via getContainerByIndex (the API the vanilla inventory UI uses),
                        -- falling back to getContainer() for single-container objects.
                        local conts = {}
                        local ncont = 0
                        pcall(function() ncont = obj:getContainerCount() or 0 end)
                        if ncont and ncont > 0 then
                            for ci = 0, ncont - 1 do
                                local cc = nil
                                pcall(function() cc = obj:getContainerByIndex(ci) end)
                                if cc then conts[#conts+1] = cc end
                            end
                        else
                            local cc = nil
                            pcall(function() cc = obj:getContainer() end)
                            if cc then conts[#conts+1] = cc end
                        end
                        for _, c in ipairs(conts) do
                            if c and not seen[c] then
                                seen[c] = true
                                -- HARD SKIP functional containers (ISA solar power box, etc.):
                                -- never scanned, never evicted, never magneted out of -- so F9
                                -- can never yank a working battery out of the power box.
                                if not (EmpireSortConfig and EmpireSortConfig.isExcludedContainer
                                        and EmpireSortConfig.isExcludedContainer(c)) then
                                    local holder = obj
                                    pcall(function() local pa = c:getParent(); if pa then holder = pa end end)
                                    out[#out+1] = {
                                        c = c, obj = holder, ctype = containerType(c),
                                        tag = readTagSet(c),
                                    }
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    _ss_cache, _ss_cacheKey, _ss_cacheAt = out, _sskey, getTimestampMs()
    return out
end

-- rotten food test (used to PURGE rot to the floor and to SKIP rot during floor pickup)
local function isRottenItem(it)
    -- isRotten() exists ONLY on Food items. Calling it on a tool/weapon/material is a
    -- nil-method call -- pcall catches it for control flow, but PZ's VM still logs the
    -- exception, flooding the console with one trace per non-food item. Guard with an
    -- instanceof Food check first (same pattern AutoFeed uses) so it's never called blind.
    local food = false
    pcall(function() food = instanceof(it, "Food") end)
    if not food then return false end
    local r = false
    pcall(function() r = it:isRotten() end)
    return r
end

-- Tell "loot I dumped to sort" apart from "stuff I PLACED on purpose". Floor pickup must
-- NEVER grab the second kind: your ammo furnace, generators, decorations, placed furniture.
-- Guard 1: Moveable item-form (all furniture/decor you set down). Guard 2: a denylist of
-- functional deployables by type. Favourite anything else you want permanently left alone.
local PLACED_KEEP_KEYS = {
    "furnace","smelt","foundr","forge","anvil","kiln","crucible","bellows","grindstone",
    "generator","campfire","compost","rainco","still","brew","loom","spinningwheel",
    "beehive","trough","workbench","smithy","cauldron",
}
-- Functional crafting STATIONS that are item-form containers, NOT Moveables, and whose
-- type name carries none of the keywords above -- so the keyword/Moveable guards miss them
-- and F9 "packs them up" off the floor. The Lee Load-Master / Lyman reloading presses are
-- exactly this: Type=Container, DisplayCategory=ReloadingTool. Keep by DisplayCategory so
-- ANY reloading bench from ANY mod is left where you placed it, with exact types as backup.
local PLACED_KEEP_CATS  = { ReloadingTool = true }
local PLACED_KEEP_TYPES = { lee_loadmaster = true, lyman_tmag = true }
local function isPlacedKeepItem(it)
    if not it then return false end
    local mv = false
    pcall(function() mv = instanceof(it, "Moveable") end)
    if mv then return true end
    local disp = nil
    pcall(function() disp = it:getDisplayCategory() end)
    if disp and PLACED_KEEP_CATS[disp] then return true end
    local t = ""
    pcall(function() t = (it:getType() or ""):lower() end)
    if t ~= "" then
        if PLACED_KEEP_TYPES[t] then return true end
        for _, k in ipairs(PLACED_KEEP_KEYS) do
            if t:find(k, 1, true) then return true end
        end
    end
    return false
end

-- ---- gather loose items lying on the FLOOR within radius, every floor ----
-- You dump loot on the ground for "sort later", so the sort has to see it. Returns
-- { wo=IsoWorldInventoryObject, item=InventoryItem, sq=square } for each ground item.
local function collectFloorItems(player)
    local out = {}
    local sq = player:getCurrentSquare()
    if not sq then return out end
    local cell = getCell()
    if not cell then return out end
    -- SCAN AREA: floor loot is dumped near you, so scan only a radius box around the
    -- player (not the whole base). This keeps F9 cheap -- the big sweep was the lag.
    local bx1, bx2, by1, by2, bz1, bz2
    do
        local px, py = sq:getX(), sq:getY()
        bx1, bx2, by1, by2, bz1, bz2 = px - RADIUS, px + RADIUS, py - RADIUS, py + RADIUS, sq:getZ(), sq:getZ()
    end
    for z = bz1, bz2 do
        for x = bx1, bx2 do
            for y = by1, by2 do
                local s = cell:getGridSquare(x, y, z)
                if s then
                    local wos = nil
                    pcall(function() wos = s:getWorldObjects() end)
                    if wos then
                        for i = 0, wos:size() - 1 do
                            local wo = wos:get(i)
                            local it = nil
                            pcall(function() it = wo:getItem() end)
                            if it and not isPlacedKeepItem(it) then out[#out+1] = { wo = wo, item = it, sq = s } end
                        end
                    end
                end
            end
        end
    end
    return out
end

-- count items per category currently in a container
local function countByCat(cont)
    local counts = {}
    local items = cont:getItems()
    for i = 0, items:size() - 1 do
        local k = categoryOf(items:get(i))
        counts[k] = (counts[k] or 0) + 1
    end
    return counts
end

-- storage ItemContainers of a SPECIFIC vehicle (trunk/bed/seats/glovebox). Parts without
-- storage are skipped. Verified vs vanilla: getPartCount/getPartByIndex, VehiclePart:getItemContainer.
local function vehicleStorageContainers(veh)
    local conts = {}
    if not veh then return conts end
    pcall(function()
        local n = veh:getPartCount() or 0
        for i = 0, n - 1 do
            local part = veh:getPartByIndex(i)
            local c = nil
            if part then pcall(function() c = part:getItemContainer() end) end
            if c then conts[#conts + 1] = c end
        end
    end)
    return conts
end

local function smartSort(player, opts)
    if not player then player = getSpecificPlayer(0) end
    if not player then return end
    opts = opts or {}

    _catCache = {}   -- fresh category cache for this sort run (perf: classify each item once)
    local stores = collectStorages(player)
    if #stores == 0 then
        HaloTextHelper.addTextWithArrow(player, "No storage nearby to sort", "[br/]", false, HaloTextHelper.getColorRed())
        player:Say("No storage close enough to sort.")
        return
    end

    -- Fallout-style base pool: when you're standing in a defined base, F9 swept the
    -- WHOLE base (collectStorages handled the area). Surface which base so it's visible.
    local _activeBase = (EmpireBases and EmpireBases.activeBase and EmpireBases.activeBase(player)) or nil
    if _activeBase then
        HaloTextHelper.addTextWithArrow(player, "BASE SORT: " .. (_activeBase.name or "Main") .. " (" .. #stores .. " containers)", "[br/]", false, HaloTextHelper.getColorGreen())
    end

    -- Classify each store + decide its strict home categories.
    --   designated = true means it evicts anything outside homeCats.
    --   general containers (designated=false) keep whatever they already hold.
    for _, st in ipairs(stores) do
        if st.tag then
            st.designated, st.homeCats = true, st.tag
        elseif isFreezer(st.ctype) then
            st.designated, st.homeCats = true, { Frozen = true }
            st.cold = true; st.freezer = true
        elseif isFridge(st.ctype) then
            st.designated, st.homeCats = true, { Perishable = true }
            st.cold = true
        else
            local aff = affinityOf(st.ctype)
            if aff then
                st.designated, st.homeCats = true, { [aff] = true }
            else
                st.designated = false
                local hc = {}
                for cat in pairs(countByCat(st.c)) do hc[cat] = true end
                -- ROOM-SMART DEFAULT: a general box inherits its room's preferred
                -- categories as a SOFT filing hint (kitchen->food, bedroom->clothes,
                -- garage->tools...). We only ADD to homeCats so loose items flow here;
                -- designated stays false, so nothing already stored is ever evicted.
                st.roomCats = roomCatsOf(st.c)
                if st.roomCats then for cat in pairs(st.roomCats) do hc[cat] = true end end
                st.homeCats = hc           -- respect existing arrangement + room hint
            end
        end
    end

    -- which containers are cold (food appliances) -- used so we only warn about
    -- non-food that's genuinely trapped in a fridge/freezer with no shelf to take it.
    local coldConts = {}
    for _, st in ipairs(stores) do if st.cold then coldConts[st.c] = true end end

    -- Build destFor[cat] = the single best container to FILE a loose/evicted item of
    -- that category into. destsFor[cat] keeps the FULL ordered fallback list so a full
    -- primary container spills over to the next valid one instead of "nowhere to go".
    -- Priority: tagged > affinity/cold > general-holding-most > any general.
    local destFor = {}
    local destsFor = {}
    local function offer(cat, cont)
        if not cat or not cont then return end
        if not destFor[cat] then destFor[cat] = cont end
        local lst = destsFor[cat]; if not lst then lst = {}; destsFor[cat] = lst end
        for _, c in ipairs(lst) do if c == cont then return end end
        lst[#lst+1] = cont
    end

    for _, st in ipairs(stores) do        -- tagged first
        if st.tag then for cat in pairs(st.tag) do offer(cat, st.c) end end
    end
    for _, st in ipairs(stores) do        -- cold + affinity
        if st.designated and not st.tag then
            for cat in pairs(st.homeCats) do offer(cat, st.c) end
        end
    end
    -- cold cross-fallback: a freezer is the primary Frozen home and a fridge the primary
    -- Perishable home (offered above via homeCats). But if you only own ONE of them, it
    -- takes the other's overflow too -- a freezer accepts fridge food, a fridge accepts
    -- frozen food -- ranked AFTER the proper appliance so it's only a fallback.
    for _, st in ipairs(stores) do
        if st.designated and not st.tag and st.cold then
            if st.freezer then offer("Perishable", st.c) else offer("Frozen", st.c) end
        end
    end
    -- room-smart: a general box sitting in a kitchen/bedroom/garage/etc is a PREFERRED
    -- filing home for that room's categories -- offered ahead of "general holding the
    -- most" so loose food flows to the kitchen box, clothes to the bedroom box, etc.
    -- Still non-evicting (these stores stay designated=false); this only sets where
    -- HOMELESS/loose items prefer to land.
    for _, st in ipairs(stores) do
        if not st.designated and st.roomCats then
            for cat in pairs(st.roomCats) do offer(cat, st.c) end
        end
    end
    -- general containers: give each category to the general container already holding
    -- the most of it (extends your existing organisation instead of fighting it).
    local mostOf = {}                      -- cat -> {cont=, n=}
    local generals = {}
    for _, st in ipairs(stores) do
        if not st.designated then
            generals[#generals+1] = st.c
            for cat, n in pairs(countByCat(st.c)) do
                if not mostOf[cat] or n > mostOf[cat].n then mostOf[cat] = { cont = st.c, n = n } end
            end
        end
    end
    for cat, rec in pairs(mostOf) do offer(cat, rec.cont) end
    -- round-robin any general container to categories still without a destination
    if #generals > 0 then
        local CATS = {
            "Perishable","Frozen","DryFood","Water","Drinks","Alcohol","Cooking","Gun","Weapon","Ammo","GunParts",
            "Explosives","Armor","Medical","Tools","VehicleParts","Materials","Chemicals","Electronics",
            "Light","Gardening","Fishing","Trapping","Camping","Animals","AnimalParts","Books","SkillBooks",
            "Entertainment","Clothing","Accessory","Bags","Furniture","Household","Misc",
        }
        local gi = 0
        for _, cat in ipairs(CATS) do
            if not destFor[cat] then offer(cat, generals[(gi % #generals) + 1]); gi = gi + 1 end
        end
    end

    -- UNIVERSAL HOME: guarantee EVERY category that shows up gets a general-box home,
    -- even odd/modded buckets and Misc (money/coins) not in the fixed list above. This is
    -- what stops "a pile of stuff that never gets sorted" -- if you own ANY unlabelled box,
    -- anything homeless flows into one (round-robin) instead of being left behind.
    local _rrIdx = 0
    local function homeFor(cat)
        if destFor[cat] then return destFor[cat] end
        if #generals > 0 then
            _rrIdx = _rrIdx + 1
            local c = generals[((_rrIdx - 1) % #generals) + 1]
            offer(cat, c)
            return c
        end
        return nil
    end

    -- free weight (headroom) of a container -- drives load-sharing + the overfill guard.
    local function freeOf(c)
        local mx, cur = 0, 0
        pcall(function() mx = c:getMaxWeight() end)
        pcall(function() cur = c:getCapacityWeight() end)
        return (mx or 0) - (cur or 0)
    end
    -- copy + sort emptiest-first so items SPREAD across same-category containers instead
    -- of cramming the first one to the brim. Never mutates the input list.
    local function byFreeDesc(list)
        local out = {}
        if list then for _, c in ipairs(list) do out[#out+1] = c end end
        table.sort(out, function(a, b) return freeOf(a) > freeOf(b) end)
        return out
    end
    local isDesig = {}
    for _, st in ipairs(stores) do if st.designated then isDesig[st.c] = true end end

    -- EMPIRE PATCH: spill list for a category = its priority homes, THEN every other
    -- unlabelled box. Load-shared WITHIN each tier (emptiest first) but tiers kept in
    -- order, so fresh food still fills fridges/designated homes before loose shelves --
    -- it just spreads evenly across them instead of jamming the first.
    local function spillCands(cat)
        local out, seen = {}, {}
        local desig, gen = {}, {}
        for _, c in ipairs(destsFor[cat] or {}) do
            if isDesig[c] then desig[#desig + 1] = c else gen[#gen + 1] = c end
        end
        local function push(list)
            for _, c in ipairs(list) do if not seen[c] then seen[c] = true; out[#out + 1] = c end end
        end
        push(byFreeDesc(desig))      -- designated homes (fridges/tagged/affinity), emptiest first
        push(byFreeDesc(gen))        -- general boxes already holding this category
        push(byFreeDesc(generals))   -- any general box at all
        return out
    end

    -- ---- plan moves ----
    local moves = {}

    -- (1) containers: only DESIGNATED ones evict mis-filed items; generals are left alone.
    for _, st in ipairs(stores) do
        if st.designated then
            local items = st.c:getItems()
            local snap = {}
            for i = 0, items:size() - 1 do snap[#snap+1] = items:get(i) end
            for _, it in ipairs(snap) do
                if not isProtected(it) then
                    local cat = categoryOf(it)
                    if not st.homeCats[cat] then
                        local dest = homeFor(cat)
                        -- fridges/freezers must end up food-only. If a misfiled item has no
                        -- home shelf nearby (e.g. inside the RV), pull it into your inventory
                        -- so it still leaves the cold instead of being stuck there.
                        if (not dest) and st.cold then dest = player:getInventory() end
                        if dest and dest ~= st.c then moves[#moves+1] = { item = it, from = st.c, to = dest } end
                    end
                end
            end
        end
    end

    -- (1a) EMPIRE PATCH: rebalance OVER-CAPACITY boxes (general AND designated/tagged).
    -- If a box is stuffed past its weight limit, shed just enough items to get it back
    -- under cap, through the capacity-checked apply path (room-checked per destination).
    --   * general / affinity / cold boxes -> shed via the normal spill path.
    --   * TAGGED boxes -> shed as MAGNET moves so overflow only goes to ANOTHER tagged
    --     home of the same category; if none has room it stays put. This stops overflow
    --     landing in a general box that the (1b) magnet pass would just yank back (thrash).
    for _, st in ipairs(stores) do
        local mx, cur = 0, 0
        pcall(function() mx = st.c:getMaxWeight() end)
        pcall(function() cur = st.c:getCapacityWeight() end)
        if mx and mx > 0 and cur and cur > mx then
            local items = st.c:getItems()
            local snap = {}
            for i = 0, items:size() - 1 do snap[#snap+1] = items:get(i) end
            local proj = cur
            for _, it in ipairs(snap) do
                if proj <= mx then break end
                if not isProtected(it) then
                    local iw = 0; pcall(function() iw = it:getWeight() end)
                    if st.tag then
                        moves[#moves+1] = { item = it, from = st.c, magnet = true }
                    else
                        moves[#moves+1] = { item = it, from = st.c }
                    end
                    proj = proj - (iw or 0)
                end
            end
        end
    end

    -- (1b) MAGNET: anything whose category you've TAGGED a container for gets pulled
    -- into that container from ANYWHERE nearby -- untagged shelves included. This is what
    -- makes "tag the cabinet Guns & Ammo, hit F9" actually gather every gun into it.
    -- Untagged categories are still left where they are (respect-existing); only the
    -- types you explicitly locked act as magnets, so nothing else gets shuffled.
    local taggedDest = {}      -- cat -> first tagged container (planning)
    local taggedDests = {}     -- cat -> ALL tagged containers for that cat (apply spillover, tagged-only)
    for _, st in ipairs(stores) do
        if st.tag then
            for cat in pairs(st.tag) do
                if not taggedDest[cat] then taggedDest[cat] = st.c end
                local l = taggedDests[cat]; if not l then l = {}; taggedDests[cat] = l end
                l[#l+1] = st.c
            end
        end
    end
    for _, st in ipairs(stores) do
        local items = st.c:getItems()
        local snap = {}
        for i = 0, items:size() - 1 do snap[#snap+1] = items:get(i) end
        for _, it in ipairs(snap) do
            if not isProtected(it) and not isRottenItem(it) then
                -- NOTE: rotten food is owned entirely by PASS A (compost routing), so it is
                -- never magnet-pulled here -- otherwise it'd get yanked out of the compost
                -- bin toward a Perishable/fridge home on the next sort.
                local cat = categoryOf(it)
                local dest = taggedDest[cat]
                -- magnet=true: belongs in a TAGGED container ONLY. If all tagged homes
                -- for it are full, it STAYS put (never shuffled to a random shelf) and is
                -- reported as "couldn't fit" so you know to tag a bigger container.
                -- IDEMPOTENCY: if the item is ALREADY in a container tagged for its own
                -- category it's already home -- don't drag it toward the "first" tagged box.
                -- (That was making two same-tag containers ping-pong items every sort.)
                local alreadyHome = st.tag and st.tag[cat]
                if dest and dest ~= st.c and not alreadyHome then moves[#moves+1] = { item = it, from = st.c, to = dest, magnet = true } end
            end
        end
    end

    -- (2) loose loot the player is carrying (inventory + worn bags) -> homes.
    local carried, seenC = {}, {}
    local function addCarried(cont, depth)
        if not cont or seenC[cont] or depth > 4 then return end
        seenC[cont] = true
        carried[#carried+1] = cont
        local items = nil
        pcall(function() items = cont:getItems() end)
        if not items then return end
        for i = 0, items:size() - 1 do
            local it = items:get(i)
            local sub = nil
            if instanceof(it, "InventoryContainer") then
                -- a bag you've marked "keep" (loadout bag) is skipped whole -- its
                -- contents never get sorted out. Flag lives on the bag's ModData.
                local keep = false
                pcall(function() local md = it:getModData(); keep = md and md.empireKeepBag == true end)
                if not keep then pcall(function() sub = it:getInventory() end) end
            end
            if sub and sub ~= cont then addCarried(sub, depth + 1) end
        end
    end
    pcall(function() addCarried(player:getInventory(), 0) end)

    -- VEHICLE UNLOAD (right-click vehicle -> "Transfer loot to base"): pull loot from the
    -- SPECIFIC vehicle you clicked (opts.vehicle) into base homes. addCarried recurses into
    -- bags in the trunk too. Same protections (favourites/holstered/loadout ammo skipped).
    if opts.vehicle then
        local vconts = vehicleStorageContainers(opts.vehicle)
        if #vconts > 0 then
            HaloTextHelper.addTextWithArrow(player, "UNLOADING VEHICLE -> base", "[br/]", false, HaloTextHelper.getColorGreen())
            for _, vc in ipairs(vconts) do pcall(function() addCarried(vc, 0) end) end
        end
    end

    -- LOADOUT PROTECTION: keep ammo + magazines that match any gun you're actively
    -- carrying (in-hand or holstered), so a sort never strips your gun's ammo. The mag
    -- already inside the gun moves with the protected gun; this covers SPARE mags and
    -- LOOSE rounds. No favouriting required.
    local neededAmmo, neededMags = {}, {}
    do
        local function addGun(w)
            if not w or not instanceof(w, "HandWeapon") then return end
            local ranged = false; pcall(function() ranged = w:isRanged() end)
            if not ranged then return end
            local at, mt = nil, nil
            pcall(function() at = w:getAmmoType() end)
            pcall(function() mt = w:getMagazineType() end)
            if at and at ~= "" then neededAmmo[at] = true; neededAmmo[at:gsub("^.*%.", "")] = true end
            if mt and mt ~= "" then neededMags[mt] = true; neededMags[mt:gsub("^.*%.", "")] = true end
        end
        pcall(function() addGun(player:getPrimaryHandItem()) end)
        pcall(function() addGun(player:getSecondaryHandItem()) end)
        pcall(function()
            local hb = getPlayerHotbar(0)
            if hb and hb.attachedItems then for _, hit in pairs(hb.attachedItems) do addGun(hit) end end
        end)
    end
    local function isLoadoutItem(it)
        local ft, tp = "", ""
        pcall(function() ft = it:getFullType() or "" end)
        pcall(function() tp = it:getType() or "" end)
        return (neededAmmo[ft] or neededAmmo[tp] or neededMags[ft] or neededMags[tp]) == true
    end

    for _, cont in ipairs(carried) do
        local items = nil
        pcall(function() items = cont:getItems() end)
        if items then
            local snap = {}
            for i = 0, items:size() - 1 do snap[#snap+1] = items:get(i) end
            for _, it in ipairs(snap) do
                local isBag = instanceof(it, "InventoryContainer")
                if not isProtected(it) and not isLoadoutItem(it) then
                    if isBag then
                        -- loose EMPTY bags (garbage/paper bag, spare duffel) are clutter ->
                        -- file them like any item. A bag with stuff inside is left so its
                        -- contents sort out first (it files once empty); a worn/favourited
                        -- bag is already protected above; a "keep" bag is skipped; and a
                        -- placed cart/deployable is blocked downstream by NEVER_MOVE.
                        local empty, keep = true, false
                        pcall(function() empty = it:getInventory():getItems():isEmpty() end)
                        pcall(function() local md = it:getModData(); keep = md and md.empireKeepBag == true end)
                        if empty and not keep then
                            local cat = categoryOf(it)
                            local dest = homeFor(cat)
                            if dest and dest ~= cont then moves[#moves+1] = { item = it, from = cont, to = dest } end
                        end
                    else
                        local cat = categoryOf(it)
                        local dest = homeFor(cat)
                        if dest and dest ~= cont then moves[#moves+1] = { item = it, from = cont, to = dest } end
                    end
                end
            end
        end
    end

    -- ---- apply moves: primary dest, then fall back to other containers of the same
    -- category. If nothing has room, the item is LEFT where it is (it was already in a
    -- valid spot) instead of reporting a fake "nowhere to go". Only non-food still
    -- trapped in a fridge/freezer is reported, because that genuinely needs a shelf.
    local moved, touched, byCat = 0, {}, {}
    local stuckCold, blocked, noRoom = 0, 0, 0
    -- move `item` out of `fromCont` into the first of `candidates` that has room
    local function placeInto(item, fromCont, candidates)
        if not candidates then return false end
        -- never relocate items flagged NEVER_MOVE (wheeled carts, deployables, etc.)
        if EmpireSortConfig and EmpireSortConfig.isNeverMove and EmpireSortConfig.isNeverMove(item) then return false end
        for _, dest in ipairs(candidates) do
            if dest ~= fromCont then
                local fits = false
                pcall(function()
                    local ok = dest:isItemAllowed(item) and dest:hasRoomFor(player, item)
                    -- OVERFILL GUARD: some containers report room past their weight cap,
                    -- which is how a box ends up at 60/50. Enforce the cap ourselves.
                    if ok then
                        local mx, cur, iw = 0, 0, 0
                        pcall(function() mx = dest:getMaxWeight() end)
                        pcall(function() cur = dest:getCapacityWeight() end)
                        pcall(function() iw = item:getWeight() end)
                        if mx and mx > 0 and (cur + (iw or 0)) > mx + 0.001 then ok = false end
                    end
                    fits = ok
                end)
                if fits then
                    local ok = pcall(function() dest:addItem(item); fromCont:Remove(item) end)
                    if ok then touched[dest] = true; touched[fromCont] = true; return true end
                end
            end
        end
        return false
    end
    for _, mv in ipairs(moves) do
        local stillThere = false
        pcall(function() stillThere = mv.from:contains(mv.item) end)
        if stillThere then
            local cat = categoryOf(mv.item)
            if mv.magnet then
                -- tag-pull: ONLY into a tagged container for this category. All full -> stay put.
                if placeInto(mv.item, mv.from, byFreeDesc(taggedDests[cat])) then
                    moved = moved + 1; byCat[cat] = (byCat[cat] or 0) + 1
                else
                    blocked = blocked + 1   -- tagged home(s) full; left exactly where it was
                end
            else
                -- eviction / loose loot: file into any home (tagged or general)
                if placeInto(mv.item, mv.from, spillCands(cat)) then
                    moved = moved + 1; byCat[cat] = (byCat[cat] or 0) + 1
                elseif coldConts[mv.from] then
                    -- non-food trapped in cold -> any free shelf, so the cold goes food-only
                    if placeInto(mv.item, mv.from, generals) then
                        moved = moved + 1; byCat[cat] = (byCat[cat] or 0) + 1
                    else
                        stuckCold = stuckCold + 1
                    end
                else
                    noRoom = noRoom + 1   -- not cold, every shelf for this category is full
                end
            end
        end
    end
    -- ---- PASS A: purge ROTTEN food -> into a Compost-tagged bin, else dropped on floor ----
    -- Rotten food is never eaten (AutoFeed skips it) and just clogs fridges/crates. Pull
    -- every rotten item out of every scanned container. If you've tagged a bin "Compost",
    -- rotten food goes IN there (for composting). Only if there's no compost bin -- or it's
    -- full -- does it fall back to the floor (old behaviour). Favourites are left alone.
    local rottenDumped, rottenComposted = 0, 0
    -- find every compost bin in range up front
    local compostBins = {}
    for _, st in ipairs(stores) do
        if st.tag and st.tag.Compost then compostBins[#compostBins+1] = st end
    end
    for _, st in ipairs(stores) do
        if not (st.tag and st.tag.Compost) then   -- never pull rotten OUT of a compost bin
            local its = st.c:getItems()
            local snap = {}
            for i = 0, its:size() - 1 do snap[#snap+1] = its:get(i) end
            for _, it in ipairs(snap) do
                if isRottenItem(it) and not isProtected(it) then
                    local placed = false
                    -- 1) try to move it INTO a compost bin that has room
                    for _, cb in ipairs(compostBins) do
                        local fits = false
                        pcall(function() fits = cb.c:hasRoomFor(player, it) end)
                        if fits then
                            local ok = pcall(function()
                                cb.c:addItem(it)
                                st.c:Remove(it)
                            end)
                            if ok then
                                placed = true
                                rottenComposted = rottenComposted + 1
                                touched[st.c] = true; touched[cb.c] = true
                                break
                            end
                        end
                    end
                    -- 2) no compost bin (or all full) -> drop on the floor beside the container
                    if not placed then
                        local dropSq = nil
                        pcall(function() dropSq = st.obj:getSquare() end)
                        if not dropSq then pcall(function() dropSq = player:getCurrentSquare() end) end
                        if dropSq then
                            -- canonical drop-from-container order (see Vehicles.lua): add to world, then Remove.
                            local ok = pcall(function()
                                dropSq:AddWorldInventoryItem(it, 0, 0, 0)
                                st.c:Remove(it)
                            end)
                            if ok then rottenDumped = rottenDumped + 1; touched[st.c] = true end
                        end
                    end
                end
            end
        end
    end

    -- ---- PASS B: file loose loot lying on the FLOOR into its home containers ----
    -- You dump loot on the ground to "sort later" -- this is the later. Skips rotten (so
    -- PASS A's pile isn't re-shelved) and favourited/equipped items. Uses the exact detach
    -- sequence from the game's own ISGrabItemAction so nothing dupes or vanishes.
    local floorSorted, floorLeft = 0, 0
    for _, fi in ipairs(collectFloorItems(player)) do
        local it, wo, sq = fi.item, fi.wo, fi.sq
        if it and not isProtected(it) and not isRottenItem(it)
           and not instanceof(it, "InventoryContainer")
           and not (EmpireSortConfig and EmpireSortConfig.isNeverMove and EmpireSortConfig.isNeverMove(it)) then
            local cat = categoryOf(it)
            homeFor(cat)
            local cands = spillCands(cat)
            local placed = false
            if cands then
                for _, dest in ipairs(cands) do
                    local fits = false
                    pcall(function() fits = dest:isItemAllowed(it) and dest:hasRoomFor(player, it) end)
                    if fits then
                        local ok = pcall(function()
                            sq:transmitRemoveItemFromSquare(wo)
                            wo:removeFromWorld()
                            wo:removeFromSquare()
                            wo:setSquare(nil)
                            it:setWorldItem(nil)
                            it:setJobDelta(0.0)
                            dest:addItem(it)
                        end)
                        if ok then
                            placed = true
                            floorSorted = floorSorted + 1
                            byCat[cat] = (byCat[cat] or 0) + 1
                            touched[dest] = true
                            break
                        end
                    end
                end
            end
            if not placed then floorLeft = floorLeft + 1 end
        end
    end
    moved = moved + floorSorted

    local contN = 0
    for c in pairs(touched) do
        contN = contN + 1
        pcall(function() c:setDrawDirty(true) end)
        -- refresh the WORLD graphic the same way the game does on a manual transfer:
        -- ItemPicker.updateOverlaySprite on the container's parent object. Without this a
        -- shelf/fridge the sort just filled still renders EMPTY, so you can't tell which
        -- containers actually hold anything. setDrawDirty alone does not swap the sprite.
        pcall(function()
            local par = c:getParent()
            if par and ItemPicker and ItemPicker.updateOverlaySprite then
                ItemPicker.updateOverlaySprite(par)
            end
        end)
    end

    local LABELS = {
        Perishable="fridge", Frozen="freezer", DryFood="dry food", Water="water", Drinks="drinks", Alcohol="alcohol",
        Cooking="cooking", Compost="compost",
        Gun="guns", Weapon="melee", Ammo="ammo", GunParts="gun parts",
        Explosives="explosives", Armor="armour", Medical="meds", Tools="tools", VehicleParts="car parts",
        Materials="materials", Chemicals="chemicals", Electronics="electronics", Light="lights",
        Gardening="gardening", Fishing="fishing", Trapping="trapping", Camping="camping",
        Animals="animals", AnimalParts="animal parts", Books="books", SkillBooks="skill books",
        Entertainment="entertainment",
        Clothing="clothing", Accessory="accessories", Bags="bags", Furniture="furniture",
        Household="household", Misc="misc",
    }
    local parts = {}
    for cat, n in pairs(byCat) do parts[#parts+1] = n .. " " .. (LABELS[cat] or cat) end
    local breakdown = table.concat(parts, ", ")

    -- one-shot visibility: shows what F9 actually saw and did, so we never guess again.
    if EMPIRE_SORT_DEBUG then
        local tagged = 0
        for _, st in ipairs(stores) do if st.tag then tagged = tagged + 1 end end
        print(string.format("[EmpireSort DIAG] stores=%d tagged=%d planned=%d moved=%d blocked=%d stuckCold=%d rotten=%d composted=%d floorSorted=%d floorLeft=%d",
            #stores, tagged, #moves, moved, blocked, stuckCold, rottenDumped, rottenComposted, floorSorted, floorLeft))
        for _, st in ipairs(stores) do
            local tg = "-"
            if st.tag then local k = {}; for c in pairs(st.tag) do k[#k+1] = c end; tg = table.concat(k, "+") end
            local n = 0; pcall(function() n = st.c:getItems():size() end)
            local w, mx = -1, -1
            pcall(function() w = st.c:getCapacityWeight() end)
            pcall(function() mx = st.c:getMaxWeight() end)
            print(string.format("[EmpireSort DIAG]   ctype=%s tag=%s items=%d weight=%.1f/%.1f", tostring(st.ctype), tg, n, w, mx))
            -- For a LOCKED/designated container, list items that DON'T belong (foreign), with
            -- their game label + how we classified them. This is how we see WHY (e.g.) an
            -- electrical item is stuck in your Gardening crate: either it's labelled wrong by
            -- its mod (sortedAs=Gardening) or it has no Electronics home to be evicted to.
            if st.designated and st.homeCats then
                local its2 = nil; pcall(function() its2 = st.c:getItems() end)
                local shown = 0
                if its2 then
                    for i = 0, its2:size() - 1 do
                        local it = its2:get(i)
                        local cat = categoryOf(it)
                        if not st.homeCats[cat] and shown < 8 then
                            local nm, dsp = "?", "?"
                            pcall(function() nm = it:getName() end)
                            pcall(function() dsp = it:getDisplayCategory() end)
                            local hasHome = destFor[cat] ~= nil
                            print(string.format("[EmpireSort DIAG]       FOREIGN: %s | label=%s | sortedAs=%s | hasHomeNearby=%s",
                                tostring(nm), tostring(dsp), tostring(cat), tostring(hasHome)))
                            shown = shown + 1
                        end
                    end
                end
            end
        end
    end

    if rottenComposted > 0 then
        HaloTextHelper.addTextWithArrow(player, "Composted " .. rottenComposted .. " ROTTEN food", "[br/]", false, HaloTextHelper.getColorGreen())
    end
    if rottenDumped > 0 then
        HaloTextHelper.addTextWithArrow(player, "Dumped " .. rottenDumped .. " ROTTEN food to floor", "[br/]", false, HaloTextHelper.getColorRed())
    end
    if floorLeft > 0 then
        HaloTextHelper.addTextWithArrow(player, floorLeft .. " floor items have no shelf yet", "[br/]", false, HaloTextHelper.getColorWhite())
    end

    if moved > 0 then
        HaloTextHelper.addTextWithArrow(player, "SORTED " .. moved .. " items -> " .. contN .. " containers", "[br/]", false, HaloTextHelper.getColorGreen())
        if breakdown ~= "" then player:Say("Sorted: " .. breakdown .. ".")
        else player:Say("Sorted " .. moved .. " items.") end
        if blocked > 0 then
            HaloTextHelper.addTextWithArrow(player, blocked .. " couldn't fit - tagged container FULL", "[br/]", false, HaloTextHelper.getColorRed())
        end
        if stuckCold > 0 then
            HaloTextHelper.addTextWithArrow(player, stuckCold .. " non-food stuck in cold - needs a shelf", "[br/]", false, HaloTextHelper.getColorRed())
        end
    elseif blocked > 0 then
        HaloTextHelper.addTextWithArrow(player, "Tagged storage FULL - " .. blocked .. " items can't fit", "[br/]", false, HaloTextHelper.getColorRed())
        player:Say("Your tagged container's full -- " .. blocked .. " items won't fit. Tag a bigger or 2nd container and F9.")
    elseif stuckCold > 0 then
        HaloTextHelper.addTextWithArrow(player, stuckCold .. " non-food stuck in fridge/freezer - tag a shelf for it", "[br/]", false, HaloTextHelper.getColorRed())
        player:Say("Non-food's stuck in the cold with no shelf to take it. Tag a crate and F9 again.")
    elseif rottenDumped > 0 then
        player:Say("Cleared " .. rottenDumped .. " rotten item(s) out to the floor.")
    else
        HaloTextHelper.addTextWithArrow(player, "Nothing to move - already sorted", "[br/]", false, HaloTextHelper.getColorWhite())
        player:Say("Storage's already in order.")
    end
end

-- ============================================================
-- CONSOLIDATE DUPLICATES  (F10 / right-click inventory -> "Consolidate Duplicates")
-- Deliberate, separate pass from F9 Smart Sort. Smart Sort respects how you've
-- arranged general shelves; this one INTENTIONALLY overrides that for ONE purpose:
-- gather every instance of the SAME item type into a single container, so you stop
-- finding the same welding rod spread across five shelves. For each item type it
-- finds the eligible container ALREADY holding the most of that type (the natural
-- pile) and pulls the rest toward it, spilling to the next-biggest pile only if the
-- first fills. Respects cold storage (food only), your tagged locks, favourites/equipped.
-- ============================================================
local CONSOLIDATE_MIN_TOTAL = 2   -- ignore types you only own one of -- nothing to merge

local function consolidateTypes(player)
    if not player then player = getSpecificPlayer(0) end
    if not player then return end

    _catCache = {}
    local stores = collectStorages(player)
    if #stores == 0 then
        HaloTextHelper.addTextWithArrow(player, "No storage nearby to consolidate", "[br/]", false, HaloTextHelper.getColorRed())
        player:Say("No storage close enough.")
        return
    end

    -- Same home-rules as Smart Sort so consolidation never fights your locks:
    --   cold = food only, tagged = its categories only, affinity furniture = its category.
    for _, st in ipairs(stores) do
        st.cold = false
        if st.tag then
            st.designated, st.homeCats = true, st.tag
        elseif isFreezer(st.ctype) then
            st.designated, st.homeCats, st.cold, st.freezer = true, { Frozen = true }, true, true
        elseif isFridge(st.ctype) then
            st.designated, st.homeCats, st.cold = true, { Perishable = true }, true
        else
            local aff = affinityOf(st.ctype)
            if aff then st.designated, st.homeCats = true, { [aff] = true }
            else st.designated = false end
        end
    end

    -- A container may RECEIVE an item of category `cat` only if it's allowed to hold it.
    -- Cold mirrors Smart Sort exactly (freezer=Frozen, fridge=Perishable) so consolidate
    -- never pulls a frozen item out of the freezer that Smart Sort would just put back.
    local function eligible(st, cat)
        if st.cold then
            if st.freezer then return cat == "Frozen" end
            return cat == "Perishable"
        end
        if st.tag then return st.tag[cat] == true end
        if st.designated then return st.homeCats and st.homeCats[cat] == true end
        return true   -- plain general shelf: takes anything
    end

    local function fullTypeOf(it)
        local ft = nil
        pcall(function() ft = it:getFullType() end)
        if not ft or ft == "" then pcall(function() ft = it:getType() end) end
        return ft
    end

    -- Tally: for each item type, how many sit in each store + its category + grand total.
    local typeData = {}        -- ft -> { cat=, total=, perCont = { [st] = n } }
    for _, st in ipairs(stores) do
        local items = st.c:getItems()
        for i = 0, items:size() - 1 do
            local it = items:get(i)
            if not isProtected(it) then
                local ft = fullTypeOf(it)
                if ft then
                    local d = typeData[ft]
                    if not d then d = { cat = categoryOf(it), total = 0, perCont = {} }; typeData[ft] = d end
                    d.perCont[st] = (d.perCont[st] or 0) + 1
                    d.total = d.total + 1
                end
            end
        end
    end

    -- Pick each type's ANCHOR = the eligible container already holding the most of it.
    -- (Fall back to any eligible store if every current holder is ineligible -- e.g. a
    -- non-food item currently trapped only in a fridge.)
    for ft, d in pairs(typeData) do
        local best, bestN = nil, -1
        for st, n in pairs(d.perCont) do
            if eligible(st, d.cat) and n > bestN then best, bestN = st, n end
        end
        if not best then
            for _, st in ipairs(stores) do
                if eligible(st, d.cat) then best = st; break end
            end
        end
        d.anchor = best
    end

    -- move helper: first store in `cands` with room takes it (never back into `fromC`).
    local moved, touched, typesDone, noRoom = 0, {}, {}, 0
    local function placeInto(it, fromC, cands)
        for _, st in ipairs(cands) do
            local dest = st.c
            if dest ~= fromC then
                local fits = false
                pcall(function() fits = dest:isItemAllowed(it) and dest:hasRoomFor(player, it) end)
                if fits then
                    local ok = pcall(function() dest:addItem(it); fromC:Remove(it) end)
                    if ok then touched[dest] = true; touched[fromC] = true; return true end
                end
            end
        end
        return false
    end

    for ft, d in pairs(typeData) do
        if d.anchor and d.total >= CONSOLIDATE_MIN_TOTAL then
            -- spill order: anchor first, then the other eligible holders biggest-pile-first
            local holders = {}
            for st, n in pairs(d.perCont) do
                if st ~= d.anchor and eligible(st, d.cat) then holders[#holders+1] = { st = st, n = n } end
            end
            table.sort(holders, function(a, b) return a.n > b.n end)
            local cands = { d.anchor }
            for _, h in ipairs(holders) do cands[#cands+1] = h.st end

            -- pull every instance that ISN'T already in the anchor toward it
            local didType = false
            for st in pairs(d.perCont) do
                if st ~= d.anchor then
                    local items = st.c:getItems()
                    local snap = {}
                    for i = 0, items:size() - 1 do
                        local it = items:get(i)
                        if fullTypeOf(it) == ft and not isProtected(it) then snap[#snap+1] = it end
                    end
                    for _, it in ipairs(snap) do
                        if placeInto(it, st.c, cands) then moved = moved + 1; didType = true
                        else noRoom = noRoom + 1 end
                    end
                end
            end
            if didType then typesDone[ft] = true end
        end
    end

    local contN = 0
    for c in pairs(touched) do
        contN = contN + 1
        pcall(function() c:setDrawDirty(true) end)
        -- refresh the WORLD graphic the same way the game does on a manual transfer:
        -- ItemPicker.updateOverlaySprite on the container's parent object. Without this a
        -- shelf/fridge the sort just filled still renders EMPTY, so you can't tell which
        -- containers actually hold anything. setDrawDirty alone does not swap the sprite.
        pcall(function()
            local par = c:getParent()
            if par and ItemPicker and ItemPicker.updateOverlaySprite then
                ItemPicker.updateOverlaySprite(par)
            end
        end)
    end
    local typeN = 0; for _ in pairs(typesDone) do typeN = typeN + 1 end

    if EMPIRE_SORT_DEBUG then
        local seen = 0; for _ in pairs(typeData) do seen = seen + 1 end
        print(string.format("[EmpireConsolidate DIAG] stores=%d types=%d consolidated=%d itemsMoved=%d noRoom=%d containersTouched=%d",
            #stores, seen, typeN, moved, noRoom, contN))
    end

    if moved > 0 then
        HaloTextHelper.addTextWithArrow(player, "CONSOLIDATED " .. typeN .. " item types (" .. moved .. " moved)", "[br/]", false, HaloTextHelper.getColorGreen())
        player:Say("Merged " .. moved .. " duplicates into " .. typeN .. " home piles.")
        if noRoom > 0 then
            HaloTextHelper.addTextWithArrow(player, noRoom .. " couldn't fit - home pile FULL", "[br/]", false, HaloTextHelper.getColorRed())
        end
    elseif noRoom > 0 then
        HaloTextHelper.addTextWithArrow(player, "Home piles FULL - " .. noRoom .. " items couldn't merge", "[br/]", false, HaloTextHelper.getColorRed())
        player:Say("No room to merge -- the target shelves are full.")
    else
        HaloTextHelper.addTextWithArrow(player, "Already consolidated - nothing to merge", "[br/]", false, HaloTextHelper.getColorWhite())
        player:Say("Every item type's already in one place.")
    end
end

-- ============================================================
-- Tagging: right-click a storage in the world -> "Empire Storage"
-- ============================================================
-- Each leaf is a single category key. The menu TOGGLES it on/off for the container, so
-- one box can hold several categories at once (multi-select).
local TAG_GROUPS = {
    { "Food & drink", { "Perishable", "Frozen", "DryFood", "Cooking", "Water", "Drinks", "Alcohol", "Compost" } },
    { "Weapons", { "Gun", "Weapon", "Ammo", "GunParts", "Explosives", "Armor" } },
    { "Survival", { "Medical", "Tools", "Materials", "Chemicals", "Electronics", "Light", "VehicleParts" } },
    { "Outdoors", { "Gardening", "Fishing", "Trapping", "Camping", "Animals", "AnimalParts" } },
    { "Goods", { "Clothing", "Accessory", "Bags", "Books", "SkillBooks", "Entertainment", "Household", "Furniture", "Misc" } },
}

local function onClearTag(playerNum, obj)
    writeTag(obj, nil)
    local p = getSpecificPlayer(playerNum)
    if p then pcall(function() HaloTextHelper.addTextWithArrow(p, "Lock cleared", "[br/]", false, HaloTextHelper.getColorRed()) end) end
end

local PRETTY = {
    Perishable="Fresh food", Frozen="Freezer", DryFood="Dry food", Water="Water", Drinks="Soft drinks",
    Alcohol="Alcohol", Cooking="Cooking", Compost="Compost bin",
    Gun="Guns", Weapon="Melee", Ammo="Ammo", GunParts="Gun parts", Explosives="Explosives",
    Armor="Armour",
    Medical="Medical", Tools="Tools", VehicleParts="Car parts", Materials="Materials",
    Chemicals="Chemicals", Electronics="Electronics", Light="Lights", Gardening="Gardening",
    Fishing="Fishing", Trapping="Trapping", Camping="Camping", Animals="Animals", AnimalParts="Animal parts",
    Books="Books", SkillBooks="Skill books",
    Entertainment="Entertainment", Clothing="Clothing", Accessory="Accessories", Bags="Bags",
    Furniture="Furniture", Household="Household", Misc="Misc",
}
local function prettyTags(set)
    local names = {}
    for cat in pairs(set) do names[#names+1] = PRETTY[cat] or cat end
    table.sort(names)
    return table.concat(names, ", ")
end

-- MULTI-SELECT: toggle ONE category on/off for this container, keeping the rest. A box
-- with several categories takes items for ALL of them.
local function onToggleTag(playerNum, obj, cat)
    local set = readTagSet(obj) or {}
    if set[cat] then set[cat] = nil else set[cat] = true end
    local parts = {}
    for c in pairs(set) do parts[#parts+1] = c end
    table.sort(parts)
    writeTag(obj, table.concat(parts, ","))
    local p = getSpecificPlayer(playerNum)
    if not p then return end
    pcall(function()
        if next(set) == nil then
            HaloTextHelper.addTextWithArrow(p, "Lock cleared", "[br/]", false, HaloTextHelper.getColorRed())
            p:Say("Unlocked -- takes anything now.")
        else
            local added = set[cat] ~= nil
            local col = added and HaloTextHelper.getColorGreen() or HaloTextHelper.getColorRed()
            local verb = added and "+ " or "- "
            HaloTextHelper.addTextWithArrow(p, verb .. (PRETTY[cat] or cat) .. "   now: " .. prettyTags(set), "[br/]", false, col)
            p:Say("This one holds: " .. prettyTags(set) .. ".")
        end
    end)
end

-- right-click your vehicle while base storage is in range -> one-click transfer its loot
-- into the base, sorted. Only the vehicle you're at is touched -- never a global sweep.
local function onTransferVehicleToBase(player, veh)
    if not player or not veh then return end
    pcall(function() smartSort(player, { vehicle = veh }) end)
    pcall(function() consolidateTypes(player) end)
    if EmpireBaseCache and EmpireBaseCache.invalidate then EmpireBaseCache.invalidate() end
end

local function onFillWorldObjectContextMenu(playerNum, context, worldobjects, test)
    if test then return end

    -- VEHICLE: offer "Transfer loot to base" only when you're AT a vehicle AND base storage
    -- is in range. getVehicleToInteractWith = the vehicle you're in or the useable one beside
    -- you (the same one PZ would interact with) -- so it targets exactly that one vehicle.
    do
        local player = getSpecificPlayer(playerNum)
        if player and ISVehicleMenu and ISVehicleMenu.getVehicleToInteractWith then
            local veh = nil
            pcall(function() veh = ISVehicleMenu.getVehicleToInteractWith(player) end)
            if veh and #vehicleStorageContainers(veh) > 0 then
                local hasBase = false
                pcall(function() hasBase = (#collectStorages(player) > 0) end)
                if hasBase then
                    context:addOption("Empire: Transfer loot to base", player, onTransferVehicleToBase, veh)
                end
            end
        end
    end

    local owner, ownerC = nil, nil
    for _, o in ipairs(worldobjects) do
        local c = nil
        pcall(function() c = o:getContainer() end)
        if c then owner = o; ownerC = c; break end
    end
    if not owner then return end

    -- canonical tag holder = the container's parent: the SAME object the sorter reads,
    -- so a lock set here is always seen by F9 (incl. vehicles / RV interiors).
    local holder = owner
    pcall(function() local pa = ownerC:getParent(); if pa then holder = pa end end)

    local current = readTagSet(ownerC)
    local label = current and ("Empire Storage (" .. prettyTags(current) .. ")") or "Empire Storage"

    local main = context:addOption(label, nil, nil)
    local root = ISContextMenu:getNew(context)
    context:addSubMenu(main, root)

    -- always-visible status line so you can SEE what a container is locked to
    local statusTxt = current and ("Currently: " .. prettyTags(current)) or "Currently: not locked"
    local statusOpt = root:addOption(statusTxt, nil, nil)
    statusOpt.notAvailable = true

    for _, group in ipairs(TAG_GROUPS) do
        local gopt = root:addOption(group[1], nil, nil)
        local gsub = ISContextMenu:getNew(root)
        root:addSubMenu(gopt, gsub)
        for _, cat in ipairs(group[2]) do
            local on = current and current[cat]
            local mark = on and "[x] " or "[ ] "
            gsub:addOption(mark .. (PRETTY[cat] or cat), playerNum, onToggleTag, ownerC, cat)
        end
    end
    if current then root:addOption("-- Clear all --", playerNum, onClearTag, ownerC) end
end
Events.OnFillWorldObjectContextMenu.Add(function(playerNum, context, worldobjects, test)
    local __t0 = getTimestampMs()
    onFillWorldObjectContextMenu(playerNum, context, worldobjects, test)
    local __dt = getTimestampMs() - __t0
    if EMPIRE_DEBUG_ON ~= false and __dt >= 1 then print("[EMPIRE-DEBUG]   H EmpireSortAll: " .. __dt .. "ms") end
end)

-- ---- right-click inventory option ----
local function onToggleKeepBag(playerObj, bagItem)
    local md = bagItem:getModData()
    md.empireKeepBag = not (md.empireKeepBag == true)
    pcall(function()
        local on = md.empireKeepBag == true
        local msg = on and "Keep bag ON -- contents won't be sorted" or "Keep bag OFF -- contents will sort again"
        local col = on and HaloTextHelper.getColorGreen() or HaloTextHelper.getColorRed()
        HaloTextHelper.addTextWithArrow(playerObj, msg, "[br/]", false, col)
    end)
end

local function onFillInventoryObjectContextMenu(player, context, items)
    local playerObj = player
    if type(player) == "number" then playerObj = getSpecificPlayer(player) end
    if not playerObj then return end
    -- (Smart Sort / Consolidate removed from the item right-click menu to keep it clean --
    --  use the Numpad3 / Numpad4 keys for those.)
    -- if a bag is right-clicked, offer a one-click "keep this bag" toggle (loadout bag)
    local it = items and items[1]
    if it and type(it) == "table" and it.items then it = it.items[1] end
    if it and instanceof(it, "InventoryContainer") then
        local kept = false
        pcall(function() local md = it:getModData(); kept = md and md.empireKeepBag == true end)
        local label = kept and "Empire: Stop keeping this bag" or "Empire: Keep this bag (don't sort its contents)"
        context:addOption(label, playerObj, onToggleKeepBag, it)
    end
end
Events.OnFillInventoryObjectContextMenu.Add(onFillInventoryObjectContextMenu)

-- ---- F9 = Smart Sort, End = Consolidate Duplicates ----
-- (Consolidate is on END, not F10: F10 is already taken by EmpireNPC's dashboard and
--  99_Debug's logging toggle. END is unused, so no double-fire.)
local function onKeyPressed(key)
    local player = getSpecificPlayer(0)
    if not player or player:isDead() then return end
    if key == Keyboard.KEY_NUMPAD3 then
        pcall(smartSort, player)        -- 1) file everything into its category home
        pcall(consolidateTypes, player) -- 2) then stack identical items into ONE pile
    elseif key == Keyboard.KEY_NUMPAD4 then
        pcall(consolidateTypes, player)
    else
        return
    end
    -- items just moved -> the base material cache is stale; rebuild on next read.
    if EmpireBaseCache and EmpireBaseCache.invalidate then EmpireBaseCache.invalidate() end
end
Events.OnKeyPressed.Add(onKeyPressed)

print("[EmpireSortAll] Smart Sort v11 loaded. Numpad3 = sort base + consolidate; Numpad4 = consolidate. Right-click a vehicle near base -> 'Transfer loot to base'. Right-click storage -> Empire Storage to lock.")
