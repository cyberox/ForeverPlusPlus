-- Talent Planner's data: the talent tree read from C_Traits for ns.TalentPlan, the points a
-- character has, a talent's name and icon, and this character's saved plans for the shown spec
-- tab. TalentPlanner.lua keeps the shown tree in internal.tree.
local _, ns = ...

local ipairs, pairs, format, concat, sort = ipairs, pairs, string.format, table.concat, table.sort
local min, tostring = math.min, tostring
local C_Traits, C_Spell, UnitLevel = C_Traits, C_Spell, UnitLevel

local L = ns.L
local Plan = ns.TalentPlan
local readable = ns.IsReadable

local module = ns.modules.TalentPlanner
local internal = module.internal

-- Enum.TraitEdgeType, with Mainline's values when the enum is missing.
local EdgeType = Enum and Enum.TraitEdgeType or {}
local EDGE_REQUIRED = EdgeType.RequiredForAvailability or 3
local EDGE_SUFFICIENT = EdgeType.SufficientForAvailability or 2

-- Tree ----------------------------------------------------------------------------------------

function internal.maxLevel()
    local level = GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()
    return level and readable(level) and level > 0 and level or 60
end

-- Points spent and unspent in a tree (the shown one by default), staged changes included.
function internal.currency(t)
    t = t or internal.tree
    local info = C_Traits.GetTreeCurrencyInfo(t.configID, t.treeID, false)
    local points = info and info[1]
    if not points then
        return 0, 0
    end
    return points.spent or 0, points.quantity or 0
end

-- Ranks learned in Forever's Legacy perk Talented, which starts talent points at level 5 instead
-- of 10 at 5/5; taken as a level earlier per rank. Its node is in the Adventure tree, named by
-- Constants.LegacyConsts (Blizzard_LegacySystem). Forever only.
local function talentedRanks()
    local consts = Constants and Constants.LegacyConsts
    local treeID = consts and consts.LEGACY_TREE_ADVENTURE_ID
    local nodeID = consts and consts.LEGACY_TREE_ADVENTURE_TALENTED_NODE_ID
    local configID = treeID and nodeID and C_Traits.GetConfigIDByTreeID
        and C_Traits.GetConfigIDByTreeID(treeID)
    local info = configID and C_Traits.GetNodeInfo(configID, nodeID)
    local ranks = info and info.activeRank
    return ranks and readable(ranks) and ranks or 0
end

function internal.firstLevel(t)
    local spent, unspent = internal.currency(t)
    return Plan.FirstLevel(UnitLevel("player"), spent + unspent, talentedRanks())
end

-- Reads a tree from C_Traits. A node's tab is whichever of its groups is a tab
-- (docs/forever-api.md). The points a row needs come from the node's gate condition when it's a
-- talent-point one (Plan.GateAmount), or else from its row, counted from the tree's top.
function internal.buildTree(configID, treeID)
    if not (configID and treeID) then
        return nil
    end
    local tabs, tabList = {}, {}
    for _, info in ipairs(C_Traits.GetGroupDisplayInfoByTreeID(treeID) or {}) do
        tabs[info.groupID] = info
        tabList[#tabList + 1] = info
    end
    sort(tabList, function(a, b)
        return (a.orderIndex or 0) < (b.orderIndex or 0)
    end)
    local treeInfo = C_Traits.GetTreeInfo(configID, treeID)
    local built = { nodes = {}, order = {}, ranks = {}, tabs = tabs, tabList = tabList,
        configID = configID, treeID = treeID,
        hideSingle = treeInfo and treeInfo.hideSingleRankNumbers }
    -- The talent point currency (3820 on a warrior), so a gate counted in another isn't a row's.
    local currencies = C_Traits.GetTreeCurrencyInfo(configID, treeID, false)
    local currencyID = currencies and currencies[1] and currencies[1].traitCurrencyID
    local incoming = {}
    for _, id in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
        local info = C_Traits.GetNodeInfo(configID, id)
        local tab
        for _, group in ipairs(info and info.groupIDs or {}) do
            tab = tab or (tabs[group] and group)
        end
        -- Choice nodes (more than one entry) aren't in Classic trees, so they aren't planned.
        if tab and info.isVisible and (info.maxRanks or 0) > 0 and #info.entryIDs == 1 then
            local conds = {}
            for _, condID in ipairs(info.conditionIDs or {}) do
                conds[#conds + 1] = C_Traits.GetConditionInfo(configID, condID)
            end
            local req = Plan.GateAmount(conds, currencyID)
            built.nodes[id] = { id = id, max = info.maxRanks, tab = tab, req = req, prereqs = {},
                x = info.posX or 0, y = info.posY or 0, entryID = info.entryIDs[1] }
            built.order[#built.order + 1] = id
            built.ranks[id] = info.ranksPurchased or 0
            for _, edge in ipairs(info.visibleEdges or {}) do
                if edge.type == EDGE_REQUIRED or edge.type == EDGE_SUFFICIENT then
                    local list = incoming[edge.targetNode] or {}
                    incoming[edge.targetNode] = list
                    list[#list + 1] = { id = id, required = edge.type == EDGE_REQUIRED }
                end
            end
        end
    end
    for target, list in pairs(incoming) do
        local node = built.nodes[target]
        for _, pre in ipairs(node and list or {}) do
            if built.nodes[pre.id] then
                node.prereqs[#node.prereqs + 1] = pre
            end
        end
    end
    Plan.RowGates(built.nodes)
    sort(built.order, function(a, b)
        local na, nb = built.nodes[a], built.nodes[b]
        if na.y ~= nb.y then
            return na.y < nb.y
        end
        return na.x < nb.x
    end)
    return built
end

-- The player's own talent tree, read without the talent window (docs/forever-api.md, Talents).
function internal.activeTree()
    local configID = C_ClassTalents and C_ClassTalents.GetActiveConfigID
        and C_ClassTalents.GetActiveConfigID()
    local info = configID and C_Traits.GetConfigInfo and C_Traits.GetConfigInfo(configID)
    return internal.buildTree(configID, info and info.treeIDs and info.treeIDs[1])
end

-- A node's name, icon, and spell, read when first needed, from its tree (the shown one by default).
function internal.describe(node, t)
    if node.name then
        return node
    end
    local entry = C_Traits.GetEntryInfo((t or internal.tree).configID, node.entryID)
    local def = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
    local spellID = def and (def.overriddenSpellID or def.spellID)
    node.name = def and def.overrideName and def.overrideName ~= "" and def.overrideName
        or spellID and C_Spell.GetSpellName(spellID) or ""
    node.icon = def and def.overrideIcon and def.overrideIcon ~= 0 and def.overrideIcon
        or spellID and C_Spell.GetSpellTexture(spellID) or 134400 -- the question mark
    return node
end

function internal.withIcon(node)
    return format("|T%s:0|t %s", tostring(node.icon), node.name)
end

local function tabName(group)
    local info = internal.tree.tabs[group]
    return info and info.displayName or ""
end

-- Why a point can't be added or removed, for the error line and the tooltip.
function internal.reasonText(reason, node, plan)
    if reason == "points" then
        return format(L.TALENTPLANNER_NO_POINTS, plan.level)
    elseif reason == "max" then
        return L.TALENTPLANNER_MAXED
    elseif reason == "tier" then
        return format(L.TALENTPLANNER_TIER, node.req, tabName(node.tab))
    elseif reason == "prereq" then
        local names = {}
        for _, pre in ipairs(node.prereqs) do
            names[#names + 1] = internal.describe(internal.tree.nodes[pre.id]).name
        end
        return format(L.TALENTPLANNER_PREREQ, concat(names, ", "))
    elseif reason == "needed" then
        return L.TALENTPLANNER_NEEDED
    end
end

-- The levels at which the plan's first `points` points put ranks in a node, leaving out ranks
-- already learned (the plan's first ranks in a node count as the learned ones).
function internal.levelsFor(plan, id, points, first)
    local levels, skip = {}, internal.tree.ranks[id] or 0
    for i = 1, min(#plan.picks, points) do
        if plan.picks[i] == id then
            if skip > 0 then
                skip = skip - 1
            else
                levels[#levels + 1] = Plan.LevelOf(i, first)
            end
        end
    end
    return levels
end

-- Plans ---------------------------------------------------------------------------------------

-- A new plan starts from the talents already learned.
function internal.newPlan(name)
    local tree = internal.tree
    return { name = name, level = internal.maxLevel(),
        picks = tree and Plan.FromRanks(tree, tree.ranks) or {} }
end

-- The saved plans for this character and the shown spec tab, made when `create` is true.
function internal.getBuilds(create)
    local frame = internal.frame
    local key = frame.GetTab and frame:GetTab() or 1
    if not readable(key) then
        return nil
    end
    local builds = module.db.builds[key]
    if not builds and create then
        builds = { active = 1, list = { internal.newPlan(format(L.TALENTPLANNER_PLAN_NAME, 1)) } }
        module.db.builds[key] = builds
    end
    if builds and not builds.list[builds.active] then
        builds.active = 1
    end
    return builds
end

-- The plan picked in the dropdown.
function internal.getPlan(create)
    local builds = internal.getBuilds(create)
    return builds and builds.list[builds.active]
end

-- The points a plan may hold at its level.
function internal.pointsOf(plan)
    return Plan.PointsAt(plan.level, internal.firstLevel())
end
