-- Talent plans: an ordered list of talent points, one node ID per point, checked against a
-- Classic talent tree's rules (points in the tab before a row opens, a maxed prerequisite before
-- an arrow's talent, a node's maximum rank), and build links from talent calculator websites read
-- into one. Pure logic with no frames, so tests/run.lua checks it.
--
-- A tree is { nodes = { [nodeID] = node }, order = { nodeID, ... } }, where a node is
-- { max = ranks, tab = groupID, req = points needed in that tab, prereqs = { { id, required } } }
-- and `order` lists the nodes top row first. A prerequisite with `required` must be maxed;
-- of the ones without it, any one maxed is enough (C_Traits' Required and Sufficient edges).
local _, ns = ...

local ipairs, max, min, remove, concat = ipairs, math.max, math.min, table.remove, table.concat
local pairs, floor, sort = pairs, math.floor, table.sort
local tostring, tonumber, type, select = tostring, tonumber, type, select
local gsub, strmatch, gmatch = string.gsub, string.match, string.gmatch
local strfind, sub, upper = string.find, string.sub, string.upper

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
    local rows = TalentPlan.Rows(nodes)
    for id, node in pairs(nodes) do
        if not node.req then
            node.req = rows[id] * perRow
        end
    end
end

---Each node's row, counted from the top node's (0), by RowGates' rule for the gap between rows.
---@param nodes table nodeID -> node with `y`
---@return table rows nodeID -> row
function TalentPlan.Rows(nodes)
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
    local rows = {}
    for id, node in pairs(nodes) do
        rows[id] = spacing and floor(((node.y or 0) - ys[1]) / spacing + 0.5) or 0
    end
    return rows
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

-- Talent calculator links ---------------------------------------------------------------------
--
-- Two websites Forever players plan builds on give a build as a link. Read from their page
-- scripts on 2026-11-11 and checked by opening links on each site:
--
-- talentsforever.com/<class>/<level>/<tab1>-<tab2>-<tab3>[-<legacy x3>][-<order>]-<numbering>
--   e.g. talentsforever.com/warrior/60/30303213002-050530055120100231--12 (17 Arms, 33 Fury).
--   A digit per talent, its ranks, in the order the site lists a tab: by row, then by column, with
--   zeros cut from the end of each tab. The three Legacy tabs come only with a perk set (not
--   planned here). <order>, when the player clicked one, is the order the points went in: a symbol
--   per run of points in one talent (its place among all the class's talents in ORDER_SYMBOLS), with
--   a digit 1-4 after it when the run stops short of that talent's ranks. <numbering> says which
--   tree the digits are written against; the site moves to a new one when a patch moves talents,
--   and gives an older link the new one when it's opened there. A query after it (?b=..&d=..) is
--   only the build the link was made on.
-- wowforevertalents.com/<class>/?t=<letter><tab1>-<tab2>-<tab3>[&level=<n>]
--   e.g. wowforevertalents.com/mage/?t=h--053502 (Frost: 5 Improved Frostbolt, 3 Precision, 5 Ice
--   Shards, 2 Improved Frost Nova). The same digits, empty tabs cut from the end, and no order. The
--   letter is the numbering, as above (none, x, y, z, then a to h so far); the site opens an older
--   one as the newest too.
--
-- Neither link names its talents, so a digit goes to the node at the same place in the game's tab:
-- rows by height (Rows), then left to right. That's safe only while the site's tab has the same
-- talents in the same places as the game's, so each numbering's tabs are kept here as a shape, the
-- row and the most ranks of each talent in link order (two digits a talent), and a link is read only
-- when every one of the game's tabs has that shape. A numbering's shape never changes (the site
-- makes a new one instead); when the game's tree changes, its shapes stop matching and links are
-- refused rather than misread, until a new numbering is added here. From each site's own data its
-- links are written against: talentsforever.com's talents.js (numbering 12) and
-- wowforevertalents.com's calculator (numbering h, read from client build 1.60.1.70888). They agree
-- on every tab but Hunter Marksmanship, where wowforevertalents has Improved Serpent Sting (row 3,
-- 5 ranks) and talentsforever doesn't; the game's tab decides whose links import. Evidence that the
-- sites' trees are the game's: wowforevertalents' talents carry the game's own node IDs, and every
-- node in the plans Talent Planner had saved in game is in its data, in the right class.
local ORDER_SYMBOLS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz056789"

local SITES = {
    talentsforever = {
        name = "talentsforever.com",
        newest = 12,
        rank = function(version) return tonumber(version) end,
        shapes = {
            ["12"] = {
                WARRIOR = { "0305031213122123313332424145525361", "050515152321232535313242414242525361",
                    "020505151313212223233331324241435561" },
                PALADIN = { "0505131215122125223232314241425561", "0505131212212322253133354241455361",
                    "0505121313232221223231334241435561" },
                HUNTER = { "05051213122221253235314241425561", "03050513151522252131354243415561",
                    "050515121513222321323531424242415561" },
                ROGUE = { "0302051312132221223531354541425361", "03020513131312222122323132334241455561",
                    "030305121313122321233231324241415561" },
                PRIEST = { "050205131315122321232333323141455361", "0303051515212323323332314241455361",
                    "0505051512122221223531334142525561" },
                SHAMAN = { "05051315131321233233314241435561", "020505121313232123353531324142425561",
                    "05051313151223232135353143415561" },
                MAGE = { "020503121215122223213232333141455361", "0505151213232321223332313343415361",
                    "020503151312132323213231334341425561" },
                WARLOCK = { "0205051212132223212335323141435561", "02030505121313122321223231334341435561",
                    "02050515131525213333314241435561" },
                DRUID = { "05051312121223213135354241435561", "0505121312132322212233313132414255556161",
                    "05051513132325213533314143425561" },
            },
        },
    },
    wowforevertalents = {
        name = "wowforevertalents.com",
        newest = 12,
        rank = function(version)
            local i = strfind("-xyzabcdefgh", version ~= "" and version or "-", 1, true)
            return i or 99
        end,
        shapes = {
            h = {
                WARRIOR = { "0305031213122123313332424145525361", "050515152321232535313242414242525361",
                    "020505151313212223233331324241435561" },
                PALADIN = { "0505131215122125223232314241425561", "0505131212212322253133354241455361",
                    "0505121313232221223231334241435561" },
                HUNTER = { "05051213122221253235314241425561", "0305051315152225213135354243415561",
                    "050515121513222321323531424242415561" },
                ROGUE = { "0302051312132221223531354541425361", "03020513131312222122323132334241455561",
                    "030305121313122321233231324241415561" },
                PRIEST = { "050205131315122321232333323141455361", "0303051515212323323332314241455361",
                    "0505051512122221223531334142525561" },
                SHAMAN = { "05051315131321233233314241435561", "020505121313232123353531324142425561",
                    "05051313151223232135353143415561" },
                MAGE = { "020503121215122223213232333141455361", "0505151213232321223332313343415361",
                    "020503151312132323213231334341425561" },
                WARLOCK = { "0205051212132223212335323141435561", "02030505121313122321223231334341435561",
                    "02050515131525213333314241435561" },
                DRUID = { "05051312121223213135354241435561", "0505121312132322212233313132414255556161",
                    "05051513132325213533314143425561" },
            },
        },
    },
}

-- "a-b-" as { "a", "b", "" }.
local function split(text)
    local parts = {}
    for part in gmatch(text .. "-", "([^%-]*)%-") do
        parts[#parts + 1] = part
    end
    return parts
end

-- Three tabs of digits, or nil when a tab has anything else in it.
local function digitTabs(parts)
    local tabs = { parts[1] or "", parts[2] or "", parts[3] or "" }
    for _, tab in ipairs(tabs) do
        if not strmatch(tab, "^%d*$") then
            return nil
        end
    end
    return tabs
end

---Reads a build link from talentsforever.com or wowforevertalents.com anywhere in the text (with
---or without http, https, or www, and whatever comes before or after it), or nil and "bad" when
---there is none, or "old" for a talentsforever link from before its numbering was in the link.
---@param text string
---@return table? link { site, version, class (as UnitClass's classFile), level?, tabs, order? }
---@return string? reason
function TalentPlan.ParseLink(text)
    text = text or ""
    local class, level, code = strmatch(text, "talentsforever%.com/(%a+)/(%d+)/([%w%-]+)")
    if not class then -- a page in another language: /de/warrior/60/...
        class, level, code = strmatch(text, "talentsforever%.com/%a%a/(%a+)/(%d+)/([%w%-]+)")
    end
    if class then
        local parts = split(code)
        if #parts == 3 then
            return nil, "old" -- the first links, with no numbering
        end
        local version = remove(parts)
        local tabs = #parts >= 3 and strmatch(version, "^%d+$") and digitTabs(parts)
        if not tabs then
            return nil, "bad"
        end
        -- After the tabs: three Legacy tabs, then the order; or the order alone.
        local extra = #parts - 3
        local order = extra >= 4 and parts[7] or extra == 1 and parts[4] or nil
        return { site = "talentsforever", version = version, class = upper(class),
            level = tonumber(level), tabs = tabs, order = order }
    end
    local slug, query = strmatch(text, "wowforevertalents%.com/(%a+)/?%?([%w%-=&]*)")
    local t = query and strmatch("&" .. query, "&t=([%w%-]*)")
    if t then
        local letter, list = strmatch(t, "^(%a?)([%d%-]*)$")
        local parts = list and split(list)
        local tabs = parts and #parts <= 3 and digitTabs(parts)
        if not tabs then
            return nil, "bad"
        end
        return { site = "wowforevertalents", version = letter, class = upper(slug),
            level = tonumber(strmatch("&" .. query, "&level=(%d+)")), tabs = tabs }
    end
    return nil, "bad"
end

---The website a link is from, as its name.
---@param link table from ParseLink
---@return string
function TalentPlan.SiteName(link)
    return SITES[link.site].name
end

---A tree's tabs (`tree.tabList`, each with `groupID`, in the game's order) with their nodes in the
---order the websites list them: by row (Rows), then left to right, and each tab's shape, as in the
---SITES table.
---@param tree table
---@return table grid { { ids = { nodeID, ... }, shape = string }, ... }
function TalentPlan.Grid(tree)
    local rows, grid = TalentPlan.Rows(tree.nodes), {}
    for i, tab in ipairs(tree.tabList) do
        local ids, top = {}, nil
        for id, node in pairs(tree.nodes) do
            if node.tab == tab.groupID then
                ids[#ids + 1] = id
                top = min(top or rows[id], rows[id])
            end
        end
        sort(ids, function(a, b)
            if rows[a] ~= rows[b] then
                return rows[a] < rows[b]
            end
            local xa, xb = tree.nodes[a].x or 0, tree.nodes[b].x or 0
            if xa ~= xb then
                return xa < xb
            end
            return tostring(a) < tostring(b)
        end)
        local shape = {}
        for k, id in ipairs(ids) do
            shape[k] = (rows[id] - top) .. tree.nodes[id].max
        end
        grid[i] = { ids = ids, shape = concat(shape) }
    end
    return grid
end

---An order for a build: the tab with the most points first, then the next, each from its top row
---down and left to right, a talent's ranks together, each point as soon as the rules allow it
---(another tab's when this one is stuck). After `start`'s points, when given, which must be valid.
---@param tree table
---@param ranks table nodeID -> ranks
---@param grid table from Grid
---@param start? table picks to begin with
---@return table picks fewer points than `ranks` holds when the rules can't place them all
function TalentPlan.FromTabs(tree, ranks, grid, start)
    local tabOrder = {}
    for i, tab in ipairs(grid) do
        local n = 0
        for _, id in ipairs(tab.ids) do
            n = n + (ranks[id] or 0)
        end
        tabOrder[i] = { ids = tab.ids, n = n, i = i }
    end
    sort(tabOrder, function(a, b)
        if a.n ~= b.n then
            return a.n > b.n
        end
        return a.i < b.i
    end)
    local picks, counts, tabs = {}, {}, {}
    for _, id in ipairs(start or {}) do
        picks[#picks + 1] = id
        count(tree, counts, tabs, id)
    end
    local progress = true
    while progress do
        progress = false
        for _, tab in ipairs(tabOrder) do
            for _, id in ipairs(tab.ids) do
                if (counts[id] or 0) < (ranks[id] or 0) and TalentPlan.CanTake(tree, counts, tabs, id) then
                    picks[#picks + 1] = id
                    count(tree, counts, tabs, id)
                    progress = true
                    break
                end
            end
            if progress then
                break
            end
        end
    end
    return picks
end

-- A talentsforever order as picks: each symbol is a run of points in one talent, all of its ranks
-- not placed yet, or as many as the digit 1-4 after it says.
local function orderFrom(code, flat, ranks)
    local picks, taken, k = {}, {}, 1
    while k <= #code do
        local f = strfind(ORDER_SYMBOLS, sub(code, k, k), 1, true)
        local id = f and flat[f]
        if id then
            local n = (ranks[id] or 0) - (taken[id] or 0)
            local run = tonumber(strmatch(sub(code, k + 1, k + 1), "^[1-4]$") or "")
            if run then
                n = min(n, run)
                k = k + 1
            end
            for _ = 1, n do
                picks[#picks + 1] = id
            end
            taken[id] = (taken[id] or 0) + max(n, 0)
        end
        k = k + 1
    end
    return picks
end

---A link's build as a plan for this tree, in the link's order when it has a valid one and
---otherwise FromTabs'. Refused with a reason: "class" (another class's), "old" or "new" (a
---numbering this file doesn't have, before or after the newest it has), "tree" (the game's tabs
---aren't the shape the link was written against), "rank" (more ranks than a talent has),
---"points" (more than MAX_POINTS, with the total), or "rules" (the tree's rules can't place them).
---@param tree table with `tabList`
---@param link table from ParseLink
---@param class string the player's class, as UnitClass's classFile
---@return table? picks
---@return string? reason
---@return number? total the link's points, with "points"
function TalentPlan.FromLink(tree, link, class)
    if link.class ~= class then
        return nil, "class"
    end
    local site = SITES[link.site]
    local shapes = site.shapes[link.version]
    if not shapes then
        local rank = site.rank(link.version)
        return nil, rank and rank < site.newest and "old" or "new"
    end
    shapes = shapes[class]
    local grid = TalentPlan.Grid(tree)
    if not shapes or #grid ~= #shapes then
        return nil, "tree"
    end
    for i, tab in ipairs(grid) do
        if tab.shape ~= shapes[i] then
            return nil, "tree"
        end
    end
    local ranks, flat, total = {}, {}, 0
    for i, tab in ipairs(grid) do
        local digits = link.tabs[i] or ""
        if #digits > #tab.ids then
            return nil, "tree"
        end
        for k, id in ipairs(tab.ids) do
            flat[#flat + 1] = id
            local n = tonumber(sub(digits, k, k)) or 0
            if n > tree.nodes[id].max then
                return nil, "rank"
            end
            ranks[id] = n
            total = total + n
        end
    end
    if total > TalentPlan.MAX_POINTS then
        return nil, "points", total
    end
    local start = link.order and orderFrom(link.order, flat, ranks) or {}
    if select(3, TalentPlan.Simulate(tree, start)) then
        start = {}
    end
    local picks = TalentPlan.FromTabs(tree, ranks, grid, start)
    if #picks < total and #start > 0 then
        picks = TalentPlan.FromTabs(tree, ranks, grid)
    end
    if #picks < total then
        return nil, "rules"
    end
    return picks
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
