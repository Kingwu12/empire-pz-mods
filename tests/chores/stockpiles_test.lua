-- EmpireStockpiles against the REAL vanilla tables.
-- SRC  = EmpireStockpiles.lua
-- SRC2 = vanilla ProceduralDistributions.lua, SRC3 = vanilla Distributions.lua (42.22.2)
local checks, fails = 0, 0
local function ok(c, msg) checks = checks + 1; if not c then fails = fails + 1; (print_real or print)("FAIL " .. msg) end end

-- mock the event bus; capture handlers
local handlers = {}
local function ev(name) return { Add = function(f) handlers[name] = handlers[name] or {}; table.insert(handlers[name], f) end } end
Events = { OnPreDistributionMerge = ev("pre"), OnPostDistributionMerge = ev("post") }
local printed = {}
print_real = print
print = function(s) table.insert(printed, tostring(s)) end

-- vanilla files reference globals defined elsewhere in the game; stub them as empty tables
local function anyTable() return setmetatable({}, { __index = function(t, k) local v = anyTable(); rawset(t, k, v); return v end }) end
Distributions = {}
setmetatable(_G, { __index = function(t, k) if type(k) == "string" and k:match("^%u") then return anyTable() end end })
assert(load(SRC2))()   -- vanilla ProceduralDistributions
assert(load(SRC3))()   -- vanilla Distributions (room table)
setmetatable(_G, nil)
local PD = ProceduralDistributions.list
local rooms = Distributions[1]

local before = {}
for _, n in ipairs({ "GunStoreAmmunition", "ArmyStorageAmmunition", "PoliceStorageAmmunition", "PoliceEvidence", "GarageFirearms" }) do
  before[n] = PD[n].rolls
end
local sidetableN = #PD.BedroomSidetable.items
local garageW = {}; for i = 1, #PD.GarageFirearms.items - 1, 2 do garageW[PD.GarageFirearms.items[i]] = PD.GarageFirearms.items[i + 1] end
local trimmedBefore = #PD.GunStoreAmmunition.items

assert(load(SRC))()
ok(handlers.pre and #handlers.pre == 1, "registers on OnPreDistributionMerge")
ok(PD.GunStoreAmmunition.rolls == before.GunStoreAmmunition, "nothing changes until the event fires")

for _, f in ipairs(handlers.pre) do f() end
for _, f in ipairs(handlers.post) do f() end   -- second call must be a no-op

ok(PD.GunStoreAmmunition.rolls == 10, "gun store ammo rolls 4 -> 10, got " .. tostring(PD.GunStoreAmmunition.rolls))
ok(PD.ArmyStorageAmmunition.rolls == 12, "army ammo rolls 4 -> 12, got " .. tostring(PD.ArmyStorageAmmunition.rolls))
ok(PD.PoliceStorageAmmunition.rolls == 12, "police ammo rolls 4 -> 12")
ok(PD.PoliceEvidence.rolls == 3, "police evidence rolls 1 -> 3")
ok(PD.GarageFirearms.rolls == 6, "garage firearms rolls 4 -> 6")
ok(#PD.GunStoreAmmunition.items == trimmedBefore, "store item list is not inflated")
ok(#PD.BedroomSidetable.items == sidetableN + 4, "two home ammo entries added to the bedside table, once")
ok(PD.GarageFirearms.items[2] ~= nil, "garage items intact")
local g2 = {}; for i = 1, #PD.GarageFirearms.items - 1, 2 do g2[PD.GarageFirearms.items[i]] = PD.GarageFirearms.items[i + 1] end
ok(g2.Revolver == garageW.Revolver * 1.5, "garage gun weight x1.5 (Revolver " .. tostring(garageW.Revolver) .. " -> " .. tostring(g2.Revolver) .. ")")
ok(g2.TissueBox == nil or g2.TissueBox == garageW.TissueBox, "non-arms entries untouched")

-- port rooms
ok(rooms.armyhanger == rooms.armystorage, "armyhanger aliases armystorage")
ok(rooms.gunstorage == rooms.gunstorestorage, "gunstorage aliases gunstorestorage")
local ind = rooms.industrialstorage
ok(ind ~= nil and ind ~= rooms.warehouse, "industrialstorage is its own copy of warehouse")
local found, cont = 0, 0
for k, c in pairs(ind) do
  if type(c) == "table" and c.procedural and c.procList then
    cont = cont + 1
    for _, p in ipairs(c.procList) do if p.name == "ArmyStorageAmmunition" then found = found + 1 end end
  end
end
ok(cont > 0 and found == cont, "every procedural cargo container can roll an army shipment (" .. found .. "/" .. cont .. ")")
local whHas = false
for _, c in pairs(rooms.warehouse) do
  if type(c) == "table" and c.procList then for _, p in ipairs(c.procList) do if p.name == "ArmyStorageAmmunition" then whHas = true end end end
end
ok(not whHas, "vanilla warehouse not polluted by the copy")
local msg = printed[#printed] or ""
ok(string.find(msg, "[EmpireStockpiles] applied", 1, true) ~= nil, "logs one summary line")
ok(string.find(msg, "port rooms", 1, true) ~= nil, "summary mentions port rooms")
print = print_real
print(msg)
print(checks .. " checks, " .. fails .. " failed")
if fails > 0 then os.exit(1) end
