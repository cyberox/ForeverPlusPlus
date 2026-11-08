-- Talent plans: an ordered list of talent points, one node ID per point, checked against a
-- Classic talent tree's rules (points in the tab before a row opens, a maxed prerequisite before
-- an arrow's talent, a node's maximum rank). Pure logic with no frames, so tests/run.lua checks it.
--
-- A tree is { nodes = { [nodeID] = node }, order = { nodeID, ... } }, where a node is
-- { max = ranks, tab = groupID, req = points needed in that tab, prereqs = { { id, required } } }
-- and `order` lists the nodes top row first. A prerequisite with `required` must be maxed;
-- of the ones without it, any one maxed is enough (C_Traits' Required and Sufficient edges).
local _, ns = ...

local ipairs, max, min, remove, concat = ipairs, math.max, math.min, table.remove, table.concat
local pairs, floor, sort = pairs, math.floor, table.sort
local tostring, tonumber, type = tostring, tonumber, type
local gsub, strmatch, gmatch = string.gsub, string.match, string.gmatch

local TalentPlan = {}
ns.TalentPlan = TalentPlan

-- Classic gives the first talent point at level 10, then one each level, 51 in all. Forever's
-- Legacy perk Talented starts them earlier but keeps the 51.
TalentPlan.FIRST_LEVEL = 10
TalentPlan.MAX_POINTS = 51
TalentPlan.POINTS_PER_ROW = 5 -- each row opens after 5 more points in its tab

---The points a node's row needs from its gate conditions (C_Traits.GetConditionInfo), or nil
---when none is a talent-point gate. A gate counted in another currency, or asking for more
---points than a character ever has, isn't a row gate: a hunter's Survival row 2 came back as
---300, so it's left to RowGates' 5 a row.
---@param conds table condition infos, { isGate, spentAmountRequired, traitCurrencyID }
---@param currencyID? number the tree's talent point currency, when known
---@return number?
function TalentPlan.GateAmount(conds, currencyID)
    local req
    for _, cond in ipairs(conds) do
        local amount = cond.isGate and cond.spentAmountRequired
        local currency = cond.traitCurrencyID
        if type(amount) == "number" and amount >= 0 and amount <= TalentPlan.MAX_POINTS
            and not (currencyID and currency and currency ~= currencyID) then
            req = max(req or 0, amount)
        end
    end
    return req
end

---Fills in the points each node's row needs in its tab, for the nodes the game gave no gate
---condition (no `req`), from their height: rows count down from the top node, and the gap
---between rows is the smallest gap between two nodes' heights that's a row's. Nodes of a row
---can sit a little apart (Forever's Affliction tree: two of its top three a few units lower, which
---read as a row of their own and put the next row 61 rows down), so a gap under a quarter of the
---largest one is a node nudged within its row. The largest gap is a row's, or a few rows' where
---every tab leaves rows empty.
---@param nodes table nodeID -> node with `y` (its height on the tree, growing downward)
---@param perRow? number points each row adds, POINTS_PER_ROW by default
function TalentPlan.RowGates(nodes, perRow)
    perRow = perRow or TalentPlan.POINTS_PER_ROW
    local ys = {}
    for _, node in pairs(nodes) do
        ys[#ys + 1] = node.y or 0
    end
    sort(ys)
    local largest = 0
    for i = 2, #ys do
        largest = max(largest, ys[i] - ys[i - 1])
    end
    local nudge = max(1, largest / 4)
    local spacing
    for i = 2, #ys do
        local gap = ys[i] - ys[i - 1]
        if gap > nudge and (not spacing or gap < spacing) then
            spacing = gap
        end
    end
    for _, node in pairs(nodes) do
        if not node.req then
            local row = spacing and floor(((node.y or 0) - ys[1]) / spacing + 0.5) or 0
            node.req = row * perRow
        end
    end
end

---Whether one more point can go into a node, after the points counted so far.
---@param tree table
---@param counts table nodeID -> ranks so far
---@param tabs table tab -> points so far
---@param id number nodeID
---@return boolean ok
---@return string? reason "unknown", "max", "tier" or "prereq"
function TalentPlan.CanTake(tree, counts, tabs, id)
    local node = tree.nodes[id]
    if not node then
        return false, "unknown"
    end
    if (counts[id] or 0) >= node.max then
        return false, "max"
    end
    if (tabs[node.tab] or 0) < (node.req or 0) then
        return false, "tier"
    end
    local any, anyMet = false, false
    for _, pre in ipairs(node.prereqs or {}) do
        local source = tree.nodes[pre.id]
        local met = source and (counts[pre.id] or 0) >= source.max
        if pre.required then
            if not met then
                return false, "prereq"
            end
        else
            any = true
            anyMet = anyMet or met
        end
    end
    if any and not anyMet then
        return false, "prereq"
    end
    return true
end

-- Counts one point in a node, and in its tab.
local function count(tree, counts, tabs, id)
    counts[id] = (counts[id] or 0) + 1
    local tab = tree.nodes[id].tab
    tabs[tab] = (tabs[tab] or 0) + 1
end

---Plays the plan's first `limit` points (all by default) in order.
---@param tree table
---@param picks table nodeIDs in order
---@param limit? number
---@return table counts nodeID -> ranks
---@return table tabs tab -> points
---@return number? bad the first point that breaks a rule, or nil when all are fine
---@return string? reason why it breaks one
function TalentPlan.Simulate(tree, picks, limit)
    local counts, tabs = {}, {}
    local last = limit and limit < #picks and limit or #picks
    for i = 1, last do
        local id = picks[i]
        local ok, reason = TalentPlan.CanTake(tree, counts, tabs, id)
        if not ok then
            return counts, tabs, i, reason
        end
        count(tree, counts, tabs, id)
    end
    return counts, tabs
end

---Adds a point to a node at the end of the plan, when the rules and the points allow it.
---@param tree table
---@param picks table changed in place
---@param id number nodeID
---@param points number the most points the plan may hold
---@return boolean ok
---@return string? reason "points", or a reason from CanTake
function TalentPlan.Add(tree, picks, id, points)
    if #picks >= points then
        return false, "points"
    end
    local counts, tabs = TalentPlan.Simulate(tree, picks)
    local ok, reason = TalentPlan.CanTake(tree, counts, tabs, id)
    if not ok then
        return false, reason
    end
    picks[#picks + 1] = id
    return true
end

---Takes a node's last point out of the plan's first `limit` points, unless a later point needs it.
---@param tree table
---@param picks table changed in place
---@param id number nodeID
---@param limit? number
---@return boolean ok
---@return string? reason "none" (no point there) or "needed"
function TalentPlan.Remove(tree, picks, id, limit)
    local last = limit and limit < #picks and limit or #picks
    local index
    for i = last, 1, -1 do
        if picks[i] == id then
            index = i
            break
        end
    end
    if not index then
        return false, "none"
    end
    local rest = {}
    for i, pick in ipairs(picks) do
        if i ~= index then
            rest[#rest + 1] = pick
        end
    end
    local _, _, bad = TalentPlan.Simulate(tree, rest)
    if bad then
        return false, "needed"
    end
    remove(picks, index)
    return true
end

---An order for talents already learned (the game doesn't say which came first): top rows first,
---each point taken as soon as the rules allow it.
---@param tree table
---@param ranks table nodeID -> ranks learned
---@return table picks
function TalentPlan.FromRanks(tree, ranks)
    local picks, counts, tabs = {}, {}, {}
    local progress = true
    while progress do
        progress = false
        for _, id in ipairs(tree.order) do
            if (counts[id] or 0) < (ranks[id] or 0) and TalentPlan.CanTake(tree, counts, tabs, id) then
                picks[#picks + 1] = id
                count(tree, counts, tabs, id)
                progress = true
                break
            end
        end
    end
    return picks
end

---The plan's next point that isn't learned yet.
---@param picks table
---@param ranks table nodeID -> ranks learned
---@return number? index its place in the plan
---@return number? id its nodeID
function TalentPlan.Next(picks, ranks)
    local counts = {}
    for i, id in ipairs(picks) do
        counts[id] = (counts[id] or 0) + 1
        if counts[id] > (ranks[id] or 0) then
            return i, id
        end
    end
end

---The level of the first talent point, from the player's level and the points they have earned,
---so a server that gives points differently is still counted right. With none earned yet, or all
---51 (which a level past the last point also has), it's Classic's level 10 less `earlier`.
---@param level number the player's level
---@param earned? number points earned (spent and unspent)
---@param earlier? number levels the first point comes early (Forever's Talented, a level a rank)
---@return number
function TalentPlan.FirstLevel(level, earned, earlier)
    if earned and earned > 0 and earned < TalentPlan.MAX_POINTS then
        return level - earned + 1
    end
    return TalentPlan.FIRST_LEVEL - (earlier or 0)
end

-- Share strings: "FPP:1:<treeID>:<level>:<name>:<points>", the points in order as nodeIDs with
-- "*n" for n points in a row on one node ("101*5,102,103*2"), so a plan fits on one line to paste.
local PREFIX = "FPP:1:"

---A plan as a share string.
---@param treeID number the class's talent tree, so another class's string is refused
---@param plan table { name, level, picks }
---@return string
function TalentPlan.Encode(treeID, plan)
    local runs, i, picks = {}, 1, plan.picks
    while i <= #picks do
        local id, n = picks[i], 1
        while picks[i + n] == id do
            n = n + 1
        end
        runs[#runs + 1] = n > 1 and (id .. "*" .. n) or tostring(id)
        i = i + n
    end
    local name = gsub(plan.name or "", "[:|]", "")
    return PREFIX .. treeID .. ":" .. plan.level .. ":" .. name .. ":" .. concat(runs, ",")
end

---Reads a share string, or nil when it isn't one. A string with more points than a character
---ever has isn't one either: a pasted run like `1*999999999` would otherwise hang the game.
---@param text string
---@return table? plan { treeID, name, level, picks }
function TalentPlan.Decode(text)
    local treeID, level, name, list = strmatch(text or "", "^%s*FPP:1:(%d+):(%d+):([^:]*):([%d,%*]*)%s*$")
    if not treeID then
        return nil
    end
    local picks = {}
    for run in gmatch(list, "[^,]+") do
        local id, n = strmatch(run, "^(%d+)%*?(%d*)$")
        if not id then
            return nil
        end
        n = tonumber(n) or 1
        if #picks + n > TalentPlan.MAX_POINTS then
            return nil
        end
        for _ = 1, n do
            picks[#picks + 1] = tonumber(id)
        end
    end
    -- Dropped as in Encode, so a pasted name can't carry colors, textures, or links.
    name = gsub(name, "|", "")
    return { treeID = tonumber(treeID), level = tonumber(level), name = name, picks = picks }
end

---How many talent points a character has at a level, never more than 51.
---@param level number
---@param first number the level of the first point
---@return number
function TalentPlan.PointsAt(level, first)
    return min(TalentPlan.MAX_POINTS, max(0, level - first + 1))
end

---The level a plan's point comes at.
---@param index number its place in the plan
---@param first number the level of the first point
---@return number
function TalentPlan.LevelOf(index, first)
    return first + index - 1
end
