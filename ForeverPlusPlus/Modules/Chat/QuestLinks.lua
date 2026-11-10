-- Quest Links: a quest someone typed as Questie writes one, [[34] A Grim Task (304)], becomes one
-- of Blizzard's own quest links, [[34] A Grim Task], which shows the quest when clicked. Questie
-- links a quest as its own hyperlink, which the server turns into plain text for everyone else, so
-- only players with Questie could click it; the ID in it is all a quest link needs, so no quest
-- database is needed. A line is rewritten once it's in the chat window (Chat.Transform), as Short
-- Channel Names does. Text already inside a link (Questie's own, when it's loaded) is left alone,
-- and so are lines the game marks secret.
local _, ns = ...

local ipairs, tonumber, gsub, find, sub, format = ipairs, tonumber, string.gsub, string.find, string.sub, string.format

local L = ns.L
local Chat = ns.Chat

local module = ns.NewModule("QuestLinks", L.QUESTLINKS_DESC, {
    enabled = false,
})
module.title = L.QUESTLINKS_TITLE
module.category = "chat"
module.added = "1.5.0"

-- Questie's text: [[level] name (id)], the level maybe with a letter or + after it (34+ elite,
-- 34D dungeon). The position is to skip one already inside a link.
local PLAIN = "()%[%[(%d+[^%]]*)%] ([^%]|]-) %((%d+)%)%]"
-- Our link, to take it out again: the color, quest:id:level, and the shown text.
local LINK = "|cffffff00|Hquest:(%d+):%d+|h%[%[([^%]]*)%] ([^%]|]-)%]|h|r"

---A chat line with each of Questie's plain quests made a quest link.
---@param text string
---@return string
local function rewrite(text)
    if not find(text, "[[", 1, true) then
        return text
    end
    return (gsub(text, PLAIN, function(at, level, name, id)
        if sub(text, at - 2, at - 1) == "|h" then
            return nil -- already a link's text
        end
        return format("|cffffff00|Hquest:%s:%d|h[[%s] %s]|h|r", id, tonumber(level:match("%d+")), level, name)
    end))
end

---A chat line with our quest links back as the plain text they came from.
---@param text string
---@return string
local function restore(text)
    return (gsub(text, LINK, "[[%2] %3 (%1)]"))
end

local function onMessage(frame, text)
    if not ns.IsText(text) then
        return
    end
    local linked = rewrite(text)
    if linked == text then
        return
    end
    Chat.Transform(frame, function(message)
        return message == text
    end, function()
        return linked
    end)
end

function module:IsAvailable()
    return ChatFrame1 ~= nil and ChatFrame1.TransformMessages ~= nil
end

function module:OnEnable()
    Chat.EachWindow(self, function(frame)
        module:Hook(frame, "AddMessage", onMessage)
    end)
end

-- Lines already linked go back to plain text, so turning the module off undoes it.
function module:OnDisable()
    for _, frame in ipairs(Chat.Frames()) do
        Chat.Transform(frame, function(message)
            return restore(message) ~= message
        end, restore)
    end
end
