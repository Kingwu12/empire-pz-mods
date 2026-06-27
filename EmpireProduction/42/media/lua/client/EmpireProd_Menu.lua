-- ============================================================
-- Empire Production : interaction (client)
-- Right-click a container in the world:
--   not a node yet -> "Set up production > [recipe (inputs -> output)]"
--   already a node -> status line (info) + "Collect now" + "Stop production"
-- Resolve runs on access (cheap), so you can leave and come back and the output
-- is waiting. No per-tick work.
-- ============================================================

local EP = EmpireProd

local function playerOf(player)
    if type(player) == "number" then return getSpecificPlayer(player) end
    return player
end

local function findContainerObj(worldobjects)
    for _, o in ipairs(worldobjects) do
        local c = nil
        pcall(function() c = o:getContainer() end)
        if c then return o end
    end
    return nil
end

local function halo(playerObj, text, good)
    local col = good and HaloTextHelper.getColorGreen() or HaloTextHelper.getColorWhite()
    pcall(function() HaloTextHelper.addTextWithArrow(playerObj, text, "[br/]", false, col) end)
end

-- recipes sorted by display name, stable across sessions
local function sortedRecipes()
    local list = {}
    for id, r in pairs(EP.recipes) do list[#list + 1] = { id = id, r = r } end
    table.sort(list, function(a, b) return (a.r.name or a.id) < (b.r.name or b.id) end)
    return list
end

local function setupNode(playerObj, obj, recipeId)
    local md = obj:getModData()
    md.EmpireProd = { recipe = recipeId, lastHour = EP.nowHours() }
    pcall(function() obj:transmitModData() end)
    local r = EP.recipes[recipeId]
    halo(playerObj, "Production set: " .. (r and r.name or recipeId), true)
end

local function collect(playerObj, obj)
    local made = EP.resolve(obj)
    halo(playerObj, "+" .. tostring(made) .. " produced. " .. (EP.status(obj) or ""), true)
end

local function stopNode(playerObj, obj)
    pcall(function() EP.resolve(obj) end)   -- settle pending before stopping
    local md = obj:getModData()
    md.EmpireProd = nil
    pcall(function() obj:transmitModData() end)
    halo(playerObj, "Production stopped.", false)
end

local function onFill(player, context, worldobjects)
    local playerObj = playerOf(player)
    if not playerObj or playerObj:isDead() then return end
    local obj = findContainerObj(worldobjects)
    if not obj then return end

    local md = obj:getModData()
    local node = md and md.EmpireProd

    if node and node.recipe then
        pcall(function() EP.resolve(obj) end)   -- settle so status is current
        local opt = context:addOption("Empire Production", nil, nil)
        local sub = ISContextMenu:getNew(context)
        context:addSubMenu(opt, sub)
        -- status as a non-clickable info line
        local info = sub:addOption(EP.status(obj) or "Status", nil, nil)
        info.notAvailable = true
        sub:addOption("Collect now", playerObj, function() collect(playerObj, obj) end)
        sub:addOption("Stop production", playerObj, function() stopNode(playerObj, obj) end)
    else
        local opt = context:addOption("Set up production", nil, nil)
        local sub = ISContextMenu:getNew(context)
        context:addSubMenu(opt, sub)
        for _, e in ipairs(sortedRecipes()) do
            local label = e.r.name .. "  (" .. EP.describe(e.r) .. ")"
            sub:addOption(label, playerObj, function() setupNode(playerObj, obj, e.id) end)
        end
    end
end

Events.OnFillWorldObjectContextMenu.Add(onFill)

print("[EmpireProduction] loaded. Right-click a container -> Set up production.")
