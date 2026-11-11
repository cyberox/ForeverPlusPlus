-- Fishing Cast: right-click twice quickly in the world with a fishing pole equipped to cast
-- Fishing. Casting a spell is protected, so the second click doesn't cast from our code: it puts a
-- temporary override binding for the right mouse button on our own secure button, which casts the
-- spell when the click goes through. That can't be changed in combat, so nothing is armed then,
-- and the binding comes off again on the next click so a right-click on the bobber still loots.
-- Louder Bobber turns sound effects up and music down while any Fishing cast channels.
local _, ns = ...

local GetTime, InCombatLockdown, CreateFrame = GetTime, InCombatLockdown, CreateFrame
local SetOverrideBindingSpell, ClearOverrideBindings = SetOverrideBindingSpell, ClearOverrideBindings
local UnitExists, GetUnitSpeed = UnitExists, GetUnitSpeed
local C_Spell, WorldFrame = C_Spell, WorldFrame
local GetMouseFoci, UnitChannelInfo = GetMouseFoci, UnitChannelInfo
local C_CVar, tonumber, tostring, next, select = C_CVar, tonumber, tostring, next, select

local L = ns.L

local module = ns.NewModule("FishingCast", L.FISHINGCAST_DESC, {
    enabled = false,
    speed = 400, -- milliseconds allowed between the two clicks
    combatWarning = true,
    louderBobber = false,
    saved = {}, -- CVar -> the player's own value while Louder Bobber has changed it
})
module.title = L.FISHINGCAST_TITLE
module.category = "automation"
module.quickToggle = "gathering"
module.presets = { developer = { enabled = true } }
-- A /reload, logout, or disconnect mid-cast leaves the changed volumes behind: put them back at
-- login if the module is off then (OnEnable does it when it's on).
ns.CVars.Track(module)

module.options = {
    {
        key = "speed",
        name = L.FISHINGCAST_SPEED,
        description = L.FISHINGCAST_SPEED_DESC,
        min = 200, max = 600, step = 50, format = function(ms) return L.FISHINGCAST_MS:format(ms) end,
    },
    { key = "combatWarning", name = L.FISHINGCAST_COMBAT, description = L.FISHINGCAST_COMBAT_DESC },
    { key = "louderBobber", name = L.FISHINGCAST_LOUDER, description = L.FISHINGCAST_LOUDER_DESC,
        added = "0.9.0" },
}

local MAINHAND = 16
-- Classic's ID: Self Test on build 70338 found Mainline's 131474 isn't in Forever's data.
local FISHING = ns.GameData.Spell(7620, "Fishing")

local button -- our secure button, made on first enable (a frame can't be removed)
local lastClick = 0
local armed = false

local function poleEquipped()
    return ns.Equipment.WeaponSubclass(MAINHAND) == ns.Equipment.FISHING_POLE
end

-- Whether the mouse is over the world and not a window or button.
local function overWorld()
    if not GetMouseFoci then
        return false
    end
    -- Forever returns an empty list over the bare world, not WorldFrame.
    local foci = GetMouseFoci()
    return not foci or foci[1] == nil or foci[1] == WorldFrame
end

local function disarm()
    if armed and button and not InCombatLockdown() then
        ClearOverrideBindings(button)
        armed = false
    end
end

local function arm()
    local name = C_Spell.GetSpellName(FISHING)
    if name then
        SetOverrideBindingSpell(button, true, "BUTTON2", name)
        armed = true
    end
end

-- The first right-click is only noted; the binding goes on when it is released, so it is already
-- in place when the second press comes (arming during the press itself was too late for the game
-- to see it). A timer takes it off again if no second click follows.
local function onMouseDown(_, buttonName)
    if InCombatLockdown() then
        return
    end
    if armed then
        -- This is the second click: leave the binding for it; the cast start removes it.
        lastClick = 0
        return
    end
    if buttonName ~= "RightButton" then
        lastClick = 0
        return
    end
    local speed = GetUnitSpeed("player")
    if not overWorld() or UnitExists("mouseover") or not ns.IsNumber(speed) or speed > 0
        or UnitChannelInfo("player") or not poleEquipped() then
        lastClick = 0
        return
    end
    lastClick = GetTime()
end

local disarmTimer = ns.Frames.Timer(module)
local function onMouseUp(_, buttonName)
    if InCombatLockdown() or armed or buttonName ~= "RightButton" or lastClick == 0 then
        return
    end
    local window = module.db.speed / 1000
    if GetTime() - lastClick >= window then
        lastClick = 0
        return
    end
    arm()
    disarmTimer:Start(window, function()
        lastClick = 0
        disarm()
    end)
end

-- The cast has started: take the binding off so the next right-click is an ordinary one.
local function onCastStart(_, unit)
    if unit == "player" then
        disarm()
    end
end

-- Louder Bobber -------------------------------------------------------------------------------------
-- While Fishing channels, sound effects go to full and music drops, so the splash is easy to hear.
-- The player's own values come back a moment after the cast ends, so a quick recast doesn't make
-- the music swell and fade between casts.

local SFX_ON, SFX_VOLUME = "Sound_EnableSFX", "Sound_SFXVolume"
local MUSIC_VOLUME = "Sound_MusicVolume"
local QUIET_MUSIC = 0.1
local RESTORE_DELAY = 5 -- seconds after a cast ends before the volumes go back

local restoreTimer = ns.Frames.Timer(module)

local function isFishing(spellID)
    if not spellID or not ns.IsReadable(spellID) then
        return false
    end
    local name = C_Spell.GetSpellName(spellID)
    return name ~= nil and name == C_Spell.GetSpellName(FISHING)
end

local function cancelRestore()
    restoreTimer:Cancel()
end

local function restoreSound()
    cancelRestore()
    ns.CVars.RestoreAll(module.db.saved)
end

local function louder()
    cancelRestore()
    local saved = module.db.saved
    ns.CVars.Set(saved, SFX_ON, "1")
    ns.CVars.Set(saved, SFX_VOLUME, "1")
    -- Only ever lower the music: a player who keeps it quieter keeps their value.
    local music = tonumber(C_CVar.GetCVar(MUSIC_VOLUME) or "")
    if music and music > QUIET_MUSIC then
        ns.CVars.Set(saved, MUSIC_VOLUME, tostring(QUIET_MUSIC))
    end
end

local function onChannelStart(_, unit, _, spellID)
    if unit == "player" and module.db.louderBobber and isFishing(spellID) then
        louder()
    end
end

local function onChannelStop(_, unit)
    if unit == "player" and next(module.db.saved) ~= nil then
        restoreTimer:Start(RESTORE_DELAY, restoreSound)
    end
end

function module:OnOptionChanged(key)
    if key == "louderBobber" then
        if self.db.louderBobber and UnitChannelInfo("player") then
            onChannelStart(nil, "player", nil, select(8, UnitChannelInfo("player")))
        elseif not self.db.louderBobber then
            restoreSound()
        end
    end
end

function module:OnEnable()
    -- Not fishing now, so anything still saved is left from a reload or disconnect mid-cast.
    restoreSound()
    self:On("UNIT_SPELLCAST_CHANNEL_START", onChannelStart)
    self:On("UNIT_SPELLCAST_CHANNEL_STOP", onChannelStop)
    if not button then
        button = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
    end
    lastClick = 0
    self:On("GLOBAL_MOUSE_DOWN", onMouseDown)
    self:On("GLOBAL_MOUSE_UP", onMouseUp)
    self:On("UNIT_SPELLCAST_CHANNEL_START", onCastStart)
    self:On("UNIT_SPELLCAST_START", onCastStart)
    -- Combat starts: never leave a right-click casting Fishing; if the lockdown already began,
    -- wait for it to end.
    self:On("PLAYER_REGEN_DISABLED", function()
        if armed then
            ns.AfterCombat(disarm)
        end
        lastClick = 0
        -- Combat with a pole still in hand: one red line where Blizzard's own errors show.
        if module.db.combatWarning and poleEquipped() then
            ns.Frames.ErrorMessage(L.FISHINGCAST_COMBAT_TEXT)
        end
    end)
end

function module:OnDisable()
    if armed then
        ns.AfterCombat(disarm)
    end
    restoreSound()
end
