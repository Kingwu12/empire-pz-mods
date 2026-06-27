-- ============================================================
-- Empire Production : accrual engine (shared)
-- A "node" is any container the player designates with a recipe. It does NOT
-- tick. State (recipe + lastHour) lives in the object's ModData (persists with
-- the save). Production is computed only when touched (right-click / collect):
--   units = min( elapsedHours * ratePerHour , inputSetsAvailable , bufferRoom )
-- So a node is O(1) on access and free the rest of the time. Inputs and outputs
-- both live in the node's own container. Recipes are pure data -> add anything.
-- ============================================================

EmpireProd = EmpireProd or {}
local EP = EmpireProd
EP.recipes = EP.recipes or {}

-- recipe: name, ratePerHour (output units/hr), bufferCap (max output held),
--         inputs = { {type, n}, ... } consumed per unit, output = item full type
EP.recipes["reload_9mm"] = {
    name        = "Reload 9mm",
    ratePerHour = 30,
    bufferCap   = 600,
    inputs      = { { type = "Base.GunPowder", n = 1 }, { type = "Base.Lead", n = 1 }, { type = "Base.BrassScrap", n = 1 } },
    output      = "Base.Bullets9mm",
}

function EP.nowHours()
    local gt = getGameTime()
    return (gt and gt:getWorldAgeHours()) or 0
end

local function countType(container, ftype)
    local n, items = 0, container:getItems()
    for i = 0, items:size() - 1 do
        if items:get(i):getFullType() == ftype then n = n + 1 end
    end
    return n
end

local function inputSets(container, recipe)
    local sets = nil
    for _, inp in ipairs(recipe.inputs) do
        local possible = math.floor(countType(container, inp.type) / math.max(1, inp.n))
        if sets == nil or possible < sets then sets = possible end
    end
    return sets or 0
end

local function removeN(container, ftype, n)
    local found = {}
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if it:getFullType() == ftype then
            found[#found + 1] = it
            if #found >= n then break end
        end
    end
    for _, it in ipairs(found) do pcall(function() container:Remove(it) end) end
end

-- Resolve accrued production. Returns madeUnits (for status text). Safe to call
-- any time; advances the node clock only by time actually converted.
function EP.resolve(obj)
    if not obj or not obj.getModData then return 0 end
    local md = obj:getModData()
    local node = md and md.EmpireProd
    if not node or not node.recipe then return 0 end
    local recipe = EP.recipes[node.recipe]
    local container = obj.getContainer and obj:getContainer() or nil
    if not recipe or not container then return 0 end

    local now = EP.nowHours()
    node.lastHour = node.lastHour or now
    local elapsed = now - node.lastHour
    if elapsed <= 0 then return 0 end

    local byTime   = math.floor(elapsed * recipe.ratePerHour)
    local bySets   = inputSets(container, recipe)
    local room     = recipe.bufferCap - countType(container, recipe.output)
    local units    = math.min(byTime, bySets, math.max(0, room))
    if units < 0 then units = 0 end

    if units > 0 then
        for _, inp in ipairs(recipe.inputs) do removeN(container, inp.type, inp.n * units) end
        for _ = 1, units do pcall(function() container:AddItem(recipe.output) end) end
    end

    if units >= byTime then
        node.lastHour = node.lastHour + units / recipe.ratePerHour   -- time-limited: bank only used time
    else
        node.lastHour = now                                          -- input/buffer stalled: don't bank idle
    end
    pcall(function() obj:transmitModData() end)
    return units
end

-- one-line status for the context menu
function EP.status(obj)
    local md = obj:getModData()
    local node = md and md.EmpireProd
    if not node or not node.recipe then return nil end
    local recipe = EP.recipes[node.recipe]
    if not recipe then return nil end
    local container = obj:getContainer()
    local have = container and countType(container, recipe.output) or 0
    local sets = container and inputSets(container, recipe) or 0
    return string.format("%s: %d made, %dh of inputs left", recipe.name, have, math.floor(sets / math.max(1, recipe.ratePerHour)))
end
