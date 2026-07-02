-- EmpireQoL :: 46_M998PartCompat.lua -- KI5 M998 double-load item bridge
-- Game 42.19 loads BOTH the mod's legacy root scripts (B41 item names:
-- M998Bullbar1_Item, M998CarFrontDoorArmor1_Item, ...) AND the 42.13 scripts
-- (new names: 92amgeneralM998BullbarA, ...). The legacy vehicle definition wins
-- the collision, so install slots demand the LEGACY items while the crafting
-- window produces the NEW ones -- crafted parts show "you don't have it".
-- Bridge: when a mechanics or tuning window opens, convert any crafted
-- new-name part (player inventory + worn bags + base storage) into its legacy
-- twin, condition preserved. Delete this file when KI5 cleans the root folder
-- or the game stops double-loading version folders.

local MAP = {
    ["Base.92amgeneralM998BullbarA"]         = "Base.M998Bullbar1_Item",
    ["Base.92amgeneralM998BullbarB"]         = "Base.M998Bullbar2_Item",
    ["Base.92amgeneralM998FrontArmor"]       = "Base.M998CarFrontDoorArmor1_Item",
    ["Base.92amgeneralM998RearArmor"]        = "Base.M998CarRearDoorArmor1_Item",
    ["Base.92amgeneralM998WindshieldArmor0"] = "Base.M998WindshieldArmor1_Item",
    ["Base.92amgeneralM998WindshieldArmor1"] = "Base.M998WindshieldArmor2_Item",
}

local _last = 0

local function convertContainer(c, out, stats)
    local items = nil
    pcall(function() items = c:getItems() end)
    if not items then return end
    local snap = {}
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        local ft = nil
        pcall(function() ft = it and it:getFullType() end)
        if ft and MAP[ft] then snap[#snap + 1] = it end
    end
    stats.candidates = stats.candidates + #snap
    for _, old in ipairs(snap) do
        local tgt = MAP[old:getFullType()]
        -- no script-existence pre-check: AddItem returns nil for unknown types,
        -- and we only Remove the original after the twin exists.
        pcall(function()
            local newIt = c:AddItem(tgt)
            if newIt then
                pcall(function() newIt:setCondition(old:getCondition()) end)
                c:Remove(old)
                local nm = tgt
                pcall(function() nm = newIt:getDisplayName() end)
                out[#out + 1] = nm
            else
                stats.spawnFail = stats.spawnFail + 1
            end
        end)
    end
end

local function convertEverywhere(player)
    local now = getTimestampMs()
    if (now - _last) < 10000 then return end
    _last = now
    local out = {}
    local stats = { candidates = 0, spawnFail = 0 }
    pcall(function() convertContainer(player:getInventory(), out, stats) end)
    -- one level of carried/worn bags (crafted parts usually ride in the backpack)
    pcall(function()
        local items = player:getInventory():getItems()
        for i = 0, items:size() - 1 do
            local it = items:get(i)
            if it and instanceof(it, "InventoryContainer") then
                convertContainer(it:getInventory(), out, stats)
            end
        end
    end)
    pcall(function()
        local src = EmpireQoL_BaseContainers and EmpireQoL_BaseContainers(player)
        if src then for _, c in ipairs(src) do convertContainer(c, out, stats) end end
    end)
    print("[EmpireQoL] M998Compat: sweep candidates=" .. stats.candidates
        .. " converted=" .. #out .. " spawnFail=" .. stats.spawnFail)
    if #out > 0 then
        print("[EmpireQoL] M998Compat: converted " .. #out .. " crafted part(s) to installable legacy items: " .. table.concat(out, ", "))
        pcall(function()
            HaloTextHelper.addTextWithArrow(player, "M998 parts converted: " .. #out, "[br/]", true, HaloTextHelper.getColorGreen())
        end)
        pcall(function() if EmpireBaseCache and EmpireBaseCache.invalidate then EmpireBaseCache.invalidate() end end)
    end
end

Events.OnGameStart.Add(function()
    local installed = false
    local function install()
        if installed then return end
        installed = true
        Events.OnTick.Remove(install)
        local function hook(klassName, methodName)
            local k = _G[klassName]
            if not k or type(k[methodName]) ~= "function" then return false end
            local prev = k[methodName]
            k[methodName] = function(self, ...)
                local r = { prev(self, ...) }
                pcall(function()
                    local p = (self and self.character) or getSpecificPlayer(0)
                    if p then convertEverywhere(p) end
                end)
                return unpack(r)
            end
            print("[EmpireQoL] M998Compat: hooked " .. klassName .. ":" .. methodName)
            return true
        end
        local any = false
        any = hook("ISVehicleMechanics", "setVehicle") or any
        any = hook("ISVehicleMechanics", "createChildren") or any
        any = hook("ISVehicleTuning2", "createChildren") or any
        if not any then print("[EmpireQoL] M998Compat: no hookable windows found (game update?)") end
    end
    Events.OnTick.Add(install)
end)
