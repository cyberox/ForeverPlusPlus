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
    border = "tooltip", -- tooltip, dialog, or none
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

-- The borders: Blizzard's own backdrop (its file if the backdrop's gone) at an edge size that
-- suits the minimap, and how far past the minimap the frame sits so the art's line lies on the
-- minimap's edge.
local BORDERS = {
    tooltip = { backdrop = "BACKDROP_TOOLTIP_16_16_5555", file = "Interface\\Tooltips\\UI-Tooltip-Border",
        size = 16, outset = 4 },
    dialog = { backdrop = "BACKDROP_DIALOG_32_32", file = "Interface\\DialogFrame\\UI-DialogBox-Border",
        size = 16, outset = 5 },
}

module.options = {
    {
        key = "border",
        name = L.SQUAREMINIMAP_BORDER,
        description = L.SQUAREMINIMAP_BORDER_DESC,
        choices = {
            { "tooltip", L.SQUAREMINIMAP_BORDER_TOOLTIP },
            { "dialog", L.SQUAREMINIMAP_BORDER_DIALOG },
            { "none", L.SQUAREMINIMAP_BORDER_NONE },
        },
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

local function drawBorder()
    local style = squared and BORDERS[module.db.border]
    if not style then
        if border then
            border:Hide()
        end
        return
    end
    if not border then
        border = CreateFrame("Frame", nil, Minimap, "BackdropTemplate")
        -- Over the map, under the icons and buttons addons put on it (ours sit 4 and more up).
        border:SetFrameLevel(Minimap:GetFrameLevel() + 2)
    end
    local backdrop = _G[style.backdrop]
    border:SetBackdrop({
        edgeFile = type(backdrop) == "table" and backdrop.edgeFile or style.file,
        edgeSize = style.size,
    })
    border:ClearAllPoints()
    border:SetPoint("TOPLEFT", Minimap, "TOPLEFT", -style.outset, style.outset)
    border:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", style.outset, -style.outset)
    border:Show()
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
    if key == "border" then
        drawBorder()
    end
end
