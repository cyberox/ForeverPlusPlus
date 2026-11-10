-- Zone Info, a part of World Map: a small panel in a corner of the world map about the zone it
-- shows, or on a continent map the zone under the cursor: its level range colored against yours,
-- the Fishing skill its waters need, and the herbs, ore, and skinning it has for the gathering
-- professions you have. Ideas from Leatrix Maps' zone levels; none of its code. The zones are in
-- Data.lua.
local _, ns = ...

local pairs, ipairs, tostring, format, concat = pairs, ipairs, tostring, string.format, table.concat
local MAP_AREA_LABEL_TYPE = MAP_AREA_LABEL_TYPE
local min, max, GetLocale = math.min, math.max, GetLocale
local unpack, ceil, type = unpack, math.ceil, type
local CreateFrame, C_Map, C_Item = CreateFrame, C_Map, C_Item

local L = ns.L
local Professions = ns.Professions
local NoBreak = ns.MapTooltip.NoBreak
local Keys = ns.Keys

-- The Skip Key dropdown's keys, without None: each row that uses the key has its own Off.
local DETAIL_KEYS = {}
for _, choice in ipairs(Keys.CHOICES) do
    if choice[1] ~= "none" then
        DETAIL_KEYS[#DETAIL_KEYS + 1] = choice
    end
end

local module = ns.modules.WorldMap:NewPart({
    key = "zoneInfo", name = L.ZONEINFO_TITLE, description = L.ZONEINFO_DESC,
    section = L.ZONEINFO_TITLE,
}, {
    corner = "BOTTOMLEFT",
    hover = true, -- on continent maps, the zone under the cursor
    hideLabel = true, -- and then the map's own zone name at the top, which says the same
    levels = true,
    faction = "name", -- who holds the zone: "off", "name" (the name's color), or "line"
    zoneDungeons = "always", -- "off", "always", or "key" (while holding the detail key)
    detailKey = "shift", -- "shift", "alt", or "ctrl"
    fishing = "always",
    -- Herbs, ore, and skinning: "off", "known" (only with the profession), or "always".
    herbs = "known",
    ore = "known",
    skinning = "known",
    scale = 100, -- percent of the panel's normal size
    folded = false, -- down to its title, from the panel's minus button; not an option
})

-- What a line can be: never, always, or only while holding the detail key, and for professions
-- also only with the profession.
local SHOW_ALWAYS = {
    { "off", L.ZONEINFO_SHOW_OFF },
    { "always", L.ZONEINFO_SHOW_ALWAYS },
    { "key", L.ZONEINFO_SHOW_KEY },
}
local SHOW_KNOWN = {
    { "off", L.ZONEINFO_SHOW_OFF },
    { "known", L.ZONEINFO_SHOW_KNOWN },
    { "always", L.ZONEINFO_SHOW_ALWAYS },
    { "key", L.ZONEINFO_SHOW_KEY },
}

-- Where the panel is first, with the detail key that some lines wait for; then the zone's own
-- lines, then the profession ones.
local GENERAL, ZONE, PROFESSIONS = L.ZONEINFO_SECTION_GENERAL, L.ZONEINFO_SECTION_ZONE,
    L.ZONEINFO_SECTION_PROFESSIONS
module:AddOptions({
    {
        key = "corner", name = L.ZONEINFO_CORNER, description = L.ZONEINFO_CORNER_DESC,
        choices = {
            { "BOTTOMLEFT", L.ZONEINFO_BOTTOMLEFT },
            { "BOTTOMRIGHT", L.ZONEINFO_BOTTOMRIGHT },
            { "TOPLEFT", L.ZONEINFO_TOPLEFT },
            { "TOPRIGHT", L.ZONEINFO_TOPRIGHT },
        },
        section = GENERAL,
    },
    {
        key = "scale", name = L.ZONEINFO_SIZE, description = L.ZONEINFO_SIZE_DESC,
        min = 70, max = 150, step = 10, format = "%d%%", section = GENERAL,
    },
    { key = "hover", name = L.ZONEINFO_HOVER, description = L.ZONEINFO_HOVER_DESC, section = GENERAL },
    {
        key = "hideLabel", name = L.ZONEINFO_HIDE_LABEL, description = L.ZONEINFO_HIDE_LABEL_DESC,
        requires = "hover", section = GENERAL,
    },
    {
        key = "detailKey", name = L.ZONEINFO_DETAIL_KEY, description = L.ZONEINFO_DETAIL_KEY_DESC,
        choices = DETAIL_KEYS,
        section = GENERAL,
    },
    { key = "levels", name = L.ZONEINFO_LEVELS, description = L.ZONEINFO_LEVELS_DESC, section = ZONE },
    {
        key = "faction", name = L.ZONEINFO_FACTION, description = L.ZONEINFO_FACTION_DESC,
        choices = {
            { "off", L.ZONEINFO_SHOW_OFF },
            { "name", L.ZONEINFO_FACTION_NAME },
            { "line", L.ZONEINFO_FACTION_LINE },
        },
        section = ZONE,
    },
    {
        key = "zoneDungeons", name = L.ZONEINFO_DUNGEONS, description = L.ZONEINFO_DUNGEONS_DESC,
        choices = SHOW_ALWAYS, section = ZONE,
    },
    {
        key = "herbs", name = L.ZONEINFO_HERBS, description = L.ZONEINFO_HERBS_DESC,
        choices = SHOW_KNOWN, section = PROFESSIONS, changed = "0.8.0", -- clearer description
    },
    {
        key = "ore", name = L.ZONEINFO_ORE, description = L.ZONEINFO_ORE_DESC,
        choices = SHOW_KNOWN, section = PROFESSIONS, changed = "0.8.0", -- clearer description
    },
    {
        key = "skinning", name = L.ZONEINFO_SKINNING, description = L.ZONEINFO_SKINNING_DESC,
        choices = SHOW_KNOWN, section = PROFESSIONS, changed = "0.8.0", -- clearer description
    },
    {
        key = "fishing", name = L.ZONEINFO_FISHING, description = L.ZONEINFO_FISHING_DESC,
        choices = SHOW_ALWAYS, section = PROFESSIONS,
    },
})

-- Shared with Data.lua: `zones` (by map ID), `herbs` and `ores` (by item ID).
local internal = {}
ns.modules.WorldMap.internal.zoneInfo = internal

local MAX_WIDTH = 300 -- the widest the text gets; longer lines wrap
local PADDING = 8
local GAP = 3 -- between rows
local ICON_SIZE = 16 -- pixels
local INDENT = ICON_SIZE + 4 -- a list's later rows start under its names, past the icon
local SECTION_GAP = 7 -- above the instances, to set them apart
local PER_ROW = 4 -- the most herbs or ores on a row
local THROTTLE = 0.1 -- seconds between looks at where the cursor is
local BUTTON = 14 -- the minus and plus button, pixels
local BUTTON_GAP = 6 -- between the title and the button

local colored = ns.Colors.Text

-- Text ----------------------------------------------------------------------------------------

-- The panel is a title and short rows: the profession ones each led by its icon, then the zone's
-- dungeons and raids:
--   Silverpine Forest  10-20
--   [fishing] Fishing 1    [skinning] Skinning 1-100
--   [herbalism] Peacebloom, Silverleaf, Earthroot
--   [mining] Copper, Tin, Silver

-- Each profession's icon, for when the player doesn't have it (a row set to Always still shows).
local ICONS = {
    [Professions.FISHING] = "Interface\\Icons\\Trade_Fishing",
    [Professions.SKINNING] = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
    [Professions.HERBALISM] = "Interface\\Icons\\Spell_Nature_NatureTouchGrow",
    [Professions.MINING] = "Interface\\Icons\\Trade_Mining",
}

-- "10-20", colored like a quest of that level.
local function levelText(low, high)
    local text = low == high and tostring(low) or format(L.ZONEINFO_RANGE, low, high)
    local color = ns.Colors.LevelRange(low, high)
    return color and colored(color, text) or text
end

-- A zone's level range: the game's (C_Map.GetMapLevels), else Data.lua's. Cities and Moonglade
-- have none in Data.lua and get none. Probe: whether Forever fills it for its zones is
-- Unverified, so anything but a range from 1 to 60 counts as none.
local function levelsOf(mapID, zone)
    if not zone[1] then
        return nil
    end
    local low, high
    if C_Map.GetMapLevels then
        low, high = C_Map.GetMapLevels(mapID) -- not `x and f()`, which keeps only the first value
    end
    if type(low) == "number" and type(high) == "number" and low >= 1 and high >= low
        and high <= 60 then
        return low, high
    end
    return zone[1], zone[2]
end

-- Whether the panel is in a right corner, where everything is mirrored: the icons come after
-- their text and the text lines up on the right.
local function onRight()
    return module.db.corner == "TOPRIGHT" or module.db.corner == "BOTTOMRIGHT"
end

-- A profession's icon in text, bigger than the small font so it reads at a glance, on the side of
-- `text` the corner calls for.
local function icon(line, own, text)
    local texture = format("|T%s:%d:%d|t", own or ICONS[line], ICON_SIZE, ICON_SIZE)
    return onRight() and text .. " " .. texture or texture .. " " .. text
end

-- Blizzard's green for a quest at your level.
local GREEN = Professions.STANDARD

-- A skill the zone needs, colored by how hard it is at the player's rank. Fishing's skill-ups
-- don't depend on the zone, so it's only enough or not: red while below it (fish get away),
-- green once there, and white without Fishing.
local function skill(rank, need, fishing)
    if not rank then
        return tostring(need) -- white: the player doesn't have the profession
    elseif fishing and rank >= need then
        return colored(GREEN, need)
    end
    return colored(Professions.Difficulty(rank, need), need)
end

-- Whether the detail key is held.
local function detailHeld()
    return Keys.IsDown(module.db.detailKey)
end

-- Whether a gathering row shows: its setting is "always", "known" and the player has the
-- profession (a rank), or "key" with the profession while the detail key is held.
local function shows(key, rank)
    local mode = module.db[key]
    return mode == "always" or (mode == "known" and rank ~= nil)
        or (mode == "key" and rank ~= nil and detailHeld())
end

-- Whether a row that isn't about a profession shows: "always", or "key" while the key is held.
local function visible(mode)
    return mode == "always" or (mode == "key" and detailHeld())
end

local function range(rank, low, high, fishing)
    local text = skill(rank, low, fishing)
    if high and high ~= low then
        text = format(L.ZONEINFO_RANGE, text, skill(rank, high, fishing))
    end
    return text
end

-- Fishing, and Skinning from the zone's level range, each as its setting says; together in one
-- row.
local function skillsRow(zone, low, high)
    local db, parts = module.db, {}
    if visible(db.fishing) and zone.fish then
        local rank, name, own = Professions.Rank(Professions.FISHING)
        parts[#parts + 1] = icon(Professions.FISHING, own, NoBreak(format(L.ZONEINFO_SKILL,
            name or L.ZONEINFO_FISHING_NAME, range(rank, zone.fish, zone.fishHigh, true))))
    end
    local rank, name, own = Professions.Rank(Professions.SKINNING)
    if shows("skinning", rank) and low then
        parts[#parts + 1] = icon(Professions.SKINNING, own, NoBreak(format(L.ZONEINFO_SKILL,
            name or L.ZONEINFO_SKINNING_NAME, range(rank, Professions.SkinningNeed(low),
                Professions.SkinningNeed(high)))))
    end
    if #parts > 0 then
        return concat(parts, "    ")
    end
end

-- An item's name: the short English one from Data.lua in English, else the game's own (which
-- keeps "Ore"), or the English until the game has loaded it.
local english = GetLocale() == "enUS"
local function itemName(id, name)
    if english or not (C_Item and C_Item.GetItemNameByID) then
        return name
    end
    local own = C_Item.GetItemNameByID(id)
    if not own and C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(id)
    end
    return own or name
end

-- The zone's herbs or ores, each colored by how hard it is at the player's skill, or nil when
-- `key`'s setting hides them (see shows) or the zone has none.
local function gatherRow(key, line, ids, items)
    local rank, _, own = Professions.Rank(line)
    if not (shows(key, rank) and ids and #ids > 0) then
        return nil
    end
    local names = {}
    for i, id in ipairs(ids) do
        local item = items[id]
        local name = itemName(id, item[2])
        names[i] = NoBreak(rank and colored(Professions.Difficulty(rank, item[1]), name) or name)
    end
    -- At most PER_ROW names to a row, split evenly (six are 3 and 3, not 4 and 2), so a long list
    -- is a few short rows instead of one that wraps and leaves a name alone.
    local count = ceil(#names / PER_ROW)
    local size = ceil(#names / count)
    local result = {}
    for row = 1, count do
        local text = concat(names, L.ZONEINFO_LIST_SEPARATOR, (row - 1) * size + 1,
            min(row * size, #names))
        result[row] = row == 1 and icon(line, own, text) or text
    end
    return result
end

-- Who holds the zone, from the player's side: the colors of Blizzard's zone text when you enter
-- one. `zone.side` is "A" or "H" for a faction's own land, or "C" for contested.
local TERRITORY = {
    friendly = { r = 0.1, g = 1, b = 0.1 },
    hostile = { r = 1, g = 0.1, b = 0.1 },
    contested = { r = 1, g = 0.7, b = 0 },
}

-- The zone's territory color and its line ("Horde Territory"), or nil when it isn't known.
local function territory(zone)
    local side = zone.side
    if not side then
        return nil
    elseif side == "C" then
        return TERRITORY.contested, L.ZONEINFO_CONTESTED
    end
    local color = side == ns.WorldMap.PlayerSide() and TERRITORY.friendly or TERRITORY.hostile
    return color, format(L.ZONEINFO_TERRITORY, ns.WorldMap.SideName(side) or side)
end

-- A dungeon or raid as one row: Points of Interest's, or in a right corner the same mirrored
-- (levels, name, then the icon).
local function instanceLine(instance)
    if not onRight() then
        return ns.Instances.Line(instance)
    end
    return format("%s  %s %s", ns.Instances.Levels(instance, true),
        NoBreak(ns.Instances.Name(instance)), ns.Instances.Icon(instance, ns.Instances.ICON_SIZE))
end

-- The rows under the zone's name, in order. The zone's dungeons and raids are a row each, as
-- Points of Interest lists them, so a row never wraps through a name or a level range.
local function rows(zone, low, high)
    local list = {}
    local function add(text, indent, gap)
        if text then
            list[#list + 1] = { text = text, indent = indent, gap = gap }
        end
    end
    if module.db.faction == "line" then
        local color, text = territory(zone)
        add(color and colored(color, text))
    end
    add(skillsRow(zone, low, high))
    for _, gather in ipairs({
        { "herbs", Professions.HERBALISM, zone.herbs, internal.herbs },
        { "ore", Professions.MINING, zone.ores, internal.ores },
    }) do
        -- A list that runs to a second row lines up under its names, not its icon.
        for i, row in ipairs(gatherRow(unpack(gather)) or {}) do
            add(row, i > 1)
        end
    end
    if visible(module.db.zoneDungeons) then
        for i, instance in ipairs(zone.dungeons or {}) do
            add(instanceLine(instance), false, i == 1 and #list > 0 and SECTION_GAP or nil)
        end
    end
    return list
end

-- Which zone ----------------------------------------------------------------------------------

-- The zone in Data.lua a map is, or is inside (a cave or a town's own map), or nil.
local function zoneOf(mapID)
    for each in ns.WorldMap.Up(mapID) do
        if internal.zones[each] then
            return each
        end
    end
end

-- The zone the panel is about: the map's own, or on a continent the one under the cursor.
local function target(map)
    local mapID = map:GetMapID()
    local info = mapID and C_Map.GetMapInfo(mapID)
    if not info then
        return nil
    end
    if not ns.WorldMap.IsContinent(info, true) then
        return zoneOf(mapID)
    end
    if not (module.db.hover and map.IsCanvasMouseFocus and map:IsCanvasMouseFocus()) then
        return nil
    end
    local x, y = map:GetNormalizedCursorPosition()
    local under = x and C_Map.GetMapInfoAtPosition and C_Map.GetMapInfoAtPosition(mapID, x, y)
    if under and under.mapID ~= mapID then
        return zoneOf(under.mapID), true
    end
end

-- The panel -----------------------------------------------------------------------------------

local panel, driver
local shownHeld -- whether the detail key was held then
local shown -- the zone the panel shows now, or false for none; nil to draw again
local toggleFolded -- the minus and plus button's click, set once draw is

local function foldTip(button)
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetText(module.db.folded and L.ZONEINFO_UNFOLD or L.ZONEINFO_FOLD, 1, 1, 1)
    GameTooltip:Show()
end

local function hideTip()
    GameTooltip:Hide()
end

-- A tooltip's look, which Blizzard uses for small boxes over the map.
local function newPanel(parent)
    local frame = ns.Frames.TooltipBox(parent)
    -- Over the map's pins, which sit on the canvas inside the same container.
    frame:SetFrameLevel(parent:GetFrameLevel() + 2000)
    -- The fonts of a GameTooltip: a white title, white rows.
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameTooltipHeaderText")
    frame.rows = {}
    -- Blizzard's minus and plus buttons, folding the panel down to its title and out again, for
    -- when it covers part of the map. The rest of the panel lets the mouse through.
    local fold = CreateFrame("Button", nil, frame)
    fold:SetSize(BUTTON, BUTTON)
    fold:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
    fold:SetScript("OnClick", function(self)
        toggleFolded()
        foldTip(self)
    end)
    fold:SetScript("OnEnter", foldTip)
    fold:SetScript("OnLeave", hideTip)
    frame.fold = fold
    frame:Hide()
    return frame
end

-- The panel's row `i`, made when the zone first needs that many.
local function rowAt(i)
    local row = panel.rows[i]
    if not row then
        row = panel:CreateFontString(nil, "OVERLAY", "GameTooltipText")
        panel.rows[i] = row
    end
    return row
end

local textWidth = ns.Text.Width

-- Blizzard's own coordinates, a row each for the cursor and the player, sit in the bottom left
-- corner from 2 pixels up, each row 15 tall, while their Settings checkboxes
-- (WorldMap.COORDS_CVARS) are on.
local COORDS_BOTTOM, COORDS_ROW = 2, 15

-- How far up the panel sits in the bottom left corner: over Blizzard's coordinates when they
-- show. By the checkboxes, not the rows, so the panel doesn't jump as the cursor row comes and
-- goes. Not when something has faded Blizzard's panel out to show the coordinates elsewhere
-- (such as our Coordinates part in the title bar): only the panel's own state is read.
local function bottomLeftOffset()
    local blizzard = ns.WorldMap.CoordsPanel()
    if blizzard and not (blizzard:IsShown() and blizzard:GetAlpha() > 0) then
        return 8
    end
    local rows = 0
    for _, name in ipairs(ns.WorldMap.COORDS_CVARS) do
        if ns.CVars.IsOn(name) then
            rows = rows + 1
        end
    end
    if rows == 0 then
        return 8
    end
    return COORDS_BOTTOM + rows * COORDS_ROW + 8
end

local anchored -- where the panel sits now: the corner and how far up, or nil to place it again

local function anchor()
    local corner, scale = module.db.corner, module.db.scale / 100
    -- Only the bottom left has Blizzard's coordinates to clear.
    local offset = corner == "BOTTOMLEFT" and bottomLeftOffset() or 8
    local key = corner .. offset .. ":" .. scale
    if key == anchored then
        return
    end
    anchored = key
    -- Offsets are in the panel's own scale, so divide to keep them the same on screen.
    panel:SetScale(scale)
    panel:ClearAllPoints()
    local x = onRight() and -8 or 8
    local y = corner:find("TOP") and -offset or offset
    panel:SetPoint(corner, panel:GetParent(), corner, x / scale, y / scale)
end

local function draw(mapID)
    shown = mapID or false
    shownHeld = detailHeld()
    local zone = mapID and internal.zones[mapID]
    if not zone then
        panel:Hide()
        return
    end
    local info = C_Map.GetMapInfo(mapID)
    local title = info and info.name or ""
    if module.db.faction == "name" then
        local color = territory(zone)
        if color then
            title = colored(color, title)
        end
    end
    local low, high = levelsOf(mapID, zone)
    if module.db.levels and low then
        title = format(L.ZONEINFO_TITLE_LEVELS, title, levelText(low, high))
    end
    local folded = module.db.folded
    local list = folded and {} or rows(zone, low, high)
    -- As wide as the longest line, up to MAX_WIDTH; longer lines wrap. The title leaves room for
    -- the button beside it.
    local beside = BUTTON + BUTTON_GAP
    panel.title:SetWidth(0)
    panel.title:SetText(title)
    local width = textWidth(panel.title) + beside
    for i = #panel.rows + 1, #list do
        rowAt(i)
    end
    for i, row in ipairs(panel.rows) do
        local entry = list[i]
        row:SetWidth(0)
        row:SetText(entry and entry.text or "")
        row:SetShown(entry ~= nil)
        if entry then
            width = max(width, textWidth(row) + (entry.indent and INDENT or 0))
        end
    end
    width = min(width, MAX_WIDTH)
    panel.title:SetWidth(width - beside)
    -- In a right corner the text lines up on the right, and a later row of a list is set in from
    -- there, past where the icon is.
    local side = onRight() and "RIGHT" or "LEFT"
    panel.title:ClearAllPoints()
    panel.title:SetPoint("TOP" .. side, side == "RIGHT" and -PADDING or PADDING, -PADDING)
    panel.title:SetJustifyH(side)
    local titleHeight = panel.title:GetStringHeight()
    local height = PADDING * 2 + titleHeight
    -- The button at the title's other end: a minus while the rows show, a plus while folded.
    local other = side == "RIGHT" and "LEFT" or "RIGHT"
    local look = folded and "Plus" or "Minus"
    local fold = panel.fold
    fold:SetNormalTexture("Interface\\Buttons\\UI-" .. look .. "Button-Up")
    fold:SetPushedTexture("Interface\\Buttons\\UI-" .. look .. "Button-Down")
    fold:ClearAllPoints()
    fold:SetPoint(other, panel, "TOP" .. other, other == "RIGHT" and -(PADDING - 2) or PADDING - 2,
        -(PADDING + titleHeight / 2))
    local above, aboveIndent = panel.title, 0
    for i, row in ipairs(panel.rows) do
        local entry = list[i]
        if entry then
            local indent = entry.indent and INDENT or 0
            local gap = entry.gap or GAP
            row:ClearAllPoints()
            local inset = indent - aboveIndent
            row:SetPoint("TOP" .. side, above, "BOTTOM" .. side, side == "RIGHT" and -inset or inset,
                -gap)
            row:SetJustifyH(side)
            row:SetWidth(width - indent)
            height = height + gap + row:GetStringHeight()
            above, aboveIndent = row, indent
        end
    end
    panel:SetSize(width + PADDING * 2, height)
    panel:Show()
end

toggleFolded = function()
    module.db.folded = not module.db.folded
    draw(shown or nil)
end

-- Blizzard's zone name ------------------------------------------------------------------------
-- On a continent map the game names the zone under the cursor at the top of the map, which says
-- what the panel's title does. While the panel shows that zone, it's faded out (never hidden or
-- changed), and only while it names just the zone: a pin's name there (a dungeon, a flight
-- point) stays.

local label -- Blizzard's area label frame, once found
local labelFaded = false
local hovered = false -- the panel shows the zone under the cursor on a continent map

-- Whether the label names anything besides the zone: its other label types with a name.
local function labelHasOther(frame)
    local byType = frame.labelInfoByType
    local types = MAP_AREA_LABEL_TYPE
    if not (byType and types) then
        return true -- can't tell, so leave it be
    end
    for kind, info in pairs(byType) do
        if kind ~= types.AREA_NAME and info.name then
            return true
        end
    end
    return false
end

-- After the label decides what to show, every frame while the map is open and the module is on.
local function onLabel(frame)
    local fade = (module.db.hover and module.db.hideLabel and hovered
        and not labelHasOther(frame)) and true or false
    if fade ~= labelFaded then
        labelFaded = fade
        frame:SetAlpha(fade and 0 or 1)
    end
end

-- The label comes from Blizzard's area label data provider. Probe: its `Label` frame and
-- `EvaluateLabels` are Mainline's.
local function hookLabel(map)
    for provider in pairs(map.dataProviders or {}) do
        local frame = provider.Label
        if frame and frame.EvaluateLabels then
            label = frame
            module:Hook(frame, "EvaluateLabels", onLabel)
            return
        end
    end
end

local function unfadeLabel()
    if label and labelFaded then
        labelFaded = false
        label:SetAlpha(1)
    end
end

local function look()
    -- Blizzard's coordinates can be turned on, off, or faded out at any time, with no event for
    -- the fading; this only moves the panel when that changed.
    anchor()
    local mapID, fromCursor = target(WorldMapFrame)
    hovered = (fromCursor and mapID) and true or false
    mapID = mapID or false
    local held = detailHeld()
    if mapID ~= shown or held ~= shownHeld then
        draw(mapID or nil)
    end
end

local onUpdate = ns.Frames.Throttled(THROTTLE, ns.Profiler.Wrap(module, look))

-- Draws the panel again on the next update, after something it shows changed.
local function redraw()
    shown = nil
end

-- Makes the panel on the world map, once the map has loaded. The driver looks at the map a few
-- times a second while it's open; it's the map's child, so it stops while the map is closed.
local function attach(map)
    if not driver then
        local parent = map.ScrollContainer or map
        panel = newPanel(parent)
        driver = CreateFrame("Frame", nil, parent)
        driver:SetScript("OnUpdate", onUpdate)
        -- The map closed: the next time it opens starts with its own zone name showing.
        driver:SetScript("OnHide", function()
            hovered = false
            unfadeLabel()
        end)
        hookLabel(map)
    end
    anchor()
    redraw()
    driver:Show()
end

function module:OnEnable()
    ns.WorldMap.WhenLoaded(attach)
    -- What the colors are measured against.
    self:On("PLAYER_LEVEL_UP", redraw)
    self:On("SKILL_LINES_CHANGED", redraw)
    self:On("CHAT_MSG_SKILL", redraw)
    -- Herb and ore names the game hadn't loaded yet came out in English; draw them again.
    if not english then
        self:On("ITEM_DATA_LOAD_RESULT", redraw)
    end
end

function module:OnDisable()
    ns.WorldMap.Cancel(attach)
    hovered = false
    unfadeLabel()
    if driver then
        driver:Hide()
        panel:Hide()
    end
end

function module:OnOptionChanged()
    if panel then
        anchor()
        redraw()
    end
end
