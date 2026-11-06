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

local select, pcall = select, pcall
local CreateFrame, C_CVar = CreateFrame, C_CVar
local UnitClass, UnitPower, UnitPowerMax, UnitPowerType = UnitClass, UnitPower, UnitPowerMax, UnitPowerType
local UnitIsDeadOrGhost, UnitPowerPercent = UnitIsDeadOrGhost, UnitPowerPercent

local L = ns.L

local module = ns.NewModule("DruidManaBar", L.DRUIDMANABAR_DESC, {
    enabled = true,
    everyForm = false, -- caster, Travel, and Aquatic Form too, where the frame's own bar is mana
    formColor = true, -- a lighter blue than the frame's own mana bar
    text = true, -- off: no text on our bar, whatever Status Text says
})
module.title = L.DRUIDMANABAR_TITLE
module.category = "units"
module.added = "1.0.2"

module.options = {
    { key = "everyForm", name = L.DRUIDMANABAR_EVERY_FORM, description = L.DRUIDMANABAR_EVERY_FORM_DESC },
    { key = "formColor", name = L.DRUIDMANABAR_FORM_COLOR, description = L.DRUIDMANABAR_FORM_COLOR_DESC },
    { key = "text", name = L.DRUIDMANABAR_TEXT, description = L.DRUIDMANABAR_TEXT_DESC },
}

-- Your mana, which may be secret, and its max.
local function mana()
    return UnitPower("player", Enum.PowerType.Mana), UnitPowerMax("player", Enum.PowerType.Mana)
end

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
-- Lighter Blue: the white fill Blizzard tints for a power without art of its own
-- (PlayerFrameAlternatePowerBarBaseMixin:UpdateArt's Mana-Status), in a sky blue that reads as
-- mana but never matches the frame's own dark blue mana bar, which is right above it in caster
-- form with Show in Every Form on.
local TINTED = { "ui-hud-unitframe-player-portraiton-bar-mana-status-c60",
    "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana-Status" }
local LIGHT_BLUE = { 0.3, 0.65, 1 }
local fillAtlas, tintedAtlas -- this client's, found when the bar is made

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
    local power = UnitPowerType("player")
    return module.db.everyForm or (ns.IsNumber(power) and power ~= Enum.PowerType.Mana)
end

-- The player's mana is secret on Forever even out of combat, while its max reads fine (`/dump`
-- 2026-11-05, a level 1 druid). Blizzard's own code may do math on a secret; ours may not, but
-- SetFormattedText takes one, and so may AbbreviateLargeNumbers (Mainline made the number
-- helpers take secrets; a pcall falls back to the plain number if this client's doesn't). The
-- percent comes from the game, scaled to 0-100, where it has UnitPowerPercent.
local function setNumber(text, format, value, max)
    local short = AbbreviateLargeNumbers
    if not (short and pcall(function()
        if max then
            text:SetFormattedText(format, short(value), short(max))
        else
            text:SetFormattedText(format, short(value))
        end
    end)) then
        if max then
            text:SetFormattedText(format, value, max)
        else
            text:SetFormattedText(format, value)
        end
    end
end

-- Whether there's a percent, then the percent, which may be secret: never test it, only show it.
local function secretPercent()
    local scale = CurveConstants and CurveConstants.ScaleTo100
    if not (UnitPowerPercent and scale) then
        return false
    end
    return pcall(UnitPowerPercent, "player", Enum.PowerType.Mana, false, scale)
end

-- As ns.Text.StatusText lays it out, for a secret value.
local function secretText(value, max, mode)
    local hasPercent, percent = false, nil
    if mode == "BOTH" or mode == "PERCENT" then
        hasPercent, percent = secretPercent()
    end
    if mode == "BOTH" then
        if hasPercent then
            bar.LeftText:SetFormattedText("%.0f%%", percent)
        end
        setNumber(bar.RightText, "%s", value)
    elseif mode == "PERCENT" and hasPercent then
        bar.Text:SetFormattedText("%.0f%%", percent)
    else
        setNumber(bar.Text, "%s / %s", value, max)
    end
end

-- Blizzard's status text (TextStatusBarMixin:UpdateTextStringWithValues, for a mana bar): always
-- with Status Text on (the statusText CVar), else under the mouse; numbers by statusTextDisplay.
local function updateText()
    if not (bar and bar:IsShown()) then
        return -- the player frame's hover comes in caster form too
    end
    local value, max = mana()
    bar.Text:SetText("")
    bar.LeftText:SetText("")
    bar.RightText:SetText("")
    if not (module.db.text and (hovered or C_CVar.GetCVar("statusText") == "1") and ns.IsNumber(max)
        and max > 0) then
        return
    end
    local mode = C_CVar.GetCVar("statusTextDisplay")
    if ns.IsNumber(value) then
        local middle, left, right = ns.Text.StatusText(value, max, mode)
        bar.Text:SetText(middle)
        bar.LeftText:SetText(left)
        bar.RightText:SetText(right)
    else
        secretText(value, max, mode)
    end
end

-- The mana goes straight to the bar, which takes a secret value too.
local function updatePower()
    if bar and bar:IsShown() then
        local value, max = mana()
        bar:SetMinMaxValues(0, max)
        bar:SetValue(value)
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

local onUpdate = ns.Frames.Throttled(0.1, ns.Profiler.Wrap(module, updatePower))

-- Mana's own fill, or Lighter Blue's, so it never matches the frame's own mana bar above it.
local function updateFill()
    local fill = bar:GetStatusBarTexture()
    if module.db.formColor and tintedAtlas then
        fill:SetAtlas(tintedAtlas)
        bar:SetStatusBarColor(LIGHT_BLUE[1], LIGHT_BLUE[2], LIGHT_BLUE[3])
    else
        fill:SetAtlas(fillAtlas)
        bar:SetStatusBarColor(1, 1, 1)
    end
end

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
        updateFill()
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
    fillAtlas, tintedAtlas = fillArt, ns.Frames.FirstAtlas(TINTED[1], TINTED[2])
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
