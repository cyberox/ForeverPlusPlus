-- Gathering Map: every herb and vein the player gathers is remembered where they stood, for the
-- whole account, and shown on the world map and the minimap. Gathering the same node again counts
-- it and moves its spot toward the average of where the player stood (Lib/Gathering.lua). Ideas
-- from GatherMate2 and GatherLite; none of their code or data.
--
-- This file holds the module, its options, and remembering gathers. Map.lua draws the nodes on
-- the world map and Minimap.lua on the minimap. They share module.internal.
local _, ns = ...

local pairs, type, time, format, tostring = pairs, type, time, string.format, tostring
local C_Minimap, C_Map = C_Minimap, C_Map

local L = ns.L
local Gathering = ns.Gathering

local module = ns.NewModule("GatheringMap", L.GATHERINGMAP_DESC, {
    enabled = true,
    onlyMine = true, -- only nodes this character has the profession for
    onlyTracking = true, -- herbs only while Find Herbs is on, ore while Find Minerals is
    sightings = true, -- also remember the nodes Minimap Node Icons sees, not gathered
    justGathered = "fade", -- a node gathered lately: "fade" (a faint circle), "hide", or "show"
    justMinutes = 10, -- how long "lately" is
    icon = "item", -- "item" (the node's item's icon, a circle without one) or "circle"
    shape = "round", -- an item icon "round" or "square"
    ring = true, -- the minimap's gold ring around a round icon
    worldMap = true,
    mapSize = 100, -- percent of MAP_PIXELS on the world map
    mapAlpha = 100, -- percent
    mapContinents = false, -- on continent maps too
    minimap = true,
    minimapSize = 12, -- pixels
    minimapAlpha = 100, -- percent
    log = false, -- print each gather in chat (Debug)
    -- Nodes remembered, by zone map ID: a list of { name, kind, x, y, count, time, loot }, where
    -- loot is item ID -> how many it gave in all. For the whole account. Data, not a setting.
    nodes = {},
})
module.title = L.GATHERINGMAP_TITLE
module.category = "map"
module.added = "1.2.0"
module.internal = {}
local internal = module.internal

local LOOK, MINIMAP, WORLD = L.GATHERINGMAP_SECTION_LOOK, L.GATHERINGMAP_SECTION_MINIMAP,
    L.GATHERINGMAP_SECTION_WORLDMAP

module.options = {
    { key = "onlyMine", name = L.GATHERINGMAP_ONLY_MINE, description = L.GATHERINGMAP_ONLY_MINE_DESC },
    { key = "onlyTracking", name = L.GATHERINGMAP_ONLY_TRACKING, description = L.GATHERINGMAP_ONLY_TRACKING_DESC },
    { key = "sightings", name = L.GATHERINGMAP_SIGHTINGS, description = L.GATHERINGMAP_SIGHTINGS_DESC },
    {
        key = "justGathered", name = L.GATHERINGMAP_JUST, description = L.GATHERINGMAP_JUST_DESC,
        choices = {
            { "fade", L.GATHERINGMAP_JUST_FADE },
            { "hide", L.GATHERINGMAP_JUST_HIDE },
            { "show", L.GATHERINGMAP_JUST_SHOW },
        },
    },
    {
        key = "justMinutes", name = L.GATHERINGMAP_JUST_MINUTES, description = L.GATHERINGMAP_JUST_MINUTES_DESC,
        min = 1, max = 30, step = 1, format = ns.Text.Minutes,
        shown = function(db)
            return db.justGathered ~= "show"
        end,
    },
    {
        key = "icon", name = L.GATHERINGMAP_ICON, description = L.GATHERINGMAP_ICON_DESC, section = LOOK,
        choices = {
            { "item", L.GATHERINGMAP_ICON_ITEM },
            { "circle", L.GATHERINGMAP_ICON_CIRCLE },
        },
    },
    {
        key = "shape", name = L.GATHERINGMAP_SHAPE, description = L.GATHERINGMAP_SHAPE_DESC, section = LOOK,
        choices = {
            { "round", L.GATHERINGMAP_SHAPE_ROUND },
            { "square", L.GATHERINGMAP_SHAPE_SQUARE },
        },
        shown = function(db)
            return db.icon == "item"
        end,
    },
    { key = "ring", name = L.GATHERINGMAP_RING, description = L.GATHERINGMAP_RING_DESC, section = LOOK },
    {
        key = "minimap", name = L.GATHERINGMAP_MINIMAP, description = L.GATHERINGMAP_MINIMAP_DESC,
        section = MINIMAP, slider = "minimapSize",
    },
    {
        key = "minimapSize", name = L.GATHERINGMAP_SIZE, description = L.GATHERINGMAP_MINIMAP_SIZE_DESC,
        section = MINIMAP, requires = "minimap", min = 8, max = 32, step = 2, format = L.ICONMARK_PIXELS,
    },
    {
        key = "minimapAlpha", name = L.GATHERINGMAP_ALPHA, description = L.GATHERINGMAP_ALPHA_DESC,
        section = MINIMAP, requires = "minimap", min = 10, max = 100, step = 5, format = "%d%%",
    },
    {
        key = "worldMap", name = L.GATHERINGMAP_WORLDMAP, description = L.GATHERINGMAP_WORLDMAP_DESC,
        section = WORLD, slider = "mapSize",
    },
    {
        key = "mapSize", name = L.GATHERINGMAP_SIZE, description = L.GATHERINGMAP_MAP_SIZE_DESC,
        section = WORLD, requires = "worldMap", min = 50, max = 200, step = 10, format = "%d%%",
    },
    {
        key = "mapAlpha", name = L.GATHERINGMAP_ALPHA, description = L.GATHERINGMAP_ALPHA_DESC,
        section = WORLD, requires = "worldMap", min = 10, max = 100, step = 5, format = "%d%%",
    },
    {
        key = "mapContinents", name = L.GATHERINGMAP_CONTINENTS, description = L.GATHERINGMAP_CONTINENTS_DESC,
        section = WORLD, requires = "worldMap",
    },
    {
        key = "log", name = L.GATHERINGMAP_LOG, description = L.GATHERINGMAP_LOG_DESC,
        debug = true, section = L.DEBUG_SECTION_LOGGING,
    },
}

module.actions = {
    {
        name = L.GATHERINGMAP_FORGET_SEEN,
        button = L.GATHERINGMAP_FORGET_SEEN_BUTTON,
        description = L.GATHERINGMAP_FORGET_SEEN_DESC,
        confirm = L.GATHERINGMAP_FORGET_SEEN_CONFIRM,
        fn = function()
            local forgot = 0
            for mapID, list in pairs(module.db.nodes) do
                for i = #list, 1, -1 do
                    if list[i].count == 0 then
                        table.remove(list, i)
                        forgot = forgot + 1
                    end
                end
                if #list == 0 then
                    module.db.nodes[mapID] = nil
                end
            end
            ns.Print(format(L.GATHERINGMAP_FORGET_SEEN_DONE, forgot))
            internal.Changed(nil)
        end,
    },
}

-- What decides which nodes show: the player's professions, and their tracking.
local HERBS = ns.GameData.Spell(2383, "Find Herbs")
local MINERALS = ns.GameData.Spell(2580, "Find Minerals")
local tracking = {} -- kind -> true while its tracking spell is on

local function readTracking()
    tracking = {}
    for i = 1, C_Minimap.GetNumTrackingTypes() do
        local info = C_Minimap.GetTrackingInfo(i)
        if type(info) == "table" and info.active then
            if info.spellID == HERBS then
                tracking.herb = true
            elseif info.spellID == MINERALS then
                tracking.ore = true
            end
        end
    end
end

local function onTracking()
    readTracking()
    internal.Changed(nil)
end

local function onSkills()
    internal.Changed(nil)
end

module:OnWhile("onlyTracking", { MINIMAP_UPDATE_TRACKING = onTracking, PLAYER_ENTERING_WORLD = onTracking })
module:OnWhile("onlyMine", { SKILL_LINES_CHANGED = onSkills })

-- The kinds of node remembered.
local RECORDED = { herb = true, ore = true }

-- Redraws ----------------------------------------------------------------------------------------

local redraws = {} -- fn(mapID) of the other files, after a map's nodes changed (nil for all)

---Has the other files call `fn(mapID)` after a map's nodes change, or with nil after anything
---that changes every map (an option).
---@param fn fun(mapID: number?)
function internal.OnChanged(fn)
    redraws[#redraws + 1] = fn
end

function internal.Changed(mapID)
    for i = 1, #redraws do
        redraws[i](mapID)
    end
end

-- How a node looks ------------------------------------------------------------------------------
-- Its item's icon (Copper Ore for a Copper Vein): the one Lib/Professions knows, else the first
-- the node gave. A node with neither, or every node with Icon Style set to circles, is a circle
-- in its kind's color.

local next = next
local C_Item = C_Item
local Professions = ns.Professions

local COLORS = {
    herb = { 0.35, 0.85, 0.35 },
    ore = { 0.95, 0.6, 0.25 },
    treasure = { 1, 0.82, 0 },
    fish = { 0.35, 0.65, 1 },
}
local CIRCLE = "Interface\\Buttons\\WHITE8X8" -- tinted and drawn round
internal.COLORS = COLORS
internal.KIND_NAMES = {
    herb = L.GATHERINGMAP_KIND_HERB,
    ore = L.GATHERINGMAP_KIND_ORE,
    treasure = L.GATHERINGMAP_KIND_TREASURE,
    fish = L.GATHERINGMAP_KIND_FISH,
}

local icons = {} -- node name -> its item's icon, once found

-- The icon of a node's item, or nil.
local function itemIcon(node)
    local icon = icons[node.name]
    if icon then
        return icon
    end
    local known = Professions.Node(node.name)
    local item = known and known[3]
    if not item and node.loot then
        item = next(node.loot)
    end
    icon = item and C_Item.GetItemIconByID(item)
    if icon and ns.IsReadable(icon) then
        icons[node.name] = icon
        return icon
    end
end

---Whether a node was gathered within the last Just Gathered minutes, so it's likely still gone.
---@param node table
---@return boolean
function internal.JustGathered(node)
    return node.time ~= nil and time() - node.time < module.db.justMinutes * 60
end

-- How much of its opacity a node just gathered keeps, drawn as a faint circle.
internal.FADED = 0.35

---Fills `look` with how a node is drawn, as Lib/MapPins takes it: `texture`, `trim`, `round`,
---`color`, and `ring`, and `faded` for a node just gathered, drawn as a faint circle.
---@param node table
---@param look table
---@return table look
function internal.Look(node, look)
    local db = module.db
    local faded = db.justGathered == "fade" and internal.JustGathered(node)
    local icon = db.icon == "item" and not faded and itemIcon(node)
    look.atlas, look.faded = nil, faded
    if icon then
        look.texture, look.trim, look.color = icon, true, nil
        look.round = db.shape == "round"
    else
        look.texture, look.trim, look.color = CIRCLE, false, COLORS[node.kind] or COLORS.herb
        look.round = true
    end
    look.ring = db.ring and look.round or false
    return look
end

-- Herbs and ore need their gathering skill and tracking spell; anyone can open treasure.
local TRACKED = { herb = true, ore = true }

---Whether a node is shown, on either map: with Only My Professions, only while this character
---has the skill that gathers it, and with Only While Tracking, only while its tracking is on.
---@param node table
---@return boolean
function internal.Shown(node)
    local db = module.db
    local kind = node.kind
    if db.onlyMine and kind ~= "treasure" then
        local line = Professions.KindLine(kind)
        if not (line and Professions.Rank(line)) then
            return false
        end
    end
    if db.onlyTracking and TRACKED[kind] and not tracking[kind] then
        return false
    end
    if db.justGathered == "hide" and internal.JustGathered(node) then
        return false
    end
    return true
end

---The lines under a node's name in its tooltip.
---@param node table
---@return table lines
function internal.TooltipLines(node)
    local lines = { internal.KIND_NAMES[node.kind] or node.kind }
    if node.count == 1 then
        lines[#lines + 1] = ns.MapTooltip.Detail(L.GATHERINGMAP_GATHERED_ONCE)
    elseif node.count > 1 then
        lines[#lines + 1] = ns.MapTooltip.Detail(format(L.GATHERINGMAP_GATHERED, node.count))
    else
        lines[#lines + 1] = ns.MapTooltip.Detail(L.GATHERINGMAP_SEEN)
    end
    if node.time then
        lines[#lines + 1] = ns.MapTooltip.Note(format(L.GATHERINGMAP_LAST, ns.Text.Ago(time() - node.time)))
    end
    return lines
end

-- Remembering gathers ---------------------------------------------------------------------------

local function log(gather, result)
    if not module.db.log then
        return
    end
    local where = gather.mapID
        and format("%s %.1f, %.1f", ns.WorldMap.MapName(gather.mapID, gather.mapID), gather.x * 100,
            gather.y * 100)
        or L.GATHERINGMAP_LOG_NOWHERE
    ns.Print(format(L.GATHERINGMAP_LOG_LINE, gather.name or "?", gather.kind, gather.from,
        gather.objectID or "-", where, result))
end

-- The list of a map's nodes and its size in yards, the list made when `make` is set; nil where
-- the map has no size.
local function mapNodes(mapID, make)
    local width, height = ns.WorldMap.Size(mapID)
    if not width then
        return nil
    end
    local nodes = module.db.nodes
    local list = nodes[mapID]
    if not list and make then
        list = {}
        nodes[mapID] = list
    end
    return list, width, height
end

-- A node Minimap Node Icons saw where it really is, while the player stood still.
local function onSighting(sighting)
    if not (module.db.sightings and RECORDED[sighting.kind]) then
        return
    end
    local list, width, height = mapNodes(sighting.mapID, true)
    if not list then
        return
    end
    local _, new = Gathering.See(list, sighting.name, sighting.kind, sighting.x, sighting.y, width,
        height, time(), sighting.radius)
    if new then
        internal.Changed(sighting.mapID)
    end
end

---The zone map the player is on, for a cave or a district too, or nil.
---@return number? mapID
function internal.ZoneMap()
    local best = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not (ns.IsNumber(best) and best) then
        return nil
    end
    return ns.WorldMap.Zone(best) or best
end

-- A dot the player pointed at on the minimap (Lib/MinimapPins.lua, once a hover, at the middle of
-- where the mouse named it): the herbs and veins it names are there. The only way left to learn
-- a node without gathering it since build 70862 stopped the minimap answering Minimap Node Icons'
-- scans (docs/forever-api.md).
-- How far apart, in minimap units, two hovers of one dot can land: the minimap names a dot from a
-- little way off it, so a hover from one side and one from the other are up to twice that apart
-- (four sightings of one vein about 12 units apart, in game, 2026-11-07).
local HOVER_PIXELS = 24

local function onHover(names, right, up)
    if not module.db.sightings then
        return
    end
    local v = ns.MinimapPins.View(internal.ZoneMap())
    if not v then
        return
    end
    local x, y = ns.MinimapPins.FromMinimap(v, right, up)
    -- Anywhere around the dot is the same node: that many yards at this zoom.
    local radius = HOVER_PIXELS / v.scale
    if radius < Gathering.RADIUS then
        radius = Gathering.RADIUS
    end
    for _, name in pairs(names) do
        local kind = Professions.Kind(name)
        if kind then
            onSighting({ name = name, kind = kind, mapID = v.mapID, x = x, y = y, radius = radius })
        end
    end
end

local LOOKUP = 25 -- yards from a dot first seen while moving to the node remembered for it

-- For Minimap Node Icons: the spot of the node remembered nearest where it saw a dot.
local function rememberedSpot(name, mapID, x, y)
    local list, width, height = mapNodes(mapID)
    if not list then
        return nil
    end
    local node = Gathering.Nearest(list, x, y, width, height, LOOKUP, function(known)
        return known.name == name
    end)
    if node then
        return node.x, node.y
    end
end

local function onGather(gather)
    if not RECORDED[gather.kind] then
        log(gather, L.GATHERINGMAP_LOG_KIND)
        return
    elseif not gather.name then
        log(gather, L.GATHERINGMAP_LOG_UNNAMED)
        return
    end
    local mapID = gather.mapID
    local list, width, height
    if mapID then
        list, width, height = mapNodes(mapID, true)
    end
    if not list then
        log(gather, L.GATHERINGMAP_LOG_NOWHERE)
        return
    end
    local node, new = Gathering.Add(list, gather.name, gather.kind, gather.x, gather.y, width, height, time())
    for _, item in pairs(gather.items) do
        if item.id then
            node.loot = node.loot or {}
            node.loot[item.id] = (node.loot[item.id] or 0) + (item.count or 1)
        end
    end
    log(gather, new and L.GATHERINGMAP_LOG_NEW
        or node.count == 1 and L.GATHERINGMAP_LOG_ONCE
        or format(L.GATHERINGMAP_LOG_AGAIN, node.count))
    internal.Changed(mapID)
end

-- Each step of hearing a gather, while Log Gathers is on, for finding out why one wasn't.
local TRACE = {
    cast = L.GATHERINGMAP_TRACE_CAST,
    success = L.GATHERINGMAP_TRACE_SUCCESS,
    failed = L.GATHERINGMAP_TRACE_FAILED,
    loot = L.GATHERINGMAP_TRACE_LOOT,
}

-- Read at each step rather than when the option changes: the Debug module turning off puts the
-- option back to its default without telling this one.
local function traceStep(step, a, b, c)
    if module.db.log then
        ns.Print(format(TRACE[step], tostring(a), tostring(b), tostring(c)))
    end
end

local function setTrace()
    Gathering.SetTrace(module.enabled and traceStep or nil)
end

-- Turning on and off ------------------------------------------------------------------------------

function module:OnEnable()
    setTrace()
    readTracking()
    Gathering.Listen(onGather, true)
    Gathering.ListenSightings(onSighting, true)
    Gathering.SetRemembered(rememberedSpot)
    ns.MinimapPins.OnHover(onHover, true)
    if internal.EnableMap then
        internal.EnableMap()
    end
    if internal.EnableMinimap then
        internal.EnableMinimap()
    end
end

function module:OnDisable()
    Gathering.SetTrace(nil)
    Gathering.Listen(onGather, false)
    Gathering.ListenSightings(onSighting, false)
    Gathering.SetRemembered(nil)
    ns.MinimapPins.OnHover(onHover, false)
    if internal.DisableMap then
        internal.DisableMap()
    end
    if internal.DisableMinimap then
        internal.DisableMinimap()
    end
end

function module:OnOptionChanged(key)
    if key == "onlyTracking" then
        readTracking()
    end
    internal.Changed(nil)
end
