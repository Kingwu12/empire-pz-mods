-- Empire Perf :: 21_SquareHookTrim.lua
-- Kills the per-square (LoadGridsquare) work of mods whose content King keeps
-- loaded for save integrity but whose runtime he doesn't use. Every streamed
-- tile fires ALL registered LoadGridsquare handlers on the main thread; at
-- driving speed that's hundreds of tiles/sec -> streaming starves -> black
-- chunks. This trims the fat without uninstalling anything.
--
-- 1) TchernoLib SSpawn: handler is global-reachable (Spawn.spawnOnLoadGridsquare)
--    -> FULLY unregistered via Events.LoadGridsquare.Remove (Tcherno's own
--    removal path, SSpawn.lua:59 does the identical call).
-- 2) TchernoLib SGlobalObjectCreator: anonymous closures guard on
--    SGOSystems[key].instance:OnLoadGridSquare -> neutered by no-op'ing the
--    method on each instance. Tank objects stay in-world and error-free;
--    they just stop reconnecting (feature unused).
-- 3) More Damaged Objects: handlers are locals (can't unregister) but all
--    real work flows through MDO_SpriteData lookups -> stub to return nil.
--    Already-damaged tiles keep rendering (tilesheets stay loaded); no new
--    per-square replacement work.

local function trim()
    -- (1) Tcherno spawn scan: full unregister
    pcall(function()
        if Spawn and Spawn.spawnOnLoadGridsquare then
            Events.LoadGridsquare.Remove(Spawn.spawnOnLoadGridsquare)
            print("[EmpirePerf] Trim: TchernoLib SSpawn LoadGridsquare handler removed")
        end
    end)
    -- (2) Tcherno global-object systems: neuter per-square reconnect
    pcall(function()
        if SGOSystems then
            local n = 0
            for _, rec in pairs(SGOSystems) do
                local inst = rec and rec.instance
                if inst and inst.OnLoadGridSquare then
                    inst.OnLoadGridSquare = function() end
                    n = n + 1
                end
            end
            if n > 0 then print("[EmpirePerf] Trim: neutered " .. n .. " SGO OnLoadGridSquare handler(s)") end
        end
    end)
    -- (3) MDO: stub the sprite-data lookups its square handlers run
    pcall(function()
        if MDO_SpriteData then
            if MDO_SpriteData.getSpriteDataByBaseSprite then
                MDO_SpriteData.getSpriteDataByBaseSprite = function() return nil end
            end
            if MDO_SpriteData.getSpriteDataFromNewStandpipeSprite then
                MDO_SpriteData.getSpriteDataFromNewStandpipeSprite = function() return nil end
            end
            print("[EmpirePerf] Trim: MDO sprite lookups stubbed (existing damage keeps rendering)")
        end
    end)
end

-- OnGameStart runs after every mod has initialised and registered its events,
-- so removals/stubs land on the final handler set. Re-run is harmless.
Events.OnGameStart.Add(function() pcall(trim) end)
