-- Empire NPC - Shared Data
-- Role definitions, settler registry, guard posts, persistent data

EmpireNPC = EmpireNPC or {}

-- Role definitions
EmpireNPC.Roles = {
    GUARD   = "Guard",
    MEDIC   = "Medic",
    FARMER  = "Farmer",
    WARDEN  = "Warden",
    LOOTER  = "Looter",
    COOK    = "Cook",
    NONE    = "Settler",
}

EmpireNPC.RoleIcons = {
    Guard   = "🛡",
    Medic   = "🩺",
    Farmer  = "🌾",
    Warden  = "📦",
    Looter  = "🎒",
    Settler = "👤",
}

EmpireNPC.RoleDescriptions = {
    Guard   = "Holds assigned guard post. Defends base when threats detected.",
    Medic   = "Heals nearby settlers and the player automatically.",
    Farmer  = "Tends crops near base. Waters and harvests automatically.",
    Warden  = "Manages base storage. Sorts containers periodically.",
    Looter  = "Can be sent on supply runs to nearby buildings.",
    Settler = "No assigned role. Follow orders manually.",
}

-- Settler registry: key = survivor name, value = { role, guardPost, health, lastSeen }
EmpireNPC.settlers = {}

-- Guard posts: list of { x, y, z, assignedNPC }
EmpireNPC.guardPosts = {}

-- Empire stats
EmpireNPC.stats = {
    totalFood = 0,
    totalAmmo = 0,
    totalMeds = 0,
    totalFuel = 0,
    threatLevel = 0,
    lastUpdate = 0,
}

-- Save/load settler data to mod data
EmpireNPC.MODDATA_KEY = "EmpireNPC_Data"

EmpireNPC.saveData = function()
    local player = getSpecificPlayer(0)
    if not player then return end
    local md = player:getModData()
    local saveTable = {
        settlers = EmpireNPC.settlers,
        guardPosts = EmpireNPC.guardPosts,
    }
    md[EmpireNPC.MODDATA_KEY] = saveTable
end

EmpireNPC.loadData = function()
    local player = getSpecificPlayer(0)
    if not player then return end
    local md = player:getModData()
    local saved = md[EmpireNPC.MODDATA_KEY]
    if saved then
        EmpireNPC.settlers = saved.settlers or {}
        EmpireNPC.guardPosts = saved.guardPosts or {}
        print("[EmpireNPC] Loaded " .. #EmpireNPC.guardPosts .. " guard posts, " ..
            tostring(#EmpireNPC.settlers) .. " settler records.")
    end
end

EmpireNPC.getSettler = function(npcName)
    if not EmpireNPC.settlers[npcName] then
        EmpireNPC.settlers[npcName] = {
            role = EmpireNPC.Roles.NONE,
            guardPost = nil,
            status = "Active",
        }
    end
    return EmpireNPC.settlers[npcName]
end

EmpireNPC.setRole = function(npcName, role)
    local s = EmpireNPC.getSettler(npcName)
    s.role = role
    EmpireNPC.saveData()
    print("[EmpireNPC] " .. npcName .. " assigned role: " .. role)
end

EmpireNPC.addGuardPost = function(x, y, z)
    table.insert(EmpireNPC.guardPosts, { x=x, y=y, z=z, assigned=nil })
    EmpireNPC.saveData()
    return #EmpireNPC.guardPosts
end

print("[EmpireNPC] Shared data loaded.")
