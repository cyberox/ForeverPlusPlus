-- The world map, which comes with a load-on-demand Blizzard addon: whether it has loaded, code to
-- run once it has, and the parts of it more than one module finds. Nothing is listened to until a
-- module waits for it.
local _, ns = ...

local ipairs, pairs, tonumber = ipairs, pairs, tonumber
local sqrt, atan2, pi = math.sqrt, math.atan2, math.pi
local UnitFactionGroup, CreateFromMixins = UnitFactionGroup, CreateFromMixins
local FACTION_ALLIANCE, FACTION_HORDE = FACTION_ALLIANCE, FACTION_HORDE

local WorldMap = {}
ns.WorldMap = WorldMap

local ADDON = "Blizzard_WorldMap"

---The world map, once its addon has loaded, or nil. Probe: it's loaded at login on Mainline, but
---it's a load-on-demand Blizzard addon, so don't count on it.
---@return table?
function WorldMap.Get()
    return ns.AddOns.IsLoaded(ADDON) and WorldMapFrame or nil
end

local waiting = {} -- fn -> the function waiting on the addon for it

---Calls `fn(map)` now if the world map has loaded, or else once it does. Waiting with the same
---`fn` again doesn't call it twice; `WorldMap.Cancel(fn)` stops the wait, for a module turned off
---before the map loaded.
---@param fn fun(map: table)
function WorldMap.WhenLoaded(fn)
    local map = WorldMap.Get()
    if map then
        fn(map)
        return
    end
    waiting[fn] = waiting[fn] or function()
        waiting[fn] = nil
        if WorldMapFrame then
            fn(WorldMapFrame)
        end
    end
    ns.AddOns.WhenLoaded(ADDON, waiting[fn])
end

---Stops waiting to call `fn` when the world map loads.
---@param fn function
function WorldMap.Cancel(fn)
    if waiting[fn] then
        ns.AddOns.Cancel(ADDON, waiting[fn])
        waiting[fn] = nil
    end
end


---A data provider for a map to draw our own things on: what the map calls as it changes maps,
---zooms or resizes. `handlers` may have RemoveAllData, RefreshAllData, OnCanvasScaleChanged,
---OnCanvasSizeChanged and OnGlobalAlphaChanged, each called with the provider. Add it with
---`map:AddDataProvider`. Only call this once the map has loaded, since the mixin comes with it.
---@param handlers table<string, fun(provider: table)>
---@return table provider
function WorldMap.NewProvider(handlers)
    local provider = CreateFromMixins(MapCanvasDataProviderMixin)
    for name, fn in pairs(handlers) do
        provider[name] = fn
    end
    return provider
end

---Whether a map (`C_Map.GetMapInfo` of it) is a continent or the world map, as against a zone.
---@param info table?
---@param cosmic? boolean count the cosmic map (Azeroth and beyond) too
---@return boolean
function WorldMap.IsContinent(info, cosmic)
    local types = Enum and Enum.UIMapType
    if not (info and types) then
        return false
    end
    local kind = info.mapType
    return kind == types.Continent or kind == types.World or (cosmic and kind == types.Cosmic) or false
end

-- The map tree --------------------------------------------------------------------------------

---Walks up the map tree from `mapID` to its continent: `for mapID, info in WorldMap.Up(id)`
---gives each map and its `C_Map.GetMapInfo`, the continent (or the world, or a map without info)
---last.
---@param mapID number?
---@return function iterator
function WorldMap.Up(mapID)
    local continent = Enum and Enum.UIMapType and Enum.UIMapType.Continent or 2
    local done = false
    return function()
        if done or not mapID or mapID == 0 then
            return nil
        end
        local current = mapID
        local info = C_Map.GetMapInfo(current)
        if not info or (info.mapType and info.mapType <= continent) then
            done = true
        else
            mapID = info.parentMapID
        end
        return current, info
    end
end

---The zone `mapID` is in: the map itself when it's a zone, else the first zone above it (for a
---cave or a city's district), or nil above zones.
---@param mapID number?
---@return number?
function WorldMap.Zone(mapID)
    local zone = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
    for id, info in WorldMap.Up(mapID) do
        if info and info.mapType == zone then
            return id
        end
    end
end

---The top map above `mapID` (the world, or Azeroth), under which every zone is.
---@param mapID number?
---@return number?
function WorldMap.Root(mapID)
    local info = mapID and C_Map.GetMapInfo(mapID)
    while info and info.parentMapID and info.parentMapID ~= 0 do
        local parent = C_Map.GetMapInfo(info.parentMapID)
        if not parent then
            break
        end
        info = parent
    end
    return info and info.mapID or nil
end

-- Forever's Azeroth map (Classic map IDs: Kalimdor 1414, Eastern Kingdoms 1415), for finding a
-- zone by name where the player has no map, like in a dungeon.
local AZEROTH = ns.GameData.Map(947, "Azeroth")

-- A name made easy to compare: lowercase letters and digits only.
local function plain(text)
    return (text:lower():gsub("[^%w]", ""))
end

---The map called `name`: a zone before any other kind of map with that name, then the first
---zone whose name starts with it, under the top map above the player's (or Azeroth). "#1429" is a
---map ID, as TomTom takes it. Nil when there's none.
---@param name string
---@return number? mapID
function WorldMap.FindMap(name)
    local id = tonumber(name:match("^#(%d+)$"))
    if id then
        return C_Map.GetMapInfo(id) and id or nil
    end
    local wanted = plain(name)
    if wanted == "" or not C_Map.GetMapChildrenInfo then
        return nil
    end
    local root = WorldMap.Root(C_Map.GetBestMapForUnit("player")) or AZEROTH
    local zone = Enum and Enum.UIMapType and Enum.UIMapType.Zone
    local exact, other, partial
    for _, info in ipairs(C_Map.GetMapChildrenInfo(root, nil, true) or {}) do
        local have = plain(info.name or "")
        if have == wanted then
            if info.mapType == zone then
                exact = exact or info.mapID
            else
                other = other or info.mapID
            end
        elseif not partial and info.mapType == zone and have:sub(1, #wanted) == wanted then
            partial = info.mapID
        end
    end
    return exact or other or partial
end

---Whether this client lets addons place the map pin (the user waypoint).
---@return boolean
function WorldMap.CanWaypoint()
    return C_Map and C_Map.SetUserWaypoint and C_Map.CanSetUserWaypointOnMap and true or false
end

---Puts Blizzard's map pin on `mapID` at x, y (0 to 1) and tracks it, so the game draws the pin
---and its marker in the world. False with why not: "unavailable" (this client can't), "range"
---(x or y outside 0 to 1), or "map" (no pin allowed on that map, like inside a dungeon).
---@param mapID number
---@param x number
---@param y number
---@return boolean ok
---@return string? reason
function WorldMap.SetWaypoint(mapID, x, y)
    if not WorldMap.CanWaypoint() then
        return false, "unavailable"
    end
    if x < 0 or x > 1 or y < 0 or y > 1 then
        return false, "range"
    end
    if not C_Map.CanSetUserWaypointOnMap(mapID) then
        return false, "map"
    end
    local point
    if UiMapPoint and UiMapPoint.CreateFromCoordinates then
        point = UiMapPoint.CreateFromCoordinates(mapID, x, y)
    else
        point = { uiMapID = mapID, position = CreateVector2D(x, y) }
    end
    C_Map.SetUserWaypoint(point)
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
        C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    end
    return true
end

---A map's name, or `fallback` for a map the game doesn't know.
---@param mapID number
---@param fallback? string
---@return string?
function WorldMap.MapName(mapID, fallback)
    local info = mapID and C_Map.GetMapInfo(mapID)
    return info and info.name or fallback
end

---Where the player stands on `mapID` (the map they're on, by default): the map and x, y from 0
---to 1. Nil when it can't be read, as in an instance or while it's secret.
---@param mapID? number
---@return number? mapID
---@return number? x
---@return number? y
function WorldMap.PlayerPosition(mapID)
    if not (C_Map and C_Map.GetPlayerMapPosition) then
        return nil
    end
    mapID = mapID or (C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))
    if not (ns.IsReadable(mapID) and mapID) then
        return nil
    end
    local position = C_Map.GetPlayerMapPosition(mapID, "player")
    local x, y = position and position.x, position and position.y
    if not (ns.IsReadable(x) and ns.IsReadable(y) and x and y) then
        return nil
    end
    return mapID, x, y
end

---Where the player stands on their zone's map, so a spot in a district or below ground goes on
---the zone's map with the rest: the zone map ID, x, y, or nil where it can't be read.
---@return number? mapID
---@return number? x
---@return number? y
function WorldMap.PlayerZonePosition()
    local mapID, x, y = WorldMap.PlayerPosition()
    local zone = mapID and WorldMap.Zone(mapID)
    if zone and zone ~= mapID then
        return WorldMap.PlayerPosition(zone)
    end
    return mapID, x, y
end

local sizes = {} -- mapID -> { width, height } in yards, or false: a map's size never changes

---A map's size in yards (C_Map.GetMapWorldSize), or nil when the game can't say, as for a map
---with no place in the world. Asked once per map.
---@param mapID number
---@return number? width
---@return number? height
function WorldMap.Size(mapID)
    if mapID == nil then
        return nil
    end
    local size = sizes[mapID]
    if size == nil then
        size = false
        local width, height
        if C_Map and C_Map.GetMapWorldSize then
            width, height = C_Map.GetMapWorldSize(mapID)
        end
        if ns.IsNumber(width) and ns.IsNumber(height) and width > 0 and height > 0 then
            size = { width, height }
        end
        sizes[mapID] = size
    end
    if size then
        return size[1], size[2]
    end
end

-- Directions ----------------------------------------------------------------------------------

---How far and which way one spot on a map is from another, for an arrow. Spots are 0 to 1 across
---and down the map, as C_Map gives them, and `width` and `height` are the map's size in yards
---(C_Map.GetMapWorldSize). The angle is counter-clockwise from north in radians, 0 to 2 pi, like
---GetPlayerFacing, so an arrow pointing ahead turns by `angle - facing`.
---@param width number yards
---@param height number yards
---@param fromX number
---@param fromY number
---@param toX number
---@param toY number
---@return number yards
---@return number angle
function WorldMap.Toward(width, height, fromX, fromY, toX, toY)
    local east = (toX - fromX) * width
    local south = (toY - fromY) * height
    return sqrt(east * east + south * south), atan2(-east, -south) % (2 * pi)
end

-- Sides -----------------------------------------------------------------------------------------
-- Map data marks what belongs to a faction with "A" (Alliance) or "H" (Horde).

local SIDES = { Alliance = "A", Horde = "H" }
local SIDE_NAMES = { A = FACTION_ALLIANCE, H = FACTION_HORDE }

---The player's side, "A" or "H", or nil when the game doesn't say.
---@return string?
function WorldMap.PlayerSide()
    return SIDES[UnitFactionGroup("player") or ""]
end

---A side's faction name in the player's language ("Horde"), or nil for any other letter.
---@param side string
---@return string?
function WorldMap.SideName(side)
    return SIDE_NAMES[side]
end

-- Blizzard's panels ---------------------------------------------------------------------------

-- The CVars of Blizzard's checkboxes for the player's and the cursor's coordinates on the map
-- (Settings > Gameplay > Interface > Coordinates). Forever only; see docs/forever-api.md.
WorldMap.COORDS_CVARS = { "worldMapShowPlayerCoords", "worldMapShowCursorCoords" }

local coords -- false once looked for and not there

---Blizzard's coordinates panel: the map's overlay frame with a CursorCoords row and a
---PlayerCoords row, or nil before the map loads or on a client without it. It has no name, so
---it's found by its parts.
---@return table?
function WorldMap.CoordsPanel()
    if coords == nil then
        local map = WorldMap.Get()
        if not map then
            return nil
        end
        coords = false
        for _, frame in ipairs(map.overlayFrames or {}) do
            if frame.CursorCoords and frame.PlayerCoords then
                coords = frame
                break
            end
        end
    end
    return coords or nil
end
