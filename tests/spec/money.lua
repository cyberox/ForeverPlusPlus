-- Money: copper as coin text, through Blizzard's GetMoneyString, or the coin text without it.
local T = ...
local ns, eq = T.ns, T.eq

local asked
GetMoneyString = function(copper, separate)
    asked = separate
    return "money:" .. copper
end
C_CurrencyInfo = { GetCoinTextureString = function(copper) return "coins:" .. copper end }
T.load("Lib/Money")
eq(ns.Money(12345), "money:12345", "money: Blizzard's money text")
eq(asked, true, "money: with thousands separated")
GetMoneyString = nil
T.load("Lib/Money") -- it caches GetMoneyString
eq(ns.Money(50), "coins:50", "money: the coin text without it")
