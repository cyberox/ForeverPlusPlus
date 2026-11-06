-- NPC Nameplates: friendly NPCs always show their name, with their title (<Innkeeper>) and level
-- beside it, and the health bar only shows while they're hurt or in combat. Players' pets,
-- totems, and companions can keep Blizzard's plate instead, each kind with its own option.
-- The plates themselves are ns.FriendlyPlates; this module picks the colors and the title line.
local _, ns = ...

local L = ns.L
local Units = ns.Units

local module = ns.NewModule("NpcNameplates", L.NPCNAMEPLATES_DESC, ns.FriendlyPlates.Defaults({
    nameColor = "green", -- "green" (as in the world) or "white"
    titles = "always", -- "always", "hidden" (only without the bar), or "off"
    titleColor = "name", -- "name" (the name's color), "gray", or "green"
    -- Players' summons left to Blizzard's plate, by kind (see Units.SummonKind)
    skipPets = false, -- pets, minions, and guardians
    skipTotems = false,
    skipCompanions = false,
}))
module.title = L.NPCNAMEPLATES_TITLE
module.category = "units"

-- Laid out like Player Nameplates: general, the name, then the title line, then summons.
module.options = ns.FriendlyPlates.Options(L.NPCNAMEPLATES_BAR_WHEN_HURT_DESC, {
    {
        key = "nameColor", name = L.PLATES_NAME_COLOR, description = L.NPCNAMEPLATES_NAME_COLOR_DESC,
        choices = { { "green", L.PLATES_COLOR_GREEN }, { "white", L.PLATES_COLOR_WHITE } },
        section = L.PLATES_SECTION_NAME,
    },
    ns.PlateLabel.NameSizeOption(L.PLATES_SECTION_NAME),
    {
        key = "titles", name = L.NPCNAMEPLATES_TITLES, description = L.NPCNAMEPLATES_TITLES_DESC,
        choices = ns.PlateLabel.SUBTITLE_CHOICES, section = L.NPCNAMEPLATES_SECTION_TITLE,
    },
    {
        key = "titleColor", name = L.NPCNAMEPLATES_TITLE_COLOR, description = L.NPCNAMEPLATES_TITLE_COLOR_DESC,
        choices = {
            { "name", L.NPCNAMEPLATES_TITLE_COLOR_NAME },
            { "gray", L.PLATES_COLOR_GRAY },
            { "green", L.PLATES_COLOR_GREEN },
        },
        requires = "titles", section = L.NPCNAMEPLATES_SECTION_TITLE,
    },
    {
        key = "skipPets", name = L.NPCNAMEPLATES_SKIP_PETS, description = L.NPCNAMEPLATES_SKIP_PETS_DESC,
        section = L.NPCNAMEPLATES_SECTION_SUMMONS, added = "0.9.0",
    },
    {
        key = "skipTotems", name = L.NPCNAMEPLATES_SKIP_TOTEMS,
        description = L.NPCNAMEPLATES_SKIP_TOTEMS_DESC, section = L.NPCNAMEPLATES_SECTION_SUMMONS,
        added = "0.9.0",
    },
    {
        key = "skipCompanions", name = L.NPCNAMEPLATES_SKIP_COMPANIONS,
        description = L.NPCNAMEPLATES_SKIP_COMPANIONS_DESC, section = L.NPCNAMEPLATES_SECTION_SUMMONS,
        added = "0.9.0",
    },
    {
        key = "centerLine", name = L.PLATES_CENTER_LINE_NPC, description = L.PLATES_CENTER_LINE_DESC,
        debug = true, section = L.DEBUG_SECTION_LAYOUT,
    },
})

local NAME_COLORS = {
    green = { 0.1, 1, 0.1 }, -- the green of friendly NPC names in the world
    white = { 1, 1, 1 },
}
local TITLE_COLORS = ns.FriendlyPlates.SUBTITLE_COLORS

local function nameColor()
    return NAME_COLORS[module.db.nameColor] or NAME_COLORS.green
end

local style = { icons = false }

function style.NameColor()
    local color = nameColor()
    return color[1], color[2], color[3]
end

function style.Subtitle(unit)
    local mode = module.db.titles
    if mode == "off" then
        return nil, mode
    end
    return Units.Title(unit), mode
end

function style.SubtitleColor()
    return TITLE_COLORS[module.db.titleColor] or nameColor()
end

-- Blizzard's friendly NPC nameplates can be turned off after this module turns them on, and then
-- there are no plates to draw on.
local SHOW_NPCS = { "nameplateShowFriendlyNpcs", "nameplateShowFriendlyNPCs" }
module.notice = ns.CVars.OffNotice(module, SHOW_NPCS, L.PLATES_BLIZZARD_OFF,
    L.NPCNAMEPLATES_BLIZZARD_OFF_DESC)

ns.FriendlyPlates.New(module, {
    players = false,
    cvars = {
        { names = SHOW_NPCS, value = "1" },
    },
    style = style,
    -- A player's pet or summon has the player's name in its title ("Cameron's Minion"), which
    -- reads as clutter on a name-only plate.
    Skip = function(unit)
        local db = module.db
        if not (db.skipPets or db.skipTotems or db.skipCompanions) then
            return false
        end
        local kind = Units.SummonKind(unit)
        return kind == "pet" and db.skipPets or kind == "totem" and db.skipTotems
            or kind == "companion" and db.skipCompanions or false
    end,
})
