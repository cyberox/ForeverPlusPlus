-- Quest Pins: a ! on the world map where each quest you can still take starts, colored by kind
-- (normal, repeatable, dungeon and raid, class, profession), with the quests an NPC offers or waits
-- to hear back on its tooltip. Idea from ForeverQuestPins; the quests, their givers and where
-- those stand come from the QuestieDB addon at run time (Lib/QuestieDB.lua), never copied here.
-- Needs QuestieDB: without it the module is red and locked off in the list, saying to get it.
--
-- This file holds the module, its options, and what changes the pins. Index.lua reads QuestieDB
-- into a map-by-map list of givers, Rules.lua says which quests the player can take, Map.lua draws
-- the pins, and Tooltips.lua adds the NPC tooltip lines. They share module.internal.
local _, ns = ...

local pairs, type, format, tonumber, tostring = pairs, type, string.format, tonumber, tostring
local sort = table.sort
local C_QuestLog = C_QuestLog

local L = ns.L
local QuestieDB = ns.QuestieDB

local module = ns.NewModule("QuestPins", L.QUESTPINS_DESC, {
    enabled = false,
    pins = true, -- the world map's filter menu switches this one
    worldMap = true, -- on world and continent maps too
    clusters = true, -- one pin for each group of nearby spawns of a giver
    clusterLimit = 6, -- the most pins one giver gets on a map
    size = 100, -- percent of PIN_PIXELS
    color = "kind", -- "kind", "difficulty", or "plain"
    alpha = 100, -- percent
    fadeAlpha = 50, -- percent, for a pin of only upcoming or low-level quests
    holiday = false,
    upcoming = true, -- quests the player is upcomingLevels or fewer levels short of
    upcomingLevels = 2,
    tooltipGiver = true,
    tooltipHints = true,
    tooltipMax = 8, -- the most quests a pin's tooltip lists
    normal = true,
    repeatable = true,
    class = true,
    profession = true,
    dungeon = true,
    warEffort = false,
    warEffortAlways = false,
    low = "hide", -- quests lowGap or more levels below the player: "hide", "fade", or "off" (shown)
    lowGap = 9,
    reputation = true, -- leave out quests that need a reputation the player lacks
    hideHigh = false, -- quests highGap or more levels above the player
    highGap = 5,
    npcTooltips = true,
    chat = true,
    debug = false,
    -- Quest ID -> true, for the pins the player hid with Shift+right-click. Data, for each character.
    hidden = {},
})
module.perCharacter = { hidden = true }
module.title = L.QUESTPINS_TITLE
module.category = "quests"
module.added = "1.6.0"
module.internal = {}
local internal = module.internal

-- Without QuestieDB there are no quests to read: the module stays in the list, red and locked off,
-- with a notice saying to install it. One of a version we don't read is red too, its notice
-- saying so.
QuestieDB.Require(module)

local PINS, KINDS, LEVELS, TOOLTIPS = L.QUESTPINS_SECTION_PINS, L.QUESTPINS_SECTION_KINDS,
    L.QUESTPINS_SECTION_LEVELS, L.QUESTPINS_SECTION_TOOLTIPS

module.options = {
    { key = "pins", name = L.QUESTPINS_PINS, description = L.QUESTPINS_PINS_DESC, section = PINS },
    { key = "worldMap", name = L.QUESTPINS_WORLD_MAP, description = L.QUESTPINS_WORLD_MAP_DESC,
        requires = "pins", section = PINS },
    { key = "clusters", name = L.QUESTPINS_CLUSTERS, description = L.QUESTPINS_CLUSTERS_DESC,
        requires = "pins", section = PINS },
    { key = "clusterLimit", name = L.QUESTPINS_CLUSTER_LIMIT, description = L.QUESTPINS_CLUSTER_LIMIT_DESC,
        requires = "clusters", section = PINS, min = 1, max = 12, step = 1, format = "%d" },
    { key = "size", name = L.QUESTPINS_SIZE, description = L.QUESTPINS_SIZE_DESC, requires = "pins",
        section = PINS, min = 50, max = 150, step = 10, format = "%d%%" },
    {
        key = "color", name = L.QUESTPINS_COLOR, description = L.QUESTPINS_COLOR_DESC, requires = "pins",
        choices = {
            { "kind", L.QUESTPINS_COLOR_KIND },
            { "difficulty", L.QUESTPINS_COLOR_DIFFICULTY },
            { "plain", L.QUESTPINS_COLOR_PLAIN },
        },
        section = PINS,
    },
    { key = "alpha", name = L.QUESTPINS_ALPHA, description = L.QUESTPINS_ALPHA_DESC, requires = "pins",
        section = PINS, min = 20, max = 100, step = 5, format = "%d%%" },

    { key = "normal", name = L.QUESTPINS_NORMAL, description = L.QUESTPINS_NORMAL_DESC, requires = "pins",
        section = KINDS },
    { key = "repeatable", name = L.QUESTPINS_REPEATABLE, description = L.QUESTPINS_REPEATABLE_DESC,
        requires = "pins", section = KINDS },
    { key = "class", name = L.QUESTPINS_CLASS, description = L.QUESTPINS_CLASS_DESC, requires = "pins",
        section = KINDS },
    { key = "profession", name = L.QUESTPINS_PROFESSION, description = L.QUESTPINS_PROFESSION_DESC,
        requires = "pins", section = KINDS },
    { key = "dungeon", name = L.QUESTPINS_DUNGEON, description = L.QUESTPINS_DUNGEON_DESC,
        requires = "pins", section = KINDS },
    { key = "holiday", name = L.QUESTPINS_HOLIDAY, description = L.QUESTPINS_HOLIDAY_DESC,
        requires = "pins", section = KINDS },
    { key = "warEffort", name = L.QUESTPINS_WAR_EFFORT, description = L.QUESTPINS_WAR_EFFORT_DESC,
        requires = "pins", section = KINDS },
    { key = "warEffortAlways", name = L.QUESTPINS_WAR_EFFORT_ALWAYS,
        description = L.QUESTPINS_WAR_EFFORT_ALWAYS_DESC, requires = "warEffort", section = KINDS },

    {
        key = "low", name = L.QUESTPINS_LOW, description = L.QUESTPINS_LOW_DESC,
        choices = {
            { "hide", L.QUESTPINS_LOW_HIDE },
            { "fade", L.QUESTPINS_LOW_FADE },
            { "off", L.QUESTPINS_LOW_SHOW },
        },
        section = LEVELS,
    },
    { key = "lowGap", name = L.QUESTPINS_LOW_GAP, description = L.QUESTPINS_LOW_GAP_DESC,
        requires = "low", section = LEVELS, min = 3, max = 15, step = 1, format = "%d" },
    { key = "hideHigh", name = L.QUESTPINS_HIDE_HIGH, description = L.QUESTPINS_HIDE_HIGH_DESC,
        slider = "highGap", section = LEVELS },
    { key = "highGap", name = L.QUESTPINS_HIGH_GAP, description = L.QUESTPINS_HIGH_GAP_DESC,
        requires = "hideHigh", section = LEVELS, min = 3, max = 14, step = 1, format = "%d" },
    { key = "upcoming", name = L.QUESTPINS_UPCOMING, description = L.QUESTPINS_UPCOMING_DESC,
        slider = "upcomingLevels", section = LEVELS },
    { key = "upcomingLevels", name = L.QUESTPINS_UPCOMING_LEVELS, description = L.QUESTPINS_UPCOMING_LEVELS_DESC,
        requires = "upcoming", section = LEVELS, min = 1, max = 10, step = 1, format = "%d" },
    { key = "fadeAlpha", name = L.QUESTPINS_FADE_ALPHA, description = L.QUESTPINS_FADE_ALPHA_DESC,
        section = LEVELS, min = 20, max = 100, step = 5, format = "%d%%" },
    { key = "reputation", name = L.QUESTPINS_REPUTATION, description = L.QUESTPINS_REPUTATION_DESC,
        section = LEVELS },

    { key = "npcTooltips", name = L.QUESTPINS_NPC_TOOLTIPS, description = L.QUESTPINS_NPC_TOOLTIPS_DESC,
        section = TOOLTIPS },
    { key = "tooltipGiver", name = L.QUESTPINS_TOOLTIP_GIVER, description = L.QUESTPINS_TOOLTIP_GIVER_DESC,
        section = TOOLTIPS },
    { key = "tooltipHints", name = L.QUESTPINS_TOOLTIP_HINTS, description = L.QUESTPINS_TOOLTIP_HINTS_DESC,
        section = TOOLTIPS },
    { key = "tooltipMax", name = L.QUESTPINS_TOOLTIP_MAX, description = L.QUESTPINS_TOOLTIP_MAX_DESC,
        section = TOOLTIPS, min = 3, max = 20, step = 1, format = "%d" },
    ns.ChatOption(L.QUESTPINS_CHAT_DESC),
    { key = "debug", name = L.QUESTPINS_DEBUG, description = L.QUESTPINS_DEBUG_DESC, debug = true,
        section = L.DEBUG_SECTION_DIAGNOSTICS },
}

-- Hidden pins ------------------------------------------------------------------------------------

local function hiddenCount()
    local count = 0
    for _ in pairs(module.db.hidden) do
        count = count + 1
    end
    return count
end

---Hides quests' pins for this character, and says so in chat.
---@param ids number[]
function internal.Hide(ids)
    local count = 0
    for _, id in ipairs(ids) do
        if not module.db.hidden[id] then
            module.db.hidden[id] = true
            count = count + 1
        end
    end
    if count > 0 then
        module:Print(format(L.QUESTPINS_HID, count))
        internal.Changed()
    end
end

local function unhide(arg)
    arg = (arg or ""):lower()
    if arg == "all" then
        local count = hiddenCount()
        module.db.hidden = {}
        ns.Print(format(L.QUESTPINS_RESTORED, count))
        internal.Changed()
        return
    end
    local id = tonumber(arg)
    if not id then
        ns.Print(L.QUESTPINS_UNHIDE_USAGE)
    elseif module.db.hidden[id] then
        module.db.hidden[id] = nil
        ns.Print(format(L.QUESTPINS_RESTORED_ONE, id))
        internal.Changed()
    else
        ns.Print(format(L.QUESTPINS_NOT_HIDDEN, id))
    end
end

module.actions = {
    {
        name = L.QUESTPINS_RESET,
        button = L.QUESTPINS_RESET_BUTTON,
        description = L.QUESTPINS_RESET_DESC,
        confirm = L.QUESTPINS_RESET_CONFIRM,
        fn = function()
            unhide("all")
        end,
    },
}

-- What the player has done ------------------------------------------------------------------------
-- Forever's quest lists lag behind its events, so what the events say is kept for the session on
-- top of what the lists say.

local sessionDone, sessionInLog = {}, {}
local completed -- quest ID -> true from the game's list of completed quests, nil until read

local function readCompleted()
    completed = {}
    local list = C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs and C_QuestLog.GetAllCompletedQuestIDs()
    if type(list) == "table" then
        for key, value in pairs(list) do
            if value == true or value == 1 then
                completed[key] = true -- a set
            elseif type(value) == "number" then
                completed[value] = true -- a list
            end
        end
        completed.loaded = true
    end
end

---Whether the player has turned a quest in. The game's list of completed quests is the word of
---record, since an object-started quest is on it when IsQuestFlaggedCompleted misses it.
---@param id number
---@return boolean
function internal.Done(id)
    if sessionDone[id] then
        return true
    end
    if not completed then
        readCompleted()
    end
    if completed.loaded then
        return completed[id] == true
    end
    return C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(id) or false
end

---Whether a quest is in the player's quest log.
---@param id number
---@return boolean
function internal.InLog(id)
    if sessionInLog[id] then
        return true
    end
    return C_QuestLog and C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(id) or false
end

-- Redraws -----------------------------------------------------------------------------------------

local redraws = {} -- fn(), from the other files

---Has the other files call `fn()` when something that decides the pins changed.
---@param fn function
function internal.OnChanged(fn)
    redraws[#redraws + 1] = fn
end

function internal.Changed()
    for i = 1, #redraws do
        redraws[i]()
    end
end

local changedSoon = ns.Frames.Coalesce(internal.Changed, 0.2, module)

local function onAccepted(_, questID)
    questID = type(questID) == "number" and questID or nil
    if questID then
        sessionInLog[questID] = true
    end
    internal.NoteWarEffort()
    changedSoon()
end

local function onRemoved(_, questID)
    if type(questID) == "number" then
        sessionInLog[questID] = nil
    end
    changedSoon()
end

local function onTurnedIn(_, questID)
    if type(questID) == "number" then
        sessionDone[questID] = true
        sessionInLog[questID] = nil
        completed = nil
    end
    changedSoon()
end

local function onChanged()
    completed = nil
    changedSoon()
end

module:OnWhile("pins", {
    QUEST_ACCEPTED = onAccepted,
    QUEST_REMOVED = onRemoved,
    QUEST_TURNED_IN = onTurnedIn,
    QUEST_LOG_UPDATE = onChanged,
    PLAYER_LEVEL_UP = onChanged,
    SKILL_LINES_CHANGED = onChanged,
})

-- Starting and stopping -----------------------------------------------------------------------------

local function start()
    if module.enabled then
        internal.Build()
    end
end

function module:OnEnable()
    sessionDone, sessionInLog, completed = {}, {}, nil
    internal.HookTooltips()
    QuestieDB.OnReady(start)
end

function module:OnDisable()
    QuestieDB.Cancel(start)
    internal.Reset()
    internal.MapOff()
end

function module:OnOptionChanged()
    internal.Changed()
end

-- Commands ----------------------------------------------------------------------------------------

local function command(rest)
    local word, arg = (rest or ""):match("^(%S*)%s*(.-)%s*$")
    word = word:lower()
    if word == "unhide" then
        unhide(arg)
    elseif word == "why" then
        internal.Why(tonumber(arg))
    elseif word == "hidden" or word == "" then
        local ids = {}
        for id in pairs(module.db.hidden) do
            ids[#ids + 1] = id
        end
        sort(ids)
        if #ids == 0 then
            ns.Print(L.QUESTPINS_NONE_HIDDEN)
            return
        end
        ns.Print(format(L.QUESTPINS_HIDDEN, #ids))
        for _, id in ipairs(ids) do
            local q = QuestieDB.Quest(id)
            ns.PrintLine(format("  %d %s", id, tostring(q and q.name or "")))
        end
    else
        ns.Print(L.QUESTPINS_USAGE)
    end
end

ns.AddCommand("questpins", "[hidden | unhide <id|all> | why <id>]", L.QUESTPINS_COMMAND, command, "QuestPins")
