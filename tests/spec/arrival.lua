-- Arrival: the time left from how fast a distance is closing, and when it says nothing.
local T = ...
local eq = T.eq

local ns = {}
T.load("Lib/Arrival", ns)
local Arrival = ns.Arrival

-- Feeds `est` a sample every `step` seconds from `from` to `to`, the distance given by `at(t)`,
-- and returns the last answer.
local function run(est, from, to, step, at)
    local seconds
    local t = from
    while t <= to + 1e-9 do
        seconds = est:Add(t, at(t))
        t = t + step
    end
    return seconds
end

local function near(got, want, name)
    eq(got ~= nil and math.abs(got - want) < 0.01, true, name .. " (" .. tostring(got) .. ")")
end

do -- a steady run: 7 yards a second from 700 yards
    local est = Arrival.New()
    local function running(t)
        return 700 - 7 * t
    end
    eq(run(est, 0, 1.75, 0.25, running), nil, "arrival: nothing before two seconds of samples")
    near(run(est, 2, 2, 0.25, running), (700 - 14) / 7, "arrival: a steady run after two seconds")
    near(run(est, 2.25, 10, 0.25, running), 90, "arrival: the window slides with the run")
end

do -- fed every frame, it keeps a sample a quarter second apart and answers the same between
    local est = Arrival.New()
    local seconds = run(est, 0, 5, 0.03, function(t)
        return 500 - 14 * t
    end)
    eq(seconds ~= nil and math.abs(seconds - (500 - 14 * 5) / 14) < 0.5, true,
        "arrival: every frame gives the same time (" .. tostring(seconds) .. ")")
    eq(est.count <= 18, true, "arrival: it keeps only the window's samples (" .. est.count .. ")")
    eq(est:Add(5.01, 0), seconds, "arrival: a sample too soon after the last is left out")
end

do -- standing still, and moving away
    local est = Arrival.New()
    eq(run(est, 0, 6, 0.25, function()
        return 300
    end), nil, "arrival: standing still")
    est:Reset()
    eq(run(est, 0, 6, 0.25, function(t)
        return 300 + 7 * t
    end), nil, "arrival: moving away")
    est:Reset()
    eq(run(est, 0, 6, 0.25, function(t)
        return 300 - 0.5 * t
    end), nil, "arrival: creeping closer is not heading there")
end

do -- an unsteady rate: stopped, then running
    local est = Arrival.New()
    local function stopAndGo(t)
        return t < 10 and 400 or 400 - 7 * (t - 10)
    end
    eq(run(est, 0, 11.5, 0.25, stopAndGo), nil, "arrival: just set off, not steady yet")
    near(run(est, 11.75, 16, 0.25, stopAndGo), (400 - 42) / 7, "arrival: steady once it has run")
    -- Then stops: the late half of the window stops closing.
    eq(run(est, 16.25, 18.5, 0.25, function()
        return 358
    end), nil, "arrival: stopped")
end

do -- a gap, a jump, a clock that went back, and Reset start it over
    local function running(t)
        return 700 - 7 * t
    end
    local est = Arrival.New()
    run(est, 0, 5, 0.25, running)
    eq(est:Add(8, running(8)), nil, "arrival: a gap in the samples starts over")
    eq(est.count, 1, "arrival: only the sample after the gap is kept")
    near(run(est, 8.25, 11, 0.25, running), (700 - 77) / 7, "arrival: and it finds the rate again")
    eq(est:Add(11.25, 200), nil, "arrival: a jump no travel explains starts over")
    run(est, 11.5, 14, 0.25, function(t)
        return 200 - 7 * (t - 11.25)
    end)
    eq(est:Add(3, 150), nil, "arrival: a clock that went back starts over")
    run(est, 3.25, 6, 0.25, function(t)
        return 150 - 7 * (t - 3)
    end)
    eq(est.seconds ~= nil, true, "arrival: an estimate before Reset")
    est:Reset()
    eq(est:Add(6.25, 120), nil, "arrival: Reset forgets it")
end

do -- too far to be worth a clock
    local est = Arrival.New()
    eq(run(est, 0, 5, 0.25, function(t)
        return 30000 - 7 * t
    end), nil, "arrival: more than an hour away")
end

eq(Arrival.Round(44.6), 45, "arrival: under a minute, to the second")
eq(Arrival.Round(59.4), 59, "arrival: 59 seconds")
eq(Arrival.Round(62), 60, "arrival: from a minute, to five seconds")
eq(Arrival.Round(183), 185, "arrival: three minutes")
