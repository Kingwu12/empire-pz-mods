local handlers = {}
Events = setmetatable({}, {__index=function(t,name) local e={Add=function(f) handlers[name]=handlers[name] or {}; table.insert(handlers[name],f) end}; rawset(t,name,e); return e end})
local md = {}
ModData = {getOrCreate=function(k) md[k]=md[k] or {}; return md[k] end}
getSpecificPlayer = function() return nil end
local f = assert(load(SRC, "core")); f()
local g = assert(load(SRC2, "registry")); g()
local EZ, EB = EmpireZones, EmpireBases
local n, fails = 0, 0
local function expect(name, c) n=n+1; if c then print("PASS "..name) else fails=fails+1; print("FAIL "..name) end end
-- count tile walks via parseKey wrapper
local walks = 0
local origParse = EZ.parseKey
EZ.parseKey = function(k) walks = walks + 1; return origParse(k) end
expect("no zone -> nil", EB.getEmpireZoneBase() == nil)
local id = EZ.newZone("Base", "base")
for x=0,29 do for y=0,29 do EZ.addTile(id, 100+x, 200+y, 0) end end
local b = EB.getEmpireZoneBase()
expect("bounds computed", b and b.x1==100 and b.x2==129 and b.y1==200 and b.y2==229 and b.zmin==0)
local w1 = walks
expect("first read walked tiles", w1 == 900)
for i=1,50 do EB.getEmpireZoneBase() end
expect("50 more reads walked ZERO tiles (cached)", walks == w1)
b.name = "Main"; local b2 = EB.getEmpireZoneBase()
expect("caller annotation does not leak into cache", b2.name == nil)
EZ.addTile(id, 150, 200, 0)
local b3 = EB.getEmpireZoneBase()
expect("addTile invalidates cache", b3.x2 == 150 and walks > w1)
EZ.removeTile(id, 150, 200, 0)
expect("removeTile invalidates", EB.getEmpireZoneBase().x2 == 129)
EZ.delete(id)
expect("delete invalidates -> nil", EB.getEmpireZoneBase() == nil)
local id2 = EZ.newZone("B2", "base"); EZ.addTile(id2, 5, 5, 1); EZ.addTile(id2, 9, 9, 1)
expect("newZone invalidates", EB.getEmpireZoneBase() ~= nil)
-- game start clears cache
for _,h in ipairs(handlers.OnGameStart or {}) do h() end
expect("OnGameStart handler registered and safe", #(handlers.OnGameStart or {}) >= 1)
print(n.." checks, "..fails.." failed"); if fails>0 then error("failures") end
