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
node, new = Gathering.Add(list, "Copper Vein", "ore", 0.5, 0.51, W, H, 200)
eq(new, false, "add: within the radius is the same node")
eq(#list, 1, "add: not saved twice")
eq(node.y, 0.505, "add: the spot is the average")
eq(node.count .. ":" .. node.time, "2:200", "add: counted again")

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

-- The average counts at most ten gathers, so a node that moved still follows.
local moved = { { name = "Peacebloom", kind = "herb", x = 0.2, y = 0.2, count = 50, time = 1 } }
node = Gathering.Add(moved, "Peacebloom", "herb", 0.2055, 0.2, W, H, 2)
eq(node.x, 0.2005, "add: the average weighs at most ten gathers")
