-- Prices: auction prices from a source, Auctionator, and prices as they're saved.
local T = ...
local ns, eq, game = T.ns, T.eq, T.game

local Prices = ns.Prices
game.cachedItems["Strange Dust"] = 10940
eq(Prices.Available(), false, "no prices without a source")
eq(Prices.Auction(10940), nil, "no auction price without a source")
eq(Prices.ItemByName("Strange Dust"), 10940, "item cache finds a name without a source")
eq(Prices.ItemByName("Bolt of Silk Cloth"), nil, "unknown name without a source")
eq(Prices.Inline(), false, "price lines at the edge without a source")
Prices.SetSource({
    price = function(itemID)
        return itemID == 4305 and 120 or nil
    end,
    itemByName = function(name)
        return name == "Bolt of Silk Cloth" and 4305 or nil
    end,
    inline = function()
        return true
    end,
})
eq(Prices.Available(), true, "prices with a source")
eq(Prices.Auction(4305), 120, "source's price")
eq(Prices.Auction(10940), nil, "item the source has no price for")
eq(Prices.ItemByName("Bolt of Silk Cloth"), 4305, "source finds a name the cache doesn't")
eq(Prices.ItemByName("Strange Dust"), 10940, "item cache first")
eq(Prices.Inline(), true, "source's alignment")
eq(Prices.AgeColor(60), "gray", "a source without an age color gives gray")
Prices.SetSource(nil)
eq(Prices.Auction(4305), nil, "no prices once the source goes")
eq(Prices.AgeColor(60), "gray", "no source, a gray age")
Prices.SetSource({
    price = function() return nil end,
    itemByName = function() return nil end,
    inline = function() return false end,
    ageColor = function(seconds) return seconds > 100 and { 1, 0, 0 } or "white" end,
})
eq(Prices.AgeColor(10), "white", "the source's age color, by name")
eq(Prices.AgeColor(200)[1], 1, "or as a color")
Prices.SetSource(nil)

-- Auctionator's prices, while the player chose them and it's loaded.
local chooseAuctionator = false
Prices.SetSource({
    price = function(itemID)
        if itemID == 4305 then
            return 120, 1000
        end
    end,
    itemByName = function() end,
    inline = function()
        return false
    end,
    auctionator = function()
        return chooseAuctionator
    end,
})
local ownPrice, ownSeen = Prices.Auction(4305)
eq(ownPrice, 120, "auctionator: our price while it isn't chosen")
eq(ownSeen, 1000, "auctionator: and when ours was seen")
chooseAuctionator = true
eq(Prices.AuctionatorLoaded(), false, "auctionator: not loaded")
eq(Prices.UsingAuctionator(), false, "auctionator: chosen but not loaded")
eq(Prices.Auction(4305), 120, "auctionator: our price while it isn't loaded")
local callers = {}
Auctionator = { API = { v1 = {
    GetAuctionPriceByItemID = function(caller, itemID)
        callers[#callers + 1] = caller
        if type(itemID) ~= "number" then
            error("bad item ID")
        end
        return ({ [4305] = 300, [10940] = 50, [10938] = 200 })[itemID]
    end,
} } }
game.clock = 10 * 86400
eq(Prices.AuctionatorLoaded(), true, "auctionator: loaded")
eq(Prices.UsingAuctionator(), true, "auctionator: in use")
local theirPrice, theirSeen = Prices.Auction(4305)
eq(theirPrice, 300, "auctionator: its price")
eq(theirSeen, nil, "auctionator: no age without its age call")
eq(callers[1], "Forever++", "auctionator: our caller ID")
eq(Prices.Auction(2589), nil, "auctionator: an item it has no price for")
eq(Prices.Auction("x"), nil, "auctionator: its error is caught")
Auctionator.API.v1.GetAuctionAgeByItemID = function(_, itemID)
    return itemID == 4305 and 2 or nil
end
theirPrice, theirSeen = Prices.Auction(4305)
eq(theirSeen, 8 * 86400, "auctionator: seen its age in days ago")
theirPrice, theirSeen = Prices.Auction(10940)
eq(theirPrice, 50, "auctionator: a price without an age")
eq(theirSeen, nil, "auctionator: and no age for it")
-- Disenchant prices its materials through Prices.Auction: 0.8 x 1.5 x 50 + 0.2 x 1.5 x 200.
local deValue, deMissing = ns.Disenchant.Value(ns.Disenchant.Outcomes(2, 5, false), Prices.Auction)
eq(deValue, 0.8 * 1.5 * 50 + 0.2 * 1.5 * 200, "auctionator: disenchant value from its prices")
eq(deMissing, 0, "auctionator: every disenchant outcome priced")
chooseAuctionator = false
eq(Prices.Auction(4305), 120, "auctionator: back to ours when it's turned off")
chooseAuctionator = true
Prices.SetSource(nil)
eq(Prices.UsingAuctionator(), false, "auctionator: not in use without a source")
eq(Prices.Auction(4305), nil, "auctionator: no prices without a source")
Auctionator = nil

-- Saved prices ------------------------------------------------------------------------------------

local packed = Prices.Pack(4800, 1791836472)
eq(packed, "4800,1530607", "prices: a saved price is copper and minutes")
local copper, seenAt = Prices.Unpack(packed)
eq(copper, 4800, "prices: unpacked copper")
eq(seenAt, 1791836420, "prices: unpacked time, to the minute")
eq(Prices.Pack(10000000000, 1792175033), "10000000000,1536250", "prices: a price past 2^31 copper")
eq((Prices.Unpack(Prices.Pack(10000000000, 1792175033))), 10000000000,
    "prices: a price past 2^31 copper comes back")
eq(Prices.Unpack(nil), nil, "prices: nothing saved")
eq(Prices.Unpack({ price = 1 }), nil, "prices: an old table isn't a saved price")
copper, seenAt = Prices.Unpack(Prices.Pack(700, 0))
eq(copper, 700, "prices: a price seen before the epoch keeps its copper")
eq(seenAt <= 0, true, "prices: and a time before the epoch")

-- A house from 0.7.0 to 0.8.4, and one from before 0.7.0.
local newer = { scannedAt = 1791836000, items = { [1] = { price = 50, seenAt = 1791836472 },
    [2] = "60,1530600", [3] = { broken = true } } }
Prices.PackHouse(newer)
eq(newer.items[1], Prices.Pack(50, 1791836472), "prices: a saved table is packed")
eq(newer.items[2], "60,1530600", "prices: a packed price stays")
eq(newer.items[3], nil, "prices: a broken entry goes")
local older = { scannedAt = 1790781485, prices = { [7] = 4800, [8] = 700 } }
Prices.PackHouse(older)
eq(older.prices, nil, "prices: the old price list goes")
copper, seenAt = Prices.Unpack(older.items[7])
eq(copper, 4800, "prices: an old price is kept")
eq(math.abs(seenAt - 1790781485) < 60, true, "prices: aged from the house's scan")
local unscanned = { prices = { [7] = 4800 } }
Prices.PackHouse(unscanned)
eq(unscanned.prices, nil, "prices: an unscanned house's old list goes")
eq(unscanned.items[7], nil, "prices: and its prices with it, having no age")
local zeroScan = { scannedAt = 0, prices = { [7] = 4800 } }
Prices.PackHouse(zeroScan)
eq(zeroScan.items[7], nil, "prices: a house scanned at 0 drops its old prices")
