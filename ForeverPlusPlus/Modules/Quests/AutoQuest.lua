-- Auto Quest: accepts quests and turns in finished ones as their windows open, and walks a quest
-- giver's list one quest at a time. It never picks among reward choices: with more than one, the
-- reward window stays for the player. Hold the pause key (Shift by default) to do it yourself.
local _, ns = ...

local ipairs = ipairs
local C_GossipInfo = C_GossipInfo
local UnitIsPlayer = UnitIsPlayer

local L = ns.L

local module = ns.NewModule("AutoQuest", L.AUTOQUEST_DESC, {
    enabled = false,
    accept = true,
    repeatable = true,
    shared = false,
    turnIn = true,
    pauseKey = "shift", -- "shift", "ctrl", "alt", or "none"
})
module.title = L.AUTOQUEST_TITLE
module.category = "quests"
module.quickToggle = "npcs"
module.added = "0.8.0"

module.options = {
    { key = "accept", name = L.AUTOQUEST_ACCEPT, description = L.AUTOQUEST_ACCEPT_DESC },
    {
        key = "repeatable", name = L.AUTOQUEST_REPEATABLE, description = L.AUTOQUEST_REPEATABLE_DESC,
        requires = "accept",
    },
    { key = "shared", name = L.AUTOQUEST_SHARED, description = L.AUTOQUEST_SHARED_DESC, requires = "accept" },
    { key = "turnIn", name = L.AUTOQUEST_TURN_IN, description = L.AUTOQUEST_TURN_IN_DESC },
    ns.Keys.Option("pauseKey", L.SKIP_KEY, L.AUTOQUEST_KEY_DESC),
}

-- Whether the player is holding the pause key, to do this quest themselves.
local function paused()
    return ns.Keys.IsDown(module.db.pauseKey)
end

-- Whether the quest window was opened by another player sharing a quest, not by an NPC. Unknown
-- (secret) counts as shared, so a quest is never taken from a player by mistake.
local function fromPlayer()
    for _, unit in ipairs({ "questnpc", "npc" }) do
        local isPlayer = UnitIsPlayer(unit)
        if not ns.IsReadable(isPlayer) or isPlayer then
            return true
        end
    end
    return false
end

local function wantsAvailable(repeatable, trivial)
    -- Gray quests show only with low-level quest tracking on; leave those for the player to pick.
    return module.db.accept and not trivial and (module.db.repeatable or not repeatable)
end

-- A quest giver's list (gossip). Turns in a finished quest first, then takes a new one; the list
-- shows again after each, which picks the next.
local function onGossipShow()
    if paused() then
        return
    end
    if module.db.turnIn then
        for _, quest in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
            if quest.isComplete and quest.questID then
                C_GossipInfo.SelectActiveQuest(quest.questID)
                return
            end
        end
    end
    for _, quest in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
        local repeatable = quest.repeatable or (quest.frequency ~= nil and quest.frequency ~= 0)
        if quest.questID and wantsAvailable(repeatable, quest.isTrivial) then
            C_GossipInfo.SelectAvailableQuest(quest.questID)
            return
        end
    end
end

-- The older quest list some NPCs and objects (wanted posters) show instead of gossip.
local function onQuestGreeting()
    if paused() then
        return
    end
    if module.db.turnIn and GetNumActiveQuests and GetActiveTitle then
        for i = 1, GetNumActiveQuests() do
            local _, isComplete = GetActiveTitle(i)
            if isComplete then
                SelectActiveQuest(i)
                return
            end
        end
    end
    if GetNumAvailableQuests and GetAvailableQuestInfo then
        for i = 1, GetNumAvailableQuests() do
            local isTrivial, frequency, isRepeatable = GetAvailableQuestInfo(i)
            local repeatable = isRepeatable or (frequency ~= nil and frequency ~= 0)
            if wantsAvailable(repeatable, isTrivial) then
                SelectAvailableQuest(i)
                return
            end
        end
    end
end

local function onQuestDetail()
    if not module.db.accept or paused() then
        return
    end
    if not module.db.shared and fromPlayer() then
        return
    end
    if QuestGetAutoAccept and QuestGetAutoAccept() then
        -- Already in the log; this only closes the window the way its button does.
        if AcknowledgeAutoAcceptQuest then
            AcknowledgeAutoAcceptQuest()
        end
    else
        AcceptQuest()
    end
end

local function onQuestProgress()
    if not module.db.turnIn or paused() or not IsQuestCompletable() then
        return
    end
    -- A quest that takes gold asks first; leave giving money away to the player.
    if GetQuestMoneyToGet and GetQuestMoneyToGet() > 0 then
        return
    end
    CompleteQuest()
end

local function onQuestComplete()
    if not module.db.turnIn or paused() then
        return
    end
    -- More than one reward to choose from: that choice is the player's.
    local choices = GetNumQuestChoices()
    if choices > 1 then
        return
    end
    GetQuestReward(choices)
end

function module:OnEnable()
    self:On("GOSSIP_SHOW", onGossipShow)
    self:On("QUEST_GREETING", onQuestGreeting)
    self:On("QUEST_DETAIL", onQuestDetail)
    self:On("QUEST_PROGRESS", onQuestProgress)
    self:On("QUEST_COMPLETE", onQuestComplete)
end
