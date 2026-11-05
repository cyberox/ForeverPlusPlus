-- Shared nameplate plumbing for modules: which nameplates are on screen, the parts of a Forever
-- nameplate by name, and when a plate's cast bar shows or hides. It listens to events only while
-- at least one module has registered, so it costs nothing otherwise.
--
--   ns.Nameplates.Register(owner, {
--       OnAdded = function(unit, frame) end,   -- a plate appeared (frame = plate.UnitFrame)
--       OnRemoved = function(unit, frame) end, -- it went away; undo changes, plates are pooled
--       OnCastBar = function(unit) end,        -- its cast bar just showed or hid
--   })
--
-- Friendly plates in instances are forbidden to addons and never show up here.
local _, ns = ...

local pairs, next, setmetatable, C_NamePlate = pairs, next, setmetatable, C_NamePlate

local Nameplates = {}
ns.Nameplates = Nameplates

local users = {} -- owner -> handlers
local frames = {} -- nameplate unit -> its UnitFrame, while on screen

-- Blizzard cast bar -> the unit whose plate it's on, while that plate is on screen. The bar's own
-- OnShow and OnHide say when it's drawn, which cast events don't: our event handler could run
-- before Blizzard's bar had shown, and a bar stays up after its stop event while it fades out
-- (and for a moment after an interrupt).
local barUnits = setmetatable({}, { __mode = "k" })
local hookedBars = setmetatable({}, { __mode = "k" })

-- Calls each user's handler; while the Profiler records, timed and charged to the user's module
-- (an owner that isn't a module itself carries it as `owner.module`).
local function dispatch(method, ...)
    local profiler = ns.Profiler
    local timed = profiler and profiler.recording
    for owner, handlers in pairs(users) do
        local fn = handlers[method]
        if fn then
            -- Through ns.Call: one module's error mustn't stop the other plate modules.
            if timed then
                profiler.Call(owner, ns.Call, fn, ...)
            else
                ns.Call(fn, ...)
            end
        end
    end
end

local function frameFor(unit)
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    return plate and plate.UnitFrame
end

-- A cast bar showed or hid. Hooks can't be removed, so this does nothing unless the bar's plate
-- is one we're tracking.
local function onBarChanged(bar)
    local unit = barUnits[bar]
    if unit and frames[unit] then
        dispatch("OnCastBar", unit)
    end
end

-- The bars are the cast bar container's children (a cast bar and, on some builds, others such as
-- an empowered one), or the container itself if it has none.
local function barsIn(container)
    local bars = { container:GetChildren() }
    if #bars == 0 then
        bars[1] = container
    end
    return bars
end

local function castBarsOf(frame)
    local container = frame.CastBarsContainer
    return container and barsIn(container) or nil
end

local function watchCastBars(unit, frame)
    local bars = castBarsOf(frame)
    if not bars then
        return
    end
    for i = 1, #bars do
        local bar = bars[i]
        barUnits[bar] = unit
        if not hookedBars[bar] then
            hookedBars[bar] = true
            bar:HookScript("OnShow", onBarChanged)
            bar:HookScript("OnHide", onBarChanged)
        end
    end
end

local function unwatchCastBars(frame)
    local bars = castBarsOf(frame)
    if bars then
        for i = 1, #bars do
            barUnits[bars[i]] = nil
        end
    end
end

local function onEvent(event, unit)
    if event == "NAME_PLATE_UNIT_ADDED" then
        local frame = frameFor(unit)
        frames[unit] = frame
        if frame then
            watchCastBars(unit, frame)
            dispatch("OnAdded", unit, frame)
        end
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        -- Remembered from when it was added, since the plate may already be gone.
        local frame = frames[unit]
        frames[unit] = nil
        if frame then
            unwatchCastBars(frame)
            dispatch("OnRemoved", unit, frame)
        end
    end
end

local EVENTS = { "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED" }

-- Picks up the plates already on screen.
local function scan()
    for _, plate in pairs(C_NamePlate.GetNamePlates()) do
        local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
        if unit and plate.UnitFrame then
            frames[unit] = plate.UnitFrame
            watchCastBars(unit, plate.UnitFrame)
        end
    end
end

---Starts calling `handlers` for nameplate changes, first with OnAdded for every plate on screen.
---@param owner any a key for Unregister, usually the module
---@param handlers table OnAdded, OnRemoved, OnCastBar (all optional)
function Nameplates.Register(owner, handlers)
    if users[owner] then
        return
    end
    if not next(users) then
        for _, event in pairs(EVENTS) do
            ns.On(event, onEvent)
        end
        scan()
    end
    users[owner] = handlers
    if handlers.OnAdded then
        for unit, frame in pairs(frames) do
            handlers.OnAdded(unit, frame)
        end
    end
end

---Stops calling `owner`'s handlers, first with OnRemoved for every plate on screen.
---@param owner any
function Nameplates.Unregister(owner)
    local handlers = users[owner]
    if not handlers then
        return
    end
    users[owner] = nil
    if handlers.OnRemoved then
        for unit, frame in pairs(frames) do
            handlers.OnRemoved(unit, frame)
        end
    end
    if not next(users) then
        for _, event in pairs(EVENTS) do
            ns.Off(event, onEvent)
        end
        for _, frame in pairs(frames) do
            unwatchCastBars(frame)
        end
        frames = {}
    end
end

---Calls `fn(unit, frame)` for every plate on screen (only while something is registered).
---@param fn fun(unit: string, frame: table)
function Nameplates.ForEach(fn)
    for unit, frame in pairs(frames) do
        fn(unit, frame)
    end
end

---The UnitFrame of a plate on screen, by its unit, or nil (only while something is registered).
---@param unit string
---@return table?
function Nameplates.FrameFor(unit)
    return frames[unit]
end

---Whether Blizzard is drawing a cast bar on this plate right now, fading out included. Friendly
---plates can hide cast bars, so casting alone doesn't mean one is there. `castBar` is
---Parts(frame).castBar, a container whose children are the bars; a visibility we can't read counts
---as hidden. Right for OnCastBar: the bar that just hid already reads as hidden.
---@param castBar table?
---@return boolean
function Nameplates.IsCastBarShown(castBar)
    if not castBar then
        return false
    end
    local bars = barsIn(castBar)
    for i = 1, #bars do
        local shown = bars[i]:IsVisible()
        if ns.IsReadable(shown) and shown then
            return true
        end
    end
    return false
end

---The parts of a nameplate's UnitFrame, under the names Forever uses (build 70009). Any may be
---nil on another build, so check before use. Anchor your frames to these or to the UnitFrame,
---never to the nameplate base (plate) above it: that fails with "anchor family connection" on
---12.x and breaks Blizzard's own anchors on the plate.
---@param frame table plate.UnitFrame
---@return table parts name, container (the health bar's frame), level, levelDiff, castBar, buffs,
---classification, elite
function Nameplates.Parts(frame)
    local auras = frame.AurasFrame
    return {
        -- The buff row beside the bar (a restricted region: set its anchors, never read them).
        buffs = auras and auras.BuffListFrame,
        classification = frame.ClassificationFrame, -- the buff row's anchor
        -- The elite, rare, or boss dragon at the bar's left end, while the unit is one.
        elite = frame.classificationIndicator
            or frame.ClassificationFrame and frame.ClassificationFrame.classificationIndicator,
        name = frame.name or frame.Name,
        container = frame.HealthBarsContainer or frame.healthBar,
        level = frame.LevelFrame, -- Forever-only: the level badge at the bar's end
        levelDiff = frame.PlayerLevelDiffFrame,
        castBar = frame.CastBarsContainer,
    }
end
