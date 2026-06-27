-- Empire Eat All: make the normal "Eat" click eat the WHOLE item.
-- No portion submenu (Eat All / Eat Half / Eat Quarter gone).
--
-- The OnFillInventoryObjectContextMenu event fires LATE in the game's
-- createMenu (after the eat option is built), so by the time we run, the
-- vanilla "Eat" parent + its "Eat All" child already exist. We copy the
-- game's own "Eat All" handler (correct opening-recipe + params) straight
-- onto the parent, then remove the submenu. Zero guessing, stays B42-correct.

local EAT_ALL = getText("ContextMenu_Eat_All")

local function onFill(playerNum, context, items)
    if not context or not context.options then return end

    for _, opt in ipairs(context.options) do
        -- a submenu parent looks like: onSelect == nil AND subOption set
        if opt and opt.subOption and opt.onSelect == nil then
            local sub = context:getSubMenu(opt.subOption)
            if sub and sub.options and sub.options[1]
                    and sub.options[1].name == EAT_ALL then
                local eatAll = sub.options[1]
                -- copy the exact eat-all handler + every param onto the parent
                opt.onSelect = eatAll.onSelect
                opt.target   = eatAll.target
                opt.param1   = eatAll.param1
                opt.param2   = eatAll.param2
                opt.param3   = eatAll.param3
                opt.param4   = eatAll.param4
                opt.param5   = eatAll.param5
                opt.param6   = eatAll.param6
                -- delete the submenu so no portion options appear
                opt.subOption = nil
            end
        end
    end
end

Events.OnFillInventoryObjectContextMenu.Add(onFill)
