-- Minimap Node Icons' /fpp nodes and /fpp nodes here: what the probes see, and where a dot answers
-- against where its icon is, for finding out in game why icons don't show or sit off their dots.
local _, ns = ...

local ipairs, floor, tostring, format = ipairs, math.floor, tostring, string.format
local min, concat = math.min, table.concat
local Minimap, C_Timer = Minimap, C_Timer
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
    if not module:IsAvailable() then
        ns.Print(L.MINIMAPNODEICONS_REPORT_UNAVAILABLE)
        return
    end
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

ns.AddCommand("nodes", "[here]", L.MINIMAPNODEICONS_COMMAND, function(rest)
    if rest and rest:lower():match("^%s*here") then
        if not module:IsAvailable() or InCombatLockdown() then
            ns.Print(L.MINIMAPNODEICONS_REPORT_COMBAT)
            return
        end
        ns.Print(format(L.MINIMAPNODEICONS_HERE_START, HERE_WAIT))
        C_Timer.After(HERE_WAIT, measure)
        return
    end
    report()
end, "MinimapNodeIcons")
