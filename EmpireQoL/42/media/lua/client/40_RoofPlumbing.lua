-- Empire QoL - Roof Plumbing (realistic)
-- Connect a sink to your roof rain collectors. Vanilla only links a sink to a collector on the
-- EXACT tile directly above it; this links a sink to ANY collector above it in the same building.
-- It does NOT make the tap infinite. A pump tops the sink's OWN water store from the roof tanks
-- every in-game while, and the roof tanks DRAIN by exactly what it moves -- so the tanks deplete
-- as you use the taps, and run dry until it rains again. Roof water is rain => tainted; boil it.

local SCAN_FLOORS_UP = 4     -- floors above the sink to search for collectors
local SINK_BUFFER    = 25    -- water to keep sitting in a connected sink
local MAX_PER_TICK   = 25    -- cap on water moved into one sink per pump cycle
local REG_KEY        = "EmpireRoofSinks"

--===================== detection helpers =====================

-- A rain collector barrel stores waterMax in its modData (SRainBarrelSystem object keys).
local function isRainCollector(o)
    local md = o:getModData()
    return md and md.waterMax ~= nil
end

-- Footprint of the sink's building (falls back to a tight box if not a mapped building).
local function buildingBox(sq)
    local r = 10
    local x0,y0,x1,y1 = sq:getX()-r, sq:getY()-r, sq:getX()+r, sq:getY()+r
    pcall(function()
        local bld = sq:getBuilding()
        local def = bld and bld:getDef()
        if def then
            local bx,by,bw,bh = def:getX(), def:getY(), def:getW(), def:getH()
            if bx and by and bw and bh then x0,y0,x1,y1 = bx,by,bx+bw-1,by+bh-1 end
        end
    end)
    return x0,y0,x1,y1
end

-- All rain-collector ISO objects on floors above the sink, inside the building footprint.
local function roofCollectors(sq)
    local out = {}
    local cell = getCell(); if not cell then return out end
    local x0,y0,x1,y1 = buildingBox(sq)
    local z0 = sq:getZ() + 1
    for z = z0, z0 + SCAN_FLOORS_UP - 1 do
        for x = x0, x1 do
            for y = y0, y1 do
                local s = cell:getGridSquare(x,y,z)
                if s then
                    local objs = s:getObjects()
                    for i=0,objs:size()-1 do
                        local o = objs:get(i)
                        if isRainCollector(o) then out[#out+1] = o end
                    end
                end
            end
        end
    end
    return out
end

local function isPlumbableSink(obj)
    if not obj then return false end
    local piped = false
    pcall(function()
        local props = obj:getProperties()
        if props and props:has(IsoFlagType.waterPiped) then piped = true end
    end)
    if not piped then
        local md = obj:getModData()
        if md and (md.canBeWaterPiped == true or md.empireRoofSink == true) then piped = true end
    end
    return piped
end

local function hasPipeWrench(playerObj)
    local inv = playerObj:getInventory()
    if inv:containsTypeRecurse("PipeWrench") then return true end
    local ok,r = pcall(function() return inv:containsTagRecurse("PipeWrench") end)
    return ok and r or false
end

--===================== registry of connected sinks (persisted) =====================

local function registry() return ModData.getOrCreate(REG_KEY) end
local function keyFor(sq) return sq:getX()..","..sq:getY()..","..sq:getZ() end

local function registerSink(obj)
    local sq = obj:getSquare(); if not sq then return end
    obj:getModData().empireRoofSink = true
    pcall(function() obj:transmitModData() end)
    registry()[keyFor(sq)] = true
end

--===================== connect action (pipe wrench) =====================

ISEmpireRoofConnect = ISBaseTimedAction:derive("ISEmpireRoofConnect")
function ISEmpireRoofConnect:isValid() return self.character:isEquipped(self.wrench) end
function ISEmpireRoofConnect:update()
    self.character:faceThisObject(self.sink)
    self.character:setMetabolicTarget(Metabolics.MediumWork)
end
function ISEmpireRoofConnect:start() self.sound = self.character:playSound("RepairWithWrench") end
function ISEmpireRoofConnect:stop() self.character:stopOrTriggerSound(self.sound); ISBaseTimedAction.stop(self) end
function ISEmpireRoofConnect:perform() self.character:stopOrTriggerSound(self.sound); ISBaseTimedAction.perform(self) end
function ISEmpireRoofConnect:complete() registerSink(self.sink); return true end
function ISEmpireRoofConnect:getDuration() return self.character:isTimedActionInstant() and 1 or 100 end
function ISEmpireRoofConnect:new(character, sink, wrench)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character; o.sink = sink; o.wrench = wrench
    o.maxTime = o:getDuration()
    return o
end

--===================== context menu =====================

local function onConnect(worldobjects, player, sink)
    local playerObj = getSpecificPlayer(player)
    local wrench = playerObj:getInventory():getFirstTypeRecurse("PipeWrench")
    if not wrench then pcall(function() wrench = playerObj:getInventory():getFirstTagRecurse("PipeWrench") end) end
    if not wrench then return end
    ISWorldObjectContextMenu.equip(playerObj, playerObj:getPrimaryHandItem(), wrench, true)
    ISTimedActionQueue.add(ISEmpireRoofConnect:new(playerObj, sink, wrench))
end

local function onFill(player, context, worldobjects, test)
    local playerObj = getSpecificPlayer(player); if not playerObj then return end
    local sink = nil
    for _,o in ipairs(worldobjects) do
        if isPlumbableSink(o) then sink = o; break end
    end
    if not sink then return end
    if sink:getModData().empireRoofSink == true then return end   -- already connected
    if not hasPipeWrench(playerObj) then return end
    if #roofCollectors(sink:getSquare()) == 0 then return end
    context:addOption("Empire: Connect to roof tanks", worldobjects, onConnect, player, sink)
end

Events.OnFillWorldObjectContextMenu.Add(onFill)

--===================== the pump (timer) =====================

local function totalWater(barrels)
    local t = 0
    for _,b in ipairs(barrels) do t = t + (b:getFluidAmount() or 0) end
    return t
end

local function drainBarrels(barrels, amount)
    local remaining = amount
    for _,b in ipairs(barrels) do
        if remaining <= 0 then break end
        local cur = b:getFluidAmount() or 0
        if cur > 0 then
            local take = math.min(cur, remaining)
            local left = cur - take
            b:emptyFluid()
            if left > 0 then b:addFluid(FluidType.TaintedWater, left) end
            pcall(function() b:transmitModData() end)
            pcall(function()
                if SRainBarrelSystem and SRainBarrelSystem.instance then
                    local sb = b:getSquare()
                    local lo = SRainBarrelSystem.instance:getLuaObjectAt(sb:getX(), sb:getY(), sb:getZ())
                    if lo then lo.waterAmount = left end
                end
            end)
            remaining = remaining - take
        end
    end
end

-- Top one connected sink up from its roof tanks. Returns false if the sink is gone.
local function pumpSink(sq)
    local objs = sq:getObjects()
    local sink = nil
    for i=0,objs:size()-1 do
        local o = objs:get(i)
        if o:getModData() and o:getModData().empireRoofSink == true then sink = o; break end
    end
    if not sink then return false end                 -- sink removed -> drop from registry
    local cur = sink:getFluidAmount() or 0
    local need = SINK_BUFFER - cur
    if need <= 0 then return true end                 -- still full (or on mains) -> nothing to do
    if need > MAX_PER_TICK then need = MAX_PER_TICK end
    local barrels = roofCollectors(sq)
    if totalWater(barrels) <= 0 then return true end  -- tanks dry -> tap runs dry as used
    local before = sink:getFluidAmount() or 0
    sink:addFluid(FluidType.TaintedWater, need)        -- engine clamps to the sink's capacity
    local landed = (sink:getFluidAmount() or 0) - before
    if landed > 0 then
        drainBarrels(barrels, landed)                 -- drain tanks by exactly what landed
        pcall(function() sink:transmitModData() end)
    end
    return true
end

local function EveryTenMinutes()
    local reg = registry()
    local cell = getCell(); if not cell then return end
    for key,_ in pairs(reg) do
        local x,y,z = key:match("(-?%d+),(-?%d+),(-?%d+)")
        if x then
            local sq = cell:getGridSquare(tonumber(x), tonumber(y), tonumber(z))
            if sq then                                -- nil square = chunk not loaded; keep for later
                if pumpSink(sq) == false then reg[key] = nil end
            end
        else
            reg[key] = nil
        end
    end
end

Events.EveryTenMinutes.Add(EveryTenMinutes)

print("[EmpireQoL] Roof Plumbing (realistic) loaded: connect a sink to roof tanks; tanks drain as you use it.")
