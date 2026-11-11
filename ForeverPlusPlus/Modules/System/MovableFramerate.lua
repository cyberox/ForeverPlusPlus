-- Movable Framerate: Blizzard's framerate text (Ctrl+R) can be moved and resized in Edit Mode, like
-- Blizzard's own frames. On Forever FramerateFrame sits in the bottom-right corner of WorldFrame
-- (its XML anchor; FramerateFrameMixin:UpdatePosition is a no-op there, while Retail's moves it
-- beside the micro menu), and Edit Mode has no system for it, so a frame of ours stands in for it
-- in Edit Mode: until the player moves it, ours follows Blizzard's text; once moved, the text
-- follows ours. The text changes width as the number changes, so it is anchored by the edge
-- nearest the side of the screen it's on.
local _, ns = ...

local format, max = string.format, math.max
local CreateFrame, UIParent = CreateFrame, UIParent

local L = ns.L

local module = ns.NewModule("MovableFramerate", L.MOVABLEFRAMERATE_DESC, {
    enabled = false,
    moved = false, -- false while the text stays where Blizzard puts it
    x = 0, -- its offset from the center of the screen, once moved
    y = 0,
    scale = 100, -- percent
})
module.title = L.MOVABLEFRAMERATE_TITLE
module.category = "interface"

local ADDON = "Blizzard_FramerateFrame"
local SAMPLE = 144 -- a wide framerate, to size the Edit Mode box

local holder -- our frame: the Edit Mode box, and what the text follows once moved
local baseScale -- the text's own scale before ours
local original -- Blizzard's anchor points for the text, for when the micro menu can't give it back
local ready = false -- true while the module is on and Blizzard's text is there

-- The point the text and its box line up on: Blizzard's own corner until moved, then the edge
-- toward the side of the screen the box is on, so a changing number grows away from that edge.
local function point()
    if not module.db.moved then
        return (FramerateFrame:GetPoint(1)) or "CENTER"
    end
    local cx = holder:GetCenter()
    if cx and cx > UIParent:GetWidth() / 2 then
        return "RIGHT"
    end
    return "LEFT"
end

-- Sizes the box to the text at its scale, and lines up the text, the box, and the sample.
local function layout()
    if not ready then
        return
    end
    local ratio = FramerateFrame:GetEffectiveScale() / holder:GetEffectiveScale()
    holder.inner:SetScale(ratio)
    -- Text measured before its font has loaded reads as 0 tall on Forever: floor it at the size.
    local _, size = holder.sample:GetFont()
    holder:SetSize(max(holder.sample:GetStringWidth(), 1) * ratio,
        max(holder.sample:GetStringHeight(), size or 12) * ratio)
    local at = point()
    if module.db.moved then
        FramerateFrame:ClearAllPoints()
        FramerateFrame:SetPoint(at, holder, at)
    else
        holder:ClearAllPoints()
        holder:SetPoint(at, FramerateFrame, at)
    end
    holder.sample:ClearAllPoints()
    holder.sample:SetPoint(at)
end

local function applyScale()
    FramerateFrame:SetScale(baseScale * module.db.scale / 100)
    layout()
end

-- Puts the text back where Blizzard had it, then lets the micro menu place it, as Retail's does
-- (on Forever that does nothing).
local function restoreAnchor()
    if original then
        ns.Frames.SetPoints(FramerateFrame, original)
    end
    if MicroMenu and MicroMenu.UpdateFramerateFrameAnchor and MicroMenuContainer
        and MicroMenuContainer.GetPosition then
        MicroMenu:UpdateFramerateFrameAnchor(MicroMenuContainer:GetPosition())
    end
end

-- In Edit Mode the box shows a sample framerate while Blizzard's text is off.
local function showSample(active)
    if holder then
        layout() -- the font has surely loaded by now, so measure again
        holder.sample:SetShown(active and not FramerateFrame:IsShown())
    end
end

local function updateSample()
    showSample(ns.EditMode.IsActive())
end

local function newHolder()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(1, 1)
    -- The sample sits in a child at the text's scale, so the box's own size and position stay in
    -- screen units for Edit Mode.
    f.inner = CreateFrame("Frame", nil, f)
    f.inner:SetAllPoints()
    f.sample = f.inner:CreateFontString(nil, "ARTWORK", "SystemFont_Shadow_Med1")
    f.sample:SetText((FRAMERATE_LABEL or "") .. format("%.1f", SAMPLE))
    f.sample:Hide()
    return f
end

-- Edit Mode ---------------------------------------------------------------------------------------

local function moved(x, y)
    module.db.moved, module.db.x, module.db.y = true, x, y
    layout()
end

local function resetPosition()
    module.db.moved, module.db.x, module.db.y = nil, nil, nil -- forgotten: back where Blizzard puts it
    if ready then
        restoreAnchor()
        layout()
    end
end

local editModeOptions = {
    onChange = showSample,
    reset = resetPosition,
    scale = {
        min = 50, max = 200, step = 10, format = "%d%%",
        get = function() return module.db.scale end,
        set = function(value)
            module.db.scale = value
            if ready then
                applyScale()
            end
        end,
    },
}

local function setup()
    if not FramerateFrame or not module.enabled then
        return
    end
    holder = holder or newHolder()
    baseScale = baseScale or FramerateFrame:GetScale()
    if not original then
        local points = ns.Frames.GetPoints(FramerateFrame)
        if points[1] then
            original = points
        end
    end
    ready = true
    holder:Show()
    if module.db.moved then
        ns.EditMode.Place(holder, module.db.x, module.db.y)
    end
    applyScale()
    -- Blizzard places the text again whenever the micro menu lays itself out.
    module:Hook(FramerateFrame, "UpdatePosition", layout)
    module:HookScript(FramerateFrame, "OnShow", updateSample)
    module:HookScript(FramerateFrame, "OnHide", updateSample)
    module:On("UI_SCALE_CHANGED", layout)
    module:On("DISPLAY_SIZE_CHANGED", layout)
    ns.EditMode.Register(holder, L.MOVABLEFRAMERATE_TITLE, moved, editModeOptions)
end

function module:OnEnable()
    ns.AddOns.WhenLoaded(ADDON, setup)
end

function module:OnDisable()
    ns.AddOns.Cancel(ADDON, setup)
    if not ready then
        return
    end
    ready = false
    ns.EditMode.Unregister(holder)
    holder.sample:Hide()
    holder:ClearAllPoints()
    holder:Hide()
    FramerateFrame:SetScale(baseScale)
    restoreAnchor()
end
