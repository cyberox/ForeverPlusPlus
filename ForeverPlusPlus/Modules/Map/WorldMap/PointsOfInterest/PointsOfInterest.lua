-- Points of Interest, a part of World Map: icons on the world map for dungeons, raids, capital
-- cities, flight masters, boats, zeppelins, and spirit healers, each with a tooltip saying what and
-- where it is. Every kind has its own checkbox, icon size, and whether it also shows on the
-- continent and world maps, not just zone maps. Travel points of the other faction are off unless
-- asked for. Where the points are is in Data.lua, except Skyborne ley lines, saved as they're
-- found. This file has the part, its options, and drawing the points; Flights.lua the flight
-- points flight masters show, LeyLines.lua the ley lines, and BlizzardIcons.lua hiding the
-- game's own icons where ours show.
local _, ns = ...

local ipairs, pairs, format, rawget, unpack, abs = ipairs, pairs, string.format, rawget, unpack,
    math.abs
local select, floor = select, math.floor
local C_Map, C_EncounterJournal = C_Map, C_EncounterJournal

local L = ns.L

local module = ns.modules.WorldMap:NewPart({
    key = "pointsOfInterest", name = L.POI_TITLE, description = L.POI_DESC, section = L.POI_TITLE,
}, {
    -- For each kind: shown, its size in percent of normal, and shown on continent maps too.
    dungeons = true,
    dungeonSize = 90,
    dungeonsWorld = true,
    raids = true,
    raidSize = 80,
    raidsWorld = true,
    capitals = "ours", -- "ours" (and Blizzard's city icons hidden), "blizzard", or "off"
    capitalSize = 50,
    capitalsWorld = true,
    flightMasters = true,
    flightSize = 80,
    flightMastersWorld = false,
    ships = true,
    shipSize = 80,
    shipsWorld = false,
    zeppelins = true,
    zeppelinSize = 80,
    zeppelinsWorld = false,
    spiritHealers = true,
    spiritSize = 70,
    spiritHealersWorld = false,
    otherFaction = false, -- also the other faction's flight masters, boats, and zeppelins
    leyLines = "skyborne", -- who sees ley lines: "skyborne" (their own kind), "everyone", or "off"
    leyLineSize = 80,
    leyLinesWorld = false,
    leyLineIcon = "portal", -- "portal" (the minimap's blue swirl) or "orb" (the purple ball)
    chat = true, -- say so in chat when a ley line is saved
    -- Flight points this character has seen learned at a flight master, by node ID. Data, not a
    -- setting, saved per character.
    learnedNodes = {},
    -- Ley lines and elemental convergences found, by map ID: { kind, x, y } in percent. For the
    -- whole account, so every character sees what one found. Data, not a setting.
    leyLineSpots = {},
})
ns.modules.WorldMap.perCharacter = { learnedNodes = true }

-- Shared with Data.lua: `points` (by map ID), `instances` (by key), and `cities` (by map ID). And
-- with this part's other files: the part as `module`, and the helpers they call each other's.
local internal = { module = module }
ns.modules.WorldMap.internal.pointsOfInterest = internal

-- A checkbox for a kind with the slider for its size in the same row, and under it whether it
-- shows on continents.
local function kind(key, sizeKey, name, description)
    return { key = key, name = name, description = description, slider = sizeKey },
        {
            key = sizeKey, name = L.POI_SIZE, description = L.POI_SIZE_DESC, requires = key,
            min = 50, max = 200, step = 10, format = "%d%%",
        },
        { key = key .. "World", name = L.POI_WORLD, description = L.POI_WORLD_DESC, requires = key }
end

-- Each row's options go under its `section`, a smaller header in the part's section in Settings.
local options = {}
local INSTANCES, TRAVEL, OTHER = L.POI_SECTION_INSTANCES, L.POI_SECTION_TRAVEL, L.POI_SECTION_OTHER
local chat = ns.ChatOption(L.POI_CHAT_DESC)
chat.requires = "leyLines"
for _, rows in ipairs({
    { section = INSTANCES, kind("dungeons", "dungeonSize", L.POI_DUNGEONS, L.POI_DUNGEONS_DESC) },
    { section = INSTANCES, kind("raids", "raidSize", L.POI_RAIDS, L.POI_RAIDS_DESC) },
    -- Ours, Blizzard's, or none: ours hide Blizzard's city icons, so there's no checkbox.
    { section = TRAVEL, {
        key = "capitals", name = L.POI_CAPITALS, description = L.POI_CAPITALS_DESC,
        choices = {
            { "ours", L.POI_CAPITALS_OURS },
            { "blizzard", L.POI_CAPITALS_BLIZZARD },
            { "off", L.POI_CAPITALS_OFF },
        },
    }, select(2, kind("capitals", "capitalSize")) },
    { section = TRAVEL, kind("flightMasters", "flightSize", L.POI_FLIGHT, L.POI_FLIGHT_DESC) },
    { section = TRAVEL, kind("ships", "shipSize", L.POI_SHIPS, L.POI_SHIPS_DESC) },
    { section = TRAVEL, kind("zeppelins", "zeppelinSize", L.POI_ZEPPELINS, L.POI_ZEPPELINS_DESC) },
    -- After the travel points it's about.
    { section = TRAVEL,
        { key = "otherFaction", name = L.POI_OTHER_FACTION, description = L.POI_OTHER_FACTION_DESC } },
    { section = OTHER, kind("spiritHealers", "spiritSize", L.POI_SPIRIT, L.POI_SPIRIT_DESC) },
    -- Who sees them, so like Capital Cities there's no checkbox.
    { section = OTHER, {
        key = "leyLines", name = L.POI_LEYLINES, description = L.POI_LEYLINES_DESC, added = "0.8.0",
        choices = {
            { "skyborne", L.POI_LEYLINES_SKYBORNE },
            { "everyone", L.POI_LEYLINES_EVERYONE },
            { "off", L.POI_LEYLINES_OFF },
        },
    }, select(2, kind("leyLines", "leyLineSize")) },
    { section = OTHER, {
        key = "leyLineIcon", name = L.POI_LEYLINE_ICON, description = L.POI_LEYLINE_ICON_DESC,
        requires = "leyLines", added = "0.9.0",
        choices = {
            { "portal", L.POI_LEYLINE_ICON_PORTAL },
            { "orb", L.POI_LEYLINE_ICON_ORB },
        },
    } },
    -- Said only when a ley line is saved, so under them.
    { section = OTHER, chat },
}) do
    for _, option in ipairs(rows) do
        option.section = rows.section
        options[#options + 1] = option
    end
end
module:AddOptions(options)

-- Each kind of point: the checkbox, size, and continent settings for it, its normal size in
-- pixels, and its icon. The boat, zeppelin, graveyard, and town icons are in Retail's atlas list,
-- but not confirmed on Forever, so the first the client has is chosen the first time the map
-- draws; the plain colored balls after them are ones Leatrix Maps uses on Forever.
local KINDS = {
    dungeon = { show = "dungeons", size = "dungeonSize", pixels = 24, atlas = "Dungeon" },
    raid = { show = "raids", size = "raidSize", pixels = 24, atlas = "Raid" },
    capital = { show = "capitals", size = "capitalSize", pixels = 28,
        atlases = { "poi-town", "Vehicle-TempleofKotmogu-PurpleBall" } },
    flight = { show = "flightMasters", size = "flightSize", pixels = 18 },
    ship = { show = "ships", size = "shipSize", pixels = 22,
        atlases = { "FlightMasterFerry", "Vehicle-TempleofKotmogu-CyanBall" } },
    zeppelin = { show = "zeppelins", size = "zeppelinSize", pixels = 24,
        atlases = { "Vehicle-Air-Horde", "Vehicle-TempleofKotmogu-CyanBall" } },
    -- A glowing spirit, so it isn't mistaken for the corpse marker; the tombstone if it's missing.
    spirit = { show = "spiritHealers", size = "spiritSize", pixels = 22,
        atlases = { "poi-soulspiritghost", "poi-graveyard-neutral", "Vehicle-TempleofKotmogu-GreenBall" } },
    -- Skyborne spots: ley lines purple, convergences orange. Both are Kotmogu balls like the cyan
    -- and green ones, but Unverified on Forever. With Ley Line Icon on Portal (`portal`), a ley
    -- line is the blue swirl the minimap shows for one, MagePortalAlliance in the minimap's object
    -- icons (UiTextureAtlasMember, wago.tools, build 70338; Cameron picked it, 2026-10-14). The
    -- same on either side: the minimap's icon is the ley line's own, not the player's faction's.
    leyline = { show = "leyLines", size = "leyLineSize", pixels = 18,
        atlases = { "Vehicle-TempleofKotmogu-PurpleBall", "Vehicle-TempleofKotmogu-CyanBall" },
        portal = { pixels = 20,
            atlases = { "MagePortalAlliance", "Vehicle-TempleofKotmogu-PurpleBall" } } },
    convergence = { show = "leyLines", size = "leyLineSize", pixels = 18,
        atlases = { "Vehicle-TempleofKotmogu-OrangeBall", "Vehicle-TempleofKotmogu-PurpleBall",
            "Vehicle-TempleofKotmogu-CyanBall" } },
}
for _, kindInfo in pairs(KINDS) do
    kindInfo.world = kindInfo.show .. "World" -- the kind's On Continent Maps checkbox
end
internal.KINDS = KINDS

-- A flight master not learned yet (or not known to be): the flight point icon in its faction's
-- color, which on Forever is bronze.
local TAXI = { A = "TaxiNode_Alliance", H = "TaxiNode_Horde", N = "TaxiNode_Neutral" }

-- A learned one: the white flight master icon the minimap shows, or the faction's icon without
-- it. In Retail's atlas list; Unverified on Forever.
local learnedIcon
local function learnedAtlas(faction)
    if learnedIcon == nil then
        learnedIcon = ns.Frames.HasAtlas("FlightMaster") and "FlightMaster" or false
    end
    return learnedIcon or TAXI[faction]
end

local function atlasOf(kindInfo)
    if not kindInfo.atlas then
        kindInfo.atlas = ns.MapPins.Atlas(unpack(kindInfo.atlases))
    end
    return kindInfo.atlas
end
internal.atlasOf = atlasOf

-- A place name from Data.lua, in the player's language when a locale file translates it
-- (L["Booty Bay"] = ...). Place names aren't in Locales/enUS/: the English is the name itself.
local function place(name)
    return rawget(L, name) or name
end

-- A zone's name in the player's language, from the game.
local function zoneName(mapID)
    return ns.WorldMap.MapName(mapID, "")
end
internal.zoneName = zoneName

-- An instance's name in the player's language, and which entrance it is.
local function instanceName(instance)
    local name = ns.Instances.Name(instance)
    if instance.part then
        name = format(L.POI_PART, name, instance.part)
    end
    return name
end

local MapTooltip = ns.MapTooltip

-- The lines of a tooltip from the ones given, leaving out the nils.
local function linesOf(...)
    local lines = {}
    for i = 1, select("#", ...) do
        local line = select(i, ...)
        if line then
            lines[#lines + 1] = line
        end
    end
    return lines
end
internal.linesOf = linesOf

-- The tooltip of a dungeon or raid: one instance (its kind, then its level range colored against
-- the player's), or a place with several (Blackrock Mountain), a row each. Also the rows alone,
-- for a city's tooltip that takes them in.
local function instanceTooltip(kindName, key)
    local instance = internal.instances[key]
    if not instance.parts then
        local row = MapTooltip.Detail(ns.Instances.Line(instance, instanceName(instance)))
        return instanceName(instance), { kindName, MapTooltip.Detail(ns.Instances.Levels(instance)) },
            { row }
    end
    local rows = {}
    for _, partKey in ipairs(instance.parts) do
        local part = internal.instances[partKey]
        rows[#rows + 1] = MapTooltip.Detail(ns.Instances.Line(part, instanceName(part)))
    end
    return place(instance.name), rows, rows
end

-- Whether a travel point of this faction shows for the player.
local function forPlayer(faction)
    return faction == "N" or faction == ns.WorldMap.PlayerSide() or module.db.otherFaction
end

-- How close (in percent of the map) a point the game knows is to one in Data.lua for the two to
-- be the same.
local NEAR = 3
internal.NEAR = NEAR

-- Whether a kind shows, on a continent map (`world`) or a zone map.
local function shows(kindInfo, world)
    local db = module.db
    local on = db[kindInfo.show]
    return (on == true or on == "ours") and (not world or db[kindInfo.world])
end
internal.shows = shows

-- The pin for one point of Data.lua on the map `mapID` it's listed for, or nil when its settings
-- hide it. `world` when it's being drawn on a continent map.
local function pinFor(point, mapID, world)
    local kindName = point[1]
    local kindInfo = KINDS[kindName]
    local db = module.db
    -- A place with dungeons and raids (Blackrock Mountain) shows with either.
    local mixed = kindName == "dungeon" and internal.instances[point[4]].raids
    if not (shows(kindInfo, world) or (mixed and shows(KINDS.raid, world))) then
        return nil
    end
    local info = { size = kindInfo.pixels * db[kindInfo.size] / 100 }
    if kindName == "capital" then
        local city = internal.cities[point[4]]
        info.atlas = atlasOf(kindInfo)
        info.title = zoneName(point[4])
        info.lines = linesOf(L.POI_CAPITAL, MapTooltip.Side(city.faction))
    elseif kindName == "dungeon" or kindName == "raid" then
        info.atlas = kindInfo.atlas
        info.title, info.lines, info.rows = instanceTooltip(
            kindName == "raid" and L.POI_RAID or L.POI_DUNGEON, point[4])
    elseif kindName == "flight" then
        if not forPlayer(point[4]) then
            return nil
        end
        info.title = place(point[5])
        info.lines = linesOf(L.POI_FLIGHT_MASTER, MapTooltip.Side(point[4]),
            MapTooltip.Detail(zoneName(mapID)))
        -- Learned ones look like the minimap's; the rest keep the bronze flight point icon.
        local state = internal.learned(point)
        if state then
            info.atlas = learnedAtlas(point[4])
        else
            info.atlas = TAXI[point[4]]
            if state == false then
                info.lines[#info.lines + 1] = MapTooltip.Note(L.POI_FLIGHT_UNLEARNED)
            end
        end
    elseif kindName == "ship" or kindName == "zeppelin" then
        if not forPlayer(point[4]) then
            return nil
        end
        info.atlas = atlasOf(kindInfo)
        info.title = format(kindName == "ship" and L.POI_SHIP_TO or L.POI_ZEPPELIN_TO,
            place(point[5]))
        info.lines = linesOf(MapTooltip.Side(point[4]), MapTooltip.Detail(zoneName(point[6] or mapID)),
            point.via and MapTooltip.Note(format(L.POI_VIA, place(point.via))))
    else
        info.atlas = atlasOf(kindInfo)
        info.title = L.POI_SPIRIT_HEALER
    end
    return info
end

local function listedNear(listed, x, y)
    for _, point in ipairs(listed) do
        if abs(point[2] - x) < NEAR and abs(point[3] - y) < NEAR then
            return true
        end
    end
    return false
end

local function isInstance(point)
    return point[1] == "dungeon" or point[1] == "raid"
end

-- The instances Data.lua places somewhere, by their entry in Lib/Instances.lua, once asked. The
-- rest (Forever dungeons whose entrance isn't known) are left to the game's own icons.
local placed

local function placedByUs(name)
    if not placed then
        placed = {}
        for _, points in pairs(internal.points) do
            for _, point in ipairs(points) do
                if isInstance(point) then
                    local instance = internal.instances[point[4]]
                    for _, key in ipairs(instance.parts or { point[4] }) do
                        local found = ns.Instances.ByName(internal.instances[key][2])
                        if found then
                            placed[found] = true
                        end
                    end
                end
            end
        end
    end
    local instance = ns.Instances.ByName(name)
    return instance ~= nil and placed[instance] == true, instance
end
internal.placedByUs = placedByUs

-- Dungeon and raid entrances the game itself has for the map (Blizzard's own entrance list, which
-- its map hides behind a CVar), for ones Data.lua doesn't place, such as Forever's new dungeons.
-- Probe: which entrances Forever lists there is Unverified.
local function gameEntrances(mapID, listed, add)
    if not (C_EncounterJournal and C_EncounterJournal.GetDungeonEntrancesForMap) then
        return
    end
    local db = module.db
    for _, entrance in ipairs(C_EncounterJournal.GetDungeonEntrancesForMap(mapID) or {}) do
        local x, y = entrance.position:GetXY()
        local raid = (entrance.atlasName or ""):lower():find("raid") ~= nil
        local kindInfo = KINDS[raid and "raid" or "dungeon"]
        -- Not one Data.lua has, by place or by name: the Ruins of Lordaeron's entrance is listed
        -- on the Undercity's map, so the game's, on Tirisfal Glades, would be a second icon.
        local ours, instance = placedByUs(entrance.name)
        if db[kindInfo.show] and not listedNear(listed, x * 100, y * 100) and not ours then
            local lines = { raid and L.POI_RAID or L.POI_DUNGEON }
            if instance then
                lines[2] = MapTooltip.Detail(ns.Instances.Levels(instance))
            elseif entrance.description and entrance.description ~= "" then
                lines[2] = MapTooltip.Detail(entrance.description)
            end
            add(x, y, {
                atlas = entrance.atlasName ~= "" and entrance.atlasName or kindInfo.atlas,
                size = kindInfo.pixels * db[kindInfo.size] / 100,
                title = entrance.name,
                lines = lines,
            })
        end
    end
end

-- A point on one map (0 to 1) as a point on another that shows it: a city on its zone, or a zone
-- or city on a continent. For a city the game can't place, the place Data.lua gives it on its
-- zone.
local function translate(fromMap, toMap, x, y)
    local tx, ty = ns.MapPins.Translate(fromMap, toMap, x, y)
    local city = internal.cities[fromMap]
    if tx or not (city and city.rect) then
        return tx, ty
    end
    local rect = city.rect
    x, y = rect[1] + (rect[2] - rect[1]) * x, rect[3] + (rect[4] - rect[3]) * y
    if city.zone == toMap then
        return x, y
    end
    return ns.MapPins.Translate(city.zone, toMap, x, y)
end
internal.translate = translate

-- A point on a map (0 to 1) in percent, to a tenth, as saved flight points and ley lines are.
function internal.percent(value)
    return floor(value * 1000 + 0.5) / 10
end

-- A capital's icon, in the middle of its own map.
local function capitalPoint(cityMap)
    return { "capital", 50, 50, cityMap }
end

-- A point listed for `fromMap`, drawn on `mapID`.
local function addFrom(fromMap, mapID, point, world, add)
    local info = pinFor(point, fromMap, world)
    if not info then
        return
    end
    local x, y = translate(fromMap, mapID, point[2] / 100, point[3] / 100)
    if x then
        add(x, y, info)
    end
end

-- How close (in percent of the map) a city's dungeon is to the city's own icon for the dungeon to
-- go in the city's tooltip instead of on top of it (the Hall of Thanes under Ironforge).
local MERGE = 2

-- A capital's icon and its dungeons, on a map outside the city.
local function addCity(cityMap, mapID, world, add, listed)
    local capital = pinFor(capitalPoint(cityMap), cityMap, world)
    local cx, cy
    if capital then
        cx, cy = translate(cityMap, mapID, 0.5, 0.5)
    end
    for _, point in ipairs(internal.points[cityMap] or {}) do
        local info = isInstance(point) and pinFor(point, cityMap, world)
        local x, y
        if info then
            x, y = translate(cityMap, mapID, point[2] / 100, point[3] / 100)
        end
        if x then
            if listed then
                listed[#listed + 1] = { point[1], x * 100, y * 100 }
            end
            if cx and abs(x - cx) * 100 < MERGE and abs(y - cy) * 100 < MERGE then
                for _, row in ipairs(info.rows) do
                    capital.lines[#capital.lines + 1] = row
                end
            else
                add(x, y, info)
            end
        end
    end
    if cx then
        add(cx, cy, capital)
    end
end

-- A zone map: its own points, and the capitals in it with their dungeons.
local function fillZone(mapID, add)
    internal.readTaxiNodes(mapID)
    local listed = {} -- this map's dungeons and raids in Data.lua, shown or not
    for _, point in ipairs(internal.pointsOf(mapID)) do
        if isInstance(point) then
            listed[#listed + 1] = point
        end
        local info = pinFor(point, mapID)
        if info then
            add(point[2] / 100, point[3] / 100, info)
        end
    end
    for cityMap, city in pairs(internal.cities) do
        if city.zone == mapID then
            addCity(cityMap, mapID, false, add, listed)
        end
    end
    gameEntrances(mapID, listed, add)
    internal.addSpots(mapID, false, add)
end

-- A continent or world map: every kind whose On Continent Maps is on, from every zone and city
-- the game can place on it.
local function fillContinent(mapID, add)
    local flights = shows(KINDS.flight, true)
    for fromMap, points in pairs(internal.allPoints()) do
        if flights then
            internal.readTaxiNodes(fromMap)
        end
        for _, point in ipairs(points) do
            -- A city's dungeons come with the city, below.
            if not (internal.cities[fromMap] and isInstance(point)) then
                addFrom(fromMap, mapID, point, true, add)
            end
        end
    end
    for cityMap in pairs(internal.cities) do
        addCity(cityMap, mapID, true, add)
    end
    internal.addSpots(mapID, true, add)
end

local function isContinent(mapID)
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    return ns.WorldMap.IsContinent(info)
end
internal.isContinent = isContinent

local function fill(mapID, add)
    if isContinent(mapID) then
        fillContinent(mapID, add)
    else
        fillZone(mapID, add)
    end
end

local layer

internal.refresh = function()
    layer:Refresh()
end

-- The player's casts, while ley lines are shown and the character is Skyborne, the only ones who
-- can find them. Not `OnWhile`, which can't listen to one unit; this does the same from OnEnable
-- and OnOptionChanged.
local CASTER = { "player" }

local function listenForLeyLines(self)
    if self.db.leyLines ~= "off" and internal.ownKind(true) then
        self:OnUnit("UNIT_SPELLCAST_SUCCEEDED", CASTER, internal.onCast)
    else
        self:Off("UNIT_SPELLCAST_SUCCEEDED", internal.onCast)
    end
end

function module:OnEnable()
    layer = layer or ns.MapPins.New(fill)
    layer:Enable()
    ns.MapPins.OnAcquire(internal.onAcquire)
    ns.MapPins.RefreshMap() -- hide Blizzard's city icons already on it
    -- A flight master's map: which flight points are learned, and new ones learned there.
    self:On("TAXIMAP_OPENED", function()
        internal.rememberLearned()
        internal.learnFlights()
    end)
    self:On("TAXIMAP_CLOSED", function() layer:Refresh() end)
    listenForLeyLines(self)
end

function module:OnDisable()
    layer:Disable()
    ns.MapPins.RefreshMap() -- Blizzard's city icons back
end

function module:OnOptionChanged(key)
    if key == "leyLines" then
        listenForLeyLines(self)
    end
    if key:find("^capital") or key:find("^dungeon") or key:find("^raid") then
        ns.MapPins.RefreshMap() -- ours and Blizzard's, both redrawn
    else
        layer:Refresh()
    end
end
