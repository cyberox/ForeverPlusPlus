-- QuestStarts: who can pick a quest up, the index of quest starts by map, and grouping spots into
-- icons, against a made-up stand-in for ns.QuestieDB.
local T = ...
local ns, eq, same = T.ns, T.eq, T.same

-- A stand-in for Lib/QuestieDB.lua's readers, in our own shapes.
local ready = true
local reads = { quest = 0 }
local STARTERS = {
    [1] = { npcs = { 10 }, objects = {}, items = {} },
    [2] = { npcs = { 10, 11 }, objects = { 20 }, items = {} },
    [3] = { npcs = {}, objects = {}, items = { 30 } },
    [4] = { npcs = { 99 }, objects = {}, items = {} }, -- a giver without spawns
}
local SPAWNS = {
    Npc = {
        [10] = { list = { { uiMapID = 100, x = 0.5, y = 0.5 }, { uiMapID = 200, x = 0.1, y = 0.2 } }, side = "AH" },
        [11] = { list = { { uiMapID = 100, x = 0.7, y = 0.7 } }, side = "H" },
        [12] = { list = {}, side = "A" },
    },
    Object = { [20] = { list = { { uiMapID = 100, x = 0.3, y = 0.3 } } } },
}
-- A creature that drops a quest's item in more places than one map keeps.
SPAWNS.Npc[12].list = {}
for i = 1, 20 do
    SPAWNS.Npc[12].list[i] = { uiMapID = 300, x = i / 100, y = 0.5 }
end
ns.QuestieDB = {
    IsReady = function() return ready end,
    Ids = function() return { 1, 2, 3, 4 } end,
    Starters = function(id) return STARTERS[id] end,
    Spawns = function(kind, id)
        local found = SPAWNS[kind][id]
        if found then
            return found.list, {}, found.side
        end
    end,
    Item = function(id)
        return id == 30 and { npcDrops = { 12 }, objectDrops = { 20 } } or nil
    end,
    Quest = function(id)
        reads.quest = reads.quest + 1
        return STARTERS[id] and { id = id, name = "Quest " .. id } or nil
    end,
}
T.load("Lib/QuestStarts")
local S = ns.QuestStarts

-- The index ----------------------------------------------------------------------------------

ready = false
eq(S.Begin(), false, "queststarts: no build while QuestieDB can't be read")
eq(S.IsBuilt(), false, "queststarts: not built at first")
ready = true
eq(S.Begin(), true, "queststarts: a build starts")
eq(S.Step(2), false, "queststarts: not done after some of the quests")
same({ S.Progress() }, { 2, 4 }, "queststarts: progress part way")
eq(S.OnMap(300), nil, "queststarts: a later quest isn't in yet")
eq(S.Step(100), true, "queststarts: done once every quest is read")
eq(S.IsBuilt(), true, "queststarts: built")
same({ S.Progress() }, { 4, 4 }, "queststarts: progress when built")
eq(S.Begin() and S.Step(1), true, "queststarts: a second build changes nothing")

local here = S.OnMap(100)
table.sort(here, function(a, b)
    if a.quest ~= b.quest then
        return a.quest < b.quest
    end
    return a.x < b.x
end)
same(here, {
    { quest = 1, x = 0.5, y = 0.5, map = 100, kind = "npc", id = 10 },
    { quest = 2, x = 0.3, y = 0.3, map = 100, kind = "object", id = 20 },
    { quest = 2, x = 0.5, y = 0.5, map = 100, kind = "npc", id = 10 },
    { quest = 2, x = 0.7, y = 0.7, map = 100, kind = "npc", id = 11, side = "H" },
    { quest = 3, x = 0.3, y = 0.3, map = 100, kind = "object", id = 20, item = 30 },
}, "queststarts: a map's starts, a giver for both sides without a side")
eq(#S.OnMap(200), 2, "queststarts: a giver's other map")
eq(#S.OnMap(300), 12, "queststarts: one starter's spots on a map are capped")
eq(S.OnMap(300)[1].item, 30, "queststarts: an item's source carries the item")
same(S.GivenBy(10), { 1, 2 }, "queststarts: the quests an NPC gives")
eq(S.GivenBy(12), nil, "queststarts: a creature that only drops the item gives none")
eq(S.OnMap(999), nil, "queststarts: a map without starts")
local count = 0
for _ in S.Maps() do
    count = count + 1
end
eq(count, 3, "queststarts: every map with starts")

eq(S.Quest(1).name, "Quest 1", "queststarts: a quest")
S.Quest(1)
eq(reads.quest, 1, "queststarts: a quest is read once")
eq(S.Quest(77), nil, "queststarts: an unknown quest")
S.Quest(77)
eq(reads.quest, 2, "queststarts: an unknown quest is asked for once")

S.Reset()
eq(S.IsBuilt() or S.OnMap(100) ~= nil, false, "queststarts: reset forgets the index")

-- Who a quest is for -----------------------------------------------------------------------------

eq(S.RaceAllowed(nil, 1, "A") and S.RaceAllowed(0, 1, "A"), true, "queststarts: no race mask is anyone")
eq(S.RaceAllowed(1, 1, "A"), true, "queststarts: a race in the mask")
eq(S.RaceAllowed(1, 2, "H"), false, "queststarts: a race outside the mask")
eq(S.RaceAllowed(2 ^ 32, 95, "A"), true, "queststarts: an unlisted race by its side's bits")
eq(S.RaceAllowed(2 ^ 32, 96, "H"), false, "queststarts: an unlisted race of the other side")
eq(S.RaceAllowed(2 ^ 32 + 2 ^ 33, 2, "H"), false, "queststarts: a mask past 32 bits without a listed race")
eq(S.RaceAllowed(77, 95, nil), true, "queststarts: nothing known about the character lets it in")
eq(S.ClassAllowed(nil, 4) and S.ClassAllowed(8, nil), true, "queststarts: no class mask, or no class")
eq(S.ClassAllowed(8, 4), true, "queststarts: a class in the mask")
eq(S.ClassAllowed(8, 3), false, "queststarts: a class outside the mask")

eq(S.Kind({ sortID = 22 }), "seasonal", "queststarts: a holiday category")
eq(S.Kind({ sortID = 61, classes = 256 }), "class", "queststarts: a class category isn't a holiday")
eq(S.Kind({}, true), "dungeon", "queststarts: tagged a dungeon quest")
eq(S.Kind({ flags = 64 }), "dungeon", "queststarts: the raid flag")
eq(S.Kind({ flags = 8 }), "normal", "queststarts: another flag")
eq(S.Kind({ requiredSkill = { id = 186, value = 1 }, repeatable = true }), "profession",
    "queststarts: a profession quest before repeatable")
eq(S.Kind({ repeatable = true }), "repeatable", "queststarts: repeatable")

-- Check ------------------------------------------------------------------------------------------

local done, log, hide = {}, {}, {}
local skills, standings = {}, {}
local player = {
    level = 20, race = 1, class = 4, side = "A",
    completed = function(id) return done[id] end,
    inLog = function(id) return log[id] end,
    hidden = function(id) return hide[id] end,
    dungeon = function(id) return id == 500 end,
    skill = function(id) return skills[id] end,
    standing = function(id) return standings[id] end,
}
local function quest(fields)
    local q = { id = 100, level = 20, exclusiveTo = {}, prerequisites = { all = {}, any = {} } }
    for key, value in pairs(fields or {}) do
        q[key] = value
    end
    return q
end
local function check(fields, rules)
    return S.Check(quest(fields), player, rules)
end
local function verdict(fields, rules)
    return { check(fields, rules) }
end

same(verdict(), { true, "normal" }, "queststarts: a plain quest is available")
same(verdict(nil, { normal = false }), { false, "kind" }, "queststarts: a kind turned off")
same(verdict({ id = 500 }, { dungeon = false }), { false, "kind" }, "queststarts: the game's dungeon tag")
log[100] = true
same(verdict(), { false, "log" }, "queststarts: in the log")
log[100] = nil
done[100] = true
same(verdict(), { false, "completed" }, "queststarts: completed")
same(verdict({ repeatable = true }), { true, "repeatable" }, "queststarts: a repeatable one done before")
done[100] = nil
hide[100] = true
same(verdict(), { false, "hidden" }, "queststarts: hidden by the player")
hide[100] = nil

same(verdict({ races = 2 }), { false, "race" }, "queststarts: another race's")
same(verdict({ classes = 1 }), { false, "class" }, "queststarts: another class's")
same(verdict({ classes = 8 }), { true, "class" }, "queststarts: the character's class's")

done[101] = true
same(verdict({ exclusiveTo = { 101 } }), { false, "exclusive" }, "queststarts: an either-or quest done")
same(verdict({ next = 101 }), { false, "chain" }, "queststarts: the next step done")
same(verdict({ breadcrumbFor = 101 }), { false, "breadcrumb" }, "queststarts: what it leads to is done")
done[101] = nil
log[101] = true
same(verdict({ exclusiveTo = { 101 } }), { false, "exclusive" }, "queststarts: an either-or quest taken")
same(verdict({ parent = 101 }), { true, "normal" }, "queststarts: its parent is in the log")
log[101] = nil
same(verdict({ parent = 101 }), { false, "parent" }, "queststarts: its parent isn't in the log")

same(verdict({ prerequisites = { all = { 101, 102 }, any = {} } }), { false, "prerequisite" },
    "queststarts: earlier quests not done")
done[101] = true
same(verdict({ prerequisites = { all = { 101, 102 }, any = {} } }), { false, "prerequisite" },
    "queststarts: one of all not done")
same(verdict({ prerequisites = { all = { 101, 102 }, any = {} } }, { prerequisites = false }), { true, "normal" },
    "queststarts: earlier quests not checked")
same(verdict({ prerequisites = { all = { 101 }, any = { 102, 103 } } }), { false, "prerequisite" },
    "queststarts: none of any done")
done[103] = true
same(verdict({ prerequisites = { all = { 101 }, any = { 102, 103 } } }), { true, "normal" },
    "queststarts: all and one of any done")
done[101], done[103] = nil, nil

local mining = { requiredSkill = { id = 186, value = 50 } }
same(verdict(mining), { false, "skill" }, "queststarts: a profession the character lacks")
same(verdict(mining, { mySkills = false }), { true, "profession" }, "queststarts: any profession's quests")
skills[186] = 40
same(verdict(mining), { false, "skill" }, "queststarts: too little skill")
skills[186] = 50
same(verdict(mining), { true, "profession" }, "queststarts: enough skill")

local friendly = { minRep = { id = 55, value = 3000 } }
same(verdict(friendly), { true, "normal" }, "queststarts: a reputation the game doesn't answer for")
standings[55] = 2999
same(verdict(friendly), { false, "reputation" }, "queststarts: too little reputation")
same(verdict(friendly, { reputation = false }), { true, "normal" }, "queststarts: reputation not checked")
standings[55] = 3000
same(verdict(friendly), { true, "normal" }, "queststarts: enough reputation")
same(verdict({ maxRep = { id = 55, value = 3000 } }), { false, "reputation" }, "queststarts: too much reputation")

same(verdict({ maxLevel = 19 }), { false, "outleveled" }, "queststarts: past its highest level")
same(verdict({ requiredLevel = 21 }), { false, "level" }, "queststarts: a level short")
same(verdict({ requiredLevel = 22 }, { upcoming = 2 }), { true, "normal", "upcoming" },
    "queststarts: upcoming within the levels ahead")
same(verdict({ requiredLevel = 23 }, { upcoming = 2 }), { false, "level" }, "queststarts: too far ahead")
same(verdict({ level = 25 }, { highGap = 5 }), { false, "high" }, "queststarts: too far above")
same(verdict({ level = 24 }, { highGap = 5 }), { true, "normal" }, "queststarts: not too far above")
same(verdict({ level = 12 }, { lowGap = 8 }), { false, "low" }, "queststarts: low-level, hidden")
same(verdict({ level = 12 }, { lowGap = 8, low = "fade" }), { true, "normal", "low" }, "queststarts: low-level, faded")
same(verdict({ level = 12 }, { lowGap = 8, low = "show" }), { true, "normal" }, "queststarts: low-level, shown")
same(verdict({ level = 13 }, { lowGap = 8 }), { true, "normal" }, "queststarts: not low-level yet")
same(verdict({ level = -1 }, { lowGap = 8, highGap = 1 }), { true, "normal" }, "queststarts: a quest that scales")
same(verdict({ level = false }, { lowGap = 8 }), { true, "normal" }, "queststarts: a quest without a level")

-- Grouping -----------------------------------------------------------------------------------

local spots = {
    { x = 0.10, y = 0.10 }, { x = 0.11, y = 0.10 }, { x = 0.50, y = 0.50 }, { x = 0.51, y = 0.51 },
    { x = 0.90, y = 0.90 },
}
local groups = S.Cluster(spots, 0.04, 10)
eq(#groups, 3, "queststarts: nearby spots share a group")
eq(groups[1].point == spots[1] and groups[1].count == 2 and groups[3].count == 1, true,
    "queststarts: a group is its first spot and how many it stands for")
eq(#S.Cluster(spots, 0.04, 2), 2, "queststarts: at most the limit")
eq(#S.Cluster(spots, 0.001, 10), 5, "queststarts: a small radius keeps them apart")
eq(#S.Cluster({}, 0.04, 10), 0, "queststarts: no spots, no groups")

local entries = {
    { x = 0.5, y = 0.5, order = 2 }, { x = 0.505, y = 0.5, order = 1 }, { x = 0.8, y = 0.2, order = 3 },
}
local stacks = S.Stack(entries, 0.012, function(a, b) return a.order < b.order end)
eq(#stacks, 2, "queststarts: quests on one spot share a stack")
eq(stacks[1].x == 0.5 and #stacks[1].entries == 2 and stacks[1].entries[1].order == 1, true,
    "queststarts: a stack sits on its first entry, sorted")
eq(#S.Stack(entries, 0.001)[1].entries, 1, "queststarts: a small radius, and no order given")
