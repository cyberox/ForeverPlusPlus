-- Hand-kept lists of items a module acts on. Each module makes its list a ns.GameData set, so
-- Self Test checks the client still has the items and play can teach more; a fix to a list is
-- made here. A list the client's tables can give is generated instead (Lib/Generated/).
local _, ns = ...

ns.Data = ns.Data or {}

-- Auto Open Containers: containers left for the player to open, unless Open Special Containers
-- is on. What's inside is rolled on or traded in a raid, is a holiday gift, or is a quest's or a
-- recipe's one chance. From Open Sesame's default ignore list for Forever (Data/Camelot/
-- Default-Ignore-Items-Camelot.lua, MIT, hand-picked by its maintainer, read 2026-11-11).
ns.Data.autoOpenKept = {
    [17962] = true, -- Blue Sack of Gems (world bosses, Nefarian)
    [17963] = true, -- Green Sack of Gems
    [17964] = true, -- Gray Sack of Gems
    [17965] = true, -- Yellow Sack of Gems
    [17969] = true, -- Red Sack of Gems
    [13874] = true, -- Heavy Crate (Gahz'ranka)
    [11937] = true, -- Fat Sack of Coins (Fire Opal Necklace)
    [6352] = true, -- Waterlogged Crate (Hammer of the Vesper)
    [8049] = true, -- Gnarlpine Necklace (Tallonkai's Jewel)
    [9276] = true, -- Pirate's Footlocker (Ship Schedule, map fragments)
    [21150] = true, -- Iron Bound Trunk (Weather-Beaten Journal)
    [21228] = true, -- Mithril Bound Trunk (Weather-Beaten Journal)
    [20708] = true, -- Tightly Sealed Trunk (Weather-Beaten Journal)
    [21113] = true, -- Watertight Trunk (Weather-Beaten Journal)
    [20767] = true, -- Scum Covered Bag (Plans: Wicked Mithril Blade)
    [21979] = true, -- Gift of Adoration: Darnassus (Love is in the Air)
    [21980] = true, -- Gift of Adoration: Ironforge
    [22164] = true, -- Gift of Adoration: Orgrimmar
    [21981] = true, -- Gift of Adoration: Stormwind
    [22165] = true, -- Gift of Adoration: Thunder Bluff
    [22166] = true, -- Gift of Adoration: Undercity
    [22155] = true, -- Pledge of Adoration: Darnassus
    [22154] = true, -- Pledge of Adoration: Ironforge
    [22156] = true, -- Pledge of Adoration: Orgrimmar
    [21975] = true, -- Pledge of Adoration: Stormwind
    [22158] = true, -- Pledge of Adoration: Thunder Bluff
    [22157] = true, -- Pledge of Adoration: Undercity
}
