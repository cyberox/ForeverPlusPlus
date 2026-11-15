-- Hand-kept lists of items a module acts on. Each module makes its list a ns.GameData set, so
-- Self Test checks the client still has the items and play can teach more; a fix to a list is
-- made here.
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

-- Auto Weapon Buff: what each item goes on, by kind: "sharp" (sharpening stones), "blunt"
-- (weightstones), "melee" (oils and poisons: any weapon but a fishing pole), or "pole" (fishing
-- lures). Classic's items; Forever's own aren't listed yet, and one used in play is learned.
ns.Data.weaponBuffs = {
    -- Sharpening stones: Rough, Coarse, Heavy, Solid, Dense, Elemental, Consecrated.
    sharp = { 2862, 2863, 2871, 7964, 12404, 18262, 23122 },
    -- Weightstones: Rough, Coarse, Heavy, Solid, Dense.
    blunt = { 3239, 3240, 3241, 7965, 12643 },
    melee = {
        -- Wizard and mana oils, Blessed Wizard Oil, Shadow Oil, Frost Oil.
        20744, 20746, 20750, 20749, 20745, 20747, 20748, 23123, 3824, 3829,
        -- Poisons: Instant I-VI, Deadly I-V, Crippling I-II, Mind-numbing I-III, Wound I-IV.
        6947, 6949, 6950, 8926, 8927, 8928, 2892, 2893, 8984, 8985, 20844, 3775, 3776,
        5237, 6951, 9186, 10918, 10920, 10921, 10922,
    },
    -- Lures: Shiny Bauble, Nightcrawlers, Bright Baubles, Aquadynamic Fish Attractor, Flesh
    -- Eating Worm, Aquadynamic Fish Lens.
    pole = { 6529, 6530, 6532, 6533, 7307, 6811 },
}

-- Comprehend Scrolls: the scrolls that need Comprehension (ItemSparse.RequiredSkill 3012), Mage
-- only. From wago.tools' ItemSparse for 1.60.1.70374; the same 17 in 70888. Any other bag item
-- whose tooltip says "Requires Comprehension (N)" is learned as one too.
ns.Data.comprehendScrolls = {
    [211780] = true, [211784] = true, [211785] = true, [211786] = true, [211787] = true,
    [211853] = true, [211854] = true, [211855] = true,
    [213543] = true, [213544] = true, [213545] = true, [213546] = true, [213547] = true,
    [281015] = true, [281016] = true, [281017] = true, [281018] = true,
}
