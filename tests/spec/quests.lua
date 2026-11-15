-- Quests: quest levels, titles, and elite tags, which quest a quest window shows, and the quest
-- the map follows.
local T = ...
local ns, eq = T.ns, T.eq

do
    local Quests = ns.Quests
    local log = { [101] = { level = 12 }, [102] = { level = 20, difficultyLevel = 22 },
        [103] = { level = 0 } }
    local order = { 101, 102, 103 }
    C_QuestLog = {
        GetLogIndexForQuestID = function(id)
            for i, questID in ipairs(order) do
                if questID == id then
                    return i
                end
            end
        end,
        GetInfo = function(index) return log[order[index]] end,
        GetSelectedQuest = function() return 102 end,
    }
    GetQuestID = function() return 201 end
    eq(Quests.Level(101), 12, "quests: level from the log")
    eq(Quests.Level(102), 22, "quests: difficulty level first")
    eq(Quests.Level(103), nil, "quests: level 0 is unknown")
    eq(Quests.Level(999), nil, "quests: not in the log")
    eq(Quests.Level(nil), nil, "quests: no quest")
    eq(Quests.DifficultyLevel(101), 12, "quests: the log's level when the game gives no difficulty level")
    eq(Quests.DifficultyLevel(999, 30), 30, "quests: the fallback for a quest the game doesn't know")
    eq(Quests.DifficultyLevel(nil, 30), 30, "quests: and for no quest")
    C_QuestLog.GetQuestDifficultyLevel = function(id) return id == 101 and 14 or 0 end
    eq(Quests.DifficultyLevel(101, 30), 14, "quests: the game's difficulty level first")
    eq(Quests.DifficultyLevel(999, 30), 30, "quests: a difficulty level of 0 is unknown")
    C_QuestLog.GetQuestDifficultyLevel = nil
    eq(Quests.Title(101, "Quest 101"), "Quest 101", "quests: the fallback title without the game's")
    C_QuestLog.GetTitleForQuestID = function(id) return id == 101 and "A Grim Task" or "" end
    eq(Quests.Title(101, "x"), "A Grim Task", "quests: the game's title")
    eq(Quests.Title(999, "x"), "x", "quests: an empty title is none")
    eq(Quests.LevelTag(101, 12), "[12]", "quests: a plain quest's tag")
    C_QuestLog.IsEliteQuest = function(id) return id == 102 end
    eq(Quests.LevelTag(102, 22), "[22+]", "quests: an elite quest's tag has a +")
    eq(Quests.IsElite(101), false, "quests: not elite")
    Constants = { QuestConsts = { QUEST_INFO_ELITE_ID = 1 } }
    C_QuestLog.GetQuestTagInfo = function(id) return id == 103 and { tagID = 1 } or nil end
    eq(Quests.IsElite(103), true, "quests: elite by its tag")
    eq(Quests.IsElite(nil), false, "quests: no quest isn't elite")
    QuestInfoFrame = { questLog = true }
    eq(Quests.DetailsID(), 102, "quests: details from the quest log")
    QuestInfoFrame.questLog = nil
    eq(Quests.DetailsID(), 201, "quests: details from the quest giver")
    eq(Quests.GiverID(), 201, "quests: the quest giver's quest")
    GetActiveQuestID = function(i) return 300 + i end
    GetActiveLevel = function(i) return 10 + i end
    GetAvailableQuestInfo = function(i) return false, 0, false, false, 400 + i end
    GetAvailableLevel = nil
    local function button(id, active)
        return { isActive = active, GetID = function() return id end }
    end
    local id, level = Quests.GreetingButton(button(2, 1))
    eq(id == 302 and level == 12, true, "quests: an active greeting quest")
    id, level = Quests.GreetingButton(button(3, 0))
    eq(id == 403 and level == nil, true, "quests: an available one without the level function")
end

do
    -- The quest the map follows: none is 0, and the game may hide it.
    local Quests = ns.Quests
    T.game.secret = "<secret>"
    C_SuperTrack = nil
    eq(Quests.Selected(), nil, "selected: nil on a client without it")
    local tracked
    C_SuperTrack = { GetSuperTrackedQuestID = function() return tracked end }
    tracked = 0
    eq(Quests.Selected(), nil, "selected: 0 is no quest")
    tracked = 783
    eq(Quests.Selected(), 783, "selected: the quest followed")
    tracked = T.game.secret
    eq(Quests.Selected(), nil, "selected: nil while the game hides it")
    tracked = nil
    eq(Quests.Selected(), nil, "selected: nil with no answer")
    T.game.secret = nil
end
