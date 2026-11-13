-- Available Quests: an exclamation mark on the world map where a quest the character can pick up
-- starts. Blizzard's own quest icons are only for quests already in the log; nothing in the game
-- says where one not accepted yet starts, so the starts, and the rules for who can take a quest,
-- come from the QuestieDB addon at run time (Lib/QuestStarts.lua, Lib/QuestieDB.lua). Off by
-- default, and it does nothing without QuestieDB.
-- Idea from Forever Quest Pins; none of its code or data.
--
-- QuestieDB is keyed by quest, so every quest is read once after login, a few milliseconds a
-- frame and never in combat, into an index by map. Until that's done the map shows no icons.
--
-- An icon lets clicks through to the map, as all our map icons do: Shift+click puts Blizzard's map
-- pin on it, Shift+right-click hides its quests for this character.
local _, ns = ...

local ipairs, pairs, type, format, tonumber, match = ipairs, pairs, type, string.format, tonumber, string.match
local UnitLevel, UnitRace, UnitClass, UnitGUID = UnitLevel, UnitRace, UnitClass, UnitGUID
local C_QuestLog, C_Map = C_QuestLog, C_Map
local debugprofilestop, InCombatLockdown = debugprofilestop, InCombatLockdown

local L = ns.L
local QuestieDB, QuestStarts = ns.QuestieDB, ns.QuestStarts
local MapPins, WorldMap, MapTooltip = ns.MapPins, ns.WorldMap, ns.MapTooltip

local module = ns.NewModule("AvailableQuests", L.AVAILABLEQUESTS_DESC, {
    enabled = false,
    -- Quest types
    normal = true,
    repeatable = true,
    class = true,
    profession = true,
    mySkills = true,
    dungeon = true,
    seasonal = false,
    -- Filters
    low = "off", -- "off" (hidden), "fade", or "show"
    lowGap = 8,
    high = false,
    highGap = 5,
    upcoming = true,
    upcomingLevels = 2,
    prerequisites = true,
    reputation = true,
    -- Icons
    color = "kind", -- "kind", "difficulty", or "plain"
    size = 18,
    alpha = 100,
    fadeAlpha = 50,
    groupSpawns = true,
    maxSpawns = 4,
    continents = false,
    -- Tooltip
    tooltipGiver = true,
    tooltipLevels = true,
    tooltipKind = true,
    tooltipRequires = true,
    tooltipObjectives = false,
    tooltipHints = true,
    tooltipMax = 8,
    -- Other
    npcTooltip = true,
    filterMenu = true,
    hidden = {}, -- quest ID -> true: hidden with Shift+right-click, for each character
})
module.title = L.AVAILABLEQUESTS_TITLE
module.category = "quests"
module.added = "1.6.0"
module.quickToggle = "world"
module.perCharacter = { hidden = true }

-- QuestieDB's own two notices, then ours, always there: what's shown is only as good as its data.
module.notice = QuestieDB.Notices()
module.notice[#module.notice + 1] = {
    text = L.AVAILABLEQUESTS_NOTICE,
    description = L.AVAILABLEQUESTS_NOTICE_DESC,
}

function module:Problem()
    return QuestieDB.Problem()
end

local KINDS = L.AVAILABLEQUESTS_SECTION_KINDS
local FILTERS = L.AVAILABLEQUESTS_SECTION_FILTERS
local ICONS = L.AVAILABLEQUESTS_SECTION_ICONS
local TOOLTIP = L.AVAILABLEQUESTS_SECTION_TOOLTIP
local OTHER = L.AVAILABLEQUESTS_SECTION_OTHER

-- Each kind's name, for its checkbox, the map's filter menu, and the tooltip.
local KIND_NAMES = {
    normal = L.AVAILABLEQUESTS_NORMAL,
    repeatable = L.AVAILABLEQUESTS_REPEATABLE,
    class = L.AVAILABLEQUESTS_CLASS,
    profession = L.AVAILABLEQUESTS_PROFESSION,
    dungeon = L.AVAILABLEQUESTS_DUNGEON,
    seasonal = L.AVAILABLEQUESTS_SEASONAL,
}

module.options = {
    { key = "normal", name = L.AVAILABLEQUESTS_NORMAL, description = L.AVAILABLEQUESTS_NORMAL_DESC, section = KINDS },
    { key = "repeatable", name = L.AVAILABLEQUESTS_REPEATABLE, description = L.AVAILABLEQUESTS_REPEATABLE_DESC,
        section = KINDS },
    { key = "class", name = L.AVAILABLEQUESTS_CLASS, description = L.AVAILABLEQUESTS_CLASS_DESC, section = KINDS },
    { key = "profession", name = L.AVAILABLEQUESTS_PROFESSION, description = L.AVAILABLEQUESTS_PROFESSION_DESC,
        section = KINDS },
    { key = "mySkills", name = L.AVAILABLEQUESTS_MYSKILLS, description = L.AVAILABLEQUESTS_MYSKILLS_DESC,
        requires = "profession", section = KINDS },
    { key = "dungeon", name = L.AVAILABLEQUESTS_DUNGEON, description = L.AVAILABLEQUESTS_DUNGEON_DESC,
        section = KINDS },
    { key = "seasonal", name = L.AVAILABLEQUESTS_SEASONAL, description = L.AVAILABLEQUESTS_SEASONAL_DESC,
        section = KINDS },

    {
        key = "low", name = L.AVAILABLEQUESTS_LOW, description = L.AVAILABLEQUESTS_LOW_DESC,
        choices = {
            { "off", L.AVAILABLEQUESTS_LOW_HIDE },
            { "fade", L.AVAILABLEQUESTS_LOW_FADE },
            { "show", L.AVAILABLEQUESTS_LOW_SHOW },
        },
        section = FILTERS,
    },
    { key = "lowGap", name = L.AVAILABLEQUESTS_LOWGAP, description = L.AVAILABLEQUESTS_LOWGAP_DESC,
        min = 3, max = 20, step = 1, format = L.AVAILABLEQUESTS_LEVELS, section = FILTERS },
    { key = "high", name = L.AVAILABLEQUESTS_HIGH, description = L.AVAILABLEQUESTS_HIGH_DESC,
        slider = "highGap", section = FILTERS },
    { key = "highGap", name = L.AVAILABLEQUESTS_HIGHGAP, description = L.AVAILABLEQUESTS_HIGHGAP_DESC,
        requires = "high", min = 1, max = 15, step = 1, format = L.AVAILABLEQUESTS_LEVELS, section = FILTERS },
    { key = "upcoming", name = L.AVAILABLEQUESTS_UPCOMING, description = L.AVAILABLEQUESTS_UPCOMING_DESC,
        slider = "upcomingLevels", section = FILTERS },
    { key = "upcomingLevels", name = L.AVAILABLEQUESTS_UPCOMINGLEVELS,
        description = L.AVAILABLEQUESTS_UPCOMINGLEVELS_DESC, requires = "upcoming", min = 1, max = 10, step = 1,
        format = L.AVAILABLEQUESTS_LEVELS, section = FILTERS },
    { key = "prerequisites", name = L.AVAILABLEQUESTS_PREREQUISITES,
        description = L.AVAILABLEQUESTS_PREREQUISITES_DESC, section = FILTERS },
    { key = "reputation", name = L.AVAILABLEQUESTS_REPUTATION, description = L.AVAILABLEQUESTS_REPUTATION_DESC,
        section = FILTERS },

    {
        key = "color", name = L.AVAILABLEQUESTS_COLOR, description = L.AVAILABLEQUESTS_COLOR_DESC,
        choices = {
            { "kind", L.AVAILABLEQUESTS_COLOR_KIND },
            { "difficulty", L.AVAILABLEQUESTS_COLOR_DIFFICULTY },
            { "plain", L.AVAILABLEQUESTS_COLOR_PLAIN },
        },
        section = ICONS,
    },
    { key = "size", name = L.AVAILABLEQUESTS_SIZE, description = L.AVAILABLEQUESTS_SIZE_DESC,
        min = 10, max = 32, step = 2, format = L.ICONMARK_PIXELS, section = ICONS },
    { key = "alpha", name = L.AVAILABLEQUESTS_ALPHA, description = L.AVAILABLEQUESTS_ALPHA_DESC,
        min = 20, max = 100, step = 5, format = "%d%%", section = ICONS },
    { key = "fadeAlpha", name = L.AVAILABLEQUESTS_FADEALPHA, description = L.AVAILABLEQUESTS_FADEALPHA_DESC,
        min = 20, max = 100, step = 5, format = "%d%%", section = ICONS },
    { key = "groupSpawns", name = L.AVAILABLEQUESTS_GROUPSPAWNS, description = L.AVAILABLEQUESTS_GROUPSPAWNS_DESC,
        section = ICONS },
    { key = "maxSpawns", name = L.AVAILABLEQUESTS_MAXSPAWNS, description = L.AVAILABLEQUESTS_MAXSPAWNS_DESC,
        min = 1, max = 12, step = 1, format = "%d", section = ICONS },
    { key = "continents", name = L.AVAILABLEQUESTS_CONTINENTS, description = L.AVAILABLEQUESTS_CONTINENTS_DESC,
        section = ICONS },

    { key = "tooltipGiver", name = L.AVAILABLEQUESTS_TOOLTIPGIVER, description = L.AVAILABLEQUESTS_TOOLTIPGIVER_DESC,
        section = TOOLTIP },
    { key = "tooltipLevels", name = L.AVAILABLEQUESTS_TOOLTIPLEVELS,
        description = L.AVAILABLEQUESTS_TOOLTIPLEVELS_DESC, section = TOOLTIP },
    { key = "tooltipKind", name = L.AVAILABLEQUESTS_TOOLTIPKIND, description = L.AVAILABLEQUESTS_TOOLTIPKIND_DESC,
        section = TOOLTIP },
    { key = "tooltipRequires", name = L.AVAILABLEQUESTS_TOOLTIPREQUIRES,
        description = L.AVAILABLEQUESTS_TOOLTIPREQUIRES_DESC, section = TOOLTIP },
    { key = "tooltipObjectives", name = L.AVAILABLEQUESTS_TOOLTIPOBJECTIVES,
        description = L.AVAILABLEQUESTS_TOOLTIPOBJECTIVES_DESC, section = TOOLTIP },
    { key = "tooltipHints", name = L.AVAILABLEQUESTS_TOOLTIPHINTS, description = L.AVAILABLEQUESTS_TOOLTIPHINTS_DESC,
        section = TOOLTIP },
    { key = "tooltipMax", name = L.AVAILABLEQUESTS_TOOLTIPMAX, description = L.AVAILABLEQUESTS_TOOLTIPMAX_DESC,
        min = 3, max = 20, step = 1, format = "%d", section = TOOLTIP },

    { key = "npcTooltip", name = L.AVAILABLEQUESTS_NPCTOOLTIP, description = L.AVAILABLEQUESTS_NPCTOOLTIP_DESC,
        section = OTHER },
    { key = "filterMenu", name = L.AVAILABLEQUESTS_FILTERMENU, description = L.AVAILABLEQUESTS_FILTERMENU_DESC,
        section = OTHER },
}

-- The character ----------------------------------------------------------------------------------

-- The game's tags for a dungeon and a raid quest (Enum.QuestTag), for a quest it has data for.
local DUNGEON_TAGS = {
    [Enum and Enum.QuestTag and Enum.QuestTag.Dungeon or 81] = true,
    [Enum and Enum.QuestTag and Enum.QuestTag.Raid or 62] = true,
}

-- Probe: Mainline's call; it answers only for a quest the client has loaded, so a dungeon quest
-- never seen may count as normal until it has.
local function isDungeon(questID)
    local get = C_QuestLog.GetQuestTagInfo
    local info = get and get(questID)
    return type(info) == "table" and DUNGEON_TAGS[info.tagID] or false
end

local function completed(questID)
    local done = C_QuestLog.IsQuestFlaggedCompleted
    return done and done(questID) or false
end

local function inLog(questID)
    local on = C_QuestLog.IsOnQuest
    return on and on(questID) or false
end

local function hidden(questID)
    return module.db.hidden[questID] or false
end

local function skill(line)
    return (ns.Professions.Rank(line))
end

-- The character's reputation with a faction as one number, as QuestieDB's requirements are (0 at
-- the start of Neutral, 3000 at Friendly). Probe: Mainline's call; nil keeps the quest shown.
local function standing(factionID)
    local reputation = _G.C_Reputation
    local get = reputation and reputation.GetFactionDataByID
    local data = get and get(factionID)
    local value = type(data) == "table" and data.currentStanding
    return ns.IsNumber(value) and value or nil
end

local player = { completed = completed, inLog = inLog, hidden = hidden, dungeon = isDungeon, skill = skill,
    standing = standing }

local function readPlayer()
    local _, _, race = UnitRace("player")
    local _, _, class = UnitClass("player")
    player.level = UnitLevel("player") or 1
    player.race, player.class = race, class
    player.side = WorldMap.PlayerSide()
    return player
end

local rules = {}

local function readRules()
    local db = module.db
    for _, kind in ipairs(QuestStarts.KINDS) do
        rules[kind] = db[kind]
    end
    rules.mySkills, rules.prerequisites, rules.reputation = db.mySkills, db.prerequisites, db.reputation
    rules.upcoming = db.upcoming and db.upcomingLevels or 0
    rules.low, rules.lowGap = db.low, db.lowGap
    rules.highGap = db.high and db.highGap or nil
    return rules
end

-- A quest's verdict: `{ ok, kind or reason, state, quest }`, or nil for a quest QuestieDB lacks.
local function judge(questID)
    local quest = QuestStarts.Quest(questID)
    if not quest then
        return nil
    end
    local ok, kind, state = QuestStarts.Check(quest, player, rules)
    return { ok = ok, kind = kind, state = state, quest = quest }
end

-- How a quest reads ------------------------------------------------------------------------------

local WHITE = { r = 1, g = 1, b = 1 }

-- The level a quest counts as: its own, or the character's for one that scales.
local function questLevel(quest)
    local level = quest.level
    if not level or level < 1 then
        return player.level or 1
    end
    return level
end

local function difficultyColor(quest)
    if not GetQuestDifficultyColor then
        return WHITE
    end
    return GetQuestDifficultyColor(questLevel(quest)) or WHITE
end

-- "[12] Kobold Camp Cleanup", with the level only while Quest Levels is on.
local function questText(quest)
    local name = quest.name or format(L.AVAILABLEQUESTS_UNNAMED, quest.id)
    if module.db.tooltipLevels and quest.level and quest.level > 0 then
        return format(L.AVAILABLEQUESTS_LEVEL_NAME, quest.level, name)
    end
    return name
end

-- A profession's name by its skill line: the character's own, or the game's name for the line.
local function skillName(line)
    local _, name = ns.Professions.Rank(line)
    if name then
        return name
    end
    local trade = _G.C_TradeSkillUI
    local get = trade and trade.GetTradeSkillDisplayName
    local found = get and get(line)
    return ns.IsText(found) and found ~= "" and found or nil
end

-- Icons ------------------------------------------------------------------------------------------

local ATLAS = "QuestNormal" -- Blizzard's yellow exclamation mark
local DAILY -- its blue one, when this client has it
local CONTINENT = 0.75 -- smaller on a continent map, where every zone's icons crowd together
local NEAR = 0.04 -- spawns of one quest this close (a share of the map) share an icon
local APART = 0.004 -- with Group Nearby Spawns off, only spawns on the same spot do
local STACK = 0.012 -- quests starting this close share an icon

-- A kind's tint over the mark drawn gray. Normal has none: Blizzard's yellow as it is.
local KIND_COLORS = {
    repeatable = { 0.35, 0.65, 1 },
    profession = { 0.9, 0.6, 0.35 },
    dungeon = { 1, 0.45, 0.2 },
    seasonal = { 1, 0.55, 0.85 },
}

local function classColor()
    local color = ns.Colors.Class("player")
    return color and { color.r, color.g, color.b } or nil
end

-- Sets an icon's art for the quest it leads with.
local function look(info, verdict, db)
    info.atlas, info.color, info.desaturated = ATLAS, nil, false
    if verdict.state == "low" then
        info.desaturated = true -- gray, as the game draws a quest too low to matter
    elseif db.color == "difficulty" then
        local color = difficultyColor(verdict.quest)
        info.desaturated, info.color = true, { color.r, color.g, color.b }
    elseif db.color == "kind" then
        local kind = verdict.kind
        if kind == "repeatable" and DAILY then
            info.atlas = DAILY
        else
            local color = kind == "class" and classColor() or KIND_COLORS[kind]
            if color then
                info.desaturated, info.color = true, color
            end
        end
    end
    info.alpha = (verdict.state and db.fadeAlpha or db.alpha) / 100
end

-- Available now before upcoming and low, then by level, then by ID.
local function before(a, b)
    local stateA, stateB = a.verdict.state and 1 or 0, b.verdict.state and 1 or 0
    if stateA ~= stateB then
        return stateA < stateB
    end
    local levelA, levelB = questLevel(a.verdict.quest), questLevel(b.verdict.quest)
    if levelA ~= levelB then
        return levelA < levelB
    end
    return a.verdict.quest.id < b.verdict.quest.id
end

local layer

local function titleFor(info)
    local first = info.stack.entries[1]
    if module.db.tooltipGiver then
        local point = first.point
        local name = QuestieDB.Name(point.kind == "npc" and "Npc" or "Object", point.id)
        if name then
            return name
        end
    end
    return L.AVAILABLEQUESTS_TITLE
end

-- A stack's tooltip lines, worked out when it shows.
local function linesFor(info)
    local db = module.db
    local lines = {}
    local entries = info.stack.entries
    for i, entry in ipairs(entries) do
        if i > db.tooltipMax then
            lines[#lines + 1] = MapTooltip.Note(format(L.AVAILABLEQUESTS_MORE, #entries - db.tooltipMax))
            break
        end
        local verdict = entry.verdict
        local quest = verdict.quest
        local line = { questText(quest), difficultyColor(quest) }
        if db.tooltipKind and verdict.kind ~= "normal" then
            line.right = KIND_NAMES[verdict.kind]
        end
        lines[#lines + 1] = line
        if db.tooltipRequires then
            if verdict.state == "upcoming" then
                lines[#lines + 1] = MapTooltip.Note(format(L.AVAILABLEQUESTS_REQUIRES_LEVEL, quest.requiredLevel))
            end
            local needs = quest.requiredSkill
            local name = needs and skillName(needs.id)
            if name then
                lines[#lines + 1] = MapTooltip.Note(format(L.AVAILABLEQUESTS_REQUIRES_SKILL, name, needs.value))
            end
            local item = entry.point.item and QuestieDB.Name("Item", entry.point.item)
            if item then
                lines[#lines + 1] = MapTooltip.Note(format(L.AVAILABLEQUESTS_FROM_ITEM, item))
            end
        end
        if db.tooltipObjectives and quest.objectivesText[1] then
            lines[#lines + 1] = MapTooltip.Detail(quest.objectivesText[1])
        end
        if entry.count > 1 then
            lines[#lines + 1] = MapTooltip.Note(format(L.AVAILABLEQUESTS_SPAWNS, entry.count))
        end
    end
    if db.tooltipHints then
        lines[#lines + 1] = MapTooltip.Note(L.AVAILABLEQUESTS_HINT)
    end
    return lines
end

-- Shift+click puts Blizzard's map pin where the first quest starts; Shift+right-click hides every
-- quest of the icon for this character.
local function shiftClick(pin, button)
    local stack = pin.info and pin.info.stack
    if not stack then
        return
    end
    if button == "RightButton" then
        for _, entry in ipairs(stack.entries) do
            module.db.hidden[entry.verdict.quest.id] = true
        end
        layer:Refresh()
    elseif button == "LeftButton" then
        local point = stack.entries[1].point
        WorldMap.SetWaypoint(point.map, point.x, point.y)
    end
end

local continents = {} -- zone map ID -> its continent's, or false: the map tree doesn't change

local function continentOf(zone)
    local found = continents[zone]
    if found == nil then
        found = false
        for id, info in WorldMap.Up(zone) do
            if WorldMap.IsContinent(info) then
                found = id
            end
        end
        continents[zone] = found
    end
    return found
end

local function fill(mapID, add)
    if not QuestStarts.IsBuilt() then
        return
    end
    local db = module.db
    readPlayer()
    readRules()
    local verdicts = {} -- quest ID -> its verdict, or false, for this draw
    local byQuest = {} -- quest ID -> its spots on the shown map
    local side = player.side

    local function collect(points, fromMap)
        for _, point in ipairs(points) do
            -- A giver friendly only to the other side isn't this character's.
            if not (point.side and side and point.side ~= side) then
                local verdict = verdicts[point.quest]
                if verdict == nil then
                    verdict = judge(point.quest) or false
                    verdicts[point.quest] = verdict
                end
                if verdict and verdict.ok then
                    local x, y = point.x, point.y
                    if fromMap ~= mapID then
                        x, y = MapPins.Translate(fromMap, mapID, x, y)
                    end
                    if x then
                        local list = byQuest[point.quest]
                        if not list then
                            list = {}
                            byQuest[point.quest] = list
                        end
                        list[#list + 1] = { x = x, y = y, point = point, verdict = verdict }
                    end
                end
            end
        end
    end

    local size = db.size
    local own = QuestStarts.OnMap(mapID)
    if own then
        collect(own, mapID)
    end
    if db.continents and WorldMap.IsContinent(C_Map.GetMapInfo(mapID)) then
        size = size * CONTINENT
        for zone, points in QuestStarts.Maps() do
            if zone ~= mapID and continentOf(zone) == mapID then
                collect(points, zone)
            end
        end
    end

    local entries = {}
    local radius = db.groupSpawns and NEAR or APART
    for _, spots in pairs(byQuest) do
        for _, group in ipairs(QuestStarts.Cluster(spots, radius, db.maxSpawns)) do
            local spot = group.point
            spot.count = group.count
            entries[#entries + 1] = spot
        end
    end
    for _, stack in ipairs(QuestStarts.Stack(entries, STACK, before)) do
        local info = { size = size, stack = stack, lines = linesFor, shiftClick = shiftClick }
        look(info, stack.entries[1].verdict, db)
        info.title = titleFor(info)
        add(stack.x, stack.y, info)
    end
end

layer = MapPins.New(fill)

-- Building the index -----------------------------------------------------------------------------

local BUDGET = 4 -- milliseconds of reading a frame
local BATCH = 5 -- quests read between looks at the clock
local START = 3 -- seconds after turning on, so login isn't slowed
local builder = ns.Frames.Timer(module)

local function build()
    if not QuestStarts.Begin() then
        return
    end
    if InCombatLockdown() then
        builder:Start(1, build)
        return
    end
    local started = debugprofilestop()
    local done
    repeat
        done = QuestStarts.Step(BATCH)
    until done or debugprofilestop() - started >= BUDGET
    if done then
        layer:Refresh()
    else
        builder:Start(0, build)
    end
end

local function whenReady()
    if QuestStarts.IsBuilt() then
        layer:Refresh()
    else
        builder:Start(START, build)
    end
end

-- Something that decides the icons changed (a quest taken or done, a level, a skill, a
-- reputation): draw again, once for a burst of them, if the map is open. A closed map draws by
-- itself when it opens.
local refresh = ns.Frames.Coalesce(function()
    local map = WorldMap.Get()
    if map and map:IsShown() then
        layer:Refresh()
    end
end, 0.5, module)

local function onChanged()
    refresh()
end

-- NPC tooltips -----------------------------------------------------------------------------------

local NPC_LINES = 5 -- the quests listed on one NPC's tooltip

-- The quests an NPC has for the character, on its tooltip: "Quest:" and the quest's name at the
-- right, as Blizzard's Sell Price line.
local function onUnit(tooltip)
    if not (module.db.npcTooltip and QuestStarts.IsBuilt() and tooltip.GetUnit) then
        return
    end
    local _, unit = tooltip:GetUnit()
    if not ns.IsText(unit) then
        return
    end
    local guid = UnitGUID(unit)
    if not ns.IsText(guid) then
        return
    end
    local npc = tonumber(match(guid, "^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)"))
    local list = npc and QuestStarts.GivenBy(npc)
    if not list then
        return
    end
    readPlayer()
    readRules()
    local shown = 0
    for _, questID in ipairs(list) do
        local verdict = shown < NPC_LINES and judge(questID)
        if verdict and verdict.ok then
            shown = shown + 1
            local color = difficultyColor(verdict.quest)
            tooltip:AddDoubleLine(L.AVAILABLEQUESTS_TOOLTIP_LABEL, questText(verdict.quest), 1, 1, 1,
                color.r, color.g, color.b)
        end
    end
    if shown > 0 then
        tooltip:Show()
    end
end

-- The world map's filter menu --------------------------------------------------------------------

-- Blizzard's tag for the menu (WorldMapTrackingOptionsButtonMixin:SetupMenu).
local MENU_TAG = "MENU_WORLD_MAP_TRACKING"
local menuAdded = false

local function addMenu(_, root)
    if not (module.enabled and module.db.filterMenu) then
        return
    end
    root:CreateDivider()
    root:CreateTitle(L.AVAILABLEQUESTS_TITLE)
    for _, kind in ipairs(QuestStarts.KINDS) do
        root:CreateCheckbox(KIND_NAMES[kind], function()
            return module.db[kind]
        end, function()
            module.db[kind] = not module.db[kind]
            layer:Refresh()
            ns.RefreshSetting(module.name)
        end)
    end
end

-- Blizzard's menus can't take an addition back, so it's added once and checks the module each time
-- the menu opens. Probe: Menu.ModifyMenu is Mainline's.
local function enableMenu()
    if menuAdded or not (Menu and Menu.ModifyMenu) then
        return
    end
    menuAdded = true
    Menu.ModifyMenu(MENU_TAG, addMenu)
end

-- /fpp questwhy -----------------------------------------------------------------------------------

-- Says why a quest is or isn't on the map, for checking QuestieDB's data against the game.
ns.AddCommand("questwhy", L.AVAILABLEQUESTS_WHY_USAGE, L.AVAILABLEQUESTS_WHY_HELP, function(rest)
    local done, total = QuestStarts.Progress()
    if not QuestStarts.IsBuilt() then
        ns.Print(format(L.AVAILABLEQUESTS_WHY_BUILDING, done, total))
        return
    end
    local questID = tonumber(rest)
    if not questID then
        ns.Print(format(L.AVAILABLEQUESTS_WHY_COUNT, total))
        return
    end
    readPlayer()
    readRules()
    local verdict = judge(questID)
    if not verdict then
        ns.Print(format(L.AVAILABLEQUESTS_WHY_UNKNOWN, questID))
    elseif verdict.ok then
        ns.Print(format(L.AVAILABLEQUESTS_WHY_SHOWN, questText(verdict.quest), verdict.kind,
            verdict.state or "-"))
    else
        ns.Print(format(L.AVAILABLEQUESTS_WHY_HIDDEN, questText(verdict.quest), verdict.kind))
    end
end, "AvailableQuests")

-- The module -------------------------------------------------------------------------------------

module.actions = {
    {
        name = L.AVAILABLEQUESTS_UNHIDE,
        button = L.AVAILABLEQUESTS_UNHIDE_BUTTON,
        description = L.AVAILABLEQUESTS_UNHIDE_DESC,
        section = OTHER,
        fn = function()
            local list = module.db.hidden
            for questID in pairs(list) do
                list[questID] = nil
            end
            layer:Refresh()
        end,
    },
}

function module:OnEnable()
    DAILY = DAILY or ns.Frames.FirstAtlas("QuestDaily") or false
    self:On("QUEST_ACCEPTED", onChanged)
    self:On("QUEST_REMOVED", onChanged)
    self:On("QUEST_TURNED_IN", onChanged)
    self:On("PLAYER_LEVEL_UP", onChanged)
    self:On("SKILL_LINES_CHANGED", onChanged)
    self:On("UPDATE_FACTION", onChanged)
    self:TooltipPostCall(Enum.TooltipDataType.Unit, onUnit)
    enableMenu()
    layer:Enable()
    QuestieDB.OnReady(whenReady)
end

-- Events, the tooltip hook, and the timer stop by themselves; the index stays for the session.
function module:OnDisable()
    QuestieDB.Cancel(whenReady)
    layer:Disable()
end

function module:OnOptionChanged()
    layer:Refresh()
end
