-- Sounds: the alert sounds a module's Sound dropdown offers (Error Catcher, Durability Warning),
-- so each offers the same choices under the same names, and playing the one picked.
local _, ns = ...

local L = ns.L

local Sounds = {}
ns.Sounds = Sounds

-- Blizzard's own error and alert sounds, by SOUNDKIT name (SoundKitConstants.lua, `forever`
-- branch), read when played since a patch can drop one (it then plays nothing). The keys are
-- what modules save, so keep them.
local KITS = {
    buzz = "UI_GARRISON_ARCHITECT_TABLE_BUILDING_PLACEMENT_ERROR",
    denied = "LFG_DENIED",
    horn = "UI_GARRISON_TOAST_INVASION_ALERT",
    boss = "RAID_BOSS_EMOTE_WARNING",
    raidwarning = "RAID_WARNING",
    gm = "GM_CHAT_WARNING",
    alarm = "ALARM_CLOCK_WARNING_3",
    whisper = "TELL_MESSAGE",
}

-- Key, then name, as a dropdown's `choices` take them, "off" first.
Sounds.CHOICES = {
    { "off", L.SOUND_OFF },
    { "buzz", L.SOUND_BUZZ },
    { "denied", L.SOUND_DENIED },
    { "horn", L.SOUND_HORN },
    { "boss", L.SOUND_BOSS },
    { "raidwarning", L.SOUND_RAIDWARNING },
    { "gm", L.SOUND_GM },
    { "alarm", L.SOUND_ALARM },
    { "whisper", L.SOUND_WHISPER },
}

---Plays the sound `key` (a key of Sounds.CHOICES) on the Master channel, so it's heard with
---sound effects off. Nothing for "off", or a sound this client doesn't have.
---@param key string?
function Sounds.Play(key)
    local kit = key and KITS[key]
    local id = kit and SOUNDKIT and SOUNDKIT[kit]
    if id and PlaySound then
        PlaySound(id, "Master")
    end
end
