-- Points of Interest's flight points: which this character has learned, and where the ones a
-- flight master shows are, saved and merged into the data's (Data/PointsOfInterest.lua).
local _, ns = ...

local ipairs, pairs, format, abs, type = ipairs, pairs, string.format, math.abs, type
local C_Map, C_TaxiMap, Enum = C_Map, C_TaxiMap, Enum
local UnitName, GetRealmName = UnitName, GetRealmName

local internal = ns.modules.WorldMap.internal.pointsOfInterest
local module = internal.module
local NEAR, translate, percent = internal.NEAR, internal.translate, internal.percent

-- Up to 0.8.4 every character's learned flight points were saved for the account, by "Name-Realm".
ns.MigrateCharacter(2, function(char, db)
    -- UnitName's second value is a surname on Forever, not a realm.
    local me = format("%s-%s", UnitName("player") or "", GetRealmName() or "")
    ns.Store.Claim(char, db, "WorldMap", "learnedNodes", function(entries)
        local mine = entries[me]
        entries[me] = nil
        return mine
    end)
end)

-- The game's flight points on the map being drawn. Forever's world map doesn't show them, and its
-- list can't say which are learned (see learned).
local taxiNodes = {}

function internal.readTaxiNodes(mapID)
    taxiNodes = C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap
        and C_TaxiMap.GetTaxiNodesForMap(mapID) or {}
end

-- The flight points this character has seen as learned at a flight master, by the game's node ID
-- (names repeat: Light's Hope Chapel has one per faction, and the game's names are in the
-- player's language), saved per character. The map list above may not have them on Forever, so
-- this is the other way to know.
local function seenLearned()
    return module.db.learnedNodes
end

-- At a flight master, remembers which of the flight points it lists are learned, by node ID.
-- Mainline's node states (Lib/Taxi.lua): ones the master can't fly to are Unreachable.
function internal.rememberLearned()
    if not Enum.FlightPathState then
        return
    end
    local seen = seenLearned()
    for _, node in ipairs((ns.Taxi.Nodes())) do
        if node.nodeID and node.state ~= Enum.FlightPathState.Unreachable then
            seen[node.nodeID] = true
        end
    end
end

-- The game's flight point for one of the data's, by place: the closest on the map. The node
-- carries the ID.
local function nodeOf(point)
    local best, bestDistance
    for _, node in ipairs(taxiNodes) do
        local x, y = node.position:GetXY()
        local dx, dy = abs(x * 100 - point[2]), abs(y * 100 - point[3])
        if dx < NEAR and dy < NEAR and (not bestDistance or dx + dy < bestDistance) then
            best, bestDistance = node, dx + dy
        end
    end
    return best
end

-- Whether the character has learned the flight master at this point: true when a flight master
-- visit saw its node learned, false when the game's map list calls it undiscovered, else nil.
-- The map list can't say one is learned: on Forever (2026-09-28) it lists the whole continent
-- for a zone (36 for Silverpine) and calls ones never visited discovered.
function internal.learned(point)
    if point.node and seenLearned()[point.node] then
        return true
    end
    local node = nodeOf(point)
    if not (node and node.nodeID) then
        return nil
    end
    if seenLearned()[node.nodeID] then
        return true
    end
    if node.isUndiscovered then
        return false
    end
end

-- Flight points a flight master showed --------------------------------------------------------
-- The data's flight points are the seed (build 70009). A flight master's map lists every flight
-- point of the continent with its place, so each one seen is saved for the account by node ID:
-- { map, x, y, faction, name }, x and y in percent on `map`. One on the spot of the data's takes
-- its place, and one the data lacks (a patch's new flight point) is added.
local FLIGHTS = ns.GameData.New("flightPoints", {}, { label = "Flight points" })

-- How close (in percent of the flight master's map, a continent) a flight point the game lists is
-- to one of the data's for the two to be the same.
local SAME_NODE = 0.6

-- Mainline's Enum.FlightPathFaction (Neutral 0, Horde 1, Alliance 2) as our letters. Probe:
-- whether Forever's taxi nodes have `faction` is Unverified; without it, the player's side.
local function nodeFaction(node)
    local enum = Enum.FlightPathFaction
    local faction = node.faction
    if enum and faction ~= nil then
        if faction == enum.Horde then
            return "H"
        elseif faction == enum.Alliance then
            return "A"
        elseif faction == enum.Neutral then
            return "N"
        end
    end
    return ns.WorldMap.PlayerSide()
end

-- Whether flight points of these two factions can be the same one.
local function sameSide(a, b)
    return not a or not b or a == b or a == "N" or b == "N"
end

-- The data's flight point nearest a spot on the flight master's map: its map and point.
local function seedFlightNear(taxiMap, x, y, faction)
    local bestMap, best, bestDistance
    for fromMap, points in pairs(internal.points) do
        for _, point in ipairs(points) do
            if point[1] == "flight" and sameSide(point[4], faction) then
                local px, py = translate(fromMap, taxiMap, point[2] / 100, point[3] / 100)
                local distance = px and abs(px - x) + abs(py - y)
                if distance and distance * 100 < SAME_NODE
                    and (not bestDistance or distance < bestDistance) then
                    bestMap, best, bestDistance = fromMap, point, distance
                end
            end
        end
    end
    return bestMap, best
end

-- At a flight master, saves where each flight point on its map is: on the map of the data's flight
-- point on the same spot, or else on the zone the game says the spot is in.
function internal.learnFlights()
    local nodes, taxiMap = ns.Taxi.Nodes()
    local changed = false
    for _, node in ipairs(nodes) do
        local x, y
        if node.nodeID and node.position and not node.isMapLayerTransition then
            x, y = node.position:GetXY()
        end
        if x and y and ns.IsReadable(x) and ns.IsReadable(y) then
            local faction = nodeFaction(node)
            local mapID = seedFlightNear(taxiMap, x, y, faction)
            if not mapID and C_Map.GetMapInfoAtPosition then
                local info = C_Map.GetMapInfoAtPosition(taxiMap, x, y)
                mapID = info and info.mapID ~= taxiMap and info.mapID
            end
            local zx, zy
            if mapID then
                zx, zy = ns.MapPins.Translate(taxiMap, mapID, x, y)
            end
            if zx and FLIGHTS:Learn(node.nodeID, { map = mapID, x = percent(zx), y = percent(zy),
                faction = faction, name = node.name }) then
                changed = true
            end
        end
    end
    if changed then
        internal.flightsChanged = true
    end
end

-- Each map's points: the data's, with the saved flight points in. Made again once something new
-- is saved.
local merged, mergedCount = {}, -1

local function mergeFlights()
    merged = {}
    local learnedOn = {} -- map ID -> { node ID -> saved flight point }
    for nodeID, node in FLIGHTS:Pairs() do
        if type(node) == "table" and node.map and node.x and node.y then
            learnedOn[node.map] = learnedOn[node.map] or {}
            learnedOn[node.map][nodeID] = node
        end
    end
    for mapID, points in pairs(internal.points) do
        local list, nodes = {}, learnedOn[mapID] or {}
        for _, point in ipairs(points) do
            if point[1] == "flight" then
                local bestID, bestDistance
                for nodeID, node in pairs(nodes) do
                    local distance = abs(node.x - point[2]) + abs(node.y - point[3])
                    if sameSide(point[4], node.faction) and abs(node.x - point[2]) < NEAR
                        and abs(node.y - point[3]) < NEAR
                        and (not bestDistance or distance < bestDistance) then
                        bestID, bestDistance = nodeID, distance
                    end
                end
                if bestID then
                    local node = nodes[bestID]
                    nodes[bestID] = nil
                    point = { "flight", node.x, node.y, point[4], point[5], node = bestID }
                end
            end
            list[#list + 1] = point
        end
        merged[mapID] = list
    end
    -- The ones left are flight points the data doesn't have.
    for mapID, nodes in pairs(learnedOn) do
        for nodeID, node in pairs(nodes) do
            local list = merged[mapID] or {}
            merged[mapID] = list
            list[#list + 1] = { "flight", node.x, node.y, node.faction or "N", node.name or "",
                node = nodeID }
        end
    end
    mergedCount = FLIGHTS:Learned()
end

-- Every map's points, by map ID.
local function allPoints()
    if internal.flightsChanged or mergedCount ~= FLIGHTS:Learned() then
        internal.flightsChanged = false
        mergeFlights()
    end
    return merged
end
internal.allPoints = allPoints

function internal.pointsOf(mapID)
    return allPoints()[mapID] or {}
end
