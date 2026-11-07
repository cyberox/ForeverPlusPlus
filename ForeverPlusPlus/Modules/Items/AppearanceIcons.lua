-- Appearance Icons: marks gear whose appearance you haven't collected yet with one of Blizzard's
-- appearance icons in a corner of the item's icon (top right by default, where nothing else of
-- ours or Blizzard's sits), so you wear it once before selling it. It shows in your bags and bank,
-- at merchants, in the auction house, and in the loot window and loot rolls, each with its own
-- checkbox.
--
-- "Not collected" is what the game's own item tooltip says: its "You haven't collected this
-- appearance" line (TRANSMOGRIFY_TOOLTIP_APPEARANCE_UNKNOWN), seen on Forever in Cameron's
-- screenshot (2026-11-06). C_TransmogCollection is in Forever's API too (Gethe forever branch,
-- TransmogItemsDocumentation.lua), but the tooltip line is what the player sees, so it decides.
-- Nothing is written onto Blizzard's frames: our own texture sits on the icon.
local _, ns = ...

local _G, pairs, wipe = _G, pairs, wipe
local C_Item, C_Container = C_Item, C_Container
local GetTime = GetTime

local L = ns.L
local ItemButtons = ns.ItemButtons

local module = ns.NewModule("AppearanceIcons", L.APPEARANCEICONS_DESC, {
    enabled = false,
    icon = "link", -- which atlas: "link" (the appearance link's mark) or "map" (the transmogrifier)
    corner = "TOPRIGHT", -- free of Upgrade Arrows (top left), Already Known (bottom left), and counts
    size = 14, -- in the bags; other places scale from it
    bags = true,
    bank = true,
    merchant = true,
    auction = true,
    loot = true,
})
module.title = L.APPEARANCEICONS_TITLE
module.category = "items"
module.added = "1.2.0"

local ICONS = {
    link = "transmog-icon-chat", -- 13x13, the mark on appearance links in chat
    map = "poi-transmogrifier", -- 29x36, the transmogrifier on the map
}

local CORNERS = {
    { "TOPLEFT", L.APPEARANCEICONS_CORNER_TOPLEFT },
    { "TOPRIGHT", L.APPEARANCEICONS_CORNER_TOPRIGHT },
    { "BOTTOMLEFT", L.APPEARANCEICONS_CORNER_BOTTOMLEFT },
    { "BOTTOMRIGHT", L.APPEARANCEICONS_CORNER_BOTTOMRIGHT },
}

module.options = {
    {
        key = "icon", name = L.APPEARANCEICONS_ICON, description = L.APPEARANCEICONS_ICON_DESC,
        section = L.APPEARANCEICONS_SECTION_LOOK,
        choices = {
            { "link", L.APPEARANCEICONS_ICON_LINK },
            { "map", L.APPEARANCEICONS_ICON_MAP },
        },
    },
    {
        key = "corner", name = L.APPEARANCEICONS_CORNER, description = L.APPEARANCEICONS_CORNER_DESC,
        section = L.APPEARANCEICONS_SECTION_LOOK, choices = CORNERS,
        -- Other modules' marks in the same corner. Settings reads their settings and shows these
        -- only while that module is on.
        conflicts = {
            {
                module = "UpgradeArrows", key = "corner", text = L.APPEARANCEICONS_CONFLICT_ARROW,
                when = function(db, other)
                    return db.corner == other.corner
                end,
            },
            {
                module = "UpgradeArrows", key = "downCorner", text = L.APPEARANCEICONS_CONFLICT_DOWN,
                when = function(db, other)
                    return other.downgrades and db.corner == other.downCorner and other.downCorner ~= other.corner
                end,
            },
            {
                module = "AlreadyKnown", key = "style", text = L.APPEARANCEICONS_CONFLICT_KNOWN,
                when = function(db, other)
                    return db.corner == "BOTTOMLEFT" and other.style ~= "tint"
                end,
            },
        },
    },
    {
        key = "size", name = L.APPEARANCEICONS_SIZE, description = L.APPEARANCEICONS_SIZE_DESC,
        section = L.APPEARANCEICONS_SECTION_LOOK, min = 8, max = 28, step = 1,
        format = L.APPEARANCEICONS_SIZE_FORMAT,
    },
    { key = "bags", name = L.APPEARANCEICONS_BAGS, description = L.APPEARANCEICONS_BAGS_DESC,
        section = L.APPEARANCEICONS_SECTION_SHOW },
    { key = "bank", name = L.APPEARANCEICONS_BANK, description = L.APPEARANCEICONS_BANK_DESC,
        section = L.APPEARANCEICONS_SECTION_SHOW },
    { key = "merchant", name = L.APPEARANCEICONS_MERCHANT, description = L.APPEARANCEICONS_MERCHANT_DESC,
        section = L.APPEARANCEICONS_SECTION_SHOW },
    { key = "auction", name = L.APPEARANCEICONS_AUCTION, description = L.APPEARANCEICONS_AUCTION_DESC,
        section = L.APPEARANCEICONS_SECTION_SHOW },
    { key = "loot", name = L.APPEARANCEICONS_LOOT, description = L.APPEARANCEICONS_LOOT_DESC,
        section = L.APPEARANCEICONS_SECTION_SHOW },
}

local RECHECK = 10 -- seconds an item found collected (or not gear) is believed before a new look
local WEAPON, ARMOR = 2, 4 -- Enum.ItemClass: only gear has an appearance

-- Is it collected --------------------------------------------------------------------------------

-- True when the tooltip says the appearance isn't collected, false when it doesn't, nil while
-- the game has no tooltip for the item yet (not cached), so that isn't taken for "collected".
local function tooltipUncollected(link)
    local unknown = _G.TRANSMOGRIFY_TOOLTIP_APPEARANCE_UNKNOWN
    if not unknown then
        return false
    end
    local lines = ItemButtons.TooltipLines(link)
    if not lines then
        return nil
    end
    for i = 2, #lines do -- line 1 is the name
        local text = lines[i].leftText
        if ns.IsText(text) and text == unknown then
            return true
        end
    end
    return false
end

local results = {} -- link -> true (not collected) or false, with the time it was looked at
local checkedAt = {}
local waiting = {} -- itemID -> true while the game has no tooltip for it yet
-- The lookups' own row on the Profiler page: reading an item's tooltip is the costly part.
local Profiler = ns.Profiler
local PART_LOOKUP = Profiler.Part(module, L.APPEARANCEICONS_PART_LOOKUP)

-- Whether an item link is gear whose appearance isn't collected. An answer is kept, but looked at
-- again after a while or when the collection changes: wearing it collects it.
local function uncollected(link)
    if not link then
        return false
    end
    local itemID, _, _, _, _, classID = C_Item.GetItemInfoInstant(link)
    if not itemID or (classID ~= WEAPON and classID ~= ARMOR) then
        return false
    end
    local now = GetTime()
    local result = results[link]
    if result ~= nil and now - (checkedAt[link] or 0) < RECHECK then
        return result
    end
    result = Profiler.Call(PART_LOOKUP, tooltipUncollected, link)
    if result == nil then
        waiting[itemID] = true -- not loaded yet: look again when its data arrives
        return false
    end
    results[link], checkedAt[link] = result, now
    return result
end

local function forget()
    wipe(results)
    wipe(checkedAt)
end

-- Marks -----------------------------------------------------------------------------------------

local marks = ItemButtons.Overlays(function(icon)
    return icon:GetParent():CreateTexture(nil, "OVERLAY", nil, 7)
end)

local hasAtlas = {} -- atlas -> whether this client has it, read in OnEnable

-- Shows or clears our mark on an icon. `scale` sizes it against the bags' icons.
local function setMark(icon, on, scale)
    local atlas = ICONS[module.db.icon] or ICONS.link
    if on and not hasAtlas[atlas] then
        on = false
    end
    local mark = marks:Set(icon, on)
    if not mark then
        return
    end
    local size = module.db.size * (scale or 1)
    local corner = module.db.corner
    mark:SetAtlas(atlas)
    mark:SetSize(size, size)
    mark:ClearAllPoints()
    local x = corner:find("LEFT") and 1 or -1
    local y = corner:find("TOP") and -1 or 1
    mark:SetPoint(corner, icon, corner, x, y)
end

-- Bags and bank -----------------------------------------------------------------------------------

local function updateBag(frame)
    local on = module.db.bags
    ItemButtons.EachBagButton(frame, function(_, icon, bag, slot)
        local link = on and C_Container.GetContainerItemLink(bag, slot)
        setMark(icon, link and uncollected(link), 1)
    end)
end

local function updateBank()
    local on = module.db.bank
    ItemButtons.EachBankButton(function(icon, tab, slot)
        local link = on and tab and C_Container.GetContainerItemLink(tab, slot)
        setMark(icon, link and uncollected(link), 1)
    end)
end

-- Merchants -------------------------------------------------------------------------------------

local function updateMerchant()
    local on = module.db.merchant
    ItemButtons.EachMerchantItem(function(icon, index)
        setMark(icon, on and uncollected(_G.GetMerchantItemLink(index)), 1.15)
    end)
end

-- The buyback tab reuses the same buttons.
local function clearMerchant()
    ItemButtons.EachMerchantItem(function(icon)
        setMark(icon, false)
    end)
end

-- Auction house and loot ------------------------------------------------------------------------

local function updateAuction()
    local on = module.db.auction
    ItemButtons.EachAuctionRow(function(icon, itemID)
        setMark(icon, on and itemID and uncollected("item:" .. itemID), 0.85)
    end)
end

local function markLoot(icon, _, link)
    setMark(icon, module.db.loot and link and uncollected(link), 1)
end

local function markRoll(icon, link)
    setMark(icon, module.db.loot and link and uncollected(link), 1)
end

-- Module ----------------------------------------------------------------------------------------

local function refresh()
    local merchant = _G.MerchantFrame
    -- Only on the Merchant tab: Buyback shows its items on the same buttons.
    if merchant and merchant:IsShown() and (merchant.selectedTab or 1) == 1 then
        updateMerchant()
    end
    updateAuction()
    ItemButtons.EachOpenBag(updateBag)
    local bank = _G.BankFrame
    if bank and bank:IsShown() then
        updateBank()
    end
    ItemButtons.EachRoll(markRoll)
    ItemButtons.EachLootSlot(markLoot)
end

local refreshSoon = ns.Frames.Coalesce(function()
    if module.enabled then
        refresh()
    end
end, 0.5, module)

-- Item data arrives a little after a window opens; look again once it has, only for an item we
-- couldn't answer for yet, or while a merchant is open, whose links are missing until it loads.
local function onItemInfo(_, itemID)
    local merchant = _G.MerchantFrame
    if not ((itemID and waiting[itemID]) or (merchant and merchant:IsShown())) then
        return
    end
    if itemID then
        waiting[itemID] = nil
    end
    refreshSoon()
end

-- Collecting an appearance (wearing it, or one like it) changes the answers.
local function onCollectionChanged()
    forget()
    refreshSoon()
end

function module:OnEnable()
    for _, atlas in pairs(ICONS) do
        hasAtlas[atlas] = ns.Frames.HasAtlas(atlas)
    end
    self:Hook("MerchantFrame_UpdateMerchantInfo", updateMerchant)
    self:Hook("MerchantFrame_UpdateBuybackInfo", clearMerchant)
    ItemButtons.HookBags(self, updateBag)
    ItemButtons.HookBank(self, updateBank)
    ItemButtons.HookLoot(self, markLoot)
    ItemButtons.HookRolls(self, markRoll)
    ItemButtons.HookAuction(self, updateAuction)
    self:On("GET_ITEM_INFO_RECEIVED", onItemInfo)
    self:On("PLAYER_EQUIPMENT_CHANGED", onCollectionChanged)
    for _, event in pairs({ "TRANSMOG_COLLECTION_UPDATED", "TRANSMOG_COLLECTION_SOURCE_ADDED" }) do
        if ns.HasEvent(event) then
            self:On(event, onCollectionChanged)
        end
    end
    refresh()
end

function module:OnDisable()
    ItemButtons.CancelAuction(updateAuction)
    marks:HideAll()
    forget()
    wipe(waiting)
end

function module:OnOptionChanged()
    if self.enabled then
        refresh()
    end
end
