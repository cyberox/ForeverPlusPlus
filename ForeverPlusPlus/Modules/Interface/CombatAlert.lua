-- Combat Alert: a line of text that floats up and fades above the middle of the screen when you
-- enter or leave combat, in the game's big title font, red going in and green coming out. The
-- combat log is closed to addons on Forever, so this follows the player's own combat state
-- (PLAYER_REGEN_DISABLED and PLAYER_REGEN_ENABLED), which is the same thing the log would say.
local _, ns = ...

local CreateFrame, UIParent, PlaySound, C_Timer = CreateFrame, UIParent, PlaySound, C_Timer

local L = ns.L
local Colors = ns.Colors

local module = ns.NewModule("CombatAlert", L.COMBATALERT_DESC, {
    enabled = false,
    entering = true,
    leaving = true,
    sound = false,
    scale = 100, -- percent
    duration = 2, -- seconds
    x = 0, -- the text's offset from the center of the screen
    y = 120,
})
module.title = L.COMBATALERT_TITLE
module.category = "interface"

module.options = {
    { key = "entering", name = L.COMBATALERT_ENTERING, description = L.COMBATALERT_ENTERING_DESC },
    { key = "leaving", name = L.COMBATALERT_LEAVING, description = L.COMBATALERT_LEAVING_DESC },
    {
        key = "duration",
        name = L.COMBATALERT_DURATION,
        description = L.COMBATALERT_DURATION_DESC,
        min = 1, max = 5, step = 1, format = ns.Text.Seconds,
    },
    { key = "sound", name = L.COMBATALERT_SOUND, description = L.COMBATALERT_SOUND_DESC,
        added = "0.9.0" },
}

local WIDTH, HEIGHT = 400, 50
local RISE = 40 -- how far the text floats up, in pixels

local frame, rise, fade

local function newFrame()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(WIDTH, HEIGHT)
    f:SetFrameStrata("HIGH")
    -- The text sits in a child that takes the scale, so the frame's own size and position stay
    -- in screen units for Edit Mode.
    f.inner = CreateFrame("Frame", nil, f)
    f.inner:SetSize(WIDTH, HEIGHT)
    f.inner:SetPoint("CENTER") -- a scaled frame scales about its center, so keep it centered
    -- The big gold font Blizzard uses for zone names and the like.
    f.text = f.inner:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    f.text:SetPoint("CENTER")
    f.text:SetShadowOffset(1, -1)
    local group = f:CreateAnimationGroup()
    rise = group:CreateAnimation("Translation")
    rise:SetOffset(0, RISE)
    rise:SetOrder(1)
    fade = group:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetOrder(1)
    group:SetScript("OnFinished", function()
        if not ns.EditMode.IsActive() then
            f:Hide()
        end
    end)
    f.group = group
    f:Hide()
    return f
end

local function place()
    frame.inner:SetScale(module.db.scale / 100)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", module.db.x, module.db.y)
end

-- Shows `text` in a color, floating up for the set time and fading out over the second half,
-- with the SOUNDKIT named `sound` when Play Sound is on (skipped if this client lacks it).
local function alert(text, color, sound)
    if module.db.sound then
        local kit = SOUNDKIT and SOUNDKIT[sound]
        if kit and PlaySound then
            PlaySound(kit)
        end
    end
    frame.group:Stop()
    frame.text:SetText(text)
    frame.text:SetTextColor(color[1], color[2], color[3])
    local duration = module.db.duration
    rise:SetDuration(duration)
    fade:SetStartDelay(duration / 2)
    fade:SetDuration(duration / 2)
    frame:SetAlpha(1)
    frame:Show()
    frame.group:Play()
end

local function entering()
    if module.db.entering then
        alert(L.COMBATALERT_ENTER_TEXT, Colors.RED, "RAID_WARNING")
    end
end

local function leaving()
    if module.db.leaving then
        -- A softer sound going out: the whisper chime, not the raid warning horn.
        alert(L.COMBATALERT_LEAVE_TEXT, Colors.GUILD_GREEN, "TELL_MESSAGE")
    end
end

-- Debug's Test Alerts: the entering alert, then the leaving one once it has faded, out of combat.
module.debugActions = {
    {
        name = L.COMBATALERT_TEST, button = L.COMBATALERT_TEST_BUTTON,
        description = L.COMBATALERT_TEST_DESC, section = L.DEBUG_SECTION_PREVIEWS,
        fn = function()
            if not frame then
                return
            end
            entering()
            C_Timer.After(module.db.duration + 0.5, function()
                if module.enabled then
                    leaving()
                end
            end)
        end,
    },
}

-- Edit Mode -------------------------------------------------------------------------------------

-- In Edit Mode the text stays up, so it can be placed.
local function sample(active)
    frame.group:Stop()
    if active then
        frame.text:SetText(L.COMBATALERT_ENTER_TEXT)
        frame.text:SetTextColor(Colors.RED[1], Colors.RED[2], Colors.RED[3])
        frame:SetAlpha(1)
        frame:Show()
    else
        frame:Hide()
    end
end

function module:OnEnable()
    frame = frame or newFrame()
    place()
    self:On("PLAYER_REGEN_DISABLED", entering)
    self:On("PLAYER_REGEN_ENABLED", leaving)
    ns.EditMode.RegisterModule(self, frame, L.COMBATALERT_TITLE, place, sample)
end

function module:OnDisable()
    if frame then
        ns.EditMode.Unregister(frame)
        frame.group:Stop()
        frame:Hide()
    end
end
