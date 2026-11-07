-- Tooltips: colors unit and item tooltips so they say more at a glance. The border and name
-- follow the unit's class or how it feels about you, item borders follow quality, the guild,
-- level and class on a unit's lines get colors, a player's title shows in their name, and a line
-- says who the unit is targeting. Ideas from ManiaTip; none of its code.
--
-- Every change is made after Blizzard builds the tooltip (TooltipDataProcessor post calls), on
-- Blizzard's own lines, except Quest Lines, which leaves the quest lines out as it's built (line
-- pre calls). Unit data can be secret, mostly in combat and instances: text we'd have to read is
-- left alone then, and colors that come back secret go straight to the setters.
local _, ns = ...

local _G, type, setmetatable, ipairs = _G, type, setmetatable, ipairs
local find, sub, byte, format = string.find, string.sub, string.byte, string.format
local Enum, C_Item = Enum, C_Item
local UnitExists, UnitClass, UnitLevel, UnitName = UnitExists, UnitClass, UnitLevel, UnitName
local UnitPVPName, UnitIsUnit, UnitReaction, UnitSelectionColor = UnitPVPName, UnitIsUnit, UnitReaction, UnitSelectionColor
local GetGuildInfo, GetCreatureDifficultyColor = GetGuildInfo, GetCreatureDifficultyColor
local GetQuestDifficultyColor, FACTION_BAR_COLORS = GetQuestDifficultyColor, FACTION_BAR_COLORS
local NORMAL_FONT_COLOR, TOOLTIP_DEFAULT_COLOR = NORMAL_FONT_COLOR, TOOLTIP_DEFAULT_COLOR
local FACTION_HORDE, FACTION_ALLIANCE = FACTION_HORDE, FACTION_ALLIANCE
local GameTooltip, InCombatLockdown = GameTooltip, InCombatLockdown

local L = ns.L
local readable = ns.IsReadable
local Units = ns.Units
local colorCode = ns.Colors.Code

local module = ns.NewModule("Tooltips", L.TOOLTIPS_DESC, {
    enabled = true,
    border = "class", -- unit borders: "class" (players by class, others by reaction), "reaction", "off"
    itemBorder = true,
    nameColor = "class", -- unit names, same choices as border
    guildColor = "all", -- "mine" (your guild green), "all" (yours green, others gray), "off"
    levelColor = true,
    classColor = true,
    factionColor = true,
    friends = true,
    title = true,
    target = true,
    hideInCombat = false, -- hide unit tooltips while in combat
    anchorCursor = false, -- tooltips at the mouse instead of the bottom right
    hideHealthBar = false, -- hide the health bar under unit tooltips
    questLines = "show", -- "show", "units" (hidden on unit tooltips), "all" (and on objects)
})
module.title = L.TOOLTIPS_TITLE
module.category = "interface"

local UNIT_COLORS = {
    { "class", L.TOOLTIPS_COLOR_CLASS },
    { "reaction", L.TOOLTIPS_COLOR_REACTION },
    { "off", L.TOOLTIPS_COLOR_OFF },
}

module.options = {
    { key = "border", name = L.TOOLTIPS_BORDER, description = L.TOOLTIPS_BORDER_DESC,
        choices = UNIT_COLORS, section = L.TOOLTIPS_SECTION_BORDERS },
    { key = "itemBorder", name = L.TOOLTIPS_ITEM_BORDER, description = L.TOOLTIPS_ITEM_BORDER_DESC,
        section = L.TOOLTIPS_SECTION_BORDERS },
    { key = "nameColor", name = L.TOOLTIPS_NAME_COLOR, description = L.TOOLTIPS_NAME_COLOR_DESC,
        choices = UNIT_COLORS, section = L.TOOLTIPS_SECTION_TEXT },
    {
        key = "guildColor", name = L.TOOLTIPS_GUILD_COLOR, description = L.TOOLTIPS_GUILD_COLOR_DESC,
        section = L.TOOLTIPS_SECTION_TEXT,
        choices = {
            { "mine", L.TOOLTIPS_GUILD_COLOR_MINE },
            { "all", L.TOOLTIPS_GUILD_COLOR_ALL },
            { "off", L.TOOLTIPS_COLOR_OFF },
        },
    },
    { key = "levelColor", name = L.TOOLTIPS_LEVEL_COLOR, description = L.TOOLTIPS_LEVEL_COLOR_DESC,
        section = L.TOOLTIPS_SECTION_TEXT },
    { key = "classColor", name = L.TOOLTIPS_CLASS_COLOR, description = L.TOOLTIPS_CLASS_COLOR_DESC,
        section = L.TOOLTIPS_SECTION_TEXT },
    { key = "factionColor", name = L.TOOLTIPS_FACTION_COLOR,
        description = L.TOOLTIPS_FACTION_COLOR_DESC, section = L.TOOLTIPS_SECTION_TEXT },
    { key = "friends", name = L.TOOLTIPS_FRIENDS, description = L.TOOLTIPS_FRIENDS_DESC,
        section = L.TOOLTIPS_SECTION_TEXT, added = "1.0.2" },
    { key = "title", name = L.TOOLTIPS_PLAYER_TITLE, description = L.TOOLTIPS_PLAYER_TITLE_DESC,
        section = L.TOOLTIPS_SECTION_LINES },
    { key = "target", name = L.TOOLTIPS_TARGET, description = L.TOOLTIPS_TARGET_DESC,
        section = L.TOOLTIPS_SECTION_LINES },
    { key = "anchorCursor", name = L.TOOLTIPS_ANCHOR_CURSOR, description = L.TOOLTIPS_ANCHOR_CURSOR_DESC,
        section = L.TOOLTIPS_SECTION_BEHAVIOR },
    { key = "hideInCombat", name = L.TOOLTIPS_HIDE_IN_COMBAT, description = L.TOOLTIPS_HIDE_IN_COMBAT_DESC,
        section = L.TOOLTIPS_SECTION_BEHAVIOR },
    { key = "hideHealthBar", name = L.TOOLTIPS_HIDE_HEALTH_BAR,
        description = L.TOOLTIPS_HIDE_HEALTH_BAR_DESC, section = L.TOOLTIPS_SECTION_BEHAVIOR, added = "0.9.0" },
    {
        key = "questLines", name = L.TOOLTIPS_QUEST_LINES, description = L.TOOLTIPS_QUEST_LINES_DESC,
        section = L.TOOLTIPS_SECTION_BEHAVIOR, added = "1.3.0",
        choices = {
            { "show", L.TOOLTIPS_QUEST_LINES_SHOW },
            { "units", L.TOOLTIPS_QUEST_LINES_UNITS },
            { "all", L.TOOLTIPS_QUEST_LINES_ALL },
        },
    },
}

local GUILDMATE_COLOR = ns.Colors.GUILD_GREEN -- as on Player Nameplates
local GUILD_COLOR = ns.Colors.GRAY
local YOU_COLOR = ns.Colors.RED

-- Text and colors -----------------------------------------------------------------------------

local leftLine = ns.Text.LeftLine

-- The text Blizzard put on line `i`, from the tooltip's data rather than the font string, or
-- nil when it's missing or secret.
local function lineText(data, i)
    local lineData = data.lines[i]
    local text = lineData and lineData.leftText
    if ns.IsText(text) then
        return text
    end
end

-- The tooltip's left font string for data line `i`. Blizzard numbers each line it adds
-- (lineData.lineIndex); after a line left out (Quest Lines, or another addon's line pre call),
-- the tooltip's lines no longer match their place in the data. When the first line has a number
-- and this one hasn't, it was left out: nil.
local function dataLine(tooltip, data, i)
    local lineData, first = data.lines[i], data.lines[1]
    local index = lineData and lineData.lineIndex
    if ns.IsNumber(index) then
        return leftLine(tooltip, index)
    end
    if lineData and not (first and ns.IsNumber(first.lineIndex)) then
        return leftLine(tooltip, i)
    end
end

-- Whether the byte at `i` is an ASCII letter or digit, so a match there runs into a longer word.
local function wordByte(text, i)
    local c = byte(text, i)
    return c and ((c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122))
end

-- Where `word` first stands alone in `text`. A plain search with the edges checked by hand, since
-- %w and %f only know ASCII and would never match a Russian or Korean class name.
local function findWord(text, word)
    local start = 1
    while true do
        local first, last = find(text, word, start, true)
        if not first then
            return
        end
        if not wordByte(text, first - 1) and not wordByte(text, last + 1) then
            return first, last
        end
        start = first + 1
    end
end

-- `text` with the first match of `pattern` (or of `word`, standing alone) wrapped in a color, and
-- whether it matched. The |r goes back to the line's own color.
local function colorMatch(text, pattern, r, g, b, word)
    local first, last
    if word then
        first, last = findWord(text, word)
    else
        first, last = find(text, pattern)
    end
    if not first then
        return text, false
    end
    return sub(text, 1, first - 1) .. colorCode(r, g, b) .. sub(text, first, last) .. "|r" .. sub(text, last + 1), true
end

-- The unit's class color, or nil when it isn't a player or its class can't be read.
local classColor = ns.Colors.PlayerClass

-- true and r, g, b for the unit in `mode` ("class" or "reaction"), or nothing. The first value
-- is only there to test: the colors may be secret, so they can't be.
local function unitColor(unit, mode)
    if mode == "class" then
        local color = classColor(unit)
        if color then
            return true, color:GetRGB()
        end
    end
    -- Probe: UnitSelectionColor is the color Blizzard gives the unit's name and selection circle,
    -- and may come back secret. Without it, the reputation bar colors by reaction.
    if UnitSelectionColor then
        return true, UnitSelectionColor(unit, true)
    end
    local reaction = UnitReaction(unit, "player")
    local color = readable(reaction) and reaction and FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction]
    if color then
        return true, color.r, color.g, color.b
    end
end

-- The color for a unit of `level` against the player's, as quest levels are colored.
local function levelColor(level)
    if level <= 0 then
        local own = UnitLevel("player")
        if not (ns.IsNumber(own)) then
            return nil
        end
        level = own + 10 -- "??": far above the player
    end
    local getColor = GetCreatureDifficultyColor or GetQuestDifficultyColor
    return getColor and getColor(level)
end

-- Border -------------------------------------------------------------------------------------

local colored = setmetatable({}, { __mode = "k" }) -- tooltip -> true while we colored its border
local clearHooked = setmetatable({}, { __mode = "k" }) -- tooltip -> true

local function resetBorder(tooltip)
    if colored[tooltip] then
        colored[tooltip] = nil
        if TOOLTIP_DEFAULT_COLOR then
            tooltip.NineSlice:SetBorderColor(TOOLTIP_DEFAULT_COLOR:GetRGB())
        else
            tooltip.NineSlice:SetBorderColor(1, 1, 1)
        end
    end
end

local function setBorder(tooltip, r, g, b)
    local slice = tooltip.NineSlice
    if not (slice and slice.SetBorderColor) or tooltip.IsEmbedded then
        return -- tooltips inside other tooltips use their parent's border
    end
    if not clearHooked[tooltip] then
        clearHooked[tooltip] = true
        tooltip:HookScript("OnTooltipCleared", resetBorder)
    end
    colored[tooltip] = true
    slice:SetBorderColor(r, g, b)
end

-- Unit tooltips ------------------------------------------------------------------------------

-- The unit the tooltip shows, or nil when it can't tell.
local function tooltipUnit(tooltip)
    if not tooltip.GetUnit then
        return nil
    end
    local _, unit = tooltip:GetUnit()
    if not ns.IsText(unit) then
        return nil
    end
    local exists = UnitExists(unit)
    if readable(exists) and exists then
        return unit
    end
end

-- Puts the title in the name when Blizzard's line is only the name.
local function addTitle(tooltip, data, unit)
    local shown, name = lineText(data, 1), UnitName(unit)
    local full = UnitPVPName and UnitPVPName(unit)
    if shown and readable(name) and readable(full) and full and shown == name and full ~= name then
        local line = leftLine(tooltip, 1)
        if line then
            line:SetText(full)
        end
    end
end

-- Colors the <Guild> line and returns its number, so the level search skips it.
local function colorGuild(tooltip, data, unit)
    local guild = GetGuildInfo(unit)
    if not (readable(guild) and guild) then
        return nil
    end
    for i = 2, 4 do
        local text = lineText(data, i)
        if text and find(text, guild, 1, true) then
            local mode, color = module.db.guildColor, nil
            if mode ~= "off" and Units.IsGuildmate(unit) then
                color = GUILDMATE_COLOR
            elseif mode == "all" then
                color = GUILD_COLOR
            end
            local line = color and dataLine(tooltip, data, i)
            if line then
                line:SetTextColor(color[1], color[2], color[3])
            end
            return i
        end
    end
end

-- Colors the level by difficulty and the class name by class, on the level line (and the line
-- after it, where Mainline puts a player's specialization and class).
local function colorLevelLine(tooltip, data, unit, guildLine)
    local db = module.db
    local level = UnitLevel(unit)
    if not (ns.IsNumber(level)) then
        return
    end
    local levelPattern = level > 0 and "%f[%d]" .. level .. "%f[%D]" or "%?%?"
    local className = db.classColor and UnitClass(unit)
    local class = classColor(unit)
    local classWord = readable(className) and className ~= "" and class and className
    for i = 2, #data.lines do
        local text = i ~= guildLine and lineText(data, i)
        if text and find(text, levelPattern) then
            local changed, found = false
            if db.levelColor then
                local color = levelColor(level)
                if color then
                    text, changed = colorMatch(text, levelPattern, color.r, color.g, color.b)
                end
            end
            if classWord then
                local r, g, b = class:GetRGB()
                text, found = colorMatch(text, nil, r, g, b, classWord)
                changed = changed or found
                local nextText = not found and lineText(data, i + 1)
                if nextText then
                    local nextLine = dataLine(tooltip, data, i + 1)
                    nextText, found = colorMatch(nextText, nil, r, g, b, classWord)
                    if found and nextLine then
                        nextLine:SetText(nextText)
                    end
                end
            end
            local line = changed and dataLine(tooltip, data, i)
            if line then
                line:SetText(text)
            end
            return
        end
    end
end

-- Colors the "Horde" or "Alliance" line Blizzard adds to a unit, in the side's color, as on maps.
local function colorFaction(tooltip, data)
    for i = 2, #data.lines do
        local text = lineText(data, i)
        local side = text and (text == FACTION_HORDE and "H" or text == FACTION_ALLIANCE and "A")
        local line = side and dataLine(tooltip, data, i)
        if line then
            local color = ns.Colors.Faction(side)
            line:SetTextColor(color.r, color.g, color.b)
            return
        end
    end
end

-- Adds "Target: <name>", or "Target: You", colored like names.
local function addTarget(tooltip, unit)
    local target = unit .. "target"
    local exists = UnitExists(target)
    if not (readable(exists) and exists) then
        return
    end
    local lr, lg, lb = NORMAL_FONT_COLOR:GetRGB()
    local isPlayer = UnitIsUnit(target, "player")
    if readable(isPlayer) and isPlayer then
        tooltip:AddDoubleLine(L.TOOLTIPS_TARGET_LINE, L.TOOLTIPS_TARGET_YOU, lr, lg, lb,
            YOU_COLOR[1], YOU_COLOR[2], YOU_COLOR[3])
        return
    end
    local ok, r, g, b = unitColor(target, "class")
    if not ok then
        r, g, b = 1, 1, 1
    end
    -- The name may be secret; it goes straight to the tooltip.
    tooltip:AddDoubleLine(L.TOOLTIPS_TARGET_LINE, UnitName(target), lr, lg, lb, r, g, b)
end

-- Hide in Combat fades GameTooltip rather than hiding it: Hide would run Blizzard's OnHide from
-- our code, mid-processing and in combat, and taint the next tooltip. The next tooltip or its
-- hiding brings it back.
local faded = false

local function unfade()
    if faded then
        faded = false
        GameTooltip:SetAlpha(1)
    end
end

local function onUnit(tooltip, data)
    -- Hide in Combat: the mouseover tooltip only; tooltips the player opens stay.
    if module.db.hideInCombat and tooltip == GameTooltip and InCombatLockdown() then
        faded = true
        tooltip:SetAlpha(0)
        return
    end
    local unit = data and tooltipUnit(tooltip)
    if not unit then
        return
    end
    local db = module.db
    local lines = readable(data.lines) and type(data.lines) == "table"
    if lines and db.title then
        addTitle(tooltip, data, unit)
    end
    if db.nameColor ~= "off" then
        local ok, r, g, b = unitColor(unit, db.nameColor)
        local line = ok and leftLine(tooltip, 1)
        if line then
            line:SetTextColor(r, g, b)
        end
    end
    if db.border ~= "off" then
        local ok, r, g, b = unitColor(unit, db.border)
        if ok then
            setBorder(tooltip, r, g, b)
        end
    end
    if lines then
        colorLevelLine(tooltip, data, unit, colorGuild(tooltip, data, unit))
        if db.factionColor then
            colorFaction(tooltip, data)
        end
    end
    if db.target then
        addTarget(tooltip, unit)
    end
end

-- Friends list tooltips ----------------------------------------------------------------------

-- Forever's friends list is the Social window's (docs/forever-api.md), whose cards build a plain
-- GameTooltip with no tooltip data: the account name, then for a WoW character its name, "Level 17
-- Shaman", race, zone, and side (FriendsListSocialCardMixin:BuildTooltip, Gethe `forever` branch,
-- checked 2026-11-05). So it's recolored after it shows, finding Blizzard's lines by the text it
-- built from the card's own friend info. Battle.net friend info isn't secret.

-- The friend info of the Social window card that owns the tooltip, or nil for any other owner.
local function friendCardInfo(tooltip)
    local mixin = _G.FriendsListSocialCardMixin
    local owner = mixin and tooltip:GetOwner()
    if not (owner and owner.BuildTooltip == mixin.BuildTooltip) then
        return nil
    end
    local data = owner.elementData
    local info = data and data.accountInfo
    local game = info and info.gameAccountInfo
    if game and game.isOnline and ns.IsText(game.characterName, true) and ns.IsText(game.className, true)
        and ns.IsNumber(game.characterLevel) then
        return game
    end
end

-- The tooltip's line `i` and its text, when it's readable.
local function shownLine(tooltip, i)
    local line = leftLine(tooltip, i)
    local text = line and line:GetText()
    if ns.IsText(text) then
        return line, text
    end
end

local function onFriendTooltip(tooltip)
    local db = module.db
    local game = db.friends and friendCardInfo(tooltip)
    if not (game and FRIENDS_LEVEL_TEMPLATE) then
        return
    end
    local levelText = format(FRIENDS_LEVEL_TEMPLATE, game.characterLevel, game.className)
    for i = 2, tooltip:NumLines() do
        local line, text = shownLine(tooltip, i)
        if text == levelText then
            local class = ns.Colors.ClassToken(game.classFilename)
                or ns.Colors.ClassToken(ns.Players.ClassToken(game.className))
            local nameLine, nameText = shownLine(tooltip, i - 1)
            if class and db.nameColor ~= "off" and nameText and find(nameText, game.characterName, 1, true) then
                nameLine:SetTextColor(class:GetRGB())
            end
            -- A level against the player's means something only in this game.
            local color = db.levelColor and game.wowProjectID == WOW_PROJECT_ID and levelColor(game.characterLevel)
            local levelPattern = "%f[%d]" .. game.characterLevel .. "%f[%D]"
            if color then
                text = colorMatch(text, levelPattern, color.r, color.g, color.b)
            end
            if class and db.classColor then
                local r, g, b = class:GetRGB()
                text = colorMatch(text, nil, r, g, b, game.className)
            end
            line:SetText(text)
            -- Race and zone, then the side.
            local sideLine, side = shownLine(tooltip, i + 3)
            side = side and (side == FACTION_HORDE and "H" or side == FACTION_ALLIANCE and "A")
            if side and db.factionColor then
                local faction = ns.Colors.Faction(side)
                sideLine:SetTextColor(faction.r, faction.g, faction.b)
            end
            return
        end
    end
end

-- Item tooltips ------------------------------------------------------------------------------

local function onItem(tooltip, data)
    if not (module.db.itemBorder and data and C_Item.GetItemQualityByID) then
        return
    end
    local item = ns.ItemTooltip.ItemID(data)
    if not item and readable(data.hyperlink) then
        item = data.hyperlink
    end
    local quality = item and C_Item.GetItemQualityByID(item)
    if readable(quality) and quality and C_Item.GetItemQualityColor then
        local r, g, b = C_Item.GetItemQualityColor(quality)
        if r then
            setBorder(tooltip, r, g, b)
        end
    end
end

-- Anchor to Cursor: after Blizzard places a tooltip at its default spot (bottom right), move it
-- to the mouse instead.
local function onDefaultAnchor(tooltip, parent)
    if module.db.anchorCursor then
        tooltip:SetOwner(parent, "ANCHOR_CURSOR")
    end
end

-- Hide Health Bar: GameTooltip.StatusBar hangs under the tooltip and shows, hides, and fills
-- itself from a unit's GUID on every unit tooltip (GameTooltipUnitHealthBarMixin, with secure
-- methods because the health may be secret). Fading it leaves all of that to Blizzard: nothing
-- reads the bar, hooks it, or runs when it shows.
local function fadeHealthBar(hide)
    local bar = GameTooltip.StatusBar
    if bar then
        bar:SetAlpha(hide and 0 or 1)
    end
end

-- Quest Lines: true leaves a quest line (its title, an objective, or whose they are in a group) out
-- of a unit's tooltip, or an object's too, as the tooltip is built. Idea from NoQuestTooltips and
-- cyberox's Hide Quest Tooltips. Only the tooltip skips them: the data keeps them, so what reads
-- it (Quest Nameplates, through C_TooltipInfo) still sees them. The tooltip's type is never secret,
-- since Blizzard keys its own callback tables by it.
local QUEST_LINES = { "QuestTitle", "QuestObjective", "QuestPlayer" }

local function skipQuestLine(tooltip)
    local mode = module.db.questLines
    if mode == "show" or not tooltip.GetProcessingTooltipInfo then
        return false
    end
    local info = tooltip:GetProcessingTooltipInfo()
    local kind = info and info.tooltipData and info.tooltipData.type
    local types = Enum.TooltipDataType
    return kind == types.Unit or (mode == "all" and kind == types.Object)
end

function module:OnEnable()
    -- Probe: line types and line pre calls are Mainline's.
    local lineTypes = Enum.TooltipDataLineType
    for _, name in ipairs(lineTypes and QUEST_LINES or {}) do
        self:TooltipLinePreCall(lineTypes[name], skipQuestLine)
    end
    self:TooltipPostCall(Enum.TooltipDataType.Unit, onUnit)
    self:TooltipPostCall(Enum.TooltipDataType.Item, onItem)
    -- The friends list's tooltip has no tooltip data for a post call, so after it shows.
    self:Hook(GameTooltip, "Show", onFriendTooltip)
    -- GameTooltip_SetDefaultAnchor is Blizzard's for every default-placed tooltip.
    self:Hook("GameTooltip_SetDefaultAnchor", onDefaultAnchor)
    self:HookScript(GameTooltip, "OnTooltipCleared", unfade)
    self:HookScript(GameTooltip, "OnHide", unfade)
    fadeHealthBar(self.db.hideHealthBar)
end

function module:OnDisable()
    fadeHealthBar(false)
    unfade()
end

function module:OnOptionChanged(key)
    if key == "hideHealthBar" and self.enabled then
        fadeHealthBar(self.db.hideHealthBar)
    end
end
