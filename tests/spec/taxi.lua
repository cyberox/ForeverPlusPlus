-- Taxi: the open flight master's nodes, read once a frame.
local T = ...
local ns, eq, ok, near, game = T.ns, T.eq, T.ok, T.near, T.game

do
    local Taxi = ns.Taxi
    local reads = 0
    local nodes, mapID = Taxi.Nodes()
    eq(#nodes == 0 and mapID == nil, true, "taxi: nothing without the API")
    game.now = 1
    C_TaxiMap = {
        GetAllTaxiNodes = function(map)
            reads = reads + 1
            return { { nodeID = map * 10 }, { nodeID = map * 10 + 1 } }
        end,
    }
    GetTaxiMapID = function() return 1414 end
    nodes, mapID = Taxi.Nodes()
    eq(#nodes == 2 and nodes[1].nodeID == 14140 and mapID == 1414, true, "taxi: the master's nodes")
    Taxi.Nodes()
    eq(reads, 1, "taxi: read once in a frame")
    game.now = 2
    GetTaxiMapID = function() return nil end
    nodes, mapID = Taxi.Nodes()
    eq(#nodes == 0 and mapID == nil and reads == 1, true, "taxi: no flight map open")
end

-- Estimates from the generated routes (build 70888): direct flights at 30 yards a second.
do
    local Taxi = ns.Taxi
    eq(Taxi.SPEED, 30, "taxi: flights cover 30 yards a second")
    eq(Taxi.RouteYards(2, 6), 7757, "taxi: Stormwind to Ironforge's path")
    eq(Taxi.RouteYards(6, 2), 6310, "taxi: each way is its own path")
    eq(Taxi.RouteYards(2, 999999), nil, "taxi: no path")
    local seconds, direct = Taxi.FlightEstimate({ 2, 6 })
    -- Timed at 259 s on 2026-11-11.
    eq(seconds, 259, "taxi: Stormwind to Ironforge, as flown")
    eq(direct, true, "taxi: a direct flight")
    eq(Taxi.FlightEstimate({ 2, 19 }), 244, "taxi: Stormwind to Booty Bay, as flown")
    eq(Taxi.FlightEstimate({ 6, 2 }), 210, "taxi: Ironforge to Stormwind, a second off its 211")
    -- Through Ironforge, less the loop down to it and back up: flown in 260 s, legs 299.
    local through, straight = Taxi.FlightEstimate({ 7, 6, 2 })
    eq(straight, false, "taxi: a flight with stops")
    ok(through >= 255 and through <= 270, "taxi: Menethil to Stormwind through Ironforge near 260")
    -- Kalimdor's legs only meet at the stop: flown in 261 s, the legs summed.
    eq(Taxi.FlightEstimate({ 27, 26, 28 }), 261, "taxi: Rut'theran to Astranaar through Auberdine")
    eq(Taxi.FlightEstimate({ 2, 999999 }), nil, "taxi: no estimate without a path")
    eq(Taxi.FlightEstimate({ 2 }), nil, "taxi: no estimate without a destination")
    eq(Taxi.FlightEstimate(nil), nil, "taxi: no estimate without a route")
    -- Every shortcut is a real stop between real legs, and shorter than them.
    local bad = 0
    for stop, froms in pairs(Taxi.SHORTCUTS) do
        for from, tos in pairs(froms) do
            for to, yards in pairs(tos) do
                local legs = (Taxi.RouteYards(from, stop) or 0) + (Taxi.RouteYards(stop, to) or 0)
                if yards <= 0 or yards >= legs then
                    bad = bad + 1
                end
            end
        end
    end
    eq(bad, 0, "taxi: shortcuts are shorter than their legs")

    -- The legs less the shortcut, with made-up routes.
    local routes, shortcuts = Taxi.ROUTES, Taxi.SHORTCUTS
    Taxi.ROUTES = { [1] = { [2] = 300 }, [2] = { [3] = 600 } }
    Taxi.SHORTCUTS = { [2] = { [1] = { [3] = 90 } } }
    eq(Taxi.FlightEstimate({ 1, 2, 3 }), 27, "taxi: legs less the shortcut at the stop")
    Taxi.SHORTCUTS = {}
    eq(Taxi.FlightEstimate({ 1, 2, 3 }), 30, "taxi: legs summed without one")
    Taxi.SPEED = 36
    eq(Taxi.FlightEstimate({ 1, 2 }), 8, "taxi: the speed is one number")
    Taxi.SPEED = 30

    -- Checking estimates against timed flights: only direct paths count.
    eq(Taxi.CheckEstimates({}), nil, "taxi: nothing to check")
    eq(Taxi.CheckEstimates({ ["1>3"] = 30 }), nil, "taxi: a flight with stops isn't checked")
    local check = Taxi.CheckEstimates({ ["1>2"] = 10, ["2>3"] = 25, ["x"] = 5, ["2>1"] = 9 })
    eq(check.count, 2, "taxi: direct flights checked")
    near(check.median, -10, "taxi: the median error")
    eq(check.worstRoute, "2>3", "taxi: the worst route")
    near(check.worst, -20, "taxi: its error, - when the flight was longer")
    near(check.speed, 27, "taxi: the median speed flown")
    Taxi.ROUTES, Taxi.SHORTCUTS = routes, shortcuts
end
