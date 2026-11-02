-- Chat Levels: a player's level before their name in chat, [60:Name], in the color of that level
-- against yours, like a quest's. The level is the last one Forever++ saw (ns.Players): from your
-- group, guild, friends, who results, and players you target, mouse over, or see nearby, so it
-- shows for people far away too. Blizzard's chat already colors names by class from the GUID.
-- Blizzard builds the name link itself, so the finished line is rewritten through the chat
-- frame's own TransformMessages, a frame after it arrives, as Chat Copy does, so other modules
-- rewriting the same line see it first. Lines the game marks secret are left alone.
local _, ns = ...

local ipairs, pairs, tonumber, gsub, find, match = ipairs, pairs, tonumber, string.gsub, string.find, string.match
local C_ChatInfo, GetQuestDifficultyColor = C_ChatInfo, GetQuestDifficultyColor

local L = ns.L
local Chat = ns.Chat

local module = ns.NewModule("ChatLevels", L.CHATLEVELS_DESC, {
    enabled = false,
})
module.title = L.CHATLEVELS_TITLE
module.category = "chat"
module.added = "1.0.0-beta.1"

-- Blizzard's name link: |Hplayer:Name-Surname:lineID:CHANNEL:target|h[Name]|h, the name often in
-- its class color.
local LINK = "(|Hplayer:([^|]*)|h%[)"
-- Our level in a link, to take it out again: a color code, digits, |r, and a colon.
local TAGGED = "(|Hplayer:[^|]*|h%[)|c%x%x%x%x%x%x%x%x%d+|r:"

-- The level of the player a name link is for, or nil.
local function levelOf(data)
    local name, lineID = match(data, "^([^:]*):?(%d*)")
    local guid
    lineID = tonumber(lineID)
    if lineID and C_ChatInfo and C_ChatInfo.GetChatLineSenderGUID then
        guid = C_ChatInfo.GetChatLineSenderGUID(lineID)
    end
    local seen = ns.Players.Get(ns.IsText(guid, true) and guid or nil, name)
    return seen and seen.level
end

local function tag(level)
    local color = GetQuestDifficultyColor and GetQuestDifficultyColor(level)
    local code = color and ns.Colors.Code(color.r, color.g, color.b) or "|cffffffff"
    return code .. level .. "|r:"
end

---A chat line with a level put in each player link that has none yet, when it's known.
---@param text string
---@return string
local function rewrite(text)
    return (gsub(text, LINK, function(open, data)
        local level = levelOf(data)
        if level then
            return open .. tag(level)
        end
    end))
end

local function tagged(text)
    return find(text, TAGGED) ~= nil
end

local pending = {} -- chat window -> { [lineID] = true } for its lines since the last pass

local function tagPending()
    for frame, lines in pairs(pending) do
        pending[frame] = nil
        Chat.Transform(frame, function(message)
            local id = match(message, "|Hplayer:[^:|]*:(%d+)")
            return id ~= nil and lines[id] and not tagged(message) and rewrite(message) ~= message
        end, rewrite)
    end
end

local tagSoon, cancelTag = ns.Frames.Coalesce(tagPending, nil, module)

local function onMessage(frame, text)
    if not ns.IsText(text) then
        return
    end
    local id = match(text, "|Hplayer:[^:|]*:(%d+)")
    if not id then
        return
    end
    local lines = pending[frame] or {}
    lines[id] = true
    pending[frame] = lines
    tagSoon()
end

function module:IsAvailable()
    return ChatFrame1 ~= nil and ChatFrame1.TransformMessages ~= nil
end

function module:OnEnable()
    ns.Players.Use(self)
    Chat.EachWindow(self, function(frame)
        module:Hook(frame, "AddMessage", onMessage)
    end)
end

-- Lines already tagged lose their levels, so turning the module off undoes it.
function module:OnDisable()
    ns.Players.Release(self)
    cancelTag()
    for frame in pairs(pending) do
        pending[frame] = nil
    end
    for _, frame in ipairs(Chat.Frames()) do
        Chat.Transform(frame, tagged, function(message)
            return (gsub(message, TAGGED, "%1"))
        end)
    end
end
