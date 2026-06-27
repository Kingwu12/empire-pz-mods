-- Empire Sort All
-- Shared category map: item DisplayCategory -> container type keywords to target
EmpireSortAll = EmpireSortAll or {}

EmpireSortAll.CategoryMap = {
    -- Food & drink -> fridge/freezer
    ["Food"]        = { "fridge", "freezer", "frig", "food", "kitchen" },
    ["Drink"]       = { "fridge", "freezer", "frig", "food", "kitchen" },
    ["Farming"]     = { "seed", "farming", "garden", "storage", "shelf" },

    -- Weapons & ammo -> gun cabinet / locker / weapon
    ["Weapon"]      = { "gun", "weapon", "locker", "arms", "armory", "cabinet" },
    ["Ammo"]        = { "gun", "ammo", "weapon", "locker", "cabinet", "armory" },
    ["WeaponPart"]  = { "gun", "weapon", "locker", "cabinet", "armory" },

    -- Medical -> first aid cabinet
    ["Medical"]     = { "medical", "firstaid", "first aid", "med", "health", "aid" },

    -- Literature / books -> bookshelf
    ["Literature"]  = { "book", "shelf", "bookshelf", "literature", "library" },

    -- Tools & materials -> shelves / toolbox
    ["Tool"]        = { "tool", "shelf", "storage", "workbench", "bench", "supply" },
    ["Material"]    = { "shelf", "storage", "material", "supply", "resource" },
    ["Carpentry"]   = { "shelf", "storage", "material", "tool" },

    -- Clothing & gear -> locker / wardrobe
    ["Clothing"]    = { "locker", "wardrobe", "cloth", "gear", "wear", "apparel" },
    ["Bag"]         = { "locker", "wardrobe", "storage", "shelf" },

    -- Electronics / misc -> general shelf
    ["Electronics"] = { "shelf", "storage", "supply", "general" },
    ["Junk"]        = { "shelf", "storage", "general", "misc" },
    ["Item"]        = { "shelf", "storage", "general", "misc" },
}

-- Fallback: if nothing matches, try any shelf/storage/crate
EmpireSortAll.FallbackKeywords = { "shelf", "storage", "crate", "general", "misc" }
