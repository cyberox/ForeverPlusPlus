-- Quest Levels: puts a quest's level before its name, "[12] Title", the way Forever's quest log and
-- tracker show it, where Blizzard shows only the name: a quest giver's list (the gossip window
-- most NPCs use and the older greeting window) and the title of a quest's details (in the quest
-- window and on the map). Checked in wow-ui-source's forever branch: GossipFrameShared.lua,
-- QuestFrame.lua, and QuestInfo.lua.
--
-- The tag is Blizzard's own, QuestUtilsOverrides.GetQuestTitlePrefix: on Forever (Camelot) that's
-- "[12] ", with a + for elite quests. Blizzard measures a greeting row's height before it sets the
-- title, so a title the tag pushes onto another line can crowd the row below.
--
-- Color by Difficulty colors only the tag we add, with Blizzard's GetQuestDifficultyColor (the
-- quest log's gray through red); Blizzard's prefix function and its other callers are untouched.
local _, ns = ...

local type, sub = type, string.sub
local GetQuestDifficultyColor = GetQuestDifficultyColor

local L = ns.L
local Colors = ns.Colors
local Quests = ns.Quests

local module = ns.NewModule("QuestLevels", L.QUESTLEVELS_DESC, { enabled = true, color = false })
module.title = L.QUESTLEVELS_TITLE
module.category = "quests"
module.added = "0.9.0"
module.options = {
    { key = "color", name = L.QUESTLEVELS_COLOR, description = L.QUESTLEVELS_COLOR_DESC },
}

-- What a tag looks like, plain or colored, to take ours off a title again.
local TAG_PATTERN = "^%[%d+%+?%] "
local COLORED_TAG_PATTERN = "^|c%x%x%x%x%x%x%x%x%[%d+%+?%]|r "

-- A title without our tag.
local function untagged(text)
    return (text:gsub(TAG_PATTERN, ""):gsub(COLORED_TAG_PATTERN, ""))
end

-- Blizzard's tag in the color of the quest's level against the player's, with the space after it
-- left uncolored. Probe: GetQuestDifficultyColor is FrameXML's.
local function colorTag(prefix, level)
    local color = GetQuestDifficultyColor and GetQuestDifficultyColor(level)
    if not color then
        return prefix
    end
    local tag, space = prefix:match("^(.-)(%s*)$")
    return Colors.Text(color, tag) .. space
end

---The tag for a quest, such as "[12] ", or nil while its level isn't known.
---@param questID number?
---@param level number? the level the list gave, for when the quest log can't say
---@return string?
local function prefixFor(questID, level)
    if type(questID) ~= "number" or questID <= 0 then
        return nil
    end
    -- The quest log's tag uses the difficulty level, so prefer it.
    local difficulty = C_QuestLog.GetQuestDifficultyLevel and C_QuestLog.GetQuestDifficultyLevel(questID)
    if type(difficulty) == "number" and difficulty > 0 then
        level = difficulty
    end
    if type(level) ~= "number" or level <= 0 then
        return nil
    end
    local blizzard = QuestUtilsOverrides and QuestUtilsOverrides.GetQuestTitlePrefix
    -- Mainline's version gives nil unless its Show Quest Level setting is on; this module is ours.
    -- Without it, the same tag from Lib/Quests, which every other module writes ("[12+]").
    local prefix = blizzard and blizzard({ questID = questID, difficultyLevel = level })
        or Quests.LevelTag(questID, level) .. " "
    if module.db.color then
        prefix = colorTag(prefix, level)
    end
    return prefix
end

-- Puts the tag before a title's text, once, replacing a tag of ours from before an option changed.
local function tagText(fontString, prefix)
    local text = fontString and fontString:GetText()
    if prefix and type(text) == "string" and sub(text, 1, #prefix) ~= prefix then
        fontString:SetText(prefix .. untagged(text))
    end
end

-- Takes our tag off a title.
local function untagText(fontString)
    local text = fontString and fontString:GetText()
    if type(text) == "string" then
        local plain = untagged(text)
        if plain ~= text then
            fontString:SetText(plain)
        end
    end
end

-- The gossip window. Blizzard's Setup formats the title (gray for trivial quests) and sizes the
-- row; doing it again with the tag inside keeps both right, for the rows and the one it measures.
local function tagGossip(button, info)
    local prefix = info and prefixFor(info.questID, info.questLevel)
    if prefix and info.title and button.UpdateTitleForQuest then
        button:UpdateTitleForQuest(info.questID, prefix .. info.title, info.isIgnored, info.isTrivial)
    end
end

-- The greeting window. Its last word on each title is the button's SetText, so the tag goes in
-- right after that, before anything hooked to the panel's OnShow (Forever Quest Icons) sees it.
local busy = false

local function tagGreeting(button, text)
    if busy or type(text) ~= "string" then
        return
    end
    local prefix = prefixFor(Quests.GreetingButton(button))
    if prefix and sub(text, 1, #prefix) ~= prefix then
        busy = true
        button:SetText(prefix .. untagged(text))
        busy = false
    end
end

-- Runs right after the pool hands out a button and before Blizzard titles it.
local function hookGreetingButtons(pool)
    for button in pool:EnumerateActive() do
        module:Hook(button, "SetText", tagGreeting)
    end
end

-- A quest's details: QuestInfo_Display fills them for a quest giver's offer and reward, and for
-- the quest log on the map. The quest log knows its quest's level even when the API doesn't.
local function tagDetails()
    local questID = Quests.DetailsID()
    tagText(QuestInfoTitleHeader, prefixFor(questID, Quests.Level(questID)))
end

-- The window that asks for a quest's items before you turn it in.
local function tagProgress()
    local questID = Quests.GiverID()
    tagText(QuestProgressTitleText, prefixFor(questID, Quests.Level(questID)))
end

-- Fills an open list again, with or without the tags, and tags or untags open details.
local function refresh()
    -- Not with the controller interface on: GossipFrame:Update moves the controller's cursor
    -- (SmartNavigation), which refuses a call from addon code. The list is tagged when next opened.
    if GossipFrame and GossipFrame.Update and GossipFrame:IsShown() and not ns.Gamepad.On() then
        GossipFrame:Update()
    end
    if QuestFrameGreetingPanel and QuestFrameGreetingPanel_OnShow and QuestFrameGreetingPanel:IsShown() then
        QuestFrameGreetingPanel_OnShow()
    end
    if module.enabled then
        tagDetails()
        tagProgress()
    else
        untagText(QuestInfoTitleHeader)
        untagText(QuestProgressTitleText)
    end
end

function module:OnEnable()
    -- Mainline's buttons call these shared methods by name, so hooking them reaches every button.
    self:Hook(GossipSharedAvailableQuestButtonMixin, "Setup", tagGossip)
    self:Hook(GossipSharedActiveQuestButtonMixin, "Setup", tagGossip)
    self:Hook(QuestFrameGreetingPanel and QuestFrameGreetingPanel.titleButtonPool, "Acquire",
        hookGreetingButtons)
    self:Hook("QuestInfo_Display", tagDetails)
    -- The panel's script holds the function it had at load, and Blizzard may call the global
    -- itself, so both are hooked; tagging twice does nothing more.
    self:HookScript(QuestFrameProgressPanel, "OnShow", tagProgress)
    self:Hook("QuestFrameProgressPanel_OnShow", tagProgress)
    refresh()
end

-- Hooks stop by themselves; what's open gets its plain titles back.
function module:OnDisable()
    refresh()
end

-- Color by Difficulty: what's open gets its tags again, colored or plain.
function module:OnOptionChanged()
    refresh()
end
