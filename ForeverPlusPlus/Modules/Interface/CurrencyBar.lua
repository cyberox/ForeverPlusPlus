-- Currency Bar: a small box, drawn like a Blizzard tooltip, that shows your gold and the
-- currencies you have ticked "Show on Backpack" in the Currency tab, so they are in view without
-- opening a window. Hovering it lists your gold and currencies with what this session gained or
-- spent. Which currencies show is Blizzard's own choice, not ours. Move it in Edit Mode.
local _, ns = ...

local GetMoney, GetTime, C_CurrencyInfo, GameTooltip = GetMoney, GetTime, C_CurrencyInfo, GameTooltip
local CreateFrame, UIParent = CreateFrame, UIParent
local format, max, floor, abs, tconcat = string.format, math.max, math.floor, math.abs, table.concat

local L = ns.L
local Colors = ns.Colors
local number = ns.Text.Number

local module = ns.NewModule("CurrencyBar", L.CURRENCYBAR_DESC, {
    enabled = false,
    money = true,
    currencies = false,
    tooltip = true,
    session = true,
    perHour = true, -- this session's gold per hour, in the tooltip
    vertical = false,
    scale = 120, -- percent
    x = 977, -- the box's offset from the center of the screen (kept on screen on smaller ones)
    y = -462,
})
module.title = L.CURRENCYBAR_TITLE
module.category = "interface"
module.presets = { developer = { enabled = true } }

-- What the box shows and how it's laid out, then its tooltip.
module.options = {
    { key = "money", name = L.CURRENCYBAR_MONEY, description = L.CURRENCYBAR_MONEY_DESC },
    { key = "currencies", name = L.CURRENCYBAR_CURRENCIES, description = L.CURRENCYBAR_CURRENCIES_DESC },
    { key = "vertical", name = L.CURRENCYBAR_VERTICAL, description = L.CURRENCYBAR_VERTICAL_DESC,
        editMode = true },
    { key = "tooltip", name = L.CURRENCYBAR_TOOLTIP, description = L.CURRENCYBAR_TOOLTIP_DESC },
    {
        key = "session", requires = "tooltip",
        name = L.CURRENCYBAR_SESSION, description = L.CURRENCYBAR_SESSION_DESC,
    },
    {
        key = "perHour", requires = "tooltip", added = "1.1.0",
        name = L.CURRENCYBAR_PER_HOUR, description = L.CURRENCYBAR_PER_HOUR_DESC,
    },
}

local PAD = 10 -- between the text and the box's edge
local ICON = 14 -- a currency's icon, about the size of the text
local HINT_WIDTH = 200 -- the hint shown with nothing to show wraps at this width
local MAX_CURRENCIES = 10 -- far more than the Backpack's three, in case Forever allows more

local frame

-- Gold, silver, and copper as Blizzard draws them, but every coin always: 0 gold still shows.
local function coins(amount)
    local gold = floor(amount / 10000)
    local silver = floor(amount / 100) % 100
    local copper = amount % 100
    local icon = "|TInterface/MoneyFrame/UI-%sIcon:" .. ICON .. ":" .. ICON .. ":2:0|t"
    return number(gold) .. format(icon, "Gold")
        .. " " .. silver .. format(icon, "Silver") .. " " .. copper .. format(icon, "Copper")
end

local function backpackCurrency(index)
    -- Probe: the Backpack currency list is Mainline's.
    return C_CurrencyInfo and C_CurrencyInfo.GetBackpackCurrencyInfo
        and C_CurrencyInfo.GetBackpackCurrencyInfo(index)
end

-- The session ----------------------------------------------------------------------------------

-- What you had when the box turned on, and when, to say what this session gained or spent and
-- at what rate. Not saved.
local startMoney, startTime
local startCurrency = {} -- currency ID -> amount first seen

local RATE_AFTER = 60 -- seconds of the session before Gold per Hour shows, so a sale isn't a fortune

-- Remembers each Backpack currency the first time it is seen, so later changes count from there.
local function noteCurrencies()
    for index = 1, MAX_CURRENCIES do
        local info = backpackCurrency(index)
        if not info then
            return
        end
        local id = info.currencyTypesID
        if id and startCurrency[id] == nil then
            startCurrency[id] = info.quantity or 0
        end
    end
end

-- "+12" in green or "-12" in red, or plain 0.
local function signed(change, text)
    if change > 0 then
        return Colors.Code(0.1, 1, 0.1) .. "+" .. text .. "|r"
    elseif change < 0 then
        return Colors.Code(1, 0.2, 0.2) .. "-" .. text .. "|r"
    end
    return "0"
end

-- This session's gold per hour, "+3g 20s/h" in green or a loss in red, or nil in its first
-- minute and while the gold hasn't changed. Rounded to the silver from a gold up, to stay short.
-- Worked out when the tooltip opens, so nothing has to redraw it as time passes.
local function perHour(money)
    local elapsed = startTime and GetTime() - startTime
    if not (elapsed and elapsed >= RATE_AFTER) then
        return nil
    end
    local rate = abs(money - startMoney) * 3600 / elapsed
    rate = rate >= 10000 and floor(rate / 100 + 0.5) * 100 or floor(rate + 0.5)
    if rate == 0 then
        return nil
    end
    return signed(money - startMoney, format(L.CURRENCYBAR_PER_HOUR_VALUE, ns.Money(rate)))
end

-- The parts --------------------------------------------------------------------------------------

-- What to show, in order: the gold, then each Backpack currency as its icon and amount.
local function parts()
    local list = {}
    if module.db.money then
        list[#list + 1] = coins(GetMoney())
    end
    if module.db.currencies then
        for index = 1, MAX_CURRENCIES do
            local info = backpackCurrency(index)
            if not info then
                break
            end
            list[#list + 1] = format("%d |T%s:%d|t", info.quantity or 0, info.iconFileID or 134400, ICON)
        end
    end
    return list
end

local function update()
    if not frame then
        return
    end
    local list = parts()
    local text = frame.text
    if #list == 0 then
        -- Nothing to show: say how to fill it, instead of an empty box.
        text:SetWidth(HINT_WIDTH)
        text:SetText(Colors.Code(0.8, 0.8, 0.8) .. L.CURRENCYBAR_HINT .. "|r")
    else
        text:SetWidth(0)
        text:SetText(tconcat(list, module.db.vertical and "\n" or "   "))
    end
    local width = #list == 0 and HINT_WIDTH or text:GetStringWidth()
    local scale = module.db.scale / 100
    frame.inner:SetScale(scale)
    frame:SetSize(max(width, 24) * scale + PAD * 2,
        max(text:GetStringHeight(), 12) * scale + PAD * 2)
end

local function place()
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", module.db.x, module.db.y)
end

-- The tooltip ----------------------------------------------------------------------------------

local function showTooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    GameTooltip:SetText(L.CURRENCYBAR_TITLE)
    local money = GetMoney()
    GameTooltip:AddDoubleLine(L.CURRENCYBAR_MONEY, ns.Money(money), 1, 1, 1)
    if module.db.session and startMoney then
        local change = money - startMoney
        GameTooltip:AddDoubleLine(L.CURRENCYBAR_SESSION, signed(change, ns.Money(abs(change))),
            0.8, 0.8, 0.8)
    end
    local rate = module.db.perHour and perHour(money)
    if rate then
        GameTooltip:AddDoubleLine(L.CURRENCYBAR_PER_HOUR_LINE, rate, 0.8, 0.8, 0.8)
    end
    local header
    for index = 1, MAX_CURRENCIES do
        local info = backpackCurrency(index)
        if not info then
            break
        end
        if not header then
            header = true
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L.CURRENCYBAR_CURRENCIES)
        end
        local quantity = info.quantity or 0
        local text = number(quantity)
        local change = quantity - (startCurrency[info.currencyTypesID] or quantity)
        if module.db.session and change ~= 0 then
            text = text .. "  " .. signed(change, number(abs(change)))
        end
        GameTooltip:AddDoubleLine(format("|T%s:%d|t %s", info.iconFileID or 134400, ICON, info.name or ""),
            text, 1, 1, 1, 1, 1, 1)
    end
    if not header then
        GameTooltip:AddLine(L.CURRENCYBAR_HINT, 0.8, 0.8, 0.8, true)
    end
    GameTooltip:Show()
end

-- The frame ---------------------------------------------------------------------------------------

local function newFrame()
    -- The same box Blizzard draws tooltips in.
    local box = ns.Frames.TooltipBox(UIParent)
    box:SetFrameStrata("MEDIUM")
    -- The text sits in a child that takes the scale, so the box's own position stays put in Edit Mode.
    box.inner = CreateFrame("Frame", nil, box)
    box.inner:SetSize(1, 1)
    box.inner:SetPoint("CENTER")
    box.text = box.inner:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    box.text:SetPoint("CENTER")
    box.text:SetJustifyH("CENTER")
    -- The default spot is far from center, so on a smaller screen the box would sit off its edge.
    box:SetClampedToScreen(true)
    box:EnableMouse(true)
    box:SetScript("OnEnter", function(self)
        if module.db.tooltip then
            showTooltip(self)
        end
    end)
    box:SetScript("OnLeave", function() GameTooltip:Hide() end)
    box:Hide()
    return box
end

-- Edit Mode ---------------------------------------------------------------------------------------

-- Edit Mode's reset moves the box and its scale slider resizes it; doing both covers either.
local function layout()
    place()
    update()
end

local function onCurrencies()
    noteCurrencies()
    update()
end

function module:OnEnable()
    if not frame then
        frame = newFrame()
    end
    startMoney = startMoney or GetMoney()
    startTime = startTime or GetTime()
    noteCurrencies()
    layout()
    frame:Show()
    self:On("PLAYER_MONEY", update)
    self:On("CURRENCY_DISPLAY_UPDATE", onCurrencies)
    self:On("PLAYER_ENTERING_WORLD", onCurrencies)
    ns.EditMode.RegisterModule(self, frame, L.CURRENCYBAR_TITLE, layout)
end

function module:OnDisable()
    if frame then
        ns.EditMode.Unregister(frame)
        frame:Hide()
    end
end

function module:OnOptionChanged()
    update()
end
