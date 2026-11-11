-- Buff Timers: the time left under your buff and debuff icons as a clock (1:23) instead of
-- Blizzard's rounded "2 m". Blizzard's text keeps running underneath at no alpha and ours sits on
-- top, so when a time can't be read (a secret value in combat) Blizzard's shows again as it was.
-- Sort Buffs moves Blizzard's buff buttons between the places Blizzard laid them out in, and Hide
-- Tracking Buffs leaves minimap tracking out of them.
local _, ns = ...

local ipairs, pairs, type, setmetatable, floor, pcall = ipairs, pairs, type, setmetatable, math.floor, pcall
local sort, huge = table.sort, math.huge
local GetCVarBool = C_CVar and C_CVar.GetCVarBool or GetCVarBool
local C_UnitAuras, C_Minimap = C_UnitAuras, C_Minimap

local L = ns.L
local readable = ns.IsReadable
local clock = ns.Text.Clock
local Frames = ns.Frames

local module = ns.NewModule("BuffTimers", L.BUFFTIMERS_DESC, {
    enabled = true,
    limit = "10m", -- "1m", "10m", "hour", or "all": which auras get a clock
    sort = "off", -- "off", "left", or "right": where the buff that runs out next sits
    hideTracking = false, -- leave minimap tracking (Find Herbs) off the buff bar
})
module.title = L.BUFFTIMERS_TITLE
module.category = "character"
module.developer = { options = { hideTracking = true } }
module.added = "0.8.0"
-- Blizzard shows its own Duration text only with this CVar on, and so do we (see below); and
-- secret aura times in combat, which we can't show.
module.notice = {
    ns.CVars.OffNotice(module, "buffDurations", L.BUFFTIMERS_BLIZZARD_OFF, L.BUFFTIMERS_BLIZZARD_OFF_DESC),
    { text = L.BUFFTIMERS_NOTICE, description = L.BUFFTIMERS_NOTICE_DESC },
    {
        text = L.BUFFTIMERS_SORT_NOTICE, description = L.BUFFTIMERS_SORT_NOTICE_DESC,
        shown = function() return module.db.sort ~= "off" end,
    },
    {
        text = L.BUFFTIMERS_HIDE_NOTICE, description = L.BUFFTIMERS_HIDE_NOTICE_DESC,
        shown = function() return module.db.hideTracking end,
    },
}

module.options = {
    {
        key = "limit", name = L.BUFFTIMERS_LIMIT, description = L.BUFFTIMERS_LIMIT_DESC,
        changed = "0.8.2",
        choices = {
            { "1m", L.BUFFTIMERS_LIMIT_1M },
            { "10m", L.BUFFTIMERS_LIMIT_10M },
            { "hour", L.BUFFTIMERS_LIMIT_1H },
            { "all", L.BUFFTIMERS_LIMIT_ALL },
        },
    },
    {
        key = "sort", name = L.BUFFTIMERS_SORT, description = L.BUFFTIMERS_SORT_DESC,
        added = "1.2.0",
        choices = {
            { "off", L.BUFFTIMERS_SORT_OFF },
            { "left", L.BUFFTIMERS_SORT_LEFT },
            { "right", L.BUFFTIMERS_SORT_RIGHT },
        },
    },
    {
        key = "hideTracking", name = L.BUFFTIMERS_HIDE_TRACKING, description = L.BUFFTIMERS_HIDE_TRACKING_DESC,
        added = "1.3.0",
    },
}

local LIMITS = { ["1m"] = 60, ["10m"] = 600, hour = 3600 }
local WARNING = 31 -- Blizzard's BUFF_DURATION_WARNING_TIME, if it's missing

local weak = { __mode = "k" }
local texts = setmetatable({}, weak) -- aura button -> our FontString
-- Aura button -> what its clock shows (the rounded seconds and the color, as one number), or nil
-- while Blizzard's text shows. The clock changes once a second; this runs every frame.
local showing = setmetatable({}, weak)

-- Blizzard's own text is on: read at turning on and when the CVar changes, not every frame.
local durationsOn = false

local function readCVar()
    durationsOn = GetCVarBool("buffDurations") and true or false
end

local function restore(button)
    local text = texts[button]
    if text then
        text:Hide()
    end
    button.Duration:SetAlpha(1)
    showing[button] = nil
end

-- After Blizzard's AuraButtonMixin:UpdateDuration, which runs every frame while the aura counts
-- down. It shows its Duration text only with the "buffDurations" CVar on, so we do too.
local function update(button, timeLeft)
    local limit = LIMITS[module.db.limit]
    if not (readable(timeLeft) and timeLeft and durationsOn and (not limit or timeLeft < limit)) then
        if showing[button] then
            restore(button)
        end
        return
    end
    -- Blizzard's colors: white in the last half minute, gold before.
    local warn = timeLeft < (BUFF_DURATION_WARNING_TIME or WARNING)
    local shown = floor(timeLeft + 0.5) * 2 + (warn and 1 or 0)
    local duration = button.Duration
    if showing[button] == shown then
        duration:SetAlpha(0) -- in case Blizzard showed its text again; the rest is as it was
        return
    end
    showing[button] = shown
    local text = texts[button]
    if not text then
        text = button:CreateFontString(nil, "OVERLAY")
        text:SetPoint("TOP", duration, "TOP")
        text:SetFontObject(duration:GetFontObject())
        texts[button] = text
    end
    text:SetText(clock(timeLeft))
    local color = warn and HIGHLIGHT_FONT_COLOR or NORMAL_FONT_COLOR
    text:SetTextColor(color.r, color.g, color.b)
    text:Show()
    duration:SetAlpha(0)
end

local function onCVarUpdate(_, name)
    if type(name) == "string" and name:lower() == "buffdurations" then
        readCVar()
    end
end

-- An aura with no end hides Blizzard's text and stops counting without UpdateDuration.
-- A secret time left (in combat) leaves Blizzard's own text, as `update` does.
local function expiration(button)
    local timeLeft = button.timeLeft
    if not readable(timeLeft) or not timeLeft then
        restore(button)
    end
end

-- Blizzard's buff and debuff buttons (made once when the frames load) and the big deadly debuff.
local function buttons()
    local list = {}
    for _, frame in ipairs({ BuffFrame, DebuffFrame }) do
        for _, button in ipairs(frame and frame.auraFrames or {}) do
            list[#list + 1] = button
        end
    end
    if DeadlyDebuffFrame then
        list[#list + 1] = DeadlyDebuffFrame.Debuff
    end
    return list
end

-- Edit Mode's example auras, and buttons left without an aura, don't count down through
-- UpdateDuration, so our clock would stay as it was.
local function afterAuraButtons(frame)
    for _, button in ipairs(frame.auraFrames or {}) do
        if texts[button] and (button.isExample or not button:IsShown()) then
            restore(button)
        end
    end
end

-- Sort Buffs. Blizzard gives BuffFrame.auraFrames[i] the i-th buff and lays the buttons out in
-- that order (AuraContainerMixin:UpdateGridLayout, Blizzard_BuffFrame/BuffFrame.lua on the
-- `forever` branch). Sorting Blizzard's auraInfo would taint the buttonInfo a right-click cancels
-- with, so instead we keep the places Blizzard put each button in and move the buttons between
-- them: SetPoint only, on plain buttons that aren't protected, so right-click still cancels.
local slots = {} -- i -> the anchor points Blizzard gave auraFrames[i]
local placed = setmetatable({}, weak) -- button -> the slot it's in now, while not its own

-- Read right after Blizzard laid the buttons out, when each is in its own place.
local function readSlots()
    slots = {}
    for i, button in ipairs(BuffFrame and BuffFrame.auraFrames or {}) do
        slots[i] = Frames.GetPoints(button)
    end
    for button in pairs(placed) do
        placed[button] = nil
    end
end

local function place(button, i, own)
    local points = slots[i]
    if (placed[button] or own) ~= i and points and points[1] then
        Frames.SetPoints(button, points)
        placed[button] = i ~= own and i or nil
    end
end

-- Hide Tracking Buffs. A hidden button goes to no alpha with its mouse off, so it can't be
-- right-clicked away unseen, and the buttons after it close up the gap through `place`.
local hidden = setmetatable({}, weak) -- button -> true while we hide it

-- Every time: Blizzard's UpdateExpirationTime sets a buff that never runs out back to full alpha
-- on each update (Blizzard_BuffFrame/BuffFrame.lua, `forever` branch).
local function hide(button)
    hidden[button] = true
    button:SetAlpha(0)
    button:EnableMouse(false)
end

local function unhide(button)
    if hidden[button] then
        hidden[button] = nil
        button:SetAlpha(1)
        button:EnableMouse(true)
    end
end

-- The minimap's tracking spells (Find Herbs, Find Minerals, a hunter's tracks), read when turned on
-- and as spells are learned. GetTrackingInfo has no secret values.
local trackingSpells = {}

local function readTracking()
    trackingSpells = {}
    for i = 1, C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetNumTrackingTypes() or 0 do
        local info = C_Minimap.GetTrackingInfo(i)
        local spellID = type(info) == "table" and info.spellID
        if spellID and spellID > 0 then
            trackingSpells[spellID] = true
        end
    end
end

-- Whether one of Blizzard's buff infos (a button's buttonInfo, or BuffFrame.auraInfo) is a tracking
-- spell, or nil when the game won't say (a secret, in combat). The info keeps the aura's instance,
-- not its spell, so the spell is looked up.
local function isTracking(info)
    local id = info and info.auraInstanceID
    if not id then
        return false -- a weapon enchant
    end
    -- While auras are secret (in combat, and in Edit Mode's layout pass at login) the lookup throws
    -- instead of giving back a secret value: check first, and catch it in case it throws anyway.
    if not readable(id) or not C_UnitAuras.GetAuraDataByAuraInstanceID or not ns.AurasReadable() then
        return nil
    end
    local ok, aura = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, "player", id)
    if not ok then
        return nil
    end
    local spellID = aura and aura.spellId
    if not readable(spellID) then
        return nil
    end
    return spellID and trackingSpells[spellID] or false
end

-- Blizzard's arrow folds away buffs that never run out or have long left, and shows while there
-- are any. When those are only tracking buffs we hide, it has nothing to fold, so it goes too.
local arrowHidden = false

local function showArrow(shown)
    local arrow = BuffFrame and BuffFrame.CollapseAndExpandButton
    if not arrow or shown == not arrowHidden then
        return
    end
    arrowHidden = not shown
    arrow:SetAlpha(shown and 1 or 0)
    arrow:EnableMouse(shown)
end

-- Whether every buff the arrow would fold is a tracking buff; false while any can't be read.
local function onlyTrackingFolds()
    local any = false
    for _, info in ipairs(BuffFrame and BuffFrame.auraInfo or {}) do
        local folds = info.hideUnlessExpanded
        if not readable(folds) then
            return false
        end
        if folds then
            if not isTracking(info) then
                return false
            end
            any = true
        end
    end
    return any
end

-- Every button back in Blizzard's place, and shown.
local function unsort()
    for i, button in ipairs(BuffFrame and BuffFrame.auraFrames or {}) do
        unhide(button)
        place(button, i, i)
    end
    showArrow(true)
end

-- When a buff runs out: never (0 or no time) sorts after every timed one.
local function endsAt(info)
    local duration, expires = info.duration, info.expirationTime
    if not (readable(duration) and readable(expires)) then
        return nil
    end
    if type(expires) ~= "number" or expires <= 0 or duration == 0 then
        return huge
    end
    return expires
end

-- Lays out the buff buttons: sorted with Sort Buffs, and without tracking buffs with Hide Tracking
-- Buffs, in the places Blizzard laid them out, the shown ones from slot 1 and the hidden after.
local function layout()
    local frames = BuffFrame and BuffFrame.auraFrames
    local container = BuffFrame and BuffFrame.AuraContainer
    local side = module.db.sort
    local sorting, hiding = side ~= "off", module.db.hideTracking
    if not (frames and container) or not (sorting or hiding) then
        unsort()
        return
    end
    -- Blizzard's shown buttons come first, in its order; Edit Mode's examples stay as they are.
    local all, ends, order, tracked = {}, {}, {}, {}
    for i, button in ipairs(frames) do
        if not button.hasValidInfo or button.isExample then
            break
        end
        all[i], order[button] = button, i
        if sorting then
            ends[button] = button.buttonInfo and endsAt(button.buttonInfo)
            -- A secret time (in combat): Blizzard's order until it can be read.
            sorting = ends[button] ~= nil
        end
        if hiding then
            tracked[button] = isTracking(button.buttonInfo)
            -- Which is which is secret (in combat): show them all until it can be read.
            hiding = tracked[button] ~= nil
        end
    end
    if not (sorting or hiding) then
        unsort()
        return
    end
    local list, rest = {}, {}
    for _, button in ipairs(all) do
        if hiding and tracked[button] then
            rest[#rest + 1] = button
            hide(button)
        else
            list[#list + 1] = button
            unhide(button)
        end
    end
    if sorting then
        sort(list, function(a, b)
            if ends[a] ~= ends[b] then
                return ends[a] < ends[b]
            end
            return order[a] < order[b]
        end)
    end
    -- Slot 1 is the corner the buffs grow from: the right end unless Edit Mode's Icon Direction
    -- says right, and the top of a vertical bar unless it says up.
    local leftFirst
    if container.isHorizontal then
        leftFirst = container.addIconsToRight and true or false
    else
        leftFirst = not container.addIconsToTop
    end
    local n = #list
    local reverse = sorting and (side == "left") ~= leftFirst
    for k, button in ipairs(list) do
        place(button, reverse and n + 1 - k or k, order[button])
    end
    for k, button in ipairs(rest) do
        place(button, n + k, order[button])
    end
    for i = #all + 1, #frames do
        unhide(frames[i])
        place(frames[i], i, i)
    end
    showArrow(not (hiding and onlyTrackingFolds()))
end

local function onSpellsChanged()
    readTracking()
    layout()
end
module:OnWhile("hideTracking", { SPELLS_CHANGED = onSpellsChanged })

-- Blizzard just put every button back in its own place, maybe new ones (Edit Mode's settings).
local function afterGridLayout()
    readSlots()
    layout()
end

function module:OnEnable()
    readCVar()
    self:On("CVAR_UPDATE", onCVarUpdate)
    for _, button in ipairs(buttons()) do
        if type(button.UpdateDuration) == "function" and button.Duration then
            self:Hook(button, "UpdateDuration", update)
            self:Hook(button, "UpdateExpirationTime", expiration)
        end
    end
    self:Hook(BuffFrame, "UpdateAuraButtons", afterAuraButtons)
    self:Hook(DebuffFrame, "UpdateAuraButtons", afterAuraButtons)
    if BuffFrame and BuffFrame.auraFrames and BuffFrame.AuraContainer then
        self:Hook(BuffFrame.AuraContainer, "UpdateGridLayout", afterGridLayout)
        self:Hook(BuffFrame, "UpdateAuraButtons", layout)
        readSlots() -- off until now, so every button is where Blizzard put it
        readTracking()
        layout()
    end
end

function module:OnOptionChanged(key)
    if key == "hideTracking" then
        readTracking()
    end
    if key == "sort" or key == "hideTracking" then
        layout()
    end
end

function module:OnDisable()
    for button in pairs(texts) do
        restore(button)
    end
    unsort()
end
