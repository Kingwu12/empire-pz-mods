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

    -- T1b: every vanilla function the Empire mods call or WRAP, resolved by dotted path.
    -- Added for the 42.19 -> 42.22.2 jump (TIS changed several ISInventoryPaneContextMenu /
    -- ISWorldObjectContextMenu signatures and removed some entry points): one keypress now
    -- names exactly which hook point vanished instead of a silent no-op.
    -- A missing REQUIRED symbol is a FAIL (the wrapper that depends on it is dead);
    -- OPTIONAL ones come from third-party mods (tsarslib, Craft Helper) or are guarded in
    -- their callers, so absence is only a WARN.
    local function resolve(path)
        local cur = _G
        for part in string.gmatch(path, "[^%.]+") do
            if type(cur) ~= "table" then return nil end
            cur = cur[part]
            if cur == nil then return nil end
        end
        return cur
    end
    local required = {
        "FixingManager.getChanceOfFail", "FixingManager.getCondRepaired", "FixingManager.getFixes",
        "ISBaseTimedAction.new", "ISBaseTimedAction.perform", "ISBaseTimedAction.stop",
        "ISBuildIsoEntity.create",
        "ISContextMenu.get", "ISContextMenu.getNew", "ISContextMenu.calcWidth", "ISContextMenu.addOption",
        "ISFixVehiclePartAction.new",
        "ISHandcraftAction.performRecipe", "ISHandcraftAction.start",
        "ISInventoryPage.dirtyUI", "ISInventoryPane.getActualItems",
        "ISInventoryPaneContextMenu.getContainers", "ISInventoryPaneContextMenu.onFix",
        "ISInventoryTransferAction.perform", "ISInventoryTransferAction.transferItem",
        "ISLoadBulletsInMagazine.new", "ISModalDialog.new", "ISTextBox.new",
        "ISTimedActionQueue.add", "ISTimedActionQueue.getTimedActionQueue", "ISTimedActionQueue.isPlayerDoingAction",
        "ISVehicleMechanics.doPartContextMenu",
        "ISVehicleMenu.getVehicleToInteractWith", "ISVehicleMenu.onStartEngine",
        "ISVehiclePartMenu.onInstallPart", "ISVehiclePartMenu.onUninstallPart",
        "ISWorldObjectContextMenu.equip", "ISWorldObjectContextMenu.onConfirmSleep",
        "ISWorldObjectContextMenu.onSleep",
        "ModData.getOrCreate",
    }
    local optional = {
        "ISReloadManager.startReloadFromUi", -- absent from vanilla 42.22.2 Lua (checked); 35_ReloadFromGear guards it
        "ISCraftAction.perform",          -- B41-era; BaseCache wraps it only if present
        "ISCraftingUI.new",               -- Craft Helper UI (EmpireCraftFix)
        "ISVehicleTuning2.getContainers", -- tsarslib / ATA tuning UI
        "ISVehicleTuning2.onInstallPart",
        "ISVehicleTuning2.render",
    }
    for _, path in ipairs(required) do
        local v = resolve(path)
        check("api." .. path, type(v) == "function" or type(v) == "table")
    end
    for _, path in ipairs(optional) do
        local v = resolve(path)
        if v ~= nil then
            check("api.opt." .. path, true)
        else
            print("[EmpireTest] WARN api.opt." .. path .. " -- absent (third-party mod not loaded, or removed in this build)")
        end
    end
    check("api.Events.OnZombieDead", Events ~= nil and Events.OnZombieDead ~= nil)
    check("api.Events.EveryTenMinutes", Events ~= nil and Events.EveryTenMinutes ~= nil)
    pcall(function()
        print("[EmpireTest] game version: " .. tostring(getCore():getVersion()) .. " / " .. tostring(getCore():getGameVersion():toString()))
    end)

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

    -- T2b: the automation chain (13_AutoChores -> Vacuum + SmartSort) is wired end to end
    check("auto.chores.module", type(EmpireAutoChores) == "table" and type(EmpireAutoChores.state) == "table",
        EmpireAutoChores and (EmpireAutoChores.state.on and "ON" or "OFF (Numpad 5)") or "13_AutoChores not loaded")
    check("auto.sort.entry", type(EmpireSortAll) == "table" and type(EmpireSortAll.run) == "function",
        "EmpireSortAll.run (Smart Sort + consolidate) missing -> auto-sort is dead")
    check("auto.sort.uiRefresh", type(EmpireSortAll) == "table" and type(EmpireSortAll.refreshUI) == "function")
    check("auto.unload.entry", type(EmpireSortAll) == "table" and type(EmpireSortAll.transferVehicle) == "function",
        "EmpireSortAll.transferVehicle missing -> auto-unload at the dock is dead")
    check("auto.vehicle.events", Events ~= nil and Events.OnEnterVehicle ~= nil and Events.OnExitVehicle ~= nil)
    check("auto.dock.check", type(EmpireBases) == "table" and type(EmpireBases.vehicleNearBase) == "function")
    check("auto.loot.entry", type(EmpireQoL_Vacuum) == "function", "EmpireQoL_Vacuum missing -> auto-loot is dead")
    check("auto.base.registry", type(EmpireBases) == "table" and type(EmpireBases.activeBase) == "function")
    check("auto.zones.version", type(EmpireZones) == "table" and type(EmpireZones.version) == "number",
        "EmpireZones.version missing -> getEmpireZoneBase falls back to walking every tile on each call")
    pcall(function()
        local s = getSpecificPlayer(0):getStats()
        check("auto.stats.zombieCounts", type(s:getNumVisibleZombies()) == "number"
            and type(s:getNumChasingZombies()) == "number" and type(s:getNumVeryCloseZombies()) == "number")
    end)

    -- T2c: the event-driven chores (14_ needs, 15_ farm, 16_ production, 17_ restock) are registered on the
    -- 10-minute beat, and every vanilla entry point / Java enum they lean on resolves in THIS build. A FAIL
    -- here names the exact chore (or symbol) that would otherwise just silently do nothing.
    do
        local reg = {}
        pcall(function() for _, c in ipairs(EmpireAutoChores.chores) do reg[c.name] = c.order end end)
        for _, name in ipairs({ "needs", "unload", "sort", "loot", "farm", "production", "restock" }) do
            check("chore." .. name, reg[name] ~= nil, reg[name] and ("order " .. reg[name]) or "not registered -> that automation is dead")
        end
        check("chore.helpers", EmpireAutoChores ~= nil and type(EmpireAutoChores.m) == "function"
            and type(EmpireAutoChores.fetch) == "function" and type(EmpireAutoChores.carriedContainers) == "function"
            and type(EmpireAutoChores.baseContainers) == "function" and type(EmpireAutoChores.noteLoot) == "function"
            and type(EmpireAutoChores.hold) == "function" and type(EmpireAutoChores.isHeld) == "function")
        check("chore.base.peek", type(EmpireBaseCache) == "table" and type(EmpireBaseCache.peek) == "function"
            and type(EmpireBaseCache.containersFor) == "function", "restock's just-left-base catch-up needs EmpireBaseCache.peek")
        check("chore.topoff.export", type(EmpireQoL_TopOffMags) == "function", "restock cannot top the mags off")
        check("chore.production.registry", type(EmpireProd) == "table" and type(EmpireProd.registry) == "function"
            and type(EmpireProd.nodeOnSquare) == "function" and type(EmpireProd.countType) == "function",
            "EmpireProduction core without the node registry -> production nodes never feed")
        check("chore.sorter.excludesNodes", type(EmpireSortConfig) == "table" and type(EmpireSortConfig.isExcludedContainer) == "function",
            "production-node containers must be excluded or the sorter pulls their inputs back out")
        -- vanilla entry points the chores call (functions / classes), resolved by dotted path like T1b
        for _, path in ipairs({
            "ISInventoryPaneContextMenu.eatItem", "ISInventoryPaneContextMenu.onDrinkFluid", "ISInventoryPaneContextMenu.getContainers",
            "HandcraftLogic.new",
            "ISFarmingMenu.walkToPlant", "ISFarmingMenu.getWaterUsesInteger",
            "ISHarvestPlantAction.new", "ISWaterPlantAction.new", "ISEquipWeaponAction.new",
            "ISLoadBulletsInMagazine.new",
        }) do
            local v = resolve(path)
            check("chore.api." .. path, type(v) == "function" or type(v) == "table")
        end
        -- Java-exposed enums / singletons: just must be non-nil
        for _, path in ipairs({
            "CharacterStat.HUNGER", "CharacterStat.THIRST", "MoodleType.FOOD_EATEN",
            "FluidCategory.Beverage",
            "CFarmingSystem.instance", "RainManager",
        }) do
            check("chore.sym." .. path, resolve(path) ~= nil)
        end
        -- ItemTag.CAN_OPENER is NOT referenced anywhere in vanilla 42.22.2 Lua, so 14_AutoNeeds detects an opener by
        -- tag first, then by item type name (TinOpener / CanOpener). Only a WARN: sealed cans then rely on the name.
        if resolve("ItemTag.CAN_OPENER") == nil then
            print("[EmpireTest] WARN chore.sym.ItemTag.CAN_OPENER -- absent; auto-needs finds the can opener by item type name instead")
        end
        pcall(function()
            local fs = CFarmingSystem and CFarmingSystem.instance
            check("chore.farm.registry", fs ~= nil and type(fs.getLuaObjectCount) == "function" and type(fs.getLuaObjectByIndex) == "function",
                "auto-farm walks the vanilla plant registry through these two calls")
        end)
        pcall(function()
            local st = getSpecificPlayer(0):getStats()
            check("chore.stats.hungerThirst", type(st:get(CharacterStat.HUNGER)) == "number" and type(st:get(CharacterStat.THIRST)) == "number",
                "auto-needs reads hunger/thirst through Stats:get(CharacterStat.X)")
        end)
    end

    -- T3/T4: the Papa Humvee craft recipes and part items. Only meaningful when Papa_Chad's
    -- M998 mod is enabled AND the optional recipe script (empire_M998_papa_recipes.txt, shipped
    -- as .off) has been switched on. EmpirePlay uses KI5's M998 instead, so skip cleanly.
    local papaLoaded = false
    pcall(function() papaLoaded = getScriptManager():getItem("Base.M998_Bull_Bar2") ~= nil end)
    if not papaLoaded then
        print("[EmpireTest] SKIP recipe.Empire_M998_* / item.Base.M998_* -- Papa_Chad M998 mod not loaded (expected in EmpirePlay)")
    else
        local recipes = { "Empire_M998_MakeBullBar", "Empire_M998_MakeM2Armor",
            "Empire_M998_MakeTurretArmor", "Empire_M998_MakeMuffler",
            "Empire_M998_MakeSpareTireCarrier" }
        for _, r in ipairs(recipes) do
            local found = false
            pcall(function() found = getScriptManager():getCraftRecipe(r) ~= nil end)
            check("recipe." .. r, found)
        end

        local items = { "Base.M998_Bull_Bar2", "Base.M998_M2_Armor_Green2",
            "Base.M998_Turret_Armor_Green2", "Base.M998_Muffler2",
            "Base.M998_Spare_Tire_Carrier2" }
        for _, ft in ipairs(items) do
            local it = nil
            pcall(function() it = instanceItem(ft) end)
            check("item." .. ft, it ~= nil, it and it:getDisplayName() or "not spawnable")
        end
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
