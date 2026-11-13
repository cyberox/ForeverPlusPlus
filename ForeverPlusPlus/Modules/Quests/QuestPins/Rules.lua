-- Quest Pins' rules: which quests the player can take, from what Index.lua read of QuestieDB and
-- what the game says of the player. Unknown restrictions keep a quest shown.
local _, ns = ...

local type, floor, format = type, math.floor, string.format
local UnitLevel, UnitRace, UnitClass, UnitFactionGroup = UnitLevel, UnitRace, UnitClass, UnitFactionGroup
local C_QuestLog = C_QuestLog

local L = ns.L
local module = ns.modules.QuestPins
local internal = module.internal

-- QuestieDB's quest sorts (a negative zoneOrSort, which `ns.QuestieDB.Quest` gives as a positive
-- `sortID`; src/corrections/enum/quests.lua): the holidays, shown only when asked (nothing here
-- knows when an event runs; Darkmoon Faire isn't in Forever), and the war effort of Ahn'Qiraj's
-- opening. Seed from QuestieDB's enum at commit d57637f4.
local HOLIDAY = ns.GameData.New("questPinsHolidaySorts", { [404] = true, [402] = true, [378] = true,
    [376] = true, [375] = true, [374] = true, [370] = true, [369] = true, [366] = true, [364] = true,
    [41] = true, [22] = true, [21] = true }, { label = "Quest Pins: holiday quest categories" })
local WAR_EFFORT = 365

-- The bits of QuestieDB's race mask each side's races have: the race ID less one for Classic's
-- eight, and bits 33 and 34 for Forever's two new races (its Forever masks use them; which race
-- IDs the client gives those isn't checked). A race past the eight is judged by its side's bits.
local CLASSIC_RACES = 8
local SIDE_BITS = { Alliance = { 1, 3, 4, 7, 33 }, Horde = { 2, 5, 6, 8, 34 } }

-- The client's quest tags for a dungeon or a raid (Classic's: Dungeon, Raid, Heroic, Raid 10 and
-- 25, Scenario).
local INSTANCE_TAGS = { [81] = true, [62] = true, [85] = true, [88] = true, [89] = true, [98] = true }
local tagged = {} -- quest ID -> true or false, once the client has answered

-- Whether a mask of races or classes has the bit of an ID (1, 2, 3, ... from the lowest bit).
local function inMask(mask, id)
    return floor(mask / 2 ^ (id - 1)) % 2 == 1
end

-- Whether a race mask has the player's race: by its own bit, or for a race past Classic's eight,
-- by any bit of its side. A side the game doesn't name lets the quest show.
local function raceInMask(mask, race)
    if race <= CLASSIC_RACES then
        return inMask(mask, race)
    end
    local bits = SIDE_BITS[UnitFactionGroup("player") or ""]
    if not bits then
        return true
    end
    for _, bit in ipairs(bits) do
        if inMask(mask, bit) then
            return true
        end
    end
    return false
end

local function isInstance(id, info)
    local known = tagged[id]
    if known == nil and C_QuestLog and C_QuestLog.GetQuestTagInfo then
        local tag = C_QuestLog.GetQuestTagInfo(id)
        if type(tag) == "table" and tag.tagID then
            known = INSTANCE_TAGS[tag.tagID] == true
            tagged[id] = known
        end
    end
    if known ~= nil then
        return known
    end
    return info.raid
end

---What a quest is for its pin's color and its kind's checkbox: "holiday", "instance", "class",
---"profession", "repeatable", "war", or "normal".
---@param id number
---@return string
function internal.Category(id)
    local info = internal.info[id]
    if not info then
        return "normal"
    end
    if info.sort and HOLIDAY:Get(info.sort) then
        return "holiday"
    elseif isInstance(id, info) then
        return "instance"
    elseif info.classes then
        return "class"
    elseif info.skill then
        return "profession"
    elseif info.sort == WAR_EFFORT then
        return "war"
    elseif info.repeatable then
        return "repeatable"
    end
    return "normal"
end

-- The AQ war effort -------------------------------------------------------------------------------
-- Nothing says which phase the realm is in, so the war effort's quests show only once one has been
-- seen: in the quest log (this session or before), unless Always Show is on.

local warSeen = false

---Notes that the player has a war effort quest, called as quests are accepted.
function internal.NoteWarEffort()
    warSeen = false -- looked for again
end

local function warEffortSeen()
    if warSeen then
        return true
    end
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local entry = C_QuestLog.GetInfo(i)
        local info = entry and not entry.isHeader and internal.info[entry.questID]
        if info and info.sort == WAR_EFFORT then
            warSeen = true
            return true
        end
    end
    return false
end

-- The prerequisites ---------------------------------------------------------------------------------

local met

-- A prerequisite quest is as good as done when it's turned in, a breadcrumb (skippable), or a quest
-- no NPC gives (an object or item starts it, so it often never shows as turned in) whose own
-- prerequisites are met and that the player isn't in the middle of.
local function satisfied(id, seen)
    if internal.Done(id) then
        return true
    end
    local info = internal.info[id]
    if not info then
        return false
    end
    if info.breadcrumbFor then
        return true
    end
    if info.npcGiver or internal.InLog(id) or seen[id] then
        return false
    end
    seen[id] = true
    return (info.all or info.any) ~= nil and met(info, seen)
end

met = function(info, seen)
    for _, id in ipairs(info.all or {}) do
        if not satisfied(id, seen) then
            return false, "prerequisite"
        end
    end
    if info.any then
        for _, id in ipairs(info.any) do
            if satisfied(id, seen) then
                return true
            end
        end
        return false, "prerequisite"
    end
    return true
end

-- The player -----------------------------------------------------------------------------------------

local function skillMet(info)
    local Professions = ns.Professions
    if not (GetProfessions and GetProfessionInfo) then
        return true
    end
    local rank = Professions.Rank(info.skill)
    return rank ~= nil and rank >= (info.skillValue or 0)
end

-- The player's reputation with a faction as one number, as QuestieDB's requirements are (0 at the
-- start of Neutral, 3000 at Friendly), or nil. Probe: Mainline's call, and whether its
-- currentStanding is on that scale isn't checked on Forever.
local function standing(factionID)
    local reputation = _G.C_Reputation
    local get = reputation and reputation.GetFactionDataByID
    local data = get and get(factionID)
    local value = type(data) == "table" and data.currentStanding
    return ns.IsNumber(value) and value or nil
end

-- Whether the player's reputation fits a quest's: at least its lowest, and under its highest. A
-- faction the game doesn't answer for keeps the quest shown.
local function reputationMet(info)
    local low, high = info.minRep, info.maxRep
    local have = low and standing(low.id)
    if have and have < low.value then
        return false
    end
    have = high and standing(high.id)
    if have and have >= high.value then
        return false
    end
    return true
end

local function levelOf(id, info)
    local level = C_QuestLog and C_QuestLog.GetQuestDifficultyLevel and C_QuestLog.GetQuestDifficultyLevel(id)
    if type(level) == "number" and level > 0 then
        return level
    end
    return info.level or info.required
end

---A quest's level as the game or QuestieDB has it, or nil.
---@param id number
---@return number?
function internal.Level(id)
    local info = internal.info[id]
    return info and levelOf(id, info) or nil
end

---Whether the player can take a quest and has a reason to see its pin: true, or false with why
---("done", "log", "hidden", "kind", "war effort", "prerequisite", "taken", "race", "class",
---"skill", "level", "reputation", "low", "high"). True comes with "upcoming" for a quest the
---player is a few levels short of, shown ahead of time with Upcoming Quests on, or "low" for a
---low-level quest shown faded.
---@param id number
---@return boolean
---@return string? why
function internal.Check(id)
    local info = internal.info[id]
    if not info then
        return false, "unknown"
    end
    local db = module.db
    if internal.Done(id) then
        return false, "done"
    elseif internal.InLog(id) then
        return false, "log"
    elseif db.hidden[id] then
        return false, "hidden"
    end
    local kind = internal.Category(id)
    if kind == "holiday" and not db.holiday or kind == "instance" and not db.dungeon or kind == "class" and not db.class
        or kind == "profession" and not db.profession or kind == "normal" and not db.normal
        or kind == "repeatable" and not db.repeatable then
        return false, "kind"
    elseif kind == "war" and not (db.warEffort and (db.warEffortAlways or warEffortSeen())) then
        return false, "war effort"
    end
    for _, other in ipairs(info.exclusive or {}) do
        if internal.Done(other) then
            return false, "taken"
        end
    end
    -- A breadcrumb leads to a quest: no use once that one is done or begun.
    if info.breadcrumbFor and (internal.Done(info.breadcrumbFor) or internal.InLog(info.breadcrumbFor)) then
        return false, "taken"
    end
    local ok, why = met(info, {})
    if not ok then
        return false, why
    end
    if info.races then
        local _, _, race = UnitRace("player")
        if race and not raceInMask(info.races, race) then
            return false, "race"
        end
    end
    if info.classes then
        local _, _, class = UnitClass("player")
        if class and not inMask(info.classes, class) then
            return false, "class"
        end
    end
    if info.skill and not skillMet(info) then
        return false, "skill"
    end
    local player = UnitLevel("player")
    if info.max and player > info.max then
        return false, "level"
    end
    local upcoming = info.required ~= nil and player < info.required
    if upcoming and not (db.upcoming and info.required - player <= db.upcomingLevels) then
        return false, "level"
    end
    if db.reputation and not reputationMet(info) then
        return false, "reputation"
    end
    local level = levelOf(id, info)
    local low = level ~= nil and db.low ~= "off" and player - level >= db.lowGap
    if low and db.low == "hide" then
        return false, "low"
    elseif level and db.hideHigh and level - player >= db.highGap then
        return false, "high"
    end
    return true, upcoming and "upcoming" or low and "low" or nil
end

---The level a quest needs, for an upcoming one's tooltip line.
---@param id number
---@return number?
function internal.RequiredLevel(id)
    local info = internal.info[id]
    return info and info.required or nil
end

---Whether a giver QuestieDB says is friendly to one side or both is friendly to the player's.
---@param friendly string? "A", "H", or "AH"
---@return boolean
function internal.FriendlyToPlayer(friendly)
    if not friendly then
        return true
    end
    local side = UnitFactionGroup("player")
    local letter = side == "Alliance" and "A" or side == "Horde" and "H" or nil
    return letter == nil or friendly:find(letter, 1, true) ~= nil
end

---`/fpp questpins why <id>`: says in chat why a quest is pinned or not.
---@param id number?
function internal.Why(id)
    if not id then
        ns.Print(L.QUESTPINS_USAGE)
    elseif not internal.ready then
        ns.Print(L.QUESTPINS_NOT_READY)
    else
        local ok, why = internal.Check(id)
        ns.Print(format(L.QUESTPINS_WHY, id, ok and L.QUESTPINS_WHY_SHOWN or why or "?"))
    end
end
