-- Empire QoL :: 14_AutoNeeds.lua  (27 Nov 2026, B42.22)
-- King: "i love empire building but dont like the sorting and small things".
-- NEEDS ON AUTOPILOT: when hunger or thirst reaches the "peckish / thirsty" line and the
-- survivor is idle and safe, he eats or drinks the way a competent crew member would:
--   * food closest to spoiling goes first (so the fridge never rots while the tins sit), cooked
--     and non-miserable food before the grim stuff, favourites (starred items) are never touched;
--   * sealed cans are opened with the game's own opening recipe (a can opener is fetched from
--     base stock if he is not carrying one), then eaten;
--   * water = clean "Water" / "CarbonatedWater" in a bottle (never tainted, never alcohol);
--   * carried stock first, then base stock (real items move from a base container to the body
--     inventory, nothing is spawned), and only when he is inside the base.
-- Replaces the old OnTick-every-second 9_AutoFeed (disabled: it read Stats:getHunger, which 42.22 removed).
--
-- PERFORMANCE: no per-frame handler. It is a chore on the one 10-minute beat (13_AutoChores).
-- The two stat reads are O(1); the item scan runs only when a need is actually due, walks the
-- carried containers first and the base index only if nothing carried will do, classifies each
-- item type once (memo) and backs off for BACKOFF_BEATS beats when nothing edible exists.
--
-- Uses the vanilla actions through the vanilla entry points (ISInventoryPaneContextMenu.eatItem /
-- onDrinkFluid), only when no timed action is running, so it never wipes the player's queue.
-- Numpad 5 (13_AutoChores) switches everything off.

local CFG = {
    ENABLED       = true,
    EAT_AT        = 0.20,  -- CharacterStat.HUNGER 0 (full) .. 1 (starving): eat from here (about the "peckish" moodle)
    DRINK_AT      = 0.20,  -- CharacterStat.THIRST 0 .. 1; vanilla itself offers a drink above 0.1 and needs thirst*2 litres
    FULL_AT       = 0.05,  -- portion size: eat just enough to get back under this
    SEVERE_AT     = 0.50,  -- at this level he eats/drinks even while walking (the action simply cancels if he keeps running)
    BACKOFF_BEATS = 6,     -- after "nothing to eat/drink" or 3 failed tries: stay quiet for an hour of game time
    MAX_STRIKES   = 3,     -- tries in a row that did not move the stat
    BASE_STOCK    = true,  -- may take food/water/can opener from base storage while inside the base
    BIG_CONTAINER = 2.5,   -- litres: buckets and jugs are only used for drinking when no bottle is left
    FAR_FUTURE    = 100000,-- spoilage "days left" at or above this = never spoils
}

local state = {
    nextTry = { eat = 0, drink = 0 },   -- beat before which this need is not retried
    strikes = { eat = 0, drink = 0 },
    last    = nil,                      -- { kind, beat, value } of the previous attempt
    said    = {},                       -- one console line per "nothing to eat" episode
}
EmpireAutoNeeds = { cfg = CFG, state = state }

-- ---- shared helpers from 13_AutoChores (safe call, carried/base containers, real-item fetch) ----
local AC = EmpireAutoChores
local m, fetch = AC.m, AC.fetch

local function stat(player, name)
    local v = 0
    pcall(function() v = player:getStats():get(CharacterStat[name]) or 0 end)
    return tonumber(v) or 0
end

local function isFood(it)
    local f = false
    pcall(function() f = instanceof(it, "Food") end)
    return f
end

-- ---- item classification (once per item type, never per frame) ----
local KIND = {}   -- fullType -> "food" | "fluid" | "opener" | false
local function isOpener(it)
    local ok = false
    pcall(function() if ItemTag and ItemTag.CAN_OPENER and it:hasTag(ItemTag.CAN_OPENER) then ok = true end end)
    -- (a String tag throws "expected argument of type ItemTag" in 42.22; the item-type check below covers openers)
    if not ok then
        local t = m(it, "getType")
        if type(t) == "string" and (t:find("TinOpener") or t:find("CanOpener")) then ok = true end
    end
    return ok
end
local function kindOf(it)
    local ft = m(it, "getFullType")
    if not ft then return false end
    local k = KIND[ft]
    if k == nil then
        if isFood(it) then k = "food"
        elseif m(it, "getFluidContainer") then k = "fluid"
        elseif isOpener(it) then k = "opener"
        else k = false end
        KIND[ft] = k
    end
    return k
end

-- ---- what is fit to eat: the vanilla double-click predicate (ISInventoryPane.lua) plus our own safety ----
local function edibleBase(player, it)
    if m(it, "isBurnt") or m(it, "isRotten") or m(it, "isFrozen") or m(it, "isSpice")
       or m(it, "isTainted") or m(it, "isFavorite") or m(it, "isAlcoholic") then return false end
    if m(player, "isKnownPoison", it) then return false end
    if m(it, "isbDangerousUncooked") and not m(it, "isCooked") then return false end
    return true
end
local function hungerChange(it) return tonumber(m(it, "getHungChange")) or 0 end

-- "days until it rots" (lower = eat it sooner). Never-spoiling food ranks last. Food that makes the
-- survivor unhappy (raw, bland) costs ten extra days of priority so it only wins when it is about to rot.
local function spoilScore(it)
    local off, age = tonumber(m(it, "getOffAgeMax")), tonumber(m(it, "getAge"))
    local left = CFG.FAR_FUTURE
    if off and age and off > 0 and off < CFG.FAR_FUTURE then left = off - age end
    if (tonumber(m(it, "getUnhappyChange")) or 0) > 0 then left = left + 10 end
    return left
end

-- sealed food (cans): the game's own opening recipe, valid only if the recipe can be performed now
local function openingRecipe(player, it)
    local name = m(it, "getOpeningRecipe")
    if not name then return nil end
    local recipe = nil
    pcall(function() recipe = getScriptManager():getCraftRecipe(name) end)
    if not recipe then return nil end
    local ok = false
    pcall(function()
        local containers = ISInventoryPaneContextMenu.getContainers(player)
        local logic = HandcraftLogic.new(player, nil, nil)
        logic:setContainers(containers)
        logic:setRecipeFromContextClick(recipe, it)
        ok = logic:canPerformCurrentRecipe()
    end)
    if ok then return recipe end
    return nil
end

local function isSealedFood(it)
    local si = m(it, "getScriptItem")
    return si ~= nil and m(si, "isCantEat") == true and m(it, "getOpeningRecipe") ~= nil
end

-- clean water only: the same fluid strings the vanilla water drink path accepts
local function waterInfo(it)
    local fc = m(it, "getFluidContainer")
    if not fc or m(fc, "isEmpty") or m(it, "isFavorite") then return nil end
    local pf = m(fc, "getPrimaryFluid")
    local ts = pf and m(pf, "getFluidTypeString")
    if ts ~= "Water" and ts ~= "CarbonatedWater" then return nil end
    if m(fc, "isTaintedStatusKnown") then return nil end
    local amount = tonumber(m(fc, "getAmount")) or 0
    if amount <= 0 then return nil end
    return { fc = fc, amount = amount, cap = tonumber(m(fc, "getCapacity")) or amount }
end

-- ---- containers to look in ----
local carriedContainers, baseContainers = AC.carriedContainers, AC.baseContainers

-- One pass over a container list: best food, sealed foods, best water, an opener.
local function survey(conts, player, needLitres)
    local r = { food = nil, foodS = math.huge, sealed = {}, water = nil, waterS = math.huge, opener = nil }
    for _, cont in ipairs(conts or {}) do
        local items = nil
        pcall(function() items = cont:getItems() end)
        local n = items and (m(items, "size") or 0) or 0
        for i = 0, n - 1 do
            local it = m(items, "get", i)
            local k = it and kindOf(it)
            if k == "food" then
                if hungerChange(it) < 0 and edibleBase(player, it) then
                    if isSealedFood(it) then
                        if #r.sealed < 3 then r.sealed[#r.sealed + 1] = { item = it, cont = cont } end
                    elseif not (m(m(it, "getScriptItem"), "isCantEat")) then
                        local s = spoilScore(it)
                        if s < r.foodS then r.food, r.foodS, r.foodC = it, s, cont end
                    end
                end
            elseif k == "fluid" then
                local w = waterInfo(it)
                if w then
                    -- best fit: the smallest container that covers the need, big jugs/buckets last
                    local s = (w.amount >= needLitres) and w.amount or (1000 + needLitres - w.amount)
                    if w.cap > CFG.BIG_CONTAINER then s = s + 100000 end
                    if s < r.waterS then r.water, r.waterS, r.waterC = it, s, cont end
                end
            elseif k == "opener" and not r.opener then
                r.opener, r.openerC = it, cont
            end
        end
    end
    return r
end

local function nameOf(it) return tostring(m(it, "getDisplayName") or m(it, "getName") or m(it, "getType") or "?") end

-- portion: smallest of 1/4, 1/2, 1 that covers what he needs (vanilla offers the small ones only for big items)
local function portion(it, hunger)
    local hc = math.abs(hungerChange(it))
    if hc < 0.04 or hc <= 0 then return 1, 100 end
    local frac = (hunger - CFG.FULL_AT) / hc
    if frac <= 0.25 and hc >= 0.08 then return 0.25, 25 end
    if frac <= 0.5 then return 0.5, 50 end
    return 1, 100
end

local function playerNum(player) return tonumber(m(player, "getPlayerNum")) or 0 end

-- ---- the two needs ----
local function doEat(player, ctx, hunger)
    local carried = survey(carriedContainers(player), player, 0)
    local base = nil
    local function baseSurvey()
        if base == nil then
            base = false
            if CFG.BASE_STOCK and ctx.inBase then
                local bc = baseContainers()
                if bc then base = survey(bc, player, 0) end
            end
        end
        return base
    end

    -- 1) ordinary food: carried first, then base stock
    local pick, from = carried.food, "carried"
    local pickC = carried.foodC
    if not pick then
        local b = baseSurvey()
        if b and b.food then pick, pickC, from = b.food, b.foodC, "base" end
    end
    if pick then
        if from == "base" and not fetch(player, pick, pickC) then return false end
        local pct, eatPct = portion(pick, hunger)
        ISInventoryPaneContextMenu.eatItem(pick, pct, playerNum(player))
        EmpireAutoChores.say(player, "Eating " .. nameOf(pick), true)
        print(string.format("[EmpireAutoNeeds] eat %s (hunger %.2f, %s, %d%%)", nameOf(pick), hunger, from, eatPct))
        return true
    end

    -- 2) sealed cans: needs the opening recipe to be performable (opener on hand)
    local cands = {}
    for _, c in ipairs(carried.sealed) do cands[#cands + 1] = { item = c.item, cont = c.cont, from = "carried" } end
    local b = baseSurvey()
    if b then for _, c in ipairs(b.sealed) do cands[#cands + 1] = { item = c.item, cont = c.cont, from = "base" } end end
    local opener, openerC, openerFrom = carried.opener, carried.openerC, "carried"
    if not opener and b and b.opener then opener, openerC, openerFrom = b.opener, b.openerC, "base" end
    for _, c in ipairs(cands) do
        local recipe = openingRecipe(player, c.item)
        if not recipe and opener and openerFrom == "base" and fetch(player, opener, openerC) then
            openerFrom = "carried"
            recipe = openingRecipe(player, c.item)
        end
        if not recipe and c.from == "base" then
            -- the recipe may be performable only once the can itself is in the inventory
            if fetch(player, c.item, c.cont) then c.from = "carried"; recipe = openingRecipe(player, c.item) end
        end
        if recipe then
            if c.from == "base" and not fetch(player, c.item, c.cont) then return false end
            local pct, eatPct = portion(c.item, hunger)
            ISInventoryPaneContextMenu.eatItem(c.item, pct, playerNum(player), recipe, eatPct)
            EmpireAutoChores.say(player, "Opening and eating " .. nameOf(c.item), true)
            print(string.format("[EmpireAutoNeeds] open+eat %s (hunger %.2f, %s)", nameOf(c.item), hunger, c.from))
            return true
        end
    end
    return false
end

local function doDrink(player, ctx, thirst)
    local litres = thirst * 2   -- vanilla: thirst 1.0 = 2 litres
    local carried = survey(carriedContainers(player), player, litres)
    local pick, pickC, from = carried.water, carried.waterC, "carried"
    if not pick and CFG.BASE_STOCK and ctx.inBase then
        local bc = baseContainers()
        if bc then
            local b = survey(bc, player, litres)
            if b.water then pick, pickC, from = b.water, b.waterC, "base" end
        end
    end
    if not pick then return false end
    if from == "base" and not fetch(player, pick, pickC) then return false end
    local w = waterInfo(pick)
    if not w then return false end
    local percent = math.min(1, math.max(0.1, litres / w.amount))
    local recipe = nil
    if m(pick, "isSealed") then
        recipe = openingRecipe(player, pick)
        if not recipe then return false end   -- sealed and no way to open it right now
    end
    ISInventoryPaneContextMenu.onDrinkFluid(pick, percent, player, recipe, pick)
    EmpireAutoChores.say(player, "Drinking " .. nameOf(pick), true)
    print(string.format("[EmpireAutoNeeds] drink %s (thirst %.2f, %s, %d%%)", nameOf(pick), thirst, from, math.floor(percent * 100)))
    return true
end

-- A try that did not move the stat strikes; MAX_STRIKES in a row = back off an hour.
local function noteTry(kind, beat, value)
    local l = state.last
    if l and l.kind == kind and (beat - l.beat) <= 2 and value >= l.value - 0.01 then
        state.strikes[kind] = state.strikes[kind] + 1
    else
        state.strikes[kind] = 0
    end
    state.last = { kind = kind, beat = beat, value = value }
    if state.strikes[kind] >= CFG.MAX_STRIKES then
        state.strikes[kind] = 0
        state.nextTry[kind] = beat + CFG.BACKOFF_BEATS
        print("[EmpireAutoNeeds] " .. kind .. " did not take " .. CFG.MAX_STRIKES .. " times - standing down for " .. CFG.BACKOFF_BEATS .. " beats")
        return false
    end
    return true
end

local function moving(player)
    local mv = false
    pcall(function() mv = player:isPlayerMoving() end)
    return mv
end

local function run(player, ctx)
    if not CFG.ENABLED then return false end
    local hunger, thirst = stat(player, "HUNGER"), stat(player, "THIRST")
    local wantEat   = hunger >= CFG.EAT_AT and state.nextTry.eat <= ctx.beat
    local wantDrink = thirst >= CFG.DRINK_AT and state.nextTry.drink <= ctx.beat
    if wantEat then
        -- vanilla refuses to start eating when stuffed (moodle FOOD_EATEN level 3)
        local stuffed = false
        pcall(function() stuffed = player:getMoodles():getMoodleLevel(MoodleType.FOOD_EATEN) >= 3 end)
        if stuffed then wantEat = false end
    end
    if not (wantEat or wantDrink) then return false end
    local severe = math.max(hunger, thirst) >= CFG.SEVERE_AT
    if moving(player) and not severe then return false end   -- do not hijack a survivor who is walking somewhere

    local order = {}
    if wantDrink and (not wantEat or thirst >= hunger) then order = { "drink", "eat" } else order = { "eat", "drink" } end
    for _, kind in ipairs(order) do
        if (kind == "drink" and wantDrink) or (kind == "eat" and wantEat) then
            if noteTry(kind, ctx.beat, kind == "drink" and thirst or hunger) then
                local did = (kind == "drink") and doDrink(player, ctx, thirst) or doEat(player, ctx, hunger)
                if did then state.said[kind] = nil; return true end
                -- nothing usable: stay quiet for a while, and do not let this block the other need
                state.nextTry[kind] = ctx.beat + CFG.BACKOFF_BEATS
                if not state.said[kind] then
                    state.said[kind] = true
                    print("[EmpireAutoNeeds] " .. kind .. " needed but nothing suitable carried" .. (ctx.inBase and " or in base stock" or " (not in base)"))
                end
            end
        end
    end
    return false
end
EmpireAutoNeeds.run = run

if EmpireAutoChores and EmpireAutoChores.register then
    EmpireAutoChores.register("needs", 10, run, { enabled = function() return CFG.ENABLED end })
end

print("[EmpireQoL] AutoNeeds loaded: eats/drinks from carried then base stock on the 10-min beat (no per-frame handler).")
