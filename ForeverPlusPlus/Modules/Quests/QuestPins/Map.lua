-- Quest Pins on the world map: a layer of Lib/MapPins.lua with a ! at each place quests the player
-- can take start, on the zone map shown and, on a continent map, the zones below it. Spawns of one
-- giver that lie close together share a pin (up to CLUSTER_LIMIT a giver), and pins on the same
-- spot stack into one that lists every quest. Shift+click puts Blizzard's map pin on the pin's
-- nearest spawn, Shift+right-click hides its quests for this character.
local _, ns = ...

local type, pairs, ipairs, format, tostring = type, pairs, ipairs, string.format, tostring
local sort = table.sort
local C_Map, C_QuestLog = C_Map, C_QuestLog
local GetQuestDifficultyColor, HIGHLIGHT_FONT_COLOR = GetQuestDifficultyColor, HIGHLIGHT_FONT_COLOR

local L = ns.L
local QuestieDB = ns.QuestieDB
local MapPins, MapTooltip, WorldMap = ns.MapPins, ns.MapTooltip, ns.WorldMap

local module = ns.modules.QuestPins
local internal = module.internal

local PIN_PIXELS = 24 -- a pin's size on screen at 100%
local CLUSTER_RADIUS = 48 -- pixels of the map's canvas: spawns closer than this share a pin
local SAME_SPOT = 0.002 -- of the map: pins this close stack

-- Pin colors, tinting Blizzard's plain quest ! (it's yellow): the kinds that aren't normal.
local TINT = {
    holiday = { 1, 0.55, 0.85 },
    instance = { 1, 0.32, 0.08 },
    repeatable = { 0.12, 0.72, 1 },
    profession = { 1, 0.65, 0.2 },
}

-- Where the pins' tooltip names what kind they are, at the right of the title.
local KIND_NAME = {
    holiday = L.QUESTPINS_KIND_HOLIDAY,
    instance = L.QUESTPINS_KIND_INSTANCE, class = L.QUESTPINS_KIND_CLASS,
    profession = L.QUESTPINS_KIND_PROFESSION, repeatable = L.QUESTPINS_KIND_REPEATABLE,
}

-- Clusters ----------------------------------------------------------------------------------------

local function canvasSize()
    local map = WorldMap.Get()
    local canvas = map and map.GetCanvas and map:GetCanvas()
    local width, height = canvas and canvas:GetWidth(), canvas and canvas:GetHeight()
    if ns.IsNumber(width) and ns.IsNumber(height) and width >= 1 and height >= 1 then
        return width, height
    end
    return 1000, 667
end

-- Points `{ x, y }` (0 to 1 on the shown map) grouped by nearness, into at most `limit` groups:
-- the nearest two groups join until it fits.
local function cluster(points, width, height, limit)
    local groups = {}
    local radius2 = CLUSTER_RADIUS * CLUSTER_RADIUS
    for _, point in ipairs(points) do
        local joined
        for g = #groups, 1, -1 do
            local group = groups[g]
            for _, other in ipairs(group) do
                local dx, dy = (point.x - other.x) * width, (point.y - other.y) * height
                if dx * dx + dy * dy <= radius2 then
                    if joined then
                        for _, moved in ipairs(group) do
                            joined[#joined + 1] = moved
                        end
                        table.remove(groups, g)
                    else
                        group[#group + 1] = point
                        joined = group
                    end
                    break
                end
            end
        end
        if not joined then
            groups[#groups + 1] = { point }
        end
    end
    while #groups > limit do
        local bi, bj, best
        for i = 1, #groups - 1 do
            for j = i + 1, #groups do
                local a, b = groups[i][1], groups[j][1]
                local dx, dy = (a.x - b.x) * width, (a.y - b.y) * height
                local d = dx * dx + dy * dy
                if not best or d < best then
                    bi, bj, best = i, j, d
                end
            end
        end
        for _, moved in ipairs(groups[bj]) do
            groups[bi][#groups[bi] + 1] = moved
        end
        table.remove(groups, bj)
    end
    return groups
end

-- The point of a group nearest a spot.
local function nearest(group, x, y)
    local best, bestD
    for _, point in ipairs(group) do
        local d = (point.x - x) ^ 2 + (point.y - y) ^ 2
        if not bestD or d < bestD then
            best, bestD = point, d
        end
    end
    return best
end

-- The maps whose sources show on a map: itself and everything below it.
local function mapsFor(mapID)
    local maps = { mapID }
    local below = C_Map.GetMapChildrenInfo and C_Map.GetMapChildrenInfo(mapID, nil, true)
    for _, info in ipairs(below or {}) do
        maps[#maps + 1] = info.mapID
    end
    return maps
end

-- Art ---------------------------------------------------------------------------------------------

-- The color and the kind of a pin from its quests: the first kind every quest is of, else a plain
-- pin. Icon Colors can color it by how hard its first quest is instead, or not at all.
local ORDER = { "holiday", "instance", "class", "profession", "repeatable" }

local function kindOf(quests)
    for _, kind in ipairs(ORDER) do
        local all = true
        for _, id in ipairs(quests) do
            if internal.Category(id) ~= kind then
                all = false
                break
            end
        end
        if all then
            return kind
        end
    end
    return nil
end

local function look(quests)
    local kind = kindOf(quests)
    local mode = module.db.color
    if mode == "plain" then
        return kind, nil
    elseif mode == "difficulty" then
        local level = internal.Level(quests[1])
        local color = level and GetQuestDifficultyColor(level)
        return kind, color and { color.r, color.g, color.b } or nil
    end
    if kind == "class" then
        local color = ns.Colors.Class("player")
        return kind, color and { color:GetRGB() } or nil
    end
    return kind, kind and TINT[kind] or nil
end

-- Tooltip -----------------------------------------------------------------------------------------

local function questLine(id)
    local title = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)
    local q = (not title or title == "") and QuestieDB.Quest(id) or nil
    title = (title and title ~= "") and title or (q and q.name) or format(L.QUESTPINS_QUEST, id)
    local info = internal.info[id]
    local level = C_QuestLog.GetQuestDifficultyLevel and C_QuestLog.GetQuestDifficultyLevel(id)
    if not (type(level) == "number" and level > 0) then
        level = info and (info.level or info.required)
    end
    local color = HIGHLIGHT_FONT_COLOR
    if level then
        title = format("[%d] %s", level, title)
        color = GetQuestDifficultyColor(level)
    end
    return { title, color }
end

local function giverName(info)
    local record = info.giverKind == "npc" and QuestieDB.Npc(info.giverID) or QuestieDB.Object(info.giverID)
    return record and record.name
end

local function tooltipLines(info)
    local db = module.db
    local lines = {}
    local most = db.tooltipMax
    for i = 2, #info.quests do
        if i > most then
            lines[#lines + 1] = MapTooltip.Note(format(L.QUESTPINS_MORE, #info.quests - most))
            break
        end
        lines[#lines + 1] = questLine(info.quests[i])
    end
    -- An upcoming quest says the level it waits for.
    for i, id in ipairs(info.quests) do
        local required = i <= most and info.upcoming[id] == "upcoming" and internal.RequiredLevel(id)
        if required then
            lines[#lines + 1] = MapTooltip.Note(format(L.QUESTPINS_REQUIRES_LEVEL, required))
        end
    end
    local name = db.tooltipGiver and giverName(info)
    if name then
        lines[#lines + 1] = MapTooltip.Detail(name)
    end
    if info.count > 1 then
        lines[#lines + 1] = MapTooltip.Note(format(L.QUESTPINS_SPAWNS, info.count))
    end
    if module.db.debug then
        for _, id in ipairs(info.quests) do
            lines[#lines + 1] = MapTooltip.Note(format("quest %d (%s)", id, internal.Category(id)))
        end
        lines[#lines + 1] = MapTooltip.Note(format("%s %s, map %s %.1f, %.1f", tostring(info.giverKind),
            tostring(info.giverID), tostring(info.anchorMap), info.anchorX * 100, info.anchorY * 100))
    end
    if db.tooltipHints then
        lines[#lines + 1] = MapTooltip.Note(L.QUESTPINS_HINT_WAYPOINT)
        lines[#lines + 1] = MapTooltip.Note(L.QUESTPINS_HINT_HIDE)
    end
    return lines
end

local function shiftClick(pin, button)
    local info = pin.info
    if not info then
        return
    end
    if button == "RightButton" then
        local ids = {}
        for i, id in ipairs(info.quests) do
            ids[i] = id
        end
        internal.Hide(ids)
        return
    end
    local ok, why = WorldMap.SetWaypoint(info.anchorMap, info.anchorX, info.anchorY)
    if not ok then
        ns.Print(why == "map" and L.QUESTPINS_NO_PIN_HERE or L.QUESTPINS_NO_PINS)
    end
end

-- Drawing -----------------------------------------------------------------------------------------

local function fill(mapID, add)
    local db = module.db
    if not (module.enabled and db.pins and internal.ready) then
        return
    end
    local info = C_Map.GetMapInfo(mapID)
    local types = Enum.UIMapType
    -- The world and cosmic maps are too wide for pins; a continent only when asked.
    if not info or info.mapType < types.Continent or (info.mapType == types.Continent and not db.worldMap) then
        return
    end
    local _, px, py = WorldMap.PlayerPosition(mapID)
    px, py = px or 0.5, py or 0.5
    local width, height = canvasSize()
    local size = PIN_PIXELS * db.size / 100
    local checked = {}
    local upcoming = {} -- quest ID -> "upcoming" (shown ahead of its level) or "low" (far under the player's)
    local pins = {}
    for _, zone in ipairs(mapsFor(mapID)) do
        for _, source in ipairs(internal.byMap[zone] or {}) do
            local quests = {}
            if internal.FriendlyToPlayer(source.friendly) then
                for _, id in ipairs(source.quests) do
                    if checked[id] == nil then
                        local ok, note = internal.Check(id)
                        checked[id] = ok
                        upcoming[id] = ok and note or nil
                    end
                    if checked[id] then
                        quests[#quests + 1] = id
                    end
                end
            end
            if #quests > 0 then
                local points = {}
                for i = 1, #source.xs do
                    local x, y = source.xs[i], source.ys[i]
                    if zone ~= mapID then
                        x, y = MapPins.Translate(zone, mapID, x, y)
                    end
                    if x then
                        points[#points + 1] = { x = x, y = y, sx = source.xs[i], sy = source.ys[i] }
                    end
                end
                if #points > 0 then
                    local groups = db.clusters and cluster(points, width, height, db.clusterLimit) or { points }
                    for _, group in ipairs(groups) do
                        local at = nearest(group, px, py)
                        pins[#pins + 1] = { x = at.x, y = at.y, quests = quests, count = #group,
                            map = zone, sx = at.sx, sy = at.sy, kind = source.kind, id = source.id }
                    end
                end
            end
        end
    end
    -- Pins on the same spot become one with all their quests.
    local stacked = {}
    for _, pin in ipairs(pins) do
        local into
        for _, other in ipairs(stacked) do
            if (other.x - pin.x) ^ 2 + (other.y - pin.y) ^ 2 < SAME_SPOT ^ 2 then
                into = other
                break
            end
        end
        if into then
            local have = {}
            for _, id in ipairs(into.quests) do
                have[id] = true
            end
            local merged = { unpack(into.quests) }
            for _, id in ipairs(pin.quests) do
                if not have[id] then
                    merged[#merged + 1] = id
                end
            end
            into.quests = merged
        else
            stacked[#stacked + 1] = pin
        end
    end
    for _, pin in ipairs(stacked) do
        -- Quests worth taking now before upcoming and low-level ones, each by ID.
        sort(pin.quests, function(a, b)
            if (upcoming[a] or false) ~= (upcoming[b] or false) then
                return not upcoming[a]
            end
            return a < b
        end)
        local kind, color = look(pin.quests)
        -- A pin of only upcoming or low-level quests is faded; one quest worth taking now makes
        -- it whole. Low-level ones are gray too, as the game draws a quest too low to matter.
        local faded = upcoming[pin.quests[1]]
        if faded == "low" then
            color = nil
        end
        add(pin.x, pin.y, {
            atlas = "QuestNormal", size = size, color = color, desaturated = color ~= nil or faded == "low",
            alpha = (faded and db.fadeAlpha or db.alpha) / 100, upcoming = upcoming,
            title = questLine(pin.quests[1]), kind = kind and KIND_NAME[kind] or nil,
            lines = tooltipLines, shiftClick = shiftClick, quests = pin.quests, count = pin.count,
            anchorMap = pin.map, anchorX = pin.sx, anchorY = pin.sy,
            giverKind = pin.kind, giverID = pin.id,
        })
    end
end

local layer = MapPins.New(fill)

local function apply()
    if module.enabled and module.db.pins then
        layer:Enable()
        layer:Refresh()
    else
        layer:Disable()
    end
end

function internal.MapOff()
    layer:Disable()
end

internal.OnChanged(apply)

-- The world map's filter menu ---------------------------------------------------------------------
-- A checkbox after Blizzard's own entries, the same switch as Show Quest Pins in Settings. Added
-- once at load: the entry checks whether the module is on each time the menu opens.
local MENU_KINDS = {
    { key = "normal", name = L.QUESTPINS_NORMAL },
    { key = "repeatable", name = L.QUESTPINS_REPEATABLE },
    { key = "class", name = L.QUESTPINS_CLASS },
    { key = "profession", name = L.QUESTPINS_PROFESSION },
    { key = "dungeon", name = L.QUESTPINS_DUNGEON },
    { key = "holiday", name = L.QUESTPINS_HOLIDAY },
    { key = "warEffort", name = L.QUESTPINS_WAR_EFFORT },
}

if Menu and Menu.ModifyMenu then
    Menu.ModifyMenu("MENU_WORLD_MAP_TRACKING", function(_, root)
        if not module.enabled then
            return
        end
        local pins = root:CreateCheckbox(L.QUESTPINS_FILTER, function()
            return module.db.pins
        end, function()
            ns.SetOption(module.name, "pins", not module.db.pins)
        end)
        -- Its submenu: a checkbox for each kind of quest, the same switches as in Settings.
        for _, kind in ipairs(MENU_KINDS) do
            pins:CreateCheckbox(kind.name, function()
                return module.db[kind.key]
            end, function()
                ns.SetOption(module.name, kind.key, not module.db[kind.key])
                -- Keep the menu open, to switch several.
                return MenuResponse and MenuResponse.Refresh or nil
            end)
        end
    end)
end
