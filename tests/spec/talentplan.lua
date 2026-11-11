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

-- Gate conditions: only a talent-point gate a character can meet is a row's.
eq(Plan.GateAmount({}, 3820), nil, "gate: no conditions")
eq(Plan.GateAmount({ { isGate = true, spentAmountRequired = 5, traitCurrencyID = 3820 } }, 3820), 5,
    "gate: a talent point gate")
eq(Plan.GateAmount({ { isGate = true, spentAmountRequired = 300, traitCurrencyID = 3820 } }, 3820), nil,
    "gate: more points than a character has (a hunter's Survival row 2)")
eq(Plan.GateAmount({ { isGate = true, spentAmountRequired = 5, traitCurrencyID = 4225 } }, 3820), nil,
    "gate: another currency")
eq(Plan.GateAmount({ { isGate = false, spentAmountRequired = 5 } }, 3820), nil, "gate: not a gate")
eq(Plan.GateAmount({ { isGate = true, spentAmountRequired = 10 } }), 10, "gate: no currency to check")
eq(Plan.GateAmount({ { isGate = true, spentAmountRequired = 300, traitCurrencyID = 4225 },
    { isGate = true, spentAmountRequired = 5, traitCurrencyID = 3820 },
    { isGate = true, spentAmountRequired = 10, traitCurrencyID = 3820 } }, 3820), 10,
    "gate: the largest talent point gate")
-- Forever's Affliction tree: two of the top three a little lower, which read as a row, and the
-- second row then 61 rows down (305 points).
local nudged = {
    a = { y = 1000 }, b = { y = 1010 }, c = { y = 1010 },
    d = { y = 1600 }, e = { y = 1610 }, f = { y = 1600 },
    g = { y = 2200 }, h = { y = 4000 },
}
Plan.RowGates(nudged)
eq(nudged.b.req, 0, "row gates: a node nudged down stays in the top row")
eq(nudged.c.req, 0, "row gates: so does the other")
eq(nudged.d.req, 5, "row gates: the second row needs 5, not 305")
eq(nudged.e.req, 5, "row gates: a nudged node in the second row")
eq(nudged.g.req, 10, "row gates: the third row")
eq(nudged.h.req, 25, "row gates: rows left empty still count")
local single = { only = { y = 40 } }
Plan.RowGates(single, 3)
eq(single.only.req, 0, "row gates: one node is the top row")
local custom = { a = { y = 0 }, b = { y = 50 } }
Plan.RowGates(custom, 3)
eq(custom.b.req, 3, "row gates: points per row can be given")

-- Website links. The trees below stand in for the game's: each talent as "row col ranks
-- [prerequisite]", in link order, from wowforevertalents.com's data on 2026-11-11 (its talents
-- carry the game's node IDs), with talentsforever.com's Hunter Marksmanship, which lacks Improved
-- Serpent Sting. A node's ID is its tab * 100 + its place there.
local SITE_TREES = {
    WARRIOR = {
        { "0 0 3", "0 1 5", "0 2 3", "1 0 2", "1 1 3", "1 3 2", "2 1 1 5", "2 2 3 3", "3 0 1", "3 1 3",
            "3 2 2 8", "4 0 2", "4 1 1", "4 2 5", "5 0 2", "5 2 3", "6 1 1 13" },
        { "0 1 5", "0 2 5", "1 1 5", "1 2 5", "2 0 3", "2 1 1", "2 2 3", "2 3 5", "3 0 5", "3 1 1", "3 3 2",
            "4 0 2", "4 1 1", "4 2 2 7", "4 3 2", "5 0 2", "5 2 3", "6 1 1 13" },
        { "0 0 2", "0 1 5", "0 2 5", "1 0 5", "1 2 3", "1 3 3", "2 0 1", "2 1 2 2", "2 2 3", "2 3 3", "3 0 3",
            "3 1 1", "3 2 2", "4 0 2", "4 1 1", "4 2 3", "5 2 5", "6 1 1 15" },
    },
    MAGE = {
        { "0 0 2", "0 1 5", "0 2 3", "1 0 2", "1 1 2", "1 2 5", "1 3 2", "2 0 2", "2 1 3", "2 3 1", "3 0 2",
            "3 1 2", "3 2 3 6", "3 3 1 10", "4 1 1", "4 2 5", "5 2 3", "6 1 1 15" },
        { "0 1 5", "0 2 5", "1 0 5", "1 1 2", "1 2 3", "2 0 3", "2 1 3", "2 2 1", "2 3 2", "3 0 3", "3 1 2",
            "3 2 1 8", "3 3 3", "4 1 3", "4 2 1", "5 2 3", "6 1 1 14" },
        { "0 0 2", "0 1 5", "0 2 3", "1 0 5", "1 1 3", "1 2 2", "1 3 3", "2 0 3", "2 1 3", "2 2 1", "3 0 2",
            "3 1 1", "3 3 3", "4 0 3", "4 1 1", "4 2 2 10", "5 2 5", "6 1 1 15" },
    },
}
local HUNTER_BM = { "0 1 5", "0 2 5", "1 0 2", "1 1 3", "1 2 2", "2 0 2", "2 1 1", "2 2 5", "3 0 2", "3 2 5",
    "3 3 1", "4 0 2", "4 1 1 7", "4 3 2", "5 2 5 10", "6 1 1 13" }
local HUNTER_SV = { "0 1 5", "0 2 5", "1 0 5", "1 1 2", "1 2 5", "1 3 3", "2 0 2", "2 1 3", "2 2 1", "3 0 2",
    "3 1 5", "3 2 1 9", "4 0 2", "4 1 2", "4 2 2", "4 3 1", "5 2 5", "6 1 1 14" }
local MM_WFT = { "0 0 3", "0 1 5", "0 2 5", "1 0 3", "1 1 5", "1 2 5", "2 0 2", "2 1 5", "2 3 1", "3 1 1",
    "3 2 5 6", "3 3 5", "4 0 2 7", "4 2 3", "4 3 1", "5 2 5", "6 1 1 10" }
local MM_TF = { "0 0 3", "0 1 5", "0 2 5", "1 0 3", "1 1 5", "1 2 5", "2 0 2", "2 1 5", "2 3 1", "3 1 1",
    "3 2 5 6", "4 0 2 7", "4 2 3", "4 3 1", "5 2 5", "6 1 1 10" }

-- A tree as buildTree makes it, laid out like the game's: rows 80 apart, the second talent of
-- each tab's top row nudged 2 lower (as on Forever's Affliction tab), and nodes listed out of order.
local function siteTree(tabs)
    local tree = { nodes = {}, order = {}, tabList = {} }
    for t = #tabs, 1, -1 do
        tree.tabList[t] = { groupID = t * 10 }
        for i = #tabs[t], 1, -1 do
            local row, col, ranks, pre = string.match(tabs[t][i], "^(%d) (%d) (%d) ?(%d*)$")
            local id = t * 100 + i
            local node = { max = tonumber(ranks), tab = t * 10, prereqs = {},
                x = 300 * t + 60 * tonumber(col), y = 40 + 80 * tonumber(row) + (i == 2 and 2 or 0) }
            if pre ~= "" then
                node.prereqs[1] = { id = t * 100 + tonumber(pre), required = true }
            end
            tree.nodes[id] = node
            tree.order[#tree.order + 1] = id
        end
    end
    Plan.RowGates(tree.nodes)
    return tree
end

local warrior = siteTree(SITE_TREES.WARRIOR)
local mage = siteTree(SITE_TREES.MAGE)
local hunterTF = siteTree({ HUNTER_BM, MM_TF, HUNTER_SV })
local hunterWFT = siteTree({ HUNTER_BM, MM_WFT, HUNTER_SV })

local grid = Plan.Grid(warrior)
eq(grid[1].shape, "0305031213122123313332424145525361", "grid: Arms' shape")
eq(grid[1].ids[2], 102, "grid: a nudged node stays in its row's place")
eq(grid[3].ids[18], 318, "grid: Protection's last talent")

local function countsOf(picks)
    local counts = {}
    for _, id in ipairs(picks) do
        counts[id] = (counts[id] or 0) + 1
    end
    return counts
end

local function import(tree, text, class)
    local link, why = Plan.ParseLink(text)
    if not link then
        return nil, why
    end
    return Plan.FromLink(tree, link, class)
end

-- A popular Warrior build on talentsforever.com, opened there on 2026-11-11: Arms 3 Improved Heroic
-- Strike, 3 Improved Rend, 3 Improved Tactical Mastery, 2 Improved Overpower, 1 Anger Management,
-- 3 Deep Wounds, 2 Impale; Fury 5 Cruelty, 5 Unbridled Wrath, 3 Furious Precision, 5 Enrage, 5 Dual
-- Wield Specialization, 1 Reckless Swings, 2 Improved Execute, 1 Death Wish, 2 Improved Whirlwind,
-- 3 Flurry, 1 Bloodthirst.
local link = Plan.ParseLink("https://talentsforever.com/warrior/60/30303213002-050530055120100231--12")
eq(link and link.site, "talentsforever", "link: talentsforever")
eq(link and link.class, "WARRIOR", "link: class")
eq(link and link.level, 60, "link: level")
eq(link and link.version, "12", "link: numbering")
eq(link and link.order, nil, "link: no order")
local picks = Plan.FromLink(warrior, link, "WARRIOR")
eq(picks and #picks, 50, "link: 50 points")
eq(picks and select(3, Plan.Simulate(warrior, picks)), nil, "link: a valid order")
local got = countsOf(picks or {})
local want = { [101] = 3, [103] = 3, [105] = 3, [106] = 2, [107] = 1, [108] = 3, [111] = 2,
    [202] = 5, [204] = 5, [205] = 3, [208] = 5, [209] = 5, [210] = 1, [211] = 2, [213] = 1,
    [216] = 2, [217] = 3, [218] = 1 }
local same = true
for id in pairs(warrior.nodes) do
    same = same and (got[id] or 0) == (want[id] or 0)
end
eq(same, true, "link: every talent's ranks")
eq(picks and picks[1], 202, "link order: the tab with the most points, its top row first")
eq(picks and math.floor(picks[33] / 100), 2, "link order: all of Fury first")
eq(picks and picks[34], 101, "link order: then Arms from the top")

-- A Frost build on wowforevertalents.com, opened there on 2026-11-11: 5 Improved Frostbolt,
-- 3 Precision, 5 Ice Shards, 2 Improved Frost Nova.
link = Plan.ParseLink("https://wowforevertalents.com/mage/?t=h--053502")
eq(link and link.site, "wowforevertalents", "wft link: site")
eq(link and link.version, "h", "wft link: numbering")
eq(link and link.level, nil, "wft link: no level")
picks = Plan.FromLink(mage, link, "MAGE")
got = countsOf(picks or {})
eq(picks and #picks, 15, "wft link: 15 points")
eq(got[302] == 5 and got[303] == 3 and got[304] == 5 and got[306] == 2, true, "wft link: Frost's ranks")
eq(picks and picks[1], 302, "wft link: top row first")
eq(Plan.ParseLink("http://wowforevertalents.com/mage?t=h--053502&level=40").level, 40, "wft link: level")
eq(#import(mage, "www.wowforevertalents.com/mage/?private=1&t=h--053502", "MAGE"), 15,
    "wft link: t after another query")

-- talentsforever's order: B (Deflection) for 2 points, A (Improved Heroic Strike) for all 3, then B's
-- last; without the 2, B takes all 3 at once and the last B has none left (the site reads it the same).
eq(table.concat(import(warrior, "talentsforever.com/warrior/60/33---B2AB-12", "WARRIOR"), ","),
    "102,102,101,101,101,102", "order: runs")
eq(table.concat(import(warrior, "talentsforever.com/warrior/60/33---BAB-12", "WARRIOR"), ","),
    "102,102,102,101,101,101", "order: a run takes what's left")
-- D (Improved Charge, row 2) first breaks the rules, so the build gets an order of its own.
eq(table.concat(import(warrior, "talentsforever.com/warrior/60/3202---DAB-12", "WARRIOR"), ","),
    "101,101,101,102,102,104,104", "order: a bad one is replaced")
eq(#import(warrior, "talentsforever.com/warrior/60/33---1-2-3-B2AB-12", "WARRIOR"), 6,
    "order: after Legacy tabs")

-- Pasted with whatever came around it.
eq(#import(warrior, "  look: <https://www.talentsforever.com/warrior/60/33---B2AB-12?b=70888&d=261111>. ",
    "WARRIOR"), 6, "link: around other text, with a query")
eq(#import(warrior, "talentsforever.com/de/warrior/40/33---12", "WARRIOR"), 6, "link: another language")
eq(Plan.ParseLink("talentsforever.com/warrior/40/33---12").level, 40, "link: its level")

-- Refused.
eq(select(2, Plan.ParseLink("hello")), "bad", "refuse: not a link")
eq(select(2, Plan.ParseLink("talentsforever.com/warrior/60/3x---12")), "bad", "refuse: not digits")
eq(select(2, Plan.ParseLink("talentsforever.com/warrior/60/33-5-3")), "old", "refuse: the first links")
eq(select(2, Plan.ParseLink("wowforevertalents.com/mage/?t=hq")), "bad", "refuse: wft not digits")
eq(select(2, Plan.ParseLink("wowforevertalents.com/mage/?t=h1-2-3-4")), "bad", "refuse: wft four tabs")
eq(select(2, Plan.ParseLink("wowforevertalents.com/mage/")), "bad", "refuse: no build")
eq(select(2, import(warrior, "wowforevertalents.com/mage/?t=h--053502", "WARRIOR")), "class",
    "refuse: another class")
eq(select(2, import(warrior, "talentsforever.com/warrior/60/33---11", "WARRIOR")), "old",
    "refuse: an older numbering")
eq(select(2, import(warrior, "talentsforever.com/warrior/60/33---13", "WARRIOR")), "new",
    "refuse: a newer numbering")
eq(select(2, import(mage, "wowforevertalents.com/mage/?t=g--053502", "MAGE")), "old", "refuse: wft older")
eq(select(2, import(mage, "wowforevertalents.com/mage/?t=--053502", "MAGE")), "old", "refuse: wft first")
eq(select(2, import(mage, "wowforevertalents.com/mage/?t=i--053502", "MAGE")), "new", "refuse: wft newer")
eq(select(2, import(warrior, "talentsforever.com/warrior/60/9---12", "WARRIOR")), "rank",
    "refuse: more ranks than a talent has")
eq(select(2, import(warrior, "talentsforever.com/warrior/60/000000000000000000---12", "WARRIOR")), "tree",
    "refuse: more talents than the tab has")
local reason, total = select(2, import(warrior,
    "talentsforever.com/warrior/60/35323213132215231-555531355122122231--12", "WARRIOR"))
eq(reason, "points", "refuse: more than 51 points")
eq(total, 95, "refuse: and how many")
eq(select(2, import(warrior, "talentsforever.com/warrior/60/00000000000000001---12", "WARRIOR")), "rules",
    "refuse: Mortal Strike alone")
-- The sites' Marksmanship tabs differ, so each one's link reads only on the tab it was made for.
eq(#import(hunterTF, "talentsforever.com/hunter/60/-05--12", "HUNTER"), 5, "hunter: talentsforever's tab")
eq(select(2, import(hunterWFT, "talentsforever.com/hunter/60/-05--12", "HUNTER")), "tree",
    "hunter: talentsforever's link on the other tab")
eq(#import(hunterWFT, "wowforevertalents.com/hunter/?t=h-05", "HUNTER"), 5, "hunter: wowforevertalents' tab")
eq(select(2, import(hunterTF, "wowforevertalents.com/hunter/?t=h-05", "HUNTER")), "tree",
    "hunter: wowforevertalents' link on the other tab")
-- A tree a patch changed: one more rank in Arms' first talent.
local patched = siteTree(SITE_TREES.WARRIOR)
patched.nodes[101].max = 5
eq(select(2, import(patched, "talentsforever.com/warrior/60/33---12", "WARRIOR")), "tree",
    "refuse: a tree the link wasn't made on")
eq(Plan.SiteName(Plan.ParseLink("wowforevertalents.com/mage/?t=h")), "wowforevertalents.com", "site name")
