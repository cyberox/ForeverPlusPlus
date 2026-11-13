-- Where quests start, and which of them a character can pick up, from the QuestieDB addon's data
-- (Lib/QuestieDB.lua). The game says which quests are done and which are in the log, but nothing
-- about a quest not accepted yet, so its start, its earlier quests, and who it's for all come from
-- QuestieDB, and what's shown is only as right as that data.
--
-- QuestieDB is keyed by quest, so "the quests that start on this map" needs every quest read
-- once: `Begin` and `Step` build that index a few quests at a time, driven by whoever wants it
-- (a module's timer), and it's kept for the session. `Check` is the rules, on plain values, so
-- they can be tested without the game.
local _, ns = ...

local type, ipairs, pairs, floor, sort = type, ipairs, pairs, math.floor, table.sort

local QuestieDB = ns.QuestieDB

local QuestStarts = {}
ns.QuestStarts = QuestStarts

---The kinds a quest is sorted into, in the order options list them.
QuestStarts.KINDS = { "normal", "repeatable", "class", "profession", "dungeon", "seasonal" }

-- Quest log categories (QuestSort IDs) of holiday and world event quests: Seasonal, Special,
-- Darkmoon Faire, Ahn'Qiraj War, Lunar Festival, Invasion, and Midsummer. From the client's
-- QuestSort table, build 1.60.1.70888 (wago.tools).
local SEASONAL = ns.GameData.New("questStartsSeasonal", {
    [22] = true, [284] = true, [364] = true, [365] = true, [366] = true, [368] = true, [369] = true,
}, { label = "Quest Starts: holiday quest categories" })

-- The game's quest flag for a raid quest (0x40, as the Classic server cores name it). Unverified
-- on Forever's data.
local RAID_FLAG_BIT = 7

-- The bit of QuestieDB's race mask each race ID has: the race ID less one for Classic's eight, and
-- bits 33 and 34 for Forever's two new races (one Alliance, one Horde; QuestieDB's Forever masks
-- use them, but which race IDs the client gives them isn't checked, so a race not listed here
-- falls back to its side's bits).
local RACE_BITS = { 1, 2, 3, 4, 5, 6, 7, 8 }
local SIDE_BITS = { A = { 1, 3, 4, 7, 33 }, H = { 2, 5, 6, 8, 34 } }

-- Whether bit `n` (1 is the lowest) is set in `mask`. Arithmetic, since masks go past 32 bits.
local function has(mask, n)
    return floor(mask / 2 ^ (n - 1)) % 2 >= 1
end

---Whether a race mask lets a character in: by its race's bit, or for a race we have no bit for,
---by any bit of its side. No mask, or nothing known about the character, lets everyone in.
---@param mask number? QuestieDB's requiredRaces, nil or 0 for anyone
---@param race number? the character's race ID
---@param side string? "A" or "H"
---@return boolean
function QuestStarts.RaceAllowed(mask, race, side)
    if type(mask) ~= "number" or mask == 0 then
        return true
    end
    local bit = race and RACE_BITS[race]
    if bit then
        return has(mask, bit)
    end
    local bits = side and SIDE_BITS[side]
    if not bits then
        return true
    end
    for _, n in ipairs(bits) do
        if has(mask, n) then
            return true
        end
    end
    return false
end

---Whether a class mask lets a class in (bit: the class ID less one).
---@param mask number? QuestieDB's requiredClasses, nil or 0 for anyone
---@param class number? the character's class ID
---@return boolean
function QuestStarts.ClassAllowed(mask, class)
    if type(mask) ~= "number" or mask == 0 or type(class) ~= "number" then
        return true
    end
    return has(mask, class)
end

---The kind a quest is sorted into: "seasonal" (a holiday or world event category), "dungeon" (a
---dungeon or raid quest), "class", "profession", "repeatable", or "normal", the first that fits.
---@param quest table as `ns.QuestieDB.Quest` gives it
---@param dungeon? boolean whether the game tags it a dungeon or raid quest
---@return string kind
function QuestStarts.Kind(quest, dungeon)
    if quest.sortID and SEASONAL:Get(quest.sortID) then
        return "seasonal"
    elseif dungeon or has(quest.flags or 0, RAID_FLAG_BIT) then
        return "dungeon"
    elseif quest.classes then
        return "class"
    elseif quest.requiredSkill then
        return "profession"
    elseif quest.repeatable then
        return "repeatable"
    end
    return "normal"
end

local function none()
    return false
end

---Whether a character can pick a quest up, as far as QuestieDB's data says. Something not known
---(a reputation the game doesn't answer for) never hides a quest.
---
---`player` is `{ level, race, class, side, completed = fn(questID), inLog = fn(questID),
---hidden = fn(questID), dungeon = fn(questID), skill = fn(skillID) -> rank|nil,
---standing = fn(factionID) -> number|nil }`; the functions are optional but `completed` and
---`inLog`. `rules` is what the player set: a kind's name false to leave that kind out,
---`prerequisites` and `reputation` false to skip those checks, `mySkills` false to show profession
---quests of a skill the character lacks, `upcoming` (how many levels short of a quest's required
---level still shows it), `low` ("off" hides a quest `lowGap` levels or more under the character,
---"fade" marks it, "show" leaves it), and `highGap` (hides a quest that many levels over).
---@param quest table as `ns.QuestieDB.Quest` gives it
---@param player table
---@param rules? table
---@return boolean available
---@return string kindOrReason its kind when available, else why not: "log", "completed", "hidden", "kind", "race", "class", "exclusive", "chain", "breadcrumb", "parent", "prerequisite", "skill", "reputation", "outleveled", "level", "high", or "low"
---@return string? state "upcoming" (the character's level is short) or "low" (far under it), when available
function QuestStarts.Check(quest, player, rules)
    rules = rules or {}
    local id = quest.id
    local completed, inLog = player.completed, player.inLog
    if inLog(id) then
        return false, "log"
    end
    if not quest.repeatable and completed(id) then
        return false, "completed"
    end
    if (player.hidden or none)(id) then
        return false, "hidden"
    end
    local kind = QuestStarts.Kind(quest, (player.dungeon or none)(id) and true or false)
    if rules[kind] == false then
        return false, "kind"
    end
    if not QuestStarts.RaceAllowed(quest.races, player.race, player.side) then
        return false, "race"
    end
    if not QuestStarts.ClassAllowed(quest.classes, player.class) then
        return false, "class"
    end
    -- One of a set of either-or quests taken or done closes the others.
    for _, other in ipairs(quest.exclusiveTo or {}) do
        if other ~= id and (completed(other) or inLog(other)) then
            return false, "exclusive"
        end
    end
    -- A later step of the chain taken or done: this one was skipped past.
    local nextID = quest.next
    if nextID and nextID ~= id and (completed(nextID) or inLog(nextID)) then
        return false, "chain"
    end
    -- A quest that only leads to another is no use once that one is taken or done.
    local leadsTo = quest.breadcrumbFor
    if leadsTo and (completed(leadsTo) or inLog(leadsTo)) then
        return false, "breadcrumb"
    end
    if quest.parent and not inLog(quest.parent) then
        return false, "parent"
    end
    if rules.prerequisites ~= false then
        local needs = quest.prerequisites or {}
        for _, earlier in ipairs(needs.all or {}) do
            if not completed(earlier) then
                return false, "prerequisite"
            end
        end
        local any = needs.any or {}
        if #any > 0 then
            local one = false
            for _, earlier in ipairs(any) do
                one = one or (completed(earlier) and true or false)
            end
            if not one then
                return false, "prerequisite"
            end
        end
    end
    local skill = quest.requiredSkill
    if skill and rules.mySkills ~= false and player.skill then
        local rank = player.skill(skill.id)
        if not rank or rank < skill.value then
            return false, "skill"
        end
    end
    if rules.reputation ~= false and player.standing then
        local low, high = quest.minRep, quest.maxRep
        local standing = low and player.standing(low.id)
        if standing and standing < low.value then
            return false, "reputation"
        end
        standing = high and player.standing(high.id)
        if standing and standing >= high.value then
            return false, "reputation"
        end
    end
    local level = player.level or 1
    if quest.maxLevel and level > quest.maxLevel then
        return false, "outleveled"
    end
    local state
    if quest.requiredLevel and level < quest.requiredLevel then
        if level + (rules.upcoming or 0) < quest.requiredLevel then
            return false, "level"
        end
        state = "upcoming"
    end
    -- A quest level under 1 is QuestieDB's "scales with the character".
    local questLevel = quest.level
    if questLevel and questLevel > 0 then
        if rules.highGap and questLevel - level >= rules.highGap then
            return false, "high"
        end
        if not state and rules.lowGap and level - questLevel >= rules.lowGap then
            local low = rules.low or "off"
            if low == "off" then
                return false, "low"
            elseif low == "fade" then
                state = "low"
            end
        end
    end
    return true, kind, state
end

-- The index ----------------------------------------------------------------------------------

local MAX_POINTS = 12 -- the spots one starter gives a quest on one map
local MAX_SOURCES = 6 -- the creatures and objects read for an item that starts a quest

local maps -- uiMapID -> list of points
local givers -- NPC ID -> list of the quests it starts itself
local quests -- quest ID -> the quest as QuestieDB.Quest gives it, or false; read when asked
local spawnCache -- "Npc"/"Object" -> ID -> { list, side } or false
local queue, cursor, built

local function reset()
    maps, givers, quests = {}, {}, {}
    spawnCache = { Npc = {}, Object = {} }
    queue, cursor, built = nil, 0, false
end
reset()

local function spawnsOf(kind, id)
    local cache = spawnCache[kind]
    local found = cache[id]
    if found == nil then
        local list, _, side = QuestieDB.Spawns(kind, id)
        found = list and { list = list, side = side ~= "AH" and side or nil } or false
        cache[id] = found
    end
    return found or nil
end

-- Adds a starter's spots to the maps: an NPC or object that gives the quest, or (with `item`) one
-- an item that starts it is taken from.
local function addStarter(questID, kind, id, item)
    local found = spawnsOf(kind, id)
    if not found then
        return
    end
    local counts = {}
    for _, spawn in ipairs(found.list) do
        local map = spawn.uiMapID
        local count = (counts[map] or 0) + 1
        counts[map] = count
        if count <= MAX_POINTS then
            local list = maps[map]
            if not list then
                list = {}
                maps[map] = list
            end
            list[#list + 1] = { quest = questID, x = spawn.x, y = spawn.y, map = map,
                kind = kind == "Npc" and "npc" or "object", id = id, side = found.side, item = item }
        end
    end
    if kind == "Npc" and not item then
        local list = givers[id]
        if not list then
            list = {}
            givers[id] = list
        end
        list[#list + 1] = questID
    end
end

local function addQuest(questID)
    local starters = QuestieDB.Starters(questID)
    if not starters then
        return
    end
    for _, id in ipairs(starters.npcs) do
        addStarter(questID, "Npc", id)
    end
    for _, id in ipairs(starters.objects) do
        addStarter(questID, "Object", id)
    end
    for _, itemID in ipairs(starters.items) do
        local item = QuestieDB.Item(itemID)
        local sources = 0
        for _, id in ipairs(item and item.npcDrops or {}) do
            if sources < MAX_SOURCES then
                sources = sources + 1
                addStarter(questID, "Npc", id, itemID)
            end
        end
        for _, id in ipairs(item and item.objectDrops or {}) do
            if sources < MAX_SOURCES then
                sources = sources + 1
                addStarter(questID, "Object", id, itemID)
            end
        end
    end
end

---Starts building the index, if it isn't built or being built. False while QuestieDB can't be
---read.
---@return boolean started
function QuestStarts.Begin()
    if built or queue then
        return true
    end
    if not QuestieDB.IsReady() then
        return false
    end
    reset()
    queue = QuestieDB.Ids("Quest")
    return true
end

---Reads the next `count` quests into the index. True once every quest is in.
---@param count number
---@return boolean built
function QuestStarts.Step(count)
    if built or not queue then
        return built
    end
    local last = cursor + count
    if last > #queue then
        last = #queue
    end
    for i = cursor + 1, last do
        addQuest(queue[i])
    end
    cursor = last
    if cursor >= #queue then
        queue, built = nil, true
    end
    return built
end

---Whether the index is whole.
---@return boolean
function QuestStarts.IsBuilt()
    return built
end

---How far the build is: quests read, and how many there are.
---@return number done
---@return number total
function QuestStarts.Progress()
    if built then
        return cursor, cursor
    end
    return cursor, queue and #queue or 0
end

---The quest starts on a map: a list of `{ quest, x, y, map, kind, id, side, item }`, x and y 0-1
---on `map`, `kind` "npc" or "object" with its `id`, `side` "A" or "H" for an NPC friendly to one
---side only, and `item` the item that starts the quest when the starter only drops or holds it.
---Shared and read only; nil for a map with none.
---@param mapID number
---@return table[]|nil
function QuestStarts.OnMap(mapID)
    return maps[mapID]
end

---Every map with quest starts and its list, as `pairs` gives them. Read only.
---@return function iterator
---@return table state
function QuestStarts.Maps()
    return pairs(maps)
end

---The quests an NPC gives, as a list of quest IDs; read only, nil for an NPC that gives none.
---@param npcID number
---@return number[]|nil
function QuestStarts.GivenBy(npcID)
    return givers[npcID]
end

---A quest as `ns.QuestieDB.Quest` gives it, kept for the session; nil for one it doesn't know.
---@param questID number
---@return table|nil
function QuestStarts.Quest(questID)
    local quest = quests[questID]
    if quest == nil then
        quest = QuestieDB.Quest(questID) or false
        quests[questID] = quest
    end
    return quest or nil
end

---Forgets the index and the quests read, for the tests and for a QuestieDB that changed.
function QuestStarts.Reset()
    reset()
end

-- Grouping -----------------------------------------------------------------------------------

local function near(a, b, radius)
    local dx, dy = a.x - b.x, a.y - b.y
    return dx * dx + dy * dy <= radius * radius
end

---One quest's spots on a map as fewer: spots within `radius` (a share of the map) of one already
---kept count as that one, and at most `limit` are kept. Each result is `{ point, count }`: the
---first spot of the group, and how many it stands for.
---@param points table[] with x and y
---@param radius number
---@param limit number
---@return table[] groups
function QuestStarts.Cluster(points, radius, limit)
    local groups = {}
    for _, point in ipairs(points) do
        local found
        for _, group in ipairs(groups) do
            if near(group.point, point, radius) then
                found = group
                break
            end
        end
        if found then
            found.count = found.count + 1
        elseif #groups < limit then
            groups[#groups + 1] = { point = point, count = 1 }
        end
    end
    return groups
end

---Spots of different quests as stacks: every entry within `radius` of a stack's first joins it,
---so one icon stands for a quest giver's whole list. Each stack is `{ x, y, entries }`, its
---entries in the order `before(a, b)` sorts them when given.
---@param entries table[] with x and y
---@param radius number
---@param before? fun(a: table, b: table): boolean
---@return table[] stacks
function QuestStarts.Stack(entries, radius, before)
    local stacks = {}
    for _, entry in ipairs(entries) do
        local found
        for _, stack in ipairs(stacks) do
            if near(stack, entry, radius) then
                found = stack
                break
            end
        end
        if found then
            found.entries[#found.entries + 1] = entry
        else
            stacks[#stacks + 1] = { x = entry.x, y = entry.y, entries = { entry } }
        end
    end
    if before then
        for _, stack in ipairs(stacks) do
            sort(stack.entries, before)
        end
    end
    return stacks
end
