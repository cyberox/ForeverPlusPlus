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
node, new = Gathering.Add(seen, "Peacebloom", "herb", 0.301, 0.307, W, H, 2100)
eq(new, false, "see: gathering a node seen is the same node")
eq(node.count, 1, "see: and counts its first gather")
eq(node.x .. ":" .. node.y, "0.3003:0.3057", "see: a gather averages with the sightings")
eq(#seen, 1, "see: one node")
-- A gather 30 yards from a node only seen is another node: sightings are exact spots.
local far = { { name = "Silverleaf", kind = "herb", x = 0.4, y = 0.4, count = 0, sightings = 1 } }
node, new = Gathering.Add(far, "Silverleaf", "herb", 0.4, 0.43, W, H, 100)
eq(new, true, "add: a node only seen 30 yards off is another")
-- Silver where Tin spawns is the same node, shown as the one gathered most.
local shared = {}
Gathering.Add(shared, "Tin Vein", "ore", 0.7, 0.7, W, H, 100)
node, new = Gathering.Add(shared, "Silver Vein", "ore", 0.7, 0.701, W, H, 1000)
eq(new, false, "spawns: silver at tin's spot is the same node")
eq(node.name .. ":" .. node.names["Tin Vein"] .. ":" .. node.names["Silver Vein"], "Tin Vein:1:1",
    "spawns: each name counted, shown as the first while even")
node = Gathering.Add(shared, "Silver Vein", "ore", 0.7, 0.7, W, H, 2000)
eq(node.name .. ":" .. node.count, "Silver Vein:3", "spawns: shown as the one gathered most")
node, new = Gathering.Add(shared, "Copper Vein", "ore", 0.7, 0.7, W, H, 3000)
eq(new, true, "spawns: copper isn't silver's or tin's")

-- The average counts at most ten gathers, so a node that moved still follows.
local moved = { { name = "Peacebloom", kind = "herb", x = 0.2, y = 0.2, count = 50, time = 1 } }
node = Gathering.Add(moved, "Peacebloom", "herb", 0.2055, 0.2, W, H, 1000)
eq(node.x, 0.2005, "add: the average weighs at most ten gathers")

-- The red error a node too high for the player's skill gives: its skill line and the rank it takes.
local Professions = ns.Professions
local line, need = Gathering.Requirement("Requires Mining 175")
eq(line == Professions.MINING and need, 175, "requirement: mining")
line, need = Gathering.Requirement("Requires Herbalism (150)")
eq(line == Professions.HERBALISM and need, 150, "requirement: herbalism, with parentheses")
eq(Gathering.Requirement("Requires Mining"), nil, "requirement: no rank, nothing")
eq(Gathering.Requirement("Not enough rage"), nil, "requirement: another error, nothing")

-- Sharing: nodes as a line of text and back, and merged into what's known.
local shared = {
    [1429] = {
        { name = "Copper Vein", kind = "ore", x = 0.4523, y = 0.6711, count = 3, time = 1700000000 },
        { name = "Peacebloom", kind = "herb", x = 0.1, y = 0.2, count = 0 },
    },
    [1436] = { { name = "Battered Chest", kind = "treasure", x = 0.5, y = 0.5, count = 1, time = 5 } },
}
local text, sharedCount = Gathering.Encode(shared)
eq(sharedCount, 3, "share: three nodes")
eq(text:find("|", 1, true), nil, "share: no pipe in the text")
local back, backCount = Gathering.Decode(text)
eq(backCount, 3, "share: three nodes back")
local vein = back[1429][1]
eq(vein.name .. ":" .. vein.kind .. ":" .. vein.x .. ":" .. vein.y .. ":" .. vein.count .. ":" .. vein.time,
    "Copper Vein:ore:0.4523:0.6711:3:1700000000", "share: a node comes back the same")
eq(back[1429][2].time, nil, "share: never gathered stays without a time")
eq(back[1436][1].kind, "treasure", "share: a chest's kind")
local _, onlyOre = Gathering.Encode(shared, function(n) return n.kind == "ore" end)
eq(onlyOre, 1, "share: only the nodes kept")
eq(Gathering.Decode("hello"), nil, "share: not a share string")
eq(Gathering.Decode("GM1/oCopper Vein/1429:5,1,1,1,1"), nil, "share: a name past the list")
eq(select(2, Gathering.Decode("GM1//")), 0, "share: nothing shared")
-- Merging: the same vein close by takes the larger count; one far off is added.
local mine = { { name = "Copper Vein", kind = "ore", x = 0.452, y = 0.671, count = 1, time = 10 } }
eq(Gathering.Merge(mine, vein, W, H), false, "merge: the same node close by")
eq(mine[1].count .. ":" .. mine[1].time, "3:1700000000", "merge: larger count, later time")
eq(Gathering.Merge(mine, { name = "Copper Vein", kind = "ore", x = 0.9, y = 0.9, count = 2 }, W, H),
    true, "merge: one far off is added")
eq(#mine, 2, "merge: two nodes")
