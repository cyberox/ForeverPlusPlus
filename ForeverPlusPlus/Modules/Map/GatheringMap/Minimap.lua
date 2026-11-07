-- Gathering Map's icons on the minimap: the nodes near the player, each drawn from its spot on the
-- zone map and the player's own (Lib/MinimapPins.lua), so they're exact through moving, turning,
-- and zooming. Which nodes are near is worked out again each second, after a zoom, and when a
-- node is gathered; their spots on the minimap every frame while the player moves or turns, and
-- not at all while they stand still. With Minimap Tooltips on, an icon shows its node's tooltip;
-- clicks always go through to the minimap.
local _, ns = ...

local pairs = pairs
local CreateFrame, Minimap, GameTooltip = CreateFrame, Minimap, GameTooltip

local module = ns.modules.GatheringMap
local internal = module.internal
local MinimapPins = ns.MinimapPins
local ToMinimap, Inside = MinimapPins.ToMinimap, MinimapPins.Inside
local Distance = ns.Gathering.Distance

local NEAR = 1.5 -- nodes this many minimap radii away are followed, so one walked toward appears
local REFRESH = 1 -- seconds between looks for the nodes near the player

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
local function isLive(node, liveList, v)
    for i = 1, #liveList do
        local other = liveList[i]
        if other.name == node.name and other.x
            and ns.Gathering.Distance(node.x, node.y, other.x, other.y, v.width, v.height) <= LIVE_YARDS then
            return true
        end
    end
    return false
end

-- The nodes within NEAR radii of the player on view `v`'s map, but for those Minimap Node Icons
-- draws on their live dots already.
local function findNear(v)
    local count = 0
    local list = module.db.nodes[v.mapID]
    if list then
        local reach = v.half * NEAR
        local reach2 = reach * reach
        local shown = internal.Shown
        local liveMap, liveList = ns.Gathering.Live()
        if liveMap ~= v.mapID or not liveList or #liveList == 0 then
            liveList = nil
        end
        for _, node in pairs(list) do
            if shown(node) and not (liveList and isLive(node, liveList, v)) then
                local right, up = ToMinimap(v, node.x, node.y)
                if right * right + up * up <= reach2 then
                    count = count + 1
                    near[count] = node
                end
            end
        end
    end
    for i = count + 1, #near do
        near[i] = nil
    end
    nearMap = v.mapID
end

-- A pin's tooltip, while Minimap Tooltips is on: the node, as on the world map, and near the
-- player a note that only the game's own dot says whether it's there now.
local function onEnter(pin)
    local node = pin.node
    if not node then
        return
    end
    -- The game's own tooltip for its dot under the mouse, when there is one (the node is up), with
    -- our lines added under it (GatheringMap.lua's hook), so it's the same tooltip as on the dot
    -- itself, arrow for another level and all.
    GameTooltip:SetOwner(pin, "ANCHOR_CURSOR")
    if GameTooltip.SetMinimapMouseover then
        GameTooltip:SetMinimapMouseover()
        if GameTooltip:NumLines() > 0 then
            GameTooltip:Show()
            return
        end
    end
    -- No dot there: the node is gone, or not seen by the game yet. Ours, the same lines with the
    -- name and requirement as the game writes them, at the cursor as the game's is (Blizzard_Minimap's
    -- Minimap_OnUpdate: ANCHOR_CURSOR). How far it is, for Within's distance.
    local yards
    local v = MinimapPins.View(zoneMap())
    if v and v.mapID == nearMap then
        yards = Distance(node.x, node.y, v.x, v.y, v.width, v.height)
    end
    ns.MapTooltip.Show(pin, internal.Title(node), internal.TooltipLines(node, yards), nil, true)
end

local function onLeave(pin)
    if GameTooltip:IsOwned(pin) then
        GameTooltip:Hide()
    end
end

local function getPin(i)
    local pin = pins[i]
    if not pin then
        pin = CreateFrame("Frame", nil, frame)
        local texture = pin:CreateTexture(nil, "ARTWORK")
        texture:SetAllPoints()
        pin.texture = texture
        -- Clicks go through to the minimap (a ping) either way. Probe: without the split, the
        -- pin takes the mouse whole, so it takes none.
        if pin.SetMouseMotionEnabled and pin.SetMouseClickEnabled then
            pin:SetMouseClickEnabled(false)
        else
            pin:EnableMouse(false)
        end
        pin:SetScript("OnEnter", onEnter)
        pin:SetScript("OnLeave", onLeave)
        -- Shift+right-click forgets the node.
        ns.MapPins.ShiftClick(pin, function(self, button)
            if button == "RightButton" and self.node and nearMap then
                internal.Forget(nearMap, self.node)
            end
        end)
        pins[i] = pin
    end
    return pin
end

-- Sets a pin's look for `node`: the same as on the world map, at the minimap's size. Near the
-- player (`close`), with Near You set to Empty Ring, the ring alone, so the game's own dot shows
-- inside it when the node is there.
local function style(pin, node, size, alpha, close)
    local db = module.db
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
    if pin.SetMouseMotionEnabled then
        pin:SetMouseMotionEnabled(db.minimapTooltips)
    end
end

local function hidePins(from)
    for i = from, #pins do
        local pin = pins[i]
        if pin.node then
            pin.node = nil
            onLeave(pin)
            pin:Hide()
        end
    end
end

-- Draws an icon for each node followed that's on the minimap now. A pin is restyled only when it
-- shows another node, comes near the player or leaves, or an option changed (`restyle`), and
-- moved only when its spot changed. Anywhere on the minimap (Near You's Whole Minimap), or within
-- its yards of the player, a node is an empty ring or hidden, as GatherLite does close up: only
-- the game's own dot can say whether a node is there now, so ours leaves room for it.
local function draw(v, restyle)
    local db = module.db
    local size, alpha = db.minimapSize, db.minimapAlpha / 100
    local inset = size / 2
    local nearby, nearYards = db.nearby, db.nearYards
    local shown = 0
    for i = 1, #near do
        local node = near[i]
        local right, up = ToMinimap(v, node.x, node.y)
        local close = nearby == "all" or (nearby ~= "show"
            and Distance(node.x, node.y, v.x, v.y, v.width, v.height) <= nearYards)
        if Inside(right, up, inset) and not (close and nearby == "hide") then
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
        frame:SetScript("OnUpdate", ns.Profiler.Wrap(module, onUpdate)) -- timed while the Profiler records
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
