-- Quest Pins' rules: every reason a quest's pin shows or hides, from made-up quests as Index.lua
-- would have read them from QuestieDB. The module's own file is loaded onto a stand-in module, so
-- these are its real rules; nothing here needs QuestieDB or a frame.
local T = ...
local ns, eq, same, player = T.ns, T.eq, T.same, T.player

-- The player: a level 30 Horde orc (race 2) warrior (class 1), unless a case changes it.
local me = { race = 2, class = 1 }
UnitRace = function() return "Orc", "Orc", me.race end
UnitClass = function() return "Warrior", "WARRIOR", me.class end

local done, inLog = {}, {}
local db = {
    hidden = {},
    normal = true, repeatable = true, class = true, profession = true, dungeon = true, holiday = true,
    warEffort = true, warEffortAlways = false,
    low = "hide", lowGap = 6, hideHigh = true, highGap = 5,
    upcoming = true, upcomingLevels = 3, reputation = true,
}
local info = {}
local internal = {
    info = info,
    Done = function(id) return done[id] == true end,
    InLog = function(id) return inLog[id] == true end,
}
ns.modules = { QuestPins = { internal = internal, db = db } }
-- The quest log, for the war effort's "seen one" rule.
local logged = {}
C_QuestLog = {
    GetNumQuestLogEntries = function() return #logged end,
    GetInfo = function(i) return logged[i] end,
}
T.load("Modules/Quests/QuestPins/Rules", ns)

-- Starts each case from a plain quest at the player's level.
local function quest(id, fields)
    local entry = { level = 30, required = 25, npcGiver = true }
    for key, value in pairs(fields or {}) do
        entry[key] = value
    end
    info[id] = entry
    return id
end
local function check(id)
    return { internal.Check(id) }
end

same(check(999), { false, "unknown" }, "rules: a quest the index doesn't have")
same(check(quest(1)), { true }, "rules: a plain quest at the player's level shows")

-- Already dealt with.
done[2] = true
same(check(quest(2)), { false, "done" }, "rules: turned in")
inLog[3] = true
same(check(quest(3)), { false, "log" }, "rules: in the quest log")
db.hidden[4] = true
same(check(quest(4)), { false, "hidden" }, "rules: hidden by the player")
db.hidden[4] = nil

-- Kinds, each by its own checkbox.
eq(internal.Category(quest(10)), "normal", "kind: a plain quest")
eq(internal.Category(quest(11, { repeatable = true })), "repeatable", "kind: repeatable")
eq(internal.Category(quest(12, { classes = 1 })), "class", "kind: a class quest")
eq(internal.Category(quest(13, { skill = 186 })), "profession", "kind: a profession quest")
eq(internal.Category(quest(14, { raid = true })), "instance", "kind: a raid quest by QuestieDB's flag")
eq(internal.Category(quest(15, { sort = 22 })), "holiday", "kind: a holiday's category")
eq(internal.Category(quest(16, { sort = 365 })), "war", "kind: the war effort's category")
eq(internal.Category(quest(17, { sort = 22, classes = 1 })), "holiday", "kind: holiday comes first")
eq(internal.Category(998), "normal", "kind: an unknown quest is plain")
for _, case in ipairs({ { 10, "normal" }, { 11, "repeatable" }, { 12, "class" }, { 14, "dungeon" },
    { 15, "holiday" } }) do
    local id, option = case[1], case[2]
    db[option] = false
    same(check(id), { false, "kind" }, "rules: " .. option .. " quests off")
    db[option] = true
    same(check(id), { true }, "rules: " .. option .. " quests on")
end
-- The client's own tag says a quest is a dungeon's, over QuestieDB's flag.
C_QuestLog.GetQuestTagInfo = function(id) return id == 18 and { tagID = 81 } or id == 19 and { tagID = 1 } or nil end
eq(internal.Category(quest(18)), "instance", "kind: a dungeon quest by the client's tag")
eq(internal.Category(quest(19, { raid = true })), "normal", "kind: the client's tag over QuestieDB's flag")
C_QuestLog.GetQuestTagInfo = nil

-- The war effort: only once one of its quests has been seen, unless Always Show is on.
same(check(16), { false, "war effort" }, "rules: the war effort before any of it is seen")
db.warEffortAlways = true
same(check(16), { true }, "rules: the war effort with Always Show")
db.warEffortAlways = false
quest(20, { sort = 365 })
logged[1] = { isHeader = true }
logged[2] = { questID = 20 }
internal.NoteWarEffort()
same(check(16), { true }, "rules: the war effort once one of its quests is in the log")
db.warEffort = false
same(check(16), { false, "war effort" }, "rules: the war effort turned off")
db.warEffort = true

-- Quests that shut each other out, and breadcrumbs.
done[31] = true
same(check(quest(30, { exclusive = { 31 } })), { false, "taken" }, "rules: the other of a pair was done")
same(check(quest(32, { exclusive = { 33 } })), { true }, "rules: the other of a pair wasn't")
done[35] = true
same(check(quest(34, { breadcrumbFor = 35 })), { false, "taken" }, "rules: a breadcrumb to a quest that's done")
inLog[37] = true
same(check(quest(36, { breadcrumbFor = 37 })), { false, "taken" }, "rules: a breadcrumb to a quest begun")
same(check(quest(38, { breadcrumbFor = 39 })), { true }, "rules: a breadcrumb still worth taking")

-- Prerequisites.
quest(40)
same(check(quest(41, { all = { 40 } })), { false, "prerequisite" }, "rules: a prerequisite not done")
done[40] = true
same(check(41), { true }, "rules: a prerequisite done")
quest(42)
quest(43)
done[43] = true
same(check(quest(44, { any = { 42, 43 } })), { true }, "rules: any one of several done")
done[43] = nil
same(check(44), { false, "prerequisite" }, "rules: none of several done")
-- A breadcrumb counts as done: it can be skipped.
quest(45, { breadcrumbFor = 46 })
same(check(quest(46, { all = { 45 } })), { true }, "rules: a breadcrumb prerequisite counts as met")
-- A quest no NPC gives (an item starts it) counts once its own prerequisites are met.
quest(47)
quest(48, { npcGiver = false, all = { 47 } })
same(check(quest(49, { all = { 48 } })), { false, "prerequisite" }, "rules: an item's quest whose own isn't met")
done[47] = true
same(check(49), { true }, "rules: an item's quest whose own prerequisite is met")
inLog[48] = true
same(check(49), { false, "prerequisite" }, "rules: an item's quest the player is in the middle of")
inLog[48] = nil
-- A quest no NPC gives with nothing before it doesn't count by itself.
quest(50, { npcGiver = false })
same(check(quest(51, { all = { 50 } })), { false, "prerequisite" }, "rules: an item's quest with no prerequisites")
-- Two that need each other: no endless walk, and neither is met.
quest(52, { npcGiver = false, all = { 53 } })
quest(53, { npcGiver = false, all = { 52 } })
same(check(quest(54, { all = { 52 } })), { false, "prerequisite" }, "rules: a circle of prerequisites ends")
same(check(quest(55, { all = { 997 } })), { false, "prerequisite" }, "rules: a prerequisite the index doesn't have")

-- Race: the race ID's bit for Classic's eight.
same(check(quest(60, { races = 2 })), { true }, "rules: an orc's quest (bit 2)")
same(check(quest(61, { races = 1 })), { false, "race" }, "rules: a human's quest")
same(check(quest(62, { races = 2 + 16 + 32 + 128 })), { true }, "rules: a Horde races mask")
-- A Skyborne (95 Alliance, 96 Horde) by its own bit, 33 or 34, and nothing else.
me.race = 96
same(check(quest(63, { races = 2 ^ 33 })), { true }, "rules: a Horde Skyborne by bit 34")
same(check(quest(64, { races = 2 ^ 32 })), { false, "race" }, "rules: a Horde Skyborne against bit 33")
same(check(60), { false, "race" }, "rules: an orc's quest isn't a Horde Skyborne's")
same(check(62), { false, "race" }, "rules: nor one for every Classic Horde race without bit 34")
same(check(quest(66, { races = 2 + 16 + 32 + 128 + 2 ^ 33 })), { true }, "rules: the whole Horde's mask, as QuestieDB has it")
same(check(61), { false, "race" }, "rules: a Horde Skyborne against an Alliance mask")
me.race = 95
same(check(64), { true }, "rules: an Alliance Skyborne by bit 33")
same(check(quest(65, { races = 4 })), { false, "race" }, "rules: a dwarf's quest isn't an Alliance Skyborne's")
same(check(quest(67, { races = 8 + 2 ^ 32 })), { true }, "rules: a class quest shared with night elves (QuestieDB's 4294967304)")
same(check(quest(68, { races = 2 ^ 32 + 2 ^ 33 })), { true }, "rules: a quest for both Skyborne")
player.faction = nil
same(check(64), { true }, "rules: a Skyborne's quests don't wait on the side being known")
same(check(65), { false, "race" }, "rules: nor does hiding another race's")
player.faction = "Horde"
me.race = 70
same(check(61), { true }, "rules: a race the masks have no bit for keeps the quest shown")
me.race = 2

-- Class.
same(check(quest(70, { classes = 1 })), { true }, "rules: a warrior's quest")
same(check(quest(71, { classes = 2 })), { false, "class" }, "rules: a paladin's quest")
same(check(quest(72, { classes = 1 + 4 })), { true }, "rules: a mask of two classes")

-- Profession skill.
GetProfessions, GetProfessionInfo = function() end, function() end
local ranks = {}
local realRank = ns.Professions.Rank
ns.Professions.Rank = function(line) return ranks[line] end
same(check(quest(75, { skill = 186, skillValue = 100 })), { false, "skill" }, "rules: without the profession")
ranks[186] = 99
same(check(75), { false, "skill" }, "rules: one point short")
ranks[186] = 100
same(check(75), { true }, "rules: exactly the skill needed")
GetProfessions = nil
ranks[186] = nil
same(check(75), { true }, "rules: a client that can't say keeps the quest shown")
ns.Professions.Rank = realRank

-- Level: too high for the quest, not there yet, and upcoming.
same(check(quest(80, { max = 29 })), { false, "level" }, "rules: past the quest's highest level")
same(check(quest(81, { max = 30 })), { true }, "rules: at the quest's highest level")
same(check(quest(82, { required = 33, level = 33 })), { true, "upcoming" }, "rules: three levels short, shown ahead")
same(check(quest(83, { required = 34, level = 34 })), { false, "level" }, "rules: four levels short")
db.upcoming = false
same(check(82), { false, "level" }, "rules: upcoming quests off")
db.upcoming = true

-- Reputation: at least the lowest, under the highest. No answer keeps the quest shown.
local standings = {}
C_Reputation = { GetFactionDataByID = function(id) return standings[id] and { currentStanding = standings[id] } end }
quest(85, { minRep = { id = 59, value = 3000 } })
same(check(85), { true }, "rules: a faction the game doesn't answer for")
standings[59] = 2999
same(check(85), { false, "reputation" }, "rules: under the reputation needed")
standings[59] = 3000
same(check(85), { true }, "rules: exactly the reputation needed")
quest(86, { maxRep = { id = 59, value = 3000 } })
same(check(86), { false, "reputation" }, "rules: at the highest reputation allowed")
standings[59] = 2999
same(check(86), { true }, "rules: under the highest reputation allowed")
db.reputation = false
standings[59] = 0
same(check(85), { true }, "rules: the reputation check off")
db.reputation = true
C_Reputation = nil

-- Low-level quests: hidden, faded, or as usual, from Low Gap levels under the player.
same(check(quest(90, { level = 24, required = 20 })), { false, "low" }, "rules: six levels under, hidden")
same(check(quest(91, { level = 25, required = 20 })), { true }, "rules: five levels under shows")
db.low = "fade"
same(check(90), { true, "low" }, "rules: six levels under, faded")
db.low = "off"
same(check(90), { true }, "rules: low-level quests as usual")
db.low = "hide"

-- Quests far over the player's level.
same(check(quest(92, { level = 35, required = 28 })), { false, "high" }, "rules: five levels over, hidden")
same(check(quest(93, { level = 34, required = 28 })), { true }, "rules: four levels over shows")
db.hideHigh = false
same(check(92), { true }, "rules: high-level quests shown")
db.hideHigh = true
-- A quest with no level is neither low nor high.
info[94] = { npcGiver = true }
same(check(94), { true }, "rules: a quest with no level shows")

-- The level and title a pin writes.
eq(internal.Level(1), 30, "level: QuestieDB's when the game has none")
eq(internal.Level(999), nil, "level: an unknown quest")
eq(internal.RequiredLevel(82), 33, "level: what an upcoming quest waits for")
C_QuestLog.GetTitleForQuestID = function(id) return id == 1 and "A Grim Task" or nil end
eq(internal.Title(1), "A Grim Task", "title: the game's")

-- Givers friendly to one side or both.
eq(internal.FriendlyToPlayer(nil), true, "giver: no side said")
eq(internal.FriendlyToPlayer("H"), true, "giver: the player's side")
eq(internal.FriendlyToPlayer("A"), false, "giver: the other side")
eq(internal.FriendlyToPlayer("AH"), true, "giver: both sides")
