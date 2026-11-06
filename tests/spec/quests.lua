-- Quests: quest levels from the log, and which quest a quest window shows.
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
