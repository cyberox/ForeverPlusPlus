-- Item Tooltips' New in Forever line: says so, just above the prices, on an item Classic never
-- had (ns.NewItems).
local _, ns = ...

local GREEN_FONT_COLOR = GREEN_FONT_COLOR

local L = ns.L
local ItemTooltip, NewItems = ns.ItemTooltip, ns.NewItems

local module = ns.modules.ItemTooltips:NewPart({
    key = "newItem", name = L.ITEMTOOLTIPS_NEWITEM, description = L.NEWITEM_DESC,
    section = L.NEWITEM_TITLE, added = "1.9.0",
}, {
    newItem = false,
})

-- One word in Blizzard's green, as the game's own tags on an item are ("Heroic").
local function addLine(tooltip, data)
    if not module.enabled then
        return
    end
    if NewItems.Has(ItemTooltip.ItemID(data)) then
        local color = GREEN_FONT_COLOR
        tooltip:AddLine(L.NEWITEM_LINE, color.r, color.g, color.b)
    end
end

function module:OnEnable()
    -- The hook can't be removed; addLine checks the part is on.
    ItemTooltip.OnInfo(addLine, module)
end
