-- EmpireQoL :: 49_AutoTest.lua -- Tier-3 in-game self-test
-- Runs assertions on every Empire feature's wiring at game start and on demand
-- (Numpad 9). Prints one PASS/FAIL line per check and a summary. The point:
-- collapse King's manual test loop -- one boot (or one keypress) tells us
-- which links in the chain are alive before any gameplay testing happens.

local function runTests()
    local pass, fail = 0, 0
    local function check(name, ok, detail)
        if ok then
            pass = pass + 1
            print("[EmpireTest] PASS " .. name .. (detail and (" -- " .. detail) or ""))
        else
            fail = fail + 1
            print("[EmpireTest] FAIL " .. name .. (detail and (" -- " .. detail) or ""))
        end
    end

    print("[EmpireTest] ---- Empire self-test starting ----")

    -- T1: vanilla API surface our mods lean on (breaks silently on game updates)
    check("api.FixingManager.getFixes", FixingManager ~= nil and FixingManager.getFixes ~= nil)
    check("api.FixingManager.getCondRepaired", FixingManager ~= nil and FixingManager.getCondRepaired ~= nil)
    check("api.ISFixVehiclePartAction", ISFixVehiclePartAction ~= nil)
    check("api.ISVehiclePartMenu", ISVehiclePartMenu ~= nil)
    check("api.ISPathFindAction.pathToVehicleArea", ISPathFindAction ~= nil and ISPathFindAction.pathToVehicleArea ~= nil)
    check("api.HaloTextHelper", HaloTextHelper ~= nil)

    -- T2: Empire feature globals loaded
    check("feature.BaseContainers", type(EmpireQoL_BaseContainers) == "function")
    local empireGlobals = {}
    pcall(function()
        for k, v in pairs(_G) do
            if type(k) == "string" and k:find("^Empire") then
                empireGlobals[#empireGlobals + 1] = k
            end
        end
    end)
    check("feature.globals", #empireGlobals > 0, #empireGlobals .. " Empire globals: " .. table.concat(empireGlobals, ", "))

    -- T3: the five Papa Humvee craft recipes are registered
    local recipes = { "Empire_M998_MakeBullBar", "Empire_M998_MakeM2Armor",
        "Empire_M998_MakeTurretArmor", "Empire_M998_MakeMuffler",
        "Empire_M998_MakeSpareTireCarrier" }
    for _, r in ipairs(recipes) do
        local found = false
        pcall(function() found = getScriptManager():getCraftRecipe(r) ~= nil end)
        check("recipe." .. r, found)
    end

    -- T4: Papa part items resolvable (the recipe outputs / compat targets)
    local items = { "Base.M998_Bull_Bar2", "Base.M998_M2_Armor_Green2",
        "Base.M998_Turret_Armor_Green2", "Base.M998_Muffler2",
        "Base.M998_Spare_Tire_Carrier2" }
    for _, ft in ipairs(items) do
        local it = nil
        pcall(function() it = instanceItem(ft) end)
        check("item." .. ft, it ~= nil, it and it:getDisplayName() or "not spawnable")
    end

    -- T5: fixing pipe alive end-to-end on a tire (VRO supplies tire fixings;
    -- this is the exact path QuickRepair walks, minus the vehicle)
    local tire = nil
    -- vanilla tires are numbered by size: OldTire1/2/3 (generated/items/normal.txt)
    for _, ft in ipairs({ "Base.OldTire2", "Base.NormalTire2", "Base.ModernTire2" }) do
        pcall(function() tire = tire or instanceItem(ft) end)
    end
    if tire then
        local fixes, gainOk, fixerCount = nil, false, 0
        pcall(function() fixes = FixingManager.getFixes(tire) end)
        local hasFixes = fixes ~= nil and not fixes:isEmpty()
        check("fixing.tireHasFixes", hasFixes, hasFixes and (fixes:size() .. " fixing(s)") or "no fixings -- VRO wiring dead?")
        if hasFixes then
            pcall(function()
                local fixing = fixes:get(0)
                local fixers = fixing:getFixers()
                fixerCount = fixers:size()
                local player = getSpecificPlayer(0)
                local g = FixingManager.getCondRepaired(tire, player, fixing, fixers:get(0))
                gainOk = type(g) == "number"
            end)
            check("fixing.condRepairedCallable", gainOk, gainOk and (fixerCount .. " fixer(s) on first fixing") or "gain call threw")
        end
    else
        check("fixing.tireItem", false, "no vanilla tire item spawnable -- names changed?")
    end

    -- T5b: VRO parallel repair system reachable (QuickRepair v3 leans on it)
    local vro = nil
    pcall(function() vro = require "VRO/Core" end)
    local recipeCount = 0
    pcall(function() recipeCount = (vro and type(vro.Recipes) == "table") and #vro.Recipes or 0 end)
    check("vro.core", vro ~= nil, vro and (recipeCount .. " recipes loaded") or "VRO/Core not requireable")

    -- T6: base cache returns containers when at base (soft: 0 is legal away from base)
    local conts = nil
    pcall(function() conts = EmpireQoL_BaseContainers(getSpecificPlayer(0)) end)
    check("base.containers", conts ~= nil, conts and (#conts .. " container(s) in range") or "call failed")

    print("[EmpireTest] ---- " .. pass .. " pass, " .. fail .. " fail ----")
    pcall(function()
        local player = getSpecificPlayer(0)
        if player then
            local good = (fail == 0)
            HaloTextHelper.addTextWithArrow(player,
                "Empire self-test: " .. pass .. " pass, " .. fail .. " fail",
                "[br/]", good, good and HaloTextHelper.getColorGreen() or HaloTextHelper.getColorRed())
        end
    end)
end

Events.OnGameStart.Add(function()
    pcall(runTests)
end)

Events.OnKeyPressed.Add(function(key)
    local np9 = 73  -- lwjgl KEY_NUMPAD9
    pcall(function() if Keyboard and Keyboard.KEY_NUMPAD9 then np9 = Keyboard.KEY_NUMPAD9 end end)
    if key == np9 then pcall(runTests) end
end)

print("[EmpireQoL] AutoTest loaded: self-test runs at game start and on Numpad 9")
