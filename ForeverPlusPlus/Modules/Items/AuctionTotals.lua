-- Auction Totals: on the auction house's Auctions page, left of Cancel Auction, what the auctions
-- still up are listed for in all, and the money on its way from the ones that sold. The list, its
-- rows, and the button stay Blizzard's; ours is one line of text on a frame of our own.
local _, ns = ...

local L = ns.L

local C_AuctionHouse, Enum, CreateFrame, format = C_AuctionHouse, Enum, CreateFrame, format

local ADDON = "Blizzard_AuctionHouseUI"
local GAP = 12 -- between our text and the button

local module = ns.NewModule("AuctionTotals", L.AUCTIONTOTALS_DESC, {
    enabled = true,
})
module.title = L.AUCTIONTOTALS_TITLE
module.category = "items"
module.added = "1.9.0"

-- Probe: the owned auctions list is Mainline's auction house, which Forever has.
function module:IsAvailable()
    return C_AuctionHouse and C_AuctionHouse.GetNumOwnedAuctions and C_AuctionHouse.GetOwnedAuctionInfo
        and true or false
end

local holder, label

---What the auctions still up ask for in all, and what the sold ones are paying, in copper. An
---auction with no buyout counts its bid. A row that's still up holds the price of one of its
---items, so it's multiplied by how many; a sold row already holds the whole amount on its way
---(Blizzard_AuctionHouseTableBuilder.lua shows each the same way).
---@return number listed
---@return number sold
local function totals()
    local soldStatus = Enum.AuctionStatus and Enum.AuctionStatus.Sold
    local listed, sold = 0, 0
    for index = 1, C_AuctionHouse.GetNumOwnedAuctions() do
        local info = C_AuctionHouse.GetOwnedAuctionInfo(index)
        if info then
            local price = info.buyoutAmount or info.bidAmount or 0
            if soldStatus and info.status == soldStatus then
                sold = sold + price
            else
                listed = listed + price * (info.quantity or 1)
            end
        end
    end
    return listed, sold
end

local function refresh()
    if not label then
        return
    end
    local listed, sold = totals()
    local white = HIGHLIGHT_FONT_COLOR
    local text = format(L.AUCTIONTOTALS_FORMAT,
        white:WrapTextInColorCode(ns.Money(listed)), white:WrapTextInColorCode(ns.Money(sold)))
    -- The game hands the list over a part at a time when it's long; until it has it all, the
    -- sums are of what's here so far.
    local full = C_AuctionHouse.HasFullOwnedAuctionResults
    if full and not full() then
        text = format(L.AUCTIONTOTALS_PARTIAL, text)
    end
    label:SetText(text)
end

-- A child of Cancel Auction, so it shows on the Auctions tab and hides on Bids as the button does.
local function build()
    local frame = _G.AuctionHouseFrame
    local auctions = frame and frame.AuctionsFrame
    local button = auctions and auctions.CancelAuctionButton
    if holder or not button then
        return
    end
    holder = CreateFrame("Frame", nil, button)
    holder:SetSize(1, 1)
    holder:SetPoint("RIGHT", button, "LEFT", -GAP, 0)
    label = holder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("RIGHT")
end

local function onLoaded()
    build()
    if holder then
        holder:Show()
        refresh()
    end
end

function module:OnEnable()
    self:On("OWNED_AUCTIONS_UPDATED", refresh)
    ns.AddOns.WhenLoaded(ADDON, onLoaded)
end

function module:OnDisable()
    ns.AddOns.Cancel(ADDON, onLoaded)
    if holder then
        holder:Hide()
    end
end
