-- Already Known: marks items you can't learn again, such as recipes you know and mounts, pets,
-- and toys you already have, with Blizzard's green ready-check mark on the item's icon (or a
-- green tint). It shows on merchants, the auction house, bags, the inbox, and the loot window
-- and loot rolls, each with its own checkbox.
--
-- "Known" is what the game's own item tooltip says: its "Already known" line, or the pet
-- line's "Collected (1/3)". Forever has no caged battle pets (item 82800, the Pet Cage, isn't in
-- its data), so auction rows are items only.
-- Nothing is written onto Blizzard's frames: our own textures sit on the icons, a check mark and
-- a green tint that multiplies the icon, and the icon's own color is never touched.
local _, ns = ...

local _G, type, strfind = _G, type, strfind
local C_Item, C_Container = C_Item, C_Container
local C_ToyBox = C_ToyBox
local GetTime = GetTime

local L = ns.L
local ItemButtons = ns.ItemButtons

local module = ns.NewModule("AlreadyKnown", L.ALREADYKNOWN_DESC, {
    enabled = true,
    style = "check", -- "check" mark, "tint" the icon green, or "both"
    merchant = true,
    auction = true,
    bags = true,
    mail = true,
    loot = true,
})
module.title = L.ALREADYKNOWN_TITLE
module.category = "items"

module.options = {
    {
        key = "style", name = L.ALREADYKNOWN_STYLE, description = L.ALREADYKNOWN_STYLE_DESC,
        section = L.ALREADYKNOWN_SECTION_LOOK,
        choices = {
            { "check", L.ALREADYKNOWN_STYLE_CHECK },
            { "tint", L.ALREADYKNOWN_STYLE_TINT },
            { "both", L.ALREADYKNOWN_STYLE_BOTH },
        },
    },
    {
        key = "merchant", name = L.ALREADYKNOWN_MERCHANT, description = L.ALREADYKNOWN_MERCHANT_DESC,
        section = L.ALREADYKNOWN_SECTION_SHOW,
    },
    {
        key = "auction", name = L.ALREADYKNOWN_AUCTION, description = L.ALREADYKNOWN_AUCTION_DESC,
        section = L.ALREADYKNOWN_SECTION_SHOW,
    },
    {
        key = "bags", name = L.ALREADYKNOWN_BAGS, description = L.ALREADYKNOWN_BAGS_DESC,
        section = L.ALREADYKNOWN_SECTION_SHOW,
    },
    {
        key = "mail", name = L.ALREADYKNOWN_MAIL, description = L.ALREADYKNOWN_MAIL_DESC,
        section = L.ALREADYKNOWN_SECTION_SHOW,
    },
    {
        key = "loot", name = L.ALREADYKNOWN_LOOT, description = L.ALREADYKNOWN_LOOT_DESC,
        section = L.ALREADYKNOWN_SECTION_SHOW, changed = "0.9.0",
    },
}

local TINT = { 0.45, 1, 0.45 }
local CHECK_TEXTURE = "Interface\\RaidFrame\\ReadyCheck-Ready" -- Blizzard's ready check mark
local RECHECK = 10 -- seconds an item that isn't known is believed before it's looked at again

-- Is it known ---------------------------------------------------------------------------------

-- The pet line's "Collected (%d/%d)" as a pattern. Probe: the string is the client's.
local petKnown = _G.ITEM_PET_KNOWN and "^" .. ns.Text.FormatPattern(_G.ITEM_PET_KNOWN)

-- Nil while the game has no tooltip for the item yet (not cached), so that isn't taken for "no".
local function tooltipKnown(link)
    local lines = ItemButtons.TooltipLines(link)
    if not lines then
        return nil
    end
    local alreadyKnown = _G.ITEM_SPELL_KNOWN
    for i = 1, #lines do
        local text = lines[i].leftText
        if ns.IsText(text)
            and (text == alreadyKnown or (petKnown and strfind(text, petKnown))) then
            return true
        end
    end
    return false
end

-- Only these kinds of item can be known, so only they are worth a tooltip lookup: recipes (and
-- class books), companion pets and mounts, glyphs, caged pets, and toys. Enum.ItemClass and
-- Enum.ItemMiscellaneousSubclass values.
local RECIPE, MISC, GLYPH, BATTLE_PET = 9, 15, 16, 17
local PET, MOUNT = 2, 5

local kinds = {} -- itemID -> whether its kind can be known, which never changes

-- Whether an item's kind can be known. "No" is remembered only for an item whose class says so:
-- toys are misc items, and a toy's info may not have loaded yet.
local function canBeKnown(itemID, classID, subclassID)
    local can = kinds[itemID]
    if can ~= nil then
        return can
    end
    if classID == RECIPE or classID == GLYPH or classID == BATTLE_PET then
        can = true
    elseif classID == MISC and (subclassID == PET or subclassID == MOUNT) then
        can = true
    else
        can = C_ToyBox and C_ToyBox.GetToyInfo and C_ToyBox.GetToyInfo(itemID) ~= nil or false
    end
    if can or (classID and classID ~= MISC) then
        kinds[itemID] = can
    end
    return can
end

local known = {} -- key -> true, once known (you don't forget a recipe)
local checked = {} -- key -> GetTime() it was last found not known
local waiting = {} -- itemID -> true while the game has no tooltip for it yet
-- The lookups' own row on the Profiler page: reading an item's tooltip is the costly part.
local Profiler = ns.Profiler
local PART_LOOKUP = Profiler.Part(module, L.ALREADYKNOWN_PART_LOOKUP)

-- Whether `test(arg)` says known, remembering it so a full bag isn't looked up on every update.
-- Not known is remembered only briefly, since learning something makes it known.
local function check(key, test, arg)
    if known[key] then
        return true
    end
    local now = GetTime()
    local last = checked[key]
    if last and now - last < RECHECK then
        return false
    end
    local result = Profiler.Call(PART_LOOKUP, test, arg)
    if result then
        known[key] = true
        return true
    elseif result == false then
        checked[key] = now
    elseif type(key) == "number" then
        waiting[key] = true -- not loaded yet: look again when its data arrives
    end
    return false
end

---Whether an item link (or "item:123") is one the player already has.
local function itemKnown(link)
    if not link then
        return false
    end
    local itemID, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(link)
    if not itemID or not canBeKnown(itemID, classID, subclassID) then
        return false
    end
    return check(itemID, tooltipKnown, link)
end

-- Marks -----------------------------------------------------------------------------------------

-- Our own textures over the icon, never its color: Blizzard colors icons itself (red for an item
-- you can't use), and putting a color back would wipe Blizzard's.
local tints = ItemButtons.Overlays(function(icon)
    return ItemButtons.Tint(icon, TINT)
end)
local checks = ItemButtons.Overlays(function(icon)
    local check = icon:GetParent():CreateTexture(nil, "OVERLAY", nil, 7)
    check:SetTexture(CHECK_TEXTURE)
    check:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", 1, 1)
    return check
end)

-- Shows or clears our mark on an icon, as the Mark option says. `size` is the check mark's size,
-- chosen per place since the icons differ.
local function setMark(icon, on, size)
    local style = module.db.style
    tints:Set(icon, on and style ~= "check")
    local check = checks:Set(icon, on and style ~= "tint")
    if check then
        check:SetSize(size, size)
    end
end

local function clearMarks()
    tints:HideAll()
    checks:HideAll()
end

-- Merchants -------------------------------------------------------------------------------------

local function updateMerchant()
    local on = module.db.merchant
    ItemButtons.EachMerchantItem(function(icon, index)
        setMark(icon, on and itemKnown(_G.GetMerchantItemLink(index)), 16)
    end)
end

-- The buyback tab reuses the same buttons.
local function clearMerchant()
    ItemButtons.EachMerchantItem(function(icon)
        setMark(icon, false)
    end)
end

-- Auction house ---------------------------------------------------------------------------------

local function updateAuction()
    local on = module.db.auction
    ItemButtons.EachAuctionRow(function(icon, itemID)
        setMark(icon, on and itemID and itemKnown("item:" .. itemID), 12)
    end)
end

-- Bags ------------------------------------------------------------------------------------------

local function updateBag(frame)
    local on = module.db.bags
    ItemButtons.EachBagButton(frame, function(_, icon, bag, slot)
        local link = on and C_Container.GetContainerItemLink(bag, slot)
        setMark(icon, link and itemKnown(link), 14)
    end)
end

-- Mail ------------------------------------------------------------------------------------------

local function mailLink(mailIndex, attachment)
    local get = _G.GetInboxItemLink or (_G.C_Mail and _G.C_Mail.GetInboxItemLink)
    return get and get(mailIndex, attachment)
end

-- Known when the mail has attachments and every one of them is.
local function mailKnown(mailIndex)
    local any = false
    for n = 1, _G.ATTACHMENTS_MAX_RECEIVE or 16 do
        local link = mailLink(mailIndex, n)
        if link then
            if not itemKnown(link) then
                return false
            end
            any = true
        end
    end
    return any
end

local function updateInbox()
    local inbox = _G.InboxFrame
    if not inbox then
        return
    end
    local perPage = _G.INBOXITEMS_TO_DISPLAY or 7
    local on = module.db.mail
    for i = 1, perPage do
        local icon = _G["MailItem" .. i .. "ButtonIcon"]
        setMark(icon, on and mailKnown(((inbox.pageNum or 1) - 1) * perPage + i), 14)
    end
end

local function updateOpenMail()
    local inbox = _G.InboxFrame
    local mailIndex = inbox and inbox.openMailID
    local on = module.db.mail and mailIndex
    for n = 1, _G.ATTACHMENTS_MAX_RECEIVE or 16 do
        local icon = _G["OpenMailAttachmentButton" .. n .. "IconTexture"]
        local link = on and mailLink(mailIndex, n)
        setMark(icon, link and itemKnown(link), 14)
    end
end

-- Loot ------------------------------------------------------------------------------------------

local function markLoot(icon, _, link)
    setMark(icon, module.db.loot and link and itemKnown(link), 14)
end

-- Loot rolls are marked as the frame shows, before the player picks Need.
local function markRoll(icon, link)
    setMark(icon, module.db.loot and link and itemKnown(link), 14)
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
    local mail = _G.MailFrame
    if mail and mail:IsShown() then
        updateInbox()
        updateOpenMail()
    end
    ItemButtons.EachRoll(markRoll)
    ItemButtons.EachLootSlot(markLoot)
end

local refreshSoon = ns.Frames.Coalesce(function()
    if module.enabled then
        refresh()
    end
end, 0.5, module)

-- Item data arrives a little after a window opens; look again once it has. This fires for every
-- item the game loads (the auction house loads hundreds), so only for an item we couldn't answer
-- for yet, or while a merchant or the mailbox is open, whose links are missing until it loads.
local function onItemInfo(_, itemID)
    local merchant, mail = _G.MerchantFrame, _G.MailFrame
    if not ((itemID and waiting[itemID]) or (merchant and merchant:IsShown())
        or (mail and mail:IsShown())) then
        return
    end
    if itemID then
        waiting[itemID] = nil
    end
    refreshSoon()
end

function module:OnEnable()
    self:Hook("MerchantFrame_UpdateMerchantInfo", updateMerchant)
    self:Hook("MerchantFrame_UpdateBuybackInfo", clearMerchant)
    -- Forever's mail frame redraws through its mixins (InboxMixin:Update, OpenMailMixin:Update,
    -- build 70338 on), not Classic's InboxFrame_Update and OpenMail_Update.
    self:Hook(_G.InboxFrame, "Update", updateInbox)
    self:Hook(_G.OpenMailFrame, "Update", updateOpenMail)
    ItemButtons.HookBags(self, updateBag)
    ItemButtons.HookLoot(self, markLoot)
    ItemButtons.HookRolls(self, markRoll)
    ItemButtons.HookAuction(self, updateAuction)
    self:On("GET_ITEM_INFO_RECEIVED", onItemInfo)
    refresh()
end

function module:OnDisable()
    ItemButtons.CancelAuction(updateAuction)
    clearMarks()
end

function module:OnOptionChanged()
    if self.enabled then
        refresh()
    end
end
