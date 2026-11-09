-- Compass Bar: a compass across the top of the screen that turns as the player turns, with its
-- letters and dots, and the things they're heading for on it at the direction they are: the quest
-- selected on the map, the map pin, the corpse while a ghost, and, as the player picks, every quest
-- on the map, group members, flight masters, remembered gathering nodes, and rares. It reads only
-- the player's facing and positions the game gives addons (Lib/WorldMap), never an enemy's or an
-- NPC's, which it doesn't give. It's placed and sized in Edit Mode, and click-through: the markers
-- take the mouse for their tooltips only.
local _, ns = ...

local ipairs, format, floor, abs, min, max, deg, rad, pi, wipe, sort =
    ipairs, string.format, math.floor, math.abs, math.min, math.max, math.deg, math.rad, math.pi,
    wipe, table.sort
local _G, CreateFrame, UIParent, GetTime, GetPlayerFacing = _G, CreateFrame, UIParent, GetTime, GetPlayerFacing
local UnitIsGhost, UnitOnTaxi, InCombatLockdown = UnitIsGhost, UnitOnTaxi, InCombatLockdown
local C_Map, C_QuestLog = C_Map, C_QuestLog

local L = ns.L
local WorldMap, Text, MapTooltip = ns.WorldMap, ns.Text, ns.MapTooltip
local readable = ns.IsReadable

local module = ns.NewModule("CompassBar", L.COMPASSBAR_DESC, {
    enabled = false,
    x = 0, -- the bar's offset from the center of the screen (Edit Mode)
    y = 366, -- along the top
    scale = 100, -- percent
    width = 600, -- pixels
    height = 24,
    fov = 180, -- degrees across the bar
    letters = "all",
    ticks = "dots",
    numbers = false,
    heading = false,
    background = "shade",
    fadeEdges = true,
    quests = "selected",
    pin = true,
    corpse = true,
    group = false,
    flights = false,
    gathering = false,
    rares = false,
    markerSize = 16, -- pixels
    maxDistance = 500, -- yards
    distanceText = "selected",
    names = false,
    distanceFade = true,
    edgeArrows = true,
    hideCombat = false,
    hideTaxi = true,
})
module.title = L.COMPASSBAR_TITLE
module.category = "map"
module.added = "1.5.0"
module.quickToggle = "world"

local PIXELS = L.ICONMARK_PIXELS

module.options = {
    { key = "width", name = L.COMPASSBAR_WIDTH, description = L.COMPASSBAR_WIDTH_DESC, editMode = true,
        min = 300, max = 1200, step = 20, format = PIXELS },
    { key = "height", name = L.COMPASSBAR_HEIGHT, description = L.COMPASSBAR_HEIGHT_DESC,
        editMode = true, min = 16, max = 48, step = 2, format = PIXELS },
    { key = "fov", name = L.COMPASSBAR_FOV, description = L.COMPASSBAR_FOV_DESC, section = L.COMPASSBAR_SECTION_BAR,
        min = 90, max = 360, step = 15, format = L.COMPASSBAR_DEGREES },
    { key = "letters", name = L.COMPASSBAR_LETTERS, description = L.COMPASSBAR_LETTERS_DESC,
        section = L.COMPASSBAR_SECTION_BAR, choices = {
            { "all", L.COMPASSBAR_LETTERS_ALL },
            { "cardinal", L.COMPASSBAR_LETTERS_CARDINAL },
            { "off", L.COMPASSBAR_OFF },
        } },
    { key = "ticks", name = L.COMPASSBAR_TICKS, description = L.COMPASSBAR_TICKS_DESC,
        section = L.COMPASSBAR_SECTION_BAR, choices = {
            { "dots", L.COMPASSBAR_TICKS_DOTS },
            { "lines", L.COMPASSBAR_TICKS_LINES },
            { "off", L.COMPASSBAR_OFF },
        } },
    { key = "numbers", name = L.COMPASSBAR_NUMBERS, description = L.COMPASSBAR_NUMBERS_DESC,
        section = L.COMPASSBAR_SECTION_BAR },
    { key = "heading", name = L.COMPASSBAR_HEADING, description = L.COMPASSBAR_HEADING_DESC,
        section = L.COMPASSBAR_SECTION_BAR },
    { key = "background", name = L.COMPASSBAR_BACKGROUND, description = L.COMPASSBAR_BACKGROUND_DESC,
        section = L.COMPASSBAR_SECTION_BAR, choices = {
            { "shade", L.COMPASSBAR_BACKGROUND_SHADE },
            { "frame", L.COMPASSBAR_BACKGROUND_FRAME },
            { "none", L.COMPASSBAR_BACKGROUND_NONE },
        } },
    { key = "fadeEdges", name = L.COMPASSBAR_FADE_EDGES, description = L.COMPASSBAR_FADE_EDGES_DESC,
        section = L.COMPASSBAR_SECTION_BAR },
    { key = "quests", name = L.COMPASSBAR_QUESTS, description = L.COMPASSBAR_QUESTS_DESC,
        section = L.COMPASSBAR_SECTION_MARKERS, choices = {
            { "selected", L.COMPASSBAR_QUESTS_SELECTED },
            { "all", L.COMPASSBAR_QUESTS_ALL },
            { "off", L.COMPASSBAR_OFF },
        } },
    { key = "pin", name = L.COMPASSBAR_PIN, description = L.COMPASSBAR_PIN_DESC,
        section = L.COMPASSBAR_SECTION_MARKERS },
    { key = "corpse", name = L.COMPASSBAR_CORPSE, description = L.COMPASSBAR_CORPSE_DESC,
        section = L.COMPASSBAR_SECTION_MARKERS },
    { key = "group", name = L.COMPASSBAR_GROUP, description = L.COMPASSBAR_GROUP_DESC,
        section = L.COMPASSBAR_SECTION_MARKERS },
    { key = "flights", name = L.COMPASSBAR_FLIGHTS, description = L.COMPASSBAR_FLIGHTS_DESC,
        section = L.COMPASSBAR_SECTION_MARKERS },
    { key = "gathering", name = L.COMPASSBAR_GATHERING, description = L.COMPASSBAR_GATHERING_DESC,
        section = L.COMPASSBAR_SECTION_MARKERS,
        available = function() return ns.Providers.Get("gatheringNodes") ~= nil end },
    { key = "rares", name = L.COMPASSBAR_RARES, description = L.COMPASSBAR_RARES_DESC,
        section = L.COMPASSBAR_SECTION_MARKERS,
        available = function() return C_VignetteInfo ~= nil and C_VignetteInfo.GetVignettes ~= nil end },
    { key = "markerSize", name = L.COMPASSBAR_MARKER_SIZE, description = L.COMPASSBAR_MARKER_SIZE_DESC,
        section = L.COMPASSBAR_SECTION_MARKERS, min = 12, max = 24, step = 2, format = PIXELS },
    { key = "maxDistance", name = L.COMPASSBAR_MAX_DISTANCE, description = L.COMPASSBAR_MAX_DISTANCE_DESC,
        section = L.COMPASSBAR_SECTION_DISTANCE, min = 100, max = 2000, step = 50,
        format = L.COMPASSBAR_YARDS },
    { key = "distanceText", name = L.COMPASSBAR_DISTANCE_TEXT, description = L.COMPASSBAR_DISTANCE_TEXT_DESC,
        section = L.COMPASSBAR_SECTION_DISTANCE, choices = {
            { "selected", L.COMPASSBAR_DISTANCE_SELECTED },
            { "all", L.COMPASSBAR_DISTANCE_ALL },
            { "off", L.COMPASSBAR_OFF },
        } },
    { key = "names", name = L.COMPASSBAR_NAMES, description = L.COMPASSBAR_NAMES_DESC,
        section = L.COMPASSBAR_SECTION_DISTANCE },
    { key = "distanceFade", name = L.COMPASSBAR_DISTANCE_FADE, description = L.COMPASSBAR_DISTANCE_FADE_DESC,
        section = L.COMPASSBAR_SECTION_DISTANCE },
    { key = "edgeArrows", name = L.COMPASSBAR_EDGE_ARROWS, description = L.COMPASSBAR_EDGE_ARROWS_DESC,
        section = L.COMPASSBAR_SECTION_DISTANCE },
    { key = "hideCombat", name = L.COMPASSBAR_HIDE_COMBAT, description = L.COMPASSBAR_HIDE_COMBAT_DESC,
        section = L.COMPASSBAR_SECTION_SHOW },
    { key = "hideTaxi", name = L.COMPASSBAR_HIDE_TAXI, description = L.COMPASSBAR_HIDE_TAXI_DESC,
        section = L.COMPASSBAR_SECTION_SHOW },
}

module.notice = {
    text = L.COMPASSBAR_NOTICE,
    description = L.COMPASSBAR_NOTICE_DESC,
}

local INTERVAL = 0.03 -- seconds between redraws, smooth enough to follow the camera
local LOOK_INTERVAL = 1 -- seconds between looking up where things are
local STEP = 5 -- degrees between the bar's marks
local EDGE_FADE = 0.14 -- the share of the bar at each end that fades out, with Fade Edges
local MOST = 60 -- markers at most, the nearest
local NEAR = 1.5 -- things within this many times Max Distance are kept between lookups

-- Art -----------------------------------------------------------------------------------------------
-- Blizzard's own, probed: an atlas where the client has it, else older art of the same thing.

local function art(atlases, texture)
    for _, atlas in ipairs(atlases) do
        if ns.Frames.HasAtlas(atlas) then
            return { atlas = atlas }
        end
    end
    return { texture = texture }
end

local ART -- made at first use, once the atlases can be asked about
local function artOf(kind)
    if not ART then
        ART = {
            quest = art({ "QuestNormal" }, "Interface\\GossipFrame\\AvailableQuestIcon"),
            turnin = art({ "QuestTurnin" }, "Interface\\GossipFrame\\ActiveQuestIcon"),
            pin = art({ "Waypoint-MapPin-Tracked", "Waypoint-MapPin-Untracked" },
                "Interface\\Minimap\\MiniMap-QuestArrow"),
            corpse = art({ "poi-graveyard-neutral" }, "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01"),
            flight = art({ "TaxiNode_Neutral", "FlightMaster" }, "Interface\\TaxiFrame\\UI-Taxi-Icon-Green"),
            rare = art({ "VignetteKill" }, "Interface\\Icons\\INV_Misc_Head_Dragon_01"),
            dot = { texture = "Interface\\Buttons\\WHITE8X8", round = true },
            arrow = art({ "Navigation-Tracked-Arrow" }, "Interface\\Minimap\\MiniMap-QuestArrow"),
        }
    end
    return ART[kind]
end

-- A node without a known item icon is a circle in its kind's color, as on Gathering Map.
local NODE_COLORS = {
    herb = { 0.35, 0.85, 0.35 },
    ore = { 0.95, 0.6, 0.25 },
    treasure = { 1, 0.82, 0 },
    fish = { 0.35, 0.65, 1 },
}

local LETTERS = {
    [0] = L.COMPASSBAR_N, [45] = L.COMPASSBAR_NE, [90] = L.COMPASSBAR_E, [135] = L.COMPASSBAR_SE,
    [180] = L.COMPASSBAR_S, [225] = L.COMPASSBAR_SW, [270] = L.COMPASSBAR_W, [315] = L.COMPASSBAR_NW,
}

-- An angle in degrees as the nearest of -180 to 180.
local function wrap(a)
    return (a + 180) % 360 - 180
end

-- The bar ------------------------------------------------------------------------------------------

local bar, strip, layer, notch, headingText, watcher
local backdrop = {} -- the Shade's three parts, and the Frame's box
local marks = {} -- { angle, region } for each letter, number, dot, or line on the bar
local fontStrings, textures = {}, {} -- made for marks, kept for the next build

local function newBar()
    bar = CreateFrame("Frame", nil, UIParent)
    bar:SetFrameStrata("LOW")
    -- The marks, cut off at the bar's ends.
    strip = CreateFrame("Frame", nil, bar)
    strip:SetAllPoints()
    if strip.SetClipsChildren then
        strip:SetClipsChildren(true)
    end
    -- The markers, above the marks and free to reach past the bar (edge arrows, distances).
    layer = CreateFrame("Frame", nil, bar)
    layer:SetAllPoints()
    layer:SetFrameLevel(strip:GetFrameLevel() + 2)
    notch = layer:CreateTexture(nil, "OVERLAY")
    notch:SetColorTexture(NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, 0.85)
    notch:SetPoint("TOP", bar, "TOP")
    notch:SetWidth(2)
    headingText = layer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    headingText:SetPoint("TOP", bar, "BOTTOM", 0, -3)
    bar:Hide()
end

-- The background: Shade is a dark band that fades out at both ends, Frame the box Blizzard draws
-- tooltips in.
local function paintBackground()
    local kind = module.db.background
    if kind == "shade" and not backdrop.middle then
        local alpha = 0.55
        local function part()
            local t = bar:CreateTexture(nil, "BACKGROUND")
            t:SetColorTexture(0, 0, 0, alpha)
            return t
        end
        backdrop.left, backdrop.middle, backdrop.right = part(), part(), part()
        if CreateColor and backdrop.left.SetGradient then
            backdrop.left:SetColorTexture(1, 1, 1, 1)
            backdrop.right:SetColorTexture(1, 1, 1, 1)
            backdrop.left:SetGradient("HORIZONTAL", CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, alpha))
            backdrop.right:SetGradient("HORIZONTAL", CreateColor(0, 0, 0, alpha), CreateColor(0, 0, 0, 0))
        end
    elseif kind == "frame" and not backdrop.box then
        backdrop.box = ns.Frames.TooltipBox(bar)
        backdrop.box:SetPoint("TOPLEFT", -3, 3)
        backdrop.box:SetPoint("BOTTOMRIGHT", 3, -3)
        backdrop.box:SetFrameLevel(max(0, strip:GetFrameLevel() - 1))
    end
    if backdrop.middle then
        local edge = floor(bar:GetWidth() * 0.18)
        backdrop.left:ClearAllPoints()
        backdrop.left:SetPoint("TOPLEFT")
        backdrop.left:SetPoint("BOTTOMLEFT")
        backdrop.left:SetWidth(edge)
        backdrop.right:ClearAllPoints()
        backdrop.right:SetPoint("TOPRIGHT")
        backdrop.right:SetPoint("BOTTOMRIGHT")
        backdrop.right:SetWidth(edge)
        backdrop.middle:ClearAllPoints()
        backdrop.middle:SetPoint("TOPLEFT", backdrop.left, "TOPRIGHT")
        backdrop.middle:SetPoint("BOTTOMRIGHT", backdrop.right, "BOTTOMLEFT")
        for _, key in ipairs({ "left", "middle", "right" }) do
            backdrop[key]:SetShown(kind == "shade")
        end
    end
    if backdrop.box then
        backdrop.box:SetShown(kind == "frame")
    end
end

local function fontOf(template)
    local font = _G[template]
    local path = font and font:GetFont()
    return path or STANDARD_TEXT_FONT
end

-- Lays out the marks for the bar's settings: a letter at each of the eight directions (or the
-- four), the degrees between them with Degree Numbers, and a dot or line every STEP degrees.
local function build()
    local db = module.db
    for _, mark in ipairs(marks) do
        mark.region:Hide()
    end
    wipe(marks)
    local usedFonts, usedTextures = 0, 0
    local function fontString(template, size)
        usedFonts = usedFonts + 1
        local text = fontStrings[usedFonts]
        if not text then
            text = strip:CreateFontString(nil, "ARTWORK")
            fontStrings[usedFonts] = text
        end
        text:SetFont(fontOf(template), size, "OUTLINE")
        return text
    end
    local function texture()
        usedTextures = usedTextures + 1
        local t = textures[usedTextures]
        if not t then
            t = strip:CreateTexture(nil, "ARTWORK")
            textures[usedTextures] = t
        end
        return t
    end
    local height = db.height
    for angle = 0, 360 - STEP, STEP do
        local cardinal, between = angle % 90 == 0, angle % 45 == 0 and angle % 90 ~= 0
        local region
        if (cardinal and db.letters ~= "off") or (between and db.letters == "all") then
            region = fontString("GameFontNormal", floor(height * (cardinal and 0.62 or 0.46)))
            region:SetText(LETTERS[angle])
            local color = angle == 0 and RED_FONT_COLOR or cardinal and NORMAL_FONT_COLOR
                or HIGHLIGHT_FONT_COLOR
            region:SetTextColor(color.r, color.g, color.b)
        elseif db.numbers and angle % 15 == 0 then
            region = fontString("GameFontHighlight", max(8, floor(height * 0.36)))
            region:SetText(angle)
            region:SetTextColor(0.8, 0.76, 0.68)
        elseif db.ticks == "dots" and angle % 15 == 0 then
            region = texture()
            local size = angle % 45 == 0 and 4 or 3
            region:SetColorTexture(0.85, 0.81, 0.7, 0.9)
            region:SetSize(size, size)
        elseif db.ticks == "lines" then
            region = texture()
            region:SetColorTexture(0.85, 0.81, 0.7, 0.9)
            region:SetSize(1, floor(height * (angle % 15 == 0 and 0.42 or 0.22)))
        end
        if region then
            marks[#marks + 1] = { angle = angle, region = region }
        end
    end
    -- The middle: down the whole bar among lines, else a short tick from the top, clear of the
    -- letter under it.
    notch:SetHeight(db.ticks == "lines" and height or max(4, floor(height * 0.3)))
    paintBackground()
end

-- Where things are -----------------------------------------------------------------------------------
-- Each thing on the bar is a target: { kind, title, note, art, point (followed across maps) or x, y
-- (on the player's zone map), unit (a group member, read each redraw), important }. The important
-- ones are what the player is heading for: the selected quest, the map pin, the corpse. They show
-- at any distance and wait at the bar's edge while behind.

local targets = {} -- looked up each LOOK_INTERVAL
local lookedAt, dirty = 0, true
local cachedPin, cachedQuest, cachedQuestPoint, cachedCorpse -- kept, so their routes are reused
local zoneMap, zoneWidth, zoneHeight -- the player's zone map, for everything but the important

-- A target on the zone map near enough to keep between lookups, from where the player is now.
local function near(x, y, px, py)
    if not (px and zoneWidth) then
        return false
    end
    local yards = WorldMap.Toward(zoneWidth, zoneHeight, px, py, x, y)
    return yards <= module.db.maxDistance * NEAR
end

local function selectedQuest()
    if not (C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID) then
        return nil
    end
    local questID = C_SuperTrack.GetSuperTrackedQuestID()
    if readable(questID) and questID and questID ~= 0 then
        return questID
    end
end

local function questTitle(questID)
    local title = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID)
    return readable(title) and title or nil
end

local function questComplete(questID)
    return C_QuestLog.IsComplete and C_QuestLog.IsComplete(questID) and true or false
end

-- The first objective not done yet, for a quest's tooltip.
local function questNote(questID)
    if questComplete(questID) then
        return L.COMPASSBAR_READY
    end
    for _, objective in ipairs(C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(questID) or {}) do
        if objective.text and not objective.finished and readable(objective.text) then
            return objective.text
        end
    end
end

local function addQuests(px, py, selected)
    local db = module.db
    if db.quests == "off" then
        return
    end
    if selected then
        local point = WorldMap.QuestPoint(selected)
        -- The same spot keeps the old point, so its route isn't worked out again.
        if not (point and cachedQuestPoint and cachedQuest == selected
            and point.uiMapID == cachedQuestPoint.uiMapID
            and point.position.x == cachedQuestPoint.position.x
            and point.position.y == cachedQuestPoint.position.y) then
            cachedQuestPoint = point
        end
        cachedQuest = selected
        if cachedQuestPoint then
            targets[#targets + 1] = { kind = L.COMPASSBAR_KIND_SELECTED, title = questTitle(selected),
                questID = selected, art = artOf(questComplete(selected) and "turnin" or "quest"),
                point = cachedQuestPoint, important = true }
        end
    end
    if db.quests ~= "all" or not (zoneMap and C_QuestLog.GetQuestsOnMap) then
        return
    end
    for _, quest in ipairs(C_QuestLog.GetQuestsOnMap(zoneMap) or {}) do
        local questID, x, y = quest.questID, quest.x, quest.y
        if questID ~= selected and readable(x) and readable(y) and x and y and near(x, y, px, py) then
            local done = questComplete(questID)
            targets[#targets + 1] = { kind = done and L.COMPASSBAR_KIND_TURNIN or L.COMPASSBAR_KIND_QUEST,
                title = questTitle(questID), questID = questID, art = artOf(done and "turnin" or "quest"),
                x = x, y = y }
        end
    end
end

local function addPin()
    if not module.db.pin then
        return
    end
    local pin = C_Map.GetUserWaypoint and C_Map.GetUserWaypoint()
    if not pin then
        cachedPin = nil
        return
    end
    if not (cachedPin and cachedPin.uiMapID == pin.uiMapID and pin.position and cachedPin.position
        and cachedPin.position.x == pin.position.x and cachedPin.position.y == pin.position.y) then
        cachedPin = pin
    end
    targets[#targets + 1] = { kind = L.COMPASSBAR_KIND_PIN, title = L.COMPASSBAR_PIN_TITLE,
        art = artOf("pin"), point = cachedPin, important = true }
end

local function addCorpse()
    if not (module.db.corpse and UnitIsGhost("player")) then
        cachedCorpse = nil
        return
    end
    local point = WorldMap.CorpsePoint()
    if point and cachedCorpse and cachedCorpse.uiMapID == point.uiMapID
        and cachedCorpse.position.x == point.position.x and cachedCorpse.position.y == point.position.y then
        point = cachedCorpse
    end
    cachedCorpse = point
    if point then
        targets[#targets + 1] = { kind = L.COMPASSBAR_KIND_CORPSE, title = L.COMPASSBAR_CORPSE_TITLE,
            art = artOf("corpse"), point = point, important = true }
    end
end

-- Group members: their spots are read each redraw, since they move. The game gives them only
-- outside instances, and may hide them; a spot it hides is skipped.
local function addGroup()
    if not (module.db.group and IsInGroup and IsInGroup()) then
        return
    end
    local raid = IsInRaid and IsInRaid()
    local count = raid and GetNumGroupMembers() or GetNumSubgroupMembers()
    for i = 1, count do
        local unit = (raid and "raid" or "party") .. i
        if not UnitIsUnit(unit, "player") then
            local name = UnitName(unit)
            local color = ns.Colors.Class(unit)
            targets[#targets + 1] = { kind = L.COMPASSBAR_KIND_GROUP, title = readable(name) and name or nil,
                unit = unit, art = { texture = artOf("dot").texture, round = true,
                    color = color and { color.r, color.g, color.b } or { 1, 1, 1 } } }
        end
    end
end

-- The game's flight points on the zone map, the player's side's and neutral ones.
local function addFlights(px, py)
    if not (module.db.flights and zoneMap and C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap) then
        return
    end
    local side = WorldMap.PlayerSide()
    local factions = Enum and Enum.FlightPathFaction
    for _, node in ipairs(C_TaxiMap.GetTaxiNodesForMap(zoneMap) or {}) do
        local position = node.position
        local x, y = position and position.x, position and position.y
        local other = factions and ((side == "A" and node.faction == factions.Horde)
            or (side == "H" and node.faction == factions.Alliance))
        if not other and readable(x) and readable(y) and x and y and near(x, y, px, py) then
            local look = artOf("flight")
            if node.atlasName and readable(node.atlasName) and ns.Frames.HasAtlas(node.atlasName) then
                look = { atlas = node.atlasName }
            end
            targets[#targets + 1] = { kind = L.COMPASSBAR_KIND_FLIGHT, title = node.name, art = look,
                x = x, y = y }
        end
    end
end

-- Gathering Map's remembered nodes on the zone map, as it shows them on the minimap.
local function addGathering(px, py)
    local nodes = module.db.gathering and ns.Providers.Get("gatheringNodes")
    if not (nodes and zoneMap) then
        return
    end
    for _, node in ipairs(nodes.Maps()[zoneMap] or {}) do
        if node.x and node.y and near(node.x, node.y, px, py) and nodes.Shown(node) then
            local icon = nodes.Icon(node)
            local look = icon and { texture = icon, trim = true, round = true }
                or { texture = artOf("dot").texture, round = true, color = NODE_COLORS[node.kind] or NODE_COLORS.herb }
            targets[#targets + 1] = { kind = L.COMPASSBAR_KIND_NODE, title = node.name, art = look,
                x = node.x, y = node.y }
        end
    end
end

-- Rares and treasures the game marks (vignettes), where it gives them a spot.
local function addRares(px, py)
    if not (module.db.rares and zoneMap and C_VignetteInfo and C_VignetteInfo.GetVignettes) then
        return
    end
    for _, guid in ipairs(C_VignetteInfo.GetVignettes() or {}) do
        local info = C_VignetteInfo.GetVignetteInfo(guid)
        local position = info and C_VignetteInfo.GetVignettePosition(guid, zoneMap)
        local x, y = position and position.x, position and position.y
        if readable(x) and readable(y) and x and y and near(x, y, px, py) then
            local atlas = info.atlasName
            local look = atlas and readable(atlas) and ns.Frames.HasAtlas(atlas) and { atlas = atlas } or artOf("rare")
            targets[#targets + 1] = { kind = L.COMPASSBAR_KIND_RARE,
                title = readable(info.name) and info.name or nil, art = look, x = x, y = y }
        end
    end
end

local function lookUp()
    wipe(targets)
    lookedAt, dirty = GetTime(), false
    local mapID, px, py = WorldMap.PlayerZonePosition()
    zoneMap = mapID
    zoneWidth, zoneHeight = nil, nil
    if zoneMap then
        zoneWidth, zoneHeight = WorldMap.Size(zoneMap)
    end
    addCorpse()
    addQuests(px, py, selectedQuest())
    addPin()
    addGroup()
    addFlights(px, py)
    addGathering(px, py)
    addRares(px, py)
end

-- Markers ----------------------------------------------------------------------------------------------

local markers = {} -- frames, one per target shown
local used = 0

local function onEnter(self)
    local target = self.target
    if not target then
        return
    end
    local lines = {}
    if self.yards then
        lines[#lines + 1] = MapTooltip.Pair(L.COMPASSBAR_DISTANCE, Text.Yards(self.yards))
    end
    local note = target.questID and questNote(target.questID)
    if note then
        lines[#lines + 1] = MapTooltip.Note(note)
    end
    MapTooltip.Show(self, target.title or target.kind, lines, target.title and target.kind or nil)
end

local function onLeave()
    GameTooltip:Hide()
end

local function newMarker()
    local marker = CreateFrame("Frame", nil, layer)
    marker.texture = marker:CreateTexture(nil, "ARTWORK")
    marker.texture:SetAllPoints()
    marker.name = marker:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    marker.distance = marker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    marker.arrow = marker:CreateTexture(nil, "OVERLAY")
    marker.arrow:SetSize(10, 10)
    marker.arrow:Hide()
    -- Hover for the tooltip; clicks go through to the world.
    marker:EnableMouse(true)
    if marker.SetMouseClickEnabled then
        marker:SetMouseClickEnabled(false)
    end
    marker:SetScript("OnEnter", onEnter)
    marker:SetScript("OnLeave", onLeave)
    return marker
end

local function marker()
    used = used + 1
    local m = markers[used]
    if not m then
        m = newMarker()
        markers[used] = m
    end
    return m
end

-- Puts a marker on the bar for a target `delta` degrees from straight ahead and `yards` away.
-- `edge` is -1 or 1 for one waiting at that end of the bar.
local function placeMarker(target, delta, yards, edge, alpha)
    local db = module.db
    local width = db.width
    local m = marker()
    if m.target ~= target or m.art ~= target.art then
        m.target, m.art = target, target.art
        ns.MapPins.SetArt(m, target.art)
        m.shownYards, m.shownName = nil, nil
    end
    m.yards = yards
    local size = floor(db.markerSize * (target.important and 1.15 or 1))
    m:SetSize(size, size)
    m:SetFrameLevel(layer:GetFrameLevel() + (target.important and 10 or 1))
    local x = edge ~= 0 and (edge < 0 and 6 or width - 6) or (width / 2 + delta * width / db.fov)
    m:ClearAllPoints()
    m:SetPoint("CENTER", layer, "LEFT", x, 0)
    m:SetAlpha(alpha)
    -- The arrow beside one waiting at the edge, pointing the way to turn.
    if edge ~= 0 then
        local arrow = artOf("arrow")
        if arrow.atlas then
            m.arrow:SetAtlas(arrow.atlas)
        else
            m.arrow:SetTexture(arrow.texture)
        end
        m.arrow:SetRotation(edge < 0 and pi / 2 or -pi / 2)
        m.arrow:ClearAllPoints()
        m.arrow:SetPoint(edge < 0 and "RIGHT" or "LEFT", m, edge < 0 and "LEFT" or "RIGHT", 0, 0)
        m.arrow:Show()
    else
        m.arrow:Hide()
    end
    -- The name and distance under it.
    local name = db.names and target.important and target.title or nil
    local wantDistance = yards and (db.distanceText == "all" or (db.distanceText == "selected" and target.important))
    if name ~= m.shownName then
        m.shownName = name
        m.name:SetText(name or "")
    end
    local rounded = wantDistance and floor(yards + 0.5) or nil
    if rounded ~= m.shownYards then
        m.shownYards = rounded
        m.distance:SetText(rounded and Text.Yards(yards) or "")
    end
    local top = -(db.height - size) / 2 - 2
    m.name:ClearAllPoints()
    m.name:SetPoint("TOP", m, "BOTTOM", 0, top)
    m.distance:ClearAllPoints()
    if name then
        m.distance:SetPoint("TOP", m.name, "BOTTOM", 0, -1)
    else
        m.distance:SetPoint("TOP", m, "BOTTOM", 0, top)
    end
    m:Show()
    -- Whether it sits under the notch, where the heading would cover its text.
    return (name or rounded) and abs(x - width / 2) < 40
end

-- Drawing -----------------------------------------------------------------------------------------------

local SAMPLES -- Edit Mode's example markers, made at first use

local function hidden()
    local db = module.db
    return (db.hideCombat and InCombatLockdown()) or (db.hideTaxi and UnitOnTaxi("player"))
end

-- Where a target is from the player now: yards and its angle, or nil.
local function locate(target, px, py)
    if target.point then
        return WorldMap.FromPlayer(target.point)
    elseif target.unit then
        if not zoneMap then
            return nil
        end
        local position = C_Map.GetPlayerMapPosition(zoneMap, target.unit)
        local x, y = position and position.x, position and position.y
        if not (readable(x) and readable(y) and x and y and px and zoneWidth) or (x == 0 and y == 0) then
            return nil
        end
        return WorldMap.Toward(zoneWidth, zoneHeight, px, py, x, y)
    elseif px and zoneWidth then
        return WorldMap.Toward(zoneWidth, zoneHeight, px, py, target.x, target.y)
    end
end

local shownList = {} -- { target, delta, yards, edge } this redraw, before sorting
local function byWeight(a, b)
    if a.target.important ~= b.target.important then
        return b.target.important and true or false -- important ones last, on top
    end
    return (a.yards or 0) > (b.yards or 0) -- nearer ones later, on top
end

local function draw(heading, facing, sample)
    local db = module.db
    local width, half = db.width, db.fov / 2
    local fade = db.fadeEdges and width * EDGE_FADE or nil
    for _, mark in ipairs(marks) do
        local delta = wrap(mark.angle - heading)
        local region = mark.region
        if abs(delta) > half then
            region:Hide()
        else
            local x = width / 2 + delta * width / db.fov
            region:ClearAllPoints()
            region:SetPoint("CENTER", strip, "LEFT", x, 0)
            region:SetAlpha(fade and min(1, min(x, width - x) / fade) or 1)
            region:Show()
        end
    end
    -- The markers.
    used = 0
    wipe(shownList)
    local list = targets
    local _, px, py
    if sample then
        list = SAMPLES
    else
        _, px, py = WorldMap.PlayerZonePosition()
    end
    for _, target in ipairs(list) do
        local yards, angle
        if sample then
            yards, angle = target.yards, target.angle
        else
            yards, angle = locate(target, px, py)
        end
        if yards and (target.important or yards <= db.maxDistance) then
            local delta = wrap(deg(facing - angle))
            local edge = 0
            if abs(delta) > half then
                edge = (db.edgeArrows and target.important) and (delta < 0 and -1 or 1) or nil
            end
            if edge then
                shownList[#shownList + 1] = { target = target, delta = delta, yards = yards, edge = edge }
            end
        end
    end
    sort(shownList, byWeight)
    local under = false
    for i = max(1, #shownList - MOST + 1), #shownList do
        local each = shownList[i]
        local alpha = 1
        if each.edge ~= 0 then
            alpha = 0.85
        elseif db.distanceFade and not each.target.important then
            alpha = max(0.45, 1 - 0.55 * each.yards / db.maxDistance)
        end
        if placeMarker(each.target, each.delta, each.yards, each.edge, alpha) then
            under = true
        end
    end
    for i = used + 1, #markers do
        markers[i]:Hide()
        markers[i].target = nil
    end
    -- The heading under the notch, below a marker's text there.
    if db.heading then
        local direction = LETTERS[(floor((heading + 22.5) / 45) % 8) * 45]
        headingText:SetText(format(L.COMPASSBAR_HEADING_TEXT, direction, floor(heading + 0.5) % 360))
        headingText:ClearAllPoints()
        headingText:SetPoint("TOP", bar, "BOTTOM", 0, under and -30 or -3)
        headingText:Show()
    else
        headingText:Hide()
    end
end

local function update()
    if ns.EditMode.IsActive() then
        return -- the sample stays put while it's being placed
    end
    local facing = GetPlayerFacing and GetPlayerFacing()
    if not (facing and readable(facing)) or hidden() then
        bar:Hide()
        return
    end
    if dirty or GetTime() - lookedAt >= LOOK_INTERVAL then
        lookUp()
    end
    -- Facing is counter-clockwise from north in radians; the bar reads clockwise in degrees.
    draw((360 - deg(facing)) % 360, facing, false)
    bar:Show()
end

local function changed()
    dirty = true
end

-- Edit Mode ---------------------------------------------------------------------------------------------

local function place()
    local db = module.db
    bar:SetScale(db.scale / 100)
    bar:SetSize(db.width, db.height)
    ns.EditMode.Place(bar, db.x, db.y)
    build()
end

-- In Edit Mode the bar shows facing north with two example markers, so it can be placed.
local function sample(active)
    if active then
        if not SAMPLES then
            SAMPLES = {
                { kind = L.COMPASSBAR_KIND_SELECTED, title = L.COMPASSBAR_SAMPLE_QUEST, art = artOf("quest"),
                    important = true, yards = 312, angle = 2 * pi - rad(35) }, -- 35 to the right
                { kind = L.COMPASSBAR_KIND_PIN, title = L.COMPASSBAR_PIN_TITLE, art = artOf("pin"),
                    important = true, yards = 520, angle = rad(60) }, -- 60 to the left
            }
        end
        draw(0, 0, true)
        bar:Show()
    else
        bar:Hide()
        dirty = true
        update()
    end
end

-- Turning on and off ------------------------------------------------------------------------------------

function module:OnEnable()
    if not bar then
        newBar()
        watcher = ns.Frames.Watcher(module, INTERVAL, update)
    end
    place()
    ns.EditMode.RegisterModule(module, bar, L.COMPASSBAR_TITLE, place, sample)
    -- What changes the important targets at once; the rest is looked up each LOOK_INTERVAL.
    for _, event in ipairs({ "USER_WAYPOINT_UPDATED", "SUPER_TRACKING_CHANGED", "PLAYER_ENTERING_WORLD",
        "ZONE_CHANGED_NEW_AREA", "PLAYER_ALIVE", "PLAYER_UNGHOST", "GROUP_ROSTER_UPDATE" }) do
        self:On(event, changed)
    end
    dirty = true
    watcher:Show()
end

function module:OnDisable()
    watcher:Hide()
    ns.EditMode.Unregister(bar)
    bar:Hide()
    wipe(targets)
    cachedPin, cachedQuest, cachedQuestPoint, cachedCorpse = nil, nil, nil, nil
end

function module:OnOptionChanged(key)
    if key == "width" or key == "height" or key == "letters" or key == "ticks" or key == "numbers"
        or key == "background" then
        place()
    end
    dirty = true
    if ns.EditMode.IsActive() then
        sample(true)
    end
end
