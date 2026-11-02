-- Item Tooltips' disenchant value: on a green, blue, or purple weapon or armor piece, what
-- disenchanting it gives on average, priced from Auction Prices while that's on, or else the
-- material it most likely gives. Shift adds every outcome with its chance, in gray. The rules are
-- in Lib/Disenchant.lua.
local _, ns = ...

local ipairs, format, floor = ipairs, string.format, math.floor
local C_Item = C_Item
local GRAY_FONT_COLOR = GRAY_FONT_COLOR
local IsShiftKeyDown = IsShiftKeyDown

local L = ns.L
local ItemTooltip = ns.ItemTooltip
local Disenchant = ns.Disenchant

local module = ns.modules.ItemTooltips:NewPart({
    key = "disenchant", name = L.ITEMTOOLTIPS_DISENCHANT, description = L.DISENCHANT_DESC,
    section = L.DISENCHANT_TITLE, added = "1.0.0-beta.1",
}, {
    disenchant = false,
})

-- A material's name, or a stand-in while the client hasn't cached it (asking loads it, so the
-- next redraw has it).
local function materialName(itemID)
    local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
    if name then
        return name
    end
    if C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(itemID)
    end
    return format(L.DISENCHANT_UNKNOWN_ITEM, itemID)
end

-- "1-2 Soul Dust", or "1 Nexus Crystal".
local function amountText(each)
    local amount = each.min == each.max and each.min or format(L.DISENCHANT_RANGE, each.min, each.max)
    return format(L.DISENCHANT_AMOUNT, amount, materialName(each.item))
end

-- "75%", "99.5%", "0.5%".
local function chanceText(chance)
    local percent = chance * 100
    if percent == floor(percent) then
        return format(L.DISENCHANT_CHANCE, format("%d", percent))
    end
    return format(L.DISENCHANT_CHANCE, format("%.1f", percent))
end

-- The disenchant outcomes for the hovered item, or nil when it can't be disenchanted (or its
-- item info isn't cached yet).
local function outcomesFor(itemID)
    local _, _, quality, itemLevel, _, _, _, _, equipLoc, _, _, classID = C_Item.GetItemInfo(itemID)
    if not quality then
        return nil
    end
    return Disenchant.ForItem(classID, quality, equipLoc, itemLevel)
end

local function addDisenchant(tooltip, data)
    local itemID = module.enabled and ItemTooltip.ItemID(data)
    local outcomes = itemID and outcomesFor(itemID)
    if not outcomes then
        return
    end
    local db = module.db
    local value, missing = Disenchant.Value(outcomes, ns.Prices.Auction)
    if missing == 0 and value > 0 then
        ItemTooltip.AddInfo(tooltip, L.DISENCHANT_LINE, ns.Money(floor(value + 0.5)), db.align, "white")
    else
        -- No prices for every outcome: what it most likely gives instead.
        ItemTooltip.AddInfo(tooltip, L.DISENCHANT_LINE, amountText(outcomes[1]), db.align, "white")
    end
    if IsShiftKeyDown() then
        local r, g, b = GRAY_FONT_COLOR:GetRGB()
        for _, each in ipairs(outcomes) do
            tooltip:AddLine(format(L.DISENCHANT_OUTCOME, chanceText(each.chance), amountText(each)),
                r, g, b)
        end
    end
end

function module:OnEnable()
    -- The hook can't be removed; addDisenchant checks the part is on instead.
    ItemTooltip.OnPrices(addDisenchant, module)
    -- Shift adds the outcomes.
    ItemTooltip.RedrawOnShift(self, true)
end

function module:OnDisable()
    ItemTooltip.RedrawOnShift(self, false)
end
