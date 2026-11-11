-- Talent Planner's Level-Up Reminder: when a talent point comes, a chat line names the plan's next
-- talent and its rank. It reads the player's own tree, so the talent window needn't be open.
-- TalentPlanner.lua listens for the events.
local _, ns = ...

local format = string.format

local L = ns.L
local Plan = ns.TalentPlan
local readable = ns.IsReadable

local module = ns.modules.TalentPlanner
local internal = module.internal

-- internal.earned: talent points earned (spent and unspent) when last counted, to notice a new one.

-- The active spec group, as the talent window's primary and secondary tabs. Probe: Mainline's
-- names. That their numbers match the window's tab keys, which plans are saved by, is Unverified.
local function activeGroup()
    local get = C_SpecializationInfo and C_SpecializationInfo.GetActiveSpecGroup or GetActiveSpecGroup
    local group = get and get()
    return group and readable(group) and group or 1
end

-- Counts the points earned, and when there's a new one, names the plan's next talent in chat.
function internal.checkPoints()
    if not (module.enabled and module.db.reminder) then
        internal.earned = nil
        return
    end
    local t = internal.activeTree()
    if not t then
        return
    end
    local spent, unspent = internal.currency(t)
    if not (readable(spent) and readable(unspent)) then
        return
    end
    local earned = internal.earned
    local gained = earned and spent + unspent > earned
    internal.earned = spent + unspent
    if not gained or unspent <= 0 then
        return
    end
    local builds = module.db.builds[activeGroup()]
    local plan = builds and builds.list[builds.active]
    local index, id = Plan.Next(plan and plan.picks or {}, t.ranks)
    if not (index and t.nodes[id] and index <= Plan.PointsAt(plan.level, internal.firstLevel(t))) then
        return
    end
    local rank = 0
    for i = 1, index do
        if plan.picks[i] == id then
            rank = rank + 1
        end
    end
    local node = internal.describe(t.nodes[id], t)
    ns.Print(format(L.TALENTPLANNER_REMINDER_LINE, internal.withIcon(node), rank, node.max))
end

-- Talent points come a moment after the level does.
local levelTimer = ns.Frames.Timer(module)
function internal.onLevelUp()
    internal.refresh()
    if module.db.reminder then
        levelTimer:Start(1, internal.checkPoints)
    end
end
