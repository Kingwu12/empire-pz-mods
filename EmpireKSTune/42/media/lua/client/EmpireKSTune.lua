-- Empire KS Tune: runtime overrides for Knox Survivors sandbox balance.
-- KS reads balance via KS.GetOption -> SandboxVars.KnoxSurvivors[name], live on
-- every call. Sandbox vars are baked into the save at world creation, so we
-- re-assert our preferred values at game start. Works on an EXISTING save, fully
-- reversible (disable this mod to revert), and never touches KS's own files.

EmpireKSTune = EmpireKSTune or {}
local M = EmpireKSTune

-- Edit these freely. Each line is "KS sandbox option = our value".
-- Comment a line out to leave KS's saved value untouched.
M.overrides = {
    -- COMBAT tuning only -- cheap, adds NO extra rendered bodies. Safe to keep.
    SurvivorDamageMultiplier = 1.60,  -- KS default 0.75
    RetreatHealthPercent     = 25,    -- KS default 35

    -- DURABILITY: KS survivors are zombie-SHELLS the mod puppets; when a big hit (esp.
    -- a vehicle) blows past their health, KS loses control and the shell reverts to a
    -- hostile zombie in your base. Making the shells tanky keeps KS in control through
    -- bumps + combat, so far fewer "turned into a zombie for no reason" events.
    -- (Won't save them from a full-speed truck -- nothing will -- but stops the glancing
    -- hits and combat scratches that were reverting them.)
    SurvivorDurabilityMultiplier = 2.5,  -- KS default 1.0 (min 0.5). Raise toward 3-4 if
                                          -- they still revert too easily; lower if they
                                          -- feel unkillable in fights.

    -- BODY-COUNT knobs REVERTED to KS defaults. Raising these keeps more
    -- survivors fully rendered/animated near you = engine render cost, which is
    -- the FPS bottleneck. Left off until FPS is fixed.
    -- DormantActorDistance  = 200,   -- KS default 110  (reverted)
    -- BaseMarkerRadius      = 15,    -- KS default 9    (reverted)
    -- MaxBaseRadius         = 32,    -- KS default 24   (reverted)
}

function M.apply()
    SandboxVars = SandboxVars or {}
    local ks = SandboxVars.KnoxSurvivors
    if not ks then
        print("[EmpireKSTune] KnoxSurvivors sandbox not present - nothing to tune.")
        return false
    end
    local n = 0
    for name, value in pairs(M.overrides) do
        ks[name] = value
        n = n + 1
    end
    print("[EmpireKSTune] applied " .. tostring(n) .. " KS override(s).")
    return true
end

-- apply once the save's sandbox is loaded
Events.OnGameStart.Add(function() M.apply() end)

print("[EmpireKSTune] loaded. Edit M.overrides, reload, then call EmpireKSTune.apply() in the debug console to re-apply live.")
