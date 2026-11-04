-- Auction prices for any module: Item Tooltips' Auction Prices scans the auction house and gives
-- its prices here while it's on, and other modules (Waylaid Crates) read them without reaching
-- into it. With no source, there are no prices. With its Use Auctionator's Prices option on and
-- Auctionator loaded, the prices come from Auctionator instead, so every module that reads them
-- here switches together.
local _, ns = ...

local C_Item = C_Item
local floor, format, tonumber, type, pairs, ipairs = math.floor, string.format, tonumber, type, pairs, ipairs
local pcall, time = pcall, time

local Prices = {}
ns.Prices = Prices

-- Saved prices ------------------------------------------------------------------------------------
-- A saved price is one short string, "copper,minutes", with the minutes since EPOCH it was seen:
-- thousands of them are saved, and a table each took three times the room in the saved file.

local EPOCH = 1700000000 -- 2023-11-14, before any price was saved

---A price and the time it was seen as the string saved for it.
---@param copper number
---@param seenAt number time()
---@return string
function Prices.Pack(copper, seenAt)
    -- %.0f, since the game's %d overflows past 2^31 copper (214,748g) and listings go higher.
    return format("%.0f,%d", floor(copper + 0.5), floor((seenAt - EPOCH) / 60))
end

---The price and the time (to the minute) a saved string holds, or nil for none.
---@param saved string|nil
---@return number|nil copper
---@return number|nil seenAt
function Prices.Unpack(saved)
    if type(saved) ~= "string" then
        return nil
    end
    local copper, minutes = saved:match("^(%d+),(%-?%d+)$")
    if not copper then
        return nil
    end
    return tonumber(copper), EPOCH + tonumber(minutes) * 60
end

---Brings one auction house's saved prices to the packed form, for a migration: items saved as
---{ price, seenAt } tables (0.7.0 to 0.8.4), and `prices` saved before 0.7.0 with only the house's
---scan time, which become items seen at that scan.
---@param house table { scannedAt, items, prices }
function Prices.PackHouse(house)
    if type(house) ~= "table" then
        return
    end
    local items = type(house.items) == "table" and house.items or {}
    for itemID, item in pairs(items) do
        if type(item) == "table" and type(item.price) == "number" and type(item.seenAt) == "number" then
            items[itemID] = Prices.Pack(item.price, item.seenAt)
        elseif type(item) ~= "string" then
            items[itemID] = nil
        end
    end
    -- Without a scan time there's no age to give them, so they go rather than show as decades old.
    local scannedAt = house.scannedAt
    if type(house.prices) == "table" and type(scannedAt) == "number" and scannedAt > 0 then
        for itemID, copper in pairs(house.prices) do
            if items[itemID] == nil and type(copper) == "number" then
                items[itemID] = Prices.Pack(copper, scannedAt)
            end
        end
    end
    house.prices = nil
    house.items = items
    house.scannedAt = house.scannedAt or 0
end

-- Auctionator ----------------------------------------------------------------------------------
-- Only its public API (Auctionator.API.v1), never its code or saved data. UNVERIFIED on Forever:
-- Auctionator hasn't been run alongside us there, so these calls follow its Retail documentation.
-- The API raises an error on bad input, so every call is wrapped.

local CALLER = "Forever++" -- the caller ID Auctionator's API asks for
local DAY = 86400

-- Auctionator's API, or nil when it isn't loaded. Looked up at each call, not at load, since it
-- can load after us (OptionalDeps should load it first).
local function auctionatorAPI()
    local auctionator = _G.Auctionator
    local api = type(auctionator) == "table" and type(auctionator.API) == "table" and auctionator.API.v1
    if type(api) == "table" and type(api.GetAuctionPriceByItemID) == "function" then
        return api
    end
end

---Whether Auctionator is loaded with the price API we use.
---@return boolean
function Prices.AuctionatorLoaded()
    return auctionatorAPI() ~= nil
end

-- Auctionator's price for one of an item and when it was seen. It gives the age in whole days,
-- so seenAt is that many days ago; nil when its version has no age call or doesn't know it.
local function auctionatorPrice(itemID)
    local api = auctionatorAPI()
    local ok, copper = pcall(api.GetAuctionPriceByItemID, CALLER, itemID)
    if not (ok and type(copper) == "number" and copper > 0) then
        return nil
    end
    local seenAt
    if type(api.GetAuctionAgeByItemID) == "function" then
        local found, days = pcall(api.GetAuctionAgeByItemID, CALLER, itemID)
        if found and type(days) == "number" then
            seenAt = time() - days * DAY
        end
    end
    return copper, seenAt
end

-- Sources -----------------------------------------------------------------------------------------

local source -- { price, itemByName, inline, auctionator }, or nil
local listeners = {} -- functions told when the prices change

---Calls `fn()` whenever the prices change (see Prices.Changed). Called often while the auction
---house is browsed, so a listener that does real work should coalesce.
---@param fn function
function Prices.OnChanged(fn)
    listeners[#listeners + 1] = fn
end

---Tells the listeners the prices changed: new ones were seen, they were reset, or their source
---changed.
function Prices.Changed()
    for _, fn in ipairs(listeners) do
        ns.Call(fn)
    end
end

---Sets where auction prices come from, or nil when there are none (Auction Prices is off).
---`price` gives copper and the time() it was seen; `auctionator` whether the player chose
---Auctionator's prices.
---@param new table|nil { price = fun(itemID): number?, number?, itemByName = fun(name): number?, inline = fun(): boolean, auctionator = fun(): boolean }
function Prices.SetSource(new)
    if source == new then
        return
    end
    source = new
    Prices.Changed()
end

---Whether auction prices are available.
---@return boolean
function Prices.Available()
    return source ~= nil
end

---Whether prices come from Auctionator: the player chose it and it's loaded. Otherwise they're
---the source's own (our scans), as they were.
---@return boolean
function Prices.UsingAuctionator()
    return source ~= nil and source.auctionator ~= nil and source.auctionator() and Prices.AuctionatorLoaded()
        or false
end

---The lowest auction buyout for one of an item, in copper, and the time() it was seen (nil when
---unknown), or nil for no price.
---@param itemID number
---@return number|nil copper
---@return number|nil seenAt
function Prices.Auction(itemID)
    if not source then
        return nil
    end
    if Prices.UsingAuctionator() then
        return auctionatorPrice(itemID)
    end
    return source.price(itemID)
end

---An item's ID from its name: from the client's item cache, or else among the items with an
---auction price. Nil when neither knows it.
---@param name string
---@return number|nil
function Prices.ItemByName(name)
    local id = C_Item and C_Item.GetItemInfoInstant and C_Item.GetItemInfoInstant(name)
    if id then
        return id
    end
    return source and source.itemByName(name) or nil
end

---Whether price lines go right after their label instead of at the tooltip's right edge, as
---the player set it for Item Tooltips.
---@return boolean
function Prices.Inline()
    return source and source.inline() or false
end
