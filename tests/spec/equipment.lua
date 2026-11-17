-- Equipment: what's worn, whether the character can use an item, and what an item would replace,
-- by the slot rules and by the client's own comparison. tests/spec/items.lua has the first checks
-- of the rules (rings, dual wield); these are the rest.
local T = ...
local ns, eq, same, player, game = T.ns, T.eq, T.same, T.player, T.game

-- The client's side, read from tables the checks change. Lib/Equipment.lua and Lib/ItemButtons.lua
-- keep these functions at load, so they're set first and the files loaded again.
local wornIDs = {} -- GetInventoryItemID: slot -> item ID
local usable = {} -- C_PlayerInfo.CanUseItem: item ID -> answer, or "error" to throw
local tooltips = {} -- C_TooltipInfo.GetHyperlink: link -> { lines }
local links = {} -- C_Item.GetItemLinkByGUID: GUID -> link
local places = {} -- C_Item.GetItemLocation: GUID -> "worn", "bag", "error", or anything else as it is
local SECRET = {} -- the one value the test client calls secret, once game.secret is it

GetInventoryItemID = function(_, slot)
    return wornIDs[slot]
end
C_PlayerInfo = {
    CanUseItem = function(itemID)
        if usable[itemID] == "error" then
            error("no such item")
        end
        return usable[itemID]
    end,
}
C_TooltipInfo = {
    GetHyperlink = function(link)
        return tooltips[link]
    end,
}
C_Item.GetItemLinkByGUID = function(guid)
    return links[guid]
end
C_Item.GetItemLocation = function(guid)
    local place = places[guid]
    if place == "error" then
        error("no such item")
    elseif place == "worn" or place == "bag" then
        return { IsEquipmentSlot = function() return place == "worn" end }
    end
    return place
end
ITEM_MIN_LEVEL = "Requires Level %d"
T.load("Lib/ItemButtons")
T.load("Lib/Equipment")
local Equipment = ns.Equipment

local function wornOf(slot)
    return game.worn[slot]
end
-- An item as GetItemInfoInstant answers: ID, type, subtype, equip location, icon, class, subclass.
local function item(id, equipLoc, classID, subclassID)
    return { id, "", "", equipLoc, 0, classID, subclassID }
end
local WEAPON, ARMOR = 2, 4

-- Slots ------------------------------------------------------------------------------------------

same(Equipment.Slots("INVTYPE_WEAPON"), { 16, 17 }, "slots: a one-hander goes in either hand")
same(Equipment.Slots("INVTYPE_2HWEAPON"), { 16 }, "slots: a two-hander is worn in the main hand")
same(Equipment.Slots("INVTYPE_TRINKET"), { 13, 14 }, "slots: two trinkets")
same(Equipment.Slots("INVTYPE_HOLDABLE"), { 17 }, "slots: an off-hand item")
same(Equipment.Slots("INVTYPE_RANGEDRIGHT"), Equipment.Slots("INVTYPE_THROWN"), "slots: guns and thrown share the ranged slot")
eq(Equipment.Slots(nil), nil, "slots: no type")
eq(Equipment.Slots("INVTYPE_BODY"), nil, "slots: a shirt isn't gear")
eq(Equipment.Slots("INVTYPE_AMMO"), nil, "slots: nor ammo")

-- What's worn ------------------------------------------------------------------------------------

game.worn = { [1] = "helm", [19] = "tabard", [20] = "bag" }
eq(Equipment.Worn(1), "helm", "worn: a slot's link")
eq(Equipment.Worn(2), nil, "worn: an empty slot")
game.worn[2] = ""
eq(Equipment.Worn(2), nil, "worn: an empty link is nothing")
game.secret = SECRET
game.worn[2] = SECRET
eq(Equipment.Worn(2), nil, "worn: a secret link is nothing")
eq(Equipment.IsWorn("helm"), true, "worn: found past a slot that can't be read")
game.secret, game.worn[2] = nil, nil
eq(Equipment.IsWorn("tabard"), true, "worn: the tabard slot counts")
eq(Equipment.IsWorn("bag"), false, "worn: a bag slot doesn't")
eq(Equipment.IsWorn(nil), false, "worn: no link")
eq(Equipment.LinkKey(nil), nil, "link key: nothing stays nothing")
eq(Equipment.LinkKey(12), 12, "link key: a number stays as it is")
eq(Equipment.LinkKey("|cffffffff|Hitem:2589:::::|h[Linen Cloth]|h|r"), "item:2589", "link key: only the item")

-- By GUID: worn when its location is an equipment slot.
places.onMe, places.inBag = "worn", "bag"
eq(Equipment.IsWornGUID("onMe"), true, "worn guid: in an equipment slot")
eq(Equipment.IsWornGUID("inBag"), false, "worn guid: in a bag")
eq(Equipment.IsWornGUID("gone"), false, "worn guid: an item the client doesn't know")
places.broken = "error"
eq(Equipment.IsWornGUID("broken"), false, "worn guid: a client error isn't worn")
places.odd = "somewhere"
eq(Equipment.IsWornGUID("odd"), false, "worn guid: a location that isn't one")
places.bare = {}
eq(Equipment.IsWornGUID("bare"), false, "worn guid: a location that can't say")
eq(Equipment.IsWornGUID(""), false, "worn guid: no GUID")
eq(Equipment.IsWornGUID(nil), false, "worn guid: nil")
game.secret = SECRET
places.hidden = { IsEquipmentSlot = function() return SECRET end }
eq(Equipment.IsWornGUID("hidden"), false, "worn guid: a secret answer isn't worn")
eq(Equipment.IsWornGUID(SECRET), false, "worn guid: a secret GUID")
game.secret = nil

-- The type and weapon kind of what's worn.
game.worn = { [16] = "pole", [17] = "shield" }
game.cachedItems.pole = item(100, "INVTYPE_2HWEAPON", WEAPON, 20)
game.cachedItems.shield = item(101, "INVTYPE_SHIELD", ARMOR, 6)
game.cachedItems[100], game.cachedItems[101] = game.cachedItems.pole, game.cachedItems.shield
wornIDs[16], wornIDs[17] = 100, 101
eq(Equipment.WeaponSubclass(16), Equipment.FISHING_POLE, "weapon kind: a fishing pole")
eq(Equipment.WeaponSubclass(17), nil, "weapon kind: a shield isn't a weapon")
eq(Equipment.WeaponSubclass(18), nil, "weapon kind: an empty slot")
wornIDs[18] = 102 -- worn, but the client hasn't the item's info yet
eq(Equipment.WeaponSubclass(18), nil, "weapon kind: an item not loaded yet")
game.cachedItems.blank = item(103, "", ARMOR, 0)
game.worn[4] = "blank"
eq(Equipment.WornType(4), nil, "worn type: an item with no equip location")
game.worn[5] = "unknown"
eq(Equipment.WornType(5), nil, "worn type: an item not loaded yet")

game.dualWield = true
eq(Equipment.CanDualWield(), true, "dual wield: on")
game.secret, game.dualWield = SECRET, SECRET
eq(Equipment.CanDualWield(), false, "dual wield: a secret answer is no")
game.secret, game.dualWield = nil, false

-- Whether the character can use an item --------------------------------------------------------------

player.level = 30
game.cachedItems["item:5"] = 5
eq(Equipment.CanUse("item:5", 30), true, "can use: gear of the character's own level")
eq(Equipment.CanUse("item:5", 0), true, "can use: no level requirement")
eq(Equipment.CanUse("item:5", nil), true, "can use: a level requirement not known")
eq(Equipment.CanUse("item:5", 31, 1), true, "can use: one level ahead, with one allowed")
eq(Equipment.CanUse("item:5", 32, 1), false, "can use: two levels ahead, with one allowed")
eq(Equipment.CanUse("item:5", 31, 0), false, "can use: none allowed ahead")
eq(Equipment.CanUse("item:nothing", 10), true, "can use: an item the client can't name is usable")

-- The client's own check, for class and proficiency.
usable[5] = false
eq(Equipment.CanUse("item:5", 10), false, "can use: the client says no")
eq(Equipment.CanUse("item:5"), false, "can use: and without a level requirement")
usable[5] = true
eq(Equipment.CanUse("item:5", 10), true, "can use: the client says yes")
usable[5] = "error"
eq(Equipment.CanUse("item:5", 10), true, "can use: a client error doesn't hide gear")
game.secret = SECRET
usable[5] = SECRET
eq(Equipment.CanUse("item:5", 10), true, "can use: nor a secret answer")
-- A level that can't be read is no reason to say no.
player.level = SECRET
usable[5] = true
eq(Equipment.CanUse("item:5", 60), true, "can use: a secret level skips the level check")
usable[5] = false
eq(Equipment.CanUse("item:5", 60), false, "can use: and the client's no still counts")
game.secret, player.level = nil, 30

-- Gear to grow into: the client says no to all of it for the level alone, so the tooltip's red
-- lines say whether anything else stops the character.
local RED, WHITE = { r = 1, g = 0.125, b = 0.125 }, { r = 1, g = 1, b = 1 }
local function tooltip(...)
    return { lines = { { leftText = "Mail Chest", leftColor = WHITE }, ... } }
end
local level31 = { leftText = "Requires Level 31", leftColor = RED }
usable[5] = false
eq(Equipment.CanUse("item:5", 31, 5), false, "can use: ahead, tooltip not loaded yet")
tooltips["item:5"] = tooltip({ leftText = "Mail", leftColor = WHITE }, level31)
eq(Equipment.CanUse("item:5", 31, 5), true, "can use: ahead, and only the level is red")
tooltips["item:5"] = tooltip({ leftText = "Classes: Paladin", leftColor = RED }, level31)
eq(Equipment.CanUse("item:5", 31, 5), false, "can use: ahead, but the class line is red too")
tooltips["item:5"] = tooltip({ leftText = "Chest", leftColor = WHITE, rightText = "Plate", rightColor = RED }, level31)
eq(Equipment.CanUse("item:5", 31, 5), false, "can use: ahead, but the armor type on the right is red")
tooltips["item:5"] = tooltip({ leftText = "Requires Level 40", leftColor = RED })
eq(Equipment.CanUse("item:5", 31, 5), false, "can use: a red level line for another level counts")
tooltips["item:5"] = { lines = { { leftText = "Mail Chest", leftColor = RED }, level31 } }
eq(Equipment.CanUse("item:5", 31, 5), true, "can use: the name's own color isn't a reason")
tooltips["item:5"] = { lines = {} }
eq(Equipment.CanUse("item:5", 31, 5), false, "can use: an empty tooltip isn't an answer")
-- At the character's level the client's no is about something else, whatever the tooltip shows.
tooltips["item:5"] = tooltip(level31)
eq(Equipment.CanUse("item:5", 30, 5), false, "can use: not ahead, the client's no stands")
usable[5], tooltips["item:5"] = nil, nil

-- The slot rules -------------------------------------------------------------------------------------

game.cachedItems.sword = item(110, "INVTYPE_WEAPON", WEAPON, 7)
game.cachedItems.mainOnly = item(111, "INVTYPE_WEAPONMAINHAND", WEAPON, 7)
game.cachedItems.offBlade = item(112, "INVTYPE_WEAPONOFFHAND", WEAPON, 15)
game.cachedItems.orb = item(113, "INVTYPE_HOLDABLE", ARMOR, 0)
game.cachedItems.great = item(114, "INVTYPE_2HWEAPON", WEAPON, 8)

game.worn = { [13] = "trinket1", [14] = "trinket2", [16] = "sword", [17] = "shield", [18] = "bow" }
same(Equipment.RuleRivals("INVTYPE_TRINKET", wornOf), { { "trinket1" }, { "trinket2" } }, "rules: either trinket")
game.worn[14] = nil
same(Equipment.RuleRivals("INVTYPE_TRINKET", wornOf), { { "trinket1" }, {} }, "rules: a trinket, or the empty slot")
same(Equipment.RuleRivals("INVTYPE_RANGED", wornOf), { { "bow" } }, "rules: a bow against the ranged slot")
same(Equipment.RuleRivals("INVTYPE_THROWN", wornOf), { { "bow" } }, "rules: thrown against the same slot")
same(Equipment.RuleRivals("INVTYPE_ROBE", wornOf), { {} }, "rules: a robe against an empty chest")

-- A two-hander replaces both hands, whatever they hold.
same(Equipment.RuleRivals("INVTYPE_2HWEAPON", wornOf), { { "sword", "shield" } }, "rules: a two-hander against both hands")
game.worn[17] = nil
same(Equipment.RuleRivals("INVTYPE_2HWEAPON", wornOf), { { "sword" } }, "rules: a two-hander against a lone main hand")
game.worn[16], game.worn[17] = nil, "orb"
same(Equipment.RuleRivals("INVTYPE_2HWEAPON", wornOf), { { "orb" } }, "rules: a two-hander against a lone off hand")
game.worn[17] = nil
same(Equipment.RuleRivals("INVTYPE_2HWEAPON", wornOf), { {} }, "rules: a two-hander with both hands empty")
game.worn[16] = "great"
same(Equipment.RuleRivals("INVTYPE_2HWEAPON", wornOf), { { "great" } }, "rules: a two-hander against a two-hander")

-- Hand items that have only one hand to go in.
game.worn[16], game.worn[17] = "sword", "shield"
game.dualWield = true
same(Equipment.RuleRivals("INVTYPE_WEAPONMAINHAND", wornOf), { { "sword" } },
    "rules: a main-hand weapon is never the off hand, dual wielding or not")
same(Equipment.RuleRivals("INVTYPE_WEAPONOFFHAND", wornOf), { { "shield" } }, "rules: an off-hand weapon against the off hand")
same(Equipment.RuleRivals("INVTYPE_HOLDABLE", wornOf), { { "shield" } }, "rules: an off-hand item against the off hand")
game.worn[16], game.worn[17] = "great", nil
same(Equipment.RuleRivals("INVTYPE_HOLDABLE", wornOf), { { "great" } }, "rules: an off-hand item takes a two-hander off")
same(Equipment.RuleRivals("INVTYPE_WEAPONOFFHAND", wornOf), { { "great" } }, "rules: so does an off-hand weapon")
same(Equipment.RuleRivals("INVTYPE_WEAPONMAINHAND", wornOf), { { "great" } }, "rules: and a main-hand weapon")

-- A one-hander dual wielding: either hand only while the off hand holds a weapon or nothing.
game.worn[16], game.worn[17] = "sword", "offBlade"
same(Equipment.RuleRivals("INVTYPE_WEAPON", wornOf), { { "sword" }, { "offBlade" } },
    "rules: dual wielding against an off-hand weapon, either hand")
game.worn[17] = "orb"
same(Equipment.RuleRivals("INVTYPE_WEAPON", wornOf), { { "sword" } },
    "rules: dual wielding with an off-hand item held, the main hand only")
game.worn[16], game.worn[17] = nil, nil
same(Equipment.RuleRivals("INVTYPE_WEAPON", wornOf), { {}, {} }, "rules: dual wielding with both hands empty")
game.dualWield = false
same(Equipment.RuleRivals("INVTYPE_WEAPON", wornOf), { {} }, "rules: one empty hand without dual wield")
game.worn[17] = "offBlade" -- left there from before the talent was dropped
same(Equipment.RuleRivals("INVTYPE_WEAPON", wornOf), { {} }, "rules: without dual wield the off hand isn't offered")

-- The rules read what's worn only through the function they're given.
local asked = {}
Equipment.RuleRivals("INVTYPE_FINGER", function(slot)
    asked[#asked + 1] = slot
    return "ring" .. slot
end)
same(asked, { 11, 12 }, "rules: each ring slot is asked for once")

-- The client's own comparison ------------------------------------------------------------------------

local comparison, comparedWith -- what C_TooltipComparison answers, and the link it was asked about
C_TooltipComparison = {
    GetItemComparisonInfo = function(compared)
        comparedWith = compared.hyperlink
        if comparison == "error" then
            error("not an item")
        end
        return comparison
    end,
}
links.g1, links.g2, links.gMain, links.gOff, links.gBag = "ring1", "ring2", "sword", "shield", "bagSword"

-- Rings: the one under "Equipped", and the other it cycles to.
game.worn = { [11] = "ring1", [12] = "ring2", [16] = "sword", [17] = "shield" }
comparison = { method = 0, item = { guid = "g1" }, additionalItems = { { guid = "g2" } } }
local rivals, partners = Equipment.Rivals("newRing", "INVTYPE_FINGER")
same(rivals, { { "ring1" }, { "ring2" } }, "client: either ring")
eq(partners, nil, "client: nothing worn with it")
eq(comparedWith, "newRing", "client: asked about the item's link")

-- The client compares with what's worn, so a free slot the item could take is offered too.
game.worn[12] = nil
comparison = { method = 0, item = { guid = "g1" }, additionalItems = {} }
same(Equipment.Rivals("newRing", "INVTYPE_FINGER"), { { "ring1" }, {} }, "client: a ring, or the empty second slot")
game.worn[11] = nil
comparison = { method = 0 }
rivals = Equipment.Rivals("newRing", "INVTYPE_FINGER")
local allEmpty = #rivals >= 1
for _, alternative in ipairs(rivals) do
    allEmpty = allEmpty and #alternative == 0
end
eq(allEmpty, true, "client: with no ring worn every alternative is an empty slot")
game.worn[11], game.worn[12] = "ring1", "ring2"

-- One slot, filled: only what's there.
game.worn[1], links.gHelm = "helm", "helm"
comparison = { method = 0, item = { guid = "gHelm" } }
same(Equipment.Rivals("newHelm", "INVTYPE_HEAD"), { { "helm" } }, "client: a helm against the helm")
-- An item the client names but can't link reads as nothing worn there.
comparison = { method = 0, item = { guid = "gUnknown" } }
same(Equipment.Rivals("newHelm", "INVTYPE_HEAD"), { {} }, "client: a worn item it can't link")

-- A two-hander: the pair it would replace, as one alternative.
comparison = { method = 1, item = { guid = "gMain" }, additionalItems = { { guid = "gOff" } } }
rivals, partners = Equipment.Rivals("newGreat", "INVTYPE_2HWEAPON")
same(rivals, { { "sword", "shield" } }, "client: a two-hander against both hands")
eq(partners, nil, "client: and nothing worn with it")
comparison = { method = 1, item = { guid = "gMain" } }
same(Equipment.Rivals("newGreat", "INVTYPE_2HWEAPON"), { { "sword" } }, "client: a two-hander against a lone main hand")
comparison = { method = 1, additionalItems = { { guid = "gOff" } } }
same(Equipment.Rivals("newGreat", "INVTYPE_2HWEAPON"), { { "shield" } }, "client: a two-hander against a lone off hand")

-- A shield against a worn two-hander: the client pairs it with a main hand from the bags. Those
-- are worn with it, not rivals.
game.worn[16], game.worn[17], links.gGreat = "great", nil, "great"
comparison = { method = 2, item = { guid = "gGreat" },
    additionalItems = { { guid = "gBag" }, { hyperlink = "bagMace" }, {}, { guid = "gUnknown" } } }
rivals, partners = Equipment.Rivals("newShield", "INVTYPE_SHIELD")
same(rivals, { { "great" } }, "client: a shield against the two-hander alone")
same(partners, { "bagSword", "bagMace" }, "client: the bag items it could be worn with, by GUID or link")
comparison.method = 3
rivals, partners = Equipment.Rivals("newSword", "INVTYPE_WEAPON")
same(rivals, { { "great" } }, "client: a one-hander against the two-hander")
same(partners, { "bagSword", "bagMace" }, "client: with an off hand from the bags")
comparison.additionalItems = nil
rivals, partners = Equipment.Rivals("newSword", "INVTYPE_WEAPON")
same(partners, {}, "client: nothing in the bags to wear with it")

-- A one-hander dual wielding with a free off hand: the main hand, or the free hand.
game.worn[16], game.worn[17], game.dualWield = "sword", nil, true
comparison = { method = 0, item = { guid = "gMain" } }
same(Equipment.Rivals("newSword", "INVTYPE_WEAPON"), { { "sword" }, {} }, "client: dual wielding, the free off hand is offered")
game.dualWield = false
same(Equipment.Rivals("newSword", "INVTYPE_WEAPON"), { { "sword" } }, "client: not without dual wield")

-- The client's own numbers for its methods are used when it has them.
Enum.TooltipComparisonMethod = { Single = 10, WithBothHands = 11, WithBagMainHandItem = 12, WithBagOffHandItem = 13 }
game.worn[17] = "shield"
comparison = { method = 11, item = { guid = "gMain" }, additionalItems = { { guid = "gOff" } } }
same(Equipment.Rivals("newGreat", "INVTYPE_2HWEAPON"), { { "sword", "shield" } }, "client: both hands by the client's number")
comparison.method = 1 -- not that method on this client
same(Equipment.Rivals("newGreat", "INVTYPE_2HWEAPON"), { { "sword" }, { "shield" } },
    "client: another number is an ordinary comparison")
comparison = { method = 13, item = { guid = "gMain" }, additionalItems = { { guid = "gBag" } } }
rivals, partners = Equipment.Rivals("newSword", "INVTYPE_WEAPON")
same(partners, { "bagSword" }, "client: bag partners by the client's number")
Enum.TooltipComparisonMethod = nil

-- A secret method reads as an ordinary comparison.
game.secret = SECRET
comparison = { method = SECRET, item = { guid = "g1" }, additionalItems = { { guid = "g2" } } }
same(Equipment.Rivals("newRing", "INVTYPE_FINGER"), { { "ring1" }, { "ring2" } }, "client: a secret method")

-- When the client doesn't answer, the rules do.
local byRules = { { "ring1" }, { "ring2" } }
comparison = SECRET
same(Equipment.Rivals("newRing", "INVTYPE_FINGER"), byRules, "fallback: a secret answer")
game.secret = nil
comparison = nil
same(Equipment.Rivals("newRing", "INVTYPE_FINGER"), byRules, "fallback: no answer")
comparison = "error"
same(Equipment.Rivals("newRing", "INVTYPE_FINGER"), byRules, "fallback: a client error")
comparison = 5
same(Equipment.Rivals("newRing", "INVTYPE_FINGER"), byRules, "fallback: an answer that isn't a table")
C_TooltipComparison = {}
same(Equipment.Rivals("newRing", "INVTYPE_FINGER"), byRules, "fallback: a client without the call")
C_TooltipComparison = nil
same(Equipment.Rivals("newRing", "INVTYPE_FINGER"), byRules, "fallback: a client without the comparison API")
same(Equipment.Rivals("tabard", "INVTYPE_TABARD"), {}, "fallback: nothing for what isn't gear")
