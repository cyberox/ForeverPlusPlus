-- Short Channel Names: [1. General] becomes [1], [G], [1. G], or another short form in chat, and
-- optionally [Guild], [Party], [Raid] and the like become [GD], [P], [R]. Blizzard builds the
-- channel link from the channel's full name, so this rewrites the finished line after it is added
-- to the window, through the chat frame's own TransformMessages (the line stays a working link).
-- Lines the game marks secret can't be read and are left alone.
local _, ns = ...

local pairs, ipairs, gsub, tonumber, concat = pairs, ipairs, string.gsub, tonumber, table.concat
local find, sub, type, tostring, _G = string.find, string.sub, type, tostring, _G

local L = ns.L
local Chat = ns.Chat

local module = ns.NewModule("ShortChannelNames", L.SHORTCHANNELNAMES_DESC, {
    enabled = false,
    style = "numberInitials",
    chatTypes = true,
})
module.title = L.SHORTCHANNELNAMES_TITLE
module.category = "chat"
module.presets = { developer = { enabled = true } }

module.options = {
    {
        key = "style",
        name = L.SHORTCHANNELNAMES_STYLE,
        description = L.SHORTCHANNELNAMES_STYLE_DESC,
        changed = "0.9.0",
        choices = {
            { "number", L.SHORTCHANNELNAMES_NUMBER },
            { "letter", L.SHORTCHANNELNAMES_LETTER },
            { "initials", L.SHORTCHANNELNAMES_INITIALS },
            { "name", L.SHORTCHANNELNAMES_NAME },
            { "both", L.SHORTCHANNELNAMES_BOTH },
            { "numberInitials", L.SHORTCHANNELNAMES_NUMBER_INITIALS },
            { "numberName", L.SHORTCHANNELNAMES_NUMBER_NAME },
        },
    },
    {
        key = "chatTypes",
        name = L.SHORTCHANNELNAMES_CHAT_TYPES,
        description = L.SHORTCHANNELNAMES_CHAT_TYPES_DESC,
        added = "0.9.0",
    },
}

-- The first character of a name, whole, even when it takes several bytes (UTF-8).
local FIRST_CHARACTER = "^[%z\1-\127\194-\244][\128-\191]*"

---A channel's initials: the first character of each word, and each capital inside a word, of
---its name before any " - Zone" part. General and Trade give G and T, LocalDefense and
---LookingForGroup give LD and LFG, and Forever's Trade (Services) TS: punctuation around a word
---is skipped. Nil for an empty name.
---@param name string
---@return string?
local function initials(name)
    local base = name:match("^(.-) %- ") or name
    local letters = {}
    for word in base:gmatch("%S+") do
        word = gsub(word, "^%p+", "")
        local first = word:match(FIRST_CHARACTER)
        if first then
            letters[#letters + 1] = first
            for capital in word:sub(#first + 1):gmatch("%u") do
                letters[#letters + 1] = capital
            end
        end
    end
    local text = concat(letters)
    return text ~= "" and text or nil
end

-- Each style's short form of a channel, from its number and full name: the part before the
-- number's ". ", if any, and the part after it.
local FORMS = {
    number = function() return nil end,
    letter = function(name) return name:match(FIRST_CHARACTER) end,
    initials = initials,
    name = function(name) return name:match("^(.-) %- ") or name end,
}
FORMS.both, FORMS.numberInitials, FORMS.numberName = FORMS.letter, FORMS.initials, FORMS.name
local NUMBERED = { number = true, both = true, numberInitials = true, numberName = true }

---A channel's short form in a style: [1], [G], [LFG], [General], [1. G], [1. LFG], or [1. General].
---@param style string
---@param number string
---@param name string
---@return string
local function shortName(style, number, name)
    local form = FORMS[style] or FORMS.number
    local part = name ~= "" and form(name) or nil
    if not part or part == "" then
        return number
    end
    return NUMBERED[style] and number .. ". " .. part or part
end

-- Guild, party, raid, and the like: Blizzard's format string for the line, and our short name.
-- The line starts with the format's part before the speaker ("|Hchannel:GUILD|h[Guild]|h"), in
-- the client's language, so that part is what's swapped.
local CHAT_TYPES = {
    { "CHAT_GUILD_GET", L.SHORTCHANNELNAMES_GUILD },
    { "CHAT_OFFICER_GET", L.SHORTCHANNELNAMES_OFFICER },
    { "CHAT_PARTY_GET", L.SHORTCHANNELNAMES_PARTY },
    { "CHAT_PARTY_LEADER_GET", L.SHORTCHANNELNAMES_PARTY_LEADER },
    { "CHAT_PARTY_GUIDE_GET", L.SHORTCHANNELNAMES_PARTY_GUIDE },
    { "CHAT_RAID_GET", L.SHORTCHANNELNAMES_RAID },
    { "CHAT_RAID_LEADER_GET", L.SHORTCHANNELNAMES_RAID_LEADER },
    { "CHAT_RAID_WARNING_GET", L.SHORTCHANNELNAMES_RAID_WARNING },
    { "CHAT_INSTANCE_CHAT_GET", L.SHORTCHANNELNAMES_INSTANCE },
    { "CHAT_INSTANCE_CHAT_LEADER_GET", L.SHORTCHANNELNAMES_INSTANCE_LEADER },
}

local prefixes -- { full, short } for each chat type this client has, made when first needed

local function chatTypePrefixes()
    if prefixes then
        return prefixes
    end
    prefixes = {}
    for _, entry in ipairs(CHAT_TYPES) do
        local format = _G[entry[1]]
        local full = type(format) == "string" and format:match("^(.-%])")
        if full then
            local short = (gsub(full, "%[[^%]]*%]", function()
                return "[" .. entry[2] .. "]"
            end, 1))
            prefixes[#prefixes + 1] = { full, short }
        end
    end
    return prefixes
end

---`text` with the first `from` in it, found as plain text, replaced by `to`.
local function swap(text, from, to)
    local first, last = find(text, from, 1, true)
    if not first then
        return text
    end
    return sub(text, 1, first - 1) .. to .. sub(text, last + 1)
end

-- The rendered link is |Hchannel:channel:5|h[5. General - Elwynn Forest]|h.
local LINK = "(|Hchannel:channel:%d+|h%[)(%d+)%. ([^%]]-)(%]|h)"

---A chat line with its numbered channel link, or its guild, party, or raid name, shortened.
---@param text string
---@return string
local function rewrite(text)
    if find(text, "|Hchannel:channel:", 1, true) then
        return (gsub(text, LINK, function(open, number, name, close)
            return open .. shortName(module.db.style, number, name) .. close
        end))
    end
    if module.db.chatTypes then
        for _, prefix in ipairs(chatTypePrefixes()) do
            local short = swap(text, prefix[1], prefix[2])
            if short ~= text then
                return short
            end
        end
    end
    return text
end

local function onMessage(frame, text)
    if not ns.IsText(text) then
        return
    end
    local short = rewrite(text)
    if short == text then
        return
    end
    Chat.Transform(frame, function(message)
        return message == text
    end, function()
        return short
    end)
end

-- The chat box's header ----------------------------------------------------------------------
-- While typing, the box starts with where the line goes: "[2. Trade - City]: " or "Party: ".
-- Blizzard writes it in the edit box's UpdateHeader (ChatFrameEditBoxMixin, Gethe forever branch)
-- and makes room for it with the box's text insets; after it, the same short form as in chat goes
-- in its place and the insets shrink by the width saved. Each window's box is hooked, since the
-- method is copied onto each from the mixin.

-- The chat types whose header has a short form, by the edit box's chat type.
local SEND_TYPES = {
    GUILD = L.SHORTCHANNELNAMES_GUILD,
    OFFICER = L.SHORTCHANNELNAMES_OFFICER,
    PARTY = L.SHORTCHANNELNAMES_PARTY,
    RAID = L.SHORTCHANNELNAMES_RAID,
    RAID_WARNING = L.SHORTCHANNELNAMES_RAID_WARNING,
    INSTANCE_CHAT = L.SHORTCHANNELNAMES_INSTANCE,
}

-- The header's text shortened, or nil to leave it. A header already short isn't matched again,
-- so running twice (UpdateHeader calls itself when it switches party to instance) changes nothing.
local function shortHeader(editBox, text)
    local chatType = editBox.GetChatType and editBox:GetChatType()
    if chatType == "CHANNEL" and editBox.GetChannelTarget then
        local id, name, instanceID = GetChannelName(editBox:GetChannelTarget())
        if type(id) ~= "number" or type(name) ~= "string" or name == "" then
            return nil
        end
        -- As Blizzard names it there: a channel of an instance has its number after the name.
        if type(instanceID) == "number" and instanceID > 0 then
            name = name .. " " .. instanceID
        end
        local number = tostring(id)
        return swap(text, number .. ". " .. name, shortName(module.db.style, number, name))
    end
    local short = module.db.chatTypes and SEND_TYPES[chatType]
    local full = short and _G["CHAT_" .. chatType .. "_SEND"]
    local label = type(full) == "string" and full:match("^(.-)%s*:")
    if label and label ~= "" then
        return swap(text, label, short)
    end
end

local function onUpdateHeader(editBox)
    local name = editBox.GetName and editBox:GetName()
    local header = name and _G[name .. "Header"]
    local text = header and header:GetText()
    if not ns.IsText(text) then
        return
    end
    local short = shortHeader(editBox, text)
    if not short or short == text then
        return
    end
    -- The room Blizzard left: the header, and the "..." after one it cut short.
    local suffix = _G[name .. "HeaderSuffix"]
    local before = header:GetWidth() + (suffix and suffix:IsShown() and suffix:GetWidth() or 0)
    header:SetWidth(0)
    header:SetText(short)
    if suffix then
        suffix:Hide()
    end
    local left, right, top, bottom = editBox:GetTextInsets()
    if left then
        editBox:SetTextInsets(left - before + header:GetStringWidth(), right, top, bottom)
        -- Blizzard runs UpdateHeader on every key, after the box has placed its cursor for the
        -- wider insets, and new insets move the text but not the cursor: it stood off to the right
        -- of what was typed, by the width saved (seen in game 2026-11-12). Moving the cursor
        -- makes the box place it again. Unverified in game: that a step back and forth does it.
        local at = editBox.GetCursorPosition and editBox:GetCursorPosition()
        if ns.IsNumber(at) then
            if at > 0 then
                editBox:SetCursorPosition(at - 1)
            end
            editBox:SetCursorPosition(at)
        end
    end
end

function module:IsAvailable()
    return ChatFrame1 ~= nil and ChatFrame1.TransformMessages ~= nil
end

function module:OnEnable()
    -- Every window, and one added later.
    Chat.EachWindow(self, function(frame)
        module:Hook(frame, "AddMessage", onMessage)
        local editBox = frame.editBox or _G[(frame:GetName() or "") .. "EditBox"]
        module:Hook(editBox, "UpdateHeader", onUpdateHeader)
    end)
end

-- A shortened link, to put the name back: |Hchannel:channel:5|h[5. G]|h.
local SHORT_LINK = "(|Hchannel:channel:(%d+)|h%[)([^%]]-)(%]|h)"

---A chat line with its shortened channel link given its full name again, as the channel is named
---now, or its short guild, party, or raid name made whole. Only an inner text that is one of our
---short forms for that channel is replaced.
---@param text string
---@return string
local function restore(text)
    if find(text, "|Hchannel:channel:", 1, true) then
        return (gsub(text, SHORT_LINK, function(open, number, inner, close)
            local _, name = GetChannelName(tonumber(number))
            if type(name) ~= "string" or name == "" then
                return nil
            end
            -- Any style's form, since the style may have changed since the line was shortened.
            for style in pairs(FORMS) do
                if inner == shortName(style, number, name) then
                    return open .. number .. ". " .. name .. close
                end
            end
            return nil
        end))
    end
    for _, prefix in ipairs(chatTypePrefixes()) do
        local full = swap(text, prefix[2], prefix[1])
        if full ~= text then
            return full
        end
    end
    return text
end

-- Lines already shortened get their names back, so turning the module off undoes it.
function module:OnDisable()
    for _, frame in ipairs(Chat.Frames()) do
        Chat.Transform(frame, function(message)
            return restore(message) ~= message
        end, restore)
    end
end
