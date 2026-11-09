-- Square Minimap: makes Blizzard's minimap square. Its round mask becomes a square one, its round
-- frame fades out, and a border in Blizzard's tooltip or dialog art goes around it. While it's
-- on, the global GetMinimapShape answers "SQUARE": the convention minimap button libraries
-- (LibDBIcon) and Lib/MinimapPins.lua read, so buttons on the edge and our icons on the minimap
-- follow the square. Turned off, the round mask and frame come back. An addon that already shapes
-- the minimap (its own GetMinimapShape) is left to it.
local _, ns = ...

local _G, type, ipairs, abs = _G, type, ipairs, math.abs
local CreateFrame = CreateFrame

local L = ns.L

local module = ns.NewModule("SquareMinimap", L.SQUAREMINIMAP_DESC, {
    enabled = false,
    border = "window", -- a BORDERS key, or none; set below to one this client has
    borderScale = 100, -- the border art's size, in percent
})
module.title = L.SQUAREMINIMAP_TITLE
module.category = "map"
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
--   offsets for it (Camelot/NineSliceLayoutOverrides.lua) come with it. Window is the frame of the
--   game's windows, ours among them. Faction is the Alliance or Horde mission table frame by the
--   player's side, and Wood for anyone else. `atlas` is one of its pieces, to check this client
--   has it. The frame's pieces lie inside it, so it sits `outset` of its edge's width past the
--   minimap, which puts the middle of the line on the minimap's edge.
-- - `file`: a backdrop edge file at an edge size that suits the minimap, `outset` pixels past it.
--   `backdrop` is the global Blizzard keeps it in, read first in case a patch moves the file.
local BORDERS = {
    { "window", L.SQUAREMINIMAP_BORDER_WINDOW, layout = "ButtonFrameTemplateNoPortrait",
        atlas = "!UI-Frame-Metal-EdgeLeft", outset = 0.5 },
    { "panel", L.SQUAREMINIMAP_BORDER_PANEL, layout = "SimplePanelTemplate",
        atlas = "!UI-Frame-SimpleMetal-EdgeLeft", outset = 0.5 },
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
    { "gold", L.SQUAREMINIMAP_BORDER_GOLD, backdrop = "BACKDROP_GOLD_DIALOG_32_32",
        file = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border", size = 16, outset = 5 },
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
-- The window frame, the one Forever draws its windows in, when it's there.
module.defaults.border = STYLES.window and "window" or STYLES.dialog and "dialog" or "none"

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
}

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
    if want ~= was then
        ns.MinimapPins.ShapeChanged()
    end
end

-- Nothing here is Blizzard's code or a secure frame, but the minimap is part of the HUD, so a
-- change waits out combat rather than risk it.
local function refresh()
    ns.AfterCombat(update)
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
        self:Hook(MinimapCluster, "UpdateMinimapConfig", refresh)
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
    end
end
