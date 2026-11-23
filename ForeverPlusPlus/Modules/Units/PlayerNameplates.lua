-- Player Nameplates: friendly players always show their name, with their guild, level, and group
-- and friend icons beside it, and the health bar only shows while they're hurt or in combat.
-- The plates themselves are ns.FriendlyPlates; this module picks the colors and the guild line.
-- Enemy Player Names is the one thing it does to a plate that isn't friendly: Blizzard's own name
-- there, in one color.
local _, ns = ...

local ipairs, GetGuildInfo, format, setmetatable = ipairs, GetGuildInfo, format, setmetatable
local UnitClass, UnitIsUnit, UnitPVPName = UnitClass, UnitIsUnit, UnitPVPName
local UnitIsPlayer, UnitIsFriend, UnitLevel, UnitIsPVP = UnitIsPlayer, UnitIsFriend, UnitLevel, UnitIsPVP

local L = ns.L
local readable = ns.IsReadable
local Units = ns.Units

local module = ns.NewModule("PlayerNameplates", L.PLAYERNAMEPLATES_DESC, ns.FriendlyPlates.Defaults({
    nameColor = "class", -- "class" or "white"
    lightRogue = false, -- rogues in a pale yellow, apart from neutral NPCs' yellow
    titles = false, -- the title a player chose, with their name
    roleplayName = true, -- the name Total RP 3 gives a player, with that addon loaded
    roleplayColor = true, -- the name color Total RP 3 gives a player, with that addon loaded
    roleplayIcon = true, -- the profile icon Total RP 3 gives a player, with that addon loaded
    dimOthers = true, -- not in your group or guild, a friend, or a recent ally: faded
    dimAmount = 30, -- percent dimmer
    iconSize = 80, -- percent of Blizzard's name size, like nameSize
    classIcon = "off", -- "off", "before", or "after" the name
    classIconStyle = "ring", -- "ring", "round", or "square"
    classIconOrder = "inside", -- with the level on the same side: "inside" it, or "outside" past it
    recentAllies = "icon", -- "off", "color" (light blue name), or "icon"
    groupColor = "off", -- "off", "class", or one of NAME_COLORS for party and raid members' names
    groupBar = false, -- and their health bars
    friendColor = "off", -- the same for friends' names, after a group member's
    friendBar = false, -- and their health bars
    -- "off", "class", "level" (the game's difficulty color), or one of NAME_COLORS for enemy
    -- players' names
    enemyColor = "off",
    enemyBar = false, -- and their health bars
    enemyFlagged = false, -- only enemies flagged for PvP get any of it
    enemyClassIcon = false, -- the class icon on enemy players' plates too
    guildNames = "always", -- "always", "hidden" (only without the bar), or "off"
    guildColor = "gray", -- "gray" or "green"
    guildHighlight = true,
    socialIcons = true,
    groupIcon = "role", -- "role" or "looking"
    iconSide = "after", -- "after" or "before" the name
    -- Blizzard's names-only plates where it draws them itself (dungeons, raids). Off, so health bars
    -- show there by default.
    instanceNames = false,
    testIcons = "off", -- debug: "off", "group", or "friend" on every friendly player
}))
module.title = L.PLAYERNAMEPLATES_TITLE
module.category = "units"
module.quickToggle = "nameplates"

-- Layout version 5: the icons had no size of their own and grew with Name Size. A player who set
-- Name Size keeps their icons that size under the new Icon Size.
-- Health Bar When Hurt (a checkbox) became Health Bar, with Never: off meant only in combat.
ns.Migrate(5, function(db)
    local saved = db.settings and db.settings.PlayerNameplates
    if saved and saved.nameSize ~= nil and saved.iconSize == nil then
        saved.iconSize = saved.nameSize
    end
    ns.FriendlyPlates.MigrateHealthBar(saved)
end)

-- The colors Group Member Names and Enemy Player Names offer: our own, light enough to read over
-- the world with the name's outline.
local NAME_COLORS = {
    red = { 1, 0.25, 0.25 },
    orange = { 1, 0.6, 0.2 },
    yellow = { 1, 0.9, 0.3 },
    green = { 0.4, 1, 0.4 },
    blue = { 0.4, 0.7, 1 },
    purple = { 0.75, 0.5, 1 },
    pink = { 1, 0.55, 0.8 },
    white = { 1, 1, 1 },
}

-- A new list each call, so each option has its own. With `level`, Level too: the game's
-- difficulty color for the player's level against yours (ns.Colors.Difficulty).
local function nameColorChoices(level)
    local choices = {
        { "off", L.PLAYERNAMEPLATES_COLOR_OFF },
        { "class", L.PLAYERNAMEPLATES_NAME_COLOR_CLASS }, -- each player's own (ns.Colors.Class)
        { "red", L.PLATES_COLOR_RED },
        { "orange", L.PLATES_COLOR_ORANGE },
        { "yellow", L.PLATES_COLOR_YELLOW },
        { "green", L.PLATES_COLOR_GREEN },
        { "blue", L.PLATES_COLOR_BLUE },
        { "purple", L.PLATES_COLOR_PURPLE },
        { "pink", L.PLATES_COLOR_PINK },
        { "white", L.PLATES_COLOR_WHITE },
    }
    if level then
        table.insert(choices, 3, { "level", L.PLAYERNAMEPLATES_COLOR_LEVEL })
    end
    return choices
end

-- General first, then the name, the guild line, and the icons beside the name.
module.options = ns.FriendlyPlates.Options(L.PLAYERNAMEPLATES_HEALTH_BAR_DESC, {
    {
        key = "instanceNames", name = L.PLAYERNAMEPLATES_INSTANCE_NAMES,
        description = L.PLAYERNAMEPLATES_INSTANCE_NAMES_DESC, section = L.PLATES_SECTION_GENERAL,
        added = "1.4.0",
    },
    {
        key = "nameColor", name = L.PLATES_NAME_COLOR, description = L.PLAYERNAMEPLATES_NAME_COLOR_DESC,
        choices = { { "class", L.PLAYERNAMEPLATES_NAME_COLOR_CLASS }, { "white", L.PLATES_COLOR_WHITE } },
        -- The name over the bar is always white (style.BarNameColor).
        section = L.PLATES_SECTION_NAME, shown = ns.FriendlyPlates.HasNameView,
    },
    {
        key = "lightRogue", name = L.PLAYERNAMEPLATES_LIGHT_ROGUE, description = L.PLAYERNAMEPLATES_LIGHT_ROGUE_DESC,
        section = L.PLATES_SECTION_NAME, added = "1.0.1",
        shown = function(db) return db.nameColor == "class" and ns.FriendlyPlates.HasNameView(db) end,
    },
    {
        key = "titles", name = L.PLAYERNAMEPLATES_TITLES, description = L.PLAYERNAMEPLATES_TITLES_DESC,
        section = L.PLATES_SECTION_NAME, added = "1.9.0",
    },
    {
        key = "roleplayName", name = L.PLAYERNAMEPLATES_ROLEPLAY_NAME,
        description = L.PLAYERNAMEPLATES_ROLEPLAY_NAME_DESC,
        section = L.PLATES_SECTION_NAME, added = "1.9.0",
        available = ns.FriendlyPlates.HasRoleplay, needs = format(L.SETTINGS_NEEDS_ADDON, "Total RP 3"),
    },
    {
        key = "roleplayColor", name = L.PLAYERNAMEPLATES_ROLEPLAY_COLOR,
        description = L.PLAYERNAMEPLATES_ROLEPLAY_COLOR_DESC,
        section = L.PLATES_SECTION_NAME, added = "1.9.0", shown = ns.FriendlyPlates.HasNameView,
        available = ns.FriendlyPlates.HasRoleplay, needs = format(L.SETTINGS_NEEDS_ADDON, "Total RP 3"),
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
        key = "groupColor", name = L.PLAYERNAMEPLATES_GROUP_COLOR,
        description = L.PLAYERNAMEPLATES_GROUP_COLOR_DESC,
        choices = nameColorChoices(), section = L.PLATES_SECTION_NAME, added = "1.9.0",
    },
    {
        key = "groupBar", name = L.PLAYERNAMEPLATES_COLOR_BAR,
        description = L.PLAYERNAMEPLATES_GROUP_BAR_DESC,
        requires = "groupColor", section = L.PLATES_SECTION_NAME, added = "1.9.0",
    },
    {
        key = "friendColor", name = L.PLAYERNAMEPLATES_FRIEND_COLOR,
        description = L.PLAYERNAMEPLATES_FRIEND_COLOR_DESC,
        choices = nameColorChoices(), section = L.PLATES_SECTION_NAME, added = "1.9.0",
    },
    {
        key = "friendBar", name = L.PLAYERNAMEPLATES_COLOR_BAR,
        description = L.PLAYERNAMEPLATES_FRIEND_BAR_DESC,
        requires = "friendColor", section = L.PLATES_SECTION_NAME, added = "1.9.0",
    },
    {
        key = "enemyColor", name = L.PLAYERNAMEPLATES_ENEMY_COLOR,
        description = L.PLAYERNAMEPLATES_ENEMY_COLOR_DESC,
        choices = nameColorChoices(true), section = L.PLATES_SECTION_NAME, added = "1.9.0",
    },
    {
        key = "enemyBar", name = L.PLAYERNAMEPLATES_COLOR_BAR,
        description = L.PLAYERNAMEPLATES_ENEMY_BAR_DESC,
        requires = "enemyColor", section = L.PLATES_SECTION_NAME, added = "1.9.0",
    },
    {
        key = "enemyFlagged", name = L.PLAYERNAMEPLATES_ENEMY_FLAGGED,
        description = L.PLAYERNAMEPLATES_ENEMY_FLAGGED_DESC,
        requires = "enemyColor", section = L.PLATES_SECTION_NAME, added = "1.9.0",
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
        key = "iconSize", name = L.PLAYERNAMEPLATES_ICON_SIZE, description = L.PLAYERNAMEPLATES_ICON_SIZE_DESC,
        min = 50, max = 200, step = 10, format = "%d%%", section = L.PLAYERNAMEPLATES_SECTION_ICONS,
        added = "1.1.0",
    },
    {
        key = "classIcon", name = L.PLAYERNAMEPLATES_CLASS_ICON, description = L.PLAYERNAMEPLATES_CLASS_ICON_DESC,
        choices = {
            { "before", L.PLAYERNAMEPLATES_ICON_SIDE_BEFORE },
            { "after", L.PLAYERNAMEPLATES_ICON_SIDE_AFTER },
            { "off", L.PLAYERNAMEPLATES_CLASS_ICON_OFF },
        },
        -- Sharing a side with the level or the other icons is fine: the class icon sits next to
        -- the name and they move out past it (PlateLabel.Layout).
        section = L.PLAYERNAMEPLATES_SECTION_ICONS, added = "1.0.1",
    },
    {
        key = "classIconStyle", name = L.PLAYERNAMEPLATES_CLASS_ICON_STYLE,
        description = L.PLAYERNAMEPLATES_CLASS_ICON_STYLE_DESC,
        choices = {
            { "ring", L.PLAYERNAMEPLATES_CLASS_ICON_RING },
            { "round", L.PLAYERNAMEPLATES_CLASS_ICON_ROUND },
            { "square", L.PLAYERNAMEPLATES_CLASS_ICON_SQUARE },
        },
        requires = "classIcon", section = L.PLAYERNAMEPLATES_SECTION_ICONS, added = "1.0.1",
    },
    {
        -- Only matters with the level on the class icon's side, so only shown then.
        key = "classIconOrder", name = L.PLAYERNAMEPLATES_CLASS_ICON_ORDER,
        description = L.PLAYERNAMEPLATES_CLASS_ICON_ORDER_DESC,
        choices = {
            { "inside", L.PLAYERNAMEPLATES_CLASS_ICON_INSIDE },
            { "outside", L.PLAYERNAMEPLATES_CLASS_ICON_OUTSIDE },
        },
        shown = function(db)
            return db.classIcon ~= "off" and db.level == db.classIcon and ns.FriendlyPlates.HasNameView(db)
        end,
        requires = "classIcon", section = L.PLAYERNAMEPLATES_SECTION_ICONS, added = "1.0.1",
    },
    {
        key = "enemyClassIcon", name = L.PLAYERNAMEPLATES_ENEMY_CLASS_ICON,
        description = L.PLAYERNAMEPLATES_ENEMY_CLASS_ICON_DESC,
        requires = "classIcon", section = L.PLAYERNAMEPLATES_SECTION_ICONS, added = "1.9.0",
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
        key = "roleplayIcon", name = L.PLAYERNAMEPLATES_ROLEPLAY_ICON,
        description = L.PLAYERNAMEPLATES_ROLEPLAY_ICON_DESC,
        section = L.PLAYERNAMEPLATES_SECTION_ICONS, added = "1.9.0",
        available = ns.FriendlyPlates.HasRoleplay, needs = format(L.SETTINGS_NEEDS_ADDON, "Total RP 3"),
    },
    {
        -- Also the recent ally icon, so not under Group and Friend Icons.
        key = "iconSide", name = L.PLAYERNAMEPLATES_ICON_SIDE, description = L.PLAYERNAMEPLATES_ICON_SIDE_DESC,
        choices = {
            { "before", L.PLAYERNAMEPLATES_ICON_SIDE_BEFORE },
            { "after", L.PLAYERNAMEPLATES_ICON_SIDE_AFTER },
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
        debug = true, section = L.DEBUG_SECTION_PREVIEWS,
    },
    {
        key = "centerLine", name = L.PLATES_CENTER_LINE_PLAYER, description = L.PLATES_CENTER_LINE_DESC,
        debug = true, section = L.DEBUG_SECTION_LAYOUT,
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

-- Which of Group Member Names and Friend Names colors a friendly player: "group", "friend", or
-- nil. A group member first, then a friend: the group is who you're playing with now. Both come
-- before every other name color (a recent ally's, Total RP 3's, the class): they're the ones the
-- player asked to tell apart at a glance, and nearly all of them are recent allies too.
local function socialKind(unit)
    local db = module.db
    if db.groupColor ~= "off" and Units.InGroup(unit) then
        return "group"
    elseif db.friendColor ~= "off" and Units.IsFriend(unit) then
        return "friend"
    end
end

-- The color that gives a friendly player's name (r, g, b), or nil. Class is the class color
-- whatever Name Color says; one that can't be read falls through to the others.
local function groupColor(unit)
    local kind = socialKind(unit)
    if not kind then
        return nil
    end
    local choice = module.db[kind .. "Color"]
    if choice == "class" then
        local class = ns.Colors.Class(unit)
        if class then
            return class:GetRGB()
        end
        return nil
    end
    local color = NAME_COLORS[choice]
    if color then
        return color[1], color[2], color[3]
    end
end

function style.NameColor(unit)
    local r, g, b = groupColor(unit)
    if r then
        return r, g, b
    end
    if isRecentAlly(unit, "color") then
        return RECENT_ALLY[1], RECENT_ALLY[2], RECENT_ALLY[3]
    end
    if module.db.roleplayColor then
        local r, g, b = ns.FriendlyPlates.RoleplayColor(unit)
        if r then
            return r, g, b
        end
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

-- Total RP 3 Names: the roleplay name, with its out of character mark. Else, with Titles, the name
-- as the game writes it with the player's chosen title ("Name, Master Angler"); a secret one, in
-- an instance or combat, leaves Blizzard's plain name.
function style.Name(unit)
    local db = module.db
    local name = db.roleplayName and ns.FriendlyPlates.RoleplayName(unit)
    if not name and db.titles and UnitPVPName then
        local titled = UnitPVPName(unit)
        if ns.IsText(titled, true) then
            name = titled
        end
    end
    return name or nil
end

-- Total RP 3 Icons: the profile icon, drawn with our other icons in place of that addon's own.
function style.OwnsRoleplayIcon()
    return module.db.roleplayIcon and ns.FriendlyPlates.HasRoleplay()
end

function style.RoleplayIcon(unit, texture)
    return module.db.roleplayIcon and ns.FriendlyPlates.RoleplayIcon(unit, texture)
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

-- With the bar up, the name is plain white, as Blizzard draws it, except a group member's or a
-- recent ally's with a color of its own.
function style.BarNameColor(unit)
    local r, g, b = groupColor(unit)
    if r then
        return r, g, b
    end
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

-- Whether a setting does anything to enemy players' plates.
local function enemyIconOn(db)
    return db.enemyClassIcon and db.classIcon ~= "off"
end

local function enemyOptionsOn(db)
    return db.enemyColor ~= "off" or enemyIconOn(db)
end

-- The enemy settings draw on Blizzard's enemy nameplates, which are the player's to turn on: a
-- row with a button while one of those settings is on and the plates are off.
local enemyPlates = ns.CVars.OffNotice(module, "nameplateShowEnemies", L.PLAYERNAMEPLATES_ENEMY_OFF,
    L.PLAYERNAMEPLATES_ENEMY_OFF_DESC)
local enemyPlatesOff = enemyPlates.shown
enemyPlates.shown = function()
    return enemyPlatesOff() and enemyOptionsOn(module.db)
end

module.notice = {
    ns.CVars.OffNotice(module, SHOW_FRIENDLY, L.PLATES_BLIZZARD_OFF, L.PLAYERNAMEPLATES_BLIZZARD_OFF_DESC),
    enemyPlates,
    -- Blizzard's own setting colors enemy players' bars by class too (nameplateShowClassColor,
    -- which Class Colors offers a button for). Ours and it then do the same thing: said, not changed.
    {
        text = L.PLAYERNAMEPLATES_ENEMY_CLASS_BARS, description = L.PLAYERNAMEPLATES_ENEMY_CLASS_BARS_DESC,
        shown = function()
            local db = module.db
            return db.enabled and db.enemyColor == "class" and db.enemyBar
                and ns.CVars.IsOn("nameplateShowClassColor")
        end,
    },
    -- The game's rule, not ours: always there, with no button.
    { text = L.PLAYERNAMEPLATES_INSTANCES, description = L.PLAYERNAMEPLATES_INSTANCES_DESC },
}

-- Where Blizzard keeps friendly plates to itself. In dungeons and raids friendly plates are
-- forbidden to addons (Retail's rule since 7.2, and Forever's plates have the forbidden pool:
-- Blizzard_NamePlates.lua, 1.60.1.70862). In another kind of instance (a battleground), a
-- forbidden plate showing up says so too, until the next loading screen.
local forbiddenSeen = false

local function blizzardPlatesHere()
    local kind = ns.Instances.Here()
    return kind ~= nil and (kind == "party" or kind == "raid" or forbiddenSeen)
end

-- Blizzard's names-only mode (its Show Only Name checkbox) drops the bar entirely, so on our plates
-- it could never come back when hurt: off, except where the plates are Blizzard's, where it's the
-- only way to keep their health bars hidden (Names Only in Dungeons). The forbidden plates read the
-- same CVar (NamePlateUnitFrameMixin:UpdateShowOnlyName, on both pools).
local function namesOnly(db)
    return db.instanceNames and blizzardPlatesHere() and "1" or "0"
end

local plates -- set below

-- The recent allies list may load after login, or change: recolor.
local function onRecentAllies()
    if module.db.recentAllies ~= "off" then
        plates:Refresh()
    end
end

-- Enemy Player Names ----------------------------------------------------------------------------
-- A player whose plate isn't friendly (the other faction, a duel) keeps Blizzard's plate, and its
-- name gets the color picked. Blizzard colors the name itself (CompactUnitFrame_UpdateName,
-- SetVertexColor) whenever it updates the plate, so each color it sets is remembered and painted
-- over again, and put back as the plate leaves or the option turns off.
--
-- Health Bar Too, under it and under Group Member Names and Friend Names, does the same to
-- Blizzard's health bar (CompactUnitFrame_UpdateHealthColor, SetStatusBarColor): an enemy
-- player's, or a group member's or friend's on a friendly plate, whose name is our label's and
-- gets its color there (style.NameColor).
--
-- Class Icon on Enemy Players puts the class icon beside the enemy's name
-- (ns.PlateLabel.ShowClassIcon), and Only Flagged Enemies keeps all three to enemies flagged for
-- PvP.
local weak = { __mode = "k" }
local tracked = setmetatable({}, weak) -- Blizzard's name or health bar -> { plate, part }, on screen
local blizzardColor = setmetatable({}, weak) -- the same -> { r, g, b } Blizzard last set
local painted = setmetatable({}, weak) -- the same -> true while in our color
local painting = false
-- The key ns.Nameplates knows this by; the Profiler charges it to the module.
local colorOwner = { module = module }

-- How each part is colored and read.
local SETTER = { name = "SetVertexColor", bar = "SetStatusBarColor" }
local GETTER = { name = "GetVertexColor", bar = "GetStatusBarColor" }

-- Whose plate it is: "enemy" (a player who isn't friendly), "friend" (one who is, never the
-- player's own), or false. Who a unit is can be secret (in combat, an instance): then the last
-- answer for this plate stands, and none yet counts as nobody's.
local function sideOf(plate)
    local unit = plate.unit
    local isPlayer, isFriend, isSelf = UnitIsPlayer(unit), UnitIsFriend("player", unit),
        UnitIsUnit(unit, "player")
    if readable(isPlayer) and readable(isFriend) and readable(isSelf) then
        plate.side = isPlayer and not isSelf and (isFriend and "friend" or "enemy") or false
    end
    return plate.side
end

-- Whether the enemy settings apply to this plate: an enemy player's, and with Only Flagged
-- Enemies, one flagged for PvP. A flag that can't be read keeps the plate's last answer, and none
-- yet counts as not flagged. The checkbox sits under Enemy Player Names, so it's off with it.
local function enemyApplies(plate)
    if sideOf(plate) ~= "enemy" then
        return false
    end
    local db = module.db
    if not (db.enemyFlagged and db.enemyColor ~= "off") then
        return true
    end
    local flagged = UnitIsPVP(plate.unit)
    if readable(flagged) then
        plate.flagged = flagged and true or false
    end
    return plate.flagged or false
end

-- The color this part of the plate gets, or nil for Blizzard's.
local function wantedColor(plate, part)
    local db = module.db
    local side = sideOf(plate)
    local choice
    if side == "enemy" then
        choice = (part == "name" or db.enemyBar) and enemyApplies(plate) and db.enemyColor
    elseif side == "friend" and part == "bar" then
        -- The same one that colors the name, so the two never disagree.
        local kind = socialKind(plate.unit)
        choice = kind and db[kind .. "Bar"] and db[kind .. "Color"]
    end
    if choice == "class" then
        -- A class that can't be read now keeps the one read for this plate before.
        plate.class = ns.Colors.Class(plate.unit) or plate.class
        if plate.class then
            return plate.class:GetRGB()
        end
        return nil
    elseif choice == "level" then
        -- The same for a level; one the game hides (a skull) reads as -1, the hardest color.
        local level = UnitLevel(plate.unit)
        if ns.IsNumber(level) then
            plate.level = level
        end
        local color = plate.level and ns.Colors.Difficulty(plate.level)
        if color then
            return color.r, color.g, color.b
        end
        return nil
    end
    local color = choice and NAME_COLORS[choice]
    if color then
        return color[1], color[2], color[3]
    end
end

-- Blizzard's color back. Its values may be secret, so they're only ever passed on. Three numbers,
-- never an alpha: that would show a name the friendly plates hid.
local function restoreColor(widget, part)
    local old = blizzardColor[widget]
    painted[widget] = nil
    if old then
        painting = true
        widget[SETTER[part]](widget, old[1], old[2], old[3])
        painting = false
    end
end

local function paintColor(widget)
    local entry = tracked[widget]
    if not entry then
        return
    end
    local part = entry[2]
    local r, g, b = wantedColor(entry[1], part)
    if not r then
        if painted[widget] then
            restoreColor(widget, part)
        end
        return
    end
    -- Blizzard colored it before our hook saw: keep what it shows now to put back.
    if not blizzardColor[widget] then
        local oldR, oldG, oldB = widget[GETTER[part]](widget)
        blizzardColor[widget] = { oldR, oldG, oldB }
    end
    painting = true
    widget[SETTER[part]](widget, r, g, b)
    painting = false
    painted[widget] = true
end

-- Remember what Blizzard sets, then paint over it again.
local function onColored(widget, r, g, b)
    if painting or not tracked[widget] then
        return
    end
    blizzardColor[widget] = { r, g, b }
    paintColor(widget)
end

-- Blizzard's name and health bar on a plate, either nil on a build without it.
local function coloredParts(frame)
    local parts = ns.Nameplates.Parts(frame)
    local name, container = parts.name, parts.container
    local bar = frame.healthBar or container and container.healthBar
    return name and name.SetVertexColor and name or nil, bar and bar.SetStatusBarColor and bar or nil
end

local function track(widget, plate, part)
    if widget then
        tracked[widget] = { plate, part }
        module:Hook(widget, SETTER[part], onColored)
        paintColor(widget)
    end
end

-- Plates are pooled: the next unit's name and bar start from Blizzard's colors.
local function untrack(widget, part)
    if widget then
        if painted[widget] then
            restoreColor(widget, part)
        end
        tracked[widget], blizzardColor[widget] = nil, nil
    end
end

-- Class Icon on Enemy Players: shown, placed again, or hidden for this plate.
local function updateIcon(plate, name)
    if name and enemyIconOn(module.db) and enemyApplies(plate) then
        ns.PlateLabel.ShowClassIcon(plate.frame, name, plate.unit, module.db)
    else
        ns.PlateLabel.HideClassIcon(plate.frame)
    end
end

-- Blizzard wrote the name (as the plate gets its unit, or a name loads): the icon sits beside
-- the text, so it's placed again.
local function onNameText(name)
    local entry = tracked[name]
    if entry then
        updateIcon(entry[1], name)
    end
end

local function repaintFrame(_, frame)
    local name, bar = coloredParts(frame)
    if name then
        paintColor(name)
        local entry = tracked[name]
        if entry then
            updateIcon(entry[1], name)
        end
    end
    if bar then
        paintColor(bar)
    end
end

local colorHandlers = {
    OnAdded = function(unit, frame)
        local name, bar = coloredParts(frame)
        local plate = { unit = unit, frame = frame }
        track(name, plate, "name")
        track(bar, plate, "bar")
        if name then
            module:Hook(name, "SetText", onNameText)
            updateIcon(plate, name)
        end
    end,
    OnRemoved = function(_, frame)
        local name, bar = coloredParts(frame)
        untrack(name, "name")
        untrack(bar, "bar")
        ns.PlateLabel.HideClassIcon(frame)
    end,
}

-- Whether the settings do anything to Blizzard's own name, bar, or plate: an enemy's name or
-- class icon, or a group member's or friend's bar.
local function colorsPlates(db)
    return enemyOptionsOn(db) or (db.groupBar and db.groupColor ~= "off")
        or (db.friendBar and db.friendColor ~= "off")
end

-- Watches the plates only while they do, so it costs nothing otherwise.
local function syncColors(on)
    if on and colorsPlates(module.db) then
        ns.Nameplates.Register(colorOwner, colorHandlers)
        -- Already watching: the color may have changed.
        ns.Nameplates.ForEach(repaintFrame)
    else
        ns.Nameplates.Unregister(colorOwner)
    end
end

local function repaintPlates()
    ns.Nameplates.ForEach(repaintFrame)
end

module:OnWhile(colorsPlates, {
    -- A duel starts or ends, or a player flags, with the plate still up.
    UNIT_FACTION = function(_, unit)
        local frame = unit and ns.Nameplates.FrameFor(unit)
        if frame then
            repaintFrame(unit, frame)
        end
    end,
    UNIT_LEVEL = function(_, unit)
        local frame = unit and ns.Nameplates.FrameFor(unit)
        if frame then
            repaintFrame(unit, frame)
        end
    end,
    -- Someone joined or left the group, or the friends list changed.
    GROUP_ROSTER_UPDATE = repaintPlates,
    FRIENDLIST_UPDATE = repaintPlates,
    BN_FRIEND_INFO_CHANGED = repaintPlates,
})

plates = ns.FriendlyPlates.New(module, {
    players = true,
    cvars = {
        -- Each entry lists the names the setting has had, newest first; the first one this client
        -- knows is used.
        { names = SHOW_FRIENDLY, value = "1" },
        { names = { "nameplateShowOnlyNameForFriendlyPlayerUnits", "nameplateShowOnlyNames" }, value = namesOnly },
        -- Blizzard's own name, shown while the bar is up, stays plain white; class color is for ours.
        { names = { "nameplateUseClassColorForFriendlyPlayerUnitNames" }, value = "0" },
    },
    style = style,
    Roleplay = function(db)
        return db.roleplayName or db.roleplayColor or db.roleplayIcon
    end,
    OnEnable = function(self)
        if Units.HasRecentAllies() then
            for _, event in ipairs(Units.RECENT_ALLY_EVENTS) do
                self:On(event, onRecentAllies)
            end
        end
        syncColors(true)
    end,
    OnDisable = function()
        syncColors(false)
    end,
    OnOptionChanged = function()
        syncColors(true)
    end,
})

-- Names Only in Dungeons: into or out of an instance (a loading screen), or a forbidden plate
-- somewhere this didn't expect one. Set out of combat, as every nameplate CVar is (ns.CVars).
local whileInstanceNames = {
    PLAYER_ENTERING_WORLD = function()
        forbiddenSeen = false
        plates:ApplyCVars(true)
    end,
}
if ns.HasEvent("FORBIDDEN_NAME_PLATE_UNIT_ADDED") then
    whileInstanceNames.FORBIDDEN_NAME_PLATE_UNIT_ADDED = function()
        if not forbiddenSeen and ns.Instances.Here() then
            forbiddenSeen = true
            plates:ApplyCVars(true)
        end
    end
end
module:OnWhile("instanceNames", whileInstanceNames)

-- Dim Other Players leaves your target bright, so the plates follow the target.
module:OnWhile("dimOthers", {
    PLAYER_TARGET_CHANGED = function()
        plates:Refresh()
    end,
})
