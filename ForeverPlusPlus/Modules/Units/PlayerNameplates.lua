-- Player Nameplates: friendly players always show their name, with their guild, level, and group
-- and friend icons beside it, and the health bar only shows while they're hurt or in combat.
-- The plates themselves are ns.FriendlyPlates; this module picks the colors and the guild line.
local _, ns = ...

local ipairs, GetGuildInfo = ipairs, GetGuildInfo
local UnitClass, UnitIsUnit = UnitClass, UnitIsUnit

local L = ns.L
local readable = ns.IsReadable
local Units = ns.Units

local module = ns.NewModule("PlayerNameplates", L.PLAYERNAMEPLATES_DESC, ns.FriendlyPlates.Defaults({
    nameColor = "class", -- "class" or "white"
    lightRogue = false, -- rogues in a pale yellow, apart from neutral NPCs' yellow
    dimOthers = true, -- players not in your group or guild, or your friends, a little faded
    dimAmount = 30, -- percent dimmer
    classIcon = "off", -- "off", "before", or "after" the name
    recentAllies = "icon", -- "off", "color" (light blue name), or "icon"
    guildNames = "always", -- "always", "hidden" (only without the bar), or "off"
    guildColor = "gray", -- "gray" or "green"
    guildHighlight = true,
    socialIcons = true,
    groupIcon = "role", -- "role" or "looking"
    iconSide = "after", -- "after" or "before" the name
    testIcons = "off", -- debug: "off", "group", or "friend" on every friendly player
}))
module.title = L.PLAYERNAMEPLATES_TITLE
module.category = "units"

-- General first, then the name, the guild line, and the icons beside the name.
module.options = ns.FriendlyPlates.Options(L.PLAYERNAMEPLATES_BAR_WHEN_HURT_DESC, {
    {
        key = "nameColor", name = L.PLATES_NAME_COLOR, description = L.PLAYERNAMEPLATES_NAME_COLOR_DESC,
        choices = { { "class", L.PLAYERNAMEPLATES_NAME_COLOR_CLASS }, { "white", L.PLATES_COLOR_WHITE } },
        section = L.PLATES_SECTION_NAME,
    },
    {
        key = "lightRogue", name = L.PLAYERNAMEPLATES_LIGHT_ROGUE, description = L.PLAYERNAMEPLATES_LIGHT_ROGUE_DESC,
        section = L.PLATES_SECTION_NAME, added = "1.0.1",
    },
    {
        key = "dimOthers", name = L.PLAYERNAMEPLATES_DIM, description = L.PLAYERNAMEPLATES_DIM_DESC,
        slider = "dimAmount", section = L.PLATES_SECTION_NAME, added = "1.0.1",
    },
    {
        key = "dimAmount", name = L.PLAYERNAMEPLATES_DIM_AMOUNT, description = L.PLAYERNAMEPLATES_DIM_AMOUNT_DESC,
        min = 10, max = 60, step = 5, format = "%d%%", section = L.PLATES_SECTION_NAME,
    },
    ns.PlateLabel.NameSizeOption(L.PLATES_SECTION_NAME),
    {
        key = "recentAllies", name = L.PLAYERNAMEPLATES_RECENT_ALLIES, description = L.PLAYERNAMEPLATES_RECENT_ALLIES_DESC,
        choices = {
            { "off", L.PLAYERNAMEPLATES_RECENT_ALLIES_OFF },
            { "color", L.PLAYERNAMEPLATES_RECENT_ALLIES_COLOR },
            { "icon", L.PLAYERNAMEPLATES_RECENT_ALLIES_ICON },
        },
        section = L.PLATES_SECTION_NAME,
    },
    {
        key = "guildNames", name = L.PLAYERNAMEPLATES_GUILD_NAMES, description = L.PLAYERNAMEPLATES_GUILD_NAMES_DESC,
        choices = ns.PlateLabel.SUBTITLE_CHOICES, section = L.PLAYERNAMEPLATES_SECTION_GUILD,
    },
    {
        key = "guildColor", name = L.PLAYERNAMEPLATES_GUILD_COLOR, description = L.PLAYERNAMEPLATES_GUILD_COLOR_DESC,
        choices = { { "gray", L.PLATES_COLOR_GRAY }, { "green", L.PLATES_COLOR_GREEN } },
        requires = "guildNames", section = L.PLAYERNAMEPLATES_SECTION_GUILD,
    },
    {
        key = "guildHighlight", name = L.PLAYERNAMEPLATES_GUILD_HIGHLIGHT, description = L.PLAYERNAMEPLATES_GUILD_HIGHLIGHT_DESC,
        requires = "guildNames", section = L.PLAYERNAMEPLATES_SECTION_GUILD,
    },
    {
        key = "classIcon", name = L.PLAYERNAMEPLATES_CLASS_ICON, description = L.PLAYERNAMEPLATES_CLASS_ICON_DESC,
        choices = {
            { "off", L.PLAYERNAMEPLATES_CLASS_ICON_OFF },
            { "before", L.PLAYERNAMEPLATES_ICON_SIDE_BEFORE },
            { "after", L.PLAYERNAMEPLATES_ICON_SIDE_AFTER },
        },
        -- Sharing a side with the level or the other icons is fine: the class icon sits next to
        -- the name and they move out past it (PlateLabel.Layout).
        section = L.PLAYERNAMEPLATES_SECTION_ICONS, added = "1.0.1",
    },
    {
        key = "socialIcons", name = L.PLAYERNAMEPLATES_SOCIAL_ICONS, description = L.PLAYERNAMEPLATES_SOCIAL_ICONS_DESC,
        section = L.PLAYERNAMEPLATES_SECTION_ICONS,
    },
    {
        key = "groupIcon", name = L.PLAYERNAMEPLATES_GROUP_ICON, description = L.PLAYERNAMEPLATES_GROUP_ICON_DESC,
        choices = {
            { "role", L.PLAYERNAMEPLATES_GROUP_ICON_ROLE },
            { "looking", L.PLAYERNAMEPLATES_GROUP_ICON_LOOKING },
        },
        requires = "socialIcons", section = L.PLAYERNAMEPLATES_SECTION_ICONS,
    },
    {
        -- Also the recent ally icon, so not under Group and Friend Icons.
        key = "iconSide", name = L.PLAYERNAMEPLATES_ICON_SIDE, description = L.PLAYERNAMEPLATES_ICON_SIDE_DESC,
        choices = {
            { "after", L.PLAYERNAMEPLATES_ICON_SIDE_AFTER },
            { "before", L.PLAYERNAMEPLATES_ICON_SIDE_BEFORE },
        },
        section = L.PLAYERNAMEPLATES_SECTION_ICONS,
    },
    {
        key = "testIcons", name = L.PLAYERNAMEPLATES_TEST_ICONS, description = L.PLAYERNAMEPLATES_TEST_ICONS_DESC,
        choices = {
            { "off", L.PLAYERNAMEPLATES_TEST_ICONS_OFF },
            { "group", L.PLAYERNAMEPLATES_TEST_ICONS_GROUP },
            { "friend", L.PLAYERNAMEPLATES_TEST_ICONS_FRIEND },
        },
        debug = true, section = L.DEBUG_SECTION_TESTING,
    },
    {
        key = "centerLine", name = L.PLATES_CENTER_LINE_PLAYER, description = L.PLATES_CENTER_LINE_DESC,
        debug = true, section = L.DEBUG_SECTION_TESTING,
    },
})

-- Guild Name Color choices. Highlighted guildmates get guild chat's green, or white when every
-- guild is already green, so they still stand out.
local GUILD_COLORS = ns.FriendlyPlates.SUBTITLE_COLORS
local GUILDMATE_COLORS = {
    gray = GUILD_COLORS.green,
    green = { 0.9, 0.9, 0.9 },
}

local style = { icons = true, classIcons = true }

local RECENT_ALLY = ns.Colors.RECENT_ALLY
-- Lighter Rogue Yellow: the rogue color halfway to white, so it doesn't read as a neutral NPC.
local LIGHT_ROGUE = { 1, 0.98, 0.72 }

local function isRogue(unit)
    local _, class = UnitClass(unit)
    return readable(class) and class == "ROGUE"
end

local function isRecentAlly(unit, mode)
    return module.db.recentAllies == mode and Units.IsRecentAlly(unit)
end

-- The icon goes beside the name, so the class color stays.
function style.ShowAllyIcon(unit)
    return isRecentAlly(unit, "icon")
end

function style.NameColor(unit)
    if isRecentAlly(unit, "color") then
        return RECENT_ALLY[1], RECENT_ALLY[2], RECENT_ALLY[3]
    end
    if module.db.nameColor == "class" then
        if module.db.lightRogue and isRogue(unit) then
            return LIGHT_ROGUE[1], LIGHT_ROGUE[2], LIGHT_ROGUE[3]
        end
        local color = ns.Colors.Class(unit)
        if color then
            return color:GetRGB()
        end
    end
    return 1, 1, 1
end

-- Dim Other Players: anyone not in your group or guild, a friend, or a recent ally, unless you
-- have them targeted (a secret answer counts as targeted).
local function isStranger(unit)
    if ns.IsTrueOrSecret(UnitIsUnit(unit, "target")) then
        return false
    end
    return not (Units.InGroup(unit) or Units.IsGuildmate(unit) or Units.IsFriend(unit)
        or Units.IsRecentAlly(unit))
end

function style.Alpha(unit)
    local db = module.db
    if db.dimOthers and isStranger(unit) then
        return 1 - db.dimAmount / 100
    end
    return 1
end

-- With the bar up, the name is plain white, as Blizzard draws it, except a colored recent ally's.
function style.BarNameColor(unit)
    if isRecentAlly(unit, "color") then
        return RECENT_ALLY[1], RECENT_ALLY[2], RECENT_ALLY[3]
    end
    return 1, 1, 1
end

function style.Subtitle(unit)
    local mode = module.db.guildNames
    if mode == "off" then
        return nil, mode
    end
    return GetGuildInfo(unit), mode -- may be secret; PlateLabel checks
end

function style.SubtitleColor(unit)
    local db = module.db
    local scheme = GUILD_COLORS[db.guildColor] and db.guildColor or "gray"
    if db.guildHighlight and Units.IsGuildmate(unit) then
        return GUILDMATE_COLORS[scheme]
    end
    return GUILD_COLORS[scheme]
end

-- Blizzard's friendly player nameplates can be turned off after this module turns them on (in
-- its options, or with its keybind), and then there are no plates to draw on.
local SHOW_FRIENDLY = { "nameplateShowFriendlyPlayers", "nameplateShowFriends" }
module.notice = ns.CVars.OffNotice(module, SHOW_FRIENDLY, L.PLATES_BLIZZARD_OFF,
    L.PLAYERNAMEPLATES_BLIZZARD_OFF_DESC)

local plates -- set below

-- The recent allies list may load after login, or change: recolor.
local function onRecentAllies()
    if module.db.recentAllies ~= "off" then
        plates:Refresh()
    end
end

plates = ns.FriendlyPlates.New(module, {
    players = true,
    cvars = {
        -- Each entry lists the names the setting has had, newest first; the first one this client
        -- knows is used.
        { names = SHOW_FRIENDLY, value = "1" },
        -- Blizzard's names-only mode drops the bar entirely, so it could never come back when hurt.
        { names = { "nameplateShowOnlyNameForFriendlyPlayerUnits", "nameplateShowOnlyNames" }, value = "0" },
        -- Blizzard's own name, shown while the bar is up, stays plain white; class color is for ours.
        { names = { "nameplateUseClassColorForFriendlyPlayerUnitNames" }, value = "0" },
    },
    style = style,
    OnEnable = function(self)
        if Units.HasRecentAllies() then
            for _, event in ipairs(Units.RECENT_ALLY_EVENTS) do
                self:On(event, onRecentAllies)
            end
        end
    end,
})

-- Dim Other Players leaves your target bright, so the plates follow the target.
module:OnWhile("dimOthers", {
    PLAYER_TARGET_CHANGED = function()
        plates:Refresh()
    end,
})
