-- Our lines in item tooltips, kept together where Blizzard puts the sell price. Modules add price
-- lines with `OnPrices`: right after the sell price, or after the item's last line of data when
-- it has none. Other lines about the item (`OnInfo`) go just above them. One module may redraw
-- the sell price line itself with `ReplaceSellPrice`, and any module another of Blizzard's lines
-- with `ReplaceLine`. That module also gets to draw a sell price where Blizzard draws none (quest
-- rewards). Nothing is hooked until a module first calls in.
local _, ns = ...

local ipairs, next, setmetatable, format, type = ipairs, next, setmetatable, string.format, type
local pcall = pcall
local floor, max, UIParent = math.floor, math.max, UIParent
local TooltipDataProcessor, Enum, C_Item, GameTooltip = TooltipDataProcessor, Enum, C_Item, GameTooltip
local IsShiftKeyDown = IsShiftKeyDown
local HIGHLIGHT_FONT_COLOR, GRAY_FONT_COLOR = HIGHLIGHT_FONT_COLOR, GRAY_FONT_COLOR
local NORMAL_FONT_COLOR = NORMAL_FONT_COLOR

local L = ns.L
local money = ns.Money

local ItemTooltip = {}
ns.ItemTooltip = ItemTooltip

local providers = {} -- fn(tooltip, data), in the order added
local noteProviders = {} -- fn(tooltip, data) for lines about the prices, after every price line
local lineReplacers = {} -- fn(tooltip, data, lineData) -> true when it drew the line itself
local infoProviders = {} -- fn(tooltip, data) for lines above the prices, in the order added
local replacer -- fn(tooltip, data, lineData) -> true when it drew the sell price line
local done = setmetatable({}, { __mode = "k" }) -- tooltip -> price lines already added
local infoDone = setmetatable({}, { __mode = "k" }) -- tooltip -> lines above the prices added
local current = setmetatable({}, { __mode = "k" }) -- tooltip -> item data being drawn
local widest = setmetatable({}, { __mode = "k" }) -- tooltip -> widest price line name so far
local sellLine = setmetatable({}, { __mode = "k" }) -- tooltip -> Blizzard has a sell price line
local NO_LINE = {} -- the line data a sell price gets where Blizzard has none

-- The item a line belongs to: from the item pre call, or else the tooltip's own data (probe:
-- GetPrimaryTooltipData is Mainline's tooltip data mixin).
local function itemData(tooltip)
    if current[tooltip] then
        return current[tooltip]
    end
    local data = tooltip.GetPrimaryTooltipData and tooltip:GetPrimaryTooltipData()
    if data and data.type == Enum.TooltipDataType.Item then
        return data
    end
end

local owners = setmetatable({}, { __mode = "k" }) -- a module's fn -> the module, for the Profiler

-- Calls one module's fn, timed for the Profiler page while it records. Through ns.Call, so one
-- module's error is reported and the other modules' lines still show.
local function run(fn, ...)
    local profiler = ns.Profiler
    if profiler and profiler.recording then
        return profiler.CallFrom(owners[fn], profiler.SOURCE_TOOLTIP, ns.Call, fn, ...)
    end
    return ns.Call(fn, ...)
end

local function addPrices(tooltip, data)
    done[tooltip] = true
    -- Blizzard leaves the sell price off some tooltips, such as a quest's rewards: the module
    -- that draws it puts it first, where the line would be.
    if replacer and not sellLine[tooltip] then
        run(replacer, tooltip, data, NO_LINE)
    end
    for _, fn in ipairs(providers) do
        run(fn, tooltip, data)
    end
    for _, fn in ipairs(noteProviders) do
        run(fn, tooltip, data)
    end
end

local function addInfo(tooltip, data)
    infoDone[tooltip] = true
    for _, fn in ipairs(infoProviders) do
        run(fn, tooltip, data)
    end
end

local function onSellPricePre(tooltip, lineData)
    sellLine[tooltip] = true
    local data = itemData(tooltip)
    if data and not infoDone[tooltip] then
        addInfo(tooltip, data)
    end
    if data and replacer and run(replacer, tooltip, data, lineData) then
        addPrices(tooltip, data)
        return true -- Blizzard's line is skipped; ours is in its place
    end
end

local function onSellPricePost(tooltip)
    local data = not done[tooltip] and itemData(tooltip)
    if data then
        addPrices(tooltip, data)
    end
end

-- An item with no sell price: the price lines go right after its last line of data, before
-- anything added after the data (Forever's "Press F6" reminder is), instead of at the very end.
local function onAnyLinePost(tooltip, lineData)
    local data = not done[tooltip] and current[tooltip]
    local lines = data and data.lines
    if lines and lines[#lines] == lineData then
        if not infoDone[tooltip] then
            addInfo(tooltip, data)
        end
        addPrices(tooltip, data)
    end
end

-- Before each line of an item tooltip: a module may draw it instead of Blizzard.
local function onAnyLinePre(tooltip, lineData)
    local data = lineReplacers[1] and current[tooltip]
    if not data then
        return
    end
    for _, fn in ipairs(lineReplacers) do
        if run(fn, tooltip, data, lineData) then
            -- Blizzard's line is skipped, and with it the line's post-calls, so place the price
            -- lines here if this was the last one.
            onAnyLinePost(tooltip, lineData)
            return true -- the module drew its own
        end
    end
end

-- Forgets what was drawn on the tooltip, for the next item.
local function reset(tooltip)
    done[tooltip] = nil
    infoDone[tooltip] = nil
    current[tooltip] = nil
    widest[tooltip] = nil
    sellLine[tooltip] = nil
end

local function onItemPre(tooltip, data)
    reset(tooltip)
    current[tooltip] = data
end

local function onItem(tooltip, data)
    if not infoDone[tooltip] and data then
        addInfo(tooltip, data)
    end
    if not done[tooltip] and data then
        addPrices(tooltip, data)
    end
    reset(tooltip)
end

-- Redraws the item tooltip when Shift goes up or down, so lines that depend on it change. Other
-- tooltips (units, spells) are left alone.
local function onModifier(_, key)
    local shift = key == "LSHIFT" or key == "RSHIFT"
    if shift and GameTooltip:IsShown() and GameTooltip.RefreshData
        and (not GameTooltip.GetPrimaryTooltipData or itemData(GameTooltip)) then
        GameTooltip:RefreshData()
    end
end

local hooked = false

local function hook()
    if hooked then
        return
    end
    hooked = true
    local lineType = Enum.TooltipDataLineType and Enum.TooltipDataLineType.SellPrice
    if lineType and TooltipDataProcessor.AddLinePreCall then
        TooltipDataProcessor.AddLinePreCall(lineType, onSellPricePre)
    end
    if lineType and TooltipDataProcessor.AddLinePostCall then
        TooltipDataProcessor.AddLinePostCall(lineType, onSellPricePost)
    end
    if TooltipDataProcessor.AddTooltipPreCall then
        TooltipDataProcessor.AddTooltipPreCall(Enum.TooltipDataType.Item, onItemPre)
        -- Probe: AllTypes (every line type) is Mainline's; without it, no-sell-price items get
        -- their price lines at the end, from onItem.
        if TooltipDataProcessor.AllTypes and TooltipDataProcessor.AddLinePostCall then
            TooltipDataProcessor.AddLinePostCall(TooltipDataProcessor.AllTypes, onAnyLinePost)
        end
        if TooltipDataProcessor.AllTypes and TooltipDataProcessor.AddLinePreCall then
            TooltipDataProcessor.AddLinePreCall(TooltipDataProcessor.AllTypes, onAnyLinePre)
        end
    end
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, onItem)
end

local shiftUsers = {} -- owner -> true while it has lines that change with Shift

---Redraws item tooltips when Shift goes up or down while any owner wants it. A module turns this
---on in OnEnable and off in OnDisable, so nothing listens while every price module is off.
---@param owner any usually the module
---@param on boolean
function ItemTooltip.RedrawOnShift(owner, on)
    shiftUsers[owner] = on or nil
    if next(shiftUsers) then
        ns.On("MODIFIER_STATE_CHANGED", onModifier)
    else
        ns.Off("MODIFIER_STATE_CHANGED", onModifier)
    end
end

-- Adds `fn` to a provider list unless it's already there, so a module can ask on every enable.
local function addProvider(list, fn)
    for i = 1, #list do
        if list[i] == fn then
            return
        end
    end
    list[#list + 1] = fn
end

---Calls `fn(tooltip, data)` on every item tooltip, where the price lines go. Hooks can't be
---removed, so `fn` checks whether its module is on. Asking again with the same `fn` changes
---nothing, so it can be called from `OnEnable`. `owner`, the module (or part), is who the
---Profiler page charges its time to.
---@param fn fun(tooltip: table, data: table)
---@param owner? table
function ItemTooltip.OnPrices(fn, owner)
    hook()
    owners[fn] = owner
    addProvider(providers, fn)
end

---Calls `fn(tooltip, data)` on every item tooltip after all the price lines, for lines about
---the prices rather than prices themselves (Auction Prices' "Scanned: 2h ago"), so every price
---line stays together above them. Otherwise as OnPrices.
---@param fn fun(tooltip: table, data: table)
---@param owner? table
function ItemTooltip.OnPriceNotes(fn, owner)
    hook()
    owners[fn] = owner
    addProvider(noteProviders, fn)
end

---Calls `fn(tooltip, data)` on every item tooltip just above the price lines (or where they'd
---go), for lines about the item that aren't prices. Hooks can't be removed, so `fn` checks
---whether its module is on; asking again with the same `fn` changes nothing. `owner` as in
---OnPrices.
---@param fn fun(tooltip: table, data: table)
---@param owner? table
function ItemTooltip.OnInfo(fn, owner)
    hook()
    owners[fn] = owner
    addProvider(infoProviders, fn)
end

---Calls `fn(tooltip, data, lineData)` before each line of an item tooltip; when it returns true,
---it drew that line itself and Blizzard's is skipped. For adding to one of Blizzard's lines, such
---as a price beside it. Hooks can't be removed, so `fn` checks whether its module is on; asking
---again with the same `fn` changes nothing. `owner` as in OnPrices.
---@param fn fun(tooltip: table, data: table, lineData: table): boolean?
---@param owner? table
function ItemTooltip.ReplaceLine(fn, owner)
    hook()
    owners[fn] = owner
    addProvider(lineReplacers, fn)
end

---Lets `fn(tooltip, data, lineData)` draw the sell price line instead of Blizzard. It returns
---true when it drew one; otherwise Blizzard's line shows. It's also called, with a `lineData`
---that has no price, on a tooltip Blizzard gives no sell price line, before the other prices.
---`owner` as in OnPrices.
---@param fn fun(tooltip: table, data: table, lineData: table): boolean?
---@param owner? table
function ItemTooltip.ReplaceSellPrice(fn, owner)
    hook()
    owners[fn] = owner
    replacer = fn
end

-- Whether a location from GetItemLocation points at a bag slot or equipment slot holding the item.
-- A merchant's buyback slot gives a location that is neither, and IsValid (DoesItemExist) throws
-- an error on it, so it's only asked once the location is one of those two.
local function inBagsOrWorn(location)
    if not location then
        return false
    end
    local bag = location.IsBagAndSlot and location:IsBagAndSlot()
    local worn = location.IsEquipmentSlot and location:IsEquipmentSlot()
    return (bag or worn) and location:IsValid() or false
end

-- A reagent in the professions window: how many the recipe takes, or nil. The tooltip's owner is
-- the slot's button, or the slot. Probe: Mainline's reagent slot has GetReagentSlotSchematic.
local function reagentCount(tooltip)
    local owner = tooltip and tooltip.GetOwner and tooltip:GetOwner()
    for _ = 1, 2 do
        if type(owner) ~= "table" then
            return nil
        end
        if owner.GetReagentSlotSchematic then
            local ok, schematic = pcall(owner.GetReagentSlotSchematic, owner)
            local count = ok and type(schematic) == "table" and schematic.quantityRequired
            return type(count) == "number" and count > 0 and count or nil
        end
        owner = owner.GetParent and owner:GetParent()
    end
end

-- An item in a quest window (one it asks for, or a reward): how many, or nil. Blizzard's quest
-- item buttons say what they are in `type` and `objectType`, and SetItemButtonCount leaves the
-- number it drew in `count`.
local function questItemCount(tooltip)
    local owner = tooltip and tooltip.GetOwner and tooltip:GetOwner()
    if type(owner) ~= "table" or owner.objectType ~= "item" or type(owner.type) ~= "string" then
        return nil
    end
    local count = owner.count
    return ns.IsNumber(count) and count > 0 and count or nil
end

---How many items the hovered stack holds, how many a recipe takes of a reagent in the
---professions window, or how many a quest asks for or gives; 1 when it can't tell (links,
---merchants, buyback).
---@param data table tooltip data
---@param tooltip? table the tooltip, to find a reagent slot or quest item it belongs to
---@return number
function ItemTooltip.StackCount(data, tooltip)
    local reagent = reagentCount(tooltip) or questItemCount(tooltip)
    if reagent then
        return reagent
    end
    if data.guid and C_Item.GetItemLocation and C_Item.GetStackCount then
        local location = C_Item.GetItemLocation(data.guid)
        if inBagsOrWorn(location) then
            return C_Item.GetStackCount(location) or 1
        end
    end
    return 1
end

---The item's ID, or nil when it has none or it's secret.
---@param data table tooltip data
---@return number?
function ItemTooltip.ItemID(data)
    local id = data.id
    if ns.IsReadable(id) then
        return id
    end
end

-- How many items a price line counts: the whole stack, or one while Shift is held. `mode` "one"
-- turns that round (one, and the stack with Shift).
local function priceCount(tooltip, data, mode)
    local stack = (mode == "one") == IsShiftKeyDown()
    return stack and ItemTooltip.StackCount(data, tooltip) or 1
end

-- Alignment ----------------------------------------------------------------------------------
-- "right": coins against the tooltip's right edge. "inline": coins right after the label. Either
-- way a name is padded with a blank texture out to the widest price line above it in the same
-- tooltip, so the quantities line up (spaces only got within a space's width). A line with no
-- price line above it, such as Auction on an item with no sell price, isn't padded. The sell
-- price comes first and is the longest name, so the lines above are all it needs to look at.

-- Blizzard's transparent texture, drawn as a gap of any width inside text.
local SPACER = "|TInterface\\Common\\spacer:1:%d|t"

local measure -- our own hidden font string, for label widths

local COLORS = { gray = GRAY_FONT_COLOR, white = HIGHLIGHT_FONT_COLOR, gold = NORMAL_FONT_COLOR }

local function width(text)
    if not measure then
        measure = UIParent:CreateFontString(nil, "BACKGROUND", "GameTooltipText")
        measure:Hide()
    end
    measure:SetText(text)
    return measure:GetStringWidth()
end

-- A gap that pads the name out to the widest price line name above it in this tooltip.
local function padding(tooltip, name)
    local own = width(name)
    local gap = floor((widest[tooltip] or own) - own + 0.5)
    widest[tooltip] = max(widest[tooltip] or 0, own)
    return gap > 0 and format(SPACER, gap) or ""
end

-- Adds the line in white: the value after the label, or against the right edge.
local function emit(tooltip, align, label, value)
    local r, g, b = HIGHLIGHT_FONT_COLOR:GetRGB()
    if align == "inline" then
        tooltip:AddLine(format(L.PRICE_INLINE, label, value), r, g, b)
    else
        tooltip:AddDoubleLine(label, value, r, g, b, r, g, b)
    end
end

---Adds a price line: the name and an "x20", then the coins ("Sell Price x20: <coins>").
---@param tooltip table
---@param data table tooltip data, for the stack's size
---@param name string such as "Sell Price"
---@param unitPrice number copper for one item
---@param mode string "stack" (Shift for one) or "one" (Shift for the stack): how many it counts
---@param align string "right" (coins at the tooltip's edge) or "inline" (after the label)
---@param color string the quantity's color: "gray", "white", or "gold"
function ItemTooltip.AddPrice(tooltip, data, name, unitPrice, mode, align, color)
    local count = priceCount(tooltip, data, mode)
    local amount = unitPrice * count
    local quantity = (COLORS[color] or GRAY_FONT_COLOR):WrapTextInColorCode(format(L.PRICE_QUANTITY, count))
    -- The padding goes before the quantity, so the "x20"s line up.
    local label = format(L.PRICE_LINE, name .. padding(tooltip, name), quantity)
    emit(tooltip, align, label, money(amount))
end

---Text in a quantity color by its name ("gray", "white", or "gold"; gray for another) or in
---{ r, g, b }: the colors AddInfo and the price lines' choices use.
---@param text string
---@param color string|table
---@return string
function ItemTooltip.ColorText(text, color)
    if type(color) == "table" then
        return ns.Colors.Code(color[1], color[2], color[3]) .. text .. "|r"
    end
    return (COLORS[color] or GRAY_FONT_COLOR):WrapTextInColorCode(text)
end

---Adds a line in the price lines' style with text instead of coins ("Scanned: 2h ago"). The
---text goes where `align` puts coins ("right" or "inline"), in `color`: a quantity color's name
---or { r, g, b }.
---@param tooltip table
---@param name string
---@param text string
---@param align string
---@param color string|table "gray", "white", "gold", or { r, g, b }
function ItemTooltip.AddInfo(tooltip, name, text, align, color)
    -- The padding goes after the colon: there's no quantity for it to sit in front of, and
    -- before the colon it read as "Scanned :".
    local label = format(L.PRICE_INFO_LINE, name) .. padding(tooltip, name)
    emit(tooltip, align, label, ItemTooltip.ColorText(text, color))
end
