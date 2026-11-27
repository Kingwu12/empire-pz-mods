-- Mock test for EmpireSortAll_Client.lua (the sorter): the automation options of smartSort / EmpireSortAll.run
--   carriedOnly, sources, noCarried, itemFilter, quiet, plus the freeOf memo and the 30 s category-count cache,
--   and "no opts = the old behaviour" checked against the unpatched sorter.
-- Run (SRC = sorter, SRC2 = config, SRC3 = the sorter BEFORE the opts patch; SRC3 is optional, the A/B checks are skipped without it):
--   node tests/chores/runner.js EmpireSortAll/42/media/lua/client/EmpireSortAll_Client.lua tests/chores/sorter_test.lua \
--        EmpireSortAll/42/media/lua/client/EmpireSortAll_Config.lua /path/to/EmpireSortAll_Client.orig.lua
-- The sorter swallows most errors in pcall, so every scenario asserts that items really moved (the mocks reach the code).
local realPrint = print
local diag = {}
print = function(...)   -- the sorter prints a DIAG line per container per run; keep them out of the test output
  local t = {}
  for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end
  diag[#diag + 1] = table.concat(t, " ")
end

Events = setmetatable({}, {__index = function(t, name)
  local e = {Add = function() end}; rawset(t, name, e); return e end})
Keyboard = {KEY_NUMPAD3 = 51}
local NOW = 5000000
function getTimestampMs() return NOW end
local WORLD, mdStore
mdStore = {}
ModData = {getOrCreate = function(k) mdStore[k] = mdStore[k] or {}; return mdStore[k] end}
local function halo(_, msg) table.insert(WORLD.halos, msg) end
HaloTextHelper = {addTextWithArrow = halo, addGoodText = halo, addBadText = halo,
  getColorGreen = function() return 1 end, getColorRed = function() return 2 end, getColorWhite = function() return 3 end}

-- ---- mocks (same style as production_test.lua) ----
local function obj(p, kind)
  local o = {p = p, kind = kind}
  return setmetatable(o, {__index = function(_, k) return function(self, ...) local v = p[k]; if type(v) == "function" then return v(self, ...) end; return v end end})
end
function instanceof(o, cls) return o ~= nil and type(o) == "table" and rawget(o, "kind") == cls end

local CAT = {Hammer = "Tool", Screws = "Material", Nails = "Material", Book = "Literature", Apple = "Food",
  Bullets9mm = "Ammo", Bullets45 = "Ammo"}
local function item(ft, o)
  o = o or {}
  local tp = (ft:gsub("^.-%.", ""))
  local cat = o.cat or CAT[tp]
  local kind = o.kind or (cat == "Food" and "Food") or nil
  local p = {getFullType = ft, getType = tp, getName = tp, getDisplayCategory = cat, getActualWeight = o.w or 1,
    isFavorite = o.fav or false, isEquipped = o.equipped or false, isRotten = o.rotten or false}
  for k, v in pairs(o.extra or {}) do p[k] = v end
  return obj(p, kind)
end
local function wOf(it) local w = it.p.getActualWeight; return type(w) == "number" and w or 1 end

-- container with real add/remove/contains, weight capacity, and read counters (reads = items:get() calls)
local function cont(name, o)
  o = o or {}
  local c = {name = name, list = {}, cap = o.cap or 1000, ctype = o.ctype or "crate", lie = o.lie, allow = o.allow, reads = 0}
  local view = {
    size = function() return #c.list end,
    get = function(_, i) c.reads = c.reads + 1; return c.list[i + 1] end,
    isEmpty = function() return #c.list == 0 end,
  }
  function c:getItems() return view end
  function c:getCapacityWeight() local s = 0; for _, x in ipairs(c.list) do s = s + wOf(x) end return s end
  function c:getEffectiveCapacity() return c.cap end
  function c:getCapacity() return c.cap end
  function c:getType() return c.ctype end
  function c:getParent() return c.parentObj end
  function c:addItem(it) c.list[#c.list + 1] = it end
  function c:Remove(it) for i, x in ipairs(c.list) do if x == it then table.remove(c.list, i); return end end end
  function c:contains(it) for _, x in ipairs(c.list) do if x == it then return true end end return false end
  function c:isItemAllowed(it) if c.allow then return c.allow(it) end return true end
  function c:hasRoomFor(_, it) if c.lie then return true end return c:getCapacityWeight() + wOf(it) <= c.cap + 0.001 end
  function c:setDrawDirty() end
  return c
end
local function fill(c, ft, n, o) local out = {}; for _ = 1, n or 1 do local it = item(ft, o); c:addItem(it); out[#out + 1] = it end return out end
local function fillU(c, prefix, n, cat, w)   -- n items of n DISTINCT types (nothing for consolidate to merge)
  for i = 1, n do c:addItem(item("Base." .. prefix .. i, {cat = cat, w = w})) end
end
local function count(c, ft) local n = 0; for _, x in ipairs(c.list) do if x.p.getFullType == ft then n = n + 1 end end return n end
local function countPre(c, prefix) local n = 0; for _, x in ipairs(c.list) do if x.p.getFullType:find("^Base%." .. prefix) then n = n + 1 end end return n end
local function weightOf(c) return c:getCapacityWeight() end

local function list(t) return {size = function() return #t end, get = function(_, i) return t[i + 1] end} end
local function sqAt(x, y, z)
  z = z or 0
  local key = x .. "," .. y .. "," .. z
  if WORLD.squares[key] then return WORLD.squares[key] end
  local sq = {objs = {}, wobjs = {}}
  function sq:getX() return x end
  function sq:getY() return y end
  function sq:getZ() return z end
  function sq:getObjects() return list(sq.objs) end
  function sq:getWorldObjects() return list(sq.wobjs) end
  function sq:getRoom() return nil end
  function sq:AddWorldInventoryItem(it) sq.wobjs[#sq.wobjs + 1] = obj({getItem = it}); return it end
  function sq:transmitRemoveItemFromSquare(wo) for i, w in ipairs(sq.wobjs) do if w == wo then table.remove(sq.wobjs, i); return end end end
  WORLD.squares[key] = sq
  return sq
end
function getCell() return {getGridSquare = function(_, x, y, z) return WORLD.squares[x .. "," .. y .. "," .. z] end} end
local function onFloor(sq, it) sq.wobjs[#sq.wobjs + 1] = obj({getItem = it}); return it end
local function floorCount(ft)
  local n = 0
  for _, sq in pairs(WORLD.squares) do for _, wo in ipairs(sq.wobjs) do local it = wo:getItem(); if it and it.p.getFullType == ft then n = n + 1 end end end
  return n
end

-- a furniture object holding one container; tag = persisted lock (position key, same format as the sorter's containerKey)
local function store(name, x, y, ctype, o)
  o = o or {}
  local c = cont(name, {cap = o.cap, ctype = ctype, lie = o.lie, allow = o.allow})
  local sq = sqAt(x, y, 0)
  local ob = obj({getContainer = c, getContainerCount = 1, getContainerByIndex = c, getSquare = sq, getModData = o.md or {}})
  c.parentObj = ob
  sq.objs[#sq.objs + 1] = ob
  if o.tag then
    mdStore.EmpireStorageTags = mdStore.EmpireStorageTags or {}
    mdStore.EmpireStorageTags[x .. "|" .. y .. "|0|" .. ctype] = o.tag
  end
  WORLD.named[name] = c
  return c
end
-- an ammo can SET DOWN on a bench: a world item, scanned as a placed Ammo home
local function placedCan(x, y, cap)
  local c = cont("can", {cap = cap, ctype = "AmmoCan", allow = function(it) return it.p.getDisplayCategory == "Ammo" end})
  local canItem = obj({getType = "AmmoCan", getFullType = "Base.AmmoCan", getModData = {}, getInventory = c}, "InventoryContainer")
  sqAt(x, y, 0).wobjs[#sqAt(x, y, 0).wobjs + 1] = obj({getItem = canItem})
  WORLD.named.can = c
  return c
end

local P = {}
function P:isDead() return false end
function P:getInventory() return WORLD.inv end
function P:getCurrentSquare() return WORLD.psq end
function P:getPrimaryHandItem() return WORLD.hand end
function P:getSecondaryHandItem() return nil end
function P:Say(s) table.insert(WORLD.says, s) end
function getSpecificPlayer() return P end

-- a fresh world: the clock jumps far ahead so the sorter's 20 s scan cache and 30 s count cache start empty
local function newWorld()
  NOW = NOW + 1000000
  WORLD = {squares = {}, named = {}, halos = {}, says = {}}
  mdStore = {}
  WORLD.psq = sqAt(11, 12, 0)
  WORLD.inv = cont("inv", {cap = 500, ctype = "inventory"})
  return WORLD
end
local function hasHalo(s) for _, m in ipairs(WORLD.halos) do if m:find(s, 1, true) then return true end end return false end
local function hasSay(s) for _, m in ipairs(WORLD.says) do if m:find(s, 1, true) then return true end end return false end

-- content signature of a whole world, for the A/B comparison
local function sigOf(c)
  local t = {}
  for _, it in ipairs(c.list) do t[#t + 1] = it.p.getFullType .. (it.p.isFavorite and "*" or "") .. (it.p.isRotten and "!" or "") end
  table.sort(t)
  return table.concat(t, ",")
end
local function worldSig()
  local names = {}
  for n in pairs(WORLD.named) do names[#names + 1] = n end
  table.sort(names)
  local out = {}
  for _, n in ipairs(names) do out[#out + 1] = n .. "=[" .. sigOf(WORLD.named[n]) .. "]" end
  out[#out + 1] = "inv=[" .. sigOf(WORLD.inv) .. "]"
  local fl = {}
  for _, sq in pairs(WORLD.squares) do for _, wo in ipairs(sq.wobjs) do
    local it = wo:getItem()
    if it and not instanceof(it, "InventoryContainer") then fl[#fl + 1] = it.p.getFullType .. (it.p.isRotten and "!" or "") end
  end end
  table.sort(fl)
  out[#out + 1] = "floor=[" .. table.concat(fl, ",") .. "]"
  return table.concat(out, " ")
end

-- ---- load the sources ----
local function loadSorter(src, name)
  EmpireSortAll = {}   -- each load gets its own table; the module keeps its own upvalues (caches, counters)
  local f, err = load(src, name)
  if not f then return nil, err end
  local ok, e2 = pcall(f)
  if not ok or not EmpireSortAll.run then return nil, e2 or "no EmpireSortAll.run" end
  return EmpireSortAll.run
end
local cf, cerr = load(SRC2, "EmpireSortConfig"); assert(cf, cerr); cf()
local runPatched, perr = loadSorter(SRC, "EmpireSortAll_Client"); assert(runPatched, perr)
local SA_PATCHED = EmpireSortAll   -- the patched module table (transferVehicle); loading SRC3 replaces the global
local runOrig = nil
if type(SRC3) == "string" and #SRC3 > 0 then runOrig = loadSorter(SRC3, "EmpireSortAll_Client.orig") end

local fails, n = 0, 0
local function expect(name, cond, detail)
  n = n + 1
  if cond then realPrint("PASS " .. name)
  else fails = fails + 1; realPrint("FAIL " .. name .. (detail and ("  -- " .. detail) or "")) end
end
local function skip(name) realPrint("SKIP " .. name .. " (no unpatched sorter given as SRC3)") end
local RUN = runPatched
local function sortWith(run, opts) return run(P, opts) end

-- ======================================================================
-- worlds
-- ======================================================================
-- base: a Tools-locked toolbox holding a misfiled Screws, general shelves, a rotten apple, a stray hammer on a shelf,
-- duplicate books over two shelves, a nail on the floor, and a survivor carrying nails + a hammer.
local function baseWorld()
  local W = newWorld()
  local toolbox = store("toolbox", 10, 10, "crate", {tag = "Tools"})
  local shelf1 = store("shelf1", 12, 10, "shelves")
  local shelf2 = store("shelf2", 14, 10, "shelves")
  local shelf3 = store("shelf3", 16, 10, "shelves")
  fill(toolbox, "Base.Hammer"); fill(toolbox, "Base.Screws")
  fill(shelf1, "Base.Nails", 2); fill(shelf1, "Base.Apple", 1, {rotten = true})
  fill(shelf2, "Base.Book", 2)
  fill(shelf3, "Base.Book", 1); fill(shelf3, "Base.Hammer", 1)   -- the stray hammer
  onFloor(sqAt(11, 11, 0), item("Base.Nails"))
  fill(W.inv, "Base.Nails", 3); fill(W.inv, "Base.Hammer", 1)
  return W
end
-- empty-handed tidy: misfiled fresh apple in the locked toolbox, stray hammer on a shelf
local function tidyWorld()
  local W = newWorld()
  local toolbox = store("toolbox", 10, 10, "crate", {tag = "Tools"})
  local shelf1 = store("shelf1", 12, 10, "shelves")
  local shelf2 = store("shelf2", 14, 10, "shelves")
  fill(toolbox, "Base.Hammer"); fill(toolbox, "Base.Apple")
  fill(shelf1, "Base.Nails", 2); fill(shelf1, "Base.Hammer", 1)
  fill(shelf2, "Base.Book", 2)
  return W
end

-- ======================================================================
-- 1. no opts = old behaviour (and A/B against the unpatched sorter)
-- ======================================================================
do
  baseWorld()
  local ret = sortWith(RUN)
  local W = WORLD
  local tb, s1, s2, s3 = W.named.toolbox, W.named.shelf1, W.named.shelf2, W.named.shelf3
  local patchedSig = worldSig()
  expect("1 no opts: run returns true and the carried nails + hammer are filed (inventory emptied)", ret == true and #W.inv.list == 0 and count(s1, "Base.Nails") >= 5, worldSig())
  expect("1 no opts: misfiled Screws evicted from the locked toolbox", count(tb, "Base.Screws") == 0 and count(s1, "Base.Screws") == 1, worldSig())
  expect("1 no opts: magnet pulls the stray hammer and the carried one into the toolbox", count(tb, "Base.Hammer") == 3 and count(s3, "Base.Hammer") == 0, worldSig())
  expect("1 no opts: rotten apple purged off the shelf, floor nail picked up",
    count(s1, "Base.Apple") == 0 and floorCount("Base.Apple") == 1 and floorCount("Base.Nails") == 0, worldSig())
  expect("1 no opts: consolidate ran (duplicate books merged, CONSOLIDATED halo)", count(s2, "Base.Book") == 3 and #s3.list == 0 and hasHalo("CONSOLIDATED"), worldSig())
  if runOrig then
    baseWorld(); local r2 = sortWith(runOrig); local origSig = worldSig()
    expect("1 A/B: no opts leaves exactly the same contents as the unpatched sorter", r2 == true and patchedSig == origSig, patchedSig .. "  VS  " .. origSig)
  else skip("1 A/B base world") end

  -- empty-handed full tidy
  tidyWorld(); local ret2 = sortWith(RUN); local tb2, s1b = WORLD.named.toolbox, WORLD.named.shelf1
  local tsig = worldSig()
  expect("1b no opts, empty-handed: misfiled apple leaves the toolbox, stray hammer comes in",
    ret2 == true and count(tb2, "Base.Apple") == 0 and count(tb2, "Base.Hammer") == 2 and count(s1b, "Base.Hammer") == 0, tsig)
  if runOrig then
    tidyWorld(); sortWith(runOrig); local osig = worldSig()
    expect("1b A/B: empty-handed tidy identical to the unpatched sorter", tsig == osig, tsig .. "  VS  " .. osig)
  else skip("1b A/B tidy world") end
  tidyWorld(); local before = worldSig(); sortWith(RUN, {carriedOnly = true})
  expect("1b carriedOnly with nothing carried changes nothing", worldSig() == before, worldSig())
end

-- ======================================================================
-- 2. carriedOnly = deposit only
-- ======================================================================
do
  baseWorld()
  local ret = sortWith(RUN, {carriedOnly = true})
  local W = WORLD
  local tb, s1, s2, s3 = W.named.toolbox, W.named.shelf1, W.named.shelf2, W.named.shelf3
  expect("2 carriedOnly: run returns true, the carried nails are still filed and the carried hammer goes to the locked toolbox",
    ret == true and #W.inv.list == 0 and count(s1, "Base.Nails") == 5 and count(tb, "Base.Hammer") == 2, worldSig())
  expect("2 carriedOnly: the misfiled Screws stay in the toolbox (no eviction)", count(tb, "Base.Screws") == 1 and count(s1, "Base.Screws") == 0, worldSig())
  expect("2 carriedOnly: the stray hammer on a shelf is not magnet-pulled", count(s3, "Base.Hammer") == 1, worldSig())
  expect("2 carriedOnly: the rotten apple is not purged and nothing is dropped", count(s1, "Base.Apple") == 1 and floorCount("Base.Apple") == 0, worldSig())
  expect("2 carriedOnly: the floor nail is not picked up", floorCount("Base.Nails") == 1, worldSig())
  expect("2 carriedOnly: consolidateTypes does not run (books stay split, no consolidate halo)",
    count(s2, "Base.Book") == 2 and count(s3, "Base.Book") == 1 and not hasHalo("CONSOLIDATED") and not hasHalo("Already consolidated"), worldSig())

  -- placed ammo can restock
  local function canWorld(carryNails)
    local W2 = newWorld()
    local shelf1 = store("shelf1", 12, 10, "shelves")
    fill(shelf1, "Base.Bullets9mm", 4); fill(shelf1, "Base.Nails", 1)
    placedCan(13, 11, 10)
    if carryNails then fill(W2.inv, "Base.Nails", 1) end
    return W2
  end
  canWorld(false); sortWith(RUN)
  expect("2b no opts, empty-handed: the placed ammo can pulls the shelf's ammo (restock runs)", count(WORLD.named.can, "Base.Bullets9mm") == 4, worldSig())
  -- empty-handed on purpose: with something in the pack the carry-scope gate would skip the restock even without carriedOnly
  canWorld(false); local r3 = sortWith(RUN, {carriedOnly = true})
  expect("2b carriedOnly: the placed-can restock is skipped (ammo stays on the shelf, can stays empty)",
    r3 == true and count(WORLD.named.shelf1, "Base.Bullets9mm") == 4 and #WORLD.named.can.list == 0, worldSig())
  canWorld(true); sortWith(RUN, {carriedOnly = true})
  expect("2b carriedOnly with a carried nail: the nail is filed, the can is still not restocked",
    #WORLD.inv.list == 0 and count(WORLD.named.shelf1, "Base.Nails") == 2 and #WORLD.named.can.list == 0, worldSig())

  -- over-capacity shed: empty-handed, a 3-weight shelf holding 5 books
  local function shedWorld()
    local W2 = newWorld()
    local a = store("shelfA", 10, 10, "shelves", {cap = 3}); fillU(a, "Bk", 5, "Literature")
    local b = store("shelfB", 12, 10, "shelves"); fill(b, "Base.Nails", 1)
    return W2
  end
  shedWorld(); sortWith(RUN)
  expect("2c no opts: an over-capacity shelf sheds down to its cap (shed runs)", countPre(WORLD.named.shelfA, "Bk") == 3 and countPre(WORLD.named.shelfB, "Bk") == 2, worldSig())
  local ps = worldSig()
  if runOrig then
    shedWorld(); sortWith(runOrig)
    expect("2c A/B: the shed result equals the unpatched sorter", ps == worldSig(), ps .. "  VS  " .. worldSig())
  else skip("2c A/B shed world") end
  shedWorld(); sortWith(RUN, {carriedOnly = true})
  expect("2c carriedOnly: the over-capacity shelf is left alone (no shed)", countPre(WORLD.named.shelfA, "Bk") == 5 and countPre(WORLD.named.shelfB, "Bk") == 0, worldSig())

  -- compost routing (PASS A): a rotten apple on a shelf goes into the composter on a full tidy, stays on a deposit-only run
  local function compostWorld()
    local W2 = newWorld()
    local sh = store("shelf1", 10, 10, "shelves"); fill(sh, "Base.Nails", 1); fill(sh, "Base.Apple", 1, {rotten = true})
    store("composter", 12, 10, "composter", {cap = 39})
    return W2
  end
  compostWorld(); sortWith(RUN)
  expect("2c no opts: the rotten apple is routed into the composter (compost routing runs)", count(WORLD.named.composter, "Base.Apple") == 1 and floorCount("Base.Apple") == 0, worldSig())
  compostWorld(); sortWith(RUN, {carriedOnly = true})
  expect("2c carriedOnly: no compost routing, the rotten apple stays on the shelf", count(WORLD.named.composter, "Base.Apple") == 0 and count(WORLD.named.shelf1, "Base.Apple") == 1 and floorCount("Base.Apple") == 0, worldSig())

  -- rotten food in the pack: a deposit-only run has no rot purge (PASS A), so it must not shelve rot next to fresh food;
  -- the rotten apple stays in the pack until a full sort purges it. (The unpatched sorter filed it and purged it afterwards.)
  local function rotWorld()
    local W2 = newWorld()
    local fr = store("fridge", 10, 10, "fridge"); fill(fr, "Base.Apple", 1)
    store("shelf1", 12, 10, "shelves")
    fill(W2.inv, "Base.Apple", 1, {rotten = true})
    return W2
  end
  local W2 = rotWorld(); sortWith(RUN, {carriedOnly = true})
  expect("2d carriedOnly leaves a carried ROTTEN apple in the pack: the fridge keeps only the fresh one", count(WORLD.named.fridge, "Base.Apple") == 1 and count(W2.inv, "Base.Apple") == 1 and floorCount("Base.Apple") == 0, worldSig())
  rotWorld(); sortWith(RUN)
  expect("2d no opts: the same rotten apple ends up on the floor, fridge keeps only the fresh one", count(WORLD.named.fridge, "Base.Apple") == 1 and floorCount("Base.Apple") == 1, worldSig())
end

-- ======================================================================
-- 3. sources / noCarried / itemFilter
-- ======================================================================
local function nodeWorld()
  local W = newWorld()
  store("toolbox", 10, 10, "crate", {tag = "Tools"})
  store("ammobox", 12, 10, "crate", {tag = "Ammo"})
  local shelf1 = store("shelf1", 14, 10, "shelves"); fill(shelf1, "Base.Nails", 2)
  local node = store("node", 16, 12, "crate", {md = {EmpireProd = {recipe = "charcoal"}}})   -- a production node: excluded from the store scan
  fill(node, "Base.Nails", 3); fill(node, "Base.Nails", 1, {fav = true}); fill(node, "Base.Hammer", 1); fill(node, "Base.Bullets9mm", 4)
  local gun = item("Base.Pistol", {kind = "HandWeapon", equipped = true, extra = {isRanged = true, getAmmoType = "Base.Bullets9mm"}})
  W.inv:addItem(gun); W.hand = gun    -- a pistol in the hand: its ammo type is gun loadout
  fill(W.inv, "Base.Nails", 2); fill(W.inv, "Base.Bullets9mm", 5); fill(W.inv, "Base.Hammer", 1)
  return W
end
local function filterNailsAmmo(it) local ft = it:getFullType(); return ft == "Base.Nails" or ft == "Base.Bullets9mm" end
local function filterHammer(it) return it:getFullType() == "Base.Hammer" end
do
  local W = nodeWorld()
  local node, shelf1, ammobox, tb = W.named.node, W.named.shelf1, W.named.ammobox, W.named.toolbox
  local ret = sortWith(RUN, {carriedOnly = true, sources = {node}, noCarried = true, itemFilter = filterNailsAmmo})
  expect("3 sources: only the matching items leave the node (3 nails to the shelf, 4 rounds of the pistol's ammo type to the ammo box)",
    ret == true and count(shelf1, "Base.Nails") == 5 and count(ammobox, "Base.Bullets9mm") == 4 and count(node, "Base.Nails") == 1 and count(node, "Base.Bullets9mm") == 0, worldSig())
  expect("3 sources: the non-matching hammer and the favourite nail stay in the node, nothing is deposited into the node",
    count(node, "Base.Hammer") == 1 and #node.list == 2 and (node.list[1].p.isFavorite == true or node.list[2].p.isFavorite == true) and #tb.list == 0, worldSig())
  expect("3 noCarried: the survivor's own inventory is untouched",
    #W.inv.list == 9 and count(W.inv, "Base.Nails") == 2 and count(W.inv, "Base.Bullets9mm") == 5 and count(W.inv, "Base.Hammer") == 1, worldSig())

  W = nodeWorld(); node, shelf1, ammobox, tb = W.named.node, W.named.shelf1, W.named.ammobox, W.named.toolbox
  sortWith(RUN, {carriedOnly = true, itemFilter = filterNailsAmmo})
  expect("3 carried + filter: carried nails filed, loadout rounds in the pack are NOT, filtered-out hammer stays, unlisted node untouched",
    count(shelf1, "Base.Nails") == 4 and count(W.inv, "Base.Bullets9mm") == 5 and count(ammobox, "Base.Bullets9mm") == 0 and count(W.inv, "Base.Hammer") == 1 and count(tb, "Base.Hammer") == 0
      and #node.list == 9, worldSig())   -- the node, not listed as a source, is left alone

  W = nodeWorld(); node, shelf1, ammobox, tb = W.named.node, W.named.shelf1, W.named.ammobox, W.named.toolbox
  sortWith(RUN, {carriedOnly = true, sources = {node}, itemFilter = filterNailsAmmo})
  expect("3 sources + carried: node rounds filed, the pack's own loadout rounds are not (same type, same run)",
    count(ammobox, "Base.Bullets9mm") == 4 and count(W.inv, "Base.Bullets9mm") == 5 and count(shelf1, "Base.Nails") == 7 and count(W.inv, "Base.Nails") == 0, worldSig())

  W = nodeWorld(); node, shelf1, ammobox, tb = W.named.node, W.named.shelf1, W.named.ammobox, W.named.toolbox
  sortWith(RUN, {carriedOnly = true, itemFilter = filterHammer})
  expect("3 filter applies to carried items: only the hammer is filed, to the locked toolbox",
    count(tb, "Base.Hammer") == 1 and count(W.inv, "Base.Hammer") == 0 and count(W.inv, "Base.Nails") == 2 and count(shelf1, "Base.Nails") == 2, worldSig())

  W = nodeWorld(); local before = worldSig()
  sortWith(RUN, {carriedOnly = true, noCarried = true})
  expect("3 noCarried without sources moves nothing", worldSig() == before, worldSig())
end

-- ======================================================================
-- 4. quiet / carriedOnly chatter
-- ======================================================================
local function sortedWorld()
  local W = newWorld()
  local toolbox = store("toolbox", 10, 10, "crate", {tag = "Tools"}); fill(toolbox, "Base.Hammer")
  local shelf1 = store("shelf1", 12, 10, "shelves"); fill(shelf1, "Base.Nails", 2)
  return W
end
do
  sortedWorld(); sortWith(RUN)
  expect("4 no opts, nothing to move: 'Nothing to move' halo and Say", hasHalo("Nothing to move - already sorted") and hasSay("Storage's already in order."), table.concat(WORLD.halos, " | "))
  sortedWorld(); sortWith(RUN, {carriedOnly = true})
  expect("4 carriedOnly, nothing to move: silent", not hasHalo("Nothing to move") and not hasSay("already in order"), table.concat(WORLD.halos, " | "))
  sortedWorld(); sortWith(RUN, {quiet = true})
  expect("4 quiet, nothing to move: silent", not hasHalo("Nothing to move") and not hasSay("already in order"), table.concat(WORLD.halos, " | "))
  newWorld(); sortWith(RUN)
  expect("4 no opts, no storage: 'No storage nearby' halo and Say", hasHalo("No storage nearby to sort") and hasSay("No storage close enough to sort."))
  newWorld(); sortWith(RUN, {carriedOnly = true}); local a = hasHalo("No storage nearby to sort") or hasSay("No storage close enough to sort.")
  newWorld(); sortWith(RUN, {quiet = true}); local b = hasHalo("No storage nearby to sort") or hasSay("No storage close enough to sort.")
  expect("4 carriedOnly / quiet, no storage: silent", not a and not b)
  baseWorld(); sortWith(RUN, {carriedOnly = true})
  expect("4 quiet only hides idle chatter: a real deposit still reports SORTED", hasHalo("SORTED") and hasSay("Sorted"), table.concat(WORLD.halos, " | "))
  -- the "BASE SORT: <name>" banner also counts as chatter (EmpireBases stub: no scanBounds, so the radius box is used)
  EmpireBases = {activeBase = function() return {name = "Main"} end}
  sortedWorld(); sortWith(RUN); local bannerNoOpts = hasHalo("BASE SORT: Main")
  sortedWorld(); sortWith(RUN, {carriedOnly = true}); local bannerCarried = hasHalo("BASE SORT")
  EmpireBases = nil
  expect("4 the BASE SORT banner shows on a normal sort and not on a carriedOnly beat", bannerNoOpts and not bannerCarried)
end

-- ======================================================================
-- 5. capacity + the freeOf memo
-- ======================================================================
-- 5a: two Ammo-locked crates; the first has room for 2 more, the second is empty. Ammo is fill-one-first, so the
-- fullest box with room goes first; 5 rounds must put 2 in the first and spill 3 to the second.
local function ammoWorld(lieA)
  local W = newWorld()
  local a = store("ammoA", 10, 10, "crate", {tag = "Ammo", cap = 10, lie = lieA})
  store("ammoB", 12, 10, "crate", {tag = "Ammo", cap = 20})
  fillU(a, "Fill", 8, "Ammo")
  fillU(W.inv, "Rnd", 5, "Ammo")
  return W
end
-- 5b: A is the home that already holds the category but is nearly full; B and C are general shelves. Each 2-weight
-- item must go to the shelf with the most free weight AT THAT MOMENT, so B and C alternate (B 11 free, C 10 free).
local function spreadWorld()
  local W = newWorld()
  local a = store("shelfA", 10, 10, "shelves", {cap = 5}); fill(a, "Base.Nails", 3)
  local b = store("shelfB", 12, 10, "shelves", {cap = 20}); fillU(b, "BkB", 9, "Literature")
  local c = store("shelfC", 14, 10, "shelves", {cap = 20}); fillU(c, "BkC", 10, "Literature")
  fillU(W.inv, "Box", 5, "Material", 2)
  return W
end
do
  local W = ammoWorld(false)
  local ret = sortWith(RUN, {carriedOnly = true})
  local a, b = W.named.ammoA, W.named.ammoB
  expect("5a capacity: 5 rounds -> 2 in the nearly full first box, 3 spill to the second",
    ret == true and countPre(a, "Rnd") == 2 and countPre(b, "Rnd") == 3 and #W.inv.list == 0, worldSig())
  W = ammoWorld(true); sortWith(RUN, {carriedOnly = true}); a, b = W.named.ammoA, W.named.ammoB
  expect("5a capacity: a box whose hasRoomFor lies (always true) is still held to its real weight cap",
    countPre(a, "Rnd") == 2 and weightOf(a) <= 10.001 and countPre(b, "Rnd") == 3, worldSig())
  if runOrig then
    ammoWorld(false); sortWith(RUN); local ps = worldSig()
    ammoWorld(false); sortWith(runOrig); local os_ = worldSig()
    expect("5a A/B: same distribution as the unpatched sorter", ps == os_, ps .. "  VS  " .. os_)
  else skip("5a A/B ammo world") end

  W = spreadWorld(); sortWith(RUN, {carriedOnly = true})
  local A, B, C = W.named.shelfA, W.named.shelfB, W.named.shelfC
  expect("5b freeOf memo: after every move the next item goes to the shelf that is NOW emptiest (A 1, B 2, C 2), no box over its cap",
    countPre(A, "Box") == 1 and countPre(B, "Box") == 2 and countPre(C, "Box") == 2
      and weightOf(A) <= 5.001 and weightOf(B) <= 20.001 and weightOf(C) <= 20.001, worldSig())
  if runOrig then
    spreadWorld(); sortWith(RUN); local ps = worldSig()
    spreadWorld(); sortWith(runOrig); local os_ = worldSig()
    expect("5b A/B: the memoised sorter picks the same shelves as the unpatched one", ps == os_, ps .. "  VS  " .. os_)
  else skip("5b A/B spread world") end
  -- mutation check: take the invalidation out of placeInto; the same scenario must now go wrong (B takes everything),
  -- which proves the check above actually exercises the memo.
  local mut, reps = SRC:gsub("touched%[dest%] = true; touched%[fromCont%] = true; freeDirty%(dest, fromCont%); return dest",
    "touched[dest] = true; touched[fromCont] = true; return dest")
  if reps == 1 then
    local runMut = loadSorter(mut, "EmpireSortAll_Client.mutant")
    spreadWorld(); sortWith(runMut, {carriedOnly = true})
    local mB, mC = countPre(WORLD.named.shelfB, "Box"), countPre(WORLD.named.shelfC, "Box")
    expect("5b mutation: without freeDirty in placeInto the spread breaks (check is sensitive to the memo)", mB == 4 and mC == 0, "B=" .. mB .. " C=" .. mC)
  else realPrint("SKIP 5b mutation (placeInto line not found in SRC)") end
end

-- ======================================================================
-- 6. category-count cache (carriedOnly only, 30 s)
-- ======================================================================
do
  local W = newWorld()
  local g1 = store("g1", 10, 10, "shelves"); fill(g1, "Base.Book", 3)
  local g2 = store("g2", 12, 10, "shelves"); fill(g2, "Base.Hammer", 3)
  local g3 = store("g3", 14, 10, "shelves"); fill(g3, "Base.Nails", 4)
  local T0 = NOW
  local function reset() g1.reads, g2.reads, g3.reads = 0, 0, 0 end
  fill(W.inv, "Base.Book", 1); reset()
  local r1 = sortWith(RUN, {carriedOnly = true})
  expect("6 run 1: every general container is counted once (3 + 3 + 4 item reads), the book goes to the book shelf",
    r1 == true and g1.reads == 3 and g2.reads == 3 and g3.reads == 4 and count(g1, "Base.Book") == 4, g1.reads .. "/" .. g2.reads .. "/" .. g3.reads)
  NOW = T0 + 5000; fill(W.inv, "Base.Book", 1); reset()
  sortWith(RUN, {carriedOnly = true})
  expect("6 run 2 (+5 s): the untouched containers are NOT re-read (fewer reads than run 1)", g2.reads == 0 and g3.reads == 0, g1.reads .. "/" .. g2.reads .. "/" .. g3.reads)
  expect("6 run 2 (+5 s): the container run 1 deposited into IS re-counted", g1.reads > 0 and count(g1, "Base.Book") == 5, g1.reads .. "/" .. g2.reads .. "/" .. g3.reads)
  NOW = T0 + 29000; fill(W.inv, "Base.Book", 1); reset()
  sortWith(RUN, {carriedOnly = true})
  expect("6 run 3 (+29 s): still inside the 30 s window, still cached", g2.reads == 0 and g3.reads == 0, g1.reads .. "/" .. g2.reads .. "/" .. g3.reads)
  NOW = T0 + 31000; fill(W.inv, "Base.Book", 1); reset()
  sortWith(RUN, {carriedOnly = true})
  expect("6 run 4 (+31 s): the window is over, everything is counted again", g2.reads == 3 and g3.reads == 4, g1.reads .. "/" .. g2.reads .. "/" .. g3.reads)
end
-- behavioural proof of "cached = stale hints, fresh = real counts": g1 holds a hammer, g2 a book. Run 1 (carriedOnly)
-- fills the cache. Behind the sorter's back the hammer moves to g2. Then a hammer is deposited:
--   carriedOnly within 30 s  -> cached g1 still "holds" a tool, g1 wins the tie -> hammer to g1
--   carriedOnly after 30 s   -> recounted -> g2 (it really holds the tool)
--   no opts (any time)       -> never uses the cache -> g2
local function staleRun(opts, dt)
  local W = newWorld()
  local g1 = store("g1", 10, 10, "shelves"); fill(g1, "Base.Hammer", 1)
  local g2 = store("g2", 12, 10, "shelves"); fill(g2, "Base.Book", 1)
  fill(W.inv, "Base.Book", 1)
  local T = NOW
  sortWith(RUN, {carriedOnly = true})                      -- fills the cache; the book goes to g2 (touched, so g2 is not cached)
  local h = g1.list[1]; g1:Remove(h); g2:addItem(h)        -- the hammer moves without the sorter
  NOW = T + dt
  fill(W.inv, "Base.Hammer", 1)
  sortWith(RUN, opts)
  return g1, g2
end
do
  local g1, g2 = staleRun({carriedOnly = true}, 5000)
  expect("6 carriedOnly within 30 s uses the cached counts (the hint is stale: hammer goes to g1)", count(g1, "Base.Hammer") == 1 and count(g2, "Base.Hammer") == 1, worldSig())
  g1, g2 = staleRun({carriedOnly = true}, 31000)
  expect("6 carriedOnly after 30 s recounts (hammer goes to g2, which really holds the tool)", count(g1, "Base.Hammer") == 0 and count(g2, "Base.Hammer") == 2, worldSig())
  g1, g2 = staleRun(nil, 5000)
  expect("6 a no-opts run always recounts, even with a fresh cache (hammer goes to g2)", count(g1, "Base.Hammer") == 0 and count(g2, "Base.Hammer") == 2, worldSig())
end

-- ======================================================================
-- 7. transferVehicle returns what really LEFT the truck (bug hunt r2: with no base storage in range the
--    auto-unload used to report "Unloaded the vehicle into base storage (N items)" for a truck it never touched)
-- ======================================================================
local function truckWith(nItems)
  local trunk = cont("trunk", {cap = 500, ctype = "TruckBed"})
  fillU(trunk, "Load", nItems, "Literature")
  local part = obj({getItemContainer = trunk})
  return obj({getPartCount = 1, getPartByIndex = part}), trunk
end
do
  newWorld()   -- nothing to file into
  local veh, trunk = truckWith(8)
  local got = SA_PATCHED.transferVehicle(P, veh, 6)
  expect("7 no storage in range: transferVehicle returns 0 and the truck keeps its load", got == 0 and #trunk.list == 8, tostring(got) .. " " .. worldSig())
  newWorld(); store("shelf1", 12, 10, "shelves"); veh, trunk = truckWith(8)
  got = SA_PATCHED.transferVehicle(P, veh, 6)
  expect("7 storage in range: returns the 8 items that left the truck", got == 8 and #trunk.list == 0, tostring(got) .. " " .. worldSig())
  newWorld(); store("shelf1", 12, 10, "shelves"); veh, trunk = truckWith(3)
  expect("7 below minItems: skipped", SA_PATCHED.transferVehicle(P, veh, 6) == 0 and #trunk.list == 3)
  newWorld(); store("shelf1", 12, 10, "shelves"); veh, trunk = truckWith(8)
  local keep = trunk.list[1]
  got = SA_PATCHED.transferVehicle(P, veh, 6, {itemFilter = function(it) return it ~= keep end})
  expect("7 itemFilter: the held item stays in the truck, the count says 7", got == 7 and #trunk.list == 1 and trunk.list[1] == keep, tostring(got) .. " " .. worldSig())
end

realPrint(string.format("%d checks, %d failed", n, fails))
if fails > 0 then os.exit(1) end
