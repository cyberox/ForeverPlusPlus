-- Player Nameplates: friendly players always show their name, with their guild, level, and group
-- and friend icons beside it, and the health bar only shows while they're hurt or in combat.
-- The plates themselves are ns.FriendlyPlates; this module picks the colors and the guild line.
-- Enemy Player Names is the one thing it does to a plate that isn't friendly: Blizzard's own name
-- there, in one color.
local _, ns = ...

local ipairs, GetGuildInfo, format, setmetatable = ipairs, GetGuildInfo, format, setmetatable
local UnitClass, UnitIsUnit, UnitPVPName = UnitClass, UnitIsUnit, UnitPVPName
local UnitIsPlayer, UnitIsFriend = UnitIsPlayer, UnitIsFriend

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
    groupColor = "off", -- "off", or one of NAME_COLORS for party and raid members' names
    enemyColor = "off", -- "off", or one of NAME_COLORS for enemy players' names
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

-- A new list each call, so each option has its own.
local function nameColorChoices()
    return {
        { "off", L.PLAYERNAMEPLATES_COLOR_OFF },
        { "red", L.PLATES_COLOR_RED },
        { "orange", L.PLATES_COLOR_ORANGE },
        { "yellow", L.PLATES_COLOR_YELLOW },
        { "green", L.PLATES_COLOR_GREEN },
        { "blue", L.PLATES_COLOR_BLUE },
        { "purple", L.PLATES_COLOR_PURPLE },
        { "pink", L.PLATES_COLOR_PINK },
        { "white", L.PLATES_COLOR_WHITE },
    }
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
        key = "enemyColor", name = L.PLAYERNAMEPLATES_ENEMY_COLOR,
        description = L.PLAYERNAMEPLATES_ENEMY_COLOR_DESC,
        choices = nameColorChoices(), section = L.PLATES_SECTION_NAME, added = "1.9.0",
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

-- Group Member Names: the color picked for someone in your party or raid, or nil. It comes before
-- every other name color: a group member is nearly always a recent ally too, and it's the one the
-- player asked to tell apart at a glance.
local function groupColor(unit)
    local color = NAME_COLORS[module.db.groupColor]
    if color and Units.InGroup(unit) then
        return color
    end
end

function style.NameColor(unit)
    local group = groupColor(unit)
    if group then
        return group[1], group[2], group[3]
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
    local group = groupColor(unit)
    if group then
        return group[1], group[2], group[3]
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
module.notice = {
    ns.CVars.OffNotice(module, SHOW_FRIENDLY, L.PLATES_BLIZZARD_OFF, L.PLAYERNAMEPLATES_BLIZZARD_OFF_DESC),
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
local weak = { __mode = "k" }
local enemyUnits = setmetatable({}, weak) -- Blizzard's name -> its plate's unit, while on screen
local enemyKnown = setmetatable({}, weak) -- Blizzard's name -> whether that unit is an enemy player
local blizzardColor = setmetatable({}, weak) -- Blizzard's name -> { r, g, b } Blizzard last set
local enemyPainted = setmetatable({}, weak) -- Blizzard's name -> true while in our color
local paintingEnemy = false
-- The key ns.Nameplates knows this by; the Profiler charges it to the module.
local enemyOwner = { module = module }

-- Whether the plate's unit is an enemy player. Who a unit is can be secret (in combat, an
-- instance): then the last answer for this plate stands, and none yet counts as no.
local function isEnemyPlayer(text, unit)
    local isPlayer, isFriend = UnitIsPlayer(unit), UnitIsFriend("player", unit)
    if readable(isPlayer) and readable(isFriend) then
        enemyKnown[text] = (isPlayer and not isFriend) and true or false
    end
    return enemyKnown[text] or false
end

-- Blizzard's color back. Its values may be secret, so they're only ever passed on. Three numbers,
-- never an alpha: that would show a name the friendly plates hid.
local function restoreEnemyName(text)
    local old = blizzardColor[text]
    enemyPainted[text] = nil
    if old then
        paintingEnemy = true
        text:SetVertexColor(old[1], old[2], old[3])
        paintingEnemy = false
    end
end

local function paintEnemyName(text)
    local unit = enemyUnits[text]
    local color = unit and NAME_COLORS[module.db.enemyColor]
    if not (color and isEnemyPlayer(text, unit)) then
        if enemyPainted[text] then
            restoreEnemyName(text)
        end
        return
    end
    -- Blizzard colored it before our hook saw: keep what it shows now to put back.
    if not blizzardColor[text] then
        local r, g, b = text:GetVertexColor()
        blizzardColor[text] = { r, g, b }
    end
    paintingEnemy = true
    text:SetVertexColor(color[1], color[2], color[3])
    paintingEnemy = false
    enemyPainted[text] = true
end

-- Remember what Blizzard sets, then paint over it again.
local function onEnemyNameColored(text, r, g, b)
    if paintingEnemy or not enemyUnits[text] then
        return
    end
    blizzardColor[text] = { r, g, b }
    paintEnemyName(text)
end

local function enemyNameOf(frame)
    local text = ns.Nameplates.Parts(frame).name
    return text and text.SetVertexColor and text or nil
end

local enemyHandlers = {
    OnAdded = function(unit, frame)
        local text = enemyNameOf(frame)
        if text then
            enemyUnits[text], enemyKnown[text] = unit, nil
            module:Hook(text, "SetVertexColor", onEnemyNameColored)
            paintEnemyName(text)
        end
    end,
    -- Plates are pooled: the next unit's name starts from Blizzard's color.
    OnRemoved = function(_, frame)
        local text = enemyNameOf(frame)
        if text then
            if enemyPainted[text] then
                restoreEnemyName(text)
            end
            enemyUnits[text], enemyKnown[text], blizzardColor[text] = nil, nil, nil
        end
    end,
}

-- Watches the plates only while the option has a color, so it costs nothing otherwise.
local function syncEnemyNames(on)
    if on and NAME_COLORS[module.db.enemyColor] then
        ns.Nameplates.Register(enemyOwner, enemyHandlers)
        -- Already watching: the color may have changed.
        ns.Nameplates.ForEach(function(_, frame)
            local text = enemyNameOf(frame)
            if text then
                paintEnemyName(text)
            end
        end)
    else
        ns.Nameplates.Unregister(enemyOwner)
    end
end

-- A duel starts or ends, or a player flags, with the plate still up.
module:OnWhile("enemyColor", {
    UNIT_FACTION = function(_, unit)
        local frame = unit and ns.Nameplates.FrameFor(unit)
        local text = frame and enemyNameOf(frame)
        if text and enemyUnits[text] then
            paintEnemyName(text)
        end
    end,
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
        syncEnemyNames(true)
    end,
    OnDisable = function()
        syncEnemyNames(false)
    end,
    OnOptionChanged = function()
        syncEnemyNames(true)
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
