-- Chat Sounds: a sound when someone else writes in guild, officer, party, or raid chat, each kind
-- a checkbox with its own sound. Whispers aren't here: Blizzard's chat plays its own sound for
-- those (TELL_MESSAGE, in its chat frame's message handler), and nothing turns that off.
local _, ns = ...

local GetTime, UnitGUID = GetTime, UnitGUID

local L = ns.L

local module = ns.NewModule("ChatSounds", L.CHATSOUNDS_DESC, {
    enabled = false,
    guild = true,
    officer = false,
    party = false,
    raid = false,
    -- Keys of ns.Sounds.CHOICES.
    guildSound = "whisper",
    officerSound = "gm",
    partySound = "whisper",
    raidSound = "whisper",
})
module.title = L.CHATSOUNDS_TITLE
module.category = "chat"
module.added = "1.9.0"
module.notice = { text = L.CHATSOUNDS_NOTICE, description = L.CHATSOUNDS_NOTICE_DESC }

-- Each kind of chat: its checkbox's key (its dropdown's is that with "Sound"), and its events.
local KINDS = {
    { key = "guild", events = { "CHAT_MSG_GUILD" } },
    { key = "officer", events = { "CHAT_MSG_OFFICER" } },
    { key = "party", events = { "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER" } },
    { key = "raid", events = { "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER" } },
}

module.options = {}
for _, kind in ipairs(KINDS) do
    local upper = kind.key:upper()
    module.options[#module.options + 1] = {
        key = kind.key,
        name = L["CHATSOUNDS_" .. upper],
        description = L["CHATSOUNDS_" .. upper .. "_DESC"],
    }
    module.options[#module.options + 1] = ns.Sounds.Option(kind.key .. "Sound",
        L.CHATSOUNDS_SOUND_DESC, { requires = kind.key })
end

-- Seconds after a sound before the next, so a burst of lines plays one.
local THROTTLE = 2

local quietUntil = 0

-- Plays `key`'s sound for a line from someone else. A line whose sender can't be read (secret, in
-- an encounter) counts as someone else's.
local function heard(key, guid)
    if ns.IsText(guid, true) and guid == UnitGUID("player") then
        return
    end
    local now = GetTime()
    if now < quietUntil then
        return
    end
    quietUntil = now + THROTTLE
    ns.Sounds.Play(module.db[key .. "Sound"])
end

for _, kind in ipairs(KINDS) do
    local key = kind.key
    -- A chat event's twelfth value is its sender's GUID.
    local function onMessage(_, _, _, _, _, _, _, _, _, _, _, _, guid)
        heard(key, guid)
    end
    local events = {}
    for _, event in ipairs(kind.events) do
        events[event] = onMessage
    end
    module:OnWhile(key, events)
end

function module:OnOptionChanged(key)
    if key:find("Sound$") then
        ns.Sounds.Play(self.db[key]) -- hear the one picked
    end
end
