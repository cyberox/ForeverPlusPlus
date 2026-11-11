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
eq(ns.MoneyShort(123456), "money:120000", "money: short rounds to whole gold")
eq(ns.MoneyShort(15000), "money:20000", "money: short rounds half a gold up")
eq(ns.MoneyShort(9999.6), "money:10000", "money: short rounds to the copper under a gold")
eq(ns.MoneyShort(2550), "money:2550", "money: short keeps silver and copper under a gold")
eq(ns.MoneyShort(-34567), "-money:30000", "money: short puts a minus before a loss")
eq(ns.MoneyShort(-0.2), "money:0", "money: short has no minus on nothing")
GetMoneyString = nil
T.load("Lib/Money") -- it caches GetMoneyString
eq(ns.Money(50), "coins:50", "money: the coin text without it")
