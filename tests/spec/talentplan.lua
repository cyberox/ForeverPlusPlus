-- TalentPlan: adding and removing points under Classic's rules, sharing plans, and levels.
local T = ...
local ns, eq = T.ns, T.eq

local Plan = ns.TalentPlan
-- Two tabs. Tab 1: a (5 ranks, row 0), b (3, row 1, needs 5), c (1, row 1, needs a maxed).
-- Tab 2: d (5, row 0), e (1, row 0, needs d or a maxed: Sufficient edges).
local talents = {
    nodes = {
        a = { max = 5, tab = 1, req = 0, prereqs = {} },
        b = { max = 3, tab = 1, req = 5, prereqs = {} },
        c = { max = 1, tab = 1, req = 5, prereqs = { { id = "a", required = true } } },
        d = { max = 5, tab = 2, req = 0, prereqs = {} },
        e = { max = 1, tab = 2, req = 0, prereqs = { { id = "d" }, { id = "a" } } },
    },
    order = { "a", "d", "e", "b", "c" },
}

local picks = {}
eq(Plan.Add(talents, picks, "b", 10), false, "row 1 needs 5 points in the tab")
eq(select(2, Plan.Add(talents, picks, "b", 10)), "tier", "tier reason")
for _ = 1, 4 do
    Plan.Add(talents, picks, "a", 10)
end
eq(select(2, Plan.Add(talents, picks, "c", 10)), "tier", "4 points aren't 5")
eq(select(2, Plan.Add(talents, picks, "e", 10)), "prereq", "sufficient edge unmet")
eq(Plan.Add(talents, picks, "a", 10), true, "fifth rank")
eq(select(2, Plan.Add(talents, picks, "a", 10)), "max", "no sixth rank")
eq(Plan.Add(talents, picks, "c", 10), true, "prerequisite maxed")
eq(Plan.Add(talents, picks, "e", 10), true, "any sufficient edge is enough")
eq(#picks, 7, "seven points")
eq(select(2, Plan.Add(talents, picks, "d", 7)), "points", "no points left at the cap")

eq(select(2, Plan.Remove(talents, picks, "a")), "needed", "c and e need the fifth a")
eq(Plan.Remove(talents, picks, "e"), true, "remove the last point")
eq(Plan.Remove(talents, picks, "c"), true, "then c")
eq(Plan.Remove(talents, picks, "a"), true, "then a is free")
eq(#picks, 4, "four points left")
eq(select(2, Plan.Remove(talents, picks, "d")), "none", "nothing in d")
eq(select(2, Plan.Remove(talents, { "a", "a", "d" }, "d", 2)), "none", "remove looks under the cap")

local counts, tabs, bad, why = Plan.Simulate(talents, { "a", "b" })
eq(bad, 2, "simulate finds the bad point")
eq(why, "tier", "and why")
eq(counts.a, 1, "counts before it")
eq(tabs[1], 1, "tab points before it")
eq(select(3, Plan.Simulate(talents, { "a", "b" }, 1)), nil, "limit stops before it")

local order = Plan.FromRanks(talents, { a = 5, c = 1, e = 1, d = 2 })
eq(#order, 9, "learned points all placed")
eq(select(3, Plan.Simulate(talents, order)), nil, "learned order is valid")
eq(order[1], "a", "top row first")

eq(select(2, Plan.Next({ "a", "a", "d", "a" }, { a = 2 })), "d", "next unlearned point")
eq(Plan.Next({ "a", "a", "d", "a" }, { a = 2 }), 3, "its place")
eq(Plan.Next({ "a" }, { a = 1 }), nil, "plan done")

local shared = Plan.Encode(1117, { name = "Arms: Leveling|x", level = 30, picks = { 101, 101, 101, 102, 101 } })
eq(shared, "FPP:1:1117:30:Arms Levelingx:101*3,102,101", "encode runs, strip : and |")
local back = Plan.Decode("  " .. shared .. " ")
eq(back and back.treeID, 1117, "decode tree")
eq(back and back.level, 30, "decode level")
eq(back and back.name, "Arms Levelingx", "decode name")
eq(back and #back.picks, 5, "decode points")
eq(back and back.picks[3], 101, "decode run")
eq(back and back.picks[4], 102, "decode single")
eq(#Plan.Decode("FPP:1:5:10::").picks, 0, "decode empty plan")
eq(Plan.Decode("hello"), nil, "decode junk")
eq(Plan.Decode("FPP:1:5:10:x:1**2"), nil, "decode bad run")
eq(Plan.Decode("FPP:1:5:60::1*999999999"), nil, "decode refuses a huge run")
eq(Plan.Decode("FPP:1:5:60::1*50,2*2"), nil, "decode refuses more than 51 points")
eq(#Plan.Decode("FPP:1:5:60::1*50,2").picks, 51, "decode takes 51 points")
eq(Plan.Decode("FPP:1:5:60:|cffff0000Red|r:1").name, "cffff0000Redr", "decode drops | from names")

eq(Plan.FirstLevel(30, 21), 10, "first point at 10")
eq(Plan.FirstLevel(5, 0), 10, "none earned yet: Classic's 10")
eq(Plan.PointsAt(30, 10), 21, "21 points at 30")
eq(Plan.PointsAt(9, 10), 0, "none before 10")
eq(Plan.LevelOf(21, 10), 30, "21st point at 30")
eq(Plan.FirstLevel(30, 26, 5), 5, "talented: counted from points earned")
eq(Plan.FirstLevel(4, 0, 5), 5, "talented, none earned yet: level 5")
eq(Plan.FirstLevel(60, 51, 5), 5, "talented, all 51 earned: level 5")
eq(Plan.FirstLevel(60, 51), 10, "all 51 earned: level 10")
eq(Plan.PointsAt(60, 5), 51, "never more than 51")
eq(Plan.PointsAt(30, 5), 26, "talented: 26 points at 30")

-- Rows 90 apart from the top at 100; a node 1 off its row's height stays in it, and a gate
-- condition the game gave is kept.
local gated = {
    top = { y = 100 },
    nudged = { y = 101 },
    second = { y = 190 },
    fourth = { y = 370 },
    given = { y = 370, req = 7 },
}
Plan.RowGates(gated)
eq(gated.top.req, 0, "row gates: top row needs nothing")
eq(gated.nudged.req, 0, "row gates: a 1 gap isn't a row")
eq(gated.second.req, 5, "row gates: second row needs 5")
eq(gated.fourth.req, 15, "row gates: rows counted by the smallest gap")
eq(gated.given.req, 7, "row gates: a gate condition is kept")
local single = { only = { y = 40 } }
Plan.RowGates(single, 3)
eq(single.only.req, 0, "row gates: one node is the top row")
local custom = { a = { y = 0 }, b = { y = 50 } }
Plan.RowGates(custom, 3)
eq(custom.b.req, 3, "row gates: points per row can be given")
