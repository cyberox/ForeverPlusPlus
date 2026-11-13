-- Quest Pins' rules: which quests the player can take, from what Index.lua read of QuestieDB and
-- what the game says of the player. Unknown restrictions keep a quest shown.
local _, ns = ...

local type, floor, format = type, math.floor, string.format
local UnitLevel, UnitRace, UnitClass, UnitFactionGroup = UnitLevel, UnitRace, UnitClass, UnitFactionGroup
local C_QuestLog = C_QuestLog

local L = ns.L
local module = ns.modules.QuestPins
local internal = module.internal

-- QuestieDB's quest sorts (negative zoneOrSort, src/corrections/enum/quests.lua): the holidays,
-- which never show (nothing here knows when an event runs; Darkmoon Faire isn't in Forever), and
-- the war effort of Ahn'Qiraj's opening.
local HOLIDAY = { [-404] = true, [-402] = true, [-378] = true, [-376] = true, [-375] = true,
    [-374] = true, [-370] = true, [-369] = true, [-366] = true, [-364] = true, [-41] = true,
    [-22] = true, [-21] = true }
local WAR_EFFORT = -365

-- The client's quest tags for a dungeon or a raid (Classic's: Dungeon, Raid, Heroic, Raid 10 and
-- 25, Scenario).
local INSTANCE_TAGS = { [81] = true, [62] = true, [85] = true, [88] = true, [89] = true, [98] = true }
local tagged = {} -- quest ID -> true or false, once the client has answered

-- Whether a mask of races or classes has the bit of an ID (1, 2, 3, ... from the lowest bit).
local function inMask(mask, id)
    return floor(mask / 2 ^ (id - 1)) % 2 == 1
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

---What a quest is for its pin's color and its kind's checkbox: "instance", "class", "profession",
---"repeatable", "war", or "normal".
---@param id number
---@return string
function internal.Category(id)
    local info = internal.info[id]
    if not info then
        return "normal"
    end
    if isInstance(id, info) then
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

local function levelOf(id, info)
    local level = C_QuestLog and C_QuestLog.GetQuestDifficultyLevel and C_QuestLog.GetQuestDifficultyLevel(id)
    if type(level) == "number" and level > 0 then
        return level
    end
    return info.level or info.required
end

---Whether the player can take a quest and has a reason to see its pin: true, or false with why
---("done", "log", "hidden", "kind", "event", "war effort", "prerequisite", "taken", "race",
---"class", "skill", "level", "low", "high").
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
    if HOLIDAY[info.sort] then
        return false, "event"
    elseif kind == "instance" and not db.dungeon or kind == "class" and not db.class
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
        if race and not inMask(info.races, race) then
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
    if info.required and player < info.required or info.max and player > info.max then
        return false, "level"
    end
    local level = levelOf(id, info)
    if level and db.hideLow and player - level >= db.lowGap then
        return false, "low"
    elseif level and db.hideHigh and level - player >= db.highGap then
        return false, "high"
    end
    return true
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
