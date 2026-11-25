-- Quest Tracker's additions to the header of the tracker's Quests section (QuestObjectiveTracker's
-- Header, Blizzard's ObjectiveTrackerModuleHeaderTemplate): the quest count beside its collapse
-- button. Everything here is a region or frame of our own on that header; nothing of Blizzard's is
-- moved, resized, or written to. QuestTracker.lua turns it on and off.
local _, ns = ...

local type = type
local C_QuestLog, Constants = C_QuestLog, Constants

local module = ns.modules.QuestTracker
local internal = module.internal

---The Quests section's header, or nil on a client whose tracker isn't built this way.
---@return table?
local function header()
    local section = QuestObjectiveTracker
    local frame = type(section) == "table" and section.Header
    return type(frame) == "table" and frame.CreateFontString and frame or nil
end

-- Quest count -------------------------------------------------------------------------------------
-- "12/25": the quests in the log against how many it holds, the numbers Forever's quest log shows
-- above its list (QuestLogQuests_ShowQuestCount, Camelot/QuestMapFrameUtils.lua on the forever
-- branch). In the header's own font, at the right beside the collapse button, and red once the
-- log is full.

local COUNT_GAP = 6 -- pixels between the count and the collapse button
local count -- our font string on the header, made the first time it's needed

-- How many quests the log holds: Blizzard's constant, as the quest log reads it.
local function questLimit()
    local consts = Constants and Constants.QuestLogConsts
    local limit = consts and consts.MAXIMUM_NUM_QUESTS_LOG_CAN_ACCEPT
    if type(limit) ~= "number" and C_QuestLog.GetMaxNumQuestsCanAccept then
        limit = C_QuestLog.GetMaxNumQuestsCanAccept()
    end
    return type(limit) == "number" and limit > 0 and limit or nil
end

local function updateCount()
    local frame = header()
    if not (module.enabled and module.db.count and frame) then
        if count then
            count:Hide()
        end
        return
    end
    local _, quests = C_QuestLog.GetNumQuestLogEntries()
    local limit = questLimit()
    if type(quests) ~= "number" or not limit then
        if count then
            count:Hide()
        end
        return
    end
    if not count then
        count = frame:CreateFontString(nil, "ARTWORK", "ObjectiveTrackerHeaderFont")
        count:SetJustifyH("RIGHT")
        if frame.MinimizeButton then
            count:SetPoint("RIGHT", frame.MinimizeButton, "LEFT", -COUNT_GAP, 0)
        else
            count:SetPoint("RIGHT", frame, "RIGHT", -COUNT_GAP, 0)
        end
    end
    count:SetFormattedText("%d/%d", quests, limit)
    if quests >= limit and RED_FONT_COLOR then
        count:SetTextColor(RED_FONT_COLOR:GetRGB())
    elseif frame.Text and frame.Text.GetTextColor then
        count:SetTextColor(frame.Text:GetTextColor()) -- the header's own color, whatever it is
    end
    count:Show()
end

local requestCount = ns.Frames.Coalesce(updateCount, nil, module)

module:OnWhile("count", { QUEST_LOG_UPDATE = requestCount })

-- For QuestTracker.lua -----------------------------------------------------------------------------

---Shows or hides what the header gets, as the module or one of these options turns on or off.
function internal.updateHeader()
    updateCount()
end
