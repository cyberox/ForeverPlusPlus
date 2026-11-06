-- Item Tooltips' Compare Crafted Gear: a recipe in your bags that makes gear shows Blizzard's own
-- comparison with what you wear, as the gear itself would.
--
-- A recipe's tooltip data is the recipe's item (`id`) with the crafted item's link as its
-- `hyperlink`, and the crafted item's lines nested after its first line (`/run` on a linked Plans:
-- Copper Chain Vest, 2026-11-05: id 3609, hyperlink [Copper Chain Vest], line 2 a NestedBlock).
-- Blizzard compares a tooltip's item by its GUID when it has one, else by its link
-- (TooltipComparisonManager:CreateComparisonItem, `forever` UI source), so a linked recipe already
-- compares its crafted item while one in your bags compares the recipe, which has nothing to
-- compare. Blizzard compares a bag item on every refresh of its tooltip (about five a second, and
-- each refresh clears the comparison), through GameTooltip_ShowCompareItem. So right after that,
-- this asks again by the crafted item's link, in the same frame: asking from the tooltip's own
-- post call instead came before Blizzard's ask, which then emptied it, and the comparison flashed
-- on and off (2026-11-05).
--
-- Which recipes: gear you can use (your class, armor, and weapon skills, whatever its level, so a
-- recipe you'll craft later still compares), and optionally only recipes of professions you have.
local _, ns = ...

local _G, pcall = _G, pcall
local Enum, C_Item, C_TooltipComparison = Enum, C_Item, C_TooltipComparison

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

-- After Blizzard has compared a tooltip's item (GameTooltip_ShowCompareItem, once per refresh,
-- after its comparison by the item's GUID is done): when that's a bag recipe for gear this setting
-- compares, the same comparison by the crafted item's link, so it's the last word that frame.
-- Asking from inside Blizzard's own comparison (a hook on TooltipComparisonManager:CompareItem)
-- ran, by `/run` prints, but showed nothing: it was nested inside the comparison by GUID, which
-- the client was still finishing (2026-11-05).
local function onShowCompare(tooltip, anchorFrame)
    tooltip = tooltip or _G.GameTooltip
    local data = tooltip and tooltip.GetPrimaryTooltipData and tooltip:GetPrimaryTooltipData()
    local link = data and craftedGear(data)
    if link then
        pcall(C_TooltipComparison.CompareItem, { hyperlink = link }, tooltip, anchorFrame)
    end
end

function module:OnEnable()
    if C_TooltipComparison and C_TooltipComparison.CompareItem then
        self:Hook("GameTooltip_ShowCompareItem", onShowCompare)
    end
end
