-- Profiler: nothing timed while off, each call's own time charged to its module (a call inside
-- another counts once, for the inner one), a module's time split by source and added up across
-- its parts, the worst frames kept as spikes, and memory growth.
local T = ...
local ns, eq, near, game = T.ns, T.eq, T.near, T.game

-- A stopwatch the spec moves: a fake call "takes" ms by moving it.
local ms = 0
debugprofilestop = function() return ms end
local inCombat = false
InCombatLockdown = function() return inCombat end
-- The once-a-frame frame Profiler makes while recording; the spec runs its OnUpdate by hand.
local onUpdate
CreateFrame = function()
    return {
        SetScript = function(_, _, fn) onUpdate = fn end,
        Show = function() end,
        Hide = function() end,
    }
end
wipe = function(t)
    for k in pairs(t) do
        t[k] = nil
    end
    return t
end
local memory = 1000
UpdateAddOnMemoryUsage = function() end
GetAddOnMemoryUsage = function() return memory end
T.load("Locales/enUS/Tools")
T.load("Lib/Profiler") -- it caches debugprofilestop, CreateFrame, and InCombatLockdown
local Profiler = ns.Profiler

local function takes(spent)
    return function(...)
        ms = ms + spent
        return ...
    end
end

local A = { name = "A", title = "Module A" }
local B = { name = "B", title = "Module B" }
local partA = { module = A, key = "part" } -- a part made with module:NewPart

-- Off: calls go straight through and nothing is kept.
eq(Profiler.CallFrom(A, "BAG_UPDATE", takes(5), "result"), "result", "profiler: off, the call's result")
eq(#Profiler.Results(), 0, "profiler: off, nothing recorded")
eq(Profiler.Wrap(A, takes(1))("x"), "x", "profiler: off, a wrapped call goes through")

Profiler.Start()
game.now = 0
Profiler.CallFrom(A, "BAG_UPDATE", takes(3))
Profiler.CallFrom(A, "BAG_UPDATE", takes(2))
Profiler.CallFrom(partA, "UNIT_AURA", takes(4))
-- B's call runs A's inside it: A's 1 ms is A's alone, and B keeps only its own 2.
Profiler.CallFrom(B, "GameTooltip:Show", function()
    ms = ms + 2
    Profiler.CallFrom(A, "BAG_UPDATE", takes(1))
end)
game.now = 10
onUpdate()

local results = Profiler.Results()
local byName = {}
for _, result in ipairs(results) do
    byName[result.key.name] = result
end
local a, b = byName.A, byName.B
eq(results[1] and results[1].key, A, "profiler: the heaviest module first")
near(a and a.total, 10, "profiler: a module adds up its own calls and its parts'")
near(b and b.total, 2, "profiler: a call inside another counts once, for the inner one")
eq(a and a.parts and #a.parts, 1, "profiler: the part under its module")

local sources = {}
for _, source in ipairs(a and a.sources or {}) do
    sources[source.key.label] = source
end
near(sources.BAG_UPDATE and sources.BAG_UPDATE.total, 6, "profiler: a source adds up its calls")
eq(sources.BAG_UPDATE and sources.BAG_UPDATE.callsPerSecond, 0.3, "profiler: and counts them")
near(sources.UNIT_AURA and sources.UNIT_AURA.total, 4, "profiler: a part's sources show under its module")
eq(a and a.sources and a.sources[1].key.label, "BAG_UPDATE", "profiler: the heaviest source first")
eq(b and b.sources and b.sources[1].key.label, "GameTooltip:Show", "profiler: a hook's source")

-- A plain Call names no source; Wrap names Updates by default.
Profiler.Call(B, takes(1))
Profiler.Wrap(B, takes(1))()
local labels = {}
for _, result in ipairs(Profiler.Results()) do
    if result.key == B then
        for _, source in ipairs(result.sources or {}) do
            labels[#labels + 1] = source.key.label
        end
    end
end
table.sort(labels)
eq(table.concat(labels, ","), "GameTooltip:Show," .. Profiler.SOURCE_UPDATE,
    "profiler: a wrapped update is a source; a plain call isn't")

-- Spikes: the frame above took 12 ms in all, under the line; this one takes 20, in combat.
eq(#Profiler.Spikes(), 0, "profiler: no spike under " .. Profiler.SPIKE_MS .. " ms")
onUpdate() -- closes the frame with the two calls above (2 ms)
inCombat = true
game.now = 12
Profiler.CallFrom(A, "BAG_UPDATE", takes(5))
Profiler.CallFrom(B, "PLAYER_TARGET_CHANGED", takes(15))
onUpdate()
inCombat = false
local spike = Profiler.Spikes()[1]
near(spike and spike.ms, 20, "profiler: a frame over the line is a spike, with all of its time")
eq(spike and spike.key, B, "profiler: charged to the call that took the most of it")
eq(spike and spike.source, "PLAYER_TARGET_CHANGED", "profiler: with that call's source")
eq(spike and spike.combat, true, "profiler: and whether it was in combat")
near(spike and spike.at, 12, "profiler: and when, into the recording")
for i = 1, 12 do
    Profiler.Call(A, takes(16 + i))
    onUpdate()
end
local kept = Profiler.Spikes()
eq(#kept, 10, "profiler: only the worst spikes are kept")
eq(kept[1].ms > kept[#kept].ms, true, "profiler: worst first")

-- Memory: how fast it grew since Record.
memory = 1500
near(Profiler.MemoryGrowth(memory), 500 / 12, "profiler: memory growth in KB a second")

Profiler.Reset()
eq(#Profiler.Spikes() + #Profiler.Results(), 0, "profiler: Clear forgets it all")
Profiler.Stop()
ms = 0
eq(Profiler.CallFrom(A, "BAG_UPDATE", takes(5), 7), 7, "profiler: stopped, calls go straight through again")
eq(#Profiler.Results(), 0, "profiler: and nothing more is kept")
