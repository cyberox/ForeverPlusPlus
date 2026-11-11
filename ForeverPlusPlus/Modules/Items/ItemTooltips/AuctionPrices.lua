-- Item Tooltips' auction prices: scans the auction house when it opens and shows the lowest
-- buyout in item tooltips, under the sell price. Like the sell price, it counts the stack (Shift
-- for one), or the other way round. Its prices are every module's through ns.Prices: the
-- Professions module's Crafting Costs and Waylaid Crates read them there.
--
-- The scan is an empty browse search paged to the end, the same one Auctionator's default scan
-- uses on Forever. C_AuctionHouse.ReplicateItems is in the client too, but it's unproven here,
-- and Auctionator leaves it off by default. Browse results give the lowest unit price per item.
local _, ns = ...

local ipairs, pairs, format, time, floor = ipairs, pairs, string.format, time, math.floor
local C_AuctionHouse, GetTime = C_AuctionHouse, GetTime
local GetRealmName, UnitFactionGroup = GetRealmName, UnitFactionGroup
local CreateFrame, pcall = CreateFrame, pcall
local C_Item, Enum = C_Item, Enum
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

local packPrice, unpackPrice = ns.Prices.Pack, ns.Prices.Unpack

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
ns.AddCommand("scan", "", L.AUCTIONPRICES_COMMAND, scanCommand, "ItemTooltips")

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

local function onClosed()
    open = false
    stopScan() -- prices seen so far are kept; the next visit scans again
    hideIndicator()
end

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

local events = {
    AUCTION_HOUSE_SHOW = onShow,
    AUCTION_HOUSE_CLOSED = onClosed,
    AUCTION_HOUSE_BROWSE_RESULTS_UPDATED = onResultsUpdated,
    AUCTION_HOUSE_BROWSE_RESULTS_ADDED = onResultsAdded,
}

function module:OnEnable()
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
end

function module:OnDisable()
    ItemTooltip.RedrawOnShift(self, false)
    ns.Prices.SetSource(nil)
    stopScan()
    hideIndicator()
    open = false
end

function module:OnOptionChanged(key)
    if key == "auctionator" then
        ns.Prices.Changed() -- every price now comes from the other source
        -- A scan running when Auctionator's prices take over stops, keeping what it saw.
        if ns.Prices.UsingAuctionator() then
            stopScan()
            hideIndicator()
        end
    end
end
