-- Minimap Node Icons' /fpp nodes, /fpp nodes here, and /fpp nodes probe (only while the module is
-- on, which Core checks before running the command): what the probes see, and where a dot answers
-- against where its icon is, for finding out in game why icons don't show or sit off their dots.
local _, ns = ...

local ipairs, floor, tostring, format = ipairs, math.floor, tostring, string.format
local min, concat = math.min, table.concat
local Minimap, C_Timer, UIParent, GetCVar = Minimap, C_Timer, UIParent, GetCVar
local GetCursorPosition, InCombatLockdown = GetCursorPosition, InCombatLockdown

local L = ns.L

local module = ns.modules.MinimapNodeIcons
local internal = module.internal

local NONE = internal.NONE

-- /fpp nodes ----------------------------------------------------------------------------------------
-- What the probes see, for finding out in game why no icons show: whether tracking is on, and a
-- whole pass in each space with the names it found. The space whose pass finds the most nodes is
-- saved.

local REPORT_NAMES = 4 -- names listed for each space

local function report()
    if InCombatLockdown() then
        ns.Print(L.MINIMAPNODEICONS_REPORT_COMBAT)
        return
    end
    internal.readTracking()
    local v = internal.readView()
    ns.Print(format(L.MINIMAPNODEICONS_REPORT_STATE,
        internal.tracking and L.MINIMAPNODEICONS_REPORT_YES or L.MINIMAPNODEICONS_REPORT_NO,
        v and L.MINIMAPNODEICONS_REPORT_YES or L.MINIMAPNODEICONS_REPORT_NO,
        floor(Minimap:GetWidth() + 0.5), v and format("%.1f", v.scale * 100) or "?"))
    local list = internal.grid(Minimap:GetWidth() / 2, internal.STEPS.high)
    local best, bestCount = nil, 0
    for _, space in ipairs(internal.ORDER) do
        local names, order, count = {}, {}, 0
        internal.startProbing()
        for _, point in ipairs(list) do
            local found = internal.probe(point[1], point[2], space)
            if internal.blocked then
                internal.stopProbing()
                return
            end
            for _, entry in ipairs(found or NONE) do
                local name = entry.name
                if not names[name] then
                    names[name] = true
                    order[#order + 1] = name
                    if internal.iconFor(name) then
                        count = count + 1
                    end
                end
            end
        end
        internal.stopProbing()
        local shown = {}
        for i = 1, min(#order, REPORT_NAMES) do
            shown[i] = order[i]
        end
        ns.Print(format(L.MINIMAPNODEICONS_REPORT_SPACE, space, #order, count,
            #shown > 0 and concat(shown, ", ") or L.MINIMAPNODEICONS_REPORT_NONE))
        if count > bestCount then
            best, bestCount = space, count
        end
    end
    if best then
        module.db.calibration.space = best
        ns.Print(format(L.MINIMAPNODEICONS_REPORT_SAVED, best))
    else
        module.db.calibration.space = nil
        ns.Print(L.MINIMAPNODEICONS_REPORT_NOTHING)
    end
    internal.nodes, internal.pass, internal.findAll = {}, nil, true
end

-- /fpp nodes here: where the dot under the cursor is against where its icon is. After a few
-- seconds to point at a dot, the cursor's spot and the name the game shows there (with its color)
-- are read, and the nearest icon of that name, all in minimap units right and up of its center,
-- with the trail measured while moving.
local HERE_WAIT = 3 -- seconds to put the cursor on a dot

local function measure()
    local x, y = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = Minimap:GetCenter()
    local right, up = x / scale - cx, y / scale - cy
    local under = internal.readMouseover()
    local first = under and under[1]
    if not first then
        ns.Print(L.MINIMAPNODEICONS_HERE_NONE)
        return
    end
    ns.Print(format(L.MINIMAPNODEICONS_HERE_CURSOR, first.name, right, up, Minimap:GetZoom()))
    -- The name's color, for telling whether a node on another level is named in gray.
    ns.Print(format(L.MINIMAPNODEICONS_HERE_COLOR, tostring(first.r), tostring(first.g),
        tostring(first.b), first.gray and L.MINIMAPNODEICONS_REPORT_YES or L.MINIMAPNODEICONS_REPORT_NO))
    local v = internal.readView()
    local drawnAt = internal.drawnAt
    local nearest, best
    for _, node in ipairs(internal.nodes) do
        local nr, nu = drawnAt(node, v)
        local dr, du = nr - right, nu - up
        local d = dr * dr + du * du
        if node.name == first.name and (not best or d < best) then
            nearest, best = node, d
        end
    end
    if nearest then
        local nr, nu = drawnAt(nearest, v)
        ns.Print(format(L.MINIMAPNODEICONS_HERE_ICON, nr, nu, nearest.right, nearest.up))
    else
        ns.Print(L.MINIMAPNODEICONS_HERE_MISSED)
    end
    local lagR, lagU = internal.lag()
    ns.Print(format(L.MINIMAPNODEICONS_HERE_LAG, lagR, lagU,
        internal.still() and L.MINIMAPNODEICONS_REPORT_YES or L.MINIMAPNODEICONS_REPORT_NO))
end

-- /fpp nodes probe: which ways of probing still read a dot, for when probes stop reading anything
-- (build 70862). The dot's spot is taken from the real cursor while the player points at it,
-- then probed in each way once the mouse is off the minimap, so only a probe can read it.

local function readNames()
    local list = internal.readMouseover()
    if not list then
        return L.MINIMAPNODEICONS_PROBE_NOTHING
    end
    local names = {}
    for i, entry in ipairs(list) do
        names[i] = entry.name
    end
    return concat(names, ", ")
end

local function say(way, text)
    ns.Print(format(L.MINIMAPNODEICONS_PROBE_RESULT, way, text))
end

local function soft(on)
    if Minimap.SetUsingSoftCursor then
        pcall(Minimap.SetUsingSoftCursor, Minimap, on)
    end
end

local function away()
    pcall(Minimap.UpdateMouseoverAtPoint, Minimap, -10000, -10000)
end

-- Runs one way that reads right away: `fn` returns what it read; an error is shown instead.
local function try(way, fn)
    local ok, result = pcall(fn)
    say(way, ok and result or format(L.MINIMAPNODEICONS_PROBE_ERROR, tostring(result)))
    away()
    soft(false)
end

local function yesNo(value)
    return value and L.MINIMAPNODEICONS_REPORT_YES or L.MINIMAPNODEICONS_REPORT_NO
end

local function probeWays(x, y)
    local scale = UIParent:GetEffectiveScale()
    ns.Print(format(L.MINIMAPNODEICONS_PROBE_API, yesNo(Minimap.SetUsingSoftCursor),
        yesNo(Minimap.UpdateMouseoverAtPoint), yesNo(Minimap.UpdateBlips),
        tostring(GetCVar and GetCVar("GamePadEnable")), scale))
    try(L.MINIMAPNODEICONS_PROBE_SOFT, function()
        soft(true)
        Minimap:UpdateMouseoverAtPoint(x, y)
        return readNames()
    end)
    try(L.MINIMAPNODEICONS_PROBE_PLAIN, function()
        Minimap:UpdateMouseoverAtPoint(x, y)
        return readNames()
    end)
    try(L.MINIMAPNODEICONS_PROBE_UNITS, function()
        soft(true)
        Minimap:UpdateMouseoverAtPoint(x / scale, y / scale)
        return readNames()
    end)
    try(L.MINIMAPNODEICONS_PROBE_BLIPS, function()
        soft(true)
        if Minimap.UpdateBlips then
            Minimap:UpdateBlips()
        end
        Minimap:UpdateMouseoverAtPoint(x, y)
        return readNames()
    end)
    -- Whether the answer now comes a frame or more later rather than right away.
    soft(true)
    pcall(Minimap.UpdateMouseoverAtPoint, Minimap, x, y)
    C_Timer.After(0, function()
        say(L.MINIMAPNODEICONS_PROBE_NEXT, readNames())
        C_Timer.After(0.2, function()
            say(L.MINIMAPNODEICONS_PROBE_LATER, readNames())
            away()
            soft(false)
            pcall(Minimap.UpdateMouseoverAtPoint, Minimap, x, y)
            C_Timer.After(0.2, function()
                say(L.MINIMAPNODEICONS_PROBE_HOVER, readNames())
                away()
                ns.Print(L.MINIMAPNODEICONS_PROBE_DONE)
            end)
        end)
    end)
end

local function probeTest()
    ns.Print(format(L.MINIMAPNODEICONS_PROBE_START, HERE_WAIT))
    C_Timer.After(HERE_WAIT, function()
        local x, y = GetCursorPosition()
        local under = internal.readMouseover()
        local first = under and under[1]
        if not first then
            ns.Print(L.MINIMAPNODEICONS_HERE_NONE)
            return
        end
        ns.Print(format(L.MINIMAPNODEICONS_PROBE_MOVE, first.name, x, y, HERE_WAIT))
        C_Timer.After(HERE_WAIT, function()
            if InCombatLockdown() then
                ns.Print(L.MINIMAPNODEICONS_REPORT_COMBAT)
                return
            end
            probeWays(x, y)
        end)
    end)
end

ns.AddCommand("nodes", "[here|probe]", L.MINIMAPNODEICONS_COMMAND, function(rest)
    if rest and rest:lower():match("^%s*probe") then
        if InCombatLockdown() then
            ns.Print(L.MINIMAPNODEICONS_REPORT_COMBAT)
            return
        end
        probeTest()
        return
    end
    if rest and rest:lower():match("^%s*here") then
        if InCombatLockdown() then
            ns.Print(L.MINIMAPNODEICONS_REPORT_COMBAT)
            return
        end
        ns.Print(format(L.MINIMAPNODEICONS_HERE_START, HERE_WAIT))
        C_Timer.After(HERE_WAIT, measure)
        return
    end
    report()
end, "MinimapNodeIcons")
