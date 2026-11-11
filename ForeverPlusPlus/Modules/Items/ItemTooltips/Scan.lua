-- Item Tooltips' Auction Prices, its scan: scans the auction house when it opens, keeping the
-- lowest buyout of each item in the prices AuctionPrices.lua saves and gives out, with a spinner
-- in the auction house's title bar while it runs, and /fpp scan. Shares the part through
-- `internal.auction` (see AuctionPrices.lua), which turns this on and off with it.
--
-- The scan is an empty browse search paged to the end, the same one Auctionator's default scan
-- uses on Forever. C_AuctionHouse.ReplicateItems is in the client too, but it's unproven here,
-- and Auctionator leaves it off by default. Browse results give the lowest unit price per item.
local _, ns = ...

local ipairs, pairs, format, time, floor = ipairs, pairs, string.format, time, math.floor
local C_AuctionHouse, GetTime = C_AuctionHouse, GetTime
local CreateFrame, pcall = CreateFrame, pcall
local wipe = wipe

local L = ns.L

local auction = ns.modules.ItemTooltips.internal.auction
local module = auction.part
local house = auction.House
local packPrice, unpackPrice = ns.Prices.Pack, ns.Prices.Unpack

local SCAN_INTERVAL = 15 * 60 -- seconds between automatic scans, as Auctionator waits

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
                    auction.NameSoon() -- a newly priced item: named on the next look, not a minute later
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

local function onClosed()
    open = false
    stopScan() -- prices seen so far are kept; the next visit scans again
    hideIndicator()
end

-- On and off with the part ---------------------------------------------------------------------

local events = {
    AUCTION_HOUSE_SHOW = onShow,
    AUCTION_HOUSE_CLOSED = onClosed,
    AUCTION_HOUSE_BROWSE_RESULTS_UPDATED = onResultsUpdated,
    AUCTION_HOUSE_BROWSE_RESULTS_ADDED = onResultsAdded,
}

---Starts listening to the auction house, from the part's OnEnable.
function auction.EnableScan()
    for event, fn in pairs(events) do
        module:On(event, fn)
    end
    -- Hooked by name, each skipped when this client doesn't have it; the hooks do nothing unless
    -- a scan is running.
    for _, name in ipairs(SEARCHES) do
        module:Hook(C_AuctionHouse, name, onOtherSearch)
    end
    for _, name in ipairs(QUERIES) do
        module:Hook(C_AuctionHouse, name, onBlizzardQuery)
    end
    -- Turned on with the auction house already open, its show event has passed.
    local frame = _G.AuctionHouseFrame
    open = frame and frame:IsShown() and true or false
end

---Stops a scan that's running, keeping the prices it saw, and hides its indicator.
function auction.StopScan()
    stopScan()
    hideIndicator()
end

---Stops everything, from the part's OnDisable.
function auction.DisableScan()
    auction.StopScan()
    open = false
end
