-- Simplified Dungeon Nameplates: Blizzard's Simplified nameplates (its Options > Nameplates
-- dropdown: a small plate without the cast bar and auras, for minions, minor enemies, friendly
-- players, and friendly NPCs) on only inside dungeons and raids, where the screen is crowded, and
-- the player's own choice everywhere else. A feature request on CurseForge, 2026-11-11.
--
-- That dropdown is one CVar for everywhere, nameplateSimplifiedTypes, a bit for each kind
-- (Enum.NamePlateSimplifiedType; Blizzard_SettingsDefinitions_Frame/Nameplates.lua and
-- NamePlateUnitFrameMixin:ShouldBeSimplified, Gethe forever branch, 1.60.1.70862). Blizzard's
-- plates, the forbidden ones in instances too, follow the CVar as it changes. So inside, this
-- turns on the bits of the kinds picked, on top of the player's own, and outside it puts the
-- player's value back. The CVar's text isn't a number (a version byte, then six bits a
-- character), so bits are set through C_CVar.SetCVarBitfield and the whole text is what's kept.
local _, ns = ...

local ipairs = ipairs
local C_CVar, IsInInstance = C_CVar, IsInInstance

local L = ns.L
local CVars = ns.CVars

local CVAR = "nameplateSimplifiedTypes"

local module = ns.NewModule("DungeonNameplates", L.DUNGEONNAMEPLATES_DESC, {
    enabled = false,
    friendlyPlayers = true,
    friendlyNpcs = true,
    minions = false,
    minorEnemies = false,
    battlegrounds = false, -- battlegrounds and arenas too
    saved = {}, -- the player's own value, put back outside and when the module turns off
})
module.title = L.DUNGEONNAMEPLATES_TITLE
module.category = "units"
module.added = "1.6.0"

-- Each kind's option, its bit, and Blizzard's own name for it where the client has one.
local kinds = Enum and Enum.NamePlateSimplifiedType or {}
local KINDS = {
    { key = "friendlyPlayers", bit = kinds.FriendlyPlayer, name = _G.UNIT_NAMEPLATES_SIMPLIFIED_FRIENDLY_PLAYERS
        or L.DUNGEONNAMEPLATES_FRIENDLY_PLAYERS, description = L.DUNGEONNAMEPLATES_FRIENDLY_PLAYERS_DESC,
        -- Blizzard's names-only plate has no bar, cast bar, or auras left to simplify
        -- (NamePlateHealthBarMixin and the others check IsShowOnlyName first).
        conflicts = { {
            module = "PlayerNameplates", key = "instanceNames", text = L.DUNGEONNAMEPLATES_NAMES_ONLY,
            when = function(db, other) return db.friendlyPlayers and other.instanceNames end,
        } } },
    { key = "friendlyNpcs", bit = kinds.FriendlyNpc, name = _G.UNIT_NAMEPLATES_SIMPLIFIED_FRIENDLY_NPCS
        or L.DUNGEONNAMEPLATES_FRIENDLY_NPCS, description = L.DUNGEONNAMEPLATES_FRIENDLY_NPCS_DESC },
    { key = "minions", bit = kinds.Minion, name = _G.UNIT_NAMEPLATES_SIMPLIFIED_MINIONS
        or L.DUNGEONNAMEPLATES_MINIONS, description = L.DUNGEONNAMEPLATES_MINIONS_DESC },
    { key = "minorEnemies", bit = kinds.MinusMob, name = _G.UNIT_NAMEPLATES_SIMPLIFIED_MINUS_MOBS
        or L.DUNGEONNAMEPLATES_MINOR_ENEMIES, description = L.DUNGEONNAMEPLATES_MINOR_ENEMIES_DESC },
}

module.options = {}
for _, kind in ipairs(KINDS) do
    if kind.bit then
        module.options[#module.options + 1] = { key = kind.key, name = kind.name, description = kind.description,
            conflicts = kind.conflicts }
    end
end
module.options[#module.options + 1] = {
    key = "battlegrounds", name = L.DUNGEONNAMEPLATES_BATTLEGROUNDS, description = L.DUNGEONNAMEPLATES_BATTLEGROUNDS_DESC,
}

-- What it does to a setting of the player's own, and the one thing it can't keep.
module.notice = {
    text = L.DUNGEONNAMEPLATES_NOTICE,
    description = L.DUNGEONNAMEPLATES_NOTICE_DESC,
}

CVars.Track(module)

-- Only on a client with the CVar and its bits.
function module:IsAvailable()
    return C_CVar ~= nil and C_CVar.SetCVarBitfield ~= nil and C_CVar.GetCVar(CVAR) ~= nil
        and kinds.FriendlyPlayer ~= nil
end

-- Whether the player is somewhere it applies: a dungeon or raid, or with the option a
-- battleground or arena.
local function inside()
    local here, kind = IsInInstance()
    if not here then
        return false
    end
    return kind == "party" or kind == "raid"
        or (module.db.battlegrounds and (kind == "pvp" or kind == "arena")) or false
end

-- Out of combat, as every nameplate CVar is set (ns.AfterCombat).
local function apply()
    ns.AfterCombat(function()
        if not module.enabled then
            return
        end
        local saved = module.db.saved
        if not inside() then
            CVars.Restore(saved, CVAR)
            return
        end
        -- From the player's own value each time, so a kind unticked since goes back to theirs.
        if saved[CVAR] == nil then
            saved[CVAR] = C_CVar.GetCVar(CVAR)
        else
            C_CVar.SetCVar(CVAR, saved[CVAR])
        end
        for _, kind in ipairs(KINDS) do
            if kind.bit and module.db[kind.key] then
                C_CVar.SetCVarBitfield(CVAR, kind.bit, true)
            end
        end
    end)
end

function module:OnEnable()
    -- Into or out of an instance is always a loading screen.
    self:On("PLAYER_ENTERING_WORLD", apply)
    apply()
end

function module:OnDisable()
    CVars.Restore(module.db.saved, CVAR)
end

function module:OnOptionChanged()
    apply()
end
