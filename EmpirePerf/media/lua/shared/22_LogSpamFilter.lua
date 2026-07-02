-- Empire Perf :: 22_LogSpamFilter.lua
-- Some mods shipped with debug prints left ON. Every print = string format +
-- console write + disk IO on the main thread, and the worst offenders fire
-- PER TRIGGER-CHECK DURING COMBAT (HF Point Blank: 550+ lines/session) or per
-- burst (RAF firerate). Invisible pure waste -- exactly the cut policy.
-- This wraps global print with an exact-prefix denylist. Anything else passes
-- through untouched, so real logs (Empire, errors, other mods) are unaffected.

local DENY_PREFIX = {
    "PointBlankCanTriggerCheck",          -- HF_PointBlankMod combat-loop debug
    "SetPendingPointBlankTarget",         -- HF_PointBlankMod combat-loop debug
    "RAF Og",                             -- RAF_Real_Automatic_Firerate burst debug
}

local _origPrint = print
local function filteredPrint(first, ...)
    if type(first) == "string" then
        for i = 1, #DENY_PREFIX do
            local p = DENY_PREFIX[i]
            if first:sub(1, #p) == p then return end   -- dropped: known spam
        end
    end
    return _origPrint(first, ...)
end
print = filteredPrint

_origPrint("[EmpirePerf] Log-spam filter active (" .. #DENY_PREFIX .. " known debug-spam prefixes dropped)")
