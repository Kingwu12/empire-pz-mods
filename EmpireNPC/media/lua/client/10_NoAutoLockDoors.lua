-- Empire NPC - No Random Door Locking
-- SSC auto-runs LockDoorsTask (via AI-Manager) which walks the base CLOSING and LOCKING
-- every unlocked door -- that's the "random" door-closing. We neuter the task so survivors
-- stop doing it. Doors they open to walk through are unaffected (that's engine pathing).
Events.OnGameStart.Add(function()
    if LockDoorsTask and LockDoorsTask.update then
        LockDoorsTask.update = function(self) self.Complete = true; return false end
        print("[EmpireNPC] LockDoorsTask neutered -- no more random door closing/locking.")
    end
end)
