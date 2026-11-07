-- Item Tooltips' repair cost: what repairing a damaged piece of gear costs, with the prices, on
-- gear you wear or carry. Blizzard's own line only shows with a merchant's repair cursor.
local _, ns = ...

local InRepairMode = InRepairMode

local L = ns.L
local ItemTooltip = ns.ItemTooltip

local module = ns.modules.ItemTooltips:NewPart({
    key = "repairCost", name = L.ITEMTOOLTIPS_REPAIRCOST, description = L.REPAIRCOST_DESC,
    section = L.REPAIRCOST_TITLE, added = "0.9.0",
}, {
    repairCost = false,
})

-- The client puts the cost in the item's tooltip data (`repairCost`) for gear in your bags or
-- equipped that has lost durability; links and merchants' items have none.
local function addRepairCost(tooltip, data)
    if not module.enabled then
        return
    end
    local cost = data.repairCost
    if not (ns.IsNumber(cost) and cost > 0) then
        return
    end
    -- With the repair cursor Blizzard shows its own repair cost line.
    if InRepairMode and InRepairMode() then
        return
    end
    ItemTooltip.AddInfo(tooltip, L.REPAIRCOST_LINE, ns.Money(cost), module.db.align, "white")
end

function module:OnEnable()
    -- The hook can't be removed; addRepairCost checks the part is on instead.
    ItemTooltip.OnPrices(addRepairCost, module)
end
