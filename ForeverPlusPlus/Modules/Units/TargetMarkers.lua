-- Target Markers: hold a key and a ring of the eight raid icons opens at the cursor, as the game's
-- ping wheel does; point toward one and let go to mark your target with it, or let go in the middle
-- to clear the mark. Holding Shift as you let go places that icon as a world marker instead, which
-- the game then has you put on the ground (or, in the middle, clears every world marker). The key
-- is in Blizzard's Key Bindings (Bindings.xml, under Forever++).
--
-- It works in combat: the ring and its key are secure. The key clicks a secure action button, and
-- a snippet wrapped around that click (SecureHandlerWrapScript) opens the ring at the cursor on
-- the key going down, and on it coming up works out the icon from the mouse's direction (and Shift
-- from IsShiftKeyDown, which secure code may read) and lets the button do Blizzard's own
-- `raidtarget` or `worldmarker` action with it (SecureTemplates.lua). Nothing here marks anything
-- itself or touches Blizzard's frames. What the ring looks like while it's open (the pointer, the
-- icon pointed at, its name) is drawn by plain code, the same way, so the two always agree.
local _, ns = ...

local ipairs, format, floor = ipairs, string.format, math.floor
local atan2, deg, rad, cos, sin = math.atan2, math.deg, math.rad, math.cos, math.sin
local CreateFrame, GetCursorPosition, GetBindingKey = CreateFrame, GetCursorPosition, GetBindingKey
local IsShiftKeyDown, IsInGroup = IsShiftKeyDown, IsInGroup

local L = ns.L

local module = ns.NewModule("TargetMarkers", L.TARGETMARKERS_DESC, {
    enabled = false,
    mouseover = true, -- the unit under the mouse becomes the target first, so it's the one marked
    scale = 100, -- the ring's size, in percent
})
module.title = L.TARGETMARKERS_TITLE
module.category = "units"
module.added = "1.3.0"

-- The button the key clicks, named for its binding in Bindings.xml.
local BUTTON = "ForeverPlusPlusMarkerButton"
local BINDING = "CLICK " .. BUTTON .. ":LeftButton"

-- Blizzard's Key Bindings read these names when it lists Bindings.xml's keys.
BINDING_HEADER_FOREVERPLUSPLUS = ns.title
_G["BINDING_NAME_" .. BINDING] = L.TARGETMARKERS_BINDING

local function openKeyBindings()
    if Settings and Settings.OpenToCategory and Settings.KEYBINDINGS_CATEGORY_ID then
        Settings.OpenToCategory(Settings.KEYBINDINGS_CATEGORY_ID)
    end
end

module.notice = {
    {
        text = L.TARGETMARKERS_NO_KEY, description = L.TARGETMARKERS_NO_KEY_DESC,
        button = L.TARGETMARKERS_BIND, fn = openKeyBindings,
        shown = function() return module.db.enabled and not GetBindingKey(BINDING) end,
    },
}

module.options = {
    { key = "mouseover", name = L.TARGETMARKERS_MOUSEOVER, description = L.TARGETMARKERS_MOUSEOVER_DESC },
    {
        key = "scale", name = L.TARGETMARKERS_SCALE, description = L.TARGETMARKERS_SCALE_DESC,
        min = 50, max = 200, step = 10, format = "%d%%",
    },
}

-- The ring ----------------------------------------------------------------------------------------

-- Blizzard's radial wheel, which the ping wheel is made of (Blizzard_SharedXML/Blizzard_RadialWheel
-- .lua and .xml, `forever` branch): its background, pointer, the dividers and the picked wedge's
-- glow for its number of wedges, and the middle's close icon and the ring around it when picked.
local ATLAS_BACKGROUND = "Radial_Wheel_BG"
local ATLAS_POINTER = "Radial_Wheel_Select_Pointer"
local ATLAS_DIVIDERS = "Radial_Wheel_Frame_Count_8"
-- The ping wheel's four dividers, an X: two of them turned 22.5 degrees each way are eight.
local ATLAS_DIVIDERS_4 = "Radial_Wheel_Frame_Count_4"
local ATLAS_PICKED = "Radial_Wheel_Select_Wedge_Count_8"
-- The ping wheel's gold glow for a quarter of the wheel, pointing right. Forever has no eighth, so
-- it's squeezed to one: its width across the wedge to tan(22.5)/tan(45) of itself.
local ATLAS_PICKED_4 = "Radial_Wheel_Select_Wedge_Count_4"
local SQUEEZE = 0.414
-- Where the wheel puts the glow's middle: its wedge's spot (80) and 20 more outward, in the
-- wheel's own pixels (RadialWheelFrameMixin:SetupRadialWedgeButtons).
local GLOW_REACH = 100
local ATLAS_CLOSE = "Radial_Wheel_Icon_Close"
local ATLAS_CLOSE_PICKED = "Radial_Wheel_Select_Close"
local ATLAS_CLOSE_FALLBACK = "common-icon-redx"
local ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_%d"

local SIZE = 300 -- the wheel's size when its atlas is missing
-- Icons are drawn at this size and shrink to 90% while not picked, as the wheel's own do, and so do
-- their names, in the wheel's font (RadialWheelButtonTemplate's Text: Game18Font).
local ICON_SIZE, UNPICKED = 48, 0.9
local NAME_FONT, NAME_FALLBACK = "Game18Font", "GameFontHighlightLarge"
-- Where the icons sit and how far the middle reaches, as shares of the wheel's size.
local RADIUS, MIDDLE = 0.35, 0.12
-- The divider lines drawn when the client has no eight-wedge dividers (Forever has only the ping
-- wheel's four): solid and dark like those, from the middle's ring out past the icons.
local LINE_COLOR = { 0.32, 0.29, 0.25, 0.9 }
local LINE_FROM, LINE_TO, LINE_WIDTH = 0.1, 0.52, 2
-- The area the mouse's direction is read in (the ring frame), centered on the wheel. Wider than
-- the wheel, so pointing well past an icon still picks it; the mouse farther out than this cancels.
local REACH = 1600

-- The raid icons, 1 to 8, go clockwise from the top: star, circle, diamond, triangle, moon, square,
-- cross, skull. World markers number them differently (Blizzard's WORLD_MARKER order), so each
-- place maps to its marker.
local WORLD_IDS = "56327148"

-- The icon at the mouse's offset (dx, dy) from the middle: 0 for the middle, else 1 to 8.
local function placeAt(dx, dy, middle)
    if dx * dx + dy * dy <= middle * middle then
        return 0
    end
    local angle = (90 - deg(atan2(dy, dx))) % 360
    return floor((angle + 22.5) / 45) % 8 + 1
end

-- The secure side of the key: down opens the ring at the cursor (and targets what's under the
-- mouse first, with that option on); up reads the place pointed at, closes the ring, and lets the
-- button do the action, a world marker with Shift held. The same arithmetic as `placeAt`, in
-- Blizzard's restricted Lua, where `control` is the ring. A key coming down while the ring is open
-- (its key-up was missed) only closes it.
local SNIPPET = [[
    local ring = control
    if not self:GetAttribute("on") then
        ring:Hide()
        return false
    end
    if down then
        if ring:IsShown() then
            ring:Hide()
            return false
        end
        ring:ClearAllPoints()
        ring:SetPoint("CENTER", "$cursor")
        ring:Show()
        if self:GetAttribute("mouseover") and SecureCmdOptionParse("[@mouseover,exists] 1") == "1" then
            self:SetAttribute("useOnKeyDown", true)
            self:SetAttribute("type", "target")
            self:SetAttribute("unit", "mouseover")
            return
        end
        return false
    end
    if not ring:IsShown() then
        return false
    end
    local fx, fy = ring:GetMousePosition()
    ring:Hide()
    if not fx then
        return false
    end
    local reach, middle = %d, %f * ring:GetAttribute("wheel")
    local dx, dy = (fx - 0.5) * reach, (fy - 0.5) * reach
    local place = 0
    if dx * dx + dy * dy > middle * middle then
        local angle = (90 - math.deg(math.atan2(dy, dx))) %% 360
        place = math.floor((angle + 22.5) / 45) %% 8 + 1
    end
    self:SetAttribute("useOnKeyDown", false)
    self:SetAttribute("action", place > 0 and "set" or "clear")
    if IsShiftKeyDown() then
        self:SetAttribute("type", "worldmarker")
        self:SetAttribute("marker", place > 0 and tonumber(strsub("%s", place, place)) or nil)
    else
        self:SetAttribute("type", "raidtarget")
        self:SetAttribute("unit", "target")
        self:SetAttribute("marker", place > 0 and place or nil)
    end
]]

local ring -- { frame, button, icons, names, angles, close, closePicked, glow, pointer, label, hint, wheel }

-- What the line under the wheel says: only with Shift, which makes it a world marker (the ping
-- wheel has no line, and each icon's own name is beside it).
local function underText(place, world)
    if not world then
        return ""
    end
    if place == 0 then
        return L.TARGETMARKERS_CLEAR_ALL
    end
    return format(L.TARGETMARKERS_ON_GROUND, _G["RAID_TARGET_" .. place] or "")
end

-- While the ring is open: the pointer toward the mouse, and the icon it picks at full size with its
-- glow (the others at 90%, as the wheel's own), or the middle's ring. Plain code on our own
-- frames' textures, which it may change in combat.
local function drawPicked(frame)
    local scale = frame:GetEffectiveScale()
    local x, y = GetCursorPosition()
    local cx, cy = frame:GetCenter()
    if not cx then
        return
    end
    local dx, dy = x / scale - cx, y / scale - cy
    local place = placeAt(dx, dy, MIDDLE * ring.wheel)
    local world = IsShiftKeyDown() and true or false
    if place > 0 then
        ring.pointer:SetRotation(atan2(dy, dx))
    end
    if place == ring.place and world == ring.world then
        return
    end
    ring.place, ring.world = place, world
    for i, icon in ipairs(ring.icons) do
        local picked = i == place
        local size = picked and ICON_SIZE or ICON_SIZE * UNPICKED
        icon:SetSize(size, size)
        ring.names[i]:SetScale(picked and 1 or UNPICKED)
    end
    ring.closePicked:SetShown(place == 0 and ring.hasClosePicked)
    ring.pointer:SetShown(place > 0 and ring.hasPointer)
    if ring.glow then
        ring.glow:SetShown(place > 0)
        if place > 0 then
            local angle = ring.angles[place]
            ring.glow:ClearAllPoints()
            ring.glow:SetPoint("CENTER", cos(angle) * GLOW_REACH, sin(angle) * GLOW_REACH)
            ring.glow:SetRotation(angle)
        end
    end
    ring.label:SetText(underText(place, world))
end

-- An icon's name beside it, on the side away from the middle, as the wheel places its own. The
-- wheel's icon art has room around it and the raid icons fill theirs, so the gaps make up for it.
local NAME_GAP_SIDE, NAME_GAP_END = 18, 12
local function placeName(name, icon, angle)
    local quarter = math.pi / 4
    name:ClearAllPoints()
    if angle > quarter + 0.01 and angle < 3 * quarter - 0.01 then
        name:SetPoint("BOTTOM", icon, "TOP", 0, NAME_GAP_END)
    elseif angle >= 3 * quarter - 0.01 and angle <= 5 * quarter + 0.01 then
        name:SetPoint("RIGHT", icon, "LEFT", -NAME_GAP_SIDE, 0)
    elseif angle > 5 * quarter + 0.01 and angle < 7 * quarter - 0.01 then
        name:SetPoint("TOP", icon, "BOTTOM", 0, -NAME_GAP_END)
    else
        name:SetPoint("LEFT", icon, "RIGHT", NAME_GAP_SIDE, 0)
    end
end

-- The lines between wedges, drawn when the client has no eight-wedge dividers to show.
local function drawDividers(art, wheel)
    for k = 0, 7 do
        local angle = rad(90 - 22.5 - k * 45)
        local line = art:CreateLine(nil, "BORDER")
        local r, g, b, a = LINE_COLOR[1], LINE_COLOR[2], LINE_COLOR[3], LINE_COLOR[4]
        -- Fading out toward the edge as the wheel's own do; a line's gradient runs along it.
        if line.SetGradient and CreateColor then
            line:SetColorTexture(1, 1, 1, 1)
            line:SetGradient("HORIZONTAL", CreateColor(r, g, b, a), CreateColor(r, g, b, 0))
        else
            line:SetColorTexture(r, g, b, a)
        end
        line:SetThickness(LINE_WIDTH)
        line:SetStartPoint("CENTER", art, cos(angle) * LINE_FROM * wheel, sin(angle) * LINE_FROM * wheel)
        line:SetEndPoint("CENTER", art, cos(angle) * LINE_TO * wheel, sin(angle) * LINE_TO * wheel)
    end
end

local function buildRing()
    local frame = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
    frame:SetSize(REACH, REACH)
    frame:SetFrameStrata("DIALOG")
    frame:Hide()
    ring = { frame = frame, icons = {}, names = {}, angles = {} }

    -- The wheel's art, at its own size; the ring frame around it is only the area read.
    local art = CreateFrame("Frame", nil, frame)
    art:SetPoint("CENTER")
    local background = art:CreateTexture(nil, "BACKGROUND")
    background:SetPoint("CENTER")
    local wheel = SIZE
    if ns.Frames.HasAtlas(ATLAS_BACKGROUND) then
        background:SetAtlas(ATLAS_BACKGROUND, true)
        wheel = background:GetWidth()
    end
    ring.wheel = wheel
    art:SetSize(wheel, wheel)
    frame:SetAttribute("wheel", wheel)

    ring.pointer = art:CreateTexture(nil, "OVERLAY", nil, 2)
    ring.pointer:SetPoint("CENTER")
    ring.hasPointer = ns.Frames.HasAtlas(ATLAS_POINTER)
    if ring.hasPointer then
        ring.pointer:SetAtlas(ATLAS_POINTER, true)
    end
    ring.pointer:Hide()

    -- Between the wedges: the wheel's own eight-wedge dividers, or the ping wheel's four twice, or
    -- lines like them.
    if ns.Frames.HasAtlas(ATLAS_DIVIDERS) then
        local dividers = art:CreateTexture(nil, "BORDER")
        dividers:SetPoint("CENTER")
        dividers:SetAtlas(ATLAS_DIVIDERS, true)
    elseif ns.Frames.HasAtlas(ATLAS_DIVIDERS_4) then
        for _, turn in ipairs({ 22.5, -22.5 }) do
            local dividers = art:CreateTexture(nil, "BORDER")
            dividers:SetPoint("CENTER")
            dividers:SetAtlas(ATLAS_DIVIDERS_4, true)
            dividers:SetRotation(rad(turn))
        end
    else
        drawDividers(art, wheel)
    end
    -- The picked wedge's gold glow: the wheel's for eight wedges, or its quarter one squeezed.
    if ns.Frames.HasAtlas(ATLAS_PICKED) then
        ring.glow = art:CreateTexture(nil, "ARTWORK", nil, -1)
        ring.glow:SetAtlas(ATLAS_PICKED, true)
        ring.glow:Hide()
    elseif ns.Frames.HasAtlas(ATLAS_PICKED_4) then
        ring.glow = art:CreateTexture(nil, "ARTWORK", nil, -1)
        ring.glow:SetAtlas(ATLAS_PICKED_4, true)
        ring.glow:SetHeight(ring.glow:GetHeight() * SQUEEZE)
        ring.glow:Hide()
    end

    for i = 1, 8 do
        local icon = art:CreateTexture(nil, "ARTWORK")
        icon:SetTexture(ICON:format(i))
        icon:SetSize(ICON_SIZE * UNPICKED, ICON_SIZE * UNPICKED)
        local angle = rad(90 - (i - 1) * 45) % (2 * math.pi)
        icon:SetPoint("CENTER", cos(angle) * RADIUS * wheel, sin(angle) * RADIUS * wheel)
        local name = art:CreateFontString(nil, "OVERLAY", _G[NAME_FONT] and NAME_FONT or NAME_FALLBACK)
        name:SetText(_G["RAID_TARGET_" .. i] or "")
        name:SetScale(UNPICKED)
        placeName(name, icon, angle)
        ring.icons[i], ring.names[i], ring.angles[i] = icon, name, angle
    end

    -- The middle: the wheel's close icon, ringed while picked.
    local close = art:CreateTexture(nil, "ARTWORK")
    close:SetPoint("CENTER")
    if ns.Frames.HasAtlas(ATLAS_CLOSE) then
        close:SetAtlas(ATLAS_CLOSE, true)
    else
        close:SetAtlas(ATLAS_CLOSE_FALLBACK)
        close:SetSize(ICON_SIZE * 0.6, ICON_SIZE * 0.6)
    end
    ring.closePicked = art:CreateTexture(nil, "ARTWORK", nil, -1)
    ring.closePicked:SetPoint("CENTER")
    ring.hasClosePicked = ns.Frames.HasAtlas(ATLAS_CLOSE_PICKED)
    if ring.hasClosePicked then
        ring.closePicked:SetAtlas(ATLAS_CLOSE_PICKED, true)
    end
    ring.closePicked:Hide()

    ring.label = art:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ring.label:SetPoint("TOP", art, "BOTTOM", 0, -2)
    -- In a group, where world markers work: how to place one.
    ring.hint = art:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ring.hint:SetPoint("TOP", ring.label, "BOTTOM", 0, -2)
    ring.hint:SetText(L.TARGETMARKERS_SHIFT_HINT)

    -- Fading in over 0.2 seconds as the wheel does (its IntroAnim), on our own art frame.
    local intro = art:CreateAnimationGroup()
    intro:SetToFinalAlpha(true)
    local fade = intro:CreateAnimation("Alpha")
    fade:SetFromAlpha(0)
    fade:SetToAlpha(1)
    fade:SetDuration(0.2)

    frame:SetScript("OnShow", function(self)
        ring.place, ring.world = nil, nil
        ring.hint:SetShown(IsInGroup() and true or false)
        drawPicked(self)
        intro:Restart()
    end)
    frame:SetScript("OnUpdate", drawPicked)

    -- The key's button. Its action is set by the snippet on each press.
    local button = CreateFrame("Button", BUTTON, UIParent, "SecureActionButtonTemplate")
    button:RegisterForClicks("AnyDown", "AnyUp")
    frame:WrapScript(button, "OnClick", format(SNIPPET, REACH, MIDDLE, WORLD_IDS))
    ring.button = button
end

-- Settings into the secure frames, which only happens out of combat.
local function apply()
    ns.AfterCombat(function()
        local on = module.enabled
        if on and not ring then
            buildRing()
        end
        if not ring then
            return
        end
        ring.button:SetAttribute("on", on)
        ring.button:SetAttribute("mouseover", module.db.mouseover)
        ring.frame:SetScale(module.db.scale / 100)
        if not on then
            ring.frame:Hide()
        end
    end)
end

function module:OnEnable()
    apply()
end

function module:OnDisable()
    apply()
end

function module:OnOptionChanged()
    apply()
end
