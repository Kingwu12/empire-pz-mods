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
    -- stop survivors vanishing while you move around a large base
    DormantActorDistance     = 200,   -- KS default 110
    -- make survivors actually useful in a fight (still below player damage)
    SurvivorDamageMultiplier = 1.10,  -- KS default 0.75
    -- they hold the line a little longer before fleeing
    RetreatHealthPercent     = 25,    -- KS default 35
    -- treat more of your base as "home" (better base behaviour + cleanup margin)
    BaseMarkerRadius         = 15,    -- KS default 9
    MaxBaseRadius            = 32,    -- KS default 24
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
