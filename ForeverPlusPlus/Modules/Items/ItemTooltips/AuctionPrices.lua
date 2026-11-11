-- Item Tooltips' auction prices: shows the lowest buyout in item tooltips, under the sell price,
-- with how long ago it was seen. Like the sell price, it counts the stack (Shift for one), or the
-- other way round. Its prices are every module's through ns.Prices: the Professions module's
-- Crafting Costs and Waylaid Crates read them there. The auction house scan that finds them is
-- in Scan.lua, which shares this part and its saved prices through `internal.auction`.
local _, ns = ...

local pairs, format, time = pairs, string.format, time
local GetTime = GetTime
local GetRealmName, UnitFactionGroup = GetRealmName, UnitFactionGroup
local C_Item, Enum = C_Item, Enum

local L = ns.L
local ItemTooltip = ns.ItemTooltip

local itemTooltips = ns.modules.ItemTooltips
local module = itemTooltips:NewPart({
    key = "auction", name = L.ITEMTOOLTIPS_AUCTION, description = L.AUCTIONPRICES_DESC,
    section = L.AUCTIONPRICES_TITLE,
}, {
    auction = true,
    auctionColor = "gold",
    hideJunk = false, -- no price on gray items (they do sell at auction on Forever)
    scanAge = "right", -- "right", "inline" (like the price line's alignment), or "off"
    scanAgeColor = "age", -- "age" (green when fresh to red when old), "gray", "white", or "gold"
    scanAgeRedHours = 12, -- hours old at which "age" is fully red
    scanOnOpen = true,
    auctionator = false, -- Auctionator's prices instead of our scans, while it's loaded
    chat = true,
    -- Data, not settings: it isn't in the options.
    -- Per auction house ("Realm-Faction"): { scannedAt = time(), items = { [itemID] =
    -- ns.Prices.Pack(copper, seenAt) } }. scannedAt is the last full scan and decides when to scan
    -- again; seenAt is when that item's price was last seen, which the tooltip's age shows, since
    -- an item missing from a scan keeps its older price.
    houses = {},
})

-- What Scan.lua shares with this file: the part, its auction house, and the calls between them.
local auction = { part = module }
itemTooltips.internal.auction = auction

local unpackPrice = ns.Prices.Unpack

-- Layout version 4 saves each price as one short string instead of a table. Houses saved before
-- 0.7.0 kept `prices` (copper by item) with only the house's scan time; they become items seen then.
ns.Migrate(4, function(db)
    local houses = db.data and db.data.ItemTooltips and db.data.ItemTooltips.houses
    for _, house in pairs(houses or {}) do
        ns.Prices.PackHouse(house)
    end
end)

-- The price line, then its age, then scanning, then Chat Messages.
module:AddOptions({
    {
        key = "auctionColor", name = L.PRICE_COLOR, description = L.PRICE_COLOR_DESC,
        choices = itemTooltips.internal.COLORS,
    },
    { key = "hideJunk", name = L.AUCTIONPRICES_JUNK, description = L.AUCTIONPRICES_JUNK_DESC, added = "1.0.1" },
    {
        key = "scanAge", name = L.AUCTIONPRICES_SCAN_AGE, description = L.AUCTIONPRICES_SCAN_AGE_DESC,
        choices = {
            { "right", L.PRICE_ALIGN_RIGHT },
            { "inline", L.PRICE_ALIGN_INLINE },
            { "off", L.AUCTIONPRICES_SCAN_AGE_OFF },
        },
    },
    {
        key = "scanAgeColor", name = L.AUCTIONPRICES_SCAN_AGE_COLOR,
        description = L.AUCTIONPRICES_SCAN_AGE_COLOR_DESC, requires = "scanAge",
        choices = {
            { "age", L.AUCTIONPRICES_SCAN_AGE_COLOR_AGE },
            { "gray", L.PRICE_COLOR_GRAY },
            { "white", L.PRICE_COLOR_WHITE },
            { "gold", L.PRICE_COLOR_GOLD },
        },
    },
    {
        key = "scanAgeRedHours", name = L.AUCTIONPRICES_SCAN_AGE_RED,
        description = L.AUCTIONPRICES_SCAN_AGE_RED_DESC, requires = "scanAge",
        min = 1, max = 48, step = 1, format = ns.Text.Hours,
    },
    { key = "scanOnOpen", name = L.AUCTIONPRICES_SCAN_ON_OPEN, description = L.AUCTIONPRICES_SCAN_ON_OPEN_DESC },
    {
        key = "auctionator", name = L.AUCTIONPRICES_AUCTIONATOR, description = L.AUCTIONPRICES_AUCTIONATOR_DESC,
        available = ns.Prices.AuctionatorLoaded, added = "1.0.0-beta.1",
    },
    ns.ChatOption(L.AUCTIONPRICES_CHAT_DESC),
})

-- The auction house this character sees. Realms share one per faction. Kept once found, since
-- every item tooltip asks and neither changes while logged in.
local houseData

local function house()
    if houseData then
        return houseData
    end
    local faction = UnitFactionGroup("player")
    local key = format("%s-%s", GetRealmName(), faction or "")
    local data = module.db.houses[key]
    if not (data and data.items) then
        data = { scannedAt = 0, items = {} } -- first visit to this auction house
        module.db.houses[key] = data
    end
    if faction then
        houseData = data -- without a faction yet (early in login), look again next time
    end
    return data
end
auction.House = house

-- Reset: forgets this auction house's prices, after the player confirms in a popup.
local function resetPrices()
    local data = house()
    data.items = {}
    data.scannedAt = 0
    ns.Prices.Changed()
    ns.Print(L.AUCTIONPRICES_RESET_DONE)
end

local RESET_POPUP = "AUCTIONPRICES_RESET"

local function confirmReset()
    ns.Confirm(RESET_POPUP, L.AUCTIONPRICES_RESET_CONFIRM, resetPrices)
end
ns.AddCommand("resetprices", "", L.AUCTIONPRICES_RESET_COMMAND, confirmReset, "ItemTooltips")

-- The reset button sits on the module's page, after every part's options.
itemTooltips.actions = {
    {
        name = L.AUCTIONPRICES_RESET,
        button = L.AUCTIONPRICES_RESET_BUTTON,
        description = L.AUCTIONPRICES_RESET_DESC,
        fn = resetPrices,
        confirm = L.AUCTIONPRICES_RESET_CONFIRM,
        key = RESET_POPUP, -- the same popup /fpp resetprices asks
    },
}

-- Tooltips -----------------------------------------------------------------------------------

-- The color of a price `seconds` old, as Scan Age Color says: with "age", green when just scanned,
-- yellow halfway, red at Red After (hours); otherwise the quantity color it names.
local function ageColor(seconds)
    local db = module.db
    if db.scanAgeColor ~= "age" then
        return db.scanAgeColor
    end
    local t = seconds / (db.scanAgeRedHours * 3600)
    t = t > 1 and 1 or t
    if t < 0.5 then
        return { t * 2, 1, 0 }
    end
    return { 1, (1 - t) * 2, 0 }
end

-- Prices for other modules -----------------------------------------------------------------------
-- ns.Prices hands our prices to other modules while this part is on, with the Scan Age Color
-- the player picked (Crafting Costs colors its Oldest Price by it), and this file reads its own
-- through it too, so Use Auctionator's Prices switches them all. Waylaid Crates finds items
-- by name, since a crate's tooltip gives names, not IDs: among the names of items with a saved
-- price, when the client's item cache doesn't know them.

local nameIDs = {} -- item name -> itemID
local named = {} -- itemIDs already in nameIDs (or given up on), so each is only asked once
local tries = {} -- itemID -> looks it had no name in
local nextLook = 0 -- GetTime() the saved prices may next be looked through for names
local LOADING_AGAIN = 0.5 -- seconds, while some saved items' names are still loading
local LOOK_AGAIN = 60 -- seconds, once every saved item has its name
local GIVE_UP = 5 -- looks an item may come back without a name before it stops counting as loading

---A newly priced item came in (Scan.lua): look through the names again at the next ask.
function auction.NameSoon()
    nextLook = 0
end

-- The saved prices can hold thousands of items, and a tooltip draws many times while it's up,
-- so after a look through them every name not found waits for the next. Asking for a name the
-- client doesn't have yet loads it, and the first look at a crate is usually before they've come
-- in: look again soon while any are loading, or the bundles show No price until the long wait is
-- over. An item whose name never comes (gone from the game) stops counting after a few looks.
local function itemByName(name)
    local id = nameIDs[name]
    if id or not C_Item.GetItemNameByID then
        return id
    end
    local now = GetTime()
    if now < nextLook then
        return nil
    end
    local loading = false
    for itemID in pairs(house().items) do
        if not named[itemID] then
            local itemName = C_Item.GetItemNameByID(itemID) -- nil until the client has the item
            if itemName then
                named[itemID] = true
                nameIDs[itemName] = itemID
            else
                tries[itemID] = (tries[itemID] or 0) + 1
                if tries[itemID] >= GIVE_UP then
                    named[itemID] = true
                else
                    loading = true
                end
            end
        end
    end
    nextLook = now + (loading and LOADING_AGAIN or LOOK_AGAIN)
    return nameIDs[name]
end

local priceSource = {
    price = function(itemID)
        return unpackPrice(house().items[itemID])
    end,
    itemByName = itemByName,
    inline = function()
        return module.db.align == "inline"
    end,
    auctionator = function()
        return module.db.auctionator
    end,
    ageColor = ageColor,
}

local auctionPrice = ns.Prices.Auction

-- The item whose tooltip this is, unless its price lines are off: the part is off, or it's a gray
-- item and Hide on Junk is on. An item the client hasn't loaded yet has no quality and counts.
local function tooltipItem(data)
    local itemID = module.enabled and ItemTooltip.ItemID(data)
    if itemID and module.db.hideJunk and C_Item.GetItemQualityByID
        and C_Item.GetItemQualityByID(itemID) == Enum.ItemQuality.Poor then
        return nil
    end
    return itemID
end

local function addAuctionPrice(tooltip, data)
    local itemID = tooltipItem(data)
    if not itemID then
        return
    end
    local price = auctionPrice(itemID)
    if not price then
        return
    end
    local db = module.db
    ItemTooltip.AddPrice(tooltip, data, L.AUCTIONPRICES_LINE, price, db.mode, db.align, db.auctionColor)
end

-- When this item's price was last seen, by a scan or the player's own search: an item missing
-- from the last scan keeps its older price and age. Auctionator may not say. After every price
-- line (OnPriceNotes), so other prices priced from this one, like Disenchant, sit above it.
local function addScanAge(tooltip, data)
    local itemID = tooltipItem(data)
    if not itemID then
        return
    end
    local price, seenAt = auctionPrice(itemID)
    local db = module.db
    if price and db.scanAge ~= "off" and seenAt then
        local age = time() - seenAt
        ItemTooltip.AddInfo(tooltip, L.AUCTIONPRICES_SCAN_AGE_LINE, ns.Text.Ago(age), db.scanAge, ageColor(age))
    end
end

function module:OnEnable()
    ns.Prices.SetSource(priceSource)
    auction.EnableScan()
    -- The hooks can't be removed; addAuctionPrice and addScanAge check the part is on instead.
    ItemTooltip.OnPrices(addAuctionPrice, module)
    ItemTooltip.OnPriceNotes(addScanAge, module)
    -- The price changes from the stack to one item with Shift.
    ItemTooltip.RedrawOnShift(self, true)
end

function module:OnDisable()
    ItemTooltip.RedrawOnShift(self, false)
    ns.Prices.SetSource(nil)
    auction.DisableScan()
end

function module:OnOptionChanged(key)
    if key == "auctionator" then
        ns.Prices.Changed() -- every price now comes from the other source
        -- A scan running when Auctionator's prices take over stops, keeping what it saw.
        if ns.Prices.UsingAuctionator() then
            auction.StopScan()
        end
    end
end
