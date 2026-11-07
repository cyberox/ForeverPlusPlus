-- Gathering Map: every herb and vein the player gathers is remembered where they stood, for the
-- whole account, and shown on the world map and the minimap. Gathering the same node again counts
-- it and moves its spot toward the average of where the player stood (Lib/Gathering.lua). Ideas
-- from GatherMate2 and GatherLite; none of their code or data.
--
-- This file holds the module, its options, and remembering gathers. Map.lua draws the nodes on
-- the world map and Minimap.lua on the minimap. They share module.internal.
local _, ns = ...

local pairs, time, format = pairs, time, string.format

local L = ns.L
local Gathering = ns.Gathering

local module = ns.NewModule("GatheringMap", L.GATHERINGMAP_DESC, {
    enabled = true,
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

module.options = {
    {
        key = "log", name = L.GATHERINGMAP_LOG, description = L.GATHERINGMAP_LOG_DESC,
        debug = true, section = L.DEBUG_SECTION_LOGGING,
    },
}

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

local function onGather(gather)
    if not RECORDED[gather.kind] then
        log(gather, L.GATHERINGMAP_LOG_KIND)
        return
    elseif not gather.name then
        log(gather, L.GATHERINGMAP_LOG_UNNAMED)
        return
    end
    local mapID = gather.mapID
    local width, height
    if mapID then
        width, height = ns.WorldMap.Size(mapID)
    end
    if not width then
        log(gather, L.GATHERINGMAP_LOG_NOWHERE)
        return
    end
    local nodes = module.db.nodes
    local list = nodes[mapID]
    if not list then
        list = {}
        nodes[mapID] = list
    end
    local node, new = Gathering.Add(list, gather.name, gather.kind, gather.x, gather.y, width, height, time())
    for _, item in pairs(gather.items) do
        if item.id then
            node.loot = node.loot or {}
            node.loot[item.id] = (node.loot[item.id] or 0) + (item.count or 1)
        end
    end
    log(gather, new and L.GATHERINGMAP_LOG_NEW or format(L.GATHERINGMAP_LOG_AGAIN, node.count))
    internal.Changed(mapID)
end

-- Turning on and off ------------------------------------------------------------------------------

function module:OnEnable()
    Gathering.Listen(onGather, true)
    if internal.EnableMap then
        internal.EnableMap()
    end
    if internal.EnableMinimap then
        internal.EnableMinimap()
    end
end

function module:OnDisable()
    Gathering.Listen(onGather, false)
    if internal.DisableMap then
        internal.DisableMap()
    end
    if internal.DisableMinimap then
        internal.DisableMinimap()
    end
end

function module:OnOptionChanged()
    internal.Changed(nil)
end
