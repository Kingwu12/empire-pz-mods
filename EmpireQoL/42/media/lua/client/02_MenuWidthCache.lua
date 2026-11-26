-- Empire QoL - Context Menu Width Cache  (THE fix for the right-click freeze)
--
-- ROOT CAUSE (measured via 90_MenuProfiler): the world right-click builds ~844 menu options
-- -- your full Build catalog (MoreBuilds + Improved Build Menu + Hydrocraft) plus the
-- SuperbSurvivors area-select block. Vanilla ISContextMenu:addOption recomputes the menu
-- WIDTH on EVERY option added, and ISContextMenu:calcWidth loops EVERY option calling
-- getTextManager():MeasureStringX (an expensive text-layout call). So N options cost ~N*N
-- string measurements: 844^2 ~= 700,000 measurements per right-click = the 1-9 second freeze.
-- (calcHeight is cheap; calcWidth is the whole cost. It scales with menu size, which is why
-- it felt tied to how much was around you.)
--
-- FIX: memoize the per-label text measurement. calcWidth still loops the current options and
-- returns the EXACT same width (so removals/changes stay correct), but each distinct label is
-- measured once and cached instead of thousands of times. O(N^2) text layout -> ~unique-labels
-- measurements + cheap cache hits. Nothing is removed, no behaviour changes, and it speeds up
-- EVERY mod's context menu. Fully reversible: delete this file.

local measureCache = {}   -- [font] -> { [labelString] = widthPixels }
local arrowCache = {}     -- [font] -> width of the ">" submenu arrow

local function install()
    if EMPIRE_MENU_WIDTH_FIX then return end
    if type(ISContextMenu) ~= "table" then return end
    EMPIRE_MENU_WIDTH_FIX = true

    -- 42.22.2 pass: vanilla's width formula changed (icon-aware: it reserves room for the
    -- option icon and the ">" arrow, and reads self.itemHgt). Verified against the real
    -- 42.22.2 ISContextMenu.lua (calcWidth at ~line 616). The old override returned
    -- maxWidth + 64, which would clip icons / text on 42.22. The loop below is the same
    -- cached measurement; only the final formula mirrors vanilla exactly.
    function ISContextMenu:calcWidth()
        local tm = getTextManager()
        local font = self.font
        local cache = measureCache[font]
        if not cache then cache = {}; measureCache[font] = cache end
        local maxWidth = 0
        for _, k in ipairs(self.options) do
            local nm = k.name or ""
            local w = cache[nm]
            if w == nil then
                w = tm:MeasureStringX(font, nm)
                cache[nm] = w
            end
            if w > maxWidth then maxWidth = w end
        end
        local arrowW = arrowCache[font]
        if arrowW == nil then
            arrowW = tm:MeasureStringX(font, ">")
            arrowCache[font] = arrowW
        end
        local iconSize = (self.itemHgt or 0) - 12
        local iconShiftX = 2
        local textForIconShift = iconSize + iconShiftX * 2 + 2
        return math.max(textForIconShift + maxWidth + 24 + arrowW + 4, 100)
    end

    print("[EmpireQoL] Context-menu width cache installed -- right-click no longer re-measures every option N^2 times. THIS is the lag fix.")
end

Events.OnGameStart.Add(install)
