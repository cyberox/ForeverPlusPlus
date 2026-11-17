-- Waylaid Crates' auction house category: a Waylaid Crates row at the top or bottom of the auction
-- house's category list that fills Blizzard's browse list with every item the crates in your bags
-- still need, one row each, the way the Favorites star lists your favorites. What's still needed
-- is every crate's bundles added up, less what's already in your bags and bank. Items are found
-- by name.
--
-- The rows come from C_AuctionHouse.SearchForItemKeys: Blizzard's browse list shows whatever
-- browse results arrive, whoever asked for them. A real category would mean adding to Blizzard's
-- AuctionCategories table, which would taint the auction house, so the row is our own button in
-- the category buttons' art, and the list's scroll box gives up one row's room for it (put back
-- when the option goes off).
local _, ns = ...

local _G, ipairs, pairs, type, sort, format, wipe = _G, ipairs, pairs, type, table.sort, string.format, wipe
local CreateFrame, GameTooltip, Enum = CreateFrame, GameTooltip, Enum
local C_Item, C_TooltipInfo, C_AuctionHouse = C_Item, C_TooltipInfo, C_AuctionHouse
local GRAY_FONT_COLOR, HIGHLIGHT_FONT_COLOR, GREEN_FONT_COLOR = GRAY_FONT_COLOR, HIGHLIGHT_FONT_COLOR,
    GREEN_FONT_COLOR

local L = ns.L

local internal = ns.modules.WaylaidCrates.internal

local module = ns.modules.WaylaidCrates:NewPart({
    key = "list", name = L.WAYLAIDCRATES_LIST, description = L.WAYLAIDCRATES_LIST_DESC,
    section = L.WAYLAIDCRATES_LIST,
    choices = {
        { "off", L.WAYLAIDCRATES_LIST_OFF },
        { "top", L.WAYLAIDCRATES_LIST_TOP },
        { "bottom", L.WAYLAIDCRATES_LIST_BOTTOM },
    },
}, {
    list = "bottom", -- the auction house entry: "off", "top" or "bottom" of the categories
})

local ROW_WIDTH, ROW_HEIGHT = 132, 21 -- Blizzard's category buttons (AuctionCategoryButtonTemplate)

local row -- our Waylaid Crates row
local listAnchors = {} -- the category list's scroll box TOPLEFT and BOTTOMRIGHT anchors before we moved it
local crates = 0 -- crates in the bags when last read
local needs = {} -- what they still need, by name: { name, count, itemID? }
local listed -- itemIDs our last search found auctions for, or nil before it has answered
local awaiting = false -- our search's results haven't all come in yet

-- Needs -----------------------------------------------------------------------------------------

local function byName(a, b)
    return a.name < b.name
end

-- Item link -> its bundles ({} for an item that isn't a crate). A crate's list is fixed per
-- link, so each item's tooltip is read once, not on every bag change and every hover of the row.
local bundlesOf = {}

-- Reads every crate in the bags.
local function readCrates()
    wipe(needs)
    crates = 0
    local wanted, names = {}, {}
    ns.Bags.Each(function(bag, slot, info) -- the reagent bag too
        local link = info and info.hyperlink
        local bundles = link and bundlesOf[link]
        if link and not bundles then
            local data = C_TooltipInfo.GetBagItem(bag, slot)
            bundles = data and internal.Bundles(data)
            -- Not kept while the item hasn't loaded (a lone "Retrieving" line).
            local lines = data and data.lines
            if bundles and (#bundles > 0 or (type(lines) == "table" and #lines > 1)) then
                bundlesOf[link] = bundles
            end
        end
        if bundles and #bundles > 0 then
            crates = crates + 1
            for _, bundle in ipairs(bundles) do
                local count, name = bundle[1], bundle[2]
                if not wanted[name] then
                    names[#names + 1] = name
                end
                wanted[name] = (wanted[name] or 0) + count
            end
        end
    end, true)
    for _, name in ipairs(names) do
        local itemID = ns.Prices.ItemByName(name)
        -- What's in the bank counts too: it needn't be bought.
        local still = wanted[name] - (itemID and C_Item.GetItemCount(itemID, true) or 0)
        if still > 0 then
            needs[#needs + 1] = { name = name, count = still, itemID = itemID }
        end
    end
    sort(needs, byName)
end

-- Whether any need can be searched for.
local function searchable()
    for _, need in ipairs(needs) do
        if need.itemID then
            return true
        end
    end
    return false
end

-- Gold like Blizzard's categories while there's something to list, gray otherwise.
local function refresh()
    readCrates()
    row:SetNormalFontObject(searchable() and "GameFontNormalSmall" or "GameFontDisableSmall")
end

local function setSelected(selected)
    row.selected = selected
    row.SelectedTexture:SetShown(selected)
end

-- Searching -------------------------------------------------------------------------------------

-- On Forever the first search for these keys comes back with every row "None available", and
-- the same search sent again fills in the prices (seen in game: the second or third click
-- showed them). So while any row has no quantity, the search goes out again, up to RETRIES
-- times, before a row is taken as having no auctions.
local RETRIES = 3
local RETRY_DELAY = 0.5 -- seconds
local tries = 0 -- searches sent for this click
local retryTimer = ns.Frames.Timer(module)

local function search()
    module:Off("AUCTION_HOUSE_THROTTLED_SYSTEM_READY", search)
    local ready = C_AuctionHouse.IsThrottledMessageSystemReady
    if ready and not ready() then
        module:On("AUCTION_HOUSE_THROTTLED_SYSTEM_READY", search)
        return
    end
    local keys = {}
    for _, need in ipairs(needs) do
        if need.itemID then
            keys[#keys + 1] = C_AuctionHouse.MakeItemKey(need.itemID)
        end
    end
    if #keys == 0 then
        return
    end
    -- As the Favorites star does: the Buy display, where the browse list is (clearing the
    -- category doesn't leave an item's or commodity's buy page), no Blizzard category selected,
    -- then an empty list while the search runs. Only on the click, not a retry, so the rows stay
    -- up meanwhile. Probed: Mainline's frame.
    if tries == 0 then
        local frame = _G.AuctionHouseFrame
        local modes = _G.AuctionHouseFrameDisplayMode
        if frame and modes and modes.Buy and frame.GetDisplayMode and frame.SetDisplayMode
            and frame:GetDisplayMode() ~= modes.Buy then
            frame:SetDisplayMode(modes.Buy)
        end
        local list = frame and frame.CategoriesList
        if list and list.SetSelectedCategory then
            list:SetSelectedCategory(nil)
        end
        local mixin = _G.AuctionHouseFrameMixin
        if frame and frame.TriggerEvent and mixin and mixin.Event and mixin.Event.BrowseSearchStarted then
            frame:TriggerEvent(mixin.Event.BrowseSearchStarted)
        end
    end
    local order = Enum.AuctionHouseSortOrder
    local sorts = order and { { sortOrder = order.Name, reverseSort = false } } or {}
    tries = tries + 1
    listed, awaiting = nil, true
    setSelected(true)
    C_AuctionHouse.SearchForItemKeys(keys, sorts)
end

-- Sends the search again, unless something else replaced our list in the meantime.
local function retry()
    if row and row.selected and not awaiting then
        search()
    end
end

-- Notes which items our search found auctions for, so the tooltip can say which have none.
-- Returns whether any row came back with no quantity.
local function addResults(results)
    listed = listed or {}
    local empty = false
    for _, result in ipairs(results or {}) do
        local itemID = result.itemKey and result.itemKey.itemID
        if itemID and (result.totalQuantity or 0) > 0 then
            listed[itemID] = true
        elseif itemID then
            empty = true
        end
    end
    awaiting = not C_AuctionHouse.HasFullBrowseResults()
    return empty
end

-- New browse results that aren't ours (a search, favorites, a sort) replace our list.
local function onResultsUpdated()
    if awaiting then
        listed = nil
        local empty = addResults(C_AuctionHouse.GetBrowseResults())
        if empty and not awaiting and tries < RETRIES then
            listed = nil -- not known yet: the tooltip shouldn't say None listed
            retryTimer:Start(RETRY_DELAY, retry)
        end
    elseif row and row.selected then
        setSelected(false)
    end
end

local function onResultsAdded(_, added)
    if awaiting then
        addResults(added)
    end
end

-- Picking one of Blizzard's categories deselects ours.
local function onCategorySelected()
    if row and row.selected and not awaiting then
        setSelected(false)
    end
end

-- Row -------------------------------------------------------------------------------------------

local function onClick()
    tries = 0
    refresh()
    search()
end

local function onEnter(self)
    self.HighlightTexture:Show()
    refresh()
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L.WAYLAIDCRATES_NEEDS, HIGHLIGHT_FONT_COLOR:GetRGB())
    if crates == 0 then
        GameTooltip:AddLine(L.WAYLAIDCRATES_NO_CRATES, GRAY_FONT_COLOR:GetRGB())
    elseif #needs == 0 then
        GameTooltip:AddLine(L.WAYLAIDCRATES_DONE, GRAY_FONT_COLOR:GetRGB())
    end
    local wr, wg, wb = HIGHLIGHT_FONT_COLOR:GetRGB()
    local gr, gg, gb = GRAY_FONT_COLOR:GetRGB()
    for _, need in ipairs(needs) do
        local count = format("%d", need.count)
        if not need.itemID then
            GameTooltip:AddDoubleLine(need.name, L.WAYLAIDCRATES_NOT_FOUND, gr, gg, gb, gr, gg, gb)
        elseif listed and not awaiting and not listed[need.itemID] then
            GameTooltip:AddDoubleLine(need.name, format("%s  %s", count,
                GRAY_FONT_COLOR:WrapTextInColorCode(L.WAYLAIDCRATES_NONE_LISTED)), wr, wg, wb, wr, wg, wb)
        else
            GameTooltip:AddDoubleLine(need.name, count, wr, wg, wb, wr, wg, wb)
        end
    end
    if searchable() then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(ns.Gamepad.Hint(L.WAYLAIDCRATES_HINT), GREEN_FONT_COLOR:GetRGB())
    end
    GameTooltip:Show()
end

local function onLeave(self)
    self.HighlightTexture:Hide()
    GameTooltip:Hide()
end

-- Bags change while the auction house is open (a purchase lands): read the crates again.
local function onShow()
    refresh()
    module:On("BAG_UPDATE_DELAYED", refresh)
end

local function onHide()
    module:Off("BAG_UPDATE_DELAYED", refresh)
    module:Off("AUCTION_HOUSE_THROTTLED_SYSTEM_READY", search)
    awaiting = false
    setSelected(false)
end

-- A texture in one of the category button's atlases, sized and placed as Blizzard's top-level
-- category buttons set theirs (AuctionHouseFilterButton_SetUp).
local function texture(layer, atlas, width, height, point, x)
    local tex = row:CreateTexture(nil, layer)
    tex:SetAtlas(atlas, false)
    tex:SetSize(width, height)
    tex:SetPoint(point, x, 0)
    return tex
end

local function makeRow(list)
    row = CreateFrame("Button", nil, list)
    row:SetSize(ROW_WIDTH, ROW_HEIGHT)
    texture("BACKGROUND", "auctionhouse-nav-button", 136, 32, "TOPLEFT", -2)
    row.HighlightTexture = texture("BORDER", "auctionhouse-nav-button-highlight", ROW_WIDTH, ROW_HEIGHT,
        "LEFT", 0)
    row.HighlightTexture:Hide()
    row.SelectedTexture = texture("ARTWORK", "auctionhouse-nav-button-select", ROW_WIDTH, ROW_HEIGHT,
        "LEFT", 0)
    row.SelectedTexture:SetBlendMode("ADD")
    row.SelectedTexture:Hide()
    local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("LEFT", 8, 0)
    text:SetPoint("RIGHT", -4, 0)
    text:SetJustifyH("LEFT")
    text:SetShadowOffset(1, -1)
    row:SetFontString(text)
    row:SetText(L.WAYLAIDCRATES_CATEGORY)
    row:SetPushedTextOffset(1, -1)
    row:SetScript("OnClick", onClick)
    row:SetScript("OnEnter", onEnter)
    row:SetScript("OnLeave", onLeave)
    row:SetScript("OnShow", onShow)
    row:SetScript("OnHide", onHide)
end


-- The scroll box's anchor for `point`: { relativeTo, relativePoint, x, y }, or nil.
local function anchorOf(box, point)
    for i = 1, box:GetNumPoints() do
        local p, relativeTo, relativePoint, x, y = box:GetPoint(i)
        if p == point then
            return { relativeTo, relativePoint, x, y }
        end
    end
end

local function categoryList()
    local frame = _G.AuctionHouseFrame
    local list = frame and frame.CategoriesList
    return list, list and list.ScrollBox
end

-- Puts the scroll box's anchors back where Blizzard had them.
local function restoreList(box)
    for point, anchor in pairs(listAnchors) do
        box:SetPoint(point, anchor[1], anchor[2], anchor[3], anchor[4])
    end
end

-- Our row in the first slot with the list one row lower ("top"), or under the list, which ends a
-- row higher ("bottom"). The list's view pads its rows 3 from the left.
local function place()
    local _, box = categoryList()
    if not (row and box) then
        return
    end
    restoreList(box)
    local top, bottom = listAnchors.TOPLEFT, listAnchors.BOTTOMRIGHT
    row:ClearAllPoints()
    if module.db.list == "top" then
        row:SetPoint("TOPLEFT", top[1], top[2], top[3] + 3, top[4])
        box:SetPoint("TOPLEFT", top[1], top[2], top[3], top[4] - ROW_HEIGHT)
    else
        box:SetPoint("BOTTOMRIGHT", bottom[1], bottom[2], bottom[3], bottom[4] + ROW_HEIGHT)
        row:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 3, 0)
    end
    row:Show()
end

local function setup()
    local list, box = categoryList()
    if not (box and C_AuctionHouse.SearchForItemKeys and C_AuctionHouse.MakeItemKey
        and C_TooltipInfo and C_TooltipInfo.GetBagItem) then
        return
    end
    if not listAnchors.TOPLEFT then
        local top, bottom = anchorOf(box, "TOPLEFT"), anchorOf(box, "BOTTOMRIGHT")
        if not (top and bottom) then
            return -- not the layout we know: leave the list alone
        end
        listAnchors.TOPLEFT, listAnchors.BOTTOMRIGHT = top, bottom
    end
    if not row then
        makeRow(list)
        module:Hook(list, "SetSelectedCategory", onCategorySelected)
    end
    place()
end

local function teardown()
    if row then
        row:Hide()
    end
    local _, box = categoryList()
    if box then
        restoreList(box)
    end
end

module:OnWhile("list", {
    AUCTION_HOUSE_BROWSE_RESULTS_UPDATED = onResultsUpdated,
    AUCTION_HOUSE_BROWSE_RESULTS_ADDED = onResultsAdded,
})

function module:OnEnable()
    ns.AddOns.WhenLoaded("Blizzard_AuctionHouseUI", setup)
end

function module:OnDisable()
    ns.AddOns.Cancel("Blizzard_AuctionHouseUI", setup)
    listed, awaiting = nil, false
    teardown()
end

-- Moving between the top and the bottom of the list.
function module:OnOptionChanged(key)
    if key == "list" then
        place()
    end
end
