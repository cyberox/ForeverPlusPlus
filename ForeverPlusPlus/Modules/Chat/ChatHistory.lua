-- Chat History: keeps each chat window's latest lines across logging out and reloading, for each
-- character on its own. The lines are read from the windows' own buffers as the game logs out
-- (PLAYER_LOGOUT, which a reload also sends), so nothing runs while you play, and put back with
-- AddMessage at login.
-- Colors and links are kept because the lines are saved as they were drawn. A line the game
-- marks secret can't be read, so it isn't saved. Whispers aren't saved either: SavedVariables are
-- plain text that players often share when reporting a bug.
local _, ns = ...

local pairs, ipairs, type, max = pairs, ipairs, type, math.max
local GetChatTypeIndex = GetChatTypeIndex

local L = ns.L
local Chat = ns.Chat

local module = ns.NewModule("ChatHistory", L.CHATHISTORY_DESC, {
    lines = 100,
    divider = false,
    saved = {}, -- chat window number -> { { text, r, g, b }, ... }
})
module.title = L.CHATHISTORY_TITLE
module.category = "chat"
module.presets = { developer = { options = { divider = true } } }
-- Each character's own chat, so an alt doesn't log in to another character's.
module.perCharacter = { saved = true }

-- Up to 0.8.4 the lines were saved for the account. The first character to log in takes them.
ns.MigrateCharacter(2, function(char, db)
    ns.Store.Claim(char, db, "ChatHistory", "saved", function(entries)
        local mine
        for index, lines in pairs(entries) do
            mine = mine or {}
            mine[index] = lines
            entries[index] = nil
        end
        return mine
    end)
end)

-- How much is kept, then how it shows.
module.options = {
    {
        key = "lines",
        name = L.CHATHISTORY_LINES,
        description = L.CHATHISTORY_LINES_DESC,
        -- Blizzard's windows hold 128 lines, so more could never be saved.
        min = 25, max = 125, step = 25, format = "%d",
    },
    { key = "divider", name = L.CHATHISTORY_DIVIDER_OPTION, description = L.CHATHISTORY_DIVIDER_DESC },
}

local WHISPERS = { "WHISPER", "WHISPER_INFORM", "BN_WHISPER", "BN_WHISPER_INFORM" }

-- The chat type ids of whispers, as GetMessageInfo returns them (Blizzard passes ChatTypeInfo's
-- id, from GetChatTypeIndex, to AddMessage).
local function whisperIDs()
    local ids = {}
    for _, chatType in ipairs(WHISPERS) do
        local id = GetChatTypeIndex and GetChatTypeIndex(chatType)
        if type(id) == "number" then
            ids[id] = true
        end
    end
    return ids
end

-- Windows are kept by their number, so only the numbered ones: a temporary window's number belongs
-- to another whisper after a reload. The combat log isn't chat, so it's skipped.
local function isCombatLog(frame)
    return frame == _G.COMBATLOG or (_G.IsCombatLog and _G.IsCombatLog(frame)) and true or false
end

-- The longest line kept, in bytes. A chat line with its links and colors is well under this: it's
-- here so a line something made huge is dropped instead of saved and put back again (see `add`).
local MAX_LINE = 4000

-- Puts a saved line back as it was drawn, through Blizzard's own AddMessage and not the window's.
-- Another chat addon replaces a window's AddMessage to rewrite each line as it's added: a level
-- before a name, a web address made a link. A saved line already has those, so through the
-- window's AddMessage it got them again at every login and was saved with one more layer each
-- time, and a link inside a link doubles: a Guild Message of the Day with a web address reached
-- 2.4 GB in one character's saved file, and the game ran out of memory loading it (vChat, from a
-- player's files, 2026-11-20). Our own readers of new lines skip these too, which they'd only
-- have read a second time.
local function add(frame, text, r, g, b)
    local mixin = _G.ChatFrameMixin
    local blizzard = mixin and mixin.AddMessage or frame.AddMessage
    blizzard(frame, text, r, g, b)
end

local function keepable(text)
    return ns.IsText(text) and #text <= MAX_LINE
end

local function save()
    local saved = {}
    local whispers = whisperIDs()
    for index, frame in ipairs(Chat.Frames(true)) do
        local total = isCombatLog(frame) and 0 or frame:GetNumMessages()
        local lines = {}
        for i = max(1, total - module.db.lines + 1), total do
            local text, r, g, b, chatTypeID = frame:GetMessageInfo(i)
            -- An unreadable type id is left out too, since it could be a whisper's.
            local whisper = not ns.IsReadable(chatTypeID)
                or (type(chatTypeID) == "number" and whispers[chatTypeID])
            if not whisper and keepable(text)
                and text ~= L.CHATHISTORY_DIVIDER
                and ns.IsReadable(r) and ns.IsReadable(g) and ns.IsReadable(b) then
                lines[#lines + 1] = { text, r, g, b }
            end
        end
        if #lines > 0 then
            saved[index] = lines
        end
    end
    module.db.saved = saved
end

local function restore(_, isLogin, isReload)
    if not (isLogin or isReload) then
        return
    end
    for index, frame in ipairs(Chat.Frames(true)) do
        local lines = not isCombatLog(frame) and module.db.saved[index]
        if lines and #lines > 0 then
            for _, line in ipairs(lines) do
                if type(line) == "table" and keepable(line[1]) then
                    add(frame, line[1], line[2], line[3], line[4])
                end
            end
            if module.db.divider then
                add(frame, L.CHATHISTORY_DIVIDER, 0.6, 0.6, 0.6)
            end
        end
    end
    -- They're in the windows now, and logging out saves the windows again. Let go of the saved
    -- copy so a huge line from before the limit isn't held in memory for the whole session.
    module.db.saved = {}
end

function module:IsAvailable()
    return ChatFrame1 ~= nil and ChatFrame1.GetMessageInfo ~= nil
end

function module:OnEnable()
    self:On("PLAYER_LOGOUT", save)
    self:On("PLAYER_ENTERING_WORLD", restore)
end

function module:OnDisable()
    self.db.saved = {}
end
