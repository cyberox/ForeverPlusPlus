-- Hand-kept data about the dungeons and raids: the instances themselves (Lib/Instances.lua reads
-- them) and the old map art each has (Lib/DungeonMaps.lua). Forever changes these between
-- patches, so a fix is made here.
local _, ns = ...

local L = ns.L

ns.Data = ns.Data or {}

-- Instances ---------------------------------------------------------------------------------------
-- Each is { instance ID (the game names it in the player's language), English name for when it
-- can't, lowest level, highest level, true for a raid }, by a short key.
--
-- A nil lowest level is the dungeon finder's from the client's tables
-- (Lib/Generated/InstanceLevels.lua). A number is kept by hand: the tables lack the instance, or
-- play showed otherwise (said beside it). The highest levels are guides', since no table has one.
ns.Data.instances = {
    -- Not in the finder's tables (build 70938).
    aq20 = { 509, "Ruins of Ahn'Qiraj", 60, 60, true },
    aq40 = { 531, "Temple of Ahn'Qiraj", 60, 60, true },
    blackfathom = { 48, "Blackfathom Deeps", nil, 32 },
    brd = { 230, "Blackrock Depths", nil, 60 },
    brs = { 229, "Blackrock Spire", nil, 60 },
    bwl = { 469, "Blackwing Lair", nil, 60, true },
    deadmines = { 36, "The Deadmines", nil, 26 },
    diremaul = { 429, "Dire Maul", nil, 60 },
    gnomeregan = { 90, "Gnomeregan", nil, 38 },
    -- Forever's. The instance IDs are the client's Map table (build 70009; the five after Hall of
    -- Thanes from 70888, see tools/datagen/Reference.txt). The five after Hall of Thanes have the
    -- Group Finder's levels (C_LFGList activities, seen in game 2026-11-07), which also gave Hall
    -- of Thanes' 13-20.
    hallOfThanes = { 3065, "Hall of Thanes", nil, 20 },
    drownedCity = { 2970, "The Drowned City", nil, 42 },
    kroldok = { 3039, "Krol'dok Stronghold", nil, 47 },
    alcazPrison = { 2994, "Alcaz Prison", nil, 55 },
    blackmawHold = { 2974, "Blackmaw Hold", nil, 60 },
    -- 58 in the Group Finder in game (2026-11-07); the tables say 60.
    shapersTerrace = { 3001, "The Shaper's Terrace", 58, 60 },
    ruinsOfLordaeron = { 2999, "Ruins of Lordaeron", nil, 20 },
    excavationSite = { 2998, "Excavation Site: Wetlands", nil, 31 },
    dalaran = { 2959, "City of Dalaran", nil, 33 },
    maraudon = { 349, "Maraudon", nil, 55 },
    mc = { 409, "Molten Core", nil, 60, true },
    -- Not in the finder's tables (build 70938).
    naxxramas = { 533, "Naxxramas", 60, 60, true },
    onyxia = { 249, "Onyxia's Lair", nil, 60, true },
    ragefire = { 389, "Ragefire Chasm", nil, 18 },
    razorfenDowns = { 129, "Razorfen Downs", nil, 46 },
    razorfenKraul = { 47, "Razorfen Kraul", nil, 38 },
    scarlet = { 189, "Scarlet Monastery", nil, 45 },
    scholomance = { 289, "Scholomance", nil, 60 },
    shadowfang = { 33, "Shadowfang Keep", nil, 30 },
    stockade = { 34, "The Stockade", nil, 30 },
    stratholme = { 329, "Stratholme", nil, 60 },
    sunkenTemple = { 109, "The Temple of Atal'Hakkar", nil, 60 },
    uldaman = { 70, "Uldaman", nil, 51 },
    wailing = { 43, "Wailing Caverns", nil, 24 },
    zulfarrak = { 209, "Zul'Farrak", nil, 54 },
    zulgurub = { 309, "Zul'Gurub", nil, 60, true },
}

-- Dungeon map art ---------------------------------------------------------------------------------
-- By instance key (above), a texture name for each floor in order, under Interface\WorldMap\.
-- Each floor is 12 textures, <name>1 to 12. The names are Leatrix Maps' list (1.60.28-forever,
-- read 2026-11-14), which drew its maps from the same art; the Deadmines' first tile is in the
-- client (GetFileIDFromPath gave 449591, enUS, build 70938). An instance whose first tile isn't
-- in the client counts as having no art, so a wrong name here hides a map and breaks nothing.
--
-- Wailing Caverns' art is the game's later layout, without what Forever added to it. Scholomance
-- has none. Shadowfang Keep's seventh texture comes before its sixth on purpose: that is the
-- order Leatrix Maps lists them in.
--
-- Dire Maul and Scarlet Monastery are one instance of several wings, each entered by its own
-- door: their floors are listed by wing, each with a key to ask for it by, so a wing is shown on
-- its own instead of paged through.
local function wing(key, name, ...)
    return { key = key, name = name, floors = { ... } }
end

ns.Data.dungeonArt = {
    ragefire = { "Ragefire\\Ragefire1_" },
    deadmines = { "TheDeadmines\\TheDeadmines1_", "TheDeadmines\\TheDeadmines2_" },
    wailing = { "WailingCaverns\\WailingCaverns1_" },
    shadowfang = { "ShadowfangKeep\\ShadowfangKeep1_", "ShadowfangKeep\\ShadowfangKeep2_",
        "ShadowfangKeep\\ShadowfangKeep3_", "ShadowfangKeep\\ShadowfangKeep4_",
        "ShadowfangKeep\\ShadowfangKeep5_", "ShadowfangKeep\\ShadowfangKeep7_",
        "ShadowfangKeep\\ShadowfangKeep6_" },
    stockade = { "TheStockade\\TheStockade1_" },
    blackfathom = { "BlackFathomDeeps\\BlackFathomDeeps1_", "BlackFathomDeeps\\BlackFathomDeeps2_",
        "BlackFathomDeeps\\BlackFathomDeeps3_" },
    gnomeregan = { "Gnomeregan\\Gnomeregan1_", "Gnomeregan\\Gnomeregan2_", "Gnomeregan\\Gnomeregan3_",
        "Gnomeregan\\Gnomeregan4_" },
    razorfenKraul = { "RazorfenKraul\\RazorfenKraul1_" },
    scarlet = { wings = {
        wing("graveyard", L.DUNGEONMAPS_SM_GRAVEYARD, "ScarletMonastery\\ScarletMonastery1_"),
        wing("library", L.DUNGEONMAPS_SM_LIBRARY, "ScarletMonastery\\ScarletMonastery2_"),
        wing("armory", L.DUNGEONMAPS_SM_ARMORY, "ScarletMonastery\\ScarletMonastery3_"),
        wing("cathedral", L.DUNGEONMAPS_SM_CATHEDRAL, "ScarletMonastery\\ScarletMonastery4_"),
    } },
    razorfenDowns = { "RazorfenDowns\\RazorfenDowns1_" },
    uldaman = { "Uldaman\\Uldaman1_", "Uldaman\\Uldaman2_" },
    zulfarrak = { "ZulFarrak\\ZulFarrak" },
    maraudon = { "Maraudon\\Maraudon1_", "Maraudon\\Maraudon2_" },
    sunkenTemple = { "TheTempleOfAtalHakkar\\TheTempleOfAtalHakkar1_" },
    brd = { "BlackrockDepths\\BlackrockDepths1_", "BlackrockDepths\\BlackrockDepths2_" },
    brs = { "BlackrockSpire\\BlackrockSpire1_", "BlackrockSpire\\BlackrockSpire2_",
        "BlackrockSpire\\BlackrockSpire3_", "BlackrockSpire\\BlackrockSpire4_",
        "BlackrockSpire\\BlackrockSpire5_", "BlackrockSpire\\BlackrockSpire6_" },
    mc = { "MoltenCore\\MoltenCore1_" },
    bwl = { "BlackwingLair\\BlackwingLair1_", "BlackwingLair\\BlackwingLair2_",
        "BlackwingLair\\BlackwingLair3_", "BlackwingLair\\BlackwingLair4_" },
    -- Its six floors as Leatrix Maps names them: Gordok Commons (north), Capital Gardens, Court
    -- of the Highborne, and Prison of Immol'thar (west), Warpwood Quarter and The Shrine of
    -- Eldretharr (east).
    diremaul = { wings = {
        wing("east", L.DUNGEONMAPS_DM_EAST, "DireMaul\\DireMaul5_", "DireMaul\\DireMaul6_"),
        wing("west", L.DUNGEONMAPS_DM_WEST, "DireMaul\\DireMaul2_", "DireMaul\\DireMaul3_",
            "DireMaul\\DireMaul4_"),
        wing("north", L.DUNGEONMAPS_DM_NORTH, "DireMaul\\DireMaul1_"),
    } },
    stratholme = { "Stratholme\\Stratholme1_", "Stratholme\\Stratholme2_" },
    zulgurub = { "ZulGurub\\ZulGurub" },
    onyxia = { "OnyxiasLair\\OnyxiasLair1_" },
    aq20 = { "RuinsofAhnQiraj\\RuinsofAhnQiraj" },
    aq40 = { "AhnQiraj\\AhnQiraj1_", "AhnQiraj\\AhnQiraj2_", "AhnQiraj\\AhnQiraj3_" },
    naxxramas = { "Naxxramas\\Naxxramas1_", "Naxxramas\\Naxxramas2_", "Naxxramas\\Naxxramas3_",
        "Naxxramas\\Naxxramas4_", "Naxxramas\\Naxxramas5_", "Naxxramas\\Naxxramas6_" },
}
