-- The dungeons and raids, for the modules that place or list them: each is { instance ID (the game
-- names it in the player's language), English name for when it can't, lowest level, highest
-- level, true for a raid }, by a short key. The table below is the seed; the dungeon finder's
-- list fixes its levels and adds the dungeons it doesn't have, remembered for the account (see
-- "From the dungeon finder").
local _, ns = ...

local pairs, ipairs, type, tostring, pcall = pairs, ipairs, type, tostring, pcall
local GetRealZoneText, GetTime, format = GetRealZoneText, GetTime, string.format

local L = ns.L

local Instances = {
    aq20 = { 509, "Ruins of Ahn'Qiraj", 60, 60, true },
    aq40 = { 531, "Temple of Ahn'Qiraj", 60, 60, true },
    blackfathom = { 48, "Blackfathom Deeps", 24, 32 },
    brd = { 230, "Blackrock Depths", 52, 60 },
    brs = { 229, "Blackrock Spire", 55, 60 },
    bwl = { 469, "Blackwing Lair", 60, 60, true },
    deadmines = { 36, "The Deadmines", 17, 26 },
    diremaul = { 429, "Dire Maul", 56, 60 },
    gnomeregan = { 90, "Gnomeregan", 29, 38 },
    -- Forever's. The instance IDs are the client's Map table (build 70009; the five after Hall of
    -- Thanes from 70888, see tools/datagen/Reference.txt); the lowest levels are its dungeon
    -- finder's, the highest are guides'. The five after Hall of Thanes have the Group Finder's
    -- levels (C_LFGList activities, seen in game 2026-11-07), which also gave Hall of Thanes'
    -- 13-20.
    hallOfThanes = { 3065, "Hall of Thanes", 13, 20 },
    drownedCity = { 2970, "The Drowned City", 35, 42 },
    kroldok = { 3039, "Krol'dok Stronghold", 40, 47 },
    alcazPrison = { 2994, "Alcaz Prison", 48, 55 },
    blackmawHold = { 2974, "Blackmaw Hold", 55, 60 },
    shapersTerrace = { 3001, "The Shaper's Terrace", 58, 60 },
    ruinsOfLordaeron = { 2999, "Ruins of Lordaeron", 15, 20 },
    excavationSite = { 2998, "Excavation Site: Wetlands", 26, 31 },
    dalaran = { 2959, "City of Dalaran", 28, 33 },
    maraudon = { 349, "Maraudon", 46, 55 },
    mc = { 409, "Molten Core", 60, 60, true },
    naxxramas = { 533, "Naxxramas", 60, 60, true },
    onyxia = { 249, "Onyxia's Lair", 60, 60, true },
    ragefire = { 389, "Ragefire Chasm", 13, 18 },
    razorfenDowns = { 129, "Razorfen Downs", 37, 46 },
    razorfenKraul = { 47, "Razorfen Kraul", 29, 38 },
    scarlet = { 189, "Scarlet Monastery", 34, 45 },
    scholomance = { 289, "Scholomance", 58, 60 },
    shadowfang = { 33, "Shadowfang Keep", 22, 30 },
    stockade = { 34, "The Stockade", 22, 30 },
    stratholme = { 329, "Stratholme", 58, 60 },
    sunkenTemple = { 109, "The Temple of Atal'Hakkar", 50, 60 },
    uldaman = { 70, "Uldaman", 41, 51 },
    wailing = { 43, "Wailing Caverns", 17, 24 },
    zulfarrak = { 209, "Zul'Farrak", 44, 54 },
    zulgurub = { 309, "Zul'Gurub", 60, 60, true },
}

ns.Instances = {
    byKey = Instances,
}

-- From the dungeon finder ----------------------------------------------------------------------
-- The finder's dungeons (GetLFDChoiceOrder, GetLFGDungeonInfo) give each one's instance ID, its
-- name in the player's language, and its levels. What differs from the seed is learned for the
-- account (ns.GameData, "instances", by instance ID): a seed entry takes the learned levels in
-- place, so modules holding it see them, and a dungeon the seed doesn't have gets an entry of its
-- own under "lfg<ID>" (or "lfgd<finder ID>" without an instance ID). Probe: what the finder lists
-- on Forever is Unverified; see docs/forever-api.md.

local seed = {} -- instance ID -> { low = n, high = n }, from the table above
local byID = {} -- instance ID -> entry of `byKey`
for _, instance in pairs(Instances) do
    seed[instance[1]] = { low = instance[3], high = instance[4] }
    byID[instance[1]] = instance
end

local learned = ns.GameData.New("instances", seed, { label = "Dungeons" })

local TYPE_DUNGEON = 1 -- GetLFGDungeonInfo's typeID for one dungeon (6 is a random one)
local SUBTYPE_DUNGEON, SUBTYPE_RAID = 1, 3
local MAX_SPAN = 15 -- the widest level range taken from the finder; wider is a whole bracket
local SPAN = 5 -- the range a new dungeon gets when the finder's is a bracket (Forever's are 5)
local RETRY = 30 -- seconds before asking the finder again while it lists nothing

local byName -- instances by lower-case name, once asked

-- Puts what was learned into `byKey`: levels onto seed entries, new entries for the rest.
local function apply()
    for id, value in learned:Pairs() do
        local instance = byID[id]
        if not instance and value.name then
            instance = { type(id) == "number" and id or nil, value.name }
            Instances["lfg" .. tostring(id)] = instance
            byID[id] = instance
            byName = nil
        end
        if instance and value.low and value.high then
            instance[3], instance[4] = value.low, value.high
            instance[5] = instance[5] or value.raid or nil
        end
    end
end

-- A level range from the finder's numbers: its lowest, and the recommended or highest level when
-- that's a dungeon's range. Nil when both are a whole bracket (a dungeon that scales), which says
-- nothing about the dungeon's own levels.
local function range(minLevel, maxLevel, maxRecLevel)
    for _, high in ipairs({ maxRecLevel, maxLevel }) do
        if type(high) == "number" and high >= minLevel and high - minLevel <= MAX_SPAN then
            return minLevel, high
        end
    end
end

-- Learns from the finder's list. False when it lists nothing yet (early in the session).
local function fromFinder()
    if not (GetLFDChoiceOrder and GetLFGDungeonInfo) then
        return true
    end
    local ok, list = pcall(GetLFDChoiceOrder)
    if not ok or type(list) ~= "table" or not list[1] then
        return false
    end
    for _, dungeonID in ipairs(list) do
        -- Negative IDs are headers.
        if type(dungeonID) == "number" and dungeonID > 0 then
            -- name, typeID, subtypeID, minLevel, maxLevel, recLevel, minRecLevel, maxRecLevel,
            -- expansionLevel, ... and the instance ID 22nd (Mainline's order).
            local info = { GetLFGDungeonInfo(dungeonID) }
            local name, typeID, subtypeID, minLevel, maxLevel = info[1], info[2], info[3], info[4], info[5]
            local maxRecLevel, expansion, mapID = info[8], info[9], info[22]
            if ns.IsText(name, true) and typeID == TYPE_DUNGEON
                and (subtypeID == SUBTYPE_DUNGEON or subtypeID == SUBTYPE_RAID)
                and (expansion == nil or expansion == 0) and type(minLevel) == "number" then
                local id = type(mapID) == "number" and mapID > 0 and mapID or nil
                if not id then
                    local instance = ns.Instances.ByName(name)
                    id = instance and instance[1] or ("d" .. dungeonID)
                end
                local low, high = range(minLevel, maxLevel, maxRecLevel)
                if not seed[id] then
                    learned:Learn(id, { name = name, low = minLevel, high = high or minLevel + SPAN,
                        raid = subtypeID == SUBTYPE_RAID or nil })
                elseif low then
                    learned:Learn(id, { low = low, high = high })
                end
            end
        end
    end
    return true
end

local applied, done, tried -- learned values put in; the finder read; when it was last asked

-- Brings `byKey` up to date: once the saved variables are in, then from the finder once it lists
-- something, asking again at most every RETRY seconds until it does.
local function refresh()
    if done or not ns.db then
        return
    end
    if not applied then
        applied = true
        apply()
    end
    local now = GetTime and GetTime() or 0
    if tried and now - tried < RETRY then
        return
    end
    tried = now
    done = fromFinder()
    if done then
        apply()
    end
end

---Brings the list up to date with what's saved and what the dungeon finder lists, which can add
---dungeons to `byKey`. Call it before walking `byKey`, since adding to a table mid-walk breaks the
---walk.
ns.Instances.Refresh = refresh

---Blizzard's dungeon or raid entrance icon for an instance, as text to put before its name.
---@param instance table an entry of `byKey`, or one shaped like it
---@param size number pixels
---@return string
function ns.Instances.Icon(instance, size)
    return format("|A:%s:%d:%d|a", instance[5] and "Raid" or "Dungeon", size, size)
end

---An instance's name in the player's language from the game, or the English one.
---@param instance table an entry of `byKey`, or one shaped like it
---@return string
function ns.Instances.Name(instance)
    refresh()
    local name = instance[1] and GetRealZoneText and GetRealZoneText(instance[1])
    if not name or name == "" then
        name = instance[2]
    end
    return name
end

---An instance's level range as text, colored against the player's level like a quest's.
---@param instance table an entry of `byKey`, or one shaped like it
---@param compact boolean? "52-60" instead of "Level 52-60"
---@return string
function ns.Instances.Levels(instance, compact)
    refresh()
    local low, high = instance[3], instance[4]
    local text
    if compact then
        text = low == high and tostring(low) or format(L.INSTANCES_RANGE, low, high)
    else
        text = low == high and format(L.INSTANCES_LEVEL, low) or format(L.INSTANCES_LEVELS, low, high)
    end
    local color = ns.Colors.LevelRange(low, high)
    if not color then
        return text
    end
    return ns.Colors.Text(color, text)
end

ns.Instances.ICON_SIZE = 14 -- pixels, the icon before an instance in a tooltip or panel

---One instance as a row: its icon, its name, and its level range, the same in every tooltip and
---panel that lists instances. The name's spaces are no-break spaces, so a row that wraps breaks
---between the parts, never inside the name.
---@param instance table an entry of `byKey`, or one shaped like it
---@param name string? shown instead of the instance's own name (for one of its entrances)
---@return string
function ns.Instances.Line(instance, name)
    return format("%s %s  %s", ns.Instances.Icon(instance, ns.Instances.ICON_SIZE),
        ns.MapTooltip.NoBreak(name or ns.Instances.Name(instance)), ns.Instances.Levels(instance, true))
end

---The instance a name belongs to (in the player's language or English), for telling Blizzard's
---own icon for it from ours.
---@param name string?
---@return table? instance an entry of `byKey`
function ns.Instances.ByName(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end
    refresh()
    if not byName then
        byName = {}
        for _, instance in pairs(Instances) do
            byName[ns.Instances.Name(instance):lower()] = instance
            byName[instance[2]:lower()] = instance
        end
    end
    return byName[name:lower()]
end
