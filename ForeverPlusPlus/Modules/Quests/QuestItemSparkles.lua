-- Quest Item Sparkles: the sparkle on quest items lying in the world, so they're easy to spot.
-- Forever's client draws it only while its CVar says to (outlineModeShowLootEffectWhenDisabled),
-- and a graphics preset can turn that back off. This keeps it on while the module is on, setting it
-- again a moment after it changes, and puts the player's own value back when the module turns off.
-- Ideas from Forever Loot Sparkles (v2.0.0, CurseForge, read 2026-11-09); none of its code.
local _, ns = ...

local type = type
local C_CVar = C_CVar

local L = ns.L
local CVars = ns.CVars

local CVAR = "outlineModeShowLootEffectWhenDisabled"
local LOWER = CVAR:lower()

local module = ns.NewModule("QuestItemSparkles", L.QUESTITEMSPARKLES_DESC, {
    enabled = false,
    saved = {}, -- the player's own value, put back when the module turns off
})
module.title = L.QUESTITEMSPARKLES_TITLE
module.category = "quests"
module.developer = { enabled = true }
module.added = "1.5.0"

-- The game draws the sparkle until it restarts, whatever the CVar says after.
module.notice = {
    text = L.QUESTITEMSPARKLES_NOTICE,
    description = L.QUESTITEMSPARKLES_NOTICE_DESC,
}

CVars.Track(module)

-- Only on a client with the CVar.
function module:IsAvailable()
    return C_CVar ~= nil and C_CVar.GetCVar(CVAR) ~= nil
end

local function apply()
    CVars.Set(module.db.saved, CVAR, "1")
end

-- A second after a change, as a graphics preset sets many CVars at once and could set this one
-- again after us.
local applySoon = ns.Frames.Coalesce(apply, 1, module)

local function onCVarUpdate(_, name)
    if type(name) == "string" and name:lower() == LOWER then
        applySoon()
    end
end

function module:OnEnable()
    apply()
    self:On("CVAR_UPDATE", onCVarUpdate)
end

function module:OnDisable()
    CVars.Restore(module.db.saved, CVAR)
end
