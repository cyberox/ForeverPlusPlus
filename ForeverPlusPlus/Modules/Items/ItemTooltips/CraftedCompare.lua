-- Item Tooltips' Compare Crafted Gear: a recipe in your bags that makes gear shows Blizzard's own
-- comparison with what you wear, as the gear itself would.
--
-- A recipe's tooltip data is the recipe's item (`id`) with the crafted item's link as its
-- `hyperlink`, and the crafted item's lines nested after its first line (`/run` on a linked Plans:
-- Copper Chain Vest, 2026-11-05: id 3609, hyperlink [Copper Chain Vest], line 2 a NestedBlock).
-- Blizzard compares a tooltip's item by its GUID when it has one, else by its link
-- (TooltipComparisonManager:CreateComparisonItem, `forever` UI source), so a linked recipe already
-- compares its crafted item while one in your bags compares the recipe, which has nothing to
-- compare. For a bag recipe this asks the same comparison by the crafted item's link, only where
-- Blizzard would compare anyway (Always Compare Items, or Shift).
--
-- Which recipes: gear you can use (your class, armor, and weapon skills, whatever its level, so a
-- recipe you'll craft later still compares), and optionally only recipes of professions you have.
local _, ns = ...

local pcall = pcall
local Enum, C_Item, C_CVar, C_TooltipComparison = Enum, C_Item, C_CVar, C_TooltipComparison
local IsModifiedClick = IsModifiedClick

local L = ns.L
local Equipment, Professions = ns.Equipment, ns.Professions

local module = ns.modules.ItemTooltips:NewPart({
    key = "craftedCompare", name = L.CRAFTEDCOMPARE_TITLE, description = L.CRAFTEDCOMPARE_DESC,
    section = L.CRAFTEDCOMPARE_TITLE, added = "1.0.3",
    choices = {
        { "usable", L.CRAFTEDCOMPARE_USABLE },
        { "professions", L.CRAFTEDCOMPARE_PROFESSIONS },
        { "off", L.CRAFTEDCOMPARE_OFF },
    },
}, {
    craftedCompare = "usable",
})

local RECIPE = Enum.ItemClass and Enum.ItemClass.Recipe or 9

-- The profession that crafts a recipe's item, by the recipe's subclass (Enum.ItemRecipeSubclass:
-- 1 Leatherworking, 2 Tailoring, 3 Engineering, 4 Blacksmithing, 10 Jewelcrafting), as its skill
-- line. Only those that make gear.
local CRAFTS_GEAR = {
    [1] = 165,
    [2] = 197,
    [3] = 202,
    [4] = Professions.BLACKSMITHING,
    [10] = 755, -- should a later build add it
}

-- Whether Blizzard compares the item under the mouse now: Always Compare Items, or Shift.
local function comparing()
    local always = C_CVar and C_CVar.GetCVar and C_CVar.GetCVar("alwaysCompareItems")
    return always == "1" or (IsModifiedClick and IsModifiedClick("COMPAREITEMS")) or false
end

-- The crafted item's link when the tooltip is a recipe in a slot (it has a GUID) that makes gear
-- this setting compares, else nil.
local function craftedGear(data)
    if not (ns.IsText(data.guid, true) and ns.IsText(data.hyperlink, true)) then
        return nil -- a linked recipe compares its crafted item already
    end
    local recipe = ns.IsNumber(data.id) and data.id
    if not (recipe and C_Item and C_Item.GetItemInfoInstant) then
        return nil
    end
    local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(recipe)
    local line = classID == RECIPE and CRAFTS_GEAR[subclassID]
    if not line then
        return nil
    end
    local link = data.hyperlink
    local itemID, _, _, equipLoc = C_Item.GetItemInfoInstant(link)
    if not itemID or itemID == recipe or not ns.IsText(equipLoc, true) then
        return nil -- not gear, or no crafted item in the link
    end
    -- Class, armor, and weapon skills only: no level, so gear to craft later compares too.
    if not Equipment.CanUse(link) then
        return nil
    end
    if module.db.craftedCompare == "professions" and not Professions.Rank(line) then
        return nil
    end
    return link
end

local function onItem(tooltip, data)
    if not (tooltip.shoppingTooltips and C_TooltipComparison and C_TooltipComparison.CompareItem) then
        return
    end
    local link = data and comparing() and craftedGear(data)
    if link then
        -- The game's own comparison, by link, as for a linked item.
        pcall(C_TooltipComparison.CompareItem, { hyperlink = link }, tooltip)
    end
end

function module:OnEnable()
    self:TooltipPostCall(Enum.TooltipDataType.Item, onItem)
end
