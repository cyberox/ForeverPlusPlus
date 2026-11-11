-- Item Tooltips: lines in item tooltips, each with its own checkbox: the vendor price of the whole
-- stack (SellPrice.lua), what damaged gear costs to repair (RepairCost.lua), how many you own
-- (ItemCount.lua), what disenchanting gives (Disenchant.lua), and the lowest auction house
-- buyout, which other modules read through ns.Prices (AuctionPrices.lua); each stat line in
-- its stat's color (StatColors.lua); and Blizzard's comparison on a bag recipe for gear
-- (CraftedCompare.lua). This file has the settings every line shares; each line is a part of the
-- module (`module:NewPart`) with its own.
local _, ns = ...

local L = ns.L

local module = ns.NewModule("ItemTooltips", L.ITEMTOOLTIPS_DESC, {
    enabled = true,
    -- Every price line
    mode = "stack", -- "stack" (Shift for one) or "one" (Shift for the stack)
    align = "right", -- "right" (at the tooltip's edge) or "inline" (after the label), counts too
})
module.title = L.ITEMTOOLTIPS_TITLE
module.category = "items"

-- Before 0.8.0, Sell Price, Item Count, and Auction Prices were modules of their own. Item
-- Tooltips is on if any of them was, and each keeps its own checkbox, options, and data.
ns.Migrate(1, function(db)
    local saved = db.modules or {}
    local sell, count, auction = saved.SellPrice, saved.ItemCount, saved.AuctionPrices
    if not (sell or count or auction) then
        return
    end
    local db = saved.ItemTooltips or {}
    saved.ItemTooltips = db
    db.enabled = false
    -- The price options are shared now; Sell Price's win, since it's the line most players see.
    for _, name in ipairs({ "AuctionPrices", "ItemCount", "SellPrice" }) do
        local old = saved[name]
        if old then
            ns.MoveSettings(old, db, { "mode", "align" })
            db.enabled = db.enabled or old.enabled ~= false
        end
    end
    if sell then
        ns.MoveSettings(sell, db, { sellPrice = "enabled", sellPriceColor = "color" })
    end
    if count then
        ns.MoveSettings(count, db, { itemCount = "enabled", "bank", "labels", "banks" })
    end
    if auction then
        ns.MoveSettings(auction, db, { auction = "enabled", auctionColor = "color", "scanAge",
            "scanAgeColor", "scanAgeRedHours", "crafting", "scanOnOpen", "chat", "vendor", "houses" })
    end
    saved.SellPrice, saved.ItemCount, saved.AuctionPrices = nil, nil, nil
end)
module.internal = {}

-- The color a price line's quantity takes, for the parts' Color options.
module.internal.COLORS = {
    { "gray", L.PRICE_COLOR_GRAY },
    { "white", L.PRICE_COLOR_WHITE },
    { "gold", L.PRICE_COLOR_GOLD },
}

-- The settings every line shares first; each part (Sell Price, Repair Cost, Item Count,
-- Disenchant, Stat Colors, Compare Crafted Gear, Auction Prices, in the TOC's order) adds its
-- section after them, with Auction Prices last for its Chat Messages.
module.options = {
    {
        key = "mode", name = L.PRICE_MODE, description = L.PRICE_MODE_DESC,
        section = L.ITEMTOOLTIPS_SECTION_GENERAL,
        choices = { { "stack", L.PRICE_MODE_STACK }, { "one", L.PRICE_MODE_ONE } },
    },
    {
        key = "align", name = L.PRICE_ALIGN, description = L.PRICE_ALIGN_DESC,
        section = L.ITEMTOOLTIPS_SECTION_GENERAL,
        choices = { { "right", L.PRICE_ALIGN_RIGHT }, { "inline", L.PRICE_ALIGN_INLINE } },
    },
}
