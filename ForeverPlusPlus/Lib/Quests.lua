-- Which quest Blizzard's quest windows show, and its level from the quest log, for the quest
-- modules that tag or mark quest titles. The window functions are read when called, since some
-- (the greeting's level functions) are Classic's and may be gone on a patch. Probe each.
local _, ns = ...

local select, type = select, type

local Quests = {}
ns.Quests = Quests

---The quest the map and the game's arrow follow (the super-tracked one, picked by clicking it in
---the tracker), or nil with none, while the game hides it, or on a client without it.
---@return number? questID
function Quests.Selected()
    local track = C_SuperTrack
    if not (track and track.GetSuperTrackedQuestID) then
        return nil
    end
    local questID = track.GetSuperTrackedQuestID()
    if ns.IsNumber(questID) and questID ~= 0 then
        return questID
    end
    return nil
end

---The quest's level as the quest log has it, or nil while the log doesn't have it (or the quest
---isn't in it).
---@param questID number?
---@return number?
function Quests.Level(questID)
    local log = C_QuestLog
    if not (questID and log and log.GetLogIndexForQuestID) then
        return nil
    end
    local index = log.GetLogIndexForQuestID(questID)
    local info = index and log.GetInfo(index)
    local level = info and (info.difficultyLevel or info.level)
    if type(level) == "number" and level > 0 then
        return level
    end
end

---The level a quest counts as, for its tag and its difficulty color: the game's own for a quest it
---knows, then the quest log's, then `fallback` (what another source says, such as QuestieDB).
---@param questID number?
---@param fallback? number
---@return number?
function Quests.DifficultyLevel(questID, fallback)
    local log = C_QuestLog
    local level = questID and log and log.GetQuestDifficultyLevel and log.GetQuestDifficultyLevel(questID)
    if type(level) == "number" and level > 0 then
        return level
    end
    return Quests.Level(questID) or fallback
end

---A quest's title as the game has it, or `fallback` while it doesn't (a quest not seen yet).
---@param questID number?
---@param fallback? string
---@return string?
function Quests.Title(questID, fallback)
    local log = C_QuestLog
    local title = questID and log and log.GetTitleForQuestID and log.GetTitleForQuestID(questID)
    if ns.IsText(title, true) then
        return title
    end
    return fallback
end

---Whether a quest is an elite (group) one, as Forever's quest log marks with a + after the level.
---C_QuestLog.IsEliteQuest is what Blizzard's own tag asks (Camelot's QuestUtilsOverrides); the
---quest's tag is asked too, for a quest that one doesn't answer for. Probe both.
---@param questID number?
---@return boolean
function Quests.IsElite(questID)
    local log = C_QuestLog
    if not (type(questID) == "number" and log) then
        return false
    end
    if log.IsEliteQuest and log.IsEliteQuest(questID) == true then
        return true
    end
    local tag = log.GetQuestTagInfo and log.GetQuestTagInfo(questID)
    local elite = Constants and Constants.QuestConsts and Constants.QuestConsts.QUEST_INFO_ELITE_ID
    return type(tag) == "table" and elite ~= nil and tag.tagID == elite
end

local tags = {} -- quest ID -> its tag's ID, once the client has answered

---The client's tag for a quest (`C_QuestLog.GetQuestTagInfo`'s `tagID`: 81 Dungeon, 62 Raid, 41
---PvP, 1 Group, and so on), or nil while the client hasn't said: it knows only quests it has
---cached. An answer is kept, so a quest is asked about until the client knows it, then never again.
---@param questID number?
---@return number? tagID
function Quests.Tag(questID)
    if type(questID) ~= "number" then
        return nil
    end
    local known = tags[questID]
    local log = C_QuestLog
    if known == nil and log and log.GetQuestTagInfo then
        local tag = log.GetQuestTagInfo(questID)
        if type(tag) == "table" and ns.IsNumber(tag.tagID) then
            known = tag.tagID
            tags[questID] = known
        end
    end
    return known
end

---A quest's level as the quest log writes it before a title: "[12]", or "[12+]" for an elite quest.
---@param questID number?
---@param level number
---@return string
function Quests.LevelTag(questID, level)
    return "[" .. level .. (Quests.IsElite(questID) and "+" or "") .. "]"
end

---The quest in the details pane. QuestInfo_Display fills it for a quest giver's offer and reward,
---and for the quest log on the map, where it's the log's selected quest.
---@return number?
function Quests.DetailsID()
    if QuestInfoFrame and QuestInfoFrame.questLog then
        return C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest()
    end
    return GetQuestID and GetQuestID()
end

---The quest giver's quest, in the window that asks for its items before you turn it in.
---@return number?
function Quests.GiverID()
    return GetQuestID and GetQuestID()
end

---A title button in a quest giver's older greeting list: its quest ID, and its level while the
---client still has the old index functions. Active quests come first; each button's ID is its
---place in its own list.
---@param button table
---@return number? questID
---@return number? level
function Quests.GreetingButton(button)
    local index = button:GetID()
    if button.isActive == 1 then
        return GetActiveQuestID and GetActiveQuestID(index),
            GetActiveLevel and GetActiveLevel(index)
    end
    return GetAvailableQuestInfo and (select(5, GetAvailableQuestInfo(index))),
        GetAvailableLevel and GetAvailableLevel(index)
end
