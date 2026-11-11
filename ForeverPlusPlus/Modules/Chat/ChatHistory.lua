-- Chat History: keeps each chat window's latest lines across logging out and reloading, for each
-- character on its own. The lines are read from the windows' own buffers as the game logs out
-- (PLAYER_LOGOUT, which a reload also sends), so nothing runs while you play, and put back with
-- AddMessage at login.
-- Colors and links are kept because the lines are saved as they were drawn. A line the game
-- marks secret can't be read, so it isn't saved. Whispers aren't saved either: SavedVariables are
-- plain text that players often share when reporting a bug.
local _, ns = ...

local pairs, ipairs, type, max, setmetatable = pairs, ipairs, type, math.max, setmetatable
local GetChatTypeIndex = GetChatTypeIndex

local L = ns.L
local Chat = ns.Chat

local module = ns.NewModule("ChatHistory", L.CHATHISTORY_DESC, {
    lines = 100,
    divider = false,
    arrows = false, -- Up and Down in the chat box recall what you sent, without holding Alt
    saved = {}, -- chat window number -> { { text, r, g, b }, ... }
})
module.title = L.CHATHISTORY_TITLE
module.category = "chat"
module.developer = { options = { divider = true, arrows = true } }
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
    { key = "arrows", name = L.CHATHISTORY_ARROWS, description = L.CHATHISTORY_ARROWS_DESC, added = "1.5.0" },
}

-- Arrow Keys Recall Messages ------------------------------------------------------------------
-- The chat box already remembers what you sent, but reads the arrow keys only with Alt held, so
-- they keep moving your character while it's open (its "alt arrow key mode"). With that off, Up
-- and Down step through what you sent and Left and Right move in the text. It's the game's own
-- history and the game's own typing, so a recalled slash command is sent as if typed; nothing of
-- ours writes into the box. Each box's own mode is kept to put back.

local arrowModes = setmetatable({}, { __mode = "k" }) -- edit box -> its mode before ours

local function editBoxOf(frame)
    return frame.editBox or _G[(frame:GetName() or "") .. "EditBox"]
end

local function applyArrows(frame)
    local box = editBoxOf(frame)
    if not (box and box.SetAltArrowKeyMode and box.GetAltArrowKeyMode) then
        return
    end
    local on = module.enabled and module.db.arrows
    if on and arrowModes[box] == nil then
        arrowModes[box] = box:GetAltArrowKeyMode() and true or false
        box:SetAltArrowKeyMode(false)
    elseif not on and arrowModes[box] ~= nil then
        box:SetAltArrowKeyMode(arrowModes[box])
        arrowModes[box] = nil
    end
end

local function applyArrowsAll()
    for _, frame in ipairs(Chat.Frames()) do
        applyArrows(frame)
    end
end

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
            if not whisper and ns.IsText(text)
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
                frame:AddMessage(line[1], line[2], line[3], line[4])
            end
            if module.db.divider then
                frame:AddMessage(L.CHATHISTORY_DIVIDER, 0.6, 0.6, 0.6)
            end
        end
    end
end

function module:IsAvailable()
    return ChatFrame1 ~= nil and ChatFrame1.GetMessageInfo ~= nil
end

function module:OnEnable()
    self:On("PLAYER_LOGOUT", save)
    self:On("PLAYER_ENTERING_WORLD", restore)
    -- Every window's chat box, and one added later.
    Chat.EachWindow(self, applyArrows)
end

function module:OnDisable()
    self.db.saved = {}
    applyArrowsAll()
end

function module:OnOptionChanged(key)
    if key == "arrows" then
        applyArrowsAll()
    end
end
