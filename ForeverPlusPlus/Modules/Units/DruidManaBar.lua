-- Druid Mana Bar: a druid's mana under the energy or rage bar on the player frame while in a form
-- that doesn't use mana (Cat, Bear), in the spot Blizzard's own third bar takes. Mainline's player
-- frame has that bar (AlternatePowerBar, loaded on Forever), but it only shows mana for Balance's
-- Lunar Power, which Forever's druids don't have (Blizzard_UnitFrame/Mainline/AlternatePowerBar.lua,
-- Gethe `forever` branch, checked 2026-11-05).
--
-- It looks like Blizzard's: the taller frame art with a slot for the third bar
-- (`...-PortraitOn-ClassResource`, Forever's `-c60` sheet has one), a mana fill and mask from the
-- same sheet, at the place and size of Blizzard's bar, and text that follows the game's Status
-- Text settings. The art is a texture of ours over Blizzard's frame art, which is faded while ours
-- shows; nothing of Blizzard's is shown, hidden, moved, or called, so the secure player frame
-- isn't touched, in combat or out.
local _, ns = ...

local select = select
local CreateFrame, C_CVar = CreateFrame, C_CVar
local UnitClass, UnitPower, UnitPowerMax, UnitPowerType = UnitClass, UnitPower, UnitPowerMax, UnitPowerType
local UnitIsDeadOrGhost = UnitIsDeadOrGhost

local L = ns.L

local module = ns.NewModule("DruidManaBar", L.DRUIDMANABAR_DESC, {
    enabled = true,
    preview = false,
})
module.title = L.DRUIDMANABAR_TITLE
module.category = "units"
module.added = "1.0.2"

module.options = {
    { key = "preview", name = L.DRUIDMANABAR_PREVIEW, description = L.DRUIDMANABAR_PREVIEW_DESC,
        debug = true, section = L.DEBUG_SECTION_TESTING },
}

-- Only druids change forms; everyone else keeps it out of Settings.
function module:IsAvailable()
    return select(2, UnitClass("player")) == "DRUID" and Enum and Enum.PowerType
        and Enum.PowerType.Mana ~= nil or false
end

-- Atlases, Forever's own first (docs/forever-api.md, "Unit frames").
local FRAME_ART = { "ui-hud-unitframe-player-portraiton-classresource-c60",
    "UI-HUD-UnitFrame-Player-PortraitOn-ClassResource" }
local FILL = { "ui-hud-unitframe-player-portraiton-bar-mana-c60", "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana" }
local MASK = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana-Mask"

local bar, art -- ours, made the first time the module turns on
local hovered = false -- the mouse is over our bar or the player frame: the text shows, as Blizzard's

-- The parts of Blizzard's player frame we sit in, or nil on a client without them.
local function playerFrame()
    local frame = PlayerFrame
    local container = frame and frame.PlayerFrameContainer
    local content = frame and frame.PlayerFrameContent
    local main = content and content.PlayerFrameContentMain
    if container and container.FrameTexture and main then
        return frame, container, main
    end
end

-- Whether the bar should show: a form without mana, on the player's own frame (not a vehicle's),
-- with no bar of Blizzard's in the slot. A value that can't be read counts as no.
local function wanted()
    local frame = playerFrame()
    if not (module.enabled and frame) or UNIT_FRAME_SHOW_HEALTH_ONLY then
        return false
    end
    if frame.activeAlternatePowerBar or (frame.state ~= nil and frame.state ~= "player") then
        return false
    end
    local max = UnitPowerMax("player", Enum.PowerType.Mana)
    if not (ns.IsNumber(max) and max > 0) then
        return false
    end
    -- Preview (Debug): in every form, to see it without Cat Form (level 20) or Bear Form (10).
    local power = UnitPowerType("player")
    return module.db.preview or (ns.IsNumber(power) and power ~= Enum.PowerType.Mana)
end

-- Blizzard's status text (TextStatusBarMixin:UpdateTextStringWithValues, for a mana bar): always
-- with Status Text on (the statusText CVar), else under the mouse; numbers by statusTextDisplay.
local function updateText()
    if not (bar and bar:IsShown()) then
        return -- the player frame's hover comes in caster form too
    end
    local value, max = UnitPower("player", Enum.PowerType.Mana), UnitPowerMax("player", Enum.PowerType.Mana)
    local middle, left, right = "", "", ""
    if (hovered or C_CVar.GetCVar("statusText") == "1") and ns.IsNumber(value) and ns.IsNumber(max)
        and max > 0 then
        middle, left, right = ns.Text.StatusText(value, max, C_CVar.GetCVar("statusTextDisplay"))
    end
    bar.Text:SetText(middle)
    bar.LeftText:SetText(left)
    bar.RightText:SetText(right)
end

-- The mana goes straight to the bar, which takes a secret value too.
local function updatePower()
    if bar and bar:IsShown() then
        bar:SetMinMaxValues(0, UnitPowerMax("player", Enum.PowerType.Mana))
        bar:SetValue(UnitPower("player", Enum.PowerType.Mana))
        updateText()
    end
end

-- Gray and faded while dead, as Blizzard's bars are.
local function updateAlive()
    local dead = UnitIsDeadOrGhost("player")
    dead = ns.IsTrue(dead)
    local fill = bar:GetStatusBarTexture()
    fill:SetDesaturated(dead)
    fill:SetAlpha(dead and 0.5 or 1)
end

local onUpdate = ns.Profiler.Wrap(module, ns.Frames.Throttled(0.1, updatePower))

local function update()
    local _, container = playerFrame()
    if not bar then
        return
    end
    local show = wanted()
    bar:SetShown(show)
    art:SetShown(show)
    container.FrameTexture:SetAlpha(show and 0 or 1)
    if show then
        updateAlive()
        updatePower()
    end
end
-- Shifting sends UNIT_DISPLAYPOWER, UPDATE_SHAPESHIFT_FORM, and UNIT_MAXPOWER together: once, a
-- frame later.
local updateSoon, cancelUpdate = ns.Frames.Coalesce(update, nil, module)

local function onEnter()
    hovered = true
    updateText()
end

local function onLeave()
    hovered = false
    updateText()
end

local function newText(point, x)
    local text = bar:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
    text:SetDrawLayer("OVERLAY", 2)
    text:SetPoint(point, bar, point, x, 0)
    return text
end

-- Our bar and frame art, once. They're ours: added to Blizzard's frame, never set on it.
local function build()
    local _, container, main = playerFrame()
    local frameArt, fillArt = ns.Frames.FirstAtlas(FRAME_ART[1], FRAME_ART[2]), ns.Frames.FirstAtlas(FILL[1], FILL[2])
    if bar or not (main and frameArt and fillArt) then
        return
    end
    art = container:CreateTexture(nil, "BACKGROUND", nil, 2) -- Blizzard's frame art's layer
    art:SetAtlas(frameArt, true)
    art:SetPoint("CENTER", container, "CENTER", 0, -1.5) -- where Blizzard puts its own
    art:SetTexelSnappingBias(0)
    art:SetSnapToPixelGrid(false)
    art:Hide()

    -- PlayerFrameAlternatePowerBarBaseTemplate's size, at Forever's mana bar's left edge
    -- (Camelot's PlayerFrame_UpdateManaBarVisuals: x 87, where Mainline's is 85) and Blizzard's
    -- third bar's height below it.
    bar = CreateFrame("StatusBar", nil, main)
    bar:SetSize(124, 9)
    bar:SetPoint("TOPLEFT", main, "TOPLEFT", 87, -73)
    bar:SetStatusBarTexture(fillArt)
    local fill = bar:GetStatusBarTexture()
    fill:SetTexelSnappingBias(0)
    fill:SetSnapToPixelGrid(false)
    if ns.Frames.HasAtlas(MASK) then
        local mask = bar:CreateMaskTexture()
        mask:SetAtlas(MASK, true)
        mask:SetPoint("TOPLEFT", bar, "TOPLEFT", -2, 3)
        fill:AddMaskTexture(mask)
    end
    bar.Text, bar.LeftText, bar.RightText = newText("CENTER", 0), newText("LEFT", 2), newText("RIGHT", -2)
    -- Mouse motion only, so clicks still reach the player frame under it (to target yourself),
    -- as on Blizzard's mana bar.
    bar:SetMouseMotionEnabled(true)
    bar:SetMouseClickEnabled(false)
    bar:SetScript("OnEnter", onEnter)
    bar:SetScript("OnLeave", onLeave)
    -- Mana ticks back more often than UNIT_POWER_UPDATE says (Blizzard's bars update every
    -- frame), so a few times a second while the bar shows.
    bar:SetScript("OnUpdate", onUpdate)
    bar:Hide()
end

local function onCVar(_, name)
    if name == "statusText" or name == "statusTextDisplay" then
        updateText()
    end
end

function module:OnEnable()
    build()
    self:OnUnit("UNIT_DISPLAYPOWER", { "player" }, updateSoon)
    self:OnUnit("UNIT_MAXPOWER", { "player" }, updateSoon)
    self:OnUnit("UNIT_POWER_UPDATE", { "player" }, updatePower)
    self:On("UPDATE_SHAPESHIFT_FORM", updateSoon)
    self:On("PLAYER_ENTERING_WORLD", updateSoon)
    self:On("PLAYER_DEAD", updateSoon)
    self:On("PLAYER_ALIVE", updateSoon)
    self:On("PLAYER_UNGHOST", updateSoon)
    self:On("CVAR_UPDATE", onCVar)
    -- Blizzard redraws the frame for a vehicle, and for a bar of its own in the slot.
    self:Hook("PlayerFrame_UpdateArt", updateSoon)
    -- Hovering the player frame shows every bar's text, so ours too.
    self:HookScript(PlayerFrame, "OnEnter", onEnter)
    self:HookScript(PlayerFrame, "OnLeave", onLeave)
    update()
end

function module:OnOptionChanged()
    update()
end

-- module.enabled is already false, so update hides ours and puts Blizzard's frame art back.
function module:OnDisable()
    cancelUpdate()
    hovered = false
    update()
end
