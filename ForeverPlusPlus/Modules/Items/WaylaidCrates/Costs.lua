-- Waylaid Crates' bundle costs: what buying each bundle a crate takes costs at auction, the count
-- times the item's lowest buyout. Blizzard's line is skipped and we draw it again, the same text
-- in the same color, with each price beside its bundle ("beside": on the right, or after it with
-- inline price lines) or indented on a line of its own under it ("below"). Without auction prices
-- (Item Tooltips' Auction Prices off), Blizzard's line shows as it is.
local _, ns = ...

local ipairs, format = ipairs, string.format
local GRAY_FONT_COLOR, HIGHLIGHT_FONT_COLOR = GRAY_FONT_COLOR, HIGHLIGHT_FONT_COLOR

local L = ns.L
local ItemTooltip = ns.ItemTooltip
local Prices = ns.Prices

local internal = ns.modules.WaylaidCrates.internal

local module = ns.modules.WaylaidCrates:NewPart({
    key = "costs", name = L.WAYLAIDCRATES_COSTS, description = L.WAYLAIDCRATES_COSTS_DESC,
    section = L.WAYLAIDCRATES_COSTS,
    choices = {
        { "off", L.WAYLAIDCRATES_COSTS_OFF },
        { "below", L.WAYLAIDCRATES_COSTS_BELOW },
        { "beside", L.WAYLAIDCRATES_COSTS_BESIDE },
    },
}, {
    costs = "beside", -- each bundle's cost: "off", "below" each bundle, or "beside" it
})

-- Without auction prices there is nothing to price, and the crate's tooltip is Blizzard's own:
-- a gray row in Settings says why.
module.module.notice = {
    text = L.WAYLAIDCRATES_NO_PRICES,
    description = L.WAYLAIDCRATES_NO_PRICES_DESC,
    shown = function()
        return ns.PartOn(module.module, "costs") and not Prices.Available()
    end,
}

local LINES = internal.LINES

-- Color codes come as |cAARRGGBB or as |cnNAME: with one of Blizzard's named colors
-- (|cnHIGHLIGHT_FONT_COLOR:), and end at |r.
local HEX_CODE, NAMED_CODE = "|c%x%x%x%x%x%x%x%x", "|cn[%w_]+:"

-- The color code still running at the end of `piece`: the code, false when the piece ends its
-- color with |r, or nil when it has neither and the color before it runs on.
local function runningColor(piece)
    local lastOpen, code = 0, nil
    for _, pattern in ipairs({ HEX_CODE, NAMED_CODE }) do
        for at, found in piece:gmatch("()(" .. pattern .. ")") do
            if at > lastOpen then
                lastOpen, code = at, found
            end
        end
    end
    local lastClose = 0
    for at in piece:gmatch("()|r") do
        lastClose = at
    end
    if lastOpen > lastClose then
        return code
    elseif lastClose > 0 then
        return false
    end
end

-- What buying a bundle costs at auction, or a gray "No price".
local function bundleCost(count, name)
    local itemID = Prices.ItemByName(name)
    local price = itemID and Prices.Auction(itemID)
    if price then
        return ns.Money(price * count)
    end
    return GRAY_FONT_COLOR:WrapTextInColorCode(L.WAYLAIDCRATES_NO_PRICE)
end

-- The indent of a cost under its bundle: Blizzard's blank texture.
local UNDER_INDENT = "|TInterface\\Common\\spacer:1:12|t"

-- Draws a line that lists bundles again with their costs, and returns true so Blizzard's is
-- skipped. Text around the bundles keeps its own line, wrapped as Blizzard wraps it.
local function replaceBundleLine(tooltip, data, lineData)
    if not (module.enabled and Prices.Available() and internal.IsCrate(data)) then
        return
    end
    local below = module.db.costs == "below"
    local text = internal.PlainText(lineData)
    if not (text and internal.HasBundle(text) and internal.InList(data, lineData)) then
        return
    end
    local r, g, b = 1, 1, 1
    local color = lineData.leftColor
    if color and color.GetRGB then
        r, g, b = color:GetRGB()
    end
    local wr, wg, wb = HIGHLIGHT_FONT_COLOR:GetRGB()
    local inline = Prices.Inline()
    local pending -- text lines before the next bundle, drawn together
    local function flush()
        if pending then
            tooltip:AddLine(pending, r, g, b, true)
            pending = nil
        end
    end
    -- Blizzard colors parts of the line with color codes (the Use text green, the bundles
    -- white), and a code can run on past a line break. Each piece is drawn with the codes it
    -- had, reopening a color still running from the piece before and closing it at its end.
    local open -- the color code still running at the start of the next piece
    for piece in (lineData.leftText .. "\n"):gmatch(LINES) do
        local shown = (open or "") .. piece
        local running = runningColor(piece)
        if running ~= nil then
            open = running or nil
        end
        if open then
            shown = shown .. "|r"
        end
        local count, name = internal.BundleOf(ns.Text.Plain(piece))
        if count then
            flush()
            local cost = bundleCost(count, name)
            if below then
                -- The bundle's line as it was, then its cost under it, indented at the left.
                tooltip:AddLine(shown, r, g, b)
                tooltip:AddLine(UNDER_INDENT .. cost, wr, wg, wb)
            elseif inline then
                tooltip:AddLine(format(L.PRICE_INLINE, shown, cost), r, g, b)
            else
                tooltip:AddDoubleLine(shown, cost, r, g, b, wr, wg, wb)
            end
        else
            pending = pending and (pending .. "\n" .. shown) or shown
        end
    end
    flush()
    return true
end

function module:OnEnable()
    -- The hook can't be removed; replaceBundleLine checks the part is on instead.
    ItemTooltip.ReplaceLine(replaceBundleLine, self)
end
