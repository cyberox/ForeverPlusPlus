-- WorldMap: the map tree, zones by name, the map pin, the player's side, and Toward.
local T = ...
local ns, eq, near, game, player = T.ns, T.eq, T.near, T.game, T.player

local WorldMap = ns.WorldMap
eq(WorldMap.IsContinent({ mapType = 2 }), true, "continent")
eq(WorldMap.IsContinent({ mapType = 1 }), true, "world")
eq(WorldMap.IsContinent({ mapType = 3 }), false, "zone")
eq(WorldMap.IsContinent({ mapType = 0 }), false, "cosmic off by default")
eq(WorldMap.IsContinent({ mapType = 0 }, true), true, "cosmic when asked")
eq(WorldMap.IsContinent(nil), false, "no info")

-- A map tree: Azeroth (world) > Kalimdor (continent) > Durotar (zone) > a cave (dungeon).
local maps = {
    [947] = { mapID = 947, name = "Azeroth", mapType = 1, parentMapID = 0 },
    [12] = { mapID = 12, name = "Kalimdor", mapType = 2, parentMapID = 947 },
    [1411] = { mapID = 1411, name = "Durotar", mapType = 3, parentMapID = 12 },
    [9001] = { mapID = 9001, name = "Cave", mapType = 4, parentMapID = 1411 },
}
local here = { mapID = 1411, x = 0.25, y = 0.75 }
C_Map = {
    GetMapInfo = function(id)
        return maps[id]
    end,
    GetBestMapForUnit = function()
        return here.mapID
    end,
    GetPlayerMapPosition = function(id)
        return id == here.mapID and { x = here.x, y = here.y } or nil
    end,
}
local walked = {}
for mapID in WorldMap.Up(9001) do
    walked[#walked + 1] = mapID
end
eq(table.concat(walked, ","), "9001,1411,12", "Up stops at the continent")
walked = {}
for mapID in WorldMap.Up(947) do
    walked[#walked + 1] = mapID
end
eq(table.concat(walked, ","), "947", "Up from the world is just the world")
walked = {}
for mapID, info in WorldMap.Up(5) do
    walked[#walked + 1] = mapID .. (info and "" or "?")
end
eq(table.concat(walked, ","), "5?", "Up stops at a map without info")
eq(WorldMap.Up(nil)(), nil, "Up from no map")
eq(WorldMap.Root(9001), 947, "Root")
eq(WorldMap.Root(5), nil, "Root of an unknown map")
eq(WorldMap.MapName(1411, "?"), "Durotar", "MapName")
eq(WorldMap.MapName(5, "?"), "?", "MapName fallback")
local id, x, y = WorldMap.PlayerPosition()
eq(id == 1411 and x == 0.25 and y == 0.75, true, "PlayerPosition on the player's map")
eq(WorldMap.PlayerPosition(12), nil, "PlayerPosition off the map")
game.secret = 0.25
eq(WorldMap.PlayerPosition(), nil, "PlayerPosition while secret")
game.secret = nil

-- A map's size in yards, asked once per map.
local asked = 0
C_Map.GetMapWorldSize = function(id)
    asked = asked + 1
    if id == 1411 then
        return 5000, 3000
    end
    return 0, 0
end
local width, height = WorldMap.Size(1411)
eq(width == 5000 and height == 3000, true, "Size")
WorldMap.Size(1411)
eq(asked, 1, "Size asks once")
eq(WorldMap.Size(12), nil, "Size of a map with none")
WorldMap.Size(12)
eq(asked, 2, "Size remembers a map with none")

-- Zones by name, under the root above the player's map, and the map pin.
maps[1413] = { mapID = 1413, name = "The Barrens", mapType = 3, parentMapID = 12 }
maps[1412] = { mapID = 1412, name = "Durotar", mapType = 5, parentMapID = 12 } -- not a zone
local pin
C_Map.GetMapChildrenInfo = function(root)
    if root ~= 947 then
        return {}
    end
    return { maps[1412], maps[1411], maps[1413], maps[9001] }
end
C_Map.CanSetUserWaypointOnMap = function(mapID)
    return mapID ~= 9001
end
C_Map.SetUserWaypoint = function(point)
    pin = point
end
UiMapPoint = { CreateFromCoordinates = function(mapID, px, py)
    return { uiMapID = mapID, position = { x = px, y = py } }
end }
eq(WorldMap.FindMap("Durotar"), 1411, "FindMap: a zone before another map of the name")
eq(WorldMap.FindMap("the barrens"), 1413, "FindMap: any case and spacing")
eq(WorldMap.FindMap("Barr"), nil, "FindMap: a start must match the start")
eq(WorldMap.FindMap("TheBar"), 1413, "FindMap: the start of a zone's name")
eq(WorldMap.FindMap("#12"), 12, "FindMap: a map ID")
eq(WorldMap.FindMap("#5"), nil, "FindMap: an unknown map ID")
eq(WorldMap.FindMap("Nowhere"), nil, "FindMap: no such zone")
eq(WorldMap.CanWaypoint(), true, "CanWaypoint")
eq(WorldMap.SetWaypoint(1411, 0.5, 0.25), true, "SetWaypoint")
eq(pin and pin.uiMapID == 1411 and pin.position.y == 0.25, true, "SetWaypoint sets the pin")
local ok, why = WorldMap.SetWaypoint(1411, 1.5, 0)
eq(ok == false and why, "range", "SetWaypoint: outside the map")
ok, why = WorldMap.SetWaypoint(9001, 0.5, 0.5)
eq(ok == false and why, "map", "SetWaypoint: a map without pins")
UiMapPoint = nil
C_Map = nil
eq(WorldMap.PlayerSide(), "H", "Horde side")
player.faction = "Alliance"
eq(WorldMap.PlayerSide(), "A", "Alliance side")
player.faction = "Pandaren"
eq(WorldMap.PlayerSide(), nil, "neutral side")
eq(WorldMap.SideName("A"), "Alliance", "side name")
eq(WorldMap.SideName("X"), nil, "unknown side name")

-- Toward: on a 1000 by 500 yard map, from the middle.
local yards, angle = WorldMap.Toward(1000, 500, 0.5, 0.5, 0.5, 0.3)
near(yards, 100, "north distance")
near(angle, 0, "north is 0")
yards, angle = WorldMap.Toward(1000, 500, 0.5, 0.5, 0.4, 0.5)
near(yards, 100, "west distance uses width")
near(angle, math.pi / 2, "west is a quarter turn left")
_, angle = WorldMap.Toward(1000, 500, 0.5, 0.5, 0.5, 0.7)
near(angle, math.pi, "south is half a turn")
_, angle = WorldMap.Toward(1000, 500, 0.5, 0.5, 0.6, 0.5)
near(angle, 3 * math.pi / 2, "east is three quarters")
yards = WorldMap.Toward(1000, 500, 0.2, 0.2, 0.2, 0.2)
near(yards, 0, "same spot")
