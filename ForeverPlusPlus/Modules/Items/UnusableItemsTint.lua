-- Unusable Items Tint: tints red the icons of items you can't use, in your bags, the bank, at
-- merchants, in the auction house, and in the loot window and loot rolls, the way Blizzard tints
-- them in a merchant's list.
--
-- "Can't use" is what the game's own item tooltip says: any line in Blizzard's red, such as a
-- class, armor or weapon type, level, profession skill, or reputation you don't have. That
-- covers more than C_PlayerInfo.CanUseItem, which doesn't say whether it checks level. "Already
-- known" is red too but left out: that's Already Known's mark, not "can't use". A recipe is
-- judged by its own lines only, not those of the item it makes.
--
-- The tint is our own texture over the icon, multiplying it (MOD blend), so it looks like
-- Blizzard's red vertex color without touching the icon: bags set the icon's color themselves
-- on every cooldown update, which would wipe a color we set.
local _, ns = ...

local _G, wipe, select, pairs = _G, wipe, select, pairs
local C_Item, C_Container = C_Item, C_Container

local L = ns.L
local ItemButtons = ns.ItemButtons

local module = ns.NewModule("UnusableItemsTint", L.UNUSABLEITEMSTINT_DESC, {
    enabled = true,
    bags = true,
    bank = true,
    merchant = true,
    auction = false,
    loot = false,
})
module.title = L.UNUSABLEITEMSTINT_TITLE
module.category = "items"
module.added = "0.8.0"

module.options = {
    ItemButtons.PlaceOption("bags", L.UNUSABLEITEMSTINT_BAGS_DESC),
    ItemButtons.PlaceOption("bank", L.UNUSABLEITEMSTINT_BANK_DESC),
    ItemButtons.PlaceOption("merchant", L.UNUSABLEITEMSTINT_MERCHANT_DESC),
    ItemButtons.PlaceOption("auction", L.UNUSABLEITEMSTINT_AUCTION_DESC, { added = "0.9.0" }),
    ItemButtons.PlaceOption("loot", L.UNUSABLEITEMSTINT_LOOT_DESC, { added = "0.9.0" }),
}

local TINT = { 0.9, 0, 0 } -- Blizzard's merchant tint for an item you can't use

-- Is it usable ------------------------------------------------------------------------------------

local RECIPE = 9 -- Enum.ItemClass.Recipe

-- A recipe's tooltip has the item it makes inside it, from a blank line after the recipe's name
-- to its "Use: Teaches you how to craft" line; the recipe's reagents and "Requires
-- Blacksmithing (85)" come after. That item's armor type or level in red says nothing about
-- whether you can learn the recipe, so those lines are skipped.
local function isBlank(text)
    return ns.IsReadable(text) and text == ""
end

local function isUse(text)
    local use = _G.ITEM_SPELL_TRIGGER_ONUSE
    return use and ns.IsText(text) and text:sub(1, #use) == use or false
end

-- True when a line is red, false when none is, nil while the game has no tooltip for the item
-- yet (not cached), so that isn't taken for "usable".
local function tooltipUnusable(link)
    local lines = ItemButtons.TooltipLines(link)
    if not lines then
        return nil
    end
    local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(link)
    local recipe = classID == RECIPE
    local crafted = false -- inside a recipe's crafted item
    local alreadyKnown = _G.ITEM_SPELL_KNOWN
    for i = 2, #lines do -- line 1 is the name, in its quality color
        local line = lines[i]
        local text = line.leftText
        if recipe then
            if isUse(text) then
                crafted = false
            elseif isBlank(text) then
                crafted = true
            end
        end
        if not crafted and not (alreadyKnown and ns.IsReadable(text) and text == alreadyKnown)
            and ItemButtons.IsRedLine(line) then
            return true
        end
    end
    return false
end

-- The lookups' own row on the Profiler page: reading an item's tooltip is the costly part.
local Profiler = ns.Profiler
local PART_LOOKUP = Profiler.Part(module, L.UNUSABLEITEMSTINT_PART_LOOKUP)

local results = {} -- itemID -> true (can't use) or false, until the player changes
local waiting = {} -- itemID -> true while the game has no tooltip for it yet

---Whether an item link is one the player can't use. False for no item, or one not loaded yet.
local function unusable(link)
    if not link then
        return false
    end
    local itemID = C_Item.GetItemInfoInstant(link)
    if not itemID then
        return false
    end
    local result = results[itemID]
    if result == nil then
        result = Profiler.Call(PART_LOOKUP, tooltipUnusable, link)
        results[itemID] = result
        if result == nil then
            waiting[itemID] = true
        end
    end
    return result or false
end

-- Tints -----------------------------------------------------------------------------------------

local tints = ItemButtons.Overlays(function(icon)
    return ItemButtons.Tint(icon, TINT)
end)

-- Bags ------------------------------------------------------------------------------------------

local function updateBag(frame)
    local on = module.db.bags
    ItemButtons.EachBagButton(frame, function(_, icon, bag, slot)
        local link = on and C_Container.GetContainerItemLink(bag, slot)
        tints:Set(icon, link and unusable(link))
    end)
end

-- Bank ------------------------------------------------------------------------------------------

local function updateBank()
    local on = module.db.bank
    ItemButtons.EachBankButton(function(icon, tab, slot)
        local link = on and tab and C_Container.GetContainerItemLink(tab, slot)
        tints:Set(icon, link and unusable(link))
    end)
end

-- Merchants -------------------------------------------------------------------------------------

-- Whether Blizzard already tints this merchant item red, so ours isn't laid on top of it.
local function blizzardTinted(index)
    local info = _G.C_MerchantFrame and _G.C_MerchantFrame.GetItemInfo
        and _G.C_MerchantFrame.GetItemInfo(index)
    return info and (info.isPurchasable == false or info.isUsable == false)
end

local function updateMerchant()
    local on = module.db.merchant
    ItemButtons.EachMerchantItem(function(icon, index)
        local link = on and _G.GetMerchantItemLink(index)
        tints:Set(icon, link and not blizzardTinted(index) and unusable(link))
    end)
end

-- The buyback tab reuses the same buttons, and Blizzard tints those itself.
local function clearMerchant()
    ItemButtons.EachMerchantItem(function(icon)
        tints:Set(icon, false)
    end)
end

-- Auction house ---------------------------------------------------------------------------------

local function updateAuction()
    local on = module.db.auction
    ItemButtons.EachAuctionRow(function(icon, itemID)
        tints:Set(icon, on and itemID and unusable("item:" .. itemID))
    end)
end

-- Loot ------------------------------------------------------------------------------------------

-- Blizzard tints a slot you can't loot (locked) red itself, so ours isn't laid on top of it.
local function tintLoot(icon, slot, link)
    local locked = slot and _G.GetLootSlotInfo and select(6, _G.GetLootSlotInfo(slot))
    tints:Set(icon, module.db.loot and link and not locked and unusable(link))
end

local function tintRoll(icon, link)
    tints:Set(icon, module.db.loot and link and unusable(link))
end

-- Module ----------------------------------------------------------------------------------------

local function refresh()
    ItemButtons.EachOpenBag(updateBag)
    local bank = _G.BankFrame
    if bank and bank:IsShown() then
        updateBank()
    end
    local merchant = _G.MerchantFrame
    if merchant and merchant:IsShown() and (merchant.selectedTab or 1) == 1 then
        updateMerchant()
    end
    updateAuction()
    ItemButtons.EachLootSlot(tintLoot)
    ItemButtons.EachRoll(tintRoll)
end

local forget

-- Leveling, training, and skill-ups only ever make an item usable, so only the "can't use"
-- answers can be wrong now. Forgetting just those spares a tooltip read per item on every skill
-- point.
local function forgetUnusable()
    for itemID, result in pairs(results) do
        if result then
            results[itemID] = nil
        end
    end
end

-- Item data arrives a little after a window opens, and what you can use changes as you level
-- and train: look again shortly, once for a burst of events. The answers are forgotten then
-- too, not at the event, since the tooltip can still say the old level for a moment.
local refreshSoon = ns.Frames.Coalesce(function()
    if forget then
        forget = false
        forgetUnusable()
    end
    if module.enabled then
        refresh()
    end
end, 0.5, module)

local function onPlayerChanged()
    forget = true
    refreshSoon()
end

-- Only items we couldn't answer for yet are worth another look; this fires for every item.
local function onItemInfo(_, itemID)
    if itemID and waiting[itemID] then
        waiting[itemID] = nil
        refreshSoon()
    end
end

function module:OnEnable()
    self:Hook("MerchantFrame_UpdateMerchantInfo", updateMerchant)
    self:Hook("MerchantFrame_UpdateBuybackInfo", clearMerchant)
    ItemButtons.HookBags(self, updateBag)
    ItemButtons.HookBank(self, updateBank)
    ItemButtons.HookLoot(self, tintLoot)
    ItemButtons.HookRolls(self, tintRoll)
    ItemButtons.HookAuction(self, updateAuction)
    self:On("GET_ITEM_INFO_RECEIVED", onItemInfo) -- items without a tooltip yet weren't kept
    self:On("PLAYER_LEVEL_UP", onPlayerChanged)
    self:On("SKILL_LINES_CHANGED", onPlayerChanged)
    self:On("LEARNED_SPELL_IN_SKILL_LINE", onPlayerChanged)
    refresh()
end

function module:OnDisable()
    ItemButtons.CancelAuction(updateAuction)
    forget = false
    wipe(results) -- you may level while it's off
    wipe(waiting)
    tints:HideAll()
end

function module:OnOptionChanged()
    if self.enabled then
        refresh()
    end
end
