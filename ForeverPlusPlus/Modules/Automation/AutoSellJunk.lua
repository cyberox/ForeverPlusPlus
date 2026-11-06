-- Auto Sell Junk: sells the gray items in your bags when a merchant opens, and says in chat what
-- they sold for. Hold the Skip Key (Shift by default) while opening the merchant to skip it.
local _, ns = ...

local format, select = string.format, select
local C_Container, C_Item = C_Container, C_Item
local GetNumBuybackItems, GetBuybackItemLink = GetNumBuybackItems, GetBuybackItemLink

local L = ns.L
local money = ns.Money

local LAST_BAG = 5
local BUYBACK_SLOTS = 12 -- the merchant's buyback list holds this many; older sales fall off it

local module = ns.NewModule("AutoSellJunk", L.AUTOSELLJUNK_DESC, {
    enabled = false,
    buybackOnly = true,
    skipKey = "shift",
    chat = true,
})
module.title = L.AUTOSELLJUNK_TITLE
module.category = "automation"

-- Hold Shift to Skip was a checkbox, 0.8.4 and before.
ns.Migrate(1, function(db)
    local saved = db.modules or {}
    ns.Keys.MigrateShift(saved, "AutoSellJunk", "shiftSkips", "skipKey")
end)

module.options = {
    {
        key = "buybackOnly",
        name = L.AUTOSELLJUNK_BUYBACK,
        description = L.AUTOSELLJUNK_BUYBACK_DESC,
        changed = "0.9.0",
    },
    ns.Keys.Option("skipKey", L.SKIP_KEY, L.AUTOSELLJUNK_KEY_DESC, nil, "0.9.0"),
    ns.ChatOption(L.AUTOSELLJUNK_CHAT_DESC),
}

-- How many gray items can be sold without pushing anything else off the buyback list: the room
-- left beside the items there that aren't gray, so one sold by mistake stays buyable.
local function buybackRoom()
    local kept = 0
    for i = 1, (GetNumBuybackItems and GetNumBuybackItems() or 0) do
        local link = GetBuybackItemLink(i)
        local quality = link and C_Item.GetItemQualityByID(link)
        if quality ~= Enum.ItemQuality.Poor then
            kept = kept + 1
        end
    end
    return BUYBACK_SLOTS - kept
end

local function onMerchantShow()
    if ns.Keys.IsDown(module.db.skipKey) then
        return
    end
    local limit = module.db.buybackOnly and buybackRoom() or nil
    -- Past the limit, junk is counted instead of sold, so the player hears what was left.
    local sold, left, total = 0, 0, 0
    for bag = 0, LAST_BAG do -- backpack, four bags, and the reagent bag
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.quality == Enum.ItemQuality.Poor and not info.hasNoValue
                and not info.isLocked then
                if limit and sold >= limit then
                    left = left + 1
                else
                    local price = select(11, C_Item.GetItemInfo(info.hyperlink)) or 0
                    total = total + price * (info.stackCount or 1)
                    sold = sold + 1
                    C_Container.UseContainerItem(bag, slot)
                end
            end
        end
    end
    if sold > 0 and left > 0 then
        module:Print(format(L.AUTOSELLJUNK_SOLD_FULL, sold, money(total), left))
    elseif sold > 0 then
        module:Print(format(L.AUTOSELLJUNK_SOLD, sold, money(total)))
    elseif left > 0 then
        module:Print(format(L.AUTOSELLJUNK_FULL, left))
    end
end

function module:OnEnable()
    self:On("MERCHANT_SHOW", onMerchantShow)
end
