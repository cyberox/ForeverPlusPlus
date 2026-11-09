-- Target Markers: hold a key and a ring of the eight raid icons opens at the cursor, as the game's
-- ping wheel does; point toward one and let go to mark your target with it, or let go in the middle
-- to clear the mark. A second key does the same with world markers, which the game then has you
-- place on the ground. The keys are in Blizzard's Key Bindings (Bindings.xml, under Forever++).
--
-- It works in combat: the ring and its keys are secure. Each key clicks a secure action button,
-- and a snippet wrapped around that click (SecureHandlerWrapScript) opens the ring at the cursor
-- on the key going down, and on it coming up works out the icon from the mouse's direction and
-- lets the button do Blizzard's own `raidtarget` or `worldmarker` action with it
-- (SecureTemplates.lua). Nothing here marks anything itself or touches Blizzard's frames. What
-- the ring looks like while it's open (the pointer, the icon pointed at, its name) is drawn by
-- plain code, the same way, so the two always agree.
local _, ns = ...

local ipairs, pairs, format, floor = ipairs, pairs, string.format, math.floor
local atan2, deg, rad, cos, sin = math.atan2, math.deg, math.rad, math.cos, math.sin
local CreateFrame, GetCursorPosition, GetBindingKey = CreateFrame, GetCursorPosition, GetBindingKey

local L = ns.L

local module = ns.NewModule("TargetMarkers", L.TARGETMARKERS_DESC, {
    enabled = false,
    mouseover = true, -- the unit under the mouse becomes the target first, so it's the one marked
    scale = 100, -- the ring's size, in percent
})
module.title = L.TARGETMARKERS_TITLE
module.category = "units"
module.added = "1.3.0"

-- The buttons the keys click, named for their bindings in Bindings.xml.
local MARK_BUTTON, WORLD_BUTTON = "ForeverPlusPlusMarkerButton", "ForeverPlusPlusWorldMarkerButton"
local MARK_BINDING = "CLICK " .. MARK_BUTTON .. ":LeftButton"
local WORLD_BINDING = "CLICK " .. WORLD_BUTTON .. ":LeftButton"

-- Blizzard's Key Bindings read these names when it lists Bindings.xml's keys.
BINDING_HEADER_FOREVERPLUSPLUS = ns.title
_G["BINDING_NAME_" .. MARK_BINDING] = L.TARGETMARKERS_BINDING_MARK
_G["BINDING_NAME_" .. WORLD_BINDING] = L.TARGETMARKERS_BINDING_WORLD

local function anyKey()
    return GetBindingKey(MARK_BINDING) or GetBindingKey(WORLD_BINDING)
end

local function openKeyBindings()
    if Settings and Settings.OpenToCategory and Settings.KEYBINDINGS_CATEGORY_ID then
        Settings.OpenToCategory(Settings.KEYBINDINGS_CATEGORY_ID)
    end
end

module.notice = {
    {
        text = L.TARGETMARKERS_NO_KEY, description = L.TARGETMARKERS_NO_KEY_DESC,
        button = L.TARGETMARKERS_BIND, fn = openKeyBindings,
        shown = function() return module.db.enabled and not anyKey() end,
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

-- Blizzard's radial wheel, which the ping wheel is made of (Blizzard_SharedXML/Blizzard_RadialWheel.xml).
local ATLAS_BACKGROUND = "Radial_Wheel_BG"
local ATLAS_POINTER = "Radial_Wheel_Select_Pointer"
local ATLAS_CLEAR = "common-icon-redx"
local ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_%d"

local SIZE = 300 -- the wheel's size when its atlas is missing
local ICON_SIZE, PICKED_SIZE = 34, 46
-- Where the icons sit and how far the middle reaches, as shares of the wheel's size.
local RADIUS, MIDDLE = 0.34, 0.12
-- The area the mouse's direction is read in (the ring frame), centered on the wheel. Wider than
-- the wheel, so pointing well past an icon still picks it; the mouse farther out than this cancels.
local REACH = 1600

-- The raid icons, 1 to 8, go clockwise from the top: star, circle, diamond, triangle, moon, square,
-- cross, skull. World markers number them differently (Blizzard's WORLD_MARKER order), so the world
-- ring maps each place to its marker.
local WORLD_IDS = "56327148"

-- The icon at the mouse's offset (dx, dy) from the middle: 0 for the middle, else 1 to 8.
local function placeAt(dx, dy, middle)
    if dx * dx + dy * dy <= middle * middle then
        return 0
    end
    local angle = (90 - deg(atan2(dy, dx))) % 360
    return floor((angle + 22.5) / 45) % 8 + 1
end

-- The secure side of a key: down opens the ring at the cursor (and, for marks, targets what's
-- under the mouse first, with that option on); up reads the place pointed at, closes the ring,
-- and lets the button do the action. The same arithmetic as `placeAt`, in Blizzard's restricted
-- Lua, where `control` is the ring. A key coming down while the ring is open (its key-up was
-- missed) only closes it.
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
        if self:GetAttribute("kind") == "mark" and self:GetAttribute("mouseover")
            and SecureCmdOptionParse("[@mouseover,exists] 1") == "1" then
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
    if self:GetAttribute("kind") == "mark" then
        self:SetAttribute("type", "raidtarget")
        self:SetAttribute("unit", "target")
        self:SetAttribute("marker", place > 0 and place or nil)
        self:SetAttribute("action", place > 0 and "set" or "clear")
    else
        self:SetAttribute("type", "worldmarker")
        self:SetAttribute("marker", place > 0 and tonumber(strsub("%s", place, place)) or nil)
        self:SetAttribute("action", place > 0 and "set" or "clear")
    end
]]

local rings = {} -- kind ("mark", "world") -> { frame, button, icons, clear, pointer, label, wheel }

-- The names under the ring: Blizzard's for the icons, ours for the middle.
local function placeName(kind, place)
    if place == 0 then
        return kind == "mark" and L.TARGETMARKERS_CLEAR or L.TARGETMARKERS_CLEAR_ALL
    end
    return _G["RAID_TARGET_" .. place] or ""
end

-- While a ring is open: the pointer toward the mouse, the icon it picks grown, and its name.
-- Plain code on our own frames' textures, which it may change in combat.
local function drawPicked(frame)
    local ring = frame.ring
    local scale = frame:GetEffectiveScale()
    local x, y = GetCursorPosition()
    local cx, cy = frame:GetCenter()
    if not cx then
        return
    end
    local dx, dy = x / scale - cx, y / scale - cy
    local place = placeAt(dx, dy, MIDDLE * ring.wheel)
    if place == ring.place then
        if place > 0 then
            ring.pointer:SetRotation(atan2(dy, dx))
        end
        return
    end
    ring.place = place
    for i, icon in ipairs(ring.icons) do
        local size = i == place and PICKED_SIZE or ICON_SIZE
        icon:SetSize(size, size)
    end
    ring.clear:SetAlpha(place == 0 and 1 or 0.6)
    ring.pointer:SetShown(place > 0 and ring.hasPointer)
    if place > 0 then
        ring.pointer:SetRotation(atan2(dy, dx))
    end
    ring.label:SetText(placeName(ring.kind, place))
end

local function buildRing(kind, buttonName)
    local frame = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
    frame:SetSize(REACH, REACH)
    frame:SetFrameStrata("DIALOG")
    frame:Hide()
    local ring = { kind = kind, frame = frame, icons = {} }
    frame.ring = ring

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

    for i = 1, 8 do
        local icon = art:CreateTexture(nil, "ARTWORK")
        icon:SetTexture(ICON:format(i))
        icon:SetSize(ICON_SIZE, ICON_SIZE)
        local angle = rad(90 - (i - 1) * 45)
        icon:SetPoint("CENTER", cos(angle) * RADIUS * wheel, sin(angle) * RADIUS * wheel)
        ring.icons[i] = icon
    end
    ring.clear = art:CreateTexture(nil, "ARTWORK")
    ring.clear:SetPoint("CENTER")
    ring.clear:SetAtlas(ATLAS_CLEAR)
    ring.clear:SetSize(ICON_SIZE * 0.7, ICON_SIZE * 0.7)

    ring.label = art:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    ring.label:SetPoint("TOP", art, "BOTTOM", 0, -2)

    frame:SetScript("OnShow", function(self)
        self.ring.place = nil
        drawPicked(self)
    end)
    frame:SetScript("OnUpdate", drawPicked)

    -- The key's button. Its action is set by the snippet on each press.
    local button = CreateFrame("Button", buttonName, UIParent, "SecureActionButtonTemplate")
    button:RegisterForClicks("AnyDown", "AnyUp")
    button:SetAttribute("kind", kind)
    frame:WrapScript(button, "OnClick", format(SNIPPET, REACH, MIDDLE, WORLD_IDS))
    ring.button = button
    return ring
end

-- Settings into the secure frames, which only happens out of combat.
local function apply()
    ns.AfterCombat(function()
        local on = module.enabled
        if on and not rings.mark then
            rings.mark = buildRing("mark", MARK_BUTTON)
            rings.world = buildRing("world", WORLD_BUTTON)
        end
        for _, ring in pairs(rings) do
            ring.button:SetAttribute("on", on)
            ring.button:SetAttribute("mouseover", module.db.mouseover)
            ring.frame:SetScale(module.db.scale / 100)
            if not on then
                ring.frame:Hide()
            end
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
