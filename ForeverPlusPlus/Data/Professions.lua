-- Hand-kept data about gathering and professions: herbs and veins, the stones veins give, rare
-- vein spawns, chests, fishing pools, profession tools, and skeleton keys. Lib/Professions.lua
-- makes each a ns.GameData set, so what play shows is learned over it; a fix to the seed is made
-- here. None of it is in the client's tables (docs/table-survey.md, 1 and 8).
local _, ns = ...

ns.Data = ns.Data or {}

-- Skill lines, as Lib/Professions.lua names them.
local HERB, MINE = 182, 186
local SKINNING, BLACKSMITHING, ENGINEERING = 393, 164, 202

-- Herbs and veins by their name in the world: the skill line that gathers them, the skill it
-- takes, and the item they give first. Classic's, in English; the game teaches the rest
-- (Professions.LearnRequirement, LearnNodeItem), so other languages and Forever's changes fill in
-- as the player meets them. Every skill here is one the client's Lock table has (27 of 27 herb
-- skills and 11 of 11 vein skills, build 70888; docs/table-survey.md, 8), though the table names
-- none of them.
ns.Data.professionNodes = { -- object name -> { skill line, skill, item ID }
    ["Peacebloom"] = { HERB, 1, 2447 },
    ["Silverleaf"] = { HERB, 1, 765 },
    ["Earthroot"] = { HERB, 15, 2449 },
    ["Mageroyal"] = { HERB, 50, 785 },
    ["Briarthorn"] = { HERB, 70, 2450 },
    ["Stranglekelp"] = { HERB, 85, 3820 },
    ["Bruiseweed"] = { HERB, 100, 2453 },
    ["Wild Steelbloom"] = { HERB, 115, 3355 },
    ["Grave Moss"] = { HERB, 120, 3369 },
    ["Kingsblood"] = { HERB, 125, 3356 },
    ["Liferoot"] = { HERB, 150, 3357 },
    ["Fadeleaf"] = { HERB, 160, 3818 },
    ["Goldthorn"] = { HERB, 170, 3821 },
    ["Khadgar's Whisker"] = { HERB, 185, 3358 },
    ["Wintersbite"] = { HERB, 195, 3819 },
    ["Firebloom"] = { HERB, 205, 4625 },
    ["Purple Lotus"] = { HERB, 210, 8831 },
    ["Arthas' Tears"] = { HERB, 220, 8836 },
    ["Sungrass"] = { HERB, 230, 8838 },
    ["Blindweed"] = { HERB, 235, 8839 },
    ["Ghost Mushroom"] = { HERB, 245, 8845 },
    ["Gromsblood"] = { HERB, 250, 8846 },
    ["Golden Sansam"] = { HERB, 260, 13464 },
    ["Dreamfoil"] = { HERB, 270, 13463 },
    ["Mountain Silversage"] = { HERB, 280, 13465 },
    ["Plaguebloom"] = { HERB, 285, 13466 },
    ["Icecap"] = { HERB, 290, 13467 },
    ["Black Lotus"] = { HERB, 300, 13468 },

    ["Copper Vein"] = { MINE, 1, 2770 },
    ["Tin Vein"] = { MINE, 65, 2771 },
    ["Incendicite Mineral Vein"] = { MINE, 65, 3340 },
    ["Silver Vein"] = { MINE, 75, 2775 },
    ["Ooze Covered Silver Vein"] = { MINE, 75, 2775 },
    ["Lesser Bloodstone Deposit"] = { MINE, 75, 4278 },
    ["Iron Deposit"] = { MINE, 125, 2772 },
    ["Ooze Covered Iron Deposit"] = { MINE, 125, 2772 },
    ["Indurium Mineral Vein"] = { MINE, 150, 5833 },
    ["Gold Vein"] = { MINE, 155, 2776 },
    ["Ooze Covered Gold Vein"] = { MINE, 155, 2776 },
    ["Mithril Deposit"] = { MINE, 175, 3858 },
    ["Ooze Covered Mithril Deposit"] = { MINE, 175, 3858 },
    ["Truesilver Deposit"] = { MINE, 230, 7911 },
    ["Ooze Covered Truesilver Deposit"] = { MINE, 230, 7911 },
    ["Dark Iron Deposit"] = { MINE, 230, 11370 },
    ["Small Thorium Vein"] = { MINE, 245, 10620 },
    ["Ooze Covered Thorium Vein"] = { MINE, 245, 10620 },
    ["Rich Thorium Vein"] = { MINE, 275, 10620 },
    ["Ooze Covered Rich Thorium Vein"] = { MINE, 275, 10620 },
    ["Hakkari Thorium Vein"] = { MINE, 275, 10620 },
    ["Small Obsidian Chunk"] = { MINE, 305, 22202 },
    ["Large Obsidian Chunk"] = { MINE, 305, 22203 },
}

-- The stone a vein gives besides its ore, which no node lists as its item: item ID -> the Mining
-- skill of the lowest vein that gives it. Classic's values.
ns.Data.miningStones = {
    [2835] = 1, -- Rough Stone
    [2836] = 65, -- Coarse Stone
    [2838] = 125, -- Heavy Stone
    [7912] = 175, -- Solid Stone
    [12365] = 245, -- Dense Stone
}

-- Spots that spawn either of two veins: the rarer one -> the vein it takes the place of. Classic's
-- (the rare spawns GatherMate2 also knows); the game shows no list of them.
ns.Data.sharedSpawns = {
    ["Silver Vein"] = "Tin Vein",
    ["Gold Vein"] = "Iron Deposit",
    ["Truesilver Deposit"] = "Mithril Deposit",
    ["Ooze Covered Silver Vein"] = "Tin Vein",
    ["Ooze Covered Gold Vein"] = "Iron Deposit",
    ["Ooze Covered Truesilver Deposit"] = "Mithril Deposit",
}

-- The chests in the world, by name: true, or the Lockpicking a locked one takes. The Opening
-- spell opens much besides chests (quest objects, crates a quest asks for), so only these count as
-- treasure. Classic's world chests, from memory of Classic Era (2026-11-07), unverified on
-- Forever; a chest's "Requires Lockpicking (N)" line teaches its skill, and more chests.
ns.Data.treasureNodes = {
    ["Battered Chest"] = true,
    ["Tattered Chest"] = true,
    ["Solid Chest"] = true,
    ["Large Battered Chest"] = true,
    ["Large Iron Bound Chest"] = true,
    ["Large Solid Chest"] = true,
    ["Large Mithril Bound Chest"] = true,
    ["Dented Footlocker"] = true,
    ["Mossy Footlocker"] = true,
    ["Waterlogged Footlocker"] = true,
    ["Buccaneer's Strongbox"] = true,
    ["Box of Assorted Parts"] = true,
    ["Burial Chest"] = true,
}

-- The fishing pools in the world, by name. Classic's pools, from memory of Classic Era
-- (2026-11-07), unverified on Forever; play teaches more.
ns.Data.fishingPools = {
    ["Floating Wreckage"] = true,
    ["Floating Debris"] = true,
    ["Oil Spill"] = true,
    ["Patch of Elemental Water"] = true,
    ["School of Deviate Fish"] = true,
    ["Oily Blackmouth School"] = true,
    ["Firefin Snapper School"] = true,
    ["Sagefish School"] = true,
    ["Greater Sagefish School"] = true,
    ["Stonescale Eel Swarm"] = true,
    ["Schooner Wreckage"] = true,
    ["Waterlogged Wreckage"] = true,
}

-- The fishing bobber as a world object: loot from it is open water, not a pool. Classic's Fishing
-- Bobber, object 35591; unverified on Forever.
ns.Data.fishingBobbers = { [35591] = true }

-- Profession tools a character can equip but carries for their profession, not to fight with:
-- item ID -> the skill line. Classic's IDs (Classic Era 1.15 item data). Fishing poles are told
-- by their weapon subclass instead, so every pole counts.
ns.Data.professionTools = {
    [2901] = MINE, -- Mining Pick
    [5956] = BLACKSMITHING, -- Blacksmith Hammer
    [7005] = SKINNING, -- Skinning Knife
    [6219] = ENGINEERING, -- Arclight Spanner
}

-- Blacksmiths make skeleton keys that open locks like Lockpicking: item ID, the skill it opens
-- up to, and the Blacksmithing skill that makes it. Classic's values, unverified on Forever.
ns.Data.skeletonKeys = {
    { id = 15869, skill = 100, smith = 100 }, -- Silver Skeleton Key
    { id = 15870, skill = 150, smith = 150 }, -- Golden Skeleton Key
    { id = 15871, skill = 200, smith = 200 }, -- Truesilver Skeleton Key
    { id = 15872, skill = 275, smith = 275 }, -- Arcanite Skeleton Key
}
