-- How much CPU each module takes, for the Profiler page (Modules/Tools/Profiler.lua). The game
-- measures only the addon as a whole (C_AddOnProfiler), so while recording, each call into a
-- module's code is timed and charged to its module: events and hooks through Core.lua, callbacks
-- the shared Lib files run for modules, and per-frame updates a module wraps with Profiler.Wrap.
-- Time a timed call spends inside another timed call is charged to the inner one only.
-- Paths that know what ran (Core's events and hooks, the shared Lib callbacks, timers, updates)
-- say so with Profiler.CallFrom, so a module's time is also split by source ("BAG_UPDATE",
-- "GameTooltip:Show"), and each frame Forever++ took more than SPIKE_MS in is kept as a spike,
-- with the call that took the most of it.
-- Off (the default) nothing is timed: each of those paths checks `recording` and calls straight
-- through, and no frame runs. A hook's source name is made once, when it's hooked, not per call.
local _, ns = ...

local pairs, ipairs, type, sort, wipe = pairs, ipairs, type, table.sort, wipe
local debugprofilestop, GetTime, CreateFrame = debugprofilestop, GetTime, CreateFrame
local InCombatLockdown = InCombatLockdown
local L = ns.L

local Profiler = { recording = false }
ns.Profiler = Profiler

-- The key for code no module owns: the Lib files' own event handlers and anything else not
-- traced to a module.
local SHARED = {}
Profiler.SHARED = SHARED

-- Sources for paths with no name of their own: a module's OnUpdate (Profiler.Wrap), a delayed
-- run (Frames.Coalesce), a timer (Frames.Timer), and item tooltip lines (Lib/ItemTooltip.lua).
Profiler.SOURCE_UPDATE = L.PROFILER_SOURCE_UPDATE
Profiler.SOURCE_DELAYED = L.PROFILER_SOURCE_DELAYED
Profiler.SOURCE_TIMER = L.PROFILER_SOURCE_TIMER
Profiler.SOURCE_TOOLTIP = L.PROFILER_SOURCE_TOOLTIP

local SPIKE_MS = 16 -- a frame Forever++ took longer than this in (a whole frame at 60 fps) is a spike
local MAX_SPIKES = 10 -- the worst ones kept
Profiler.SPIKE_MS = SPIKE_MS

-- key -> { total = ms, calls, frame = ms this frame, peak = most ms in one frame }: each key's own
-- time, and in `groups` a module's together with its parts' (Profiler.Part).
local stats = {}
local groups = {}
local sources = {} -- key -> source -> sums like stats', of the key's own time from that source
local spikes = {} -- the worst frames, worst first: { at (seconds in), ms, key, source, combat }
local frameTotal = 0 -- Forever++'s own ms this frame
local topMs, topKey, topSource = 0, nil, nil -- the call that took the most of this frame
local started, stopped -- GetTime() when recording started and stopped (nil while it runs)
local startMemory -- KB when recording started
local depth = 0 -- timed calls under way, one inside another
local inner = {} -- depth -> ms spent in timed calls inside the one at that depth
local frame -- closes each frame's sums while recording

local function entry(list, key)
    local s = list[key]
    if not s then
        s = { total = 0, calls = 0, frame = 0, peak = 0 }
        list[key] = s
    end
    return s
end

local function closeFrame(list)
    for _, s in pairs(list) do
        if s.frame > s.peak then
            s.peak = s.frame
        end
        s.frame = 0
    end
end

-- Keeps this frame as a spike, among the worst MAX_SPIKES. Only for a frame over SPIKE_MS, so
-- rarely.
local function keepSpike()
    spikes[#spikes + 1] = {
        at = started and GetTime() - started or 0, ms = frameTotal, key = topKey, source = topSource,
        combat = InCombatLockdown() and true or false,
    }
    sort(spikes, function(a, b) return a.ms > b.ms end)
    spikes[MAX_SPIKES + 1] = nil
end

-- Once a frame while recording: each module's time this frame against its worst, and the frame
-- as a spike if Forever++ took too long in it. A call that errored never closed its depth, so the
-- count starts over here too.
local function onUpdate()
    closeFrame(stats)
    closeFrame(groups)
    for _, list in pairs(sources) do
        closeFrame(list)
    end
    if frameTotal > SPIKE_MS then
        keepSpike()
    end
    frameTotal, topMs, topKey, topSource = 0, 0, nil, nil
    depth = 0
end

-- Times `fn(...)` for `key` (and `source`, when known) and returns its first result. Only while
-- recording; the callers check.
local function timed(key, source, fn, ...)
    -- A part of a module (module:NewPart) is a row of its own under the module, like
    -- Profiler.Part; any other owner that stands in for a module is charged to the module.
    if type(key) == "table" and key.module and not key.key then
        key = key.module
    end
    depth = depth + 1
    local level = depth
    inner[level] = 0
    local start = debugprofilestop()
    local result = fn(...)
    local spent = debugprofilestop() - start
    depth = level - 1
    if level > 1 then
        inner[level - 1] = (inner[level - 1] or 0) + spent
    end
    local own = spent - inner[level]
    key = key or SHARED
    local s = entry(stats, key)
    s.total = s.total + own
    s.frame = s.frame + own
    s.calls = s.calls + 1
    local g = entry(groups, key.parent or key.module or key)
    g.total = g.total + own
    g.frame = g.frame + own
    if source then
        local bySource = sources[key]
        if not bySource then
            bySource = {}
            sources[key] = bySource
        end
        local src = entry(bySource, source)
        src.total = src.total + own
        src.frame = src.frame + own
        src.calls = src.calls + 1
    end
    frameTotal = frameTotal + own
    if own > topMs then
        topMs, topKey, topSource = own, key, source
    end
    return result
end

---Calls `fn(...)` and returns its first result. While recording, the time it takes is charged to
---`key`: a module (a part is charged to its module), or nil for shared code.
---@param key table?
---@param fn function
---@return any
function Profiler.Call(key, fn, ...)
    if not Profiler.recording then
        return (fn(...))
    end
    return timed(key, nil, fn, ...)
end

---Profiler.Call for a path that knows what ran: `source` names it on the page under its module
---(an event, "GameTooltip:Show", one of Profiler.SOURCE_*). Make the name once, not per call.
---@param key table?
---@param source string
---@param fn function
---@return any
function Profiler.CallFrom(key, source, fn, ...)
    if not Profiler.recording then
        return (fn(...))
    end
    return timed(key, source, fn, ...)
end

---Counts a call to `key` without timing it, for something called thousands of times a second,
---where a stopwatch around each would cost more than the call. Only while recording.
---@param key table
function Profiler.Count(key)
    local s = entry(stats, key)
    s.calls = s.calls + 1
    s.counted = true
    entry(groups, key.parent or key.module or key)
end

---A key for one part of a module's work, listed on the page under its module, so a heavy module
---can show which of its parts the time goes to. The module's row adds up its parts. A module's
---parts made with module:NewPart get rows of their own without this.
---@param module table
---@param label string
---@return table key for Profiler.Call
function Profiler.Part(module, label)
    return { parent = module, label = label }
end

---A function that calls `fn` and, while recording, charges it to `key`: for a module's OnUpdate
---script, timers, and other code that doesn't come through Core. `source` names it on the page
---(Profiler.SOURCE_UPDATE by default). Wrap the work inside a throttle, not the throttle:
---`Frames.Throttled(0.5, Profiler.Wrap(module, fn))`, so only the runs that do something are
---timed and counted, not every frame the throttle skips.
---@param key table the module
---@param fn function
---@param source? string
---@return function
function Profiler.Wrap(key, fn, source)
    source = source or Profiler.SOURCE_UPDATE
    return function(...)
        if Profiler.recording then
            return timed(key, source, fn, ...)
        end
        return fn(...)
    end
end

---Starts recording from nothing.
function Profiler.Start()
    Profiler.recording = true
    Profiler.Reset() -- recording, so it starts the clock and the memory count from now
    if not frame then
        frame = CreateFrame("Frame")
        frame:SetScript("OnUpdate", onUpdate)
    end
    frame:Show()
end

---Stops recording, keeping what it found.
function Profiler.Stop()
    if not Profiler.recording then
        return
    end
    onUpdate() -- the last frame's sums count toward the worst frame
    Profiler.recording = false
    stopped = GetTime()
    frame:Hide()
end

---Forgets what was recorded; recording goes on from now if it was running.
function Profiler.Reset()
    wipe(stats)
    wipe(groups)
    wipe(sources)
    wipe(spikes)
    frameTotal, topMs, topKey, topSource = 0, 0, nil, nil
    depth = 0
    started = Profiler.recording and GetTime() or nil
    stopped = nil
    startMemory = nil
    if Profiler.recording then
        local _, _, memory = Profiler.AddOn()
        startMemory = memory
    end
end

---Seconds recorded so far, or nil before the first recording.
---@return number?
function Profiler.Elapsed()
    return started and (stopped or GetTime()) - started or nil
end

local function heaviest(a, b)
    return a.total > b.total
end

-- One row of Results from a key's sums.
local function row(key, s, seconds, calls)
    return {
        key = key, total = s.total, peak = s.frame > s.peak and s.frame or s.peak,
        perSecond = seconds > 0 and s.total / seconds or 0,
        callsPerSecond = seconds > 0 and calls / seconds or 0,
        counted = s.counted, -- only counted (Profiler.Count): it has calls but no time
    }
end

-- The sources of `keys` (a module and its parts) added together by name, heaviest first, as rows
-- whose key is { label = source }; nil when none was named.
local function sourceRows(keys, seconds)
    local merged
    for _, key in ipairs(keys) do
        for source, s in pairs(sources[key] or {}) do
            merged = merged or {}
            local m = merged[source]
            if not m then
                m = { total = 0, calls = 0, frame = 0, peak = 0 }
                merged[source] = m
            end
            m.total = m.total + s.total
            m.calls = m.calls + s.calls
            local peak = s.frame > s.peak and s.frame or s.peak
            if peak > m.peak then
                m.peak = peak
            end
        end
    end
    if not merged then
        return nil
    end
    local list = {}
    for source, m in pairs(merged) do
        list[#list + 1] = row({ label = source }, m, seconds, m.calls)
    end
    sort(list, heaviest)
    return list
end

---What was recorded, heaviest first: a row for each module (Profiler.SHARED for shared code)
---with its parts' time added in, and the parts in `parts`, heaviest first, with the module's own
---time beside them as `own` (nil without parts), and in `sources` what its time (and its parts')
---went to by source, heaviest first. A row is { key, total, peak, perSecond, callsPerSecond,
---counted }, times in ms; a part's or a source's key has `label`.
---@return table[]
function Profiler.Results()
    local seconds = Profiler.Elapsed() or 0
    local list, byKey = {}, {}
    for key, g in pairs(groups) do
        local own = stats[key]
        local result = row(key, g, seconds, own and own.calls or 0)
        list[#list + 1] = result
        byKey[key] = result
    end
    for key, s in pairs(stats) do
        local parent = key.parent or key.module
        local result = parent and byKey[parent]
        if result then
            result.parts = result.parts or {}
            result.parts[#result.parts + 1] = row(key, s, seconds, s.calls)
        end
    end
    for _, result in ipairs(list) do
        local keys = { result.key }
        for _, part in ipairs(result.parts or {}) do
            keys[#keys + 1] = part.key
        end
        result.sources = sourceRows(keys, seconds)
        if result.parts then
            sort(result.parts, heaviest)
            local own = stats[result.key]
            if own then
                result.own = row(result.key, own, seconds, own.calls)
            end
            -- With no calls of its own, the module ran as often as its busiest part.
            if result.callsPerSecond == 0 then
                for _, part in ipairs(result.parts) do
                    if part.callsPerSecond > result.callsPerSecond then
                        result.callsPerSecond = part.callsPerSecond
                    end
                end
            end
        end
    end
    sort(list, heaviest)
    return list
end

---The worst frames recorded, worst first: { at (seconds into the recording), ms (Forever++'s
---own time that frame), key (whose call took the most of it), source (that call's, or nil),
---combat }. Don't change them.
---@return table[]
function Profiler.Spikes()
    return spikes
end

---KB a second Forever++'s memory grew by since recording started (less than 0 when the game
---collected more than it made), or nil when this client can't say or nothing was recorded.
---@param memory? number KB now (Profiler.AddOn's)
---@return number?
function Profiler.MemoryGrowth(memory)
    local seconds = Profiler.Elapsed()
    if not (startMemory and memory and seconds and seconds > 0) then
        return nil
    end
    return (memory - startMemory) / seconds
end

---Forever++ as a whole, from the game: its average and its most ms in one frame, lately
---(C_AddOnProfiler), and its memory in KB. Any of them is nil when this client can't say.
---@return number? average
---@return number? peak
---@return number? memory
function Profiler.AddOn()
    local average, peak
    local profiler, metric = C_AddOnProfiler, Enum and Enum.AddOnProfilerMetric
    if profiler and profiler.GetAddOnMetric and metric then
        average = profiler.GetAddOnMetric(ns.name, metric.RecentAverageTime)
        peak = profiler.GetAddOnMetric(ns.name, metric.PeakTime)
    end
    local update = UpdateAddOnMemoryUsage or (C_AddOns and C_AddOns.UpdateAddOnMemoryUsage)
    local get = GetAddOnMemoryUsage or (C_AddOns and C_AddOns.GetAddOnMemoryUsage)
    local memory
    if update and get then
        update()
        memory = get(ns.name)
    end
    return average, peak, memory
end
