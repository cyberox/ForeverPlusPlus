-- Gathering: remembering nodes, merged by yards with their spots averaged.
local T = ...
local ns, eq, near = T.ns, T.eq, T.near

local Gathering = ns.Gathering

eq(Gathering.Round(0.123456), 0.1235, "round: 4 places")
eq(Gathering.Round(0.5), 0.5, "round: already round")

-- A zone 2000 yards wide and 1000 tall: 0.01 across is 20 yards, 0.01 down is 10.
local W, H = 2000, 1000
near(Gathering.Distance(0.5, 0.5, 0.51, 0.5, W, H), 20, "distance: across")
near(Gathering.Distance(0.5, 0.5, 0.5, 0.51, W, H), 10, "distance: down")

local list = {}
local node, new = Gathering.Add(list, "Copper Vein", "ore", 0.5, 0.5, W, H, 100)
eq(new, true, "add: a first gather is a new node")
eq(#list, 1, "add: saved")
eq(node.count .. ":" .. node.time, "1:100", "add: count and time")

-- 10 yards down: the same vein, its spot halfway between the two.
node, new = Gathering.Add(list, "Copper Vein", "ore", 0.5, 0.51, W, H, 1000)
eq(new, false, "add: within the radius is the same node")
eq(#list, 1, "add: not saved twice")
eq(node.y, 0.505, "add: the spot is the average")
eq(node.count .. ":" .. node.time, "2:1000", "add: counted again")
-- Mined again a minute later: the same visit, neither counted nor moved.
node = Gathering.Add(list, "Copper Vein", "ore", 0.5, 0.5, W, H, 1060)
eq(node.count .. ":" .. node.time .. ":" .. node.y, "2:1060:0.505", "add: the same visit counts once")

-- 20 yards across is out of the 15 yard radius: another vein.
node, new = Gathering.Add(list, "Copper Vein", "ore", 0.51, 0.505, W, H, 300)
eq(new, true, "add: out of the radius is another node")
-- Another node's name at the same spot is its own node (silver where tin spawns).
node, new = Gathering.Add(list, "Tin Vein", "ore", 0.5, 0.505, W, H, 300)
eq(new, true, "add: another name is another node")
eq(#list, 3, "add: three nodes")

-- Nearest, with and without a match.
local found, yards = Gathering.Nearest(list, 0.5, 0.505, W, H, 5)
eq(found ~= nil and yards == 0, true, "nearest: right on one")
found = Gathering.Nearest(list, 0.5, 0.505, W, H, 5, function(known)
    return known.name == "Peacebloom"
end)
eq(found, nil, "nearest: nothing matches")
found = Gathering.Nearest(list, 0.509, 0.505, W, H, 5)
eq(found and found.x, 0.51, "nearest: the closest within the radius")

-- Sightings: a node seen on the minimap, not gathered.
local seen = {}
node, new = Gathering.See(seen, "Peacebloom", "herb", 0.3, 0.3, W, H, 1000)
eq(new, true, "see: a first sighting is a new node")
eq(node.count .. ":" .. node.sightings, "0:1", "see: seen, never gathered")
node = Gathering.See(seen, "Peacebloom", "herb", 0.3, 0.31, W, H, 1030)
eq(node.sightings .. ":" .. node.y, "1:0.3", "see: seen again on the same visit changes nothing")
node = Gathering.See(seen, "Peacebloom", "herb", 0.3, 0.31, W, H, 2000)
eq(node.sightings .. ":" .. node.y, "2:0.305", "see: a later visit moves it")
node, new = Gathering.Add(seen, "Peacebloom", "herb", 0.3, 0.305, W, H, 2100)
eq(new, false, "see: gathering a node seen is the same node")
eq(node.count, 1, "see: and counts its first gather")
eq(#seen, 1, "see: one node")

-- The average counts at most ten gathers, so a node that moved still follows.
local moved = { { name = "Peacebloom", kind = "herb", x = 0.2, y = 0.2, count = 50, time = 1 } }
node = Gathering.Add(moved, "Peacebloom", "herb", 0.2055, 0.2, W, H, 1000)
eq(node.x, 0.2005, "add: the average weighs at most ten gathers")
