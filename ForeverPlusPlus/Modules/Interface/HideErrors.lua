-- Hide Error Messages: keeps the red errors that repeat while fighting ("Out of range", "Not
-- enough energy", "Ability is not ready yet") out of the error frame at the top of the screen, or
-- every red error but a few worth seeing.
--
-- How: Blizzard's error frame draws each UI_ERROR_MESSAGE as it comes (UIErrorsMixin:OnEvent,
-- Blizzard_UIErrorsFrame). While this is on, the frame doesn't hear that event; this does, and
-- hands the frame the ones to show through its own TryDisplayMessage, so they look, flash, and
-- sound as before. A hidden error's sound and voice go with it. Yellow messages (UI_INFO_MESSAGE)
-- and text other code adds to the frame are left alone. Turned off, the frame hears the event again.
--
-- An error is known by its string's name (GetGameMessageInfo: "ERR_OUT_OF_RANGE"), the same in
-- every language. Forever's own list of hidden types has only one (Camelot's
-- UIErrorsFrameOverrides.lua, wow-ui-source `forever` branch, checked 2026-11-12), where the
-- modern game hides most of these itself.
local _, ns = ...

local _G, type, ipairs = _G, type, ipairs

local L = ns.L

local module = ns.NewModule("HideErrors", L.HIDEERRORS_DESC, {
    enabled = false,
    hide = "ability", -- ability: the errors of using abilities; all: every error but KEPT's
})
module.title = L.HIDEERRORS_TITLE
module.category = "interface"
module.added = "1.6.0"
-- In the Minimap Button's menu, to see errors again for a moment without opening Settings.
module.quickToggle = "other"

module.options = {
    {
        key = "hide",
        name = L.HIDEERRORS_HIDE,
        description = L.HIDEERRORS_HIDE_DESC,
        choices = {
            { "ability", L.HIDEERRORS_HIDE_ABILITY },
            { "all", L.HIDEERRORS_HIDE_ALL },
        },
    },
}

-- The errors of using abilities and attacking: not ready, out of range, not enough of a resource,
-- the wrong target or none, facing the wrong way, and the game's catch-all for a failed spell.
-- Names from the game's global strings (Unverified which of them Forever sends; one it doesn't
-- send changes nothing).
local ABILITY = {
    ERR_ABILITY_COOLDOWN = true,
    ERR_SPELL_COOLDOWN = true,
    ERR_ITEM_COOLDOWN = true,
    ERR_SPELL_OUT_OF_RANGE = true,
    ERR_SPELL_FAILED_S = true,
    ERR_SPELL_FAILED_ANOTHER_IN_PROGRESS = true,
    ERR_BADATTACKFACING = true,
    ERR_BADATTACKPOS = true,
    ERR_INVALID_ATTACK_TARGET = true,
    ERR_NO_ATTACK_TARGET = true,
    ERR_GENERIC_NO_TARGET = true,
    ERR_GENERIC_NO_VALID_TARGETS = true,
    ERR_GENERIC_STUNNED = true,
    ERR_CLIENT_LOCKED_OUT = true,
    ERR_USE_TOO_FAR = true,
    ERR_ATTACK_DEAD = true,
    ERR_ATTACK_STUNNED = true,
    ERR_ATTACK_PACIFIED = true,
    ERR_ATTACK_FLEEING = true,
    ERR_ATTACK_CONFUSED = true,
    ERR_ATTACK_CHARMED = true,
    ERR_ATTACK_MOUNTED = true,
}
local OUT_OF = "^ERR_OUT_OF_" -- range, and every resource: mana, rage, energy, focus, health

-- Shown even with every error hidden: ones that say why something the player meant didn't happen
-- and that nothing else on screen says.
local KEPT = {
    ERR_INV_FULL = true,
    ERR_BAG_FULL = true,
    ERR_QUEST_LOG_FULL = true,
    ERR_RAID_GROUP_ONLY = true,
    ERR_PLAYER_DEAD = true,
    ERR_PET_SPELL_DEAD = true,
    ERR_ALREADY_PICKPOCKETED = true,
    ERR_PARTY_LFG_TELEPORT_IN_COMBAT = true,
}
local KEPT_PREFIX = "^ERR_PARTY_LFG_BOOT_" -- why a vote to kick can't start
-- Kept by their text, in either mode: they come as the catch-all failed spell, whose name says
-- nothing. A rogue needs to know a target has no pockets.
local KEPT_TEXT = { "SPELL_FAILED_TARGET_NO_POCKETS" }

local function keptText(message)
    if not ns.IsText(message) then
        return false
    end
    for _, name in ipairs(KEPT_TEXT) do
        if message == _G[name] then
            return true
        end
    end
    return false
end

local function hidden(id, message)
    if type(id) ~= "string" or keptText(message) then
        return false -- unknown, or always worth seeing: shown
    end
    if module.db.hide == "all" then
        return not (KEPT[id] or id:find(KEPT_PREFIX))
    end
    return ABILITY[id] or id:find(OUT_OF) ~= nil
end

local function onError(_, messageType, message)
    local frame = UIErrorsFrame
    if not (frame and frame.TryDisplayMessage) then
        return
    end
    local id = ns.IsNumber(messageType) and GetGameMessageInfo and GetGameMessageInfo(messageType)
    if not hidden(id, message) then
        frame:TryDisplayMessage(messageType, message, RED_FONT_COLOR:GetRGB())
    end
end

function module:IsAvailable()
    return UIErrorsFrame and UIErrorsFrame.TryDisplayMessage and true or false
end

function module:OnEnable()
    UIErrorsFrame:UnregisterEvent("UI_ERROR_MESSAGE")
    self:On("UI_ERROR_MESSAGE", onError)
end

function module:OnDisable()
    UIErrorsFrame:RegisterEvent("UI_ERROR_MESSAGE")
end
