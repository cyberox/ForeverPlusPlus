-- Lib/TaxiRoutes.lua: the length in yards of every direct flight, from TaxiPath (which node each
-- path flies from and to) and TaxiPathNode (its points), for Flight Timer's estimates before a
-- flight is timed. A path's length is the sum of the distances between its points in order, on
-- one continent. Only paths between two flight points of TaxiNodes with a length are written; the
-- speed a flight covers them at lives in Lib/Taxi.lua, so a patch that changes it is one line.
local CSV = require("csv")
local Lua = require("luaout")

local M = {
    path = "ForeverPlusPlus/Lib/TaxiRoutes.lua",
    tables = { "TaxiNodes", "TaxiPath", "TaxiPathNode" },
}

local Int, Number = CSV.Int, CSV.Number
local sqrt, floor = math.sqrt, math.floor

-- For summary.lua: a route line's key (its from and to nodes), or a stop's line of shortcuts
-- (its stop and the leg in), and the line itself.
function M.Entry(line, state)
    if line:match("^ns%.Taxi%.SHORTCUTS") then
        state.shortcuts = true
        return
    end
    local node = line:match("^    %[(%d+)%] = {")
    if node then
        state.node = node
        return
    end
    if not state.node then
        return
    end
    if state.shortcuts then
        local from = line:match("^        %[(%d+)%] = {")
        if from then
            return "shortcut " .. from .. ">" .. state.node, line
        end
    else
        local to = line:match("^        %[(%d+)%] = %d+")
        if to then
            return "route " .. state.node .. ">" .. to, line
        end
    end
end

function M.Build(t, build, script)
    local names = {} -- node ID -> name
    for _, row in ipairs(CSV.Records(t.TaxiNodes, "TaxiNodes", { "ID", "Name_lang" })) do
        names[Int(row.ID, "TaxiNodes.ID")] = row.Name_lang
    end

    local points = {} -- path ID -> its points
    for _, row in ipairs(CSV.Records(t.TaxiPathNode, "TaxiPathNode", { "PathID", "NodeIndex",
        "ContinentID", "Loc_0", "Loc_1", "Loc_2" })) do
        local path = Int(row.PathID, "PathID")
        points[path] = points[path] or {}
        table.insert(points[path], {
            index = Int(row.NodeIndex, "NodeIndex"), continent = Int(row.ContinentID),
            x = Number(row.Loc_0), y = Number(row.Loc_1), z = Number(row.Loc_2),
        })
    end
    for _, list in pairs(points) do
        table.sort(list, function(a, b) return a.index < b.index end)
    end
    local function gap(a, b)
        if a.continent ~= b.continent then
            return nil
        end
        local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
        return sqrt(dx * dx + dy * dy + dz * dz)
    end
    -- Yards flown from the start of a path to each of its points.
    local function distances(list)
        local at = { 0 }
        for i = 2, #list do
            at[i] = at[i - 1] + (gap(list[i - 1], list[i]) or 0)
        end
        return at
    end
    local function length(path)
        local at = distances(points[path] or {})
        return floor(at[#at] + 0.5)
    end

    -- from -> to -> { yards, path }. Two paths for the same pair keep the newer one (the higher
    -- ID), as the old boat path 295 stands beside its replacement.
    local routes = {}
    for _, row in ipairs(CSV.Records(t.TaxiPath, "TaxiPath", { "ID", "FromTaxiNode", "ToTaxiNode" })) do
        local id = Int(row.ID, "TaxiPath.ID")
        local from, to = Int(row.FromTaxiNode, "FromTaxiNode"), Int(row.ToTaxiNode, "ToTaxiNode")
        local yards = length(id)
        if names[from] and names[to] and from ~= to and yards > 0 then
            routes[from] = routes[from] or {}
            local old = routes[from][to]
            if not old or old.path < id then
                routes[from][to] = { yards = yards, path = id }
            end
        end
    end

    -- Flying through a stop, the game doesn't land: timed flights through Ironforge were as long
    -- as the two legs joined where they first pass within JOIN yards of each other, skipping the
    -- loop down to the stop and back up (and in Kalimdor, where legs only meet at the stop, as
    -- long as the legs summed). For each stop, each leg in and each leg out, the yards that join
    -- saves, written when it's a second's flight or more. JOIN is the radius server emulators
    -- join legs within (TrinityCore's FlightPathMovementGenerator); it fit the timed flights best.
    -- Only the approach is skipped: both points are within NEAR yards of the stop (Ironforge's
    -- joins are about 450 away), so legs that double back over each other don't count as one.
    local JOIN, NEAR, WORTH = 40, 1000, 30
    local function saving(inPath, outPath)
        local a, b = points[inPath] or {}, points[outPath] or {}
        if #a == 0 or #b == 0 then
            return 0
        end
        local atA, atB = distances(a), distances(b)
        local whole = atA[#a] + atB[#b]
        local best = whole
        local stop = a[#a]
        -- The shortest of the joins at a point of the leg in near a point of the leg out.
        for i = 1, #a do
            local near = gap(a[i], stop)
            for j = 1, near and near <= NEAR and #b or 0 do
                local d = gap(a[i], b[j])
                local back = gap(b[j], stop)
                if d and d <= JOIN and back and back <= NEAR then
                    local joined = atA[i] + d + (atB[#b] - atB[j])
                    if joined < best then
                        best = joined
                    end
                end
            end
        end
        return floor(whole - best + 0.5)
    end
    local shortcuts = {} -- stop -> from -> to -> yards
    for stop, outs in pairs(routes) do
        for from, ins in pairs(routes) do
            local inRoute = ins[stop]
            if inRoute then
                for to, outRoute in pairs(outs) do
                    if to ~= from then
                        local yards = saving(inRoute.path, outRoute.path)
                        if yards >= WORTH then
                            shortcuts[stop] = shortcuts[stop] or {}
                            shortcuts[stop][from] = shortcuts[stop][from] or {}
                            shortcuts[stop][from][to] = yards
                        end
                    end
                end
            end
        end
    end

    local function sorted(set)
        local keys = {}
        for k in pairs(set) do
            keys[#keys + 1] = k
        end
        table.sort(keys)
        return keys
    end
    local froms = sorted(routes)

    local out = {
        "-- The length in yards of every direct flight, from the game's TaxiPath and TaxiPathNode",
        "-- tables: [fromNodeID] = { [toNodeID] = yards }, by the flight points' node IDs (C_TaxiMap's",
        "-- nodeID), with the path's ID in the comment. Each way is its own path. ns.Taxi.FlightEstimate",
        "-- turns them into seconds.",
        "--",
        "-- Generated by " .. script .. " from wago.tools' tables for build " .. build .. ".",
        "-- Don't edit it by hand: run the script again after a patch.",
        "local _, ns = ...",
        "",
        "ns.Taxi.ROUTES = {",
    }
    for _, from in ipairs(froms) do
        out[#out + 1] = ("    [%d] = { -- %s"):format(from, Lua.Comment(names[from]))
        for _, to in ipairs(sorted(routes[from])) do
            local route = routes[from][to]
            out[#out + 1] = ("        [%d] = %d, -- %s, path %d"):format(to, route.yards,
                Lua.Comment(names[to]), route.path)
        end
        out[#out + 1] = "    },"
    end
    out[#out + 1] = "}"
    out[#out + 1] = ""
    out[#out + 1] = "-- The yards a flight through a stop saves by not landing there:"
    out[#out + 1] = "-- [stopNodeID] = { [fromNodeID] = { [toNodeID] = yards } }, for the legs from -> stop -> to,"
    out[#out + 1] = "-- where the legs pass within " .. JOIN .. " yards of each other before the stop. None is 0."
    out[#out + 1] = "ns.Taxi.SHORTCUTS = {"
    for _, stop in ipairs(sorted(shortcuts)) do
        out[#out + 1] = ("    [%d] = { -- %s"):format(stop, Lua.Comment(names[stop]))
        for _, from in ipairs(sorted(shortcuts[stop])) do
            local parts = {}
            for _, to in ipairs(sorted(shortcuts[stop][from])) do
                parts[#parts + 1] = ("[%d] = %d"):format(to, shortcuts[stop][from][to])
            end
            out[#out + 1] = ("        [%d] = { %s },"):format(from, table.concat(parts, ", "))
        end
        out[#out + 1] = "    },"
    end
    out[#out + 1] = "}"
    return table.concat(out, "\n") .. "\n"
end

return M
