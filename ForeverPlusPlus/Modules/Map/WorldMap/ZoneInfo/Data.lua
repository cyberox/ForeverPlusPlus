-- What Zone Info knows about each zone, by zone map ID. From Classic: Leatrix Maps' zone table was
-- the reference for level ranges and fishing, and the herbs and ores are where Classic has them
-- (a few rare spawns left out). Forever may move things; fix them here. Each zone is:
--   { lowest level, highest level, fish = skill, fishHigh = skill, herbs = { ... }, ores = { ... } }
-- Cities have no levels. For a zone that has them, the game's own level range
-- (C_Map.GetMapLevels) wins when it gives one. `fishHigh` is for zones whose coast needs more
-- than their inland water.
-- Herbs and ores are item IDs, from the lists below. Who holds each zone (`side`) and its
-- dungeons (`dungeons`) are added at the end.
local _, ns = ...

local pairs, ipairs = pairs, ipairs

local internal = ns.modules.WorldMap.internal.zoneInfo

-- Herbs and ores: item ID -> { skill needed to gather, short English name }. Other languages
-- use the game's item name. The skills match Lib/Professions.lua's herbs and veins.
internal.herbs = {
    [2447] = { 1, "Peacebloom" },
    [765] = { 1, "Silverleaf" },
    [2449] = { 15, "Earthroot" },
    [785] = { 50, "Mageroyal" },
    [2450] = { 70, "Briarthorn" },
    [3820] = { 85, "Stranglekelp" },
    [2453] = { 100, "Bruiseweed" },
    [3355] = { 115, "Wild Steelbloom" },
    [3369] = { 120, "Grave Moss" },
    [3356] = { 125, "Kingsblood" },
    [3357] = { 150, "Liferoot" },
    [3818] = { 160, "Fadeleaf" },
    [3821] = { 170, "Goldthorn" },
    [3358] = { 185, "Khadgar's Whisker" },
    [3819] = { 195, "Wintersbite" },
    [4625] = { 205, "Firebloom" },
    [8831] = { 210, "Purple Lotus" },
    [8836] = { 220, "Arthas' Tears" },
    [8838] = { 230, "Sungrass" },
    [8839] = { 235, "Blindweed" },
    [8846] = { 250, "Gromsblood" },
    [13464] = { 260, "Golden Sansam" },
    [13463] = { 270, "Dreamfoil" },
    [13465] = { 280, "Mountain Silversage" },
    [13466] = { 285, "Plaguebloom" },
    [13467] = { 290, "Icecap" },
    [13468] = { 300, "Black Lotus" },
}

internal.ores = {
    [2770] = { 1, "Copper" },
    [2771] = { 65, "Tin" },
    [3340] = { 65, "Incendicite" },
    [2775] = { 75, "Silver" },
    [4278] = { 75, "Lesser Bloodstone" },
    [2772] = { 125, "Iron" },
    [2776] = { 155, "Gold" },
    [3858] = { 175, "Mithril" },
    [7911] = { 230, "Truesilver" },
    [11370] = { 230, "Dark Iron" },
    [10620] = { 245, "Thorium" },
}

-- Herbs
local PEACEBLOOM, SILVERLEAF, EARTHROOT, MAGEROYAL, BRIARTHORN = 2447, 765, 2449, 785, 2450
local STRANGLEKELP, BRUISEWEED, STEELBLOOM, GRAVE_MOSS, KINGSBLOOD = 3820, 2453, 3355, 3369, 3356
local LIFEROOT, FADELEAF, GOLDTHORN, KHADGARS, WINTERSBITE = 3357, 3818, 3821, 3358, 3819
local FIREBLOOM, PURPLE_LOTUS, ARTHAS_TEARS, SUNGRASS, BLINDWEED = 4625, 8831, 8836, 8838, 8839
local GROMSBLOOD, SANSAM, DREAMFOIL, SILVERSAGE, PLAGUEBLOOM = 8846, 13464, 13463, 13465, 13466
local ICECAP, BLACK_LOTUS = 13467, 13468
-- Ores
local COPPER, TIN, INCENDICITE, SILVER, BLOODSTONE = 2770, 2771, 3340, 2775, 4278
local IRON, GOLD, MITHRIL, TRUESILVER, DARK_IRON, THORIUM = 2772, 2776, 3858, 7911, 11370, 10620

local STARTER_HERBS = { PEACEBLOOM, SILVERLEAF, EARTHROOT }
local LOW_HERBS = { PEACEBLOOM, SILVERLEAF, EARTHROOT, MAGEROYAL, BRIARTHORN }
local LOW_ORES = { COPPER, TIN, SILVER }

internal.zones = {
    -- Eastern Kingdoms -----------------------------------------------------------------------
    [1429] = { 1, 10, fish = 1, herbs = STARTER_HERBS, ores = { COPPER } }, -- Elwynn Forest
    [1426] = { 1, 10, fish = 1, herbs = STARTER_HERBS, ores = { COPPER } }, -- Dun Morogh
    [1420] = { 1, 10, fish = 1, herbs = STARTER_HERBS, ores = { COPPER } }, -- Tirisfal Glades
    [1432] = { 10, 20, fish = 1, herbs = LOW_HERBS, ores = LOW_ORES }, -- Loch Modan
    [1436] = { 10, 20, fish = 1, herbs = LOW_HERBS, ores = LOW_ORES }, -- Westfall
    [1421] = { 10, 20, fish = 1, herbs = LOW_HERBS, ores = LOW_ORES }, -- Silverpine Forest
    [1433] = { 15, 25, fish = 55, -- Redridge Mountains
        herbs = { PEACEBLOOM, SILVERLEAF, EARTHROOT, MAGEROYAL, BRIARTHORN, BRUISEWEED },
        ores = LOW_ORES },
    [1431] = { 18, 30, fish = 55, -- Duskwood
        herbs = { MAGEROYAL, BRIARTHORN, BRUISEWEED, GRAVE_MOSS, KINGSBLOOD },
        ores = LOW_ORES },
    [1424] = { 20, 30, fish = 55, -- Hillsbrad Foothills
        herbs = { MAGEROYAL, BRIARTHORN, STRANGLEKELP, BRUISEWEED, STEELBLOOM, KINGSBLOOD, LIFEROOT },
        ores = { COPPER, TIN, SILVER, IRON, GOLD } },
    [1437] = { 20, 30, fish = 55, -- Wetlands
        herbs = { BRIARTHORN, STRANGLEKELP, BRUISEWEED, STEELBLOOM, GRAVE_MOSS, KINGSBLOOD, LIFEROOT },
        ores = { COPPER, TIN, INCENDICITE, SILVER, IRON, GOLD } },
    [1416] = { 30, 40, fish = 130, -- Alterac Mountains
        herbs = { STEELBLOOM, KINGSBLOOD, LIFEROOT, FADELEAF, GOLDTHORN, KHADGARS, WINTERSBITE },
        ores = { TIN, SILVER, IRON, GOLD } },
    [1417] = { 30, 40, fish = 130, -- Arathi Highlands
        herbs = { STRANGLEKELP, STEELBLOOM, KINGSBLOOD, LIFEROOT, FADELEAF, GOLDTHORN, KHADGARS },
        ores = { TIN, SILVER, BLOODSTONE, IRON, GOLD } },
    [1434] = { 30, 45, fish = 130, fishHigh = 205, -- Stranglethorn Vale
        herbs = { STRANGLEKELP, KINGSBLOOD, LIFEROOT, FADELEAF, GOLDTHORN, KHADGARS, PURPLE_LOTUS },
        ores = { TIN, SILVER, IRON, GOLD, MITHRIL, TRUESILVER } },
    [1418] = { 35, 45, -- Badlands
        herbs = { FADELEAF, GOLDTHORN, KHADGARS, FIREBLOOM, PURPLE_LOTUS },
        ores = { IRON, GOLD, MITHRIL, TRUESILVER } },
    [1435] = { 35, 45, fish = 130, -- Swamp of Sorrows
        herbs = { KINGSBLOOD, LIFEROOT, FADELEAF, GOLDTHORN, KHADGARS, BLINDWEED },
        ores = { IRON, GOLD, MITHRIL, TRUESILVER } },
    [1425] = { 40, 50, fish = 205, -- The Hinterlands
        herbs = { GOLDTHORN, KHADGARS, PURPLE_LOTUS, SUNGRASS },
        ores = { IRON, GOLD, MITHRIL, TRUESILVER, THORIUM } },
    [1427] = { 43, 50, -- Searing Gorge
        herbs = { FIREBLOOM },
        ores = { IRON, GOLD, MITHRIL, TRUESILVER, DARK_IRON, THORIUM } },
    [1419] = { 45, 55, -- Blasted Lands
        herbs = { FIREBLOOM, SUNGRASS, GROMSBLOOD },
        ores = { MITHRIL, TRUESILVER, THORIUM } },
    [1428] = { 50, 58, fish = 330, -- Burning Steppes
        herbs = { FIREBLOOM, SUNGRASS, SANSAM, DREAMFOIL, SILVERSAGE },
        ores = { MITHRIL, TRUESILVER, DARK_IRON, THORIUM } },
    [1422] = { 51, 58, fish = 205, -- Western Plaguelands
        herbs = { ARTHAS_TEARS, SUNGRASS, SANSAM, DREAMFOIL, PLAGUEBLOOM },
        ores = { MITHRIL, TRUESILVER, THORIUM } },
    [1423] = { 53, 60, fish = 330, -- Eastern Plaguelands
        herbs = { ARTHAS_TEARS, SUNGRASS, SANSAM, DREAMFOIL, SILVERSAGE, PLAGUEBLOOM },
        ores = { MITHRIL, TRUESILVER, THORIUM } },
    [1430] = { 55, 60, fish = 330 }, -- Deadwind Pass
    [1453] = { fish = 1 }, -- Stormwind City
    [1455] = { fish = 1 }, -- Ironforge
    [1458] = { fish = 1 }, -- Undercity

    -- Kalimdor -------------------------------------------------------------------------------
    [1411] = { 1, 10, fish = 1, herbs = STARTER_HERBS, ores = { COPPER } }, -- Durotar
    [1412] = { 1, 10, fish = 1, herbs = STARTER_HERBS, ores = { COPPER } }, -- Mulgore
    [1438] = { 1, 10, fish = 1, herbs = STARTER_HERBS }, -- Teldrassil
    [1439] = { 10, 20, fish = 1, -- Darkshore
        herbs = { PEACEBLOOM, SILVERLEAF, EARTHROOT, MAGEROYAL, BRIARTHORN, STRANGLEKELP, BRUISEWEED },
        ores = LOW_ORES },
    [1413] = { 10, 25, fish = 1, -- The Barrens
        herbs = { PEACEBLOOM, SILVERLEAF, EARTHROOT, MAGEROYAL, BRIARTHORN, STRANGLEKELP, BRUISEWEED,
            STEELBLOOM },
        ores = LOW_ORES },
    [1442] = { 15, 27, fish = 55, -- Stonetalon Mountains
        herbs = { EARTHROOT, MAGEROYAL, BRIARTHORN, BRUISEWEED, STEELBLOOM, KINGSBLOOD },
        ores = LOW_ORES },
    [1440] = { 18, 30, fish = 55, -- Ashenvale
        herbs = { MAGEROYAL, BRIARTHORN, STRANGLEKELP, BRUISEWEED, STEELBLOOM, KINGSBLOOD, LIFEROOT },
        ores = { COPPER, TIN, SILVER, IRON, GOLD } },
    [1441] = { 25, 35, fish = 130, -- Thousand Needles
        herbs = { BRUISEWEED, STEELBLOOM, KINGSBLOOD, LIFEROOT, FADELEAF },
        ores = { TIN, SILVER, IRON, GOLD, MITHRIL } },
    [1443] = { 30, 40, fish = 130, -- Desolace
        herbs = { STRANGLEKELP, STEELBLOOM, KINGSBLOOD, LIFEROOT, FADELEAF, GOLDTHORN },
        ores = { TIN, SILVER, IRON, GOLD } },
    [1445] = { 35, 45, fish = 130, -- Dustwallow Marsh
        herbs = { STRANGLEKELP, KINGSBLOOD, LIFEROOT, FADELEAF, GOLDTHORN, KHADGARS },
        ores = { TIN, SILVER, IRON, GOLD, MITHRIL } },
    [1444] = { 40, 50, fish = 205, fishHigh = 330, -- Feralas
        herbs = { STRANGLEKELP, GOLDTHORN, KHADGARS, PURPLE_LOTUS, SUNGRASS },
        ores = { IRON, GOLD, MITHRIL, TRUESILVER } },
    [1446] = { 40, 50, fish = 205, -- Tanaris
        herbs = { FIREBLOOM, PURPLE_LOTUS },
        ores = { IRON, GOLD, MITHRIL, TRUESILVER, THORIUM } },
    [1447] = { 45, 55, fish = 205, fishHigh = 330, -- Azshara
        herbs = { PURPLE_LOTUS, SUNGRASS, SANSAM, DREAMFOIL, SILVERSAGE },
        ores = { MITHRIL, TRUESILVER, THORIUM } },
    [1448] = { 48, 55, fish = 205, -- Felwood
        herbs = { ARTHAS_TEARS, SUNGRASS, GROMSBLOOD, SANSAM, DREAMFOIL, PLAGUEBLOOM },
        ores = { MITHRIL, TRUESILVER, THORIUM } },
    [1449] = { 48, 55, fish = 205, -- Un'Goro Crater
        herbs = { SUNGRASS, BLINDWEED, SANSAM, DREAMFOIL, SILVERSAGE },
        ores = { MITHRIL, TRUESILVER, THORIUM } },
    [1451] = { 55, 60, fish = 330, -- Silithus
        herbs = { SANSAM, DREAMFOIL, SILVERSAGE, BLACK_LOTUS },
        ores = { TRUESILVER, THORIUM } },
    [1452] = { 55, 60, fish = 330, -- Winterspring
        herbs = { DREAMFOIL, SILVERSAGE, ICECAP, BLACK_LOTUS },
        ores = { MITHRIL, TRUESILVER, THORIUM } },
    [1450] = { fish = 205 }, -- Moonglade
    [1457] = { fish = 1 }, -- Darnassus
    [1454] = { fish = 1 }, -- Orgrimmar
    [1456] = { fish = 1 }, -- Thunder Bluff

    -- Forever's own zones: levels from Leatrix Maps; what grows there isn't known yet --------
    [2482] = { 60, 60 }, -- Hyjal
    [2521] = { 1, 12 }, -- Zephras Isle
    [2548] = { 35, 45 }, -- Riverglades
    [2652] = { 35, 45 }, -- Shen'dralas
}

-- Who holds each zone, as Classic has it: "A" (Alliance), "H" (Horde), or "C" (contested).
-- Forever's own zones aren't listed until we know.
local SIDES = {
    A = { 1429, 1426, 1432, 1436, 1433, 1431, 1437, 1453, 1455, 1438, 1439, 1457 },
    H = { 1420, 1421, 1458, 1411, 1412, 1413, 1454, 1456 },
    C = { 1424, 1416, 1417, 1434, 1418, 1435, 1425, 1427, 1419, 1428, 1422, 1423, 1430, 1442,
        1440, 1441, 1443, 1445, 1444, 1446, 1447, 1448, 1449, 1451, 1452, 1450 },
}
for side, maps in pairs(SIDES) do
    for _, mapID in ipairs(maps) do
        internal.zones[mapID].side = side
    end
end

-- The dungeons and raids whose entrance is in each zone, from Lib/Instances.lua. Blackrock
-- Mountain sits between Searing Gorge and Burning Steppes, so both list it.
local I = ns.Instances.byKey
local BLACKROCK = { I.brd, I.brs, I.mc, I.bwl }
local DUNGEONS = {
    [1436] = { I.deadmines }, -- Westfall
    [1453] = { I.stockade }, -- Stormwind City
    [1421] = { I.shadowfang }, -- Silverpine Forest
    [1426] = { I.gnomeregan }, -- Dun Morogh
    [1455] = { I.hallOfThanes }, -- Ironforge
    [1458] = { I.ruinsOfLordaeron }, -- Undercity
    [1420] = { I.scarlet }, -- Tirisfal Glades
    [1437] = { I.excavationSite }, -- Wetlands
    [1416] = { I.dalaran }, -- Alterac Mountains
    [1418] = { I.uldaman }, -- Badlands
    [1435] = { I.sunkenTemple }, -- Swamp of Sorrows
    [1427] = BLACKROCK, -- Searing Gorge
    [1428] = BLACKROCK, -- Burning Steppes
    [1434] = { I.drownedCity, I.zulgurub }, -- Stranglethorn Vale
    [2548] = { I.kroldok }, -- Riverglades
    [1447] = { I.blackmawHold }, -- Azshara
    [1449] = { I.shapersTerrace }, -- Un'Goro Crater
    [1422] = { I.scholomance }, -- Western Plaguelands
    [1423] = { I.stratholme, I.naxxramas }, -- Eastern Plaguelands
    [1454] = { I.ragefire }, -- Orgrimmar
    [1413] = { I.wailing, I.razorfenKraul, I.razorfenDowns }, -- The Barrens
    [1440] = { I.blackfathom }, -- Ashenvale
    [1443] = { I.maraudon }, -- Desolace
    [1446] = { I.zulfarrak }, -- Tanaris
    [1444] = { I.diremaul }, -- Feralas
    [1445] = { I.alcazPrison, I.onyxia }, -- Dustwallow Marsh
    [1451] = { I.aq20, I.aq40 }, -- Silithus
}
for mapID, dungeons in pairs(DUNGEONS) do
    internal.zones[mapID].dungeons = dungeons
end

-- So Self Test lists a zone's map ID the client no longer has.
ns.GameData.New("zoneInfoZones", internal.zones, { kind = "map", label = "Zone Info zones" })
