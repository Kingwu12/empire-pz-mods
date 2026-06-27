-- Empire NPC - Context Menu FIXED
-- SSC survivors are IsoPlayer with moddata.ID set by SSM

local function onFillWorldObjectContextMenu(player, context, worldObjects, test)
    if test then return end
    if player ~= 0 then return end
    if not SSM then return end

    local square = GetMouseSquare()
    if not square then return end

    -- SSC survivors are IsoPlayer instances with moddata.ID
    local movingObjs = square:getMovingObjects()
    if not movingObjs then return end

    for i = 0, movingObjs:size() - 1 do
        local obj = movingObjs:get(i)
        if obj and instanceof(obj, "IsoPlayer") then
            local md = obj:getModData()
            if md and md.ID ~= nil and md.ID ~= SSM:getRealPlayerID() then
                local ss = SSM:Get(md.ID)
                if ss and not ss:isDead() then
                    local survivorName = ss:getName() or ("Survivor_" .. tostring(md.ID))
                    local settler = EmpireNPC.getSettler(survivorName)
                    local currentRole = settler.role or EmpireNPC.Roles.NONE

                    local empireOption = context:addOption(
                        "[Empire] " .. survivorName .. " - " .. currentRole,
                        nil, nil)
                    local subMenu = ISContextMenu:getNew(context)
                    context:addSubMenu(empireOption, subMenu)

                    -- Role assignment options
                    for roleName, roleValue in pairs(EmpireNPC.Roles) do
                        if roleValue ~= currentRole then
                            local capturedName = survivorName
                            local capturedRole = roleValue
                            subMenu:addOption(
                                "Assign: " .. roleValue,
                                nil,
                                function()
                                    EmpireNPC.setRole(capturedName, capturedRole)
                                    local p = getSpecificPlayer(0)
                                    if p then
                                        HaloTextHelper.addText(p,
                                            capturedName .. " is now a " .. capturedRole,
                                            HaloTextHelper.getColorGreen())
                                    end
                                end
                            )
                        end
                    end

                    -- Set guard post at player position
                    subMenu:addOption(
                        "Set Guard Post Here",
                        nil,
                        function()
                            local p = getSpecificPlayer(0)
                            if not p then return end
                            local postIdx = EmpireNPC.addGuardPost(
                                math.floor(p:getX()),
                                math.floor(p:getY()),
                                math.floor(p:getZ()))
                            local s = EmpireNPC.getSettler(survivorName)
                            s.guardPost = EmpireNPC.guardPosts[postIdx]
                            s.role = EmpireNPC.Roles.GUARD
                            EmpireNPC.saveData()
                            HaloTextHelper.addText(p,
                                survivorName .. " will guard this position",
                                HaloTextHelper.getColorGreen())
                        end
                    )

                    -- Looter supply run
                    if currentRole == EmpireNPC.Roles.LOOTER then
                        subMenu:addOption(
                            "Send on Supply Run",
                            nil,
                            function()
                                local p = getSpecificPlayer(0)
                                if not p then return end
                                local s = EmpireNPC.getSettler(survivorName)
                                s.onRun = true
                                s.runReturnTick = 3600
                                EmpireNPC.saveData()
                                HaloTextHelper.addText(p,
                                    survivorName .. " departed on supply run",
                                    HaloTextHelper.getColorYellow())
                            end
                        )
                    end

                    break
                end
            end
        end
    end
end

Events.OnFillWorldObjectContextMenu.Add(function(player, context, worldObjects, test)
    local __t0 = getTimestampMs()
    onFillWorldObjectContextMenu(player, context, worldObjects, test)
    local __dt = getTimestampMs() - __t0
    if EMPIRE_DEBUG_ON ~= false and __dt >= 1 then print("[EMPIRE-DEBUG]   H EmpireNPC: " .. __dt .. "ms") end
end)
print("[EmpireNPC] Context Menu loaded.")
