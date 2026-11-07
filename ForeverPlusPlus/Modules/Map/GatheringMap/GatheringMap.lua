-- Gathering Map: every herb and vein the player gathers is remembered where they stood, for the
-- whole account, and shown on the world map and the minimap. Gathering the same node again counts
-- it and moves its spot toward the average of where the player stood (Lib/Gathering.lua). Ideas
-- from GatherMate2 and GatherLite; none of their code or data.
--
-- This file holds the module, its options, and remembering gathers. Map.lua draws the nodes on
-- the world map and Minimap.lua on the minimap. They share module.internal.
local _, ns = ...

local pairs, ipairs, type, time, format, tostring = pairs, ipairs, type, time, string.format, tostring
local C_Minimap, C_Map, IsShiftKeyDown = C_Minimap, C_Map, IsShiftKeyDown
local Minimap, GameTooltip, strtrim, NORMAL_FONT_COLOR = Minimap, GameTooltip, strtrim, NORMAL_FONT_COLOR
local ITEM_MIN_SKILL, C_TooltipInfo, setmetatable = ITEM_MIN_SKILL, C_TooltipInfo, setmetatable

local L = ns.L
local Gathering = ns.Gathering

local module = ns.NewModule("GatheringMap", L.GATHERINGMAP_DESC, {
    enabled = true,
    onlyMine = true, -- only nodes this character has the profession for
    onlyTracking = true, -- herbs only while Find Herbs is on, ore while Find Minerals is
    -- A node this character's skill is too low for, and one that no longer gives skill-ups:
    -- "show", "gray" (its icon gray), or "hide".
    tooHigh = "gray",
    trivial = "show",
    justMinutes = 5, -- how long a node counts as just gathered; nodes were back within 10 (in game,
    -- 2026-11-07); GatherLite has no timer
    -- How a node gathered lately shows on each map: "faded" (its icon, see-through), "ring" (an
    -- empty ring), "hide", or "show" (as usual), at that map's Just Gathered Opacity (percent, on
    -- its own, not times the map's Opacity, which made it too faint to see). An empty ring on the
    -- minimap, the faded icon on the world map (Cameron, 2026-11-08).
    justMinimap = "ring",
    justMinimapAlpha = 50,
    justWorld = "faded",
    justWorldAlpha = 40,
    icon = "item", -- "item" (the node's item's icon, a circle without one) or "circle"
    ring = true, -- the minimap's gold ring around each icon
    worldMap = true,
    mapSize = 70, -- percent of MAP_PIXELS on the world map
    mapAlpha = 85, -- percent
    mapContinents = false, -- on continent maps too
    minimap = true,
    minimapSize = 10, -- pixels, a little bigger than the game's own tracking dots
    minimapAlpha = 100, -- percent
    minimapEdge = false, -- a node just past the minimap's edge sits on the edge
    minimapTooltips = true, -- an icon shows its node's tooltip
    -- Each line of a node's tooltip: "always", "shift" (while Shift is held), or "never".
    tipGathered = "always",
    tipLast = "always",
    tipAlso = "always",
    tipDistance = "shift",
    tipForget = "shift",
    -- How a node shows on the minimap: "all" (an empty ring anywhere on it, the game's own dot
    -- inside it when the node is there, since the game draws dots out to about the minimap's edge:
    -- a Silver Vein ~200 yards off, in game, 2026-11-07), or within nearYards of the player "ring"
    -- (an empty ring) or "hide"; else, and with "show", its icon. Rings at ringAlpha.
    -- GatherMate2's way by default: icons far off, empty rings close (150 yards, Cameron's pick;
    -- GatherMate2 uses 100).
    nearby = "ring",
    nearYards = 150,
    ringAlpha = 50, -- percent: those empty rings near you on the minimap
    chat = true, -- say in chat when Shift+right-click forgets a node
    log = false, -- print each gather in chat (Debug)
    -- Nodes remembered, by zone map ID: a list of { name, kind, x, y, count, time, loot }, where
    -- loot is item ID -> how many it gave in all. For the whole account. Data, not a setting.
    nodes = {},
    -- What this character doesn't show, from the Gathering Map page (and the world map's filter):
    -- node name -> true, and kind ("herb", "ore") -> true. Data, saved for each character.
    hidden = {},
    hiddenKinds = {},
    -- And node name -> true for a node shown on one map but not the other.
    hiddenWorld = {},
    hiddenMinimap = {},
})
module.perCharacter = { hidden = true, hiddenKinds = true, hiddenWorld = true, hiddenMinimap = true }
module.title = L.GATHERINGMAP_TITLE
module.pageTitle = L.GATHERINGMAP_PAGE_TITLE
module.category = "map"
module.added = "1.2.0"
module.internal = {}
local internal = module.internal

-- Other gathering map addons draw their own icons for the same nodes, so both sets show.
local OTHERS = { "GatherMate2", "GatherLite", "Gatherer" }

local function otherAddon()
    for _, name in ipairs(OTHERS) do
        if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(name) then
            return name
        end
    end
end

module.notice = {
    text = L.GATHERINGMAP_OTHER,
    description = L.GATHERINGMAP_OTHER_DESC,
    shown = function()
        return otherAddon() ~= nil
    end,
}

local LOOK, MINIMAP, WORLD = L.GATHERINGMAP_SECTION_LOOK, L.GATHERINGMAP_SECTION_MINIMAP,
    L.GATHERINGMAP_SECTION_WORLDMAP
local TIPS = L.GATHERINGMAP_SECTION_TOOLTIPS

-- A line of the nodes' tooltips: shown always, only while Shift is held, or never.
local function tipOption(key, name, description)
    return {
        key = key, name = name, description = description, section = TIPS,
        choices = {
            { "always", L.GATHERINGMAP_TIP_ALWAYS },
            { "shift", L.GATHERINGMAP_TIP_SHIFT },
            { "never", L.GATHERINGMAP_TIP_NEVER },
        },
    }
end

-- How a node shows by this character's skill: as usual, gray, or not at all.
-- How a node just gathered shows on one map (`key`), in that map's section, under its Show on.
local function justOption(key, section, requires)
    return {
        key = key, name = L.GATHERINGMAP_JUST, description = L.GATHERINGMAP_JUST_DESC, section = section,
        requires = requires,
        choices = {
            { "faded", L.GATHERINGMAP_JUST_FADED },
            { "ring", L.GATHERINGMAP_JUST_RING },
            { "hide", L.GATHERINGMAP_JUST_HIDE },
            { "show", L.GATHERINGMAP_JUST_SHOW },
        },
    }
end

-- And how solid it is there, while it's faded or a ring.
local function justAlphaOption(key, look, section, requires)
    return {
        key = key, name = L.GATHERINGMAP_JUST_ALPHA, description = L.GATHERINGMAP_JUST_ALPHA_DESC,
        section = section, requires = requires, min = 10, max = 100, step = 5, format = "%d%%",
        shown = function(db)
            return db[look] == "faded" or db[look] == "ring"
        end,
    }
end

local function skillOption(key, name, description)
    return {
        key = key, name = name, description = description,
        choices = {
            { "show", L.GATHERINGMAP_SKILL_SHOW },
            { "gray", L.GATHERINGMAP_SKILL_GRAY },
            { "hide", L.GATHERINGMAP_SKILL_HIDE },
        },
    }
end

-- Last, under its own header, as every module's Chat Messages is.
-- Under Remembered Nodes, after its Share and Forget buttons (which sit at the top of the section):
-- what it says in chat is about forgetting them.
local NODES = L.GATHERINGMAP_SECTION_NODES
local chatOption = ns.ChatOption(L.GATHERINGMAP_CHAT_DESC, NODES)

module.options = {
    { key = "onlyMine", name = L.GATHERINGMAP_ONLY_MINE, description = L.GATHERINGMAP_ONLY_MINE_DESC },
    { key = "onlyTracking", name = L.GATHERINGMAP_ONLY_TRACKING, description = L.GATHERINGMAP_ONLY_TRACKING_DESC },
    skillOption("tooHigh", L.GATHERINGMAP_TOO_HIGH, L.GATHERINGMAP_TOO_HIGH_DESC),
    skillOption("trivial", L.GATHERINGMAP_TRIVIAL, L.GATHERINGMAP_TRIVIAL_DESC),
    {
        key = "icon", name = L.GATHERINGMAP_ICON, description = L.GATHERINGMAP_ICON_DESC, section = LOOK,
        choices = {
            { "item", L.GATHERINGMAP_ICON_ITEM },
            { "circle", L.GATHERINGMAP_ICON_CIRCLE },
        },
    },
    { key = "ring", name = L.GATHERINGMAP_RING, description = L.GATHERINGMAP_RING_DESC, section = LOOK },
    {
        key = "justMinutes", name = L.GATHERINGMAP_JUST_MINUTES, description = L.GATHERINGMAP_JUST_MINUTES_DESC,
        section = LOOK, min = 1, max = 30, step = 1, format = ns.Text.Minutes,
    },
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
        key = "nearby", name = L.GATHERINGMAP_NEAR, description = L.GATHERINGMAP_NEAR_DESC,
        section = MINIMAP, requires = "minimap",
        choices = {
            { "ring", L.GATHERINGMAP_NEAR_RING },
            { "hide", L.GATHERINGMAP_NEAR_HIDE },
            { "all", L.GATHERINGMAP_NEAR_ALL },
            { "show", L.GATHERINGMAP_NEAR_SHOW },
        },
    },
    {
        key = "nearYards", name = L.GATHERINGMAP_NEAR_YARDS, description = L.GATHERINGMAP_NEAR_YARDS_DESC,
        section = MINIMAP, requires = "minimap", min = 10, max = 200, step = 10, format = L.GATHERINGMAP_YARDS,
        shown = function(db)
            return db.nearby == "ring" or db.nearby == "hide"
        end,
    },
    {
        key = "ringAlpha", name = L.GATHERINGMAP_RING_ALPHA, description = L.GATHERINGMAP_RING_ALPHA_DESC,
        section = MINIMAP, requires = "minimap", min = 10, max = 100, step = 5, format = "%d%%",
        shown = function(db)
            return db.nearby == "ring" or db.nearby == "all"
        end,
    },
    justOption("justMinimap", MINIMAP, "minimap"),
    justAlphaOption("justMinimapAlpha", "justMinimap", MINIMAP, "minimap"),
    {
        key = "minimapEdge", name = L.GATHERINGMAP_EDGE, description = L.GATHERINGMAP_EDGE_DESC,
        section = MINIMAP, requires = "minimap",
    },
    {
        key = "minimapTooltips", name = L.GATHERINGMAP_TOOLTIPS, description = L.GATHERINGMAP_TOOLTIPS_DESC,
        section = MINIMAP, requires = "minimap",
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
    justOption("justWorld", WORLD, "worldMap"),
    justAlphaOption("justWorldAlpha", "justWorld", WORLD, "worldMap"),
    {
        key = "mapContinents", name = L.GATHERINGMAP_CONTINENTS, description = L.GATHERINGMAP_CONTINENTS_DESC,
        section = WORLD, requires = "worldMap",
    },
    tipOption("tipGathered", L.GATHERINGMAP_TIP_GATHERED_NAME, L.GATHERINGMAP_TIP_GATHERED_DESC),
    tipOption("tipLast", L.GATHERINGMAP_TIP_LAST_NAME, L.GATHERINGMAP_TIP_LAST_DESC),
    tipOption("tipAlso", L.GATHERINGMAP_TIP_ALSO_NAME, L.GATHERINGMAP_TIP_ALSO_DESC),
    tipOption("tipDistance", L.GATHERINGMAP_TIP_DISTANCE_NAME, L.GATHERINGMAP_TIP_DISTANCE_DESC),
    tipOption("tipForget", L.GATHERINGMAP_TIP_FORGET_NAME, L.GATHERINGMAP_TIP_FORGET_DESC),
    chatOption,
    {
        key = "log", name = L.GATHERINGMAP_LOG, description = L.GATHERINGMAP_LOG_DESC,
        debug = true, section = L.DEBUG_SECTION_LOGGING,
    },
}

---Forgets one node of the zone map `mapID`. Shift+right-click on its icon on either map.
---@param mapID number
---@param node table
function internal.Forget(mapID, node)
    local nodes = module.db.nodes
    local list = nodes[mapID]
    if not list then
        return
    end
    for i = #list, 1, -1 do
        if list[i] == node then
            table.remove(list, i)
        end
    end
    if #list == 0 then
        nodes[mapID] = nil
    end
    module:Print(format(L.GATHERINGMAP_FORGOT_ONE, node.name))
    internal.NodesChanged(mapID)
end

-- Forgets every node of a zone map, or of every map with no `mapID`; says how many.
local function forgetAll(mapID)
    local nodes = module.db.nodes
    local forgot = 0
    for id, list in pairs(nodes) do
        if not mapID or id == mapID then
            forgot = forgot + #list
            nodes[id] = nil
        end
    end
    ns.Print(format(L.GATHERINGMAP_FORGOT, forgot))
    internal.NodesChanged(nil)
end

-- Sharing: every remembered node as a line of text to copy, and a pasted one's nodes added to
-- what's remembered, the same node close by counted once.
local function exportNodes()
    local text, count = Gathering.Encode(module.db.nodes)
    if count == 0 then
        ns.Print(L.GATHERINGMAP_EXPORT_NONE)
        return
    end
    ns.Prompt("GATHERINGMAP_EXPORT", format(L.GATHERINGMAP_EXPORT_PROMPT, count), text, nil, true)
end

local function importNodes(text)
    local maps = Gathering.Decode(text, time())
    if not maps then
        ns.Print(L.GATHERINGMAP_IMPORT_BAD)
        return
    end
    local nodes = module.db.nodes
    local added, known = 0, 0
    -- A map this client has no size for (not in its game) is skipped, and not counted.
    for mapID, list in pairs(maps) do
        local width, height = ns.WorldMap.Size(mapID)
        if width then
            local mine = nodes[mapID] or {}
            for _, node in ipairs(list) do
                if Gathering.Merge(mine, node, width, height) then
                    added = added + 1
                else
                    known = known + 1
                end
            end
            nodes[mapID] = #mine > 0 and mine or nil
        end
    end
    ns.Print(format(L.GATHERINGMAP_IMPORTED, added, known))
    internal.NodesChanged(nil)
end

module.actions = {
    {
        name = L.GATHERINGMAP_EXPORT,
        button = L.GATHERINGMAP_EXPORT_BUTTON,
        description = L.GATHERINGMAP_EXPORT_DESC,
        section = NODES,
        fn = exportNodes,
    },
    {
        name = L.GATHERINGMAP_IMPORT,
        button = L.GATHERINGMAP_IMPORT_BUTTON,
        description = L.GATHERINGMAP_IMPORT_DESC,
        section = NODES,
        fn = function()
            ns.Prompt("GATHERINGMAP_IMPORT", L.GATHERINGMAP_IMPORT_PROMPT, "", importNodes, true)
        end,
    },
    {
        name = L.GATHERINGMAP_FORGET_ZONE,
        button = L.GATHERINGMAP_FORGET_BUTTON,
        description = L.GATHERINGMAP_FORGET_ZONE_DESC,
        confirm = L.GATHERINGMAP_FORGET_ZONE_CONFIRM,
        section = NODES,
        fn = function()
            local zone = internal.ZoneMap()
            if zone then
                forgetAll(zone)
            end
        end,
    },
    {
        name = L.GATHERINGMAP_FORGET_ALL,
        button = L.GATHERINGMAP_FORGET_BUTTON,
        description = L.GATHERINGMAP_FORGET_ALL_DESC,
        confirm = L.GATHERINGMAP_FORGET_ALL_CONFIRM,
        section = NODES,
        fn = function()
            forgetAll(nil)
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
-- A skill-up can change what Only My Professions, Too High for You, and No Skill-Ups show.
module:OnWhile(function(db)
    return db.onlyMine or db.tooHigh ~= "show" or db.trivial ~= "show"
end, { SKILL_LINES_CHANGED = onSkills })

-- The kinds of node remembered.
local RECORDED = { herb = true, ore = true, treasure = true, fish = true }

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

---internal.Changed after the remembered nodes themselves changed (a gather, a forget, an import),
---which also tells other addons through the public API.
---@param mapID number?
function internal.NodesChanged(mapID)
    internal.Changed(mapID)
    ns.Providers.Changed("gatheringNodes")
end

-- What the public API reads while the module is on (API.lua's GetGatheringMaps and
-- GetGatheringNodes, which copy what they give out).
local provider = {
    Maps = function()
        return module.db.nodes
    end,
}

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
internal.COLORS, internal.CIRCLE = COLORS, CIRCLE

local icons = {} -- node name -> its item's icon, once found

-- A chest gives something different each time, so it's drawn as a chest: Blizzard's small chest
-- icon, as old as the game.
local CHEST_ICON = "Interface\\Icons\\INV_Box_02"

-- A pool's icon is the fish it gave most, or a fish when it hasn't given any yet.
local FISH_ICON = "Interface\\Icons\\INV_Misc_Fish_02"

local function poolIcon(node)
    local best, most
    for item, count in pairs(node.loot or {}) do
        if not most or count > most then
            best, most = item, count
        end
    end
    local icon = best and C_Item.GetItemIconByID(best)
    return icon and ns.IsReadable(icon) and icon or FISH_ICON
end

-- The icon of a node's item, or nil. A chest's is the chest icon, and a pool's its fish.
local function itemIcon(node)
    if node.kind == "treasure" or Professions.Chest(node.name) then
        return CHEST_ICON
    elseif node.kind == "fish" or Professions.Pool(node.name) then
        return poolIcon(node)
    end
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
-- For the Gathering Map page: a node's icon by its name (and loot, when it has some).
internal.ItemIcon = itemIcon

---Whether a node was gathered within the last Just Gathered minutes, so it's likely still gone.
---@param node table
---@return boolean
function internal.JustGathered(node)
    return node.time ~= nil and time() - node.time < module.db.justMinutes * 60
end

---Makes `look` an empty ring: a node just gathered, or near the player on the minimap, where the
---game's own dot shows inside it when the node is up. Each map draws it at its own Empty Ring
---Opacity, not on top of its icons' Opacity, so a ring stays as solid as that setting says.
---@param look table
---@return table look
function internal.Hollow(look)
    look.round, look.ring, look.hollow = true, true, true
    return look
end

---Fills `look` with how a node is drawn, as Lib/MapPins takes it: `texture`, `trim`, `round`,
---`color`, `ring`, and `hollow`. A node is round: its item's icon, or a circle in its kind's color, with the gold ring if that's
---on; a node just gathered is drawn as that map's Just Gathered says (`just` while it's faded or a
---ring, at its Just Gathered Opacity), the ring alone for Empty Ring.
---@param node table
---@param look table
---@param where "world"|"minimap"
---@return table look
function internal.Look(node, look, where)
    local db = module.db
    local icon = db.icon == "item" and itemIcon(node) or nil
    look.atlas, look.round = nil, true
    -- Gray while Too High for You or No Skill-Ups says so for this character's skill.
    local standing = internal.Standing(node)
    look.desaturated = standing ~= nil and db[standing] == "gray"
    if icon then
        look.texture, look.trim, look.color = icon, true, nil
    else
        look.texture, look.trim, look.color = CIRCLE, false, COLORS[node.kind] or COLORS.herb
    end
    look.ring, look.hollow = db.ring, false
    local just = internal.JustLook(where)
    look.just = (just == "faded" or just == "ring") and internal.JustGathered(node)
    if look.just and just == "ring" then
        internal.Hollow(look)
    end
    return look
end

---A map's Just Gathered ("faded", "ring", "hide", or "show"), and its Just Gathered Opacity as a
---fraction.
---@param where "world"|"minimap"
---@return string look
---@return number alpha
function internal.JustLook(where)
    local db = module.db
    if where == "world" then
        return db.justWorld, db.justWorldAlpha / 100
    end
    return db.justMinimap, db.justMinimapAlpha / 100
end

---How this character's skill stands against a node: "tooHigh" while it's too low to gather it,
---"trivial" once gathering it no longer gives skill-ups, else nil, as for a node whose skill isn't
---known or a character without the profession (Only My Professions is for that).
---@param node table
---@return string? standing the key of its option
function internal.Standing(node)
    local known = Professions.Node(node.name)
    local line, need = known and known[1], known and known[2]
    if not (line and need) then
        return nil
    end
    local rank = Professions.Rank(line)
    if not rank then
        return nil
    elseif rank < need then
        return "tooHigh"
    elseif Professions.Difficulty(rank, need) == Professions.TRIVIAL then
        return "trivial"
    end
end

-- Herbs and ore need their gathering skill and tracking spell; anyone can open treasure.
local TRACKED = { herb = true, ore = true }

---Whether a node is shown on the world map ("world") or the minimap ("minimap"): not while this
---character turned it or its kind off (the Gathering Map page), or turned it off on that map; with
---Only My Professions, only while this character has the skill that gathers it; and with Only
---While Tracking, only while its tracking is on.
---@param node table
---@param where "world"|"minimap"
---@return boolean
function internal.Shown(node, where)
    local db = module.db
    local kind = node.kind
    -- Turned off on the Gathering Map page or the world map's filter, for this character.
    if db.hiddenKinds[kind] or db.hidden[node.name] then
        return false
    end
    if (where == "world" and db.hiddenWorld or db.hiddenMinimap)[node.name] then
        return false
    end
    if db.onlyMine and kind ~= "treasure" then
        local line = Professions.KindLine(kind)
        if not (line and Professions.Rank(line)) then
            return false
        end
    end
    if db.onlyTracking and TRACKED[kind] and not tracking[kind] then
        return false
    end
    if internal.JustLook(where) == "hide" and internal.JustGathered(node) then
        return false
    end
    local standing = internal.Standing(node)
    if standing and db[standing] == "hide" then
        return false
    end
    return true
end

---internal.Shown for each map, to pass where a function of the node alone is wanted.
---@param node table
---@return boolean
function internal.ShownOnWorld(node)
    return internal.Shown(node, "world")
end

---@param node table
---@return boolean
function internal.ShownOnMinimap(node)
    return internal.Shown(node, "minimap")
end

-- Whether a tooltip line set to `key` ("always", "shift", or "never") shows now.
local function wants(key)
    local when = module.db[key]
    return when == "always" or (when == "shift" and IsShiftKeyDown())
end

---A node's name as its tooltip's title: gold, as the minimap's own tooltip names a node.
---@param node table
---@return table title
function internal.Title(node)
    return { node.name, NORMAL_FONT_COLOR }
end

-- Blizzard's "Requires Mining (75)" under the name, as the minimap's own tooltip has it, in the
-- trainer's colors against the player's skill; nil for a node whose skill isn't known. The page's
-- details use it too, as internal.Requires.
local function requiresLine(node)
    local known = Professions.Node(node.name)
    local line, need = known and known[1], known and known[2]
    local skill = line and Professions.LineName(line)
    -- A locked chest: the Lockpicking it takes, against a rogue's (red for anyone else).
    if not known then
        local _, lock = Professions.Chest(node.name)
        if lock then
            local rank, name = Professions.Rank(Professions.LOCKPICKING)
            line, need, skill = Professions.LOCKPICKING, lock, name or L.GATHERINGMAP_LOCKPICKING
            return { format(ITEM_MIN_SKILL or L.GATHERINGMAP_REQUIRES, skill, need),
                Professions.Difficulty(rank, need) }
        end
    end
    if not (skill and need) then
        return nil
    end
    return { format(ITEM_MIN_SKILL or L.GATHERINGMAP_REQUIRES, skill, need),
        Professions.Difficulty(Professions.Rank(line), need) }
end

internal.Requires = requiresLine

---The lines under a node's name in its tooltip, as Blizzard's Sell Price line lays them out: a
---label and its value, each line shown always, with Shift held, or never as its option says.
---`yards` is how far the node is, where that's known (the minimap). With `onDot`, the lines added
---to Blizzard's own tooltip for the game's dot, which has its requirement already.
---@param node table
---@param yards? number
---@param onDot? boolean
---@return table lines
function internal.TooltipLines(node, yards, onDot)
    local Tip = ns.MapTooltip
    local lines = {}
    if not onDot then
        lines[#lines + 1] = requiresLine(node)
    end
    if node.count == 0 then
        lines[#lines + 1] = Tip.Detail(L.GATHERINGMAP_SEEN)
    elseif wants("tipGathered") then
        lines[#lines + 1] = Tip.Pair(L.GATHERINGMAP_TIP_GATHERED, node.count == 1 and L.GATHERINGMAP_TIP_ONCE
            or format(L.GATHERINGMAP_TIP_TIMES, node.count))
    end
    if node.time and wants("tipLast") then
        lines[#lines + 1] = Tip.Pair(L.GATHERINGMAP_TIP_LAST, ns.Text.Ago(time() - node.time))
    end
    -- A spot that spawned more than one vein (Tin and Silver): the others, with their gathers.
    if node.names and wants("tipAlso") then
        for name, count in pairs(node.names) do
            if name ~= node.name then
                lines[#lines + 1] = Tip.Pair(L.GATHERINGMAP_TIP_ALSO,
                    format(L.GATHERINGMAP_TIP_ALSO_VALUE, name, count))
            end
        end
    end
    if yards and wants("tipDistance") then
        lines[#lines + 1] = Tip.Pair(L.GATHERINGMAP_TIP_DISTANCE, format(L.GATHERINGMAP_YARDS, yards + 0.5))
    end
    if wants("tipForget") then
        -- On the world map a Shift+click also places the map pin; on the minimap it's a ping.
        lines[#lines + 1] = Tip.Note(onDot and L.GATHERINGMAP_FORGET_HINT or L.GATHERINGMAP_MAP_HINT)
    end
    return lines
end

-- The minimap ----------------------------------------------------------------------------------
-- Our icons on the minimap take no mouse (Minimap.lua): the minimap's own tooltip and clicks cover
-- them, so a node has one tooltip wherever the mouse is on it. Blizzard fills that tooltip every
-- frame while the mouse is on the minimap (Minimap_OnUpdate: SetOwner to the cursor, then
-- SetMinimapMouseover); a hook on that call adds our lines under the game's for its dot, arrow
-- for another level and all. A general tooltip hook missed some of those frames (in game,
-- 2026-11-07).
local DOT_REACH = 24 -- minimap units from the mouse that a dot it names can be
local addedAt = setmetatable({}, { __mode = "k" }) -- tooltip -> its line count once ours were added

-- The names the game gives for its dots under the mouse, one a row, or nil where there are none.
local function namesAtCursor()
    local data = C_TooltipInfo and C_TooltipInfo.GetMinimapMouseover and C_TooltipInfo.GetMinimapMouseover()
    local lines = data and data.lines
    local first = type(lines) == "table" and lines[1]
    local text = type(first) == "table" and first.leftText
    if not ns.IsText(text, true) then
        return nil
    end
    local names = {}
    for row in text:gmatch("[^\n]+") do
        names[#names + 1] = strtrim(ns.Text.Plain(row))
    end
    return names
end

-- The remembered node under the mouse on the minimap, how far it is from the player, and its map:
-- with `names` (the game's dots there), the one of those names as far as a dot reaches; without,
-- the one whose icon is under the mouse.
local function nodeAtCursor(names)
    local v = ns.MinimapPins.View(internal.ZoneMap())
    local list = v and module.db.nodes[v.mapID]
    if not list then
        return nil
    end
    local x, y = ns.MinimapPins.FromMinimap(v, ns.MinimapPins.CursorOffset())
    local node
    if names then
        local reach = DOT_REACH / v.scale
        for _, name in ipairs(names) do
            node = Gathering.Nearest(list, x, y, v.width, v.height, reach, function(known)
                return internal.Shown(known, "minimap") and Professions.SharesSpawn(known.name, name)
            end)
            if node then
                break
            end
        end
    else
        -- Anywhere on the icon or the gold ring around it, which reaches past the icon's edge.
        local reach = module.db.minimapSize / v.scale
        node = Gathering.Nearest(list, x, y, v.width, v.height, reach, internal.ShownOnMinimap)
    end
    if node then
        return node, Gathering.Distance(node.x, node.y, v.x, v.y, v.width, v.height), v.mapID
    end
end

local function onMinimapTooltip(tooltip)
    if not (module.enabled and module.db.minimap and module.db.minimapTooltips and Minimap:IsMouseOver()) then
        return
    end
    -- Ours are there already when the game kept its lines rather than filling them again.
    if addedAt[tooltip] and tooltip:NumLines() == addedAt[tooltip] then
        return
    end
    addedAt[tooltip] = nil
    -- Only under the game's own lines: where it has no dot (the node is gone) there's no tooltip,
    -- as without the addon; the empty ring says so, and the world map has the node's history.
    local names = namesAtCursor()
    if not names then
        return -- most frames over the minimap: no dot under the mouse
    end
    local node, yards = nodeAtCursor(names)
    if not node then
        return
    end
    ns.MapTooltip.AddLines(tooltip, internal.TooltipLines(node, yards, true))
    tooltip:Show()
    addedAt[tooltip] = tooltip:NumLines()
end

-- Shift+right-click on the minimap forgets the remembered node there, up or gone. The game's dot
-- stays; gathering it again starts a new one.
local function onMinimapClick(_, button)
    if button ~= "RightButton" or not IsShiftKeyDown() or not module.db.minimap then
        return
    end
    local node, _, mapID = nodeAtCursor(namesAtCursor())
    if node then
        internal.Forget(mapID, node)
    end
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
    if not RECORDED[sighting.kind] then
        return
    end
    local list, width, height = mapNodes(sighting.mapID, true)
    if not list then
        return
    end
    local _, new = Gathering.See(list, sighting.name, sighting.kind, sighting.x, sighting.y, width,
        height, time())
    if new then
        internal.NodesChanged(sighting.mapID)
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

-- Nodes the player only hovers on the minimap aren't remembered: a hover says only roughly where
-- the dot is, so the node it saved sat off the vein, and mining the vein made another beside it
-- (in game, 2026-11-07).

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
    elseif gather.kind == "treasure" and not Professions.Chest(gather.name) then
        -- Opening opens quest objects and crates too; only chests are treasure.
        log(gather, L.GATHERINGMAP_LOG_NOT_CHEST)
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
    -- One the player's skill is too low for: remembered where they stood, not yet gathered, and
    -- gray on the maps (Too High for You) until they can.
    if gather.requires then
        local _, new = Gathering.See(list, gather.name, gather.kind, gather.x, gather.y, width, height,
            time())
        log(gather, format(L.GATHERINGMAP_LOG_REQUIRES, gather.requires))
        if new then
            internal.NodesChanged(mapID)
        end
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
    internal.NodesChanged(mapID)
end

-- Each step of hearing a gather, while Log Gathers is on, for finding out why one wasn't.
local TRACE = {
    cast = L.GATHERINGMAP_TRACE_CAST,
    success = L.GATHERINGMAP_TRACE_SUCCESS,
    failed = L.GATHERINGMAP_TRACE_FAILED,
    loot = L.GATHERINGMAP_TRACE_LOOT,
    refused = L.GATHERINGMAP_TRACE_REFUSED,
}

-- Read at each step rather than when the option changes: the Debug module turning off puts the
-- option back to its default without telling this one.
local function traceStep(step, a, b, c)
    if module.db.log then
        ns.Print(format(TRACE[step], tostring(a), tostring(b), tostring(c)))
    end
end

-- Only while Log Gathers is on, so no step builds its log line for nothing.
local function setTrace()
    Gathering.SetTrace(module.enabled and module.db.log and traceStep or nil)
end

-- Turning on and off ------------------------------------------------------------------------------

function module:OnEnable()
    setTrace()
    readTracking()
    self:Hook(GameTooltip, "SetMinimapMouseover", onMinimapTooltip)
    self:HookScript(Minimap, "OnMouseUp", onMinimapClick)
    Gathering.Listen(onGather, true)
    Gathering.ListenSightings(onSighting, true)
    Gathering.SetRemembered(rememberedSpot)
    ns.Providers.Set("gatheringNodes", provider)
    if internal.EnableMap then
        internal.EnableMap()
    end
    if internal.EnableFilter then
        internal.EnableFilter()
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
    ns.Providers.Set("gatheringNodes", nil)
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
    elseif key == "log" then
        setTrace()
    end
    internal.Changed(nil)
end
