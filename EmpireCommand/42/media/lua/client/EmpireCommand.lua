-- ============================================================
-- Empire Command : a clean roster/command window for Knox Survivors.
-- Reads KS's own global data API (KS.GetOwnedProfiles etc.) and calls its global
-- command functions. Does NOT touch KS files. We hijack KS.OpenRoster at game
-- start so the existing roster key (default U) opens this window instead.
-- Fix vs KS's window: 2 readable lines + a health bar per row (not 5 overlapping
-- text lines), proper row height, command buttons.
-- ============================================================
require "ISUI/ISCollapsableWindow"

EmpireCommand = EmpireCommand or {}
local EC = EmpireCommand

local FONT_MED   = UIFont.Medium
local FONT_SMALL = UIFont.Small
local ROW_H      = 56

-- guarded KS call: ks("GetOwnedProfiles", player) -> result or nil, never throws
local function ks(name, ...)
    local fn = KS and KS[name]
    if type(fn) ~= "function" then return nil end
    local ok, res = pcall(fn, ...)
    if ok then return res end
    return nil
end

local Window = ISCollapsableWindow:derive("EmpireCommandWindow")

-- ---------- selection helpers ----------
function Window:selectedProfile()
    local it = self.list and self.list.items[self.list.selected]
    return it and it.item or nil
end

-- ---------- commands (mirror KS_RosterUI, fully guarded) ----------
function Window:cmdFollow()
    local p = self:selectedProfile(); if not p then return end
    p.job = "idle"
    ks("SetOrder", p, "follow")
    ks("Notify", self.player, (p.name or "Survivor") .. ": Follow Me.")
    self:refresh()
end

function Window:cmdBase()
    local p = self:selectedProfile(); if not p then return end
    local base = ks("GetPlayerBase", self.player)
    if not base then ks("Notify", self.player, "Set a base first."); return end
    p.job = "guard"; p.command = "guard"
    p.anchor = { x = base.x, y = base.y, z = base.z }
    p.destination = nil; p.destinationUntil = nil
    if KS and KS.GetWorldHours then pcall(function() p.orderChangedAt = KS.GetWorldHours() end) end
    if KS and KS.Authority and KS.Authority.CommitProfile then
        pcall(function() KS.Authority.CommitProfile(p, "empire-base") end)
    end
    ks("Notify", self.player, (p.name or "Survivor") .. ": Return to Base.")
    self:refresh()
end

function Window:cmdRest()
    local p = self:selectedProfile(); if not p then return end
    ks("AssignProfileJob", self.player, p, "rest", ks("GetActor", p.id))
    self:refresh()
end

function Window:cmdCallHere()
    local p = self:selectedProfile(); if not p then return end
    local actor = ks("GetActor", p.id)
    if actor then ks("CallActorHere", self.player, actor)
    else ks("Notify", self.player, "That survivor is not active/visible.") end
    self:refresh()
end

function Window:cmdUnstick()
    local p = self:selectedProfile(); if not p then return end
    local actor = ks("GetActor", p.id)
    if actor then ks("UnstickActor", self.player, actor)
    else ks("Notify", self.player, "That survivor is not active/visible.") end
    self:refresh()
end

function Window:cmdPolicy()
    local p = self:selectedProfile(); if not p then return end
    local next = (p.combatPolicy == "hold" and "defend")
        or (p.combatPolicy == "defend" and "aggressive")
        or "hold"
    p.combatPolicy = next
    if KS and KS.Authority and KS.Authority.CommitProfile then
        pcall(function() KS.Authority.CommitProfile(p, "empire-policy") end)
    end
    ks("Notify", self.player, (p.name or "Survivor") .. " combat policy: " .. next .. ".")
    self:refresh()
end

-- ---------- row rendering: 2 clean lines + a health bar ----------
function Window:drawRow(lst, y, item, alt)
    local p = item.item
    local w = lst:getWidth()
    local selected = (lst.selected == item.index)
    if selected then
        lst:drawRect(0, y, w, ROW_H - 2, 0.45, 0.32, 0.30, 0.52)
    elseif alt then
        lst:drawRect(0, y, w, ROW_H - 2, 0.40, 0.12, 0.12, 0.12)
    end
    lst:drawRectBorder(0, y, w, ROW_H - 2, 0.25, 0.45, 0.45, 0.55)

    -- line 1: name + role
    local role = ks("GetSurvivorRoleLabel", p) or p.role or "Survivor"
    lst:drawText((p.name or "Survivor") .. "    " .. role, 10, y + 4, 0.96, 0.96, 0.96, 1, FONT_MED)

    -- health bar
    local hp = (p.maxHealth and p.maxHealth > 0) and (p.health / p.maxHealth * 100) or 100
    local frac = math.max(0, math.min(1, hp / 100))
    local bx, by, bw, bh = 10, y + 26, 150, 10
    lst:drawRect(bx, by, bw, bh, 0.6, 0.10, 0.10, 0.10)
    lst:drawRect(bx, by, bw * frac, bh, 0.9, (1 - frac) * 0.75 + 0.15, frac * 0.65 + 0.15, 0.18)
    lst:drawRectBorder(bx, by, bw, bh, 0.5, 0.4, 0.4, 0.4)
    lst:drawText(string.format("HP %d%%", math.floor(hp)), bx + bw + 8, y + 23, 0.82, 0.86, 0.82, 1, FONT_SMALL)
    lst:drawText(string.format("Morale %d%%", math.floor(p.morale or 0)), bx + bw + 88, y + 23, 0.80, 0.80, 0.88, 1, FONT_SMALL)

    -- line 2: command | job | needs | policy
    local n = p.needs or {}
    local detail = string.format("%s  |  %s  |  Hun %d  Thr %d  Fat %d  |  %s",
        p.command or "idle",
        ks("GetJobLabel", p.job) or p.job or "idle",
        math.floor(n.hunger or 0), math.floor(n.thirst or 0), math.floor(n.fatigue or 0),
        p.combatPolicy or "defend")
    lst:drawText(detail, 10, y + ROW_H - 22, 0.70, 0.80, 0.72, 1, FONT_SMALL)
    return y + ROW_H
end

-- ---------- data refresh ----------
function Window:refresh()
    local prevId = nil
    local cur = self.list and self.list.items[self.list.selected]
    if cur and cur.item then prevId = cur.item.id end
    self.list:clear()
    local profiles = ks("GetOwnedProfiles", self.player) or {}
    for _, p in ipairs(profiles) do self.list:addItem(p.name or "Survivor", p) end
    if prevId then
        for i, it in ipairs(self.list.items) do
            if it.item and it.item.id == prevId then self.list.selected = i; break end
        end
    end
    if (self.list.selected or 0) < 1 and #self.list.items > 0 then self.list.selected = 1 end
    self.lastRefresh = ks("GetTimestamp") or 0
end

-- ---------- layout (re-flows on resize) ----------
function Window:layout()
    local pad, btnH, gap, cols = 10, 28, 6, 3
    local barH = 2 * btnH + 3 * gap
    local top = (self.titleBarHeight and self:titleBarHeight() or 16) + pad
    if self.list then
        self.list:setX(pad); self.list:setY(top)
        self.list:setWidth(self.width - pad * 2)
        self.list:setHeight(math.max(60, self.height - top - barH - pad))
    end
    local areaW = self.width - pad * 2
    local bw = (areaW - (cols - 1) * gap) / cols
    local by0 = self.height - barH + gap
    for i, b in ipairs(self.buttons or {}) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        b:setX(pad + col * (bw + gap)); b:setY(by0 + row * (btnH + gap))
        b:setWidth(bw); b:setHeight(btnH)
    end
end

-- ---------- build ----------
function Window:createChildren()
    ISCollapsableWindow.createChildren(self)
    local top = (self.titleBarHeight and self:titleBarHeight() or 16) + 10
    self.list = ISScrollingListBox:new(10, top, self.width - 20, 200)
    self.list:initialise(); self.list:instantiate()
    self.list.itemheight = ROW_H
    self.list.selected = 1
    self.list.drawBorder = true
    self.list.doDrawItem = function(lst, y, item, alt) return self:drawRow(lst, y, item, alt) end
    self:addChild(self.list)

    self.buttons = {}
    local defs = {
        { "Follow Me",      self.cmdFollow },
        { "Return to Base", self.cmdBase },
        { "Rest",           self.cmdRest },
        { "Call Here",      self.cmdCallHere },
        { "Unstick",        self.cmdUnstick },
        { "Combat Policy",  self.cmdPolicy },
    }
    for _, d in ipairs(defs) do
        local btn = ISButton:new(0, 0, 80, 28, d[1], self, d[2])
        btn:initialise(); btn:instantiate()
        self:addChild(btn)
        self.buttons[#self.buttons + 1] = btn
    end
    self:layout()
    self:refresh()
end

function Window:prerender()
    ISCollapsableWindow.prerender(self)
    self:layout()
    local t = ks("GetTimestamp") or 0
    if t - (self.lastRefresh or 0) > 2000 then self:refresh() end
end

function Window:close()
    self:setVisible(false)
    self:removeFromUIManager()
    EmpireCommand.instance = nil
end

function Window:new(player)
    local w, h = 760, 520
    local sw = getCore() and getCore():getScreenWidth() or 1280
    local sh = getCore() and getCore():getScreenHeight() or 720
    local o = ISCollapsableWindow.new(self, math.max(20, (sw - w) / 2), math.max(20, (sh - h) / 2), w, h)
    o.player = player
    o.title = "Empire Command"
    o.resizable = true
    return o
end

-- ---------- entry point ----------
function EmpireCommand.open(player)
    if EmpireCommand.instance then EmpireCommand.instance:close(); return end -- toggle
    local win = Window:new(player)
    win:initialise(); win:addToUIManager()
    EmpireCommand.instance = win
end

-- hijack KS's roster entry AFTER all mods load, so the existing U key opens ours
Events.OnGameStart.Add(function()
    if KS then
        KS.OpenRoster = function(player) EmpireCommand.open(player or getSpecificPlayer(0)) end
        print("[EmpireCommand] active - U key opens Empire Command.")
    else
        print("[EmpireCommand] KnoxSurvivors not present; window idle.")
    end
end)
