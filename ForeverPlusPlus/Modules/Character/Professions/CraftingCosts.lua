-- Professions' Crafting Costs: in the professions window, under the recipe's description, what its
-- reagents cost in all (each one's price times the count the recipe takes), what the crafted items
-- are worth, the profit after the auction house's cut, and how old the oldest auction price in
-- them is; and, with Profit in Recipe List, each recipe's profit on its row.
--
-- Auction prices come through ns.Prices (Item Tooltips' Auction Prices, or Auctionator through
-- it). A reagent a merchant sells costs the merchant's price when that's lower than the auction's;
-- those prices are learned at merchants while this part is on. A crafted item with no auction
-- price is worth what a merchant pays for it. Our own frame on Blizzard's recipe form; only the
-- reagents' anchor is changed, to move them down under it, and put back when it goes. (Prices
-- inside Blizzard's reagent slots didn't fit, and a row per reagent was too much.)
local _, ns = ...

local ipairs, format, time, floor = ipairs, string.format, time, math.floor
local CreateFrame, select, tostring, wipe = CreateFrame, select, tostring, wipe
local C_Item, C_TradeSkillUI, Enum = C_Item, C_TradeSkillUI, Enum
local GRAY_FONT_COLOR, HIGHLIGHT_FONT_COLOR = GRAY_FONT_COLOR, HIGHLIGHT_FONT_COLOR

local L = ns.L
local Professions = ns.Professions -- ours; Blizzard's global of the same name is _G.Professions

local professions = ns.modules.Professions
local module = professions:NewPart({
    key = "crafting", name = L.PROFESSIONS_CRAFTING, description = L.PROFESSIONS_CRAFTING_DESC,
    section = L.PROFESSIONS_CRAFTING,
}, {
    craftingRows = true, -- each recipe's profit on its row of the recipe list
    -- Data, not settings: what merchants charge for one of an item, { [itemID] = copper },
    -- learned at each visit.
    vendor = {},
})

module:AddOptions({
    {
        key = "craftingRows", name = L.PROFESSIONS_CRAFTING_ROWS, description = L.PROFESSIONS_CRAFTING_ROWS_DESC,
        added = "1.5.0",
    },
})

local auctionPrice = ns.Prices.Auction

-- The recipe list's profits, kept by recipe ID while it scrolls (see Profit in the recipe list
-- below), and forgotten whenever a price they're made of may have changed.
local profits = {} -- recipeID -> profit in copper, or false for none

-- Merchants ----------------------------------------------------------------------------------------

-- A merchant's item: its price, how many that price buys, how many are left (-1: unlimited),
-- and whether it costs something besides money. Probe: C_MerchantFrame.GetItemInfo is newer
-- Mainline; GetMerchantItemInfo the older one.
local function merchantItem(index)
    local C_MerchantFrame = _G.C_MerchantFrame
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local info = C_MerchantFrame.GetItemInfo(index)
        if info then
            return info.price, info.stackCount, info.numAvailable, info.hasExtendedCost
        end
    elseif _G.GetMerchantItemInfo then
        local _, _, price, stack, available, _, _, extended = _G.GetMerchantItemInfo(index)
        return price, stack, available, extended
    end
end

-- Remembers what the open merchant charges for one of each item it always has, for money only.
local function recordMerchant()
    local count = _G.GetMerchantNumItems and _G.GetMerchantNumItems() or 0
    local getID = _G.GetMerchantItemID
    if not getID then
        return
    end
    local vendor = module.db.vendor
    for i = 1, count do
        local id = getID(i)
        local price, stack, available, extended = merchantItem(i)
        if id and price and price > 0 and available == -1 and not extended then
            vendor[id] = price / ((stack and stack > 0) and stack or 1)
        end
    end
    wipe(profits) -- a reagent's merchant price may be new
end

-- Sums ---------------------------------------------------------------------------------------------

-- What one of a reagent costs: the lower of its auction and merchant prices, or nil. Then when
-- the auction price was seen, when that's the one used.
local function reagentCost(itemID)
    local auction, seenAt = auctionPrice(itemID)
    local vendor = module.db.vendor[itemID]
    if auction and (not vendor or auction < vendor) then
        return auction, seenAt
    end
    return vendor
end

-- What one crafted item is worth: its auction price, or else what a merchant pays (and true).
-- Then when the auction price was seen.
local function craftedValue(itemID)
    local price, seenAt = auctionPrice(itemID)
    if price then
        return price, false, seenAt
    end
    local sell = select(11, C_Item.GetItemInfo(itemID))
    if sell and sell > 0 then
        return sell, true
    end
end

-- A reagent slot every craft uses (not an optional or finishing one): its item and how many, or
-- nil. Probe: reagentType and its enum are Mainline's; without them, whether it's required.
local function basicReagent(slot)
    local basic = Enum.CraftingReagentType and Enum.CraftingReagentType.Basic
    local isBasic
    if basic and slot.reagentType ~= nil then
        isBasic = slot.reagentType == basic
    else
        isBasic = slot.required
    end
    local reagent = slot.reagents and slot.reagents[1]
    if isBasic and reagent and reagent.itemID and (slot.quantityRequired or 0) > 0 then
        return reagent.itemID, slot.quantityRequired
    end
end

-- The reagents every craft uses: { itemID, count } each.
local function basicReagents(schematic)
    local list = {}
    for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
        local itemID, count = basicReagent(slot)
        if itemID then
            list[#list + 1] = { itemID, count }
        end
    end
    return list
end

local GRAY, WHITE = GRAY_FONT_COLOR, HIGHLIGHT_FONT_COLOR
local GREEN, RED = GREEN_FONT_COLOR, RED_FONT_COLOR

local AUCTION_CUT = 0.05 -- the auction house's cut of a sale

-- Copper as coins, with a minus sign when it's negative.
local function coins(amount)
    amount = floor(amount + 0.5)
    if amount < 0 then
        return "-" .. ns.Money(-amount)
    end
    return ns.Money(amount)
end

-- Green for a profit, red for a loss, white for even: on the totals and the recipe list alike.
local function profitColor(profit)
    return profit > 0 and GREEN or profit < 0 and RED or WHITE
end

-- What one craft of a recipe costs and makes: the one sum both the selected recipe's totals and the
-- recipe list's rows show, so they can't disagree. Nil for a recipe with no reagents every craft
-- uses. Otherwise { cost (copper), missing (a reagent has no price), oldest (when the oldest auction
-- price used was seen), output (the itemID made; nil for an enchant, which has no value or profit),
-- low and high (how many it makes), value (of all it makes, or nil with no price), fromVendor,
-- profit (after the auction house's cut; nil without a value or a reagent's price), loading (the
-- output's item data hasn't come yet, so a merchant's price for it can't be read) }.
local function craftSums(recipeID)
    local schematic = recipeID and C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic
        and C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
    local reagents = schematic and basicReagents(schematic)
    if not (reagents and #reagents > 0) then
        return nil
    end
    local cost, missing, oldest = 0, false, nil
    for _, reagent in ipairs(reagents) do
        local unit, seenAt = reagentCost(reagent[1])
        if unit then
            cost = cost + unit * reagent[2]
        else
            missing = true
        end
        if seenAt and (not oldest or seenAt < oldest) then
            oldest = seenAt
        end
    end
    local sums = { cost = cost, missing = missing }
    local output = schematic.outputItemID
    if output then
        sums.output = output
        local low, high = schematic.quantityMin or 1, schematic.quantityMax or 1
        sums.low, sums.high = low, high
        local unit, fromVendor, seenAt = craftedValue(output)
        if seenAt and (not oldest or seenAt < oldest) then
            oldest = seenAt
        end
        if unit then
            local value = unit * (low + high) / 2 -- some recipes make a random number: count the middle
            sums.value, sums.fromVendor = value, fromVendor
            if not missing then
                -- Selling at auction loses the house's cut; a merchant pays in full.
                sums.profit = (fromVendor and value or value * (1 - AUCTION_CUT)) - cost
            end
        elseif C_Item.IsItemDataCachedByID and not C_Item.IsItemDataCachedByID(output) then
            sums.loading = true -- probe: IsItemDataCachedByID is Mainline's
        end
    end
    sums.oldest = oldest
    return sums
end

-- The totals ---------------------------------------------------------------------------------------

local CRAFT_WIDTH, ROW_HEIGHT = 280, 14

local panel -- our frame for the totals, made the first time a recipe shows
local reagentsAnchor -- Blizzard's anchor for the reagents, which our totals take over

local function getPanel(form)
    if not panel then
        panel = CreateFrame("Frame", nil, form)
        panel:SetSize(CRAFT_WIDTH, ROW_HEIGHT)
        panel.rows = {}
    end
    return panel
end

-- The totals go where Blizzard put the reagents, under the description, and the reagents move
-- down under them. Only for a reagents frame with one TOPLEFT anchor, as Mainline's has; false
-- otherwise. Blizzard may anchor the reagents again for each recipe, so the anchor is read again
-- each time unless it's still ours.
local function placeAtTop(form)
    local reagents = form.Reagents
    if not (reagents and reagents:GetNumPoints() == 1) then
        return false
    end
    local point, relativeTo, relativePoint, x, y = reagents:GetPoint(1)
    if relativeTo ~= panel then
        if point ~= "TOPLEFT" then
            return false
        end
        reagentsAnchor = { relativeTo or form, relativePoint, x, y }
    elseif not reagentsAnchor then
        return false
    end
    local anchor = reagentsAnchor
    panel:ClearAllPoints()
    -- A recipe with no description still keeps its empty line's space: the totals take it.
    local description = form.Description
    local text = description and description.GetText and description:GetText()
    if anchor[1] == description and (text == nil or text == "") then
        panel:SetPoint("TOPLEFT", description, "TOPLEFT", anchor[3], 0)
    else
        panel:SetPoint("TOPLEFT", anchor[1], anchor[2], anchor[3], anchor[4] / 2)
    end
    reagents:ClearAllPoints()
    reagents:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 0, -14)
    return true
end

-- Puts the reagents back where Blizzard had them, when our totals go.
local function restoreReagents(form)
    local reagents = form.Reagents
    if not (reagentsAnchor and reagents) then
        return
    end
    local _, relativeTo = reagents:GetPoint(1)
    if relativeTo == panel then
        local anchor = reagentsAnchor
        reagents:ClearAllPoints()
        reagents:SetPoint("TOPLEFT", anchor[1], anchor[2], anchor[3], anchor[4])
    end
end

-- Row `i` at `y`: a label on the left and a value at the right edge.
local function setRow(i, y, label, value)
    local row = panel.rows[i]
    if not row then
        row = {
            left = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"),
            right = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"),
        }
        row.left:SetJustifyH("LEFT")
        row.left:SetWordWrap(false)
        row.right:SetJustifyH("RIGHT")
        panel.rows[i] = row
    end
    row.right:ClearAllPoints()
    row.right:SetPoint("TOPRIGHT", 0, y)
    row.left:ClearAllPoints()
    row.left:SetPoint("TOPLEFT", 0, y)
    row.left:SetPoint("RIGHT", row.right, "LEFT", -8, 0)
    row.left:SetText(label)
    row.right:SetText(value)
    row.left:Show()
    row.right:Show()
end

local function noPrice()
    return GRAY:WrapTextInColorCode(L.PROFESSIONS_CRAFT_NO_PRICE)
end

local function refreshCrafting(recipeInfo)
    local form = Professions.RecipeForm()
    if not form then
        return
    end
    recipeInfo = recipeInfo or (form.GetRecipeInfo and form:GetRecipeInfo())
    local recipeID = module.enabled and recipeInfo and recipeInfo.recipeID
    local sums = recipeID and craftSums(recipeID)
    if not (sums and form.Reagents) then
        if panel then
            panel:Hide()
            restoreReagents(form)
        end
        return
    end
    getPanel(form)
    if not placeAtTop(form) then
        -- Not the layout we know: under the reagents instead, moving nothing of Blizzard's.
        restoreReagents(form)
        local below = form.OptionalReagents
        if not (below and below:IsShown()) then
            below = form.Reagents
        end
        panel:ClearAllPoints()
        panel:SetPoint("TOPLEFT", below, "BOTTOMLEFT", 0, -12)
    end

    local i, y = 0, 0
    -- How old the oldest auction price in these totals is, colored like the tooltip's age (as
    -- Auction Prices' Scan Age Color has it), for how much to trust them.
    if sums.oldest then
        local age = time() - sums.oldest
        local text = ns.ItemTooltip.ColorText(ns.Text.Ago(age), ns.Prices.AgeColor(age))
        i = i + 1
        setRow(i, y, L.PROFESSIONS_CRAFT_AGE, text)
        y = y - ROW_HEIGHT
    end

    i = i + 1
    setRow(i, y, L.PROFESSIONS_CRAFT_COST, sums.missing and noPrice() or coins(sums.cost))
    y = y - ROW_HEIGHT

    if sums.output then
        local low, high = sums.low, sums.high
        local label = L.PROFESSIONS_CRAFT_VALUE
        if high > 1 then
            local amount = low == high and tostring(low) or format(L.PROFESSIONS_CRAFT_RANGE, low, high)
            label = format(L.PROFESSIONS_CRAFT_VALUE_COUNT, amount)
        end
        local valueText = noPrice()
        if sums.value then
            valueText = coins(sums.value)
            if sums.fromVendor then
                valueText = format(L.PROFESSIONS_CRAFT_EACH, valueText,
                    GRAY:WrapTextInColorCode(L.PROFESSIONS_CRAFT_VENDOR))
            end
        end
        i = i + 1
        setRow(i, y, label, valueText)
        y = y - ROW_HEIGHT

        local profit = sums.profit
        local profitText = noPrice()
        if profit then
            profitText = profitColor(profit):WrapTextInColorCode(coins(profit))
        end
        i = i + 1
        setRow(i, y, L.PROFESSIONS_CRAFT_PROFIT, profitText)
        y = y - ROW_HEIGHT
    end

    for j = i + 1, #panel.rows do
        panel.rows[j].left:Hide()
        panel.rows[j].right:Hide()
    end
    panel:SetHeight(-y)
    panel:Show()
end

local function onRecipeInit(_, recipeInfo)
    refreshCrafting(recipeInfo)
end

-- Profit in the recipe list -------------------------------------------------------------------
-- Each recipe's Estimated Profit, from the same sum as the totals, at the right end of its row,
-- in the totals' colors. Nothing on a category header, an enchant, or a recipe missing a price.
-- It has a column of its own (Professions.NewRowColumn), left of Appearance Icons' mark and Skill-
-- Ups Left's number while those are in use and further right while they aren't; a long name is cut
-- short before it, and a row too narrow for both shows no profit. Rows are built again as the list
-- scrolls, so profits are kept by recipe.

local profitColumn = Professions.NewRowColumn(30, 0, 4) -- as wide as each row's text

local rowTexts = ns.ItemButtons.Overlays(function(row)
    local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetJustifyH("RIGHT")
    return text
end)

local waiting = {} -- itemIDs made by a recipe whose item data is loading: { [itemID] = true }

local function rowsOn()
    return module.enabled and module.db.craftingRows
end

-- A recipe's profit, or nil. Not kept while the item it makes is still loading, since its
-- merchant price may come with it.
local function profitOf(recipeID)
    local profit = profits[recipeID]
    if profit == nil then
        local sums = craftSums(recipeID)
        if sums and sums.loading then
            waiting[sums.output] = true
            return nil
        end
        profit = sums and sums.profit or false
        profits[recipeID] = profit
    end
    return profit or nil
end

local function profitRow(row, node)
    if not (row and row.Label) then
        return
    end
    local profit
    if rowsOn() then
        local info = Professions.RowRecipe(row, node)
        -- Not on a recipe the player doesn't know (Unlearned Recipes' rows): it can't be made yet.
        profit = info and info.learned and info.recipeID and profitOf(info.recipeID)
    end
    profitColumn:Use(rowsOn())
    local text = rowTexts:Set(row, profit)
    if text then
        text:SetText(profitColor(profit):WrapTextInColorCode(ns.MoneyShort(profit)))
    end
    profitColumn:Place(row, text, text and text:GetStringWidth())
end

local ROW_HOOKS = { Init = profitRow }

local function redrawRows()
    profitColumn:Use(rowsOn())
    Professions.EachRecipeRow(profitRow)
end

-- The totals and the rows again, once for a burst: prices change many times a second while the
-- auction house is browsed.
local redrawSoon = ns.Frames.Coalesce(function()
    refreshCrafting()
    redrawRows()
end, 0.5, module)

-- The rows' mixin is in Blizzard's load-on-demand professions addons: hooked once it's there, and
-- only once the option is on. A row hook does nothing while the part is off.
local function hookRows()
    if rowsOn() then
        Professions.HookRecipeRows(module, ROW_HOOKS)
    end
end

-- Registered once; does nothing while the part is off but forget what it kept. Also how a change
-- of price source (Use Auctionator's Prices, Auction Prices turned on or off) reaches the totals.
ns.Prices.OnChanged(function()
    wipe(profits)
    if module.enabled then
        redrawSoon()
    end
end)

-- Auctionator's prices change without telling us, so each time the window opens they're read again.
local function onTradeSkillShow()
    wipe(profits)
    hookRows()
    redrawSoon()
end

local function onItemInfo(_, itemID)
    if itemID and waiting[itemID] then
        waiting[itemID] = nil
        redrawSoon()
    end
end

module:OnWhile("craftingRows", {
    TRADE_SKILL_SHOW = onTradeSkillShow,
    GET_ITEM_INFO_RECEIVED = onItemInfo,
})

-- Blizzard_Professions is load-on-demand: hook its recipe form once it has loaded. Init runs each
-- time a recipe is picked.
local function hookProfessions()
    local form = Professions.RecipeForm()
    if form then
        module:Hook(form, "Init", onRecipeInit)
        refreshCrafting()
    end
    hookRows()
    redrawRows()
end

function module:OnEnable()
    self:On("MERCHANT_SHOW", recordMerchant)
    self:On("MERCHANT_UPDATE", recordMerchant)
    ns.AddOns.WhenLoaded("Blizzard_Professions", hookProfessions)
end

function module:OnDisable()
    ns.AddOns.Cancel("Blizzard_Professions", hookProfessions)
    if panel then
        panel:Hide()
    end
    local form = Professions.RecipeForm()
    if form then
        restoreReagents(form)
    end
    rowTexts:HideAll()
    profitColumn:Use(false)
    wipe(profits)
    wipe(waiting)
end

function module:OnOptionChanged(key)
    if key == "craftingRows" then
        wipe(profits)
        wipe(waiting)
        hookRows()
        redrawRows() -- hides every row's profit when they're off
    end
end
