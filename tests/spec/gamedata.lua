-- GameData: seeds and what play teaches, the dungeon finder's instances, and gathering nodes.
local T = ...
local ns, eq = T.ns, T.eq

local GameData, Instances = ns.GameData, ns.Instances
local savedDB = ns.db
ns.db = nil -- before the saved variables load
local nodes = GameData.New("testNodes", { Peacebloom = { 182, 1 } })
eq(nodes:Get("Peacebloom")[2], 1, "game data: seed read")
eq(nodes:Get("Dreamfoil"), nil, "game data: unknown is nil")
eq(nodes:Learn("Dreamfoil", { 182, 270 }), true, "game data: learning something new changes it")
eq(nodes:Get("Dreamfoil")[2], 270, "game data: learned before login is kept in memory")
ns.db = {}
eq(nodes:Get("Dreamfoil")[2], 270, "game data: early learning moves to the saved table")
eq(ns.db.gameData.testNodes.values.Dreamfoil[2], 270, "game data: saved by set name")
eq(nodes:Learn("Dreamfoil", { 182, 270 }), false, "game data: learning the same is no change")
eq(nodes:Learn("Peacebloom", { 182, 5 }), true, "game data: learned overrides the seed")
eq(nodes:Get("Peacebloom")[2], 5, "game data: learned wins")
nodes:Learn("Peacebloom", { 182, 1 })
eq(ns.db.gameData.testNodes.values.Peacebloom, nil, "game data: learning the seed's value drops ours")
local seen = 0
for _ in nodes:Pairs() do
    seen = seen + 1
end
eq(seen, 2, "game data: pairs merges seed and learned")
eq(nodes:Learned(), 1, "game data: learned count")
GetBuildInfo = function()
    return "1.60.1", "70338", "Oct 1 2026", 16001
end
nodes:Learn("Silverleaf", { 182, 1 })
eq(ns.db.gameData.testNodes.build, "70338", "game data: learned data is tagged with the build")
GetBuildInfo = nil
ns.db.gameData.removedSet = { values = { x = 1 } }
GameData.Prune(ns.db)
eq(ns.db.gameData.removedSet, nil, "game data: a set the addon no longer makes is dropped")
eq(ns.db.gameData.testNodes.values.Silverleaf[2], 1, "game data: prune keeps sets still made")
local empty = GameData.New("testEmpty", { [1] = true })
eq(empty:Get(1), true, "game data: a set that learned nothing reads its seed")
eq(ns.db.gameData.testEmpty, nil, "game data: and saves nothing")
GameData.ForgetAll()
eq(nodes:Get("Dreamfoil"), nil, "game data: forget all")
eq(GameData.Spell(1804, "Pick Lock"), 1804, "game data: single ID passes through")
eq(GameData.Requires("Requires Herbalism (75)"), "Herbalism", "game data: requires skill")
eq(select(2, GameData.Requires("Requires Herbalism (75)")), 75, "game data: requires rank")
eq(GameData.Requires("Requires Level 20"), nil, "game data: other lines aren't requirements")
eq(select(3, GameData.TooltipRequires({ lines = { { leftText = "Requires Mining (1)" },
    { leftText = "|cffff2020Requires Mining (65)|r" } } })), 2,
    "game data: tooltip requirement skips the title and color codes")

-- Instances from the dungeon finder: { name, typeID, subtypeID, minLevel, maxLevel, maxRecLevel,
-- expansion, instance ID } by finder ID, spread into GetLFGDungeonInfo's order.
local finder = {
    [1] = { "The Deadmines", 1, 1, 18, 23, 23, 0, 36 },
    [2] = { "Blackrock Depths", 1, 1, 10, 60, 60, 0, 230 }, -- a whole bracket
    [3] = { "Drowned City", 1, 1, 40, 60, 45, 0, 3100 },
    [4] = { "Sunken Vault", 1, 3, 60, 60, 60, 0, nil },
    [5] = { "Random Classic Dungeon", 6, 1, 15, 60, 60, 0, nil },
    [6] = { "Retail Dungeon", 1, 1, 70, 80, 80, 10, 2600 },
}
GetLFDChoiceOrder = function()
    return { -1, 1, 2, 3, 4, 5, 6 }
end
GetLFGDungeonInfo = function(id)
    local d = finder[id]
    return d[1], d[2], d[3], d[4], d[5], nil, nil, d[6], d[7], nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, d[8]
end
local byKey = Instances.byKey
-- Levels as plain text, without the color for the player's level.
ns.Colors.LevelRange = function()
    return nil
end
eq(Instances.Levels(byKey.deadmines, true), "18-23", "finder: levels replace the seed's")
eq(Instances.Levels(byKey.brd, true), "52-60", "finder: a whole bracket keeps the seed's")
eq(ns.db.gameData.instances.values[36].low, 18, "finder: learned for the account")
eq(ns.db.gameData.instances.values[230], nil, "finder: the seed's levels aren't saved")
eq(Instances.ByName("drowned city"), byKey.lfg3100, "finder: adds a dungeon the seed lacks")
eq(Instances.Levels(byKey.lfg3100, true), "40-45", "finder: a new dungeon's levels")
eq(byKey.lfgd4 and byKey.lfgd4[5], true, "finder: a raid without an instance ID")
eq(Instances.ByName("Random Classic Dungeon"), nil, "finder: random dungeons are left out")
eq(Instances.ByName("Retail Dungeon"), nil, "finder: later expansions are left out")
GetLFDChoiceOrder, GetLFGDungeonInfo = nil, nil

-- Herbs and veins: the seed, and what tooltips and loot teach.
local Professions = ns.Professions
eq(Professions.Node("Peacebloom")[3], 2447, "nodes: seed read")
eq(Professions.GatheringLine("Mining"), Professions.MINING, "nodes: English skill name")
eq(Professions.GatheringLine("Skinning"), nil, "nodes: not a gathering line")
eq(Professions.IsTool(2901, 2, 14), true, "tools: Mining Pick from the seed")
eq(Professions.IsTool(99999, 2, 20), true, "tools: any fishing pole")
eq(Professions.IsTool(99999, 2, 7), false, "tools: a sword isn't one")
eq(Professions.LearnRequirement("Friedenskraut", "Herbalism", 1), true, "nodes: learn a new name")
eq(Professions.Node("Friedenskraut")[1], Professions.HERBALISM, "nodes: learned skill line")
eq(Professions.Node("Friedenskraut")[3], nil, "nodes: learned without an item")
eq(Professions.LearnRequirement("Friedenskraut", "Herbalism", 1), false, "nodes: same again is no change")
eq(Professions.LearnRequirement("Copper Vein", "Mining", 1), false, "nodes: seed's requirement isn't saved")
eq(Professions.LearnNodeItem("Friedenskraut", 2447), true, "nodes: learn its item")
eq(Professions.Node("Friedenskraut")[2], 1, "nodes: item keeps the skill")
eq(Professions.LearnNodeItem("Copper Vein", 2835), false, "nodes: a known item stays")
eq(Professions.LearnRequirement("Copper Vein", "Mining", 5), true, "nodes: a changed requirement wins")
eq(Professions.Node("Copper Vein")[3], 2770, "nodes: and keeps the seed's item")
local function itemSkill(id)
    local line, skill = Professions.ItemSkill(id)
    return line and (line .. ":" .. skill) or "nil"
end
eq(itemSkill(2770), Professions.MINING .. ":5", "items: a learned requirement reaches the item")
Professions.ForgetNodes()
eq(Professions.Node("Friedenskraut"), nil, "nodes: forget")
eq(Professions.Node("Copper Vein")[2], 1, "nodes: forget restores the seed")
-- A kind of a known node ("Poor Copper Vein") takes what it lacks from that one.
eq(Professions.Node("Poor Copper Vein")[3], 2770, "nodes: a kind of a vein gets its item")
eq(Professions.Node("Poor Copper Vein")[1], Professions.MINING, "nodes: and its skill line")
eq(Professions.Node("Ooze Covered Silver Vein")[3], 2775, "nodes: a known name is read as itself")
eq(Professions.Node("Copper Veins"), nil, "nodes: a name only beginning like one isn't a kind of it")
eq(Professions.Node("Vein"), nil, "nodes: a shorter name isn't a kind of one")
Professions.LearnRequirement("Poor Copper Vein", "Mining", 10)
eq(Professions.Node("Poor Copper Vein")[2] .. ":" .. Professions.Node("Poor Copper Vein")[3], "10:2770",
    "nodes: its own skill learned, with the item it's a kind of")
Professions.ForgetNodes()
eq(itemSkill(2447), Professions.HERBALISM .. ":1", "items: herb")
eq(itemSkill(10620), Professions.MINING .. ":245", "items: the lowest vein that gives it")
eq(itemSkill(2835), Professions.MINING .. ":1", "items: a stone")
eq(itemSkill(2589), "nil", "items: not gathered")
ns.db = savedDB
