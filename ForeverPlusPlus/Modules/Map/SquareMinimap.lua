-- Square Minimap: makes Blizzard's minimap square. Its round mask becomes a square one, its round
-- frame fades out, and a border in Blizzard's tooltip or dialog art goes around it. While it's
-- on, the global GetMinimapShape answers "SQUARE": the convention minimap button libraries
-- (LibDBIcon) and Lib/MinimapPins.lua read, so buttons on the edge and our icons on the minimap
-- follow the square. The map moves up to the header row the round frame kept it from, and the day
-- and night indicator drags anywhere with a key held. Turned off, the round mask and frame, the
-- map's place, and the sun's come back. An addon that already shapes the minimap (its own
-- GetMinimapShape) is left to it.
local _, ns = ...

local _G, type, ipairs, abs, floor, wipe = _G, type, ipairs, math.abs, math.floor, wipe
local CreateFrame, GetCursorPosition = CreateFrame, GetCursorPosition

local L = ns.L

local module = ns.NewModule("SquareMinimap", L.SQUAREMINIMAP_DESC, {
    enabled = false,
    border = "gold", -- a BORDERS key, or none; set below to one this client has
    borderScale = 100, -- the border art's size, in percent
    gap = 6, -- pixels between the map and the header row (zone name, tracking, calendar)
    sunKey = "shift", -- the key held to drag the day and night indicator, or off
    mail = "topleft", -- the map's corner the mail icon sits in, or blizzard for Blizzard's place
    -- Data, not settings: where the player dragged the sun, from the map's middle, in its pixels.
    sun = {},
})
module.title = L.SQUAREMINIMAP_TITLE
module.category = "map"
module.presets = { developer = { enabled = true } }
module.added = "1.4.0"

-- A plain white square: the minimap shows wherever its mask is opaque, so all of it.
local SQUARE_MASK = "Interface\\Buttons\\WHITE8X8"
-- Blizzard's round mask. Forever's minimap sets this atlas for both of Rotate Minimap's modes
-- (Blizzard_Minimap's Camelot Minimap.lua, MinimapClusterMixin:UpdateMinimapConfig, wow-ui-source
-- `forever` branch, checked 2026-11-09); Mainline's file is for a client without that atlas.
local ROUND_MASK_ATLAS = "ui-hud-minimap-frame-generic-mask"
local ROUND_MASK_FILE = "Interface\\Masks\\CircleMaskScalable"

-- The round frame's art (Blizzard_Minimap's Minimap.xml): the ring, and with Rotate Minimap, the
-- circle its pointer turns on. Faded rather than hidden, since Blizzard shows and hides the circle
-- as the setting changes.
local ART = { "MinimapCompassTexture", "MinimapCompassTextureUnderlay" }

-- The borders, in the order the dropdown lists them. Two kinds, both Blizzard's own art:
-- - `layout`: a frame from NineSliceLayouts (Blizzard_SharedXML/Mainline/NineSliceLayouts.lua,
--   `forever` branch, checked 2026-11-09), drawn by NineSliceUtil, so Forever's own art and its
--   offsets for it (Camelot/NineSliceLayoutOverrides.lua) come with it. (The windows' own frames,
--   ButtonFrameTemplateNoPortrait and SimplePanelTemplate, left a wide empty band inside the line
--   in game, so they aren't offered.) Faction is the Alliance or Horde mission table frame by the
--   player's side, and Wood for anyone else. `atlas` is one of its pieces, to check this client
--   has it. The frame's pieces lie inside it, so it sits `outset` of its edge's width past the
--   minimap, which puts the middle of the line on the minimap's edge.
-- - `file`: a backdrop edge file at an edge size that suits the minimap, `outset` pixels past it.
--   `backdrop` is the global Blizzard keeps it in, read first in case a patch moves the file.
local BORDERS = {
    { "gold", L.SQUAREMINIMAP_BORDER_GOLD, backdrop = "BACKDROP_GOLD_DIALOG_32_32",
        file = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border", size = 16, outset = 5 },
    { "metal", L.SQUAREMINIMAP_BORDER_METAL, layout = "GenericMetal",
        atlas = "!UI-Frame-GenericMetal-EdgeLeft", outset = 0.5 },
    { "diamond", L.SQUAREMINIMAP_BORDER_DIAMOND, layout = "Dialog",
        atlas = "!UI-Frame-DiamondMetal-EdgeLeft", outset = 0.5 },
    { "wood", L.SQUAREMINIMAP_BORDER_WOOD, layout = "WoodenNeutralFrameTemplate",
        atlas = "!Neutral-NineSlice-EdgeLeft", outset = 0.5 },
    { "faction", L.SQUAREMINIMAP_BORDER_FACTION, faction = true, outset = 0.5 },
    { "dragon", L.SQUAREMINIMAP_BORDER_DRAGON, layout = "DragonflightMissionFrame",
        atlas = "!Dragonflight-NineSlice-EdgeLeft", outset = 0.5 },
    { "oribos", L.SQUAREMINIMAP_BORDER_ORIBOS, layout = "CovenantMissionFrame",
        atlas = "!Oribos-NineSlice-EdgeLeft", outset = 0.5 },
    { "dialog", L.SQUAREMINIMAP_BORDER_DIALOG, backdrop = "BACKDROP_DIALOG_32_32",
        file = "Interface\\DialogFrame\\UI-DialogBox-Border", size = 16, outset = 5 },
    { "achievement", L.SQUAREMINIMAP_BORDER_ACHIEVEMENT,
        file = "Interface\\AchievementFrame\\UI-Achievement-WoodBorder", size = 32, outset = 8 },
    { "tooltip", L.SQUAREMINIMAP_BORDER_TOOLTIP, backdrop = "BACKDROP_TOOLTIP_16_16_5555",
        file = "Interface\\Tooltips\\UI-Tooltip-Border", size = 16, outset = 4 },
}
local FACTION_LAYOUTS = {
    Alliance = { layout = "BFAMissionAlliance", atlas = "!AllianceFrameTile-Left" },
    Horde = { layout = "BFAMissionHorde", atlas = "!HordeFrameTile-Left" },
    Neutral = { layout = "WoodenNeutralFrameTemplate", atlas = "!Neutral-NineSlice-EdgeLeft" },
}

-- Whether this client can draw a border: its layout and art, or its file (when the client can say).
local function hasLayout(layout, atlas)
    return NineSliceUtil and NineSliceUtil.GetLayout and NineSliceUtil.GetLayout(layout) ~= nil
        and ns.Frames.HasAtlas(atlas)
end
local function available(style)
    if style.faction then
        return hasLayout(FACTION_LAYOUTS.Alliance.layout, FACTION_LAYOUTS.Alliance.atlas)
            and hasLayout(FACTION_LAYOUTS.Horde.layout, FACTION_LAYOUTS.Horde.atlas)
    elseif style.layout then
        return hasLayout(style.layout, style.atlas)
    end
    return not GetFileIDFromPath or GetFileIDFromPath(style.file) ~= nil
end

local STYLES, CHOICES = {}, {}
for _, style in ipairs(BORDERS) do
    if available(style) then
        STYLES[style[1]] = style
        CHOICES[#CHOICES + 1] = { style[1], style[2] }
    end
end
CHOICES[#CHOICES + 1] = { "none", L.SQUAREMINIMAP_BORDER_NONE }
-- Gold, or Stone without it.
module.defaults.border = STYLES.gold and "gold" or STYLES.dialog and "dialog" or "none"

-- The keys that can drag the sun, and Off.
local SUN_KEYS = {}
for _, choice in ipairs(ns.Keys.CHOICES) do
    if choice[1] ~= "none" then
        SUN_KEYS[#SUN_KEYS + 1] = choice
    end
end
SUN_KEYS[#SUN_KEYS + 1] = { "off", L.SQUAREMINIMAP_SUN_OFF }

module.options = {
    {
        key = "border",
        name = L.SQUAREMINIMAP_BORDER,
        description = L.SQUAREMINIMAP_BORDER_DESC,
        choices = CHOICES,
    },
    {
        key = "borderScale",
        name = L.SQUAREMINIMAP_BORDER_SCALE,
        description = L.SQUAREMINIMAP_BORDER_SCALE_DESC,
        min = 50, max = 150, step = 10, format = "%d%%",
        shown = function(db) return db.border ~= "none" end,
    },
    {
        key = "gap",
        name = L.SQUAREMINIMAP_GAP,
        description = L.SQUAREMINIMAP_GAP_DESC,
        min = 0, max = 40, step = 1, format = L.ICONMARK_PIXELS,
    },
    {
        key = "sunKey",
        name = L.SQUAREMINIMAP_SUN_KEY,
        description = L.SQUAREMINIMAP_SUN_KEY_DESC,
        choices = SUN_KEYS,
    },
    {
        key = "mail",
        name = L.SQUAREMINIMAP_MAIL,
        description = L.SQUAREMINIMAP_MAIL_DESC,
        choices = {
            { "topleft", L.SQUAREMINIMAP_MAIL_TOPLEFT },
            { "topright", L.SQUAREMINIMAP_MAIL_TOPRIGHT },
            { "bottomleft", L.SQUAREMINIMAP_MAIL_BOTTOMLEFT },
            { "bottomright", L.SQUAREMINIMAP_MAIL_BOTTOMRIGHT },
            { "blizzard", L.SQUAREMINIMAP_MAIL_BLIZZARD },
        },
        added = "1.6.0",
    },
}

module.actions = {
    {
        name = L.SQUAREMINIMAP_SUN_RESET_NAME,
        button = L.SQUAREMINIMAP_SUN_RESET,
        description = L.SQUAREMINIMAP_SUN_RESET_DESC,
        fn = function() module.internal.ResetSun() end,
    },
}
module.internal = {}

local squared = false -- whether the minimap is square because of us
local border -- our frame around the minimap, made the first time it's needed

-- Ours, the global GetMinimapShape while the minimap is square because of us.
local function getShape()
    return "SQUARE"
end

-- Whether another addon defines GetMinimapShape: it shapes the minimap, so this leaves it be.
local function otherShape()
    local shape = _G.GetMinimapShape
    return shape ~= nil and shape ~= getShape
end

-- A gray row while another addon shapes the minimap, since then turning this on does nothing.
module.notice = {
    text = L.SQUAREMINIMAP_OTHER,
    description = L.SQUAREMINIMAP_OTHER_DESC,
    shown = function()
        return module.enabled and otherShape()
    end,
}

function module:IsAvailable()
    return Minimap and Minimap.SetMaskTexture and true or false
end

local function setArt(alpha)
    for _, name in ipairs(ART) do
        local texture = _G[name]
        if texture and texture.SetAlpha then
            texture:SetAlpha(alpha)
        end
    end
end

-- Our frames around the minimap: one for a backdrop and one for a nine-slice frame, since a frame
-- keeps a layout's pieces once it has them. Over the map, under the icons and buttons addons put
-- on it (ours sit 4 and more up).
local slices
local function newFrame(template)
    local frame = CreateFrame("Frame", nil, Minimap, template)
    frame:SetFrameLevel(Minimap:GetFrameLevel() + 2)
    return frame
end

-- The minimap with `outset` (in the frame's own scale) all round.
local function around(frame, outset)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", Minimap, "TOPLEFT", -outset, outset)
    frame:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", outset, -outset)
end

local function drawLayout(layout, atlas, outset, scale)
    slices = slices or newFrame()
    slices:SetScale(scale)
    NineSliceUtil.ApplyLayout(slices, NineSliceUtil.GetLayout(layout))
    local info = C_Texture.GetAtlasInfo(atlas)
    around(slices, (info and info.width or 0) * outset)
    slices:Show()
end

local function drawBackdrop(style, scale)
    border = border or newFrame("BackdropTemplate")
    border:SetScale(scale)
    local backdrop = _G[style.backdrop or ""]
    border:SetBackdrop({
        edgeFile = type(backdrop) == "table" and backdrop.edgeFile or style.file,
        edgeSize = style.size,
    })
    around(border, style.outset)
    border:Show()
end

local function drawBorder()
    local style = squared and STYLES[module.db.border]
    if border then
        border:Hide()
    end
    if slices then
        slices:Hide()
    end
    if not style then
        return
    end
    local scale = module.db.borderScale / 100
    if style.faction then
        local faction = FACTION_LAYOUTS[UnitFactionGroup("player") or ""] or FACTION_LAYOUTS.Neutral
        drawLayout(faction.layout, faction.atlas, style.outset, scale)
    elseif style.layout then
        drawLayout(style.layout, style.atlas, style.outset, scale)
    else
        drawBackdrop(style, scale)
    end
end

-- The map's place -------------------------------------------------------------------------------
-- Blizzard centers the minimap in a container the size of its round frame (Camelot Minimap.lua's
-- UpdateMinimapConfig), so with the frame faded a band of nothing sat between the map and the
-- header row above it. The map moves to `gap` pixels from that row instead: below it, or above it
-- with Edit Mode's Header Underneath. Read from where the row is, so Edit Mode's scale and header
-- setting are already in it.

local mapMoved = false

-- The header row's frames: the zone name, the tracking button, and the calendar.
local function headerFrames()
    local cluster = MinimapCluster
    return { cluster.ZoneTextButton or false, cluster.Tracking or false, _G.GameTimeFrame or false }
end

local function placeMap()
    local container = MinimapCluster and MinimapCluster.MinimapContainer
    if not container then
        return
    end
    local cTop, cBottom = container:GetTop(), container:GetBottom()
    local zone = MinimapCluster.ZoneTextButton
    local zoneTop = zone and zone:GetTop()
    if not (squared and cTop and cBottom and zoneTop) then
        if mapMoved then
            mapMoved = false
            Minimap:ClearAllPoints()
            Minimap:SetPoint("CENTER", container, "CENTER")
        end
        return
    end
    local cScale, mScale = container:GetEffectiveScale(), Minimap:GetEffectiveScale()
    local middle = (cTop + cBottom) / 2 * cScale
    local under = zoneTop * zone:GetEffectiveScale() < middle
    local edge -- the row's edge nearest the map, on the screen
    for _, frame in ipairs(headerFrames()) do
        if frame and frame:IsShown() then
            local y = under and frame:GetTop() or frame:GetBottom()
            if y then
                y = y * frame:GetEffectiveScale()
                -- One beside the map rather than in the row (an addon moved it) doesn't count.
                local inRow = (under and y < middle) or (not under and y > middle)
                if inRow and (not edge or (under and y > edge) or (not under and y < edge)) then
                    edge = y
                end
            end
        end
    end
    if not edge then
        return
    end
    local gap = module.db.gap * mScale
    mapMoved = true
    Minimap:ClearAllPoints()
    if under then
        Minimap:SetPoint("BOTTOM", container, "BOTTOM", 0, (edge + gap - cBottom * cScale) / mScale)
    else
        Minimap:SetPoint("TOP", container, "TOP", 0, (edge - gap - cTop * cScale) / mScale)
    end
end

-- The sun -----------------------------------------------------------------------------------------
-- Camelot's day and night indicator (MinimapCluster.DielFrame, Camelot/Diel.lua) sits at a fixed
-- spot on the round frame, which a square one's edge doesn't reach, so it goes by the top right
-- corner instead. With its key held, it drags anywhere on or around the map, and stays there
-- (`sun`, from the map's middle); a right-click puts it back by the corner. Turned off, it goes
-- back to Blizzard's spot. Blizzard places it again when Edit Mode's scale changes, so that's hooked.

-- Where Blizzard puts it: from its container's middle, times the container's scale (Diel.lua's
-- DielFrameData and SetDielFrameTransform, wow-ui-source `forever` branch, checked 2026-11-09).
local SUN_X, SUN_Y = 55, 86
local SUN_REACH = 40 -- how far past the map's edge it can go, in the map's pixels
-- Where it goes on the square map until dragged: just past the top right corner, beside the
-- calendar, from that corner in the map's pixels (where the player put it in game, 2026-11-09).
local CORNER_X, CORNER_Y = 11, 5

local sunMoved = false
local handle -- our frame over the sun that takes the drag
local grabX, grabY -- the cursor's offset from the sun's middle when the drag began
local placeSun

local function sunFrame()
    return MinimapCluster and MinimapCluster.DielFrame
end

local function sunKeyDown()
    local key = module.db.sunKey
    return key ~= "off" and ns.Keys.IsDown(key)
end

-- The cursor, from the map's middle, in the map's pixels.
local function cursorOnMap()
    local x, y = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    local mx, my = Minimap:GetCenter()
    return x / scale - mx, y / scale - my
end

local function clamp(v, limit)
    return v < -limit and -limit or v > limit and limit or v
end

local function onDrag()
    local x, y = cursorOnMap()
    local limit = Minimap:GetWidth() / 2 + SUN_REACH
    local sun = module.db.sun
    sun.x = floor(clamp(x - grabX, limit) + 0.5)
    sun.y = floor(clamp(y - grabY, limit) + 0.5)
    placeSun()
end

local function stopDrag()
    if grabX then
        grabX, grabY = nil, nil
        handle:SetScript("OnUpdate", nil)
        placeSun()
    end
end

local function newHandle(sun)
    local frame = CreateFrame("Frame", nil, sun)
    frame:SetAllPoints(sun)
    frame:SetFrameLevel(sun:GetFrameLevel() + 1)
    frame:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" and sunKeyDown() then
            local x, y = cursorOnMap()
            local sx, sy = sun:GetCenter()
            local ratio = sun:GetEffectiveScale() / Minimap:GetEffectiveScale()
            local mx, my = Minimap:GetCenter()
            grabX, grabY = x - (sx * ratio - mx), y - (sy * ratio - my)
            frame:SetScript("OnUpdate", onDrag)
            GameTooltip:Hide()
        end
    end)
    frame:SetScript("OnMouseUp", function(_, button)
        if grabX then
            stopDrag()
        elseif button == "RightButton" then
            module.internal.ResetSun()
        end
    end)
    frame:SetScript("OnHide", stopDrag)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(L.SQUAREMINIMAP_SUN, 1, 1, 1)
        GameTooltip:AddLine(L.SQUAREMINIMAP_SUN_HINT, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", GameTooltip_Hide)
    return frame
end

-- The handle takes the mouse only while the key is held (or a drag goes on), so the map under the
-- sun still pings the rest of the time.
local function updateHandle()
    local sun = sunFrame()
    if not (squared and sun and module.db.sunKey ~= "off") then
        if handle then
            handle:Hide()
        end
        return
    end
    handle = handle or newHandle(sun)
    handle:Show()
    handle:EnableMouse(grabX ~= nil or sunKeyDown())
end

function placeSun()
    local sun = sunFrame()
    if not sun then
        return
    end
    local saved = module.db.sun
    if squared then
        local half = Minimap:GetWidth() / 2
        local x, y = saved.x or half + CORNER_X, saved.y or half + CORNER_Y
        local ratio = Minimap:GetEffectiveScale() / sun:GetEffectiveScale()
        sunMoved = true
        sun:ClearAllPoints()
        sun:SetPoint("CENTER", Minimap, "CENTER", x * ratio, y * ratio)
    elseif sunMoved then
        sunMoved = false
        local scale = MinimapCluster.MinimapContainer:GetScale()
        sun:ClearAllPoints()
        sun:SetPoint("CENTER", SUN_X * scale, SUN_Y * scale)
    end
    updateHandle()
end

---Puts the sun back by the top right corner.
function module.internal.ResetSun()
    wipe(module.db.sun)
    placeSun()
end

module:OnWhile(function(db) return db.sunKey ~= "off" end, {
    MODIFIER_STATE_CHANGED = updateHandle,
})

-- The mail icon -----------------------------------------------------------------------------------
-- Blizzard hangs it under the zone name's left end (MinimapCluster.IndicatorFrame, a 32 by 24 row
-- with the icon at its top left: Camelot's MinimapIndicatorFrameTemplate.xml and
-- MinimapMailFrameTemplate.xml, wow-ui-source `forever` branch), which on the square map is over
-- its top edge. It goes in a corner of the map instead, clear of the border, and back to
-- Blizzard's place when the module or the option says so. Blizzard places it again with Edit
-- Mode's Header Underneath, so its place is read again after that.

local MAIL_INSET = 10 -- from the map's corner to the icon, in the indicator's pixels
local MAIL_CORNERS = { -- the option's value -> the point, and which way is in
    topleft = { "TOPLEFT", 1, -1 },
    topright = { "TOPRIGHT", -1, -1 },
    bottomleft = { "BOTTOMLEFT", 1, 1 },
    bottomright = { "BOTTOMRIGHT", -1, 1 },
}
local mailHome -- Blizzard's anchors for it, while it's in a corner

local function placeMail()
    local frame = MinimapCluster and MinimapCluster.IndicatorFrame
    if not frame then
        return
    end
    local corner = squared and MAIL_CORNERS[module.db.mail]
    if not corner then
        if mailHome then
            ns.Frames.SetPoints(frame, mailHome)
            mailHome = nil
        end
        return
    end
    mailHome = mailHome or ns.Frames.GetPoints(frame)
    -- The icon is at the row's top left, so the row's empty right and bottom hang past the corner.
    local icon = frame.MailFrame and frame.MailFrame.MailIcon
    local spareX = icon and frame:GetWidth() - icon:GetWidth() or 0
    local spareY = icon and frame:GetHeight() - icon:GetHeight() or 0
    local point, inX, inY = corner[1], corner[2], corner[3]
    frame:ClearAllPoints()
    frame:SetPoint(point, Minimap, point, inX * MAIL_INSET + (inX < 0 and spareX or 0),
        inY * MAIL_INSET - (inY > 0 and spareY or 0))
end


-- Squares the minimap while the module is on (again after Blizzard set its own mask, as it does
-- when Rotate Minimap changes), or puts Blizzard's round mask and frame back. Another addon that
-- has taken over the shape is left to it.
local function update()
    local other = otherShape()
    local want = module.enabled and not other
    local was = squared
    if want then
        Minimap:SetMaskTexture(SQUARE_MASK)
        setArt(0)
        _G.GetMinimapShape = getShape
    elseif was and not other then
        Minimap:SetMaskTexture(ns.Frames.HasAtlas(ROUND_MASK_ATLAS) and ROUND_MASK_ATLAS or ROUND_MASK_FILE)
        setArt(1)
        _G.GetMinimapShape = nil
    end
    squared = want
    drawBorder()
    placeMap()
    placeSun()
    placeMail()
    if want ~= was then
        ns.MinimapPins.ShapeChanged()
    end
end

-- Nothing here is Blizzard's code or a secure frame, but the minimap is part of the HUD, so a
-- change waits out combat rather than risk it.
local function refresh()
    ns.AfterCombat(update)
end

-- After Blizzard put the header and the mail icon in their own places again
-- (SetHeaderUnderneath): that's the icon's home now.
local function onHeaderMoved()
    mailHome = nil
    refresh()
end

-- Blizzard pings only inside the round minimap (MinimapMixin:OnClick); a click in a corner, on
-- the map now too, pings there.
local function onMouseUp()
    if not squared then
        return
    end
    local right, up = ns.MinimapPins.CursorOffset()
    local half = Minimap:GetWidth() / 2
    if right * right + up * up >= half * half and abs(right) < half and abs(up) < half then
        Minimap:PingLocation(right, up)
    end
end

function module:OnEnable()
    if MinimapCluster then
        -- Each puts Blizzard's mask, the map, or the sun back in place (Camelot Minimap.lua, Diel.lua).
        self:Hook(MinimapCluster, "UpdateMinimapConfig", refresh)
        self:Hook(MinimapCluster, "SetHeaderUnderneath", onHeaderMoved)
        self:Hook(MinimapCluster, "SetEditModeScale", refresh)
    end
    self:HookScript(Minimap, "OnMouseUp", onMouseUp)
    refresh()
end

function module:OnDisable()
    refresh()
end

function module:OnOptionChanged(key)
    if key == "border" or key == "borderScale" then
        drawBorder()
    elseif key == "gap" then
        ns.AfterCombat(placeMap)
    elseif key == "sunKey" then
        updateHandle()
    elseif key == "mail" then
        ns.AfterCombat(placeMail)
    end
end
