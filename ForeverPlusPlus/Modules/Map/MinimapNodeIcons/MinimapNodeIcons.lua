-- Minimap Node Icons: the herb or ore a tracking dot on the minimap stands for, as that item's
-- icon over the dot, optionally gray for a node on another level (as in a cave), red while the
-- player's skill is too low to gather it, or gray once gathering it no longer raises the skill.
--
-- The game draws the dots itself, lists them nowhere an addon can read, and has no way to change
-- or hide one (Forever's minimap has no SetBlipTexture). But its minimap has UpdateMouseoverAtPoint,
-- which points its mouseover at a spot as if a controller's cursor were there, and the tooltip
-- data for the mouseover names what is under that spot. Where a dot answers lags behind where it's
-- drawn while the player moves, and catches up once they stop (in game, 2026-10-13), so probes
-- can't place an icon frame by frame. Instead:
--   - Every frame while the player moves or turns, each icon is drawn from its node's spot on the
--     zone map and the player's own (C_Map.GetPlayerMapPosition), the minimap's view radius, and
--     its rotation. That's exact through moving, turning, and zooming, and costs no probes. While
--     they stand still the icons can't move, so they're drawn again only with each round of probes.
--   - Every second or so (more often while moving), the whole minimap is looked over for new dots
--     on a grid, a part at a time, and a few times a second each node known is looked for again
--     where its dot should be: a line of probes
--     across it and one up through it. While the player stands still the answer is exact and fixes
--     the node's spot; while they move the answer's lag is measured instead, taken off new dots
--     found, and each node's spot creeps toward its answer less the lag. A corrected icon slides
--     to its new spot rather than jumping. A node that stops answering (gathered, out of range)
--     loses its icon.
-- Probing stops in combat and while the cursor is on the minimap, where the game's own mouseover
-- and tooltip (which the icons let through) are the player's; icons keep moving meanwhile.
-- Where the player's spot can't be read (an instance), icons sit where the dots answered.
--
-- Names are matched through Professions.Node: Classic's English names, and those learned in game.
-- A node whose item isn't known gets it the first time the player gathers it (Lib/Gathering.lua:
-- the spell's target, then the first item in the loot window). Its skill is learned from
-- Blizzard's "Requires Herbalism (N)" line where the minimap's tooltip shows one under its name
-- (or Profession Tooltips sees one); until then it's never tinted. Ideas from NodeSight; none of
-- its code.
--
-- This file holds the module, its options, and drawing the icons, with the view and its math from
-- Lib/MinimapPins.lua. Probe.lua asks the minimap what is under a spot, Nodes.lua follows and
-- finds the dots, Learn.lua keeps the icon of a node gathered, and Report.lua has /fpp nodes.
-- They share module.internal.
local _, ns = ...

local ipairs, type = ipairs, type
local CreateFrame, Minimap, GetTime = CreateFrame, Minimap, GetTime
local C_Minimap, C_TooltipInfo, C_Item = C_Minimap, C_TooltipInfo, C_Item

local L = ns.L
local Professions = ns.Professions
local Node = Professions.Node
local MinimapPins = ns.MinimapPins
local toMinimap = MinimapPins.ToMinimap

local module = ns.NewModule("MinimapNodeIcons", L.MINIMAPNODEICONS_DESC, {
    enabled = false,
    size = 8, -- icon size on the minimap
    border = true, -- a gold ring around each icon
    levels = true, -- gray while the minimap names the node in gray (another level)
    tint = false, -- red while the skill is too low
    gray = false, -- gray once gathering no longer raises the skill
    detail = "medium", -- a key of STEPS
    chat = true,
    -- Node name -> icon, for nodes whose item couldn't be read from the loot window (and every
    -- one learned before items were). Data, not a setting.
    learned = {},
    -- { space = a key of SPACES }, once a pass has found a node with it. Data, not a setting.
    calibration = {},
})
module.title = L.MINIMAPNODEICONS_TITLE
module.category = "map"
module.added = "0.9.0"
module.internal = {}
local internal = module.internal
-- Honest about what probing costs and misses (see the top of this file); notices with no button.
-- The second shows once a check found probes can't read the dots (Nodes.lua).
module.notice = {
    {
        text = L.MINIMAPNODEICONS_NOTICE,
        description = L.MINIMAPNODEICONS_NOTICE_DESC,
        shown = function()
            return true
        end,
    },
    {
        text = L.MINIMAPNODEICONS_BROKEN,
        description = L.MINIMAPNODEICONS_BROKEN_DESC,
        shown = function()
            return internal.broken
        end,
    },
}

-- Red on the Modules page while the game doesn't answer its scans (the second notice says why).
function module:Problem()
    return internal.broken
end

module.options = {
    {
        key = "size", name = L.MINIMAPNODEICONS_SIZE, description = L.MINIMAPNODEICONS_SIZE_DESC,
        min = 5, max = 20, step = 1, format = L.ICONMARK_PIXELS,
    },
    { key = "border", name = L.MINIMAPNODEICONS_BORDER, description = L.MINIMAPNODEICONS_BORDER_DESC },
    { key = "levels", name = L.MINIMAPNODEICONS_LEVELS, description = L.MINIMAPNODEICONS_LEVELS_DESC },
    { key = "tint", name = L.MINIMAPNODEICONS_TINT, description = L.MINIMAPNODEICONS_TINT_DESC },
    { key = "gray", name = L.MINIMAPNODEICONS_GRAY, description = L.MINIMAPNODEICONS_GRAY_DESC },
    {
        key = "detail", name = L.MINIMAPNODEICONS_DETAIL, description = L.MINIMAPNODEICONS_DETAIL_DESC,
        choices = {
            { "low", L.MINIMAPNODEICONS_DETAIL_LOW },
            { "medium", L.MINIMAPNODEICONS_DETAIL_MEDIUM },
            { "high", L.MINIMAPNODEICONS_DETAIL_HIGH },
        },
    },
    ns.ChatOption(L.MINIMAPNODEICONS_CHAT_DESC),
}

module.actions = {
    {
        name = L.MINIMAPNODEICONS_CLEAR,
        button = L.MINIMAPNODEICONS_CLEAR_BUTTON,
        description = L.MINIMAPNODEICONS_CLEAR_DESC,
        confirm = L.MINIMAPNODEICONS_CLEAR_CONFIRM,
        fn = function()
            module.db.learned = {}
            Professions.ForgetNodes()
            ns.Print(L.MINIMAPNODEICONS_CLEAR_DONE)
        end,
    },
}

-- Forever only: the minimap's UpdateMouseoverAtPoint is in its API docs (1.60.1).
function module:IsAvailable()
    return Minimap and Minimap.UpdateMouseoverAtPoint and C_TooltipInfo
        and C_TooltipInfo.GetMinimapMouseover and true or false
end

local HERBS = ns.GameData.Spell(2383, "Find Herbs")
local MINERALS = ns.GameData.Spell(2580, "Find Minerals")

-- Its parts' own rows on the Profiler page, so its time can be told apart. While not recording,
-- Profiler.Call just calls through. Probes are only counted (PART_ASK), not timed: a stopwatch
-- around each of hundreds a second costs more than the probe.
local Profiler = ns.Profiler
-- The other parts are made in the files that time them.
local PART_VIEW = Profiler.Part(module, L.MINIMAPNODEICONS_PART_VIEW)
local PART_DRAW = Profiler.Part(module, L.MINIMAPNODEICONS_PART_DRAW)

local TICK = 0.1 -- seconds between rounds of probes; icons are drawn every frame while moving
local EDGE = 2 -- keep probes and icons this far inside the minimap's edge
local RED = { 1, 0.25, 0.25 } -- the icon's vertex color while the skill is too low
local GRAY = { 0.7, 0.7, 0.7 } -- dims a gray (desaturated) icon
internal.TICK = TICK
internal.EDGE = EDGE
internal.STEPS = { low = 8, medium = 6, high = 4 } -- minimap units between finding probes
internal.NONE = {}

-- State the files share, on internal since some of it is replaced whole (internal.nodes = {}).
-- The nodes with an icon: { name, icon, standing, level, misses, right, up, x, y }. `right` and
-- `up` are where the dot answered last, in minimap units from the center; `x` and `y` its spot on
-- the zone map `nodesMap`, set when the view could be read, and what the icon is drawn from.
-- `level` is true while the minimap names it in gray (on another level).
internal.nodes = {}
internal.seen = {} -- names the minimap showed that aren't nodes we know, for learning
internal.tracking = false -- Find Herbs or Find Minerals is on
internal.blocked = false -- the client refused a probe; stop until /reload
internal.broken = false -- a probe couldn't read a dot the player's mouse named; stop until /reload
internal.findAll = false -- find every dot at the next tick, after a zoom or a reset
internal.pass = nil -- the finding pass under way (Nodes.lua)
local nodesMap

-- The icon for a node's name, or nil for a name that isn't a node we know.
function internal.iconFor(name)
    local node = Node(name)
    local icon = node and node[3] and C_Item.GetItemIconByID(node[3])
    return icon or module.db.learned[name]
end

-- How the player's skill stands against the node named `name`: "low" when it's too low to gather
-- (or they lack the profession), "gray" when gathering it no longer raises the skill, else nil,
-- as for a node whose skill isn't known.
local function standing(name)
    local node = Node(name)
    if not (node and node[1] and node[2]) then
        return nil
    end
    local rank = Professions.Rank(node[1])
    if not rank or rank < node[2] then
        return "low"
    elseif Professions.Difficulty(rank, node[2]) == Professions.TRIVIAL then
        return "gray"
    end
end
internal.standing = standing

-- The view ----------------------------------------------------------------------------------------

-- What the minimap shows right now and spots on it, from Lib/MinimapPins.lua: nil where the view
-- can't be read, as in an instance.
local readView = MinimapPins.View
internal.readView = readView
internal.fromMinimap = MinimapPins.FromMinimap

local function inside(right, up)
    return MinimapPins.Inside(right, up, EDGE)
end
internal.inside = inside

-- Nodes -------------------------------------------------------------------------------------------

local frame -- over the minimap; holds the icons and runs the probes

-- Whether Find Herbs or Find Minerals is on. The frame (and with it its icons and OnUpdate) shows
-- only while one is, so the module costs nothing per frame without them.
local function readTracking()
    internal.tracking = false
    for i = 1, C_Minimap.GetNumTrackingTypes() do
        local info = C_Minimap.GetTrackingInfo(i)
        if type(info) == "table" and info.active and (info.spellID == HERBS or info.spellID == MINERALS) then
            internal.tracking = true
            break
        end
    end
    if not internal.tracking then
        internal.nodes = {}
    end
    if frame and module.enabled then
        frame:SetShown(internal.tracking)
    end
end
internal.readTracking = readTracking

local GLIDE = 0.15 -- seconds an icon takes to slide to a node's corrected spot
local gliding = false -- an icon is sliding, so the next frame draws even standing still

---Puts a node on a new spot on the zone map. Its icon slides there from where it's drawn now,
---so a correction doesn't show as a jump.
---@param node table
---@param x number
---@param y number
function internal.moveNode(node, x, y)
    if node.x and (node.x ~= x or node.y ~= y) then
        local now, fromX, fromY = GetTime(), node.x, node.y
        if node.glideAt then
            local t = (now - node.glideAt) / GLIDE
            if t < 1 then
                fromX = node.fromX + (node.x - node.fromX) * t
                fromY = node.fromY + (node.y - node.fromY) * t
            end
        end
        node.fromX, node.fromY, node.glideAt = fromX, fromY, now
    end
    node.x, node.y = x, y
end

-- Where a node's icon belongs right now, from its map spot when there is a view, else where it
-- answered last. With `shown`, where it's drawn this frame: partway along a slide to a new spot.
local function drawnAt(node, v, shown)
    if v and node.x and v.mapID == nodesMap then
        local x, y = node.x, node.y
        if shown and node.glideAt then
            local t = (GetTime() - node.glideAt) / GLIDE
            if t < 1 then
                x, y = node.fromX + (x - node.fromX) * t, node.fromY + (y - node.fromY) * t
                gliding = true
            else
                node.glideAt = nil
            end
        end
        return toMinimap(v, x, y)
    end
    return node.right, node.up
end
internal.drawnAt = drawnAt

-- Drawing ---------------------------------------------------------------------------------------

local pins = {}
local sinceTick = 0

-- A pin: the icon, round, with the ring around it. It takes no mouse, so the minimap's own
-- tooltip for the dot under it shows, with whatever other addons (Profession Tooltips) add.
local function getPin(i)
    local pin = pins[i]
    if not pin then
        pin = CreateFrame("Frame", nil, frame)
        local icon = pin:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        -- A round icon, like the minimap's own. Probe: the mask is Mainline's portrait mask.
        local mask = pin:CreateMaskTexture()
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE",
            "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(icon)
        icon:AddMaskTexture(mask)
        pin.icon, pin.ring = icon, MinimapPins.NewRing(pin)
        pins[i] = pin
    end
    return pin
end

local function hidePins(from)
    for i = from or 1, #pins do
        local pin = pins[i]
        if pin.node then
            pin.node = nil -- restyled when it's used again
            pin:Hide()
        end
    end
end

-- Puts the ring around a pin of `size`, or hides it.
local function placeRing(pin, size, shown)
    local ring = pin.ring
    if not shown then
        ring:Hide()
        return
    end
    MinimapPins.PlaceRing(ring, pin, size)
    ring:Show()
end

-- Draws an icon per node inside the minimap. A pin's look and spot are set only when they
-- changed: standing still nothing does, and moving only the spot does.
local function draw(v)
    local db = module.db
    local size, border = db.size, db.border
    local radius = Minimap:GetWidth() / 2 - EDGE
    local shown = 0
    gliding = false
    for _, node in ipairs(internal.nodes) do
        local right, up = drawnAt(node, v, true)
        if right * right + up * up <= radius * radius then
            shown = shown + 1
            local pin = getPin(shown)
            local grayed = (db.gray and node.standing == "gray") or (db.levels and node.level) or false
            local low = (db.tint and node.standing == "low") or false
            if pin.node ~= node or pin.look ~= node.icon or pin.grayed ~= grayed or pin.low ~= low
                or pin.size ~= size or pin.border ~= border then
                pin.node, pin.look, pin.grayed, pin.low, pin.size, pin.border =
                    node, node.icon, grayed, low, size, border
                local icon = pin.icon
                icon:SetTexture(node.icon)
                icon:SetDesaturated(grayed)
                if low then
                    icon:SetVertexColor(RED[1], RED[2], RED[3])
                elseif grayed then
                    icon:SetVertexColor(GRAY[1], GRAY[2], GRAY[3])
                else
                    icon:SetVertexColor(1, 1, 1)
                end
                pin:SetSize(size, size)
                placeRing(pin, size, border)
                pin:Show()
                pin.right = nil
            end
            if pin.right ~= right or pin.up ~= up then
                pin.right, pin.up = right, up
                -- One point, so SetPoint replaces it.
                pin:SetPoint("CENTER", Minimap, "CENTER", right, up)
            end
        end
    end
    hidePins(shown + 1)
end

local redraw = true -- something changed that the next frame must draw (a zoom, an option)

-- Whether the icons could have moved since the last frame: the player is moving or turning. While
-- they stand still the icons are where they were, so the view is read and they're drawn only on
-- each tick (which also follows the dots, so a gathered node still goes within one) and when
-- something else changed. On a boat the speed reads 0; the ticks still follow it, less smoothly.
local mayHaveMoved = MinimapPins.NewMotion()

local function onUpdate(_, elapsed)
    sinceTick = sinceTick + elapsed
    local due = sinceTick >= TICK
    if not (due or redraw or gliding or mayHaveMoved()) then
        return
    end
    redraw = false
    local v = Profiler.Call(PART_VIEW, readView)
    -- A new zone map: the nodes' spots were on the old one.
    if v and v.mapID ~= nodesMap then
        internal.nodes, nodesMap, internal.pass, internal.findAll = {}, v.mapID, nil, true
        internal.forgetSpot()
    end
    if due then
        sinceTick = 0
        internal.tick(v)
    end
    Profiler.Call(PART_DRAW, draw, v)
end

-- A skill-up can lift the tint.
local function onSkill()
    for _, node in ipairs(internal.nodes) do
        node.standing = standing(node.name)
    end
    redraw = true
end

-- A zoom: icons drawn from map spots move with it by themselves; look over the minimap for dots it
-- brought in. Without a view, where the dots answered is all there is, so start over.
local function onZoom()
    internal.findAll, redraw = true, true
    if not readView() then
        internal.nodes = {}
    end
end

-- Turning on and off ------------------------------------------------------------------------------

-- The nodes with an icon now, for Gathering Map not to draw its own under them.
local function live()
    return nodesMap, internal.nodes
end

function module:OnEnable()
    ns.Gathering.SetLive(live)
    if not frame then
        frame = CreateFrame("Frame", nil, Minimap)
        frame:SetAllPoints(Minimap)
        frame:SetFrameLevel(Minimap:GetFrameLevel() + 5)
    end
    frame:SetScript("OnUpdate", ns.Profiler.Wrap(self, onUpdate)) -- timed while the Profiler records
    redraw = true
    readTracking() -- shows the frame while tracking is on
    internal.findAll = true
    self:On("MINIMAP_UPDATE_TRACKING", readTracking)
    self:On("PLAYER_ENTERING_WORLD", readTracking)
    ns.Gathering.Listen(internal.onGather, true)
    MinimapPins.OnHover(internal.onHover, true)
    self:On("SKILL_LINES_CHANGED", onSkill)
    self:On("MINIMAP_UPDATE_ZOOM", onZoom)
    -- Rotate Minimap may have changed; Lib/MinimapPins.lua reads it again by itself.
    self:On("CVAR_UPDATE", function()
        redraw = true
    end)
end

function module:OnDisable()
    if frame then
        frame:SetScript("OnUpdate", nil)
        frame:Hide()
    end
    ns.Gathering.Listen(internal.onGather, false)
    MinimapPins.OnHover(internal.onHover, false)
    ns.Gathering.SetLive(nil)
    internal.nodes, nodesMap, internal.pass = {}, nil, nil
end

function module:OnOptionChanged(key)
    redraw = true -- size, border, tints
    if key == "detail" then
        internal.pass = nil
    end
end
