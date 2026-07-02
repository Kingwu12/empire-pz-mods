-- Empire QoL :: 39_TopOffMags.lua
-- Downtime one-click: fill every empty/partial magazine ON YOU (main pockets, worn
-- vests/rigs/pouches, carried bags) from your loose rounds, wherever those live on
-- your body. Combat reload stays 100% vanilla -- this only kills the click-grind.
--
-- HOW: vanilla's ISLoadBulletsInMagazine hard-requires the mag AND rounds in MAIN
-- inventory (isValid uses non-recursive contains; start/isLoadFinished use
-- non-recursive containsWithModule -- verified in vanilla source). So we STAGE:
-- pull needed mags + rounds out of pouches into main pockets, queue the game's own
-- load actions (engine consumes rounds -- no dupe/loss), then a final queued step
-- puts every staged item that survived BACK into the exact pouch it came from.
-- Your rig's layout is preserved: mags return to their pouch, leftover rounds too.

require "TimedActions/ISBaseTimedAction"

local TOPOFF_KEY = Keyboard.KEY_NUMPAD8   -- Numpad 8 = top off all mags (NumLock ON)

local function isMagazine(it)
    local ok = false
    pcall(function()
        if it and it.getMaxAmmo and it:getMaxAmmo() and it:getMaxAmmo() > 0
           and it.getAmmoType and it:getAmmoType() then
            local isGun = false
            pcall(function() isGun = instanceof(it, "HandWeapon") end)
            ok = not isGun
        end
    end)
    return ok
end

-- ---- stash-back: queued LAST, after all load actions -- returns every staged item
-- still sitting in main pockets to the pouch it was staged out of. If the pouch has
-- no room (or the queue got cancelled) the item just stays in main pockets. ----
ISEmpireStashBack = ISBaseTimedAction:derive("ISEmpireStashBack")
function ISEmpireStashBack:isValid() return true end
function ISEmpireStashBack:waitToStart() return false end
function ISEmpireStashBack:update() end
function ISEmpireStashBack:start() end
function ISEmpireStashBack:stop() ISBaseTimedAction.stop(self) end
function ISEmpireStashBack:perform()
    pcall(function()
        local main = self.character:getInventory()
        local back = 0
        for _, rec in ipairs(self.recs or {}) do
            local it, src = rec.item, rec.src
            if it and src and main:contains(it) then
                local fits = false
                pcall(function() fits = src:hasRoomFor(self.character, it) end)
                if fits then
                    local ok = pcall(function() src:addItem(it); main:Remove(it) end)
                    if ok then back = back + 1 end
                end
            end
        end
        if back > 0 then
            pcall(function() HaloTextHelper.addTextWithArrow(self.character, "Stashed " .. back .. " item(s) back in your gear", "[br/]", false, HaloTextHelper.getColorGreen()) end)
        end
    end)
    ISBaseTimedAction.perform(self)
end
function ISEmpireStashBack:new(character, recs)
    local o = ISBaseTimedAction.new(self, character)
    o.recs = recs
    o.maxTime = 1
    o.stopOnWalk = false
    o.stopOnRun = false
    return o
end

-- collect mags that need filling, remembering WHICH container each sits in
local function collectMags(inv, out, seen, depth, src)
    if not inv or depth > 4 then return end
    local items = nil; pcall(function() items = inv:getItems() end)
    if not items then return end
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if it and not seen[it] then
            seen[it] = true
            if isMagazine(it) then
                local cur, mx = 0, 0
                pcall(function() cur = it:getCurrentAmmoCount() end)
                pcall(function() mx = it:getMaxAmmo() end)
                if mx > 0 and cur < mx then out[#out + 1] = { mag = it, src = src } end
            end
            if instanceof(it, "InventoryContainer") then
                local sub = nil; pcall(function() sub = it:getInventory() end)
                if sub then collectMags(sub, out, seen, depth + 1, sub) end
            end
        end
    end
end

-- count loose rounds of `itemKey` sitting DIRECTLY in a container (non-recursive,
-- mirroring what the vanilla load action can actually see in main pockets)
local function countDirect(cont, itemKey)
    local n = 0
    pcall(function()
        local items = cont:getItems()
        local want = tostring(itemKey):lower()
        for i = 0, items:size() - 1 do
            local it = items:get(i)
            local ft = ""; pcall(function() ft = (it:getFullType() or ""):lower() end)
            if ft == want then n = n + 1 end
        end
    end)
    return n
end

-- pull up to `need` loose rounds of `itemKey` out of sub-containers into MAIN,
-- recording each move for stash-back. Returns how many were staged.
local function stageRounds(main, cont, itemKey, need, recs, depth)
    if need <= 0 or not cont or depth > 4 then return 0 end
    local stagedN = 0
    local items = nil; pcall(function() items = cont:getItems() end)
    if not items then return 0 end
    local want = tostring(itemKey):lower()
    local snap = {}
    for i = 0, items:size() - 1 do snap[#snap + 1] = items:get(i) end
    for _, it in ipairs(snap) do
        if stagedN >= need then break end
        local ft = ""; pcall(function() ft = (it:getFullType() or ""):lower() end)
        if cont ~= main and ft == want then
            local ok = pcall(function() main:addItem(it); cont:Remove(it) end)
            if ok then recs[#recs + 1] = { item = it, src = cont }; stagedN = stagedN + 1 end
        elseif instanceof(it, "InventoryContainer") then
            local sub = nil; pcall(function() sub = it:getInventory() end)
            if sub then stagedN = stagedN + stageRounds(main, sub, itemKey, need - stagedN, recs, depth + 1) end
        end
    end
    return stagedN
end

local function topOff(player)
    if not player then player = getSpecificPlayer(0) end
    if not player then return end
    local inv = player:getInventory()
    if not inv then return end

    local magRecs, seen = {}, {}
    collectMags(inv, magRecs, seen, 0, inv)
    if #magRecs == 0 then
        HaloTextHelper.addTextWithArrow(player, "No empty mags on you", "[br/]", false, HaloTextHelper.getColorWhite())
        return
    end

    local stashRecs = {}       -- everything staged into main pockets -> goes back after
    local pool = {}            -- itemKey -> rounds available in MAIN (staged as needed)
    local queued, filled = 0, 0
    for _, mr in ipairs(magRecs) do
        local mag = mr.mag
        local cur, mx = 0, 0
        pcall(function() cur = mag:getCurrentAmmoCount() end)
        pcall(function() mx = mag:getMaxAmmo() end)
        local space = mx - cur
        if space > 0 then
            local itemKey = nil
            pcall(function() itemKey = mag:getAmmoType():getItemKey() end)
            if itemKey then
                -- pool starts at what's ALREADY loose in main pockets (that's all the
                -- vanilla action can see); pouched rounds are staged in on demand.
                if pool[itemKey] == nil then pool[itemKey] = countDirect(inv, itemKey) end
                if pool[itemKey] < space then
                    pool[itemKey] = pool[itemKey] + stageRounds(inv, inv, itemKey, space - pool[itemKey], stashRecs, 0)
                end
                local n = math.min(space, pool[itemKey])
                if n > 0 then
                    -- the MAG itself must sit in main pockets too -- stage it if pouched
                    local inMain = false
                    pcall(function() inMain = inv:contains(mag) end)
                    if not inMain then
                        local ok = pcall(function() inv:addItem(mag); mr.src:Remove(mag) end)
                        if ok then stashRecs[#stashRecs + 1] = { item = mag, src = mr.src }; inMain = true end
                    end
                    if inMain then
                        local ok = false
                        pcall(function()
                            ISTimedActionQueue.add(ISLoadBulletsInMagazine:new(player, mag, n))
                            ok = true
                        end)
                        if ok then
                            pool[itemKey] = pool[itemKey] - n
                            queued = queued + 1
                            filled = filled + n
                        end
                    end
                end
            end
        end
    end

    if queued == 0 then
        HaloTextHelper.addTextWithArrow(player, "No loose rounds anywhere on you to fill mags", "[br/]", false, HaloTextHelper.getColorRed())
        player:Say("No loose rounds on me to top off mags.")
        -- nothing queued but rounds may have been staged for a partial caliber -- return them
        if #stashRecs > 0 then pcall(function() ISTimedActionQueue.add(ISEmpireStashBack:new(player, stashRecs)) end) end
    else
        HaloTextHelper.addTextWithArrow(player, "Topping off " .. queued .. " mag(s) - " .. filled .. " rounds", "[br/]", false, HaloTextHelper.getColorGreen())
        player:Say("Topping off " .. queued .. " magazines.")
        if #stashRecs > 0 then
            pcall(function() ISTimedActionQueue.add(ISEmpireStashBack:new(player, stashRecs)) end)
        end
    end
end

-- ---- triggers: Numpad 8, plus a right-click option on guns/mags ----
Events.OnKeyPressed.Add(function(key)
    if key == TOPOFF_KEY then pcall(topOff) end
end)

-- Right-click option REMOVED per King (clutter): Numpad 8 is the way in.

print("[EmpireQoL] Top Off Mags v2 loaded. Numpad 8 fills all mags from rounds ANYWHERE on you (pouches/vests/bags); staged items return to their pouch after. Combat reload stays vanilla.")
