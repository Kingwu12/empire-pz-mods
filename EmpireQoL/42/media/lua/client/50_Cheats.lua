-- Empire QoL :: 50_Cheats.lua  (28 Nov 2026, B42.22)
-- King: "how do i cheat in items did you also make our own?"  (and earlier: "i just want to cheat in the big truck")
-- No debug flag needed. The game's own cheat windows are ordinary Lua UIs that the debug menu merely hides
-- behind -debug; opening them needs no debug check (ISItemsListViewer.OnOpenPanel, ISSpawnVehicleUI:new), and
-- what they call in single player (instanceItem + AddItem, addVehicle) has no debug gate in the 42.22.2 jar.
-- This file is only the door: a right-click submenu and two keys. No per-frame work.
--   Numpad 4  Item list: type a name in the filter box, double-click an item to add it, right-click for x2/x5/xN.
--             Lists every item of every enabled mod (screwdriver, Marz guns, ammo cartons...). The first open
--             builds the list of all items, so allow a second.
--   Numpad 6  Spawn vehicle window: pick a vehicle (Tatra815 and the rest), Spawn puts it next to you;
--             Get Key gives the key of the vehicle beside you, Repair fixes it.
--   Right-click > Empire: Cheats > the same two, plus a switch for "zombies attack my walls" (below).
--   Walls switch: ZombieLore.ThumpOnConstruction. OFF = zombies leave player-built walls, fences and doors alone
--   (the base stays up while you are away; zombies only chase you). Same call the game's own sandbox panel uses
--   (getSandboxOptions():set + toLua), so it persists in the save like the debug Sandbox panel would.

EmpireCheats = EmpireCheats or {}
local C = EmpireCheats
local vehUI = nil

function C.openItems()
    if not (ISItemsListViewer and ISItemsListViewer.OnOpenPanel) then
        print("[EmpireCheats] ISItemsListViewer is missing in this build")
        return false
    end
    ISItemsListViewer.OnOpenPanel()
    return true
end

function C.openVehicles()
    if not (ISSpawnVehicleUI and ISSpawnVehicleUI.new) then
        print("[EmpireCheats] ISSpawnVehicleUI is missing in this build")
        return false
    end
    local p = getSpecificPlayer(0)
    if not p then return false end
    if vehUI then pcall(function() vehUI:destroy() end) end   -- one window at a time
    vehUI = ISSpawnVehicleUI:new(0, 0, 200, 300, p)
    vehUI:initialise()
    vehUI:addToUIManager()
    return true
end

local THUMP = "ZombieLore.ThumpOnConstruction"

local function say(player, msg, kind)
    if player then
        pcall(function()
            local c = HaloTextHelper.getColorWhite()
            if kind == "ok" then c = HaloTextHelper.getColorGreen()
            elseif kind == "bad" then c = HaloTextHelper.getColorRed() end
            HaloTextHelper.addTextWithArrow(player, msg, "[br/]", false, c)
        end)
    end
    print("[EmpireCheats] " .. msg)
end

-- true = zombies can destroy player builds, false = they leave them alone, nil = unknown
function C.thumpOn()
    local v
    pcall(function() v = getSandboxOptions():getOptionByName(THUMP):getValue() end)
    return v
end

function C.setThump(player, on)
    local ok = pcall(function()
        local so = getSandboxOptions()
        so:getOptionByName(THUMP):setValue(on)
        so:set(THUMP, on)
        so:toLua()
    end)
    local now = C.thumpOn()
    if ok and now == on then
        say(player, on and "Zombies attack your walls again" or "Zombies now leave your walls alone", "ok")
    else
        say(player, "Could not change the walls setting (see console)", "bad")
    end
    return ok and now == on
end

function C.toggleThump(player)
    local cur = C.thumpOn()
    if cur == nil then say(player, "Walls setting not found in this build", "bad"); return false end
    return C.setThump(player, not cur)
end

Events.OnFillWorldObjectContextMenu.Add(function(playerNum, context, worldobjects, test)
    if test then return end
    local p = getSpecificPlayer(playerNum)
    if not p then return end
    local opt = context:addOption("Empire: Cheats")
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(opt, sub)
    sub:addOption("Item list (search, double-click adds)", p, C.openItems)
    sub:addOption("Spawn a vehicle (key + repair buttons)", p, C.openVehicles)
    local cur = C.thumpOn()
    if cur ~= nil then
        sub:addOption(cur and "Zombies attack my walls: ON (click: leave them alone)"
                          or "Zombies leave my walls alone: ON (click: attack again)", p, C.toggleThump)
    end
end)

Events.OnKeyPressed.Add(function(key)
    local k4, k6 = 75, 77   -- lwjgl KEY_NUMPAD4 / KEY_NUMPAD6
    pcall(function()
        if Keyboard and Keyboard.KEY_NUMPAD4 then k4 = Keyboard.KEY_NUMPAD4 end
        if Keyboard and Keyboard.KEY_NUMPAD6 then k6 = Keyboard.KEY_NUMPAD6 end
    end)
    if key == k4 then pcall(C.openItems) elseif key == k6 then pcall(C.openVehicles) end
end)

print("[EmpireQoL] Cheats loaded: Numpad 4 = item list, Numpad 6 = spawn vehicle, right-click > Empire: Cheats")
