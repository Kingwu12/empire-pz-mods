-- Empire QoL :: 16_AutoProduction.lua  (27 Nov 2026, B42.22)
-- King: "i love empire building but dont like the sorting and small things".
-- PRODUCTION NODES THAT FEED AND COLLECT THEMSELVES. An EmpireProduction node (right-click a container ->
-- Set up production) turns inputs into output on its own clock, but you had to carry inputs to it and carry
-- the output away. This is the crew doing that, on the 10-minute beat, while you are inside the base:
--   FEED     top the node's inputs up from base storage to ~FEED_HOURS of production (real items moved
--            from the shelves into the node's container, never spawned), at most MAX_MOVE items per node
--            per beat, never more than the node's container has room for;
--   COLLECT  when the node holds COLLECT_MIN or more of its output, the sorter files that output into the
--            right base containers (EmpireSortAll.run with sources = the node), exactly as if you had
--            carried it to the shelves and sorted.
-- Switch one node off in its right-click menu ("Auto-feed"), or all with Numpad 5.
--
-- PERFORMANCE: no tile scan, no per-frame handler. It walks the persisted node registry
-- (EmpireProd.registry(), one "x,y,z" key per node, written when you set a node up) at most NODES_PER_BEAT
-- nodes per beat, round robin. A key whose square is not loaded is skipped; a loaded square with no node is
-- dropped. EmpireProd.resolve (O(items in the node)) settles the accrued production before anything moves.
-- The base index (EmpireBaseCache) is the source of inputs; node containers are excluded from it and from
-- the sorter (EmpireSortConfig.isExcludedContainer), so the sorter never pulls a node's inputs back out.

local CFG = {
    ENABLED         = true,
    FEED_HOURS      = 6,    -- keep this many game hours of inputs inside the node
    MAX_MOVE        = 40,   -- items moved into one node per beat (split evenly across its inputs)
    NODES_PER_BEAT  = 3,    -- registry entries looked at per beat (round robin)
    COLLECT_MIN     = 20,   -- file the output once the node holds this many (or half its buffer, if smaller)
    COLLECT_MAX_BEATS = 12, -- ... or after this many beats with any output waiting
}

local AC = EmpireAutoChores
local m = AC.m

local state = { cursor = 0, waiting = {}, lastMoved = 0, lastFiled = 0 }
EmpireAutoProduction = { cfg = CFG, state = state }

local function inRect(x, y, b)
    return x >= math.min(b.x1, b.x2) and x <= math.max(b.x1, b.x2)
       and y >= math.min(b.y1, b.y2) and y <= math.max(b.y1, b.y2)
end

local function parseKey(k)
    local x, y, z = tostring(k):match("(-?%d+),(-?%d+),(-?%d+)")
    return tonumber(x), tonumber(y), tonumber(z)
end

-- ---- feeding ----
-- take up to `need` items of `ftype` out of the base containers into the node container
local function pull(player, node, ftype, need)
    local moved = 0
    local srcs = {}
    pcall(function() srcs = EmpireBaseCache.containersFor(ftype) or {} end)
    for _, src in ipairs(srcs) do
        if moved >= need then break end
        if src ~= node then
            local items = nil
            pcall(function() items = src:getItems() end)
            local n = items and (m(items, "size") or 0) or 0
            local take = {}
            for i = 0, n - 1 do
                if #take + moved >= need then break end
                local it = m(items, "get", i)
                if it and m(it, "getFullType") == ftype and not m(it, "isFavorite") then take[#take + 1] = it end
            end
            for _, it in ipairs(take) do
                local room = true
                pcall(function() room = node:hasRoomFor(player, it) ~= false end)
                if not room then return moved end
                if pcall(function() node:addItem(it); src:Remove(it) end) then moved = moved + 1 else return moved end
            end
        end
    end
    return moved
end

local function feed(player, obj, nodeData, recipe, cont)
    local perInput, moved = math.ceil(CFG.MAX_MOVE / math.max(1, #recipe.inputs)), 0   -- every input gets its share
    for _, inp in ipairs(recipe.inputs) do
        local want = math.ceil((recipe.ratePerHour or 1) * (inp.n or 1) * CFG.FEED_HOURS)
        local have = EmpireProd.countType(cont, inp.type)
        local need = math.min(want - have, perInput)
        if need > 0 then moved = moved + pull(player, cont, inp.type, need) end
    end
    if moved > 0 then
        pcall(function() EmpireBaseCache.invalidate() end)
        pcall(function() obj:transmitModData() end)
    end
    return moved
end

-- ---- collecting ----
local function collect(player, cont, recipe, key)
    local out = EmpireProd.countType(cont, recipe.output)
    if out < 1 then state.waiting[key] = nil; return 0 end
    local threshold = math.min(CFG.COLLECT_MIN, math.max(1, math.floor((recipe.bufferCap or 100) / 2)))
    state.waiting[key] = (state.waiting[key] or AC.state.beat)
    local long = (AC.state.beat - state.waiting[key]) >= CFG.COLLECT_MAX_BEATS
    if out < threshold and not long then return 0 end
    if not (EmpireSortAll and EmpireSortAll.run) then return 0 end
    local ftype = recipe.output
    EmpireSortAll.run(player, {
        carriedOnly = true,                -- no eviction / consolidation passes: this is a delivery, not a base tidy
        noCarried   = true,                -- do not touch what the survivor is carrying
        sources     = { cont },            -- the node's container is the "pile" to file
        itemFilter  = function(it) return m(it, "getFullType") == ftype end,
    })
    local after = EmpireProd.countType(cont, ftype)
    state.waiting[key] = nil
    return math.max(0, out - after)
end

-- ---- the chore ----
local function run(player, ctx)
    if not CFG.ENABLED or not ctx.inBase then return false end
    local EP = EmpireProd
    if not (EP and EP.registry and EP.resolve and EP.countType) then return false end
    local base = nil
    pcall(function() base = EmpireBases.activeBase(player) end)
    if not base then return false end
    local cell = getCell()
    if not cell then return false end

    local reg = EP.registry()
    local keys = {}
    for k in pairs(reg) do keys[#keys + 1] = k end
    if #keys == 0 then return false end
    table.sort(keys)

    local didMove, didFile = 0, 0
    for step = 1, math.min(CFG.NODES_PER_BEAT, #keys) do
        state.cursor = (state.cursor % #keys) + 1
        local key = keys[state.cursor]
        local x, y, z = parseKey(key)
        if not x then
            reg[key] = nil
        elseif inRect(x, y, base) then
            local sq = cell:getGridSquare(x, y, z)
            if sq then   -- nil square = not loaded: keep the entry
                local obj = EP.nodeOnSquare(sq)
                if not obj then
                    reg[key] = nil   -- the node is gone (container removed / production stopped elsewhere)
                    state.waiting[key] = nil
                else
                    local md = m(obj, "getModData")
                    local nodeData = md and md.EmpireProd
                    local recipe = nodeData and EP.recipes[nodeData.recipe]
                    local cont = m(obj, "getContainer")
                    if recipe and cont and not nodeData.manual then
                        pcall(function() EP.resolve(obj) end)           -- settle what accrued with the inputs it had
                        didMove = didMove + (feed(player, obj, nodeData, recipe, cont) or 0)
                        if didFile == 0 then didFile = collect(player, cont, recipe, key) or 0 end
                    end
                end
            end
        end
    end

    state.lastMoved, state.lastFiled = didMove, didFile
    if didMove == 0 and didFile == 0 then return false end
    AC.say(player, "Production: stocked " .. didMove .. " items, filed " .. didFile .. " made", true)
    print(string.format("[EmpireAutoProduction] fed %d items into nodes, filed %d finished items", didMove, didFile))
    return didFile > 0   -- a sort ran: that was the heavy work of this beat
end
EmpireAutoProduction.run = run

if AC and AC.register then
    AC.register("production", 60, run, { enabled = function() return CFG.ENABLED end })
end

print("[EmpireQoL] AutoProduction loaded: feeds EmpireProduction nodes from base storage and files their output on the 10-min beat.")
