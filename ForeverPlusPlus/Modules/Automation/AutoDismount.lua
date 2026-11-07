-- Auto Dismount: gets off your mount or stands up when something fails because you're mounted or
-- sitting, like casting a spell, taking a flight, or looting. The client has its own settings for
-- casting (the autoDismount, autoStand and autoUnshift CVars), so this turns those on, and answers
-- the errors they don't cover (flight masters, looting, attacking) itself.
local _, ns = ...

local _G, ipairs, pairs, type = _G, ipairs, pairs, type
local IsMounted, Dismount, UnitOnTaxi = IsMounted, Dismount, UnitOnTaxi
local IsFlying, InCombatLockdown, C_ChatInfo, DoEmote = IsFlying, InCombatLockdown, C_ChatInfo, DoEmote

local L = ns.L

local module = ns.NewModule("AutoDismount", L.AUTODISMOUNT_DESC, {
    enabled = true,
    dismount = true,
    stand = true,
    unshift = false,
    saved = {}, -- CVar -> the player's own value, put back when the module or an option turns off
})
module.title = L.AUTODISMOUNT_TITLE
module.category = "automation"
module.quickToggle = "world"

module.options = {
    { key = "dismount", name = L.AUTODISMOUNT_DISMOUNT, description = L.AUTODISMOUNT_DISMOUNT_DESC },
    { key = "stand", name = L.AUTODISMOUNT_STAND, description = L.AUTODISMOUNT_STAND_DESC },
    { key = "unshift", name = L.AUTODISMOUNT_UNSHIFT, description = L.AUTODISMOUNT_UNSHIFT_DESC },
}

-- The client's own setting behind each option.
-- An option that's off puts the player's own value back.
local cvars = ns.CVars.Bind(module, {
    dismount = "autoDismount",
    stand = "autoStand",
    unshift = "autoUnshift",
})

-- Errors the CVars don't answer, by the name of the game's string for them. Names this client
-- doesn't have are skipped. Leaving a shapeshift form has none: CancelShapeshiftForm is protected,
-- so only the client's own autoUnshift can do it.
local ERRORS = {
    dismount = {
        "SPELL_FAILED_NOT_MOUNTED",
        "ERR_NOT_WHILE_MOUNTED",
        "ERR_TAXIPLAYERALREADYMOUNTED",
        "ERR_ATTACK_MOUNTED",
    },
    stand = {
        "SPELL_FAILED_NOT_STANDING",
        "ERR_LOOT_NOTSTANDING",
        "ERR_CANTATTACK_NOTSTANDING",
    },
}

local actions -- error text -> "dismount" or "stand", built on first enable

local function buildActions()
    actions = {}
    for action, names in pairs(ERRORS) do
        for _, name in ipairs(names) do
            local text = _G[name]
            if type(text) == "string" then
                actions[text] = action
            end
        end
    end
end

local function stand()
    -- PerformEmote is Mainline's; DoEmote the older name for it.
    if C_ChatInfo and C_ChatInfo.PerformEmote then
        C_ChatInfo.PerformEmote("STAND")
    elseif DoEmote then
        DoEmote("STAND")
    end
end

local function onError(_, _, message)
    -- Only out of combat, where nothing it calls can be blocked; in combat the CVars still work.
    if not ns.IsReadable(message) or type(message) ~= "string" or InCombatLockdown() then
        return
    end
    local action = actions[message]
    if not action or not module.db[action] then
        return
    end
    if action == "dismount" then
        -- Never drop the player out of the sky or off a flight.
        if IsMounted() and not UnitOnTaxi("player") and not (IsFlying and IsFlying()) then
            Dismount()
        end
    else
        stand()
    end
end

function module:OnEnable()
    if not actions then
        buildActions()
    end
    cvars.ApplyAll()
    self:On("UI_ERROR_MESSAGE", onError)
end

-- UI_ERROR_MESSAGE stops by itself (module:On).
function module:OnDisable()
    cvars.Restore()
end

function module:OnOptionChanged(key)
    if self.enabled then
        cvars.Apply(key)
    end
end
