-- Gathering Map's icons on the minimap: the nodes near the player, each drawn from its spot on the
-- zone map and the player's own (Lib/MinimapPins.lua), so they're exact through moving, turning,
-- and zooming. Which nodes are near is worked out again each second, after a zoom, and when a
-- node is gathered; their spots on the minimap every frame while the player moves or turns, and
-- not at all while they stand still. The icons take no mouse: the minimap's own tooltip and
-- Shift+right-click cover them (GatheringMap.lua).
local _, ns = ...

local pairs, sort, setmetatable = pairs, table.sort, setmetatable
local CreateFrame, Minimap = CreateFrame, Minimap

local module = ns.modules.GatheringMap
local internal = module.internal
local MinimapPins = ns.MinimapPins
local ToMinimap, Inside = MinimapPins.ToMinimap, MinimapPins.Inside
local Distance = ns.Gathering.Distance

local NEAR = 1.5 -- nodes this many minimap radii away are followed, so one walked toward appears
local REFRESH = 1 -- seconds between looks for the nodes near the player
local LEVELS = 12 -- frame levels the pins spread over

local frame -- over the minimap; holds the icons and runs OnUpdate
local pins = {}
local near = {} -- the nodes followed now
local nearMap -- the zone map they're on
local look = {} -- filled by internal.Look for each pin
local sinceRefresh = REFRESH
local redraw = true -- the next frame must draw: an option, a zoom, a new node
local moved = MinimapPins.NewMotion()

local zoneMap = internal.ZoneMap

local LIVE_YARDS = 10 -- a remembered node this close to a live icon of its name is that node

-- Whether Minimap Node Icons draws `node` on its live dot now, so ours would sit under it.
-- Minimap Node Icons' nodes are on the map the player stands on, which in a cave or a city's
-- district isn't the zone's map ours are on, so their spots are moved onto ours to compare.
local function isLive(node, liveList, liveMap, v)
    for i = 1, #liveList do
        local other = liveList[i]
        if other.name == node.name and other.x then
            local x, y = other.x, other.y
            if liveMap ~= v.mapID then
                x, y = ns.MapPins.Translate(liveMap, v.mapID, x, y)
            end
            if x and ns.Gathering.Distance(node.x, node.y, x, y, v.width, v.height) <= LIVE_YARDS then
                return true
            end
        end
    end
    return false
end

-- How far each node followed is from the player, squared in minimap units, as findNear found it:
-- kept apart from the node, which is saved data.
local away = setmetatable({}, { __mode = "k" })

local function byAway(a, b)
    return (away[a] or 0) < (away[b] or 0)
end

-- The nodes within NEAR radii of the player on view `v`'s map, nearest first, but for those
-- Minimap Node Icons draws on their live dots already.
local function findNear(v)
    local count = 0
    local list = module.db.nodes[v.mapID]
    if list then
        local reach = v.half * NEAR
        local reach2 = reach * reach
        local shown = internal.Shown
        local liveMap, liveList = ns.Gathering.Live()
        if not (liveMap and liveList and #liveList > 0) then
            liveList = nil
        end
        for _, node in pairs(list) do
            if shown(node) and not (liveList and isLive(node, liveList, liveMap, v)) then
                local right, up = ToMinimap(v, node.x, node.y)
                local far2 = right * right + up * up
                if far2 <= reach2 then
                    count = count + 1
                    near[count] = node
                    away[node] = far2
                end
            end
        end
    end
    for i = count + 1, #near do
        near[i] = nil
    end
    -- Nearest first, so where icons overlap the one nearest the player is the one drawn.
    sort(near, byAway)
    nearMap = v.mapID
end

-- A pin takes no mouse: the mouse always reaches the minimap, whose own tooltip shows the game's
-- dot there with our lines, and whose Shift+right-click forgets a node (GatheringMap.lua).
local function getPin(i)
    local pin = pins[i]
    if not pin then
        pin = CreateFrame("Frame", nil, frame)
        pin:EnableMouse(false)
        -- A level of its own, so each pin draws whole, icon and ring, over the one before: at one
        -- level the game draws every icon before every ring, and a neighbor's ring could land
        -- between a pin's icon and its ring (in game, 2026-11-07). A few levels, so many pins
        -- can't climb over the minimap's own buttons.
        pin:SetFrameLevel(frame:GetFrameLevel() + 1 + (i - 1) % LEVELS)
        local texture = pin:CreateTexture(nil, "ARTWORK")
        texture:SetAllPoints()
        pin.texture = texture
        pins[i] = pin
    end
    return pin
end

-- Sets a pin's look for `node`: the same as on the world map, at the minimap's size. Near the
-- player (`close`), with Near You set to Empty Ring, the ring alone, so the game's own dot shows
-- inside it when the node is there.
local function style(pin, node, size, alpha, close)
    internal.Look(node, look)
    if close then
        internal.Hollow(look)
    end
    look.alpha = alpha * look.fade
    ns.MapPins.SetArt(pin, look)
    pin:SetSize(size, size)
    if pin.ring then
        MinimapPins.PlaceRing(pin.ring, pin, size)
    end
end

local function hidePins(from)
    for i = from, #pins do
        local pin = pins[i]
        if pin.node then
            pin.node = nil
            pin:Hide()
        end
    end
end

-- Draws an icon for each node followed that's on the minimap now. A pin is restyled only when it
-- shows another node, comes near the player or leaves, or an option changed (`restyle`), and
-- moved only when its spot changed. Anywhere on the minimap (Near You's Whole Minimap), or within
-- its yards of the player, a node is an empty ring or hidden, as GatherLite does close up: only
-- the game's own dot can say whether a node is there now, so ours leaves room for it.
-- Icons closer than this share of their size overlap: only the first drawn (the nearest) shows.
local OVERLAP = 0.75
local placed = {} -- the spots drawn this frame: right, up, right, up, ...

-- Whether a spot is on an icon already drawn this frame.
local function overlaps(right, up, count, gap)
    for i = 1, count, 2 do
        local dr, du = placed[i] - right, placed[i + 1] - up
        if dr * dr + du * du < gap * gap then
            return true
        end
    end
    return false
end

local function draw(v, restyle)
    local db = module.db
    local size, alpha = db.minimapSize, db.minimapAlpha / 100
    local inset = size / 2
    local nearby, nearYards, edge = db.nearby, db.nearYards, db.minimapEdge
    local gap = size * OVERLAP
    local shown, count = 0, 0
    for i = 1, #near do
        local node = near[i]
        local right, up = ToMinimap(v, node.x, node.y)
        local close = nearby == "all" or (nearby ~= "show"
            and Distance(node.x, node.y, v.x, v.y, v.width, v.height) <= nearYards)
        local inside = Inside(right, up, inset)
        -- Keep at the Edge: a node past the minimap's edge sits on it, toward where it is.
        if not inside and edge and not close then
            right, up = MinimapPins.ToEdge(right, up, inset)
            inside = true
        end
        if inside and not (close and nearby == "hide") and not overlaps(right, up, count, gap) then
            placed[count + 1], placed[count + 2] = right, up
            count = count + 2
            shown = shown + 1
            local pin = getPin(shown)
            if restyle or pin.node ~= node or pin.near ~= close then
                pin.node, pin.near = node, close
                style(pin, node, size, alpha, close)
                pin:Show()
                pin.right = nil
            end
            if pin.right ~= right or pin.up ~= up then
                pin.right, pin.up = right, up
                pin:SetPoint("CENTER", Minimap, "CENTER", right, up)
            end
        end
    end
    hidePins(shown + 1)
end

local restyle = true

local function onUpdate(_, elapsed)
    sinceRefresh = sinceRefresh + elapsed
    local due = sinceRefresh >= REFRESH
    if not (due or redraw or moved()) then
        return
    end
    local v = MinimapPins.View(zoneMap())
    if not v then
        hidePins(1)
        return
    end
    if due or redraw or v.mapID ~= nearMap then
        sinceRefresh = 0
        findNear(v)
        -- A node gathered lately fades and, its time up, comes back: look again each second.
        restyle = true
    end
    draw(v, restyle)
    redraw, restyle = false, false
end

local wrapped -- onUpdate as the Profiler times it

local function apply()
    local on = module.enabled and module.db.minimap
    if on and not frame then
        frame = CreateFrame("Frame", nil, Minimap)
        frame:SetAllPoints(Minimap)
        -- Under Minimap Node Icons' icons, which sit on the game's live dots.
        frame:SetFrameLevel(Minimap:GetFrameLevel() + 4)
    end
    if not frame then
        return
    end
    if on then
        -- Wrapped once: this runs again after every gather and option.
        wrapped = wrapped or ns.Profiler.Wrap(module, onUpdate) -- timed while the Profiler records
        frame:SetScript("OnUpdate", wrapped)
        frame:Show()
        redraw, restyle = true, true
    else
        frame:SetScript("OnUpdate", nil)
        frame:Hide()
        hidePins(1)
        near, nearMap = {}, nil
    end
end

local function onZoom()
    redraw = true
end

function internal.EnableMinimap()
    apply()
    module:On("MINIMAP_UPDATE_ZOOM", onZoom)
end

function internal.DisableMinimap()
    apply()
end

-- A new node, or an option: look for nodes and draw again.
internal.OnChanged(function()
    if module.enabled then
        apply()
    end
end)
