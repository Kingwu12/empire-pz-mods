-- ============================================================
-- Empire Production : accrual engine (shared)
-- A "node" is any container the player designates with a recipe. It does NOT
-- tick. State (recipe + lastHour) lives in the object's ModData (persists with
-- the save). Production is computed only when touched (right-click / collect):
--   cycles = min( elapsedHours * ratePerHour , inputSetsAvailable , bufferRoom )
-- Each cycle consumes inputs.n of each input and yields outputN output items.
-- O(1) on access, free the rest of the time. Inputs and outputs both live in
-- the node's own container. Recipes are pure data -> add anything.
-- ============================================================

EmpireProd = EmpireProd or {}
local EP = EmpireProd
EP.recipes = EP.recipes or {}

-- recipe fields:
--   name        display name
--   hint        one-line "inputs -> output" shown in the setup menu
--   ratePerHour production cycles per in-game hour
--   outputN     output items produced per cycle (default 1)
--   bufferCap   max output items held before it stalls
--   inputs      { {type, n}, ... } consumed per cycle
--   output      item full type produced
EP.recipes["asm_9mm"] = {
    name = "Assemble 9mm Rounds", hint = "Powder + Lead + Brass -> 9mm",
    ratePerHour = 30, outputN = 1, bufferCap = 600,
    inputs = { { type = "Base.GunPowder", n = 1 }, { type = "Base.Lead", n = 1 }, { type = "Base.BrassScrap", n = 1 } },
    output = "Base.Bullets9mm",
}
EP.recipes["charcoal"] = {
    name = "Burn Charcoal", hint = "Logs -> Charcoal",
    ratePerHour = 3, outputN = 2, bufferCap = 200,
    inputs = { { type = "Base.Log", n = 1 } },
    output = "Base.Charcoal",
}
EP.recipes["planks"] = {
    name = "Saw Planks", hint = "Logs -> Planks",
    ratePerHour = 2, outputN = 3, bufferCap = 200,
    inputs = { { type = "Base.Log", n = 1 } },
    output = "Base.Plank",
}

function EP.nowHours()
    local gt = getGameTime()
    return (gt and gt:getWorldAgeHours()) or 0
end

function EP.describe(recipe)
    return recipe.hint or recipe.name
end

local function countType(container, ftype)
    local n, items = 0, container:getItems()
    for i = 0, items:size() - 1 do
        if items:get(i):getFullType() == ftype then n = n + 1 end
    end
    return n
end

-- how many full cycles the inputs on hand can support
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

-- Resolve accrued production. Returns produced output-item count (for status).
-- Safe to call any time; advances the node clock only by time actually used.
function EP.resolve(obj)
    if not obj or not obj.getModData then return 0 end
    local md = obj:getModData()
    local node = md and md.EmpireProd
    if not node or not node.recipe then return 0 end
    local recipe = EP.recipes[node.recipe]
    local container = obj.getContainer and obj:getContainer() or nil
    if not recipe or not container then return 0 end

    local outN = recipe.outputN or 1
    local now = EP.nowHours()
    node.lastHour = node.lastHour or now
    local elapsed = now - node.lastHour
    if elapsed <= 0 then return 0 end

    local byTime = math.floor(elapsed * recipe.ratePerHour)         -- cycles by clock
    local bySets = inputSets(container, recipe)                     -- cycles by inputs
    local room   = math.floor((recipe.bufferCap - countType(container, recipe.output)) / outN) -- cycles that fit
    local cycles = math.min(byTime, bySets, math.max(0, room))
    if cycles < 0 then cycles = 0 end

    if cycles > 0 then
        for _, inp in ipairs(recipe.inputs) do removeN(container, inp.type, inp.n * cycles) end
        for _ = 1, cycles * outN do pcall(function() container:AddItem(recipe.output) end) end
    end

    if cycles >= byTime then
        node.lastHour = node.lastHour + cycles / recipe.ratePerHour -- time-limited: bank only used time
    else
        node.lastHour = now                                         -- input/buffer stalled: don't bank idle
    end
    pcall(function() obj:transmitModData() end)
    return cycles * outN
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
    local hoursLeft = math.floor(sets / math.max(1, recipe.ratePerHour))
    return string.format("%s: %d made, ~%dh inputs left", recipe.name, have, hoursLeft)
end
