-- What the player wears, and what a piece of gear would replace: the inventory slots an item's
-- type goes in, the worn item in each, whether the character can use an item, and the worn items
-- an item competes with (rings and trinkets against the weaker, a two-hander against both hands,
-- a one-hander against either hand when dual wielding), asked of the client's own item
-- comparison first (C_TooltipComparison, the "Equipped" tooltips' source; it answers addon code
-- on Forever, Gear Probe, build 70425) and worked out from the slot rules when it doesn't answer.
-- Nothing is cached: the worn links are cheap to read, and they change under us.
local _, ns = ...

local _G, ipairs, type, pcall, select, format = _G, ipairs, type, pcall, select, string.format
local GetInventoryItemLink, UnitLevel = GetInventoryItemLink, UnitLevel
local CanDualWield, GetInventoryItemID = CanDualWield, GetInventoryItemID
local C_Item, C_PlayerInfo, Enum = C_Item, C_PlayerInfo, Enum

local Equipment = {
    WEAPON = 2, -- Enum.ItemClass.Weapon
    FISHING_POLE = 20, -- Enum.ItemWeaponSubclass.Fishingpole
}
ns.Equipment = Equipment

-- Each item type's inventory slots. Shirts, tabards, bags, quivers, and ammo aren't gear worth a
-- score, so they're left out and `Slots` gives nil for them.
local SLOTS = {
    INVTYPE_HEAD = { 1 },
    INVTYPE_NECK = { 2 },
    INVTYPE_SHOULDER = { 3 },
    INVTYPE_CHEST = { 5 },
    INVTYPE_ROBE = { 5 },
    INVTYPE_WAIST = { 6 },
    INVTYPE_LEGS = { 7 },
    INVTYPE_FEET = { 8 },
    INVTYPE_WRIST = { 9 },
    INVTYPE_HAND = { 10 },
    INVTYPE_FINGER = { 11, 12 },
    INVTYPE_TRINKET = { 13, 14 },
    INVTYPE_CLOAK = { 15 },
    INVTYPE_WEAPON = { 16, 17 },
    INVTYPE_2HWEAPON = { 16 },
    INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_WEAPONOFFHAND = { 17 },
    INVTYPE_SHIELD = { 17 },
    INVTYPE_HOLDABLE = { 17 },
    INVTYPE_RANGED = { 18 },
    INVTYPE_RANGEDRIGHT = { 18 },
    INVTYPE_THROWN = { 18 },
    INVTYPE_RELIC = { 18 },
}

---The inventory slots an item type (INVTYPE_*) goes in, or nil for something that isn't gear.
---@param invType string?
---@return number[]?
function Equipment.Slots(invType)
    return invType and SLOTS[invType] or nil
end

---The link of the item worn in a slot, or nil.
---@param slot number
---@return string?
function Equipment.Worn(slot)
    local link = GetInventoryItemLink and GetInventoryItemLink("player", slot)
    return ns.IsText(link, true) and link or nil
end

---The part of a link that names the item with its suffix and enchant (`item:6541::...:12734`),
---without the color, the name, or trailing empty fields, so two links to the same item read the
---same whoever made them (a tooltip's and GetInventoryItemLink's differ in their tails). A
---string that isn't a link is returned as it is.
---@param link string
---@return string
function Equipment.LinkKey(link)
    local key = type(link) == "string" and link:match("item:[^|]+")
    if not key then
        return link
    end
    return (key:gsub(":+$", ""))
end

---Whether this exact item (by link, suffix and enchant included) is worn.
---@param link string
---@return boolean
function Equipment.IsWorn(link)
    local key = Equipment.LinkKey(link)
    for slot = 1, 19 do
        local worn = Equipment.Worn(slot)
        if worn and Equipment.LinkKey(worn) == key then
            return true
        end
    end
    return false
end

---Whether the item with this GUID is worn: its location is an equipment slot. False when the
---client can't say.
---@param guid string
---@return boolean
function Equipment.IsWornGUID(guid)
    if not (ns.IsText(guid, true) and C_Item and C_Item.GetItemLocation) then
        return false
    end
    local ok, location = pcall(C_Item.GetItemLocation, guid)
    return ok and type(location) == "table" and location.IsEquipmentSlot
        and ns.IsTrue(location:IsEquipmentSlot()) or false
end

---The item type (INVTYPE_*) of what's worn in a slot, or nil.
---@param slot number
---@return string?
function Equipment.WornType(slot)
    local link = Equipment.Worn(slot)
    local equipLoc
    if link then
        -- Not `link and f()`: that keeps only f's first value.
        equipLoc = select(4, C_Item.GetItemInfoInstant(link))
    end
    return ns.IsText(equipLoc, true) and equipLoc or nil
end

---The weapon subclass (Enum.ItemWeaponSubclass) of what's worn in a slot, or nil when it holds no
---weapon.
---@param slot number
---@return number?
function Equipment.WeaponSubclass(slot)
    local itemID = GetInventoryItemID and GetInventoryItemID("player", slot)
    if not (itemID and C_Item.GetItemInfoInstant) then
        return nil
    end
    local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
    if classID ~= Equipment.WEAPON then
        return nil
    end
    return subclassID
end

---Whether the character can dual wield now (Rogues and Hunters, Warriors and Shamans with the
---talent). False when the client can't say.
---@return boolean
function Equipment.CanDualWield()
    return ns.IsTrue(CanDualWield and CanDualWield())
end

-- For gear the character is too low level for: whether anything but the level stops them, by a
-- red line in its tooltip other than "Requires Level N". C_PlayerInfo.CanUseItem counts the level
-- too, so it says no to all of it (a level 17 Warrior's level 18 mail chest). False while the
-- tooltip isn't loaded.
local function usableButForLevel(link, minLevel)
    local ItemButtons = ns.ItemButtons
    local lines = ItemButtons.TooltipLines(link)
    if not lines then
        return false
    end
    local levelText = _G.ITEM_MIN_LEVEL and format(_G.ITEM_MIN_LEVEL, minLevel)
    for i = 2, #lines do -- line 1 is the name, in its quality color
        local line = lines[i]
        local text = ns.IsReadable(line) and line.leftText
        if not (levelText and ns.IsText(text) and text == levelText) and ItemButtons.IsRedLine(line) then
            return false
        end
    end
    return true
end

---Whether the character can use an item: its class and proficiencies by the client's own check,
---and its level requirement against the character's level. True when the client can't say.
---@param link string
---@param minLevel? number the item's level requirement
---@param ahead? number levels below the requirement the character may still be (gear to grow into)
---@return boolean
function Equipment.CanUse(link, minLevel, ahead)
    local tooLow = false
    if minLevel and minLevel > 0 then
        local level = UnitLevel and UnitLevel("player")
        if ns.IsNumber(level) then
            if level + (ahead or 0) < minLevel then
                return false
            end
            tooLow = level < minLevel
        end
    end
    if C_PlayerInfo and C_PlayerInfo.CanUseItem and C_Item and C_Item.GetItemInfoInstant then
        local itemID = C_Item.GetItemInfoInstant(link)
        if itemID then
            local ok, usable = pcall(C_PlayerInfo.CanUseItem, itemID)
            if ok and ns.IsReadable(usable) and usable == false then
                return tooLow and usableButForLevel(link, minLevel)
            end
        end
    end
    return true
end

-- Rivals ------------------------------------------------------------------------------------------
-- What an item would replace, as alternatives: each a list of worn links whose scores add up
-- (a two-hander replaces both hands), and the alternative worth least is the rival (either ring).
-- An empty alternative is an empty slot.

-- The link an item GUID names, or nil.
local function linkOf(guid)
    if not (ns.IsText(guid, true) and C_Item and C_Item.GetItemLinkByGUID) then
        return nil
    end
    local ok, link = pcall(C_Item.GetItemLinkByGUID, guid)
    return ok and ns.IsText(link, true) and link or nil
end

-- A comparison item's link, or nil for nothing worn there.
local function comparedLink(entry)
    return type(entry) == "table" and ns.IsReadable(entry) and linkOf(entry.guid) or nil
end

-- The client's own answer: the item it would show under "Equipped" and the others it cycles
-- through, or, for a two-hander, the pair it would replace. Nil when the client doesn't answer.
-- For a one-hander or an off hand against a worn two-hander, the client pairs it with a hand
-- item from the bags (WithBagMainHandItem, WithBagOffHandItem): then `additionalItems` are those
-- bag items, worn together with it, not rivals (Blizzard's TooltipComparisonManager, forever
-- branch), and come back as the second value.
local function clientRivals(link)
    local api = _G.C_TooltipComparison
    if not (api and api.GetItemComparisonInfo) then
        return nil
    end
    local ok, info = pcall(api.GetItemComparisonInfo, { hyperlink = link })
    if not (ok and type(info) == "table" and ns.IsReadable(info)) then
        return nil
    end
    local method = ns.IsReadable(info.method) and info.method or 0
    local both = Enum and Enum.TooltipComparisonMethod and Enum.TooltipComparisonMethod.WithBothHands or 1
    local first = comparedLink(info.item)
    local extra = ns.IsReadable(info.additionalItems) and type(info.additionalItems) == "table"
        and info.additionalItems or {}
    if method == both then
        local pair = {}
        pair[#pair + 1] = first
        for _, entry in ipairs(extra) do
            pair[#pair + 1] = comparedLink(entry)
        end
        return { pair }
    end
    local methods = Enum and Enum.TooltipComparisonMethod
    local bagMain = methods and methods.WithBagMainHandItem or 2
    local bagOff = methods and methods.WithBagOffHandItem or 3
    if method == bagMain or method == bagOff then
        local partners = {}
        for _, entry in ipairs(extra) do
            local partner = type(entry) == "table" and ns.IsReadable(entry)
                and (linkOf(entry.guid) or ns.IsText(entry.hyperlink, true) and entry.hyperlink) or nil
            partners[#partners + 1] = partner
        end
        return { { first } }, partners
    end
    local alternatives = { { first } }
    for _, entry in ipairs(extra) do
        alternatives[#alternatives + 1] = { comparedLink(entry) }
    end
    return alternatives
end

-- Which slots an item type competes for, by the rules, each a list of slots.
local function ruleSlots(invType)
    local slots = SLOTS[invType]
    if not slots then
        return {}
    end
    if invType == "INVTYPE_2HWEAPON" then
        return { { 16, 17 } }
    elseif invType == "INVTYPE_WEAPON" then
        -- Either hand when dual wielding, unless the off hand holds a shield or an off-hand
        -- item, which a second weapon shouldn't push out.
        local off = Equipment.WornType(17)
        local offIsWeapon = off == nil or off == "INVTYPE_WEAPON" or off == "INVTYPE_WEAPONOFFHAND"
        -- A worn two-hander fills the off hand too: a one-hander takes its place, not an empty hand.
        if Equipment.CanDualWield() and offIsWeapon
            and Equipment.WornType(16) ~= "INVTYPE_2HWEAPON" then
            return { { 16 }, { 17 } }
        end
        return { { 16 } }
    elseif slots[1] == 17 and Equipment.WornType(16) == "INVTYPE_2HWEAPON" then
        return { { 16 } } -- a shield or off-hand item means taking the two-hander off
    elseif #slots == 2 then
        return { { slots[1] }, { slots[2] } } -- rings and trinkets: either
    end
    return { { slots[1] } }
end

---Pure form of the rules, for tests and for a client without the comparison API: the alternatives
---an item type competes with as worn links, read through `worn(slot)`.
---@param invType string
---@param worn fun(slot: number): string?
---@return table alternatives lists of links
function Equipment.RuleRivals(invType, worn)
    local alternatives = {}
    for _, slots in ipairs(ruleSlots(invType)) do
        local links = {}
        for _, slot in ipairs(slots) do
            links[#links + 1] = worn(slot)
        end
        alternatives[#alternatives + 1] = links
    end
    return alternatives
end

---The worn items an item would replace, as alternatives (lists of links whose scores add up; an
---empty list is an empty slot). From the client's own comparison when it answers, else the rules.
---Second, for a hand item against a worn two-hander, the bag items the client would wear with it
---in the other hand (any one of them), or nil.
---@param link string
---@param invType string the item's INVTYPE_*
---@return table alternatives
---@return string[]? partners
function Equipment.Rivals(link, invType)
    local alternatives, partners = clientRivals(link)
    if not alternatives then
        return Equipment.RuleRivals(invType, Equipment.Worn)
    end
    if partners then
        return alternatives, partners
    end
    -- An empty slot the item could take (the second ring, a free off hand) beats any rival; the
    -- client compares with what's worn, so offer it too.
    for _, slots in ipairs(ruleSlots(invType)) do
        if #slots == 1 and not Equipment.Worn(slots[1]) then
            alternatives[#alternatives + 1] = {}
        end
    end
    return alternatives
end
