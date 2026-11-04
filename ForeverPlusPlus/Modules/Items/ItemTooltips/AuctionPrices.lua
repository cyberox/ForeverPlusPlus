-- Item Tooltips' auction prices: scans the auction house when it opens and shows the lowest
-- buyout in item tooltips, under the sell price. Like the sell price, it counts the stack (Shift
-- for one), or the other way round. In the professions window, it adds up what a recipe's
-- reagents cost against what the crafted items are worth.
--
-- The scan is an empty browse search paged to the end, the same one Auctionator's default scan
-- uses on Forever. C_AuctionHouse.ReplicateItems is in the client too, but it's unproven here,
-- and Auctionator leaves it off by default. Browse results give the lowest unit price per item.
local _, ns = ...

local ipairs, pairs, format, time, floor = ipairs, pairs, string.format, time, math.floor
local C_AuctionHouse, GetTime = C_AuctionHouse, GetTime
local GetRealmName, UnitFactionGroup = GetRealmName, UnitFactionGroup
local CreateFrame, pcall = CreateFrame, pcall
local select, tostring, C_Item, C_TradeSkillUI, Enum = select, tostring, C_Item, C_TradeSkillUI, Enum
local GRAY_FONT_COLOR, HIGHLIGHT_FONT_COLOR = GRAY_FONT_COLOR, HIGHLIGHT_FONT_COLOR
local wipe = wipe

local L = ns.L
local ItemTooltip = ns.ItemTooltip

local SCAN_INTERVAL = 15 * 60 -- seconds between automatic scans, as Auctionator waits

local itemTooltips = ns.modules.ItemTooltips
local module = itemTooltips:NewPart({
    key = "auction", name = L.ITEMTOOLTIPS_AUCTION, description = L.AUCTIONPRICES_DESC,
    section = L.AUCTIONPRICES_TITLE,
}, {
    auction = true,
    auctionColor = "gold",
    scanAge = "right", -- "right", "inline" (like the price line's alignment), or "off"
    scanAgeColor = "age", -- "age" (green when fresh to red when old), "gray", "white", or "gold"
    scanAgeRedHours = 12, -- hours old at which "age" is fully red
    crafting = true, -- costs, value, and profit under a recipe's reagents
    scanOnOpen = true,
    auctionator = false, -- Auctionator's prices instead of our scans, while it's loaded
    chat = true,
    -- Data, not settings: they aren't in the options.
    -- What merchants charge for one of an item: { [itemID] = copper }, learned at each visit.
    vendor = {},
    -- Per auction house ("Realm-Faction"): { scannedAt = time(), items = { [itemID] =
    -- ns.Prices.Pack(copper, seenAt) } }. scannedAt is the last full scan and decides when to scan
    -- again; seenAt is when that item's price was last seen, which the tooltip's age shows, since
    -- an item missing from a scan keeps its older price.
    houses = {},
})

local packPrice, unpackPrice = ns.Prices.Pack, ns.Prices.Unpack

-- Layout version 4 saves each price as one short string instead of a table. Houses saved before
-- 0.7.0 kept `prices` (copper by item) with only the house's scan time; they become items seen then.
ns.Migrate(4, function(db)
    local houses = db.data and db.data.ItemTooltips and db.data.ItemTooltips.houses
    for _, house in pairs(houses or {}) do
        ns.Prices.PackHouse(house)
    end
end)

-- The price line, then its age, then crafting and scanning, then Chat Messages.
module:AddOptions({
    {
        key = "auctionColor", name = L.PRICE_COLOR, description = L.PRICE_COLOR_DESC,
        choices = itemTooltips.internal.COLORS,
    },
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
    { key = "crafting", name = L.AUCTIONPRICES_CRAFTING, description = L.AUCTIONPRICES_CRAFTING_DESC },
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

-- Indicator ----------------------------------------------------------------------------------
-- A spinner and a line of text in the auction house's title bar while a scan runs, then
-- "Prices updated" for a few seconds. Our own frame, parented to Blizzard's window.

local indicator
local hideTimer = ns.Frames.Timer(module)

local function getIndicator()
    local parent = _G.AuctionHouseFrame
    if not parent then
        return nil
    end
    if not indicator then
        indicator = CreateFrame("Frame", nil, parent)
        indicator:SetSize(1, 20)
        indicator:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -30, -1)
        -- Above the window's border and title art, which are child frames with fixed levels well
        -- above the window's. A level over the title bar, as Coordinates does on the map, not a
        -- strata, so it stays with the window instead of floating over others.
        local title = parent.TitleContainer
        indicator:SetFrameLevel((title or parent):GetFrameLevel() + (title and 1 or 500))
        indicator.text = indicator:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        indicator.text:SetPoint("RIGHT")
        -- Probe: LoadingSpinnerTemplate is Mainline SharedXML; without it, only the text shows.
        local ok, spinner = pcall(CreateFrame, "Frame", nil, indicator, "LoadingSpinnerTemplate")
        if ok and spinner then
            spinner:SetSize(20, 20)
            spinner:SetPoint("RIGHT", indicator.text, "LEFT", -2, 0)
            indicator.spinner = spinner
        end
    end
    return indicator
end

-- busy shows the spinner; stay keeps the text up instead of hiding it after a few seconds.
local function showIndicator(text, busy, stay)
    local frame = getIndicator()
    if not frame then
        if not busy and not stay then
            module:Print(text) -- no auction house window to show it on
        end
        return
    end
    hideTimer:Cancel()
    frame.text:SetText(text)
    if frame.spinner then
        frame.spinner:SetShown(busy)
    end
    frame:Show()
    if not busy and not stay then
        hideTimer:Start(4, function()
            frame:Hide()
        end)
    end
end

local function hideIndicator()
    hideTimer:Cancel()
    if indicator then
        indicator:Hide()
    end
end

-- Scanning -----------------------------------------------------------------------------------

local scanning = false
local seen, seenCount -- itemIDs priced in this scan, and how many
local listed = {} -- itemIDs priced in the browse results shown now (any browse, not just a scan)
local nextLook = 0 -- GetTime() the saved prices may next be looked through for names (itemByName)

-- Keeps the lowest price from browse results. Any browse (the player's own searches too) updates
-- the prices, so they stay fresh between full scans.
local function addResults(results)
    local items = house().items
    local now = time()
    local changed = false
    for _, result in ipairs(results or {}) do
        local itemID = result.itemKey and result.itemKey.itemID
        local price = result.minPrice
        if itemID and result.totalQuantity and result.totalQuantity > 0 and price
            and price > 0 then
            local old = unpackPrice(items[itemID])
            if listed[itemID] and old then -- no price when the prices were reset since
                -- One item can come back once per item level or suffix: keep the lowest.
                if price < old then
                    items[itemID] = packPrice(price, now)
                    changed = true
                end
            else
                -- The first price in these results replaces the old one.
                if not old then
                    nextLook = 0 -- a newly priced item: named on the next look, not a minute later
                end
                listed[itemID] = true
                items[itemID] = packPrice(price, now)
                changed = true
            end
            if scanning and not seen[itemID] then
                seen[itemID] = true
                seenCount = seenCount + 1
            end
        end
    end
    if changed then
        ns.Prices.Changed()
    end
end

local open = false -- the auction house is open

-- The scan shares the server's query throttle with everything the player does in the auction
-- house. Paging nonstop starves Blizzard's own queries, so the Sell tab's list never loads and
-- posts can fail. So it keeps one request out at a time, sends only when the throttle is ready,
-- gives way for a moment after each of Blizzard's own queries, and pauses while an item sits in
-- the sell box, so the list and the post go through first. Browsing tabs with nothing
-- to sell doesn't stop it.
local YIELD = 2 -- seconds the scan waits after one of Blizzard's own queries

local sent = false -- the scan's browse query has gone out
local waiting -- what the next step waits on: "server", "throttle", or "blocked"
local ownQuery = false -- set while sending the scan's own browse query
local lastQuery = 0 -- GetTime() of Blizzard's last query of its own
local blockTimer = ns.Frames.Timer(module)
local onThrottleReady

-- The server doesn't always answer: a page request can be dropped by the throttle, or the last
-- page can come back with no event at all, and the throttle's ready event can fail to come. So a
-- step that waits on the server or the throttle asks again after a while, and after a few tries
-- with no answer the scan ends with the prices it has, instead of spinning forever.
local STALL = 8 -- seconds without an answer before asking again
local RETRIES = 2 -- times it asks again before it ends the scan
local stallTimer = ns.Frames.Timer(module)
local retries = 0
local answered = false -- a browse answer came since the scan's query went out

local function stopScan()
    scanning, sent, waiting = false, false, nil
    seen, seenCount = nil, nil
    retries, answered = 0, false
    module:Off("AUCTION_HOUSE_THROTTLED_SYSTEM_READY", onThrottleReady)
    blockTimer:Cancel()
    stallTimer:Cancel()
end

-- Ends the scan, keeping every price seen. The scan counts as done, so it waits the usual
-- interval before scanning again on its own.
local function finishScan(text)
    local count = seenCount
    house().scannedAt = time()
    stopScan()
    showIndicator(format(text, count), false)
end

-- An item is in the sell box on the Sell tab, so a post is coming. Probed: when the window's
-- mode or the sell frame can't be read, don't pause.
local function selling()
    local frame, modes = _G.AuctionHouseFrame, _G.AuctionHouseFrameDisplayMode
    if not (frame and modes and frame.GetDisplayMode) then
        return false
    end
    local mode = frame:GetDisplayMode()
    local sellFrame = (mode == modes.ItemSell and frame.ItemSellFrame)
        or (mode == modes.CommoditiesSell and frame.CommoditiesSellFrame)
    return sellFrame and sellFrame.GetItem and sellFrame:GetItem() ~= nil or false
end

local step

-- No answer in time: ask again, or end the scan with what it has.
local function onStall()
    if not scanning or (waiting ~= "server" and waiting ~= "throttle") then
        return
    end
    retries = retries + 1
    if retries > RETRIES then
        finishScan(L.AUCTIONPRICES_NO_ANSWER)
        return
    end
    if waiting == "server" and not answered then
        sent = false -- the first query got no answer: send it again
    end
    module:Off("AUCTION_HOUSE_THROTTLED_SYSTEM_READY", onThrottleReady)
    waiting = nil
    step()
end

-- Paused for the sell box or giving way: look again shortly. The timer runs only while a scan
-- is held back.
local function onBlockTimer()
    if waiting == "blocked" then
        step()
    end
end

-- Sends the scan's query, asks for the next page, or finishes once the server has sent
-- everything. Runs once per answer, so there's never more than one request out.
function step()
    if not scanning then
        return
    end
    local sell = selling()
    local wait = lastQuery + YIELD - GetTime()
    if sell or wait > 0 then
        waiting = "blocked"
        stallTimer:Cancel() -- held back on purpose, not waiting on anyone
        if sell then
            showIndicator(format(L.AUCTIONPRICES_PAUSED, seenCount), false, true)
        end
        if not blockTimer:IsPending() then
            blockTimer:Start(sell and 1 or wait, onBlockTimer)
        end
        return
    end
    showIndicator(format(L.AUCTIONPRICES_SCANNING, seenCount), true)
    local ready = C_AuctionHouse.IsThrottledMessageSystemReady
    if ready and not ready() then
        if waiting ~= "throttle" then
            waiting = "throttle"
            module:On("AUCTION_HOUSE_THROTTLED_SYSTEM_READY", onThrottleReady)
            stallTimer:Start(STALL, onStall)
        end
        return
    end
    waiting = "server"
    if not sent then
        sent, ownQuery, answered = true, true, false
        C_AuctionHouse.SendBrowseQuery({
            searchString = "", sorts = {}, filters = {}, itemClassFilters = {},
        })
        ownQuery = false
        stallTimer:Start(STALL, onStall)
    elseif not C_AuctionHouse.HasFullBrowseResults() then
        C_AuctionHouse.RequestMoreBrowseResults()
        stallTimer:Start(STALL, onStall)
    else
        finishScan(L.AUCTIONPRICES_SCANNED)
    end
end

function onThrottleReady()
    module:Off("AUCTION_HOUSE_THROTTLED_SYSTEM_READY", onThrottleReady)
    if waiting == "throttle" then
        step()
    end
end

local function onResults()
    if scanning and sent and waiting == "server" then
        retries, answered = 0, true
        stallTimer:Cancel()
        step()
    end
end

-- The whole list again: a new search, or more pages of the same one.
local function onResultsUpdated()
    wipe(listed)
    addResults(C_AuctionHouse.GetBrowseResults())
    onResults()
end

local function onResultsAdded(_, added)
    addResults(added)
    onResults()
end

-- Blizzard sent a query of its own (the sell list, an item's listings, your auctions, a post,
-- a purchase): hold the next page back for a moment so those go first.
local function onBlizzardQuery()
    if scanning then
        lastQuery = GetTime()
    end
end

-- Another search (the player's, favorites, another addon's) replaces the browse results the scan
-- was paging through, so stop, keeping the prices seen so far. Also stops a scan still waiting
-- to start, which would otherwise replace the player's results.
local function onOtherSearch()
    if scanning and not ownQuery then
        local count = seenCount
        stopScan()
        showIndicator(format(L.AUCTIONPRICES_STOPPED, count), false)
    end
end

local SEARCHES = { "SendBrowseQuery", "SearchForFavorites", "SearchForItemKeys" }
local QUERIES = {
    "SendSearchQuery", "SendSellSearchQuery", "RequestMoreItemSearchResults",
    "RequestMoreCommoditySearchResults", "RefreshItemSearchResults",
    "RefreshCommoditySearchResults", "QueryOwnedAuctions", "QueryBids", "PostItem",
    "PostCommodity", "PlaceBid", "CancelAuction", "StartCommoditiesPurchase",
    "ConfirmCommoditiesPurchase",
}

-- With Auctionator's prices in use, ours aren't scanned; the saved ones stay for when it's off.
local function startScan()
    if scanning or not open or ns.Prices.UsingAuctionator() then
        return
    end
    scanning, sent, waiting = true, false, nil
    seen, seenCount = {}, 0
    step()
end

-- A moment after opening, so Blizzard's window has set itself up first: scan when it's due, or
-- say how old the prices are.
local function afterShow()
    if not open or scanning or ns.Prices.UsingAuctionator() then
        return
    end
    local age = time() - house().scannedAt
    if module.db.scanOnOpen and age >= SCAN_INTERVAL then
        startScan()
    elseif house().scannedAt > 0 then
        showIndicator(format(L.AUCTIONPRICES_AGE, floor(age / 60)), false)
    end
end

local showTimer = ns.Frames.Timer(module)
local function onShow()
    open = true
    showTimer:Start(0.5, afterShow)
end

-- /fpp scan: scan now, whenever the last one was.
local function scanCommand()
    if not module.enabled then
        ns.Print(L.AUCTIONPRICES_IS_OFF)
    elseif ns.Prices.UsingAuctionator() then
        ns.Print(L.AUCTIONPRICES_USING_AUCTIONATOR)
    elseif not open then
        ns.Print(L.AUCTIONPRICES_NOT_OPEN)
    else
        startScan()
    end
end
ns.AddCommand("scan", "", L.AUCTIONPRICES_COMMAND, scanCommand)

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
ns.AddCommand("resetprices", "", L.AUCTIONPRICES_RESET_COMMAND, confirmReset)

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

local function onClosed()
    open = false
    stopScan() -- prices seen so far are kept; the next visit scans again
    hideIndicator()
end

-- Tooltips -----------------------------------------------------------------------------------

-- Scan Age Color "age": green when just scanned, yellow halfway, red at Red After (hours).
local function ageColor(seconds)
    local t = seconds / (module.db.scanAgeRedHours * 3600)
    t = t > 1 and 1 or t
    if t < 0.5 then
        return { t * 2, 1, 0 }
    end
    return { 1, (1 - t) * 2, 0 }
end

-- Prices for other modules -----------------------------------------------------------------------
-- ns.Prices hands our prices to other modules while this part is on, and this file reads its
-- own through it too, so Use Auctionator's Prices switches them all. Waylaid Crates finds items
-- by name, since a crate's tooltip gives names, not IDs: among the names of items with a saved
-- price, when the client's item cache doesn't know them.

local nameIDs = {} -- item name -> itemID
local named = {} -- itemIDs already in nameIDs (or given up on), so each is only asked once
local tries = {} -- itemID -> looks it had no name in
local LOADING_AGAIN = 0.5 -- seconds, while some saved items' names are still loading
local LOOK_AGAIN = 60 -- seconds, once every saved item has its name
local GIVE_UP = 5 -- looks an item may come back without a name before it stops counting as loading

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
}

local auctionPrice = ns.Prices.Auction

local function addAuctionPrice(tooltip, data)
    local itemID = module.enabled and ItemTooltip.ItemID(data)
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
    local itemID = module.enabled and ItemTooltip.ItemID(data)
    if not itemID then
        return
    end
    local price, seenAt = auctionPrice(itemID)
    local db = module.db
    if price and db.scanAge ~= "off" and seenAt then
        local age = time() - seenAt
        local color = db.scanAgeColor == "age" and ageColor(age) or db.scanAgeColor
        ItemTooltip.AddInfo(tooltip, L.AUCTIONPRICES_SCAN_AGE_LINE, ns.Text.Ago(age), db.scanAge, color)
    end
end

-- Crafting -----------------------------------------------------------------------------------
-- In the professions window, under the recipe's description: what its reagents cost in all (each
-- one's price times the count the recipe takes), what the crafted items are worth, the profit
-- after the auction house's cut, and how old the oldest auction price in them is. A reagent
-- a merchant sells costs the merchant's price when that's lower than the auction's; those
-- prices are learned at merchants. A crafted item with no auction price is worth what a
-- merchant pays for it. Our own frame on Blizzard's recipe form; only the reagents' anchor is
-- changed, to move them down under it, and put back when it goes. (Prices inside Blizzard's
-- reagent slots didn't fit, and a row per reagent was too much.)

-- A merchant's item: its price, how many that price buys, how many are left (-1: unlimited),
-- and whether it costs something besides money. Probe: C_MerchantFrame.GetItemInfo is newer
-- Mainline; GetMerchantItemInfo the older one.
local function merchantItem(index)
    local C_MerchantFrame = _G.C_MerchantFrame
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local info = C_MerchantFrame.GetItemInfo(index)
        if info then
            return info.price, info.stackCount, info.numAvailable, info.hasExtendedCost
        end
    elseif _G.GetMerchantItemInfo then
        local _, _, price, stack, available, _, _, extended = _G.GetMerchantItemInfo(index)
        return price, stack, available, extended
    end
end

-- Remembers what the open merchant charges for one of each item it always has, for money only.
local function recordMerchant()
    local count = _G.GetMerchantNumItems and _G.GetMerchantNumItems() or 0
    local getID = _G.GetMerchantItemID
    if not getID then
        return
    end
    local vendor = module.db.vendor
    for i = 1, count do
        local id = getID(i)
        local price, stack, available, extended = merchantItem(i)
        if id and price and price > 0 and available == -1 and not extended then
            vendor[id] = price / ((stack and stack > 0) and stack or 1)
        end
    end
end

-- What one of a reagent costs: the lower of its auction and merchant prices, or nil. Then when
-- the auction price was seen, when that's the one used.
local function reagentCost(itemID)
    local auction, seenAt = auctionPrice(itemID)
    local vendor = module.db.vendor[itemID]
    if auction and (not vendor or auction < vendor) then
        return auction, seenAt
    end
    return vendor
end

-- What one crafted item is worth: its auction price, or else what a merchant pays (and true).
-- Then when the auction price was seen.
local function craftedValue(itemID)
    local price, seenAt = auctionPrice(itemID)
    if price then
        return price, false, seenAt
    end
    local sell = select(11, C_Item.GetItemInfo(itemID))
    if sell and sell > 0 then
        return sell, true
    end
end

-- A reagent slot every craft uses (not an optional or finishing one): its item and how many, or
-- nil. Probe: reagentType and its enum are Mainline's; without them, whether it's required.
local function basicReagent(slot)
    local basic = Enum.CraftingReagentType and Enum.CraftingReagentType.Basic
    local isBasic
    if basic and slot.reagentType ~= nil then
        isBasic = slot.reagentType == basic
    else
        isBasic = slot.required
    end
    local reagent = slot.reagents and slot.reagents[1]
    if isBasic and reagent and reagent.itemID and (slot.quantityRequired or 0) > 0 then
        return reagent.itemID, slot.quantityRequired
    end
end

-- The reagents every craft uses: { itemID, count } each.
local function basicReagents(schematic)
    local list = {}
    for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
        local itemID, count = basicReagent(slot)
        if itemID then
            list[#list + 1] = { itemID, count }
        end
    end
    return list
end

local GRAY, WHITE = GRAY_FONT_COLOR, HIGHLIGHT_FONT_COLOR
local GREEN, RED = GREEN_FONT_COLOR, RED_FONT_COLOR

local AUCTION_CUT = 0.05 -- the auction house's cut of a sale

-- Copper as coins, with a minus sign when it's negative.
local function coins(amount)
    amount = floor(amount + 0.5)
    if amount < 0 then
        return "-" .. ns.Money(-amount)
    end
    return ns.Money(amount)
end

local CRAFT_WIDTH, ROW_HEIGHT = 280, 14

local panel -- our frame for the totals, made the first time a recipe shows
local reagentsAnchor -- Blizzard's anchor for the reagents, which our totals take over

local function craftForm()
    local frame = _G.ProfessionsFrame
    local page = frame and frame.CraftingPage
    return page and page.SchematicForm
end

local function getPanel(form)
    if not panel then
        panel = CreateFrame("Frame", nil, form)
        panel:SetSize(CRAFT_WIDTH, ROW_HEIGHT)
        panel.rows = {}
    end
    return panel
end

-- The totals go where Blizzard put the reagents, under the description, and the reagents move
-- down under them. Only for a reagents frame with one TOPLEFT anchor, as Mainline's has; false
-- otherwise. Blizzard may anchor the reagents again for each recipe, so the anchor is read again
-- each time unless it's still ours.
local function placeAtTop(form)
    local reagents = form.Reagents
    if not (reagents and reagents:GetNumPoints() == 1) then
        return false
    end
    local point, relativeTo, relativePoint, x, y = reagents:GetPoint(1)
    if relativeTo ~= panel then
        if point ~= "TOPLEFT" then
            return false
        end
        reagentsAnchor = { relativeTo or form, relativePoint, x, y }
    elseif not reagentsAnchor then
        return false
    end
    local anchor = reagentsAnchor
    panel:ClearAllPoints()
    -- A recipe with no description still keeps its empty line's space: the totals take it.
    local description = form.Description
    local text = description and description.GetText and description:GetText()
    if anchor[1] == description and (text == nil or text == "") then
        panel:SetPoint("TOPLEFT", description, "TOPLEFT", anchor[3], 0)
    else
        panel:SetPoint("TOPLEFT", anchor[1], anchor[2], anchor[3], anchor[4] / 2)
    end
    reagents:ClearAllPoints()
    reagents:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 0, -14)
    return true
end

-- Puts the reagents back where Blizzard had them, when our totals go.
local function restoreReagents(form)
    local reagents = form.Reagents
    if not (reagentsAnchor and reagents) then
        return
    end
    local _, relativeTo = reagents:GetPoint(1)
    if relativeTo == panel then
        local anchor = reagentsAnchor
        reagents:ClearAllPoints()
        reagents:SetPoint("TOPLEFT", anchor[1], anchor[2], anchor[3], anchor[4])
    end
end

-- Row `i` at `y`: a label on the left and a value at the right edge.
local function setRow(i, y, label, value)
    local row = panel.rows[i]
    if not row then
        row = {
            left = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"),
            right = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"),
        }
        row.left:SetJustifyH("LEFT")
        row.left:SetWordWrap(false)
        row.right:SetJustifyH("RIGHT")
        panel.rows[i] = row
    end
    row.right:ClearAllPoints()
    row.right:SetPoint("TOPRIGHT", 0, y)
    row.left:ClearAllPoints()
    row.left:SetPoint("TOPLEFT", 0, y)
    row.left:SetPoint("RIGHT", row.right, "LEFT", -8, 0)
    row.left:SetText(label)
    row.right:SetText(value)
    row.left:Show()
    row.right:Show()
end

local function noPrice()
    return GRAY:WrapTextInColorCode(L.AUCTIONPRICES_CRAFT_NO_PRICE)
end

local function refreshCrafting(recipeInfo)
    local form = craftForm()
    if not form then
        return
    end
    recipeInfo = recipeInfo or (form.GetRecipeInfo and form:GetRecipeInfo())
    local recipeID = module.enabled and module.db.crafting and recipeInfo and recipeInfo.recipeID
    local schematic = recipeID and C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic
        and C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
    local reagents = schematic and basicReagents(schematic)
    if not (reagents and #reagents > 0 and form.Reagents) then
        if panel then
            panel:Hide()
            restoreReagents(form)
        end
        return
    end
    getPanel(form)
    if not placeAtTop(form) then
        -- Not the layout we know: under the reagents instead, moving nothing of Blizzard's.
        restoreReagents(form)
        local below = form.OptionalReagents
        if not (below and below:IsShown()) then
            below = form.Reagents
        end
        panel:ClearAllPoints()
        panel:SetPoint("TOPLEFT", below, "BOTTOMLEFT", 0, -12)
    end

    -- oldest: when the oldest auction price used was seen, for how much to trust the totals.
    local total, missing, oldest = 0, false, nil
    for _, reagent in ipairs(reagents) do
        local unit, seenAt = reagentCost(reagent[1])
        if unit then
            total = total + unit * reagent[2]
        else
            missing = true
        end
        if seenAt and (not oldest or seenAt < oldest) then
            oldest = seenAt
        end
    end
    -- Enchants and other recipes that make no item have no value or profit.
    local output = schematic.outputItemID
    local unitValue, fromVendor, seenAt
    if output then
        unitValue, fromVendor, seenAt = craftedValue(output)
        if seenAt and (not oldest or seenAt < oldest) then
            oldest = seenAt
        end
    end

    local i, y = 0, 0
    -- How old the oldest auction price in these totals is, colored like the tooltip's age.
    if oldest then
        local age = time() - oldest
        local color = module.db.scanAgeColor == "age" and ageColor(age) or module.db.scanAgeColor
        local text = ItemTooltip.ColorText(ns.Text.Ago(age), color)
        i = i + 1
        setRow(i, y, L.AUCTIONPRICES_CRAFT_AGE, text)
        y = y - ROW_HEIGHT
    end

    i = i + 1
    setRow(i, y, L.AUCTIONPRICES_CRAFT_COST, missing and noPrice() or coins(total))
    y = y - ROW_HEIGHT

    if output then
        local low, high = schematic.quantityMin or 1, schematic.quantityMax or 1
        local made = (low + high) / 2 -- some recipes make a random number: count the middle
        local label = L.AUCTIONPRICES_CRAFT_VALUE
        if high > 1 then
            local amount = low == high and tostring(low) or format(L.AUCTIONPRICES_CRAFT_RANGE, low, high)
            label = format(L.AUCTIONPRICES_CRAFT_VALUE_COUNT, amount)
        end
        local valueText = noPrice()
        if unitValue then
            unitValue = unitValue * made
            valueText = coins(unitValue)
            if fromVendor then
                valueText = format(L.AUCTIONPRICES_CRAFT_EACH, valueText,
                    GRAY:WrapTextInColorCode(L.AUCTIONPRICES_CRAFT_VENDOR))
            end
        end
        i = i + 1
        setRow(i, y, label, valueText)
        y = y - ROW_HEIGHT

        -- Selling at auction loses the house's cut; a merchant pays in full.
        local profitText = noPrice()
        if unitValue and not missing then
            local profit = (fromVendor and unitValue or unitValue * (1 - AUCTION_CUT)) - total
            local color = profit > 0 and GREEN or profit < 0 and RED or WHITE
            profitText = color:WrapTextInColorCode(coins(profit))
        end
        i = i + 1
        setRow(i, y, L.AUCTIONPRICES_CRAFT_PROFIT, profitText)
        y = y - ROW_HEIGHT
    end

    for j = i + 1, #panel.rows do
        panel.rows[j].left:Hide()
        panel.rows[j].right:Hide()
    end
    panel:SetHeight(-y)
    panel:Show()
end

local function onRecipeInit(_, recipeInfo)
    refreshCrafting(recipeInfo)
end

-- Blizzard_Professions is load-on-demand: hook its recipe form once it has loaded. Init runs each
-- time a recipe is picked.
local function hookProfessions()
    local form = craftForm()
    if form then
        module:Hook(form, "Init", onRecipeInit)
        refreshCrafting()
    end
end

local events = {
    AUCTION_HOUSE_SHOW = onShow,
    AUCTION_HOUSE_CLOSED = onClosed,
    AUCTION_HOUSE_BROWSE_RESULTS_UPDATED = onResultsUpdated,
    AUCTION_HOUSE_BROWSE_RESULTS_ADDED = onResultsAdded,
    MERCHANT_SHOW = recordMerchant,
    MERCHANT_UPDATE = recordMerchant,
}

function module:OnEnable()
    -- First, since the crafting totals below read their prices through it.
    ns.Prices.SetSource(priceSource)
    for event, fn in pairs(events) do
        self:On(event, fn)
    end
    -- Hooked by name, each skipped when this client doesn't have it; the hooks do nothing unless
    -- a scan is running.
    for _, name in ipairs(SEARCHES) do
        self:Hook(C_AuctionHouse, name, onOtherSearch)
    end
    for _, name in ipairs(QUERIES) do
        self:Hook(C_AuctionHouse, name, onBlizzardQuery)
    end
    -- Turned on with the auction house already open, its show event has passed.
    local frame = _G.AuctionHouseFrame
    open = frame and frame:IsShown() and true or false
    -- The hooks can't be removed; addAuctionPrice and addScanAge check the part is on instead.
    ItemTooltip.OnPrices(addAuctionPrice, module)
    ItemTooltip.OnPriceNotes(addScanAge, module)
    -- The price changes from the stack to one item with Shift.
    ItemTooltip.RedrawOnShift(self, true)
    ns.AddOns.WhenLoaded("Blizzard_Professions", hookProfessions)
end

function module:OnDisable()
    ItemTooltip.RedrawOnShift(self, false)
    ns.Prices.SetSource(nil)
    stopScan()
    hideIndicator()
    open = false
    ns.AddOns.Cancel("Blizzard_Professions", hookProfessions)
    if panel then
        panel:Hide()
    end
    local form = craftForm()
    if form then
        restoreReagents(form)
    end
end

function module:OnOptionChanged(key)
    if key == "crafting" then
        refreshCrafting()
    elseif key == "auctionator" then
        ns.Prices.Changed() -- every price now comes from the other source
        -- A scan running when Auctionator's prices take over stops, keeping what it saw.
        if ns.Prices.UsingAuctionator() then
            stopScan()
            hideIndicator()
        end
        refreshCrafting()
    end
end
