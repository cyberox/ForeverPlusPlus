-- Quest Pins as a Forever++ plugin: a pin on the world map for every quest the character can pick
-- up now, at the quest givers' positions from the QuestieDB addon, and optionally pins for friendly
-- townsfolk: flight masters, innkeepers, and the like. It adds its module through
-- ForeverPlusPlusAPI.v1.RegisterModule and uses nothing else of Forever++ but GetPluginKit's helpers,
-- so it has its page on the Modules page, its options, and its profile settings like a built-in one.
-- Only there while QuestieDB is. From BetterQuestPins by Wouter (GPL-3.0-or-later), whose quest
-- availability rules and townsfolk pins this follows. Blacklist.lua holds the quests that exist in
-- the data but can't be taken.
--
-- The indexes of the database are built in the background, a few milliseconds a frame, so no frame
-- waits long; they're built once, when the module first turns on. Pins are a map layer from the
-- plugin kit, so a plain click goes through to the map and Shift+click sets the map pin.
local _, mine = ... -- this addon's own table
local API = ForeverPlusPlusAPI.v1 -- the only part of Forever++ it uses
local kit = API.GetPluginKit()

local ipairs, pairs, abs, floor, min = ipairs, pairs, math.abs, math.floor, math.min
local format, lower, wipe, bitand = string.format, string.lower, wipe, bit.band
local C_QuestLog, C_Map = C_QuestLog, C_Map
local UnitLevel, UnitRace, UnitClass, UnitFactionGroup = UnitLevel, UnitRace, UnitClass, UnitFactionGroup
local debugprofilestop, coroutine = debugprofilestop, coroutine

local L, QuestieDB = kit.L, kit.QuestieDB

local module = API.RegisterModule("QuestPins", L.QUESTPINS_DESC, {
    enabled = false,
    smallPins = false,
    maxAbove = 4, -- hide quests more than this many levels above the character
    -- Townsfolk, each type off until ticked.
    tfFlight = false, tfInn = false, tfRepair = false, tfClass = false,
    tfProfession = false, tfBanker = false, tfStable = false,
})
module.title = L.QUESTPINS_TITLE
module.category = "quests"

local GENERAL, TOWNS = L.QUESTPINS_SECTION_GENERAL, L.QUESTPINS_SECTION_TOWNSFOLK

local function townOption(key, name)
    return {
        key = key, name = name, section = TOWNS,
        description = format(L.QUESTPINS_TOWN_DESC, lower(name)),
    }
end

module.options = {
    { key = "smallPins", name = L.QUESTPINS_SMALL, description = L.QUESTPINS_SMALL_DESC, section = GENERAL },
    {
        key = "maxAbove", name = L.QUESTPINS_ABOVE, description = L.QUESTPINS_ABOVE_DESC, section = GENERAL,
        min = 0, max = 10, step = 1, format = "+%d",
    },
    townOption("tfFlight", L.QUESTPINS_FLIGHT),
    townOption("tfInn", L.QUESTPINS_INN),
    townOption("tfRepair", L.QUESTPINS_REPAIR),
    townOption("tfClass", L.QUESTPINS_CLASS),
    townOption("tfProfession", L.QUESTPINS_PROFESSION),
    townOption("tfBanker", L.QUESTPINS_BANKER),
    townOption("tfStable", L.QUESTPINS_STABLE),
}

-- Not for a player without QuestieDB: no page, nothing to turn on.
function module:IsAvailable()
    return QuestieDB.IsAvailable()
end

---------------------------------------------------------------------------
-- The index
---------------------------------------------------------------------------

-- uiMapID -> list of spots, each { x, y, questID, questID, ... }: a quest giver's position and
-- the quests it starts. A plain array, since there are thousands.
local byMap
local questReady, townsReady

-- lookup: mapID -> { ["x:y"] = spot }, so the quests of one giver share a spot.
local function addStarter(questID, spawns, lookup)
    for _, spawn in ipairs(spawns) do
        local mapID, x, y = spawn.uiMapID, spawn.x, spawn.y
        if x >= 0 and y >= 0 then
            local spots, keys = byMap[mapID], lookup[mapID]
            if not spots then
                spots, keys = {}, {}
                byMap[mapID], lookup[mapID] = spots, keys
            end
            local key = format("%.3f:%.3f", x, y)
            local spot = keys[key]
            if spot then
                spot[#spot + 1] = questID
            else
                spot = { x, y, questID }
                keys[key] = spot
                spots[#spots + 1] = spot
            end
        end
    end
end

-- Quest log categories of the world events and holidays: their quests are never pinned. Questie
-- blacklists them too and only lets them back while the event runs, so they stay out either way.
local EVENT_SORTS = {
    [22] = true, [368] = true, [365] = true, [1000] = true, -- world events, seasonal, temporary
    [404] = true, [402] = true, [378] = true, [376] = true, [375] = true, [374] = true, -- Winter Veil ... Noblegarden
    [370] = true, [369] = true, [366] = true, [364] = true, [41] = true, [21] = true, -- Brewfest ... Hallow's End
}

local YIELD_EVERY = 100
local function pause(i)
    if i % YIELD_EVERY == 0 then
        coroutine.yield()
    end
end

-- What the database says about a quest never changes in a session: the quest's record, cut down to
-- what the availability checks read, kept for the quests that have a giver.
local static = {}

local function staticOf(quest)
    return {
        requiredLevel = quest.requiredLevel or 0, maxLevel = quest.maxLevel, level = quest.level,
        races = quest.races, classes = quest.classes, skill = quest.requiredSkill ~= nil,
        single = #quest.prerequisites.any > 0 and quest.prerequisites.any or nil,
        group = #quest.prerequisites.all > 0 and quest.prerequisites.all or nil,
        exclusive = #quest.exclusiveTo > 0 and quest.exclusiveTo or nil,
        next = quest.next, breadcrumbFor = quest.breadcrumbFor,
        breadcrumbs = #quest.breadcrumbs > 0 and quest.breadcrumbs or nil,
        parent = quest.parent, disabledBy = quest.disabledBy, untilDone = quest.untilCompleted,
        startingWith = quest.startingWith, minRep = quest.minRep, maxRep = quest.maxRep, spell = quest.spell,
    }
end

local function buildIndex()
    byMap = {}
    local lookup = {}
    local blacklist = mine.blacklist or {}
    local npcSpawns, objectSpawns = {}, {} -- giver ID -> its spawns, a giver starts many quests
    local function spawnsOf(cache, read, giverID)
        local spawns = cache[giverID]
        if spawns == nil then
            local record = read(giverID)
            spawns = record and record.spawns or false
            cache[giverID] = spawns
        end
        return spawns
    end
    for i, questID in ipairs(QuestieDB.Ids("Quest")) do
        pause(i)
        local quest = not blacklist[questID] and QuestieDB.Quest(questID)
        -- Unnamed entries are placeholders the database knows only by ID; blacklisted ones exist
        -- in the data but cannot be taken in game.
        local sort = quest and quest.sortID
        if quest and quest.name and not EVENT_SORTS[sort or 0] then
            local pinned = false
            for _, npcID in ipairs(quest.starters.npcs) do
                local spawns = spawnsOf(npcSpawns, QuestieDB.Npc, npcID)
                if spawns then
                    addStarter(questID, spawns, lookup)
                    pinned = true
                end
            end
            for _, objectID in ipairs(quest.starters.objects) do
                local spawns = spawnsOf(objectSpawns, QuestieDB.Object, objectID)
                if spawns then
                    addStarter(questID, spawns, lookup)
                    pinned = true
                end
            end
            if pinned then
                static[questID] = staticOf(quest)
                static[questID].name = quest.name
            end
        end
    end
    questReady = true
    mine.blacklist = nil -- only the build reads it
end

---------------------------------------------------------------------------
-- Can this character pick the quest up now?
---------------------------------------------------------------------------
local IsCompleted = C_QuestLog.IsQuestFlaggedCompleted

local function inLog(questID)
    return C_QuestLog.GetLogIndexForQuestID(questID) ~= nil
end

local function taken(questID)
    return questID ~= nil and (IsCompleted(questID) or inLog(questID))
end

-- Every prerequisite done. Finishing an alternative to one counts as doing it, except for IDs the
-- data marks negative, which must be done themselves.
local function groupDone(ids)
    for _, id in ipairs(ids) do
        local done = IsCompleted(abs(id))
        local other = not done and id > 0 and static[id]
        local alts = other and other.exclusive
        if alts then
            for _, alt in ipairs(alts) do
                if IsCompleted(alt) then
                    done = true
                    break
                end
            end
        end
        if not done then
            return false
        end
    end
    return true
end

-- Reputation standing in reputation points.
local function reputation(factionID)
    local data = C_Reputation and C_Reputation.GetFactionDataByID and C_Reputation.GetFactionDataByID(factionID)
    return data and data.currentStanding
end

local function anyCompleted(ids)
    for _, id in ipairs(ids) do
        if IsCompleted(id) then
            return true
        end
    end
    return false
end

local function anyTaken(ids)
    for _, id in ipairs(ids) do
        if IsCompleted(id) or inLog(id) then
            return true
        end
    end
    return false
end

local player = {} -- level, and the bits that never change; read once per redraw
local availableNow = {} -- questID -> the answer this redraw (a quest giver can have several spawns)
local questNames, questNamesLevel = {}, nil -- questID -> the name's text, and the level it was colored for

local function refreshPlayer()
    player.level = UnitLevel("player")
    if not player.raceBit then
        player.raceBit = bit.lshift(1, select(3, UnitRace("player")) - 1)
        player.classBit = bit.lshift(1, select(3, UnitClass("player")) - 1)
        player.class = select(2, UnitClass("player"))
    end
    player.grayBelow = player.level - (GetQuestGreenRange and GetQuestGreenRange() or 8) -- probe: not every client has it
    if questNamesLevel ~= player.level then
        wipe(questNames)
        questNamesLevel = player.level
    end
end

local function checkAvailable(questID)
    if IsCompleted(questID) or inLog(questID) then
        return false
    end
    local s = static[questID]
    local db = module.db
    if s.requiredLevel > player.level then return false end
    if s.maxLevel and player.level > s.maxLevel then return false end
    -- Gray quests give nothing worth the walk; red ones are allowed, but not something to walk to yet.
    if s.level and (s.level < player.grayBelow or s.level > player.level + db.maxAbove) then return false end
    if s.races and bitand(s.races, player.raceBit) == 0 then return false end
    if s.classes and bitand(s.classes, player.classBit) == 0 then return false end
    -- Profession quests: skill levels aren't checked, so leave them out rather than guess.
    if s.skill then return false end
    if s.single then
        if not anyCompleted(s.single) then return false end
    elseif s.group and not groupDone(s.group) then
        return false
    end
    -- Done or in the log: a sibling that rules this one out, the next quest in the chain, or the
    -- quest a breadcrumb leads to. The game often skips flagging the earlier one.
    if s.exclusive and anyTaken(s.exclusive) then return false end
    if taken(s.next) or taken(s.breadcrumbFor) then return false end
    if s.breadcrumbs then
        for _, id in ipairs(s.breadcrumbs) do
            if inLog(id) then return false end
        end
    end
    if s.parent and not inLog(s.parent) then return false end
    if s.disabledBy and inLog(s.disabledBy) then return false end
    if s.untilDone and IsCompleted(s.untilDone) then return false end
    if s.startingWith and not taken(s.startingWith) then return false end
    if s.minRep and (reputation(s.minRep[1]) or -math.huge) < s.minRep[2] then return false end
    if s.maxRep and (reputation(s.maxRep[1]) or -math.huge) >= s.maxRep[2] then return false end
    -- Positive: a spell the player must know; negative: one they must not.
    if s.spell and C_SpellBook and C_SpellBook.IsSpellKnown
        and (C_SpellBook.IsSpellKnown(abs(s.spell)) == (s.spell < 0)) then
        return false
    end
    return true
end

local function isAvailable(questID)
    local available = availableNow[questID]
    if available == nil then
        available = checkAvailable(questID)
        availableNow[questID] = available
    end
    return available
end

local function questName(questID)
    local text = questNames[questID]
    if text then
        return text
    end
    local s = static[questID]
    local name = s.name or ("Quest " .. questID)
    if s.level then
        local color = GetQuestDifficultyColor(s.level)
        text = format("|cff%02x%02x%02x[%d]|r %s", color.r * 255, color.g * 255, color.b * 255, s.level, name)
    else
        text = name
    end
    questNames[questID] = text
    return text
end

---------------------------------------------------------------------------
-- Townsfolk: friendly NPCs by the service they offer, from QuestieDB's NPC flags.
---------------------------------------------------------------------------
local TRACKING = "Interface\\Minimap\\Tracking\\"
local TOWNSFOLK -- built when the index is: the flags come from the database

local function townsfolkTypes()
    if not TOWNSFOLK then
        local flags = QuestieDB.NpcFlags()
        TOWNSFOLK = {
            { key = "tfFlight", flag = flags.FLIGHT_MASTER, icon = "FlightMaster", name = L.QUESTPINS_FLIGHT },
            { key = "tfInn", flag = flags.INNKEEPER, icon = "Innkeeper", name = L.QUESTPINS_INN },
            { key = "tfRepair", flag = flags.REPAIR, icon = "Repair", name = L.QUESTPINS_REPAIR },
            { key = "tfClass", flag = flags.TRAINER, icon = "Class", name = L.QUESTPINS_CLASS, trainer = "class" },
            { key = "tfProfession", flag = flags.TRAINER, icon = "Profession", name = L.QUESTPINS_PROFESSION,
                trainer = "profession" },
            { key = "tfBanker", flag = flags.BANKER, icon = "Banker", name = L.QUESTPINS_BANKER },
            { key = "tfStable", flag = flags.STABLEMASTER, icon = "StableMaster", name = L.QUESTPINS_STABLE },
        }
    end
    return TOWNSFOLK
end

-- A townsfolk entry is an array, { x, y, type, name, sub, class }: there are thousands.
local X, Y, TYPE, NAME, SUB, CLASS = 1, 2, 3, 4, 5, 6

-- Trainers share one flag; the subname ("Mage Trainer") tells class from profession. The class
-- names are the client's own, so this works in any language.
local function trainerClass(sub)
    if not sub then
        return nil
    end
    for token, name in pairs(LOCALIZED_CLASS_NAMES_MALE) do
        local female = LOCALIZED_CLASS_NAMES_FEMALE[token]
        if sub:find(name, 1, true) or (female and sub:find(female, 1, true)) then
            return token
        end
    end
end

-- uiMapID -> list of entries (X, Y, TYPE, ... above), friendly NPCs only.
local townsByMap

local function buildTownsIndex()
    townsByMap = {}
    local types = townsfolkTypes()
    local faction = UnitFactionGroup("player") == "Alliance" and "A" or "H"
    for i, npcID in ipairs(QuestieDB.Ids("Npc")) do
        pause(i)
        local npc = QuestieDB.Npc(npcID)
        local matches
        for _, t in ipairs(types) do
            if npc and t.flag and bitand(npc.flags, t.flag) ~= 0 then
                matches = matches or {}
                matches[#matches + 1] = t
            end
        end
        if matches and npc.friendlyTo and npc.friendlyTo:find(faction, 1, true) and #npc.spawns > 0 then
            local name = npc.name or "?"
            local class = trainerClass(npc.subName)
            for _, t in ipairs(matches) do
                if not t.trainer or (t.trainer == "class") == (class ~= nil) then
                    for _, spawn in ipairs(npc.spawns) do
                        if spawn.x >= 0 and spawn.y >= 0 then
                            local entries = townsByMap[spawn.uiMapID] or {}
                            townsByMap[spawn.uiMapID] = entries
                            entries[#entries + 1] = { spawn.x, spawn.y, t, name, npc.subName, class }
                        end
                    end
                end
            end
        end
    end
    townsReady = true
end

local function anyTownsfolk()
    for _, t in ipairs(townsfolkTypes()) do
        if module.db[t.key] then
            return true
        end
    end
    return false
end

---------------------------------------------------------------------------
-- Background build: each index takes tens of milliseconds, run at most BUDGET ms a frame, from 3 s
-- after the module turns on or when a townsfolk type is first ticked. A map open while one builds
-- gets its pins when it is done.
---------------------------------------------------------------------------
local BUDGET = 4
local jobs = {} -- waiting or running, in order: { name, run = coroutine }
local failed = {} -- name -> true after an error, so it isn't retried on every redraw
local builder = CreateFrame("Frame")
builder:Hide()

local layer -- below
local function redraw()
    if layer then
        layer:Refresh()
    end
end

builder:SetScript("OnUpdate", function()
    local stop = debugprofilestop() + BUDGET
    while jobs[1] and debugprofilestop() < stop do
        local job = jobs[1]
        local ok, err = coroutine.resume(job.run)
        if not ok or coroutine.status(job.run) == "dead" then
            table.remove(jobs, 1)
            if not ok then
                failed[job.name] = true
                error(err, 0)
            end
            redraw()
        end
    end
    if not jobs[1] then
        builder:Hide()
    end
end)

local function startBackground()
    if not QuestieDB.IsReady() then
        return
    end
    local function queue(name, ready, build)
        if ready or failed[name] then
            return
        end
        for _, job in ipairs(jobs) do
            if job.name == name then
                return
            end
        end
        jobs[#jobs + 1] = { name = name, run = coroutine.create(build) }
    end
    queue("quests", questReady, buildIndex)
    if anyTownsfolk() then
        queue("towns", townsReady, buildTownsIndex)
    end
    if jobs[1] then
        builder:Show()
    end
end

---------------------------------------------------------------------------
-- Pins
---------------------------------------------------------------------------
local MAX_LINES = 10

-- Shift+click: Blizzard's map pin on the spot, which the arrow on screen follows.
local function shiftClick(pin, button)
    local info = pin.info
    if info and info.mapID and button == "LeftButton" then
        kit.SetWaypoint(info.mapID, info.px, info.py)
    end
end

-- Many townsfolk also give quests, and their quest pin would cover them. A townsfolk pin on a
-- quest pin moves a little down and right and shrinks, so both show. The quest pins drawn go into a
-- grid of NEAR-sized cells (x, y pairs, flat), so a townsfolk pin looks at nine cells.
local NEAR, NUDGE = 0.005, 0.007
local CELLS = 4096 -- cells per row of the grid key

local function markQuestPin(grid, x, y)
    local key = floor(x / NEAR) * CELLS + floor(y / NEAR)
    local cell = grid[key]
    if not cell then
        cell = {}
        grid[key] = cell
    end
    cell[#cell + 1] = x
    cell[#cell + 1] = y
end

local function nearQuestPin(grid, x, y)
    local cx, cy = floor(x / NEAR), floor(y / NEAR)
    for i = cx - 1, cx + 1 do
        for j = cy - 1, cy + 1 do
            local cell = grid[i * CELLS + j]
            if cell then
                for k = 1, #cell, 2 do
                    if abs(cell[k] - x) < NEAR and abs(cell[k + 1] - y) < NEAR then
                        return true
                    end
                end
            end
        end
    end
    return false
end

local function addQuestPins(mapID, size, add)
    local grid = {}
    if not questReady then
        startBackground() -- the pins follow when the index is done
        return grid
    end
    for _, spot in ipairs(byMap[mapID] or {}) do
        local names
        for i = 3, #spot do
            local questID = spot[i]
            if isAvailable(questID) then
                names = names or {}
                names[#names + 1] = questName(questID)
            end
        end
        if names then
            local x, y = spot[1], spot[2]
            local lines = {}
            for i = 1, min(#names, MAX_LINES) do
                lines[i] = names[i]
            end
            if #names > MAX_LINES then
                lines[#lines + 1] = kit.Note(format(L.QUESTPINS_MORE, #names - MAX_LINES))
            end
            add(x, y, {
                atlas = "QuestNormal", size = size, shiftClick = shiftClick, mapID = mapID, px = x, py = y,
                title = #names == 1 and AVAILABLE_QUEST or AVAILABLE_QUESTS, lines = lines,
            })
            markQuestPin(grid, x, y)
        end
    end
    return grid
end

local function addTownsfolkPins(mapID, size, questPins, add)
    if not anyTownsfolk() then
        return
    end
    if not townsReady then
        startBackground()
        return
    end
    local db = module.db
    for _, npc in ipairs(townsByMap[mapID] or {}) do
        local t = npc[TYPE]
        if db[t.key] and (t.trainer ~= "class" or npc[CLASS] == player.class) then
            local x, y, pinSize = npc[X], npc[Y], size
            if nearQuestPin(questPins, x, y) then
                x, y, pinSize = x + NUDGE, y + NUDGE, size * 0.75
            end
            add(x, y, {
                texture = TRACKING .. t.icon, size = pinSize, shiftClick = shiftClick, mapID = mapID,
                px = npc[X], py = npc[Y], title = npc[NAME], lines = { npc[SUB] or t.name },
            })
        end
    end
end

layer = kit.NewMapLayer(function(mapID, add)
    local info = C_Map.GetMapInfo(mapID)
    if not info or kit.IsContinent(info, true) then
        return
    end
    refreshPlayer()
    wipe(availableNow)
    local size = module.db.smallPins and 16 or 22
    local questPins = addQuestPins(mapID, size, add)
    addTownsfolkPins(mapID, size, questPins, add)
end)

-- One redraw a little after the last event, however many ask.
local redrawSoon = kit.Coalesce(redraw, 0.2, module)

local function onEvent()
    redrawSoon()
end

-- Quest log, level, reputation and spell changes alter what is available.
local EVENTS = {
    "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED",
    "PLAYER_LEVEL_UP", "UPDATE_FACTION", "SPELLS_CHANGED",
}

local startSoon = kit.Coalesce(startBackground, 3, module)

function module:OnEnable()
    for _, event in ipairs(EVENTS) do
        if kit.HasEvent(event) then
            self:On(event, onEvent)
        end
    end
    layer:Enable()
    QuestieDB.OnReady(startSoon)
end

function module:OnDisable()
    QuestieDB.Cancel(startSoon)
    layer:Disable()
    wipe(jobs) -- a build cut short starts again from the top
    builder:Hide()
end

function module:OnOptionChanged()
    startBackground() -- a townsfolk type ticked with the map closed builds its index now
    redraw()
end
