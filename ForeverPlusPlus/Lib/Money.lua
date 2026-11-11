-- Money as Blizzard shows it: gold, silver and copper with their coin icons.
local _, ns = ...

local GetMoneyString, C_CurrencyInfo = GetMoneyString, C_CurrencyInfo
local floor = math.floor

local GOLD = 10000 -- copper in a gold

---An amount of copper as coin text, the way Blizzard's own tooltips and chat show it.
---@param amount number copper
---@return string
function ns.Money(amount)
    -- Probe: GetMoneyString is Mainline FrameXML; the coin text is the fallback.
    if GetMoneyString then
        return GetMoneyString(amount, true)
    end
    return C_CurrencyInfo.GetCoinTextureString(amount)
end

---An amount of copper as short coin text, for a narrow column: rounded to whole gold at 1 gold or
---more, so it drops the silver and copper, and to the copper below that. A minus sign before a loss.
---@param amount number copper, negative for a loss
---@return string
function ns.MoneyShort(amount)
    local size = floor((amount < 0 and -amount or amount) + 0.5)
    if size >= GOLD then
        size = floor(size / GOLD + 0.5) * GOLD
    end
    local text = ns.Money(size)
    if amount < 0 and size > 0 then
        return "-" .. text
    end
    return text
end
