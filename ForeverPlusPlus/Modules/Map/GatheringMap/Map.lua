-- Gathering Map's icons on the world map: a layer of Lib/MapPins.lua with an icon for each node on
-- the zone map shown, and on a continent map the nodes of its zones too while World Map Continents
-- is on.
local _, ns = ...

local pairs = pairs
local C_Map = C_Map

local module = ns.modules.GatheringMap
local internal = module.internal
local MapPins = ns.MapPins

local MAP_PIXELS = 14 -- an icon's size on screen at 100%
local CONTINENT = 0.75 -- smaller on a continent map, where many zones' nodes crowd together

local continents = {} -- zone map ID -> its continent's, or false: the map tree doesn't change

local function continentOf(zone)
    local found = continents[zone]
    if found == nil then
        found = false
        for id, info in ns.WorldMap.Up(zone) do
            if ns.WorldMap.IsContinent(info) then
                found = id
            end
        end
        continents[zone] = found
    end
    return found
end

-- The tables pins are given, kept from one draw to the next: pin i shows infos[i].
local infos = {}

local function infoFor(i, node, size)
    local info = infos[i]
    if not info then
        info = {}
        infos[i] = info
    end
    internal.Look(node, info)
    info.size = size
    info.title = node.name
    info.lines = internal.TooltipLines(node)
    return info
end

local function fill(mapID, add)
    local db = module.db
    local shown = internal.Shown
    local count = 0
    local own = db.nodes[mapID]
    if own then
        local size = MAP_PIXELS * db.mapSize / 100
        for _, node in pairs(own) do
            if shown(node) then
                count = count + 1
                add(node.x, node.y, infoFor(count, node, size))
            end
        end
    end
    if not db.mapContinents then
        return
    end
    local info = C_Map.GetMapInfo(mapID)
    if not ns.WorldMap.IsContinent(info) then
        return
    end
    local size = MAP_PIXELS * db.mapSize / 100 * CONTINENT
    for zone, list in pairs(db.nodes) do
        if zone ~= mapID and continentOf(zone) == mapID then
            for _, node in pairs(list) do
                if shown(node) then
                    local x, y = MapPins.Translate(zone, mapID, node.x, node.y)
                    if x then
                        count = count + 1
                        add(x, y, infoFor(count, node, size))
                    end
                end
            end
        end
    end
end

local layer = MapPins.New(fill)

local function apply()
    if module.enabled and module.db.worldMap then
        layer:Enable()
        layer:Refresh()
    else
        layer:Disable()
    end
end

function internal.EnableMap()
    apply()
end

function internal.DisableMap()
    layer:Disable()
end

-- A new node, or an option: draw again if the map is open on it.
internal.OnChanged(function()
    if module.enabled then
        apply()
    end
end)
