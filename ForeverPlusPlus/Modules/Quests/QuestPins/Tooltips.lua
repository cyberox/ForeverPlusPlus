-- Quest Pins on an NPC's tooltip: the quests it offers that the player can take (!) and the quests
-- in the log that are ready to turn in to it (?), from QuestieDB's lists for that NPC.
local _, ns = ...

local type, ipairs, tonumber, format, sort = type, ipairs, tonumber, string.format, table.sort
local C_QuestLog, GameTooltip, IsInInstance = C_QuestLog, GameTooltip, IsInInstance
local GetQuestDifficultyColor, NORMAL_FONT_COLOR = GetQuestDifficultyColor, NORMAL_FONT_COLOR

local QuestieDB = ns.QuestieDB
local module = ns.modules.QuestPins
local internal = module.internal

-- The NPC's ID from a unit GUID in tooltip data, or nil (a secret GUID in combat isn't read).
local function npcID(guid)
    if not ns.IsText(guid) then
        return nil
    end
    return tonumber(guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
        or tonumber(guid:match("^Vehicle%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
end

local function row(id, marker)
    local title = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)
    if not title or title == "" then
        local q = QuestieDB.Quest(id)
        title = q and q.name or format(ns.L.QUESTPINS_QUEST, id)
    end
    local info = internal.info[id]
    local level = C_QuestLog.GetQuestDifficultyLevel and C_QuestLog.GetQuestDifficultyLevel(id)
    if not (type(level) == "number" and level > 0) then
        level = info and (info.level or info.required) or nil
    end
    return { id = id, level = level, text = format("%s %s%s", marker, level and ("[" .. level .. "] ") or "", title) }
end

local function onUnit(tooltip, data)
    local db = module.db
    if tooltip ~= GameTooltip or not db.npcTooltips or not internal.ready
        or (tooltip.IsForbidden and tooltip:IsForbidden()) or IsInInstance() then
        return
    end
    local id = data and npcID(data.guid)
    local npc = id and QuestieDB.Npc(id)
    if not npc then
        return
    end
    local rows = {}
    for _, questID in ipairs(npc.questStarts) do
        local ok, note = internal.Check(questID)
        -- Not an upcoming quest: the NPC doesn't offer it yet.
        if ok and note ~= "upcoming" and internal.FriendlyToPlayer(npc.friendlyTo) then
            rows[#rows + 1] = row(questID, "!")
        end
    end
    for _, questID in ipairs(npc.questEnds) do
        if internal.InLog(questID) and not internal.Done(questID) and not db.hidden[questID]
            and C_QuestLog.IsComplete(questID) then
            rows[#rows + 1] = row(questID, "?")
        end
    end
    sort(rows, function(a, b)
        if a.level ~= b.level then
            return (a.level or 1000) < (b.level or 1000)
        end
        return a.id < b.id
    end)
    for _, r in ipairs(rows) do
        local color = r.level and GetQuestDifficultyColor(r.level) or NORMAL_FONT_COLOR
        tooltip:AddLine(r.text, color.r, color.g, color.b, true)
    end
    if #rows > 0 then
        tooltip:Show()
    end
end

---Adds the lines to unit tooltips, while the module is on.
function internal.HookTooltips()
    module:TooltipPostCall(Enum.TooltipDataType.Unit, onUnit)
end
