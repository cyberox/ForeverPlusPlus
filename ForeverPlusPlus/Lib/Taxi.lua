-- The open flight master's flight points, as Mainline's C_TaxiMap.GetAllTaxiNodes lists them on
-- its map. Several modules read them when the flight map opens (TAXIMAP_OPENED); the list is read
-- once per frame and shared, whichever of them asks first.
local _, ns = ...

local GetTime = GetTime
local abs, floor, pairs, sort, type = math.abs, math.floor, pairs, table.sort, type
local match, tonumber, tostring = string.match, tonumber, tostring

local Taxi = {}
ns.Taxi = Taxi

-- Yards a second a flight covers. Every direct flight the developer timed on build 70888 took its
-- path's length (Lib/TaxiRoutes.lua) / 29.7 to 30.0 seconds (docs/forever-api.md, Flight times).
-- A patch that changes flight speed is this one number.
Taxi.SPEED = 30

-- Filled by the generated Lib/TaxiRoutes.lua, which loads after this file.
Taxi.ROUTES = {}
Taxi.SHORTCUTS = {}

---The length in yards of the direct flight from one flight point to another (C_TaxiMap's node
---IDs), from the game's tables, or nil when there's no such path.
---@param from number
---@param to number
---@return number?
function Taxi.RouteYards(from, to)
    local routes = Taxi.ROUTES[from]
    return routes and routes[to] or nil
end

---Estimated seconds a flight takes, from its flight points in order (from, each stop, to), or
---nil when a leg isn't in the game's tables. A direct flight is its path at SPEED; a flight with
---stops is its legs less what it saves at each stop by not landing (Taxi.SHORTCUTS), rougher,
---since how the game joins legs is inferred from timed flights, not read from it.
---@param hops number[] node IDs, at least two
---@return number? seconds
---@return boolean? direct true for a flight without stops
function Taxi.FlightEstimate(hops)
    if type(hops) ~= "table" or #hops < 2 then
        return nil
    end
    local yards = 0
    for i = 2, #hops do
        local leg = Taxi.RouteYards(hops[i - 1], hops[i])
        if not leg then
            return nil
        end
        yards = yards + leg
        if i > 2 then
            local stop = Taxi.SHORTCUTS[hops[i - 1]]
            local from = stop and stop[hops[i - 2]]
            yards = yards - (from and from[hops[i]] or 0)
        end
    end
    if yards <= 0 then
        return nil
    end
    return floor(yards / Taxi.SPEED + 0.5), #hops == 2
end

-- A flight still under way after a reload: how long past its length it may run (an estimate can
-- be short, and a clock has whole seconds), and the longest a flight of unknown length can be.
local RESUME_SLACK, RESUME_LONGEST = 60, 1800

---Seconds a flight has been under way, from when it took off (`at`, by the clock) to `now`, or
---nil when it can't still be the same flight: no takeoff, a clock that went back, or longer
---ago than its length (`total`, with half again and a minute for a short estimate) allows.
---@param at number? the clock's seconds at takeoff
---@param total number? the flight's seconds, when known or estimated
---@param now number the clock's seconds now
---@return number? elapsed
function Taxi.ResumeElapsed(at, total, now)
    if type(at) ~= "number" or type(now) ~= "number" then
        return nil
    end
    local elapsed = now - at
    local longest = type(total) == "number" and total * 1.5 + RESUME_SLACK or RESUME_LONGEST
    if elapsed < 0 or elapsed > longest then
        return nil
    end
    return elapsed
end

local function median(list)
    sort(list)
    local n = #list
    if n % 2 == 1 then
        return list[(n + 1) / 2]
    end
    return (list[n / 2] + list[n / 2 + 1]) / 2
end

---How far the estimates of direct flights are from timed ones, to check SPEED after a patch.
---Only routes with a direct path count: which way the game routed a flight with stops isn't saved.
---@param times table<string, number> seconds by "fromNodeID>toNodeID", as Flight Timer saves them
---@return table? check { count, median, worst (percent the estimate is off, + when longer), worstRoute, speed (median yards a second flown) }, nil with none to check
function Taxi.CheckEstimates(times)
    local errors, speeds = {}, {}
    local worst, worstRoute
    for route, seconds in pairs(times or {}) do
        local from, to = match(tostring(route), "^(%d+)>(%d+)$")
        local yards = from and Taxi.RouteYards(tonumber(from), tonumber(to))
        if yards and type(seconds) == "number" and seconds > 0 then
            local off = (yards / Taxi.SPEED - seconds) / seconds * 100
            errors[#errors + 1] = off
            speeds[#speeds + 1] = yards / seconds
            if not worst or abs(off) > abs(worst) or (abs(off) == abs(worst) and route < worstRoute) then
                worst, worstRoute = off, route
            end
        end
    end
    if #errors == 0 then
        return nil
    end
    return { count = #errors, median = median(errors), worst = worst, worstRoute = worstRoute,
        speed = median(speeds) }
end

local nodes, mapID, readAt = {}, nil, nil

---The flight points the open flight master lists (Mainline's node tables: nodeID, slotIndex,
---name, state, position, ...), and the map they're on. Empty when no flight map is open or this
---client can't say. The list is shared: read it, don't change it.
---@return table[] nodes
---@return number? mapID
function Taxi.Nodes()
    local now = GetTime()
    if readAt == now then
        return nodes, mapID
    end
    nodes, mapID, readAt = {}, nil, now
    -- Probe: both are Mainline's.
    if C_TaxiMap and C_TaxiMap.GetAllTaxiNodes and GetTaxiMapID then
        mapID = GetTaxiMapID()
        nodes = mapID and C_TaxiMap.GetAllTaxiNodes(mapID) or nodes
    end
    return nodes, mapID
end
