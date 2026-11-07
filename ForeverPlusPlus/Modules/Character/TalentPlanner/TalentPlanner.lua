-- Talent Planner: a Plan Talents button on the talent window. While planning, clicking a talent
-- adds a point to a saved plan instead of learning it, in the order clicked, and a level box limits
-- the plan to the points a character has at that level. Out of planning, the plan's next talent
-- glows when you have a point to spend, and talent tooltips say at which levels the plan takes
-- it, and Level-Up Reminder names it in chat when a point comes. Blizzard's tree
-- still draws the talents; while planning, our own buttons sit over its buttons (theirs go
-- transparent) and show the plan's ranks with Blizzard's own art. The tree's data comes from
-- C_Traits (docs/forever-api.md, Talents); nothing here learns a talent.
--
-- This file has the module, its hooks, and refresh; the tree and saved plans are in Tree.lua, what
-- goes on Blizzard's tree in Draw.lua, the bar along the window's bottom in Bar.lua, and the
-- Level-Up Reminder in Reminder.lua.
local _, ns = ...

local ipairs, pairs, type, tonumber, concat = ipairs, pairs, type, tonumber, table.concat
local C_Traits, UnitGUID, EventRegistry = C_Traits, UnitGUID, EventRegistry

local L = ns.L
local Plan = ns.TalentPlan

local module = ns.NewModule("TalentPlanner", L.TALENTPLANNER_DESC, {
    enabled = true,
    glow = true, -- the plan's next talent glows
    tooltip = true, -- talent tooltips say when the plan takes them
    reminder = false, -- a chat line naming the plan's next talent when a point comes
    chat = true,
    -- Saved per character: spec tab -> { active = index, list = { { name, level, picks }, ... } },
    -- where picks are nodeIDs in order and level is the plan's level cap.
    builds = {},
})
module.title = L.TALENTPLANNER_TITLE
module.category = "character"
module.added = "0.8.0"
module.perCharacter = { builds = true }

-- Shared by this module's files:
--   frame: PlayerSpellsFrame.TalentsFrame, once its addon loads
--   ui: our frames on it (Bar.lua's createUI)
--   planning: whether clicks on the tree go to the plan
--   tree: the shown tree for ns.TalentPlan, with names and ranks; rebuilt on every refresh
local internal = { planning = false }
module.internal = internal

-- Up to 0.8.4 every character's plans were saved for the account, by "<player GUID>-<spec tab>".
ns.MigrateCharacter(2, function(char, db)
    local guid = UnitGUID("player")
    if not guid then
        return
    end
    local prefix = guid .. "-"
    ns.Store.Claim(char, db, "TalentPlanner", "builds", function(entries)
        local mine
        for key, builds in pairs(entries) do
            if type(key) == "string" and key:sub(1, #prefix) == prefix then
                mine = mine or {}
                mine[tonumber(key:sub(#prefix + 1)) or 1] = builds
                entries[key] = nil
            end
        end
        return mine
    end)
end)

module.options = {
    { key = "glow", name = L.TALENTPLANNER_GLOW, description = L.TALENTPLANNER_GLOW_DESC },
    { key = "tooltip", name = L.TALENTPLANNER_TOOLTIP, description = L.TALENTPLANNER_TOOLTIP_DESC },
    { key = "reminder", name = L.TALENTPLANNER_REMINDER, description = L.TALENTPLANNER_REMINDER_DESC,
        added = "0.9.0" },
    ns.ChatOption(L.TALENTPLANNER_CHAT_DESC),
}
module.options[#module.options].requires = "reminder"

local ADDON = "Blizzard_PlayerSpells" -- the talent window's load-on-demand addon

-- Drawing -------------------------------------------------------------------------------------

local function refresh()
    local frame, ui = internal.frame, internal.ui
    if not (module.enabled and frame and ui and frame:IsVisible()) then
        return
    end
    local inspecting = frame.IsInspecting and frame:IsInspecting()
    local tree = not inspecting and internal.buildTree(frame:GetConfigID(), frame:GetTalentTreeID()) or nil
    internal.tree = tree
    if not (tree and #tree.order > 0) then
        internal.planning = false
        internal.clearPlanVisuals()
        ui.bar:Hide()
        return
    end
    ui.bar:Show()
    local plan = internal.getPlan(internal.planning)
    if plan then
        -- A patch can change node IDs; drop the points the tree no longer has.
        local picks = {}
        for _, id in ipairs(plan.picks) do
            if tree.nodes[id] then
                picks[#picks + 1] = id
            end
        end
        plan.picks = picks
    end
    internal.drawOverlays(plan)
    internal.drawHeaders(plan)
    internal.drawGates()
    internal.drawGlow(plan)
    internal.drawBar(plan)
end
internal.refresh = refresh

local function setPlanning(on)
    if internal.planning == on then
        return
    end
    internal.planning = on
    if not on then
        internal.clearPlanVisuals()
        internal.ui.level:ClearFocus()
    end
    refresh()
end
internal.setPlanning = setPlanning

-- The Screenshots tool's picture: the talent window, which the player opens, in plan mode. The
-- player clicks our button: entering plan mode from here would start an empty plan for them.
module.screenshot = {
    id = "talents",
    name = L.SCREENSHOTS_SCENE_TALENTS,
    binding = "TOGGLETALENTS",
    wait = 2,
    isShown = function()
        local window = PlayerSpellsFrame
        return window and window:IsVisible() and window.TalentsFrame
            and window.TalentsFrame:IsVisible() and true or false
    end,
    ready = function()
        local frame = internal.frame
        return module.enabled and internal.planning and frame and frame:IsVisible() and true or false
    end,
    readyText = L.SCREENSHOTS_PLAN_TALENTS,
}

-- Hooks ---------------------------------------------------------------------------------------

local function onTreeParts()
    if internal.planning and internal.tree then
        local plan = internal.getPlan(true)
        internal.drawHeaders(plan)
        internal.drawGates()
    end
end

local function onHide()
    setPlanning(false)
end

-- Adds the plan's levels to Blizzard's tooltip for a talent in this window.
local function onTalentTooltip(_, button, tooltip)
    local frame, tree = internal.frame, internal.tree
    if not (module.enabled and module.db.tooltip and frame and tree and not internal.planning) then
        return
    end
    if not (button.GetTalentFrame and button:GetTalentFrame() == frame and button.GetNodeID) then
        return
    end
    local plan = internal.getPlan(false)
    local id = button:GetNodeID()
    if not (plan and id and tree.nodes[id]) then
        return
    end
    local first = internal.firstLevel()
    local levels = internal.levelsFor(plan, id, Plan.PointsAt(plan.level, first), first)
    if #levels > 0 then
        tooltip:AddDoubleLine(L.TALENTPLANNER_PLANNED, concat(levels, ", "), 1, 1, 1, 1, 1, 1)
        tooltip:Show()
    end
end

local function start()
    local frame = PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame
    if not (frame and frame.GetConfigID and frame.EnumerateAllTalentButtons
        and frame.GetTalentButtonByNodeID) then
        internal.frame = nil
        return
    end
    internal.frame = frame
    -- The talent window may be protected in combat; make our children of it after.
    ns.AfterCombat(function()
        if not module.enabled then
            return
        end
        if not internal.ui then
            internal.createUI()
        end
        module:HookScript(frame, "OnShow", refresh)
        module:HookScript(frame, "OnHide", onHide)
        module:Hook(frame, "RefreshTreeHeaders", onTreeParts)
        module:Hook(frame, "RefreshGates", onTreeParts)
        if EventRegistry then
            EventRegistry:RegisterCallback("TalentFrameBase.ButtonsUpdated", refresh, module)
            EventRegistry:RegisterCallback("TalentDisplay.TooltipCreated", onTalentTooltip, module)
        end
        refresh()
    end)
end

function module:OnEnable()
    if not (C_Traits and C_Traits.GetTreeNodes and C_Traits.GetNodeInfo
        and C_Traits.GetGroupDisplayInfoByTreeID) then
        return
    end
    self:On("PLAYER_LEVEL_UP", internal.onLevelUp)
    self:On("TRAIT_CONFIG_UPDATED", refresh)
    self:On("TRAIT_CONFIG_UPDATED", internal.checkPoints)
    internal.checkPoints()
    ns.AddOns.WhenLoaded(ADDON, start)
end

function module:OnDisable()
    ns.AddOns.Cancel(ADDON, start)
    if EventRegistry then
        EventRegistry:UnregisterCallback("TalentFrameBase.ButtonsUpdated", module)
        EventRegistry:UnregisterCallback("TalentDisplay.TooltipCreated", module)
    end
    local ui = internal.ui
    if ui then
        setPlanning(false)
        ui.glow:Hide()
        ui.bar:Hide()
    end
    internal.planning = false
    internal.earned = nil
    internal.clearPlanVisuals()
end

function module:OnOptionChanged(key)
    if key == "reminder" then
        internal.earned = nil
        internal.checkPoints()
    end
    refresh()
end
