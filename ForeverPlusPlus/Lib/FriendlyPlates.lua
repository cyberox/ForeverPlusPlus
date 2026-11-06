-- Friendly nameplates that always show the unit's name, and the health bar only while it's hurt or
-- in combat. Built on Blizzard's own nameplates: the bar fades, Blizzard's name hides, and our label
-- (ns.PlateLabel) shows instead. Player Nameplates and NPC Nameplates each run one of these for
-- their own kind of unit:
--
--   local plates = ns.FriendlyPlates.New(module, {
--       players = true,             -- friendly players, or false for friendly NPCs
--       cvars = { { names = { "cvarName", "olderName" }, value = "1" }, ... },
--       style = { NameColor = fn, Subtitle = fn, SubtitleColor = fn, icons = bool },
--       OnEnable = fn(module), -- optional: more to do when the module turns on
--       Skip = fn(unit),       -- optional: true leaves this unit's plate to Blizzard
--   })
--   plates:Refresh() -- after a setting the plates draw from changed
--   plates:Recheck() -- after a setting Skip reads changed
--
-- New gives the module its OnEnable, OnDisable and OnOptionChanged (unless it has its own
-- OnDisable or OnOptionChanged). The module's settings come from FriendlyPlates.Defaults: they
-- need healthBar, level, levelFrame, levelSize, buffs, nameSize, centerLine, and `saved = {}` for
-- the CVars. FriendlyPlates.Options puts the General options at the top of the module's list.
local _, ns = ...

local pairs, ipairs, setmetatable, hooksecurefunc = pairs, ipairs, setmetatable, hooksecurefunc
local UnitIsPlayer, UnitIsFriend, UnitIsUnit = UnitIsPlayer, UnitIsFriend, UnitIsUnit
local UnitAffectingCombat, UnitHealthPercent = UnitAffectingCombat, UnitHealthPercent
local UnitHealth, UnitHealthMax, pcall, max = UnitHealth, UnitHealthMax, pcall, math.max

local readable = ns.IsReadable
local Nameplates, PlateLabel = ns.Nameplates, ns.PlateLabel

local FriendlyPlates = {}
ns.FriendlyPlates = FriendlyPlates

local Plates = {}
Plates.__index = Plates

local weak = { __mode = "k" }
-- Blizzard name font string -> { plates, unit } while one of ours shows on its plate
local mirrored = setmetatable({}, weak)
local hookedNames = setmetatable({}, weak)
local curve -- health fraction -> alpha: 1 below full health, 0 at full
local inverse -- the opposite: 0 below full health, 1 at full

local EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_FLAGS", "UNIT_NAME_UPDATE", "UNIT_LEVEL" }
-- When a group, friend (Battle.net ones too), or guild changes, so the icons and colors follow.
local SOCIAL_EVENTS = { "GROUP_ROSTER_UPDATE", "FRIENDLIST_UPDATE", "BN_FRIEND_INFO_CHANGED",
    "BN_FRIEND_LIST_SIZE_CHANGED", "PLAYER_GUILD_UPDATE" }

local hasEvent = ns.HasEvent

-- Blizzard sets the name text (with surname) itself; our label copies it and lays itself out
-- again as it changes.
local function onNameSet(fontString)
    local entry = mirrored[fontString]
    if entry then
        entry[1]:Layout(entry[2])
    end
end

local function hookName(name)
    if not hookedNames[name] then
        hookedNames[name] = true
        hooksecurefunc(name, "SetText", onNameSet)
    end
end

-- Blizzard's level at the bar's end. Which of the two frames draws the badge players see isn't
-- known yet (LevelFrame alone left it showing), so both fade with the bar.
local function fadeLevel(record, alpha)
    if record.levelFrame then
        record.levelFrame:SetAlpha(alpha)
    end
    if record.levelDiffFrame then
        record.levelDiffFrame:SetAlpha(alpha)
    end
end

-- Blizzard's buff row (UnitFrame.AurasFrame.BuffListFrame) sits beside the bar, to the left of its
-- classification icon, so on a name-only plate it floats far left of the name. There it moves to
-- the module's Buffs setting (`buffs`): above the whole row (level, name, and icons; and above the
-- bar view's name while the bar shows), or beside it past the level, icons, and guild/title line,
-- so it never covers them. Beside, it goes back beside the bar while the bar shows. The buff row
-- sizes itself to its icons.
-- The row is a restricted region: its anchors can be set but never read, so we put back
-- Blizzard's anchor from its XML (Blizzard_NamePlates.xml; Lua never changes it). pcall, so a
-- client that refuses the anchor can't stop the fade around it.
local BUFF_ABOVE_GAP = 6
local BUFF_SIDE_GAP = 4
-- While the bar shows: left of the bar itself, with room between. (Blizzard anchors past the
-- classification icon instead, which sat the row too close; a bigger offset from that icon
-- moved it inward on Forever, so the icon isn't where its XML suggests.)
local BUFF_BAR_GAP = 8

local aboveCurves = {} -- the name's rise -> a health curve giving the above row's y offset

-- How far the bar view's name (above the bar) sits above the name-only one, from sizes alone:
-- positions can't be read here, the plate's frames anchor to restricted ones.
local function nameRise(label)
    local ok, rowHeight = pcall(label.row.GetHeight, label.row)
    if not ok then
        return 0
    end
    local barHeight, nameHeight = label.barName:GetStringHeight(), label.name:GetStringHeight()
    if not (readable(rowHeight) and readable(barHeight) and readable(nameHeight)) then
        return 0
    end
    local barTop = rowHeight / 2 + 2 + barHeight -- see PlateLabel.Layout
    local nameTop = label.subtitle:IsShown() and 1 + nameHeight or nameHeight / 2
    return max(barTop - nameTop, 0)
end

-- Sets the buff row's anchor; run through pcall by anchorBuffs. A plain function rather than a
-- closure, since health changes call it often.
local function setBuffAnchor(record, label, where, x, y, secretY)
    local buffs = record.buffs
    buffs:ClearAllPoints()
    if where == "above" then
        -- A client that won't take a secret offset gets the bar view's height: clear of the
        -- bar, a little high over a name-only plate.
        local target = label.barName
        if not (secretY and pcall(buffs.SetPoint, buffs, "BOTTOM", target, "TOP", x, y)) then
            buffs:SetPoint("BOTTOM", target, "TOP", x, secretY and BUFF_ABOVE_GAP or y)
        end
    elseif where == "before" then
        buffs:SetPoint("RIGHT", label.name, "LEFT", x, 0)
    elseif where == "after" then
        buffs:SetPoint("LEFT", label.name, "RIGHT", x, 0)
    elseif where == "bar" then
        buffs:SetPoint("RIGHT", record.container, "LEFT", -BUFF_BAR_GAP, 0)
    else
        buffs:SetPoint("RIGHT", record.classification, "LEFT", -5, 0)
    end
end

---@param where string "above", "before", "after", "bar" (beside the bar), or "blizzard"
---(Blizzard's own anchor, for giving the plate back)
---@param unit string?
---@param state string? for "above": "bar" (showing), "name" (hidden), or "unsure" (it shows when
---the unit is hurt, but its health can't be read: the client picks the height from it)
local function anchorBuffs(record, where, unit, state)
    local buffs, label = record.buffs, record.label
    if not (buffs and record.classification and label) then
        return
    end
    local x, y
    local shift = label.nameShift or 0
    if where == "above" then
        -- Above the bar view's name, centered on the row; on a name-only plate, lowered to just
        -- above our name. Unsure, the client lowers it from the health (a secret we can't read).
        x = -(label.barNameShift or 0)
        -- Measured at each layout (Plates:Layout), not on every health tick.
        local rise = label.rise or nameRise(label)
        if state == "bar" then
            y = BUFF_ABOVE_GAP
        elseif state == "unsure" and unit and curve then
            local above = aboveCurves[rise]
            if not above then
                above = ns.HealthStepCurve(BUFF_ABOVE_GAP, BUFF_ABOVE_GAP - rise)
                aboveCurves[rise] = above
            end
            y = UnitHealthPercent(unit, true, above)
        else
            y = BUFF_ABOVE_GAP - rise
        end
    elseif where == "before" or where == "after" then
        -- Past the level and icons on that side, or past the guild/title line under the name if
        -- that reaches further (it's centered on the row, and often longer than the name).
        local before = where == "before"
        local reach = (before and label.leftWidth or label.rightWidth) or 0
        if label.subtitle:IsShown() then
            local nameWidth, subWidth = label.name:GetStringWidth(), label.subtitle:GetStringWidth()
            if readable(nameWidth) and readable(subWidth) then
                local overhang = (subWidth - nameWidth) / 2 + (before and shift or -shift)
                reach = max(reach, overhang)
            end
        end
        x = (before and -1 or 1) * (reach + BUFF_SIDE_GAP)
    end
    -- Untouched plates stay untouched, and an unchanged spot isn't set again (a secret height
    -- can't be compared, so that one is always set).
    local secretY = y ~= nil and not readable(y)
    if not secretY and (record.buffsWhere or "blizzard") == where and record.buffsX == x
        and record.buffsY == y then
        return
    end
    record.buffsWhere, record.buffsX, record.buffsY = where, x, (not secretY) and y or nil
    pcall(setBuffAnchor, record, label, where, x, y, secretY)
end

---Friendly plates for one module (see the top of this file).
---@param module table
---@param spec table players, cvars, style, and optional OnEnable and Skip
---@return table plates
function FriendlyPlates.New(module, spec)
    local self = setmetatable({ module = module, spec = spec, style = spec.style, records = {} }, Plates)
    ns.CVars.Track(module) -- its CVars come back at login if it was turned off in combat
    self.onAdded = function(unit, frame) self:Add(unit, frame) end
    self.onRemoved = function(unit) self:Remove(unit) end
    self.onUnitEvent = function(event, unit)
        -- A unit can come under a player's control (or leave it) with the plate still up.
        if event == "UNIT_FLAGS" and spec.Skip then
            self.onFaction(event, unit)
        end
        if self.records[unit] then
            if event == "UNIT_NAME_UPDATE" or event == "UNIT_LEVEL" then
                self:Layout(unit)
            end
            self:Fade(unit)
        end
    end
    self.onPlayerCombat = function()
        for unit in pairs(self.records) do
            self:Fade(unit)
        end
    end
    -- A unit turned hostile (a duel, a quest NPC) or friendly without its plate being added again:
    -- give the plate back to Blizzard, or take it over. Unknown (secret) changes nothing.
    self.onFaction = function(_, unit)
        local frame = Nameplates.FrameFor(unit)
        local ours = frame and self:IsOurs(unit)
        if ours == nil then
            return
        end
        if ours and not self.records[unit] then
            self:Add(unit, frame)
        elseif not ours and self.records[unit] then
            self:Remove(unit)
        end
    end
    -- Group, friends, or guild changed: the icons and colors may need to change.
    self.onSocialChange = function()
        for unit in pairs(self.records) do
            self:Layout(unit)
        end
    end
    -- The module's turning on and off and option changes are the same for every plate module. It
    -- keeps its own OnDisable and OnOptionChanged if it has them, and `spec.OnEnable(module)` adds
    -- to turning on.
    function module.OnEnable(mod)
        self:Enable()
        if spec.OnEnable then
            spec.OnEnable(mod)
        end
    end
    module.OnDisable = module.OnDisable or function()
        self:Disable()
    end
    module.OnOptionChanged = module.OnOptionChanged or function(mod)
        if mod.enabled then
            self:Recheck()
            self:Refresh()
        end
    end
    return self
end

---The settings every friendly plate module has, with `extra` (the module's own) added.
---@param extra table
---@return table defaults
function FriendlyPlates.Defaults(extra)
    extra.enabled = true
    extra.healthBar = "hurt" -- when the bar shows: "hurt" (or in combat), "combat", or "never"
    extra.nameSize = 80 -- percent of Blizzard's name size
    extra.level = "before" -- "before", "after", or "off"
    extra.levelFrame = "none" -- what the level sits in: see PlateLabel.LEVEL_FRAME_CHOICES
    extra.levelSize = 100 -- percent of Blizzard's level size
    extra.buffs = "above" -- where the buff row sits without the bar: see PlateLabel.BUFF_CHOICES
    extra.centerLine = false -- debug: a line through each plate's center
    extra.saved = {} -- CVar -> the player's own value, put back when the module turns off
    return extra
end

---For a module's migration step: its saved Health Bar When Hurt checkbox (`barWhenHurt`, through
---1.0.2) as the Health Bar setting it became. Off meant the bar showed only in combat.
---@param saved table|nil the module's saved settings
function FriendlyPlates.MigrateHealthBar(saved)
    if saved and saved.barWhenHurt ~= nil and saved.healthBar == nil then
        saved.healthBar = saved.barWhenHurt and "hurt" or "combat"
    end
end

---A module's options with the General ones for the settings in Defaults put first.
---@param barDescription string the Health Bar description, which names the kind of unit
---@param options table the module's own options, after General
---@return table options
function FriendlyPlates.Options(barDescription, options)
    local L = ns.L
    table.insert(options, 1, {
        key = "healthBar", name = L.PLATES_HEALTH_BAR, description = barDescription,
        choices = {
            { "hurt", L.PLATES_HEALTH_BAR_HURT },
            { "combat", L.PLATES_HEALTH_BAR_COMBAT },
            { "never", L.PLATES_HEALTH_BAR_NEVER },
        },
        section = L.PLATES_SECTION_GENERAL, changed = "1.0.3",
    })
    table.insert(options, 2, {
        key = "level", name = L.PLATES_LEVEL, description = L.PLATES_LEVEL_DESC,
        choices = PlateLabel.LEVEL_CHOICES, section = L.PLATES_SECTION_GENERAL,
    })
    table.insert(options, 3, {
        key = "levelFrame", name = L.PLATES_LEVEL_FRAME, description = L.PLATES_LEVEL_FRAME_DESC,
        choices = PlateLabel.LEVEL_FRAME_CHOICES, requires = "level", section = L.PLATES_SECTION_GENERAL,
        added = "1.0.3",
    })
    table.insert(options, 4, {
        key = "levelSize", name = L.PLATES_LEVEL_SIZE, description = L.PLATES_LEVEL_SIZE_DESC,
        min = 50, max = 200, step = 10, format = "%d%%", requires = "level",
        section = L.PLATES_SECTION_GENERAL, added = "1.0.3",
    })
    table.insert(options, 5, {
        key = "buffs", name = L.PLATES_BUFFS, description = L.PLATES_BUFFS_DESC,
        -- Sharing a side with the level is fine: the buffs go past it (placeBuffs).
        choices = PlateLabel.BUFF_CHOICES, section = L.PLATES_SECTION_GENERAL,
    })
    return options
end

-- Colors for the line under the name (an NPC's title, a player's guild).
FriendlyPlates.SUBTITLE_COLORS = {
    gray = ns.Colors.GRAY,
    green = ns.Colors.GUILD_GREEN,
}

-- Whether this is one of ours: a friendly player (or NPC). The personal resource display is a
-- friendly player too, so leave out ourselves, and any the module's Skip turns down (one it can't
-- tell about stays ours). Nil when the game won't say (secret values).
function Plates:IsOurs(unit)
    local isPlayer, isFriend, isSelf = UnitIsPlayer(unit), UnitIsFriend("player", unit),
        UnitIsUnit(unit, "player")
    if not (readable(isPlayer) and readable(isFriend) and readable(isSelf)) then
        return nil
    end
    if not (isFriend and not isSelf and (isPlayer and true or false) == self.spec.players) then
        return false
    end
    return not (self.spec.Skip and self.spec.Skip(unit))
end

---Takes over or gives back each plate on screen, after a setting the module's Skip reads changed.
function Plates:Recheck()
    if self.spec.Skip then
        Nameplates.ForEach(function(unit) self.onFaction(nil, unit) end)
    end
end

function Plates:Layout(unit)
    local record = self.records[unit]
    if record and record.label then
        PlateLabel.Layout(record.label, record, unit, self.style)
        record.label.rise = nameRise(record.label)
        -- The name, level, or icons may have moved; keep the buffs placed against them.
        if record.buffsWhere and record.buffsWhere ~= "blizzard" then
            self:PlaceBuffs(unit, record.buffsInCombat)
        end
    end
end

-- Fades the bar (and Blizzard's level with it) in when the unit is hurt or in combat (as the
-- module's Health Bar setting says), and our label in when it isn't.
function Plates:Fade(unit)
    local record = self.records[unit]
    if not record then
        return
    end
    local inCombat = UnitAffectingCombat(unit)
    if not readable(inCombat) then
        inCombat = UnitAffectingCombat("player")
    end
    local mode = self.module.db.healthBar
    local shown, hidden
    if mode == "never" then
        shown, hidden = 0, 1
    elseif inCombat then
        shown, hidden = 1, 0
    elseif mode ~= "hurt" then
        shown, hidden = 0, 1
    elseif not curve then
        shown, hidden = 1, 0
    else
        -- The percent can be secret in combat, so the client maps it to an alpha, not Lua.
        shown, hidden = UnitHealthPercent(unit, true, curve), UnitHealthPercent(unit, true, inverse)
    end
    record.container:SetAlpha(shown)
    local label = record.label
    if label then
        fadeLevel(record, shown)
        -- Blizzard's name is always hidden: our label draws the name in both views.
        record.name:SetAlpha(0)
        label.barFrame:SetAlpha(shown)
        label:SetAlpha(hidden)
    end
    self:PlaceBuffs(unit, inCombat)
end

-- Places the buff row for the bar's state. The alpha in Fade can be secret, so this asks again in
-- plain terms: "bar", "name", or "unsure". Friendly health reads as secret even out of combat,
-- so a plate that shows its bar when hurt is usually unsure.
function Plates:PlaceBuffs(unit, inCombat)
    local record = self.records[unit]
    if not record then
        return
    end
    local db = self.module.db
    local mode = db.healthBar
    local state
    if mode == "never" then
        state = "name"
    elseif inCombat or not curve and mode == "hurt" then
        state = "bar"
    elseif mode ~= "hurt" then
        state = "name"
    else
        local health, maxHealth = UnitHealth(unit), UnitHealthMax(unit)
        if readable(health) and readable(maxHealth) then
            state = health < maxHealth and "bar" or "name"
        else
            state = "unsure"
        end
    end
    record.buffsInCombat = inCombat
    local where = db.buffs
    -- Beside the name would sit on the bar. (Unsure, it stays beside the name: that's the usual
    -- case on a name-only plate, and a sideways move can't follow a secret like a height can.)
    if where ~= "above" and where ~= "blizzard" and state == "bar" then
        where = "bar"
    end
    anchorBuffs(record, where, unit, state)
end

function Plates:Add(unit, frame)
    local parts = Nameplates.Parts(frame)
    if not (parts.container and self:IsOurs(unit)) then
        return
    end
    local record = { container = parts.container }
    local name = parts.name
    if name and name.SetText then
        record.name = name
        record.levelFrame = parts.level
        record.levelDiffFrame = parts.levelDiff
        record.castBar = parts.castBar
        record.buffs = parts.buffs
        record.classification = parts.classification
        record.label = PlateLabel.Show(frame)
        hookName(name)
        mirrored[name] = { self, unit }
    end
    self.records[unit] = record
    self:Layout(unit)
    self:Fade(unit)
end

-- Plates are pooled, so everything we changed goes back as the plate leaves.
function Plates:Remove(unit)
    local record = self.records[unit]
    if not record then
        return
    end
    self.records[unit] = nil
    anchorBuffs(record, "blizzard")
    record.container:SetAlpha(1)
    fadeLevel(record, 1)
    if record.name then
        record.name:SetAlpha(1)
        mirrored[record.name] = nil
    end
    if record.label then
        PlateLabel.Hide(record.label)
    end
end

---Lays out and fades every plate again, after a setting changed.
function Plates:Refresh()
    for unit in pairs(self.records) do
        self:Layout(unit)
        self:Fade(unit)
    end
end

---Sets the CVars, and starts handling plates and their events (through module:On, so they stop
---when the module turns off).
function Plates:Enable()
    local module = self.module
    if not curve then
        curve, inverse = ns.HealthStepCurve(1, 0), ns.HealthStepCurve(0, 1)
    end
    self.style.db = module.db
    for _, entry in ipairs(self.spec.cvars) do
        ns.CVars.Set(module.db.saved, entry.names, entry.value)
    end
    for _, event in ipairs(EVENTS) do
        module:On(event, self.onUnitEvent)
    end
    if self.style.icons then
        for _, event in ipairs(SOCIAL_EVENTS) do
            if hasEvent(event) then
                module:On(event, self.onSocialChange)
            end
        end
    end
    module:On("UNIT_FACTION", self.onFaction)
    -- UNIT_FLAGS covers other units' combat; these cover the fallback to our own.
    module:On("PLAYER_REGEN_DISABLED", self.onPlayerCombat)
    module:On("PLAYER_REGEN_ENABLED", self.onPlayerCombat)
    Nameplates.Register(self, {
        OnAdded = self.onAdded,
        OnRemoved = self.onRemoved,
        OnCastBar = function(unit) self:Layout(unit) end,
    })
end

---Gives every plate back to Blizzard and puts the player's CVars back.
function Plates:Disable()
    Nameplates.Unregister(self)
    ns.CVars.RestoreAll(self.module.db.saved)
end
