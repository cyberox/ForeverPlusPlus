-- Quest Pins' index: QuestieDB read once into what the pins need, a few quests at a time so the
-- game doesn't stall. `internal.info[questID]` is what Rules.lua judges a quest by, and
-- `internal.byMap[mapID]` the places quests start on that map, each a source `{ kind, id, friendly,
-- xs, ys, quests }`: a giver (an NPC, an object, or what drops an item that starts a quest) with
-- all its spawns on that map and every quest it starts. Nothing is kept of QuestieDB's own tables.
local _, ns = ...

local ipairs, min = ipairs, math.min
local InCombatLockdown, debugprofilestop = InCombatLockdown, debugprofilestop

local QuestieDB = ns.QuestieDB

local module = ns.modules.QuestPins
local internal = module.internal

local PER_STEP = 5 -- quests read between looks at the clock
local BUDGET = 4 -- milliseconds of reading a frame
local DROP_SOURCES = 8 -- most NPCs and objects counted as where an item that starts a quest comes from

internal.info = {}
internal.byMap = {}
internal.ready = false

local sources = {} -- "kind:id" -> its list of sources, one a map
local ids, position
local timer = ns.Frames.Timer(module)

-- The sources of one giver: one for each map it spawns on. Made when the first quest it starts is
-- read, with the quest added to each after.
local function sourcesOf(kind, id)
    local key = kind .. ":" .. id
    local found = sources[key]
    if found then
        return found
    end
    found = {}
    sources[key] = found
    local record = kind == "npc" and QuestieDB.Npc(id) or QuestieDB.Object(id)
    for _, spawn in ipairs(record and record.spawns or {}) do
        local source
        for _, known in ipairs(found) do
            if known.map == spawn.uiMapID then
                source = known
                break
            end
        end
        if not source then
            source = { kind = kind, id = id, map = spawn.uiMapID, xs = {}, ys = {}, quests = {},
                friendly = record.friendlyTo }
            found[#found + 1] = source
            local list = internal.byMap[spawn.uiMapID]
            if not list then
                list = {}
                internal.byMap[spawn.uiMapID] = list
            end
            list[#list + 1] = source
        end
        source.xs[#source.xs + 1] = spawn.x
        source.ys[#source.ys + 1] = spawn.y
    end
    return found
end

local function addTo(kind, id, questID)
    for _, source in ipairs(sourcesOf(kind, id)) do
        source.quests[#source.quests + 1] = questID
    end
end

local function nonEmpty(list)
    return list and #list > 0 and list or nil
end

local function indexQuest(questID)
    local q = QuestieDB.Quest(questID)
    if not q then
        return
    end
    internal.info[questID] = {
        level = q.level, required = q.requiredLevel, max = q.maxLevel,
        races = q.races, classes = q.classes,
        skill = q.requiredSkill and q.requiredSkill.id, skillValue = q.requiredSkill and q.requiredSkill.value,
        all = nonEmpty(q.prerequisites.all), any = nonEmpty(q.prerequisites.any),
        exclusive = nonEmpty(q.exclusiveTo), breadcrumbFor = q.breadcrumbFor,
        repeatable = q.repeatable, raid = q.raid, sort = q.sortID,
        npcGiver = #q.starters.npcs > 0,
    }
    for _, npc in ipairs(q.starters.npcs) do
        addTo("npc", npc, questID)
    end
    for _, object in ipairs(q.starters.objects) do
        addTo("object", object, questID)
    end
    -- A quest an item starts: pinned where the item comes from, a few places at most.
    for _, itemID in ipairs(q.starters.items) do
        local item = QuestieDB.Item(itemID)
        local left = DROP_SOURCES
        for _, npc in ipairs(item and item.npcDrops or {}) do
            if left > 0 then
                addTo("npc", npc, questID)
                left = left - 1
            end
        end
        for _, object in ipairs(item and item.objectDrops or {}) do
            if left > 0 then
                addTo("object", object, questID)
                left = left - 1
            end
        end
    end
end

-- Reads quests for a few milliseconds, then waits for the next frame; never in combat, where a
-- slow frame costs the most.
local function step()
    if not module.enabled then
        return
    end
    if InCombatLockdown() then
        timer:Start(1, step)
        return
    end
    local started = debugprofilestop()
    local last = position
    repeat
        last = min(position + PER_STEP - 1, #ids)
        for i = position, last do
            indexQuest(ids[i])
        end
        position = last + 1
    until position > #ids or debugprofilestop() - started >= BUDGET
    if position > #ids then
        ids = nil
        internal.ready = true
        internal.Changed()
    else
        timer:Start(0, step)
    end
end

---Starts reading QuestieDB, unless it's read or being read.
function internal.Build()
    if internal.ready or ids then
        return
    end
    ids, position = QuestieDB.Ids("Quest"), 1
    timer:Start(0, step)
end

---Drops the index, when the module turns off.
function internal.Reset()
    timer:Cancel()
    ids, position = nil, nil
    internal.info, internal.byMap, internal.ready = {}, {}, false
    sources = {}
end
