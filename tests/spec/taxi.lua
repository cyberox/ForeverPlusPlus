-- Taxi: the open flight master's nodes, read once a frame.
local T = ...
local ns, eq, game = T.ns, T.eq, T.game

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
