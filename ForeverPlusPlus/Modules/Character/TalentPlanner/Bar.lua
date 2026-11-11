-- Talent Planner's bar along the bottom of the talent window: the Plan Talents button, a line
-- naming the plan's next talent (hover it for the plan in order), the dropdown of this character's
-- plans with new, rename, share, import, and delete, and while planning, the level box and the
-- Reset and Clear buttons. createUI makes it once; TalentPlanner.lua's refresh calls drawBar.
local _, ns = ...

local ipairs, format, tonumber, tostring, select = ipairs, string.format, tonumber, tostring, select
local max, min, floor, tremove = math.max, math.min, math.floor, table.remove
local CreateFrame, UnitLevel, UnitClass, GameTooltip = CreateFrame, UnitLevel, UnitClass, GameTooltip

local L = ns.L
local Plan = ns.TalentPlan
local showError = ns.Frames.ErrorMessage

local module = ns.modules.TalentPlanner
local internal = module.internal

local ATLAS_GLOW = "talents-node-square-greenglow" -- Blizzard's square talent node glow

local ORDER_LINES = 20 -- runs listed before "...and N more"

-- The plan in order, a line for each run of points in one talent: its ranks on the left and their
-- levels on the right, green once you're that level. Out of planning, only what's left to learn.
local function orderTooltip(owner)
    local tree, planning = internal.tree, internal.planning
    local plan = tree and internal.getPlan(false)
    if not (plan and #plan.picks > 0) then
        return
    end
    local first = internal.firstLevel()
    local points = Plan.PointsAt(plan.level, first)
    local level = UnitLevel("player")
    local runs, counts = {}, {}
    for i = 1, min(#plan.picks, points) do
        local id = plan.picks[i]
        counts[id] = (counts[id] or 0) + 1
        if planning or counts[id] > (tree.ranks[id] or 0) then
            local run = runs[#runs]
            if run and run.id == id and run.last == i - 1 then
                run.last, run.toRank = i, counts[id]
            else
                runs[#runs + 1] = { id = id, first = i, last = i, fromRank = counts[id],
                    toRank = counts[id] }
            end
        end
    end
    if #runs == 0 then
        return
    end
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    GameTooltip:SetText(planning and L.TALENTPLANNER_ORDER or L.TALENTPLANNER_UPCOMING, 1, 1, 1)
    for i, run in ipairs(runs) do
        if i > ORDER_LINES then
            GameTooltip:AddLine(format(L.TALENTPLANNER_MORE_LINES, #runs - ORDER_LINES), 0.5, 0.5, 0.5)
            break
        end
        local node = internal.describe(tree.nodes[run.id])
        local ranks = run.fromRank == run.toRank and format("%d/%d", run.toRank, node.max)
            or format("%d-%d/%d", run.fromRank, run.toRank, node.max)
        local from, to = Plan.LevelOf(run.first, first), Plan.LevelOf(run.last, first)
        local levels = from == to and format(L.TALENTPLANNER_LEVEL_ONE, from)
            or format(L.TALENTPLANNER_LEVEL_RANGE, from, to)
        local ready = not planning and from <= level
        GameTooltip:AddDoubleLine(internal.withIcon(node) .. " |cff808080" .. ranks .. "|r", levels,
            1, 1, 1, ready and 0.1 or 1, 1, ready and 0.1 or 1)
    end
    GameTooltip:Show()
end

function internal.drawBar(plan)
    local ui, planning = internal.ui, internal.planning
    ui.planButton:SetText(planning and L.TALENTPLANNER_DONE or L.TALENTPLANNER_PLAN)
    ui.controls:SetShown(planning)
    if ui.dropdown then
        ui.dropdown:GenerateMenu() -- shows the picked plan's name, for this spec tab
    end
    if planning then
        local points = internal.pointsOf(plan)
        local text = format(L.TALENTPLANNER_POINTS, min(#plan.picks, points), points)
        if #plan.picks > points then
            text = text .. " " .. format(L.TALENTPLANNER_MORE, #plan.picks - points)
        end
        ui.summary:SetText(text)
        if not ui.level:HasFocus() then
            ui.level:SetText(tostring(plan.level))
        end
        return
    end
    local tree = internal.tree
    local index, id = Plan.Next(plan and plan.picks or {}, tree.ranks)
    if plan and index and index <= internal.pointsOf(plan) then
        local node = internal.describe(tree.nodes[id])
        ui.summary:SetText(format(L.TALENTPLANNER_NEXT, internal.withIcon(node),
            Plan.LevelOf(index, internal.firstLevel())))
    elseif plan and #plan.picks > 0 then
        ui.summary:SetText(L.TALENTPLANNER_COMPLETE)
    else
        ui.summary:SetText("")
    end
end

-- Our frames ----------------------------------------------------------------------------------

local function simpleTooltip(owner, title, text)
    owner:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(title, 1, 1, 1)
        GameTooltip:AddLine(text, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    owner:SetScript("OnLeave", internal.onLeave)
end

-- Adds a plan to this character's list and picks it.
local function addPlan(plan)
    local builds = internal.getBuilds(true)
    if builds then
        builds.list[#builds.list + 1] = plan
        builds.active = #builds.list
        internal.refresh()
    end
end

local function promptNew()
    local builds = internal.getBuilds(true)
    ns.PromptName("TALENTPLANNER_NEW", L.TALENTPLANNER_NEW_PROMPT,
        format(L.TALENTPLANNER_PLAN_NAME, builds and #builds.list + 1 or 1), function(name)
            addPlan(internal.newPlan(name))
        end)
end

local function promptRename()
    local plan = internal.getPlan(true)
    ns.PromptName("TALENTPLANNER_RENAME", L.TALENTPLANNER_RENAME_PROMPT, plan and plan.name,
        function(name)
            local current = internal.getPlan(true)
            if current then
                current.name = name
                internal.refresh()
            end
        end)
end

local function share()
    local plan = internal.getPlan(true)
    local tree = internal.tree
    if plan and tree then
        ns.Prompt("TALENTPLANNER_SHARE", L.TALENTPLANNER_SHARE_PROMPT, Plan.Encode(tree.treeID, plan))
    end
end

-- Why a website's link can't be imported (TalentPlan.FromLink's reasons).
local function linkError(link, reason, total)
    if reason == "class" then
        return L.TALENTPLANNER_IMPORT_CLASS
    elseif reason == "old" then
        return format(L.TALENTPLANNER_IMPORT_OLD, Plan.SiteName(link))
    elseif reason == "new" then
        return format(L.TALENTPLANNER_IMPORT_NEW, Plan.SiteName(link))
    elseif reason == "tree" then
        return format(L.TALENTPLANNER_IMPORT_TREE, Plan.SiteName(link))
    elseif reason == "rank" then
        return L.TALENTPLANNER_IMPORT_RANK
    elseif reason == "points" then
        return format(L.TALENTPLANNER_IMPORT_POINTS, total, Plan.MAX_POINTS)
    end
    return L.TALENTPLANNER_IMPORT_INVALID
end

-- A pasted share string or website link as { name, level, picks }, or nil and why not.
local function readImport(text, tree)
    local data = Plan.Decode(text)
    if data then
        if data.treeID ~= tree.treeID then
            return nil, L.TALENTPLANNER_IMPORT_CLASS
        end
        local _, _, bad = Plan.Simulate(tree, data.picks)
        if bad then
            return nil, L.TALENTPLANNER_IMPORT_INVALID
        end
        return data
    end
    local link, why = Plan.ParseLink(text)
    if not link then
        return nil, why == "old" and format(L.TALENTPLANNER_IMPORT_OLD, "talentsforever.com")
            or L.TALENTPLANNER_IMPORT_BAD
    end
    local picks, reason, total = Plan.FromLink(tree, link, select(2, UnitClass("player")))
    if not picks then
        return nil, linkError(link, reason, total)
    end
    return { name = "", level = link.level or internal.maxLevel(), picks = picks }
end

-- Reads a pasted share string or website link into a new plan, if it's this class's and fits
-- this tree.
local function import(text)
    local tree = internal.tree
    if not tree then
        showError(L.TALENTPLANNER_IMPORT_BAD)
        return
    end
    local data, problem = readImport(text, tree)
    if not data then
        showError(problem)
        return
    end
    local builds = internal.getBuilds(true)
    local name = data.name ~= "" and data.name
        or format(L.TALENTPLANNER_PLAN_NAME, builds and #builds.list + 1 or 1)
    addPlan({ name = name, level = max(internal.firstLevel(), min(internal.maxLevel(), data.level)),
        picks = data.picks })
end

local function promptImport()
    ns.Prompt("TALENTPLANNER_IMPORT", L.TALENTPLANNER_IMPORT_PROMPT, "", import)
end

local function deletePlan()
    ns.Confirm("TALENTPLANNER_DELETE", L.TALENTPLANNER_DELETE_CONFIRM, function()
        local builds = internal.getBuilds(true)
        if not builds then
            return
        end
        tremove(builds.list, builds.active)
        if #builds.list == 0 then
            builds.list[1] = internal.newPlan(format(L.TALENTPLANNER_PLAN_NAME, 1))
        end
        builds.active = min(builds.active, #builds.list)
        internal.refresh()
    end)
end

local function setupMenu(_, root)
    local builds = internal.frame and internal.tree and internal.getBuilds(true)
    if not builds then
        return
    end
    for index, plan in ipairs(builds.list) do
        root:CreateRadio(plan.name, function(i)
            return builds.active == i
        end, function(i)
            builds.active = i
            internal.refresh()
        end, index)
    end
    root:CreateDivider()
    root:CreateButton(L.TALENTPLANNER_NEW, promptNew)
    root:CreateButton(L.TALENTPLANNER_RENAME, promptRename)
    root:CreateButton(L.TALENTPLANNER_SHARE, share)
    local importButton = root:CreateButton(L.TALENTPLANNER_IMPORT, promptImport)
    if importButton.SetTooltip then
        importButton:SetTooltip(function(tooltip)
            tooltip:SetText(L.TALENTPLANNER_IMPORT, 1, 1, 1)
            tooltip:AddLine(L.TALENTPLANNER_IMPORT_DESC, nil, nil, nil, true)
        end)
    end
    root:CreateButton(L.TALENTPLANNER_DELETE, deletePlan)
end

local function applyLevel(box)
    -- Hiding the bar while the box has focus lands here too, with no tree to read levels from.
    if not internal.tree then
        box:ClearFocus()
        return
    end
    local plan = internal.getPlan(true)
    local value = tonumber(box:GetText())
    if plan and value then
        plan.level = max(internal.firstLevel(), min(internal.maxLevel(), floor(value)))
    end
    box:ClearFocus()
    internal.refresh()
end

function internal.createUI()
    local frame = internal.frame
    local ui = {}
    internal.ui = ui
    local anchor = frame.Background or frame
    local bar = CreateFrame("Frame", nil, frame)
    bar:SetAllPoints(anchor)
    bar:SetFrameLevel(frame:GetFrameLevel() + 1010) -- with Blizzard's tabs and headers
    ui.bar = bar

    -- Where Blizzard's loadout dropdown sits on Mainline; Forever hides it.
    local planButton = ns.Frames.Button(bar, nil, 150, function()
        internal.setPlanning(not internal.planning)
    end)
    planButton:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 48, 8)
    simpleTooltip(planButton, L.TALENTPLANNER_TITLE, L.TALENTPLANNER_PLAN_DESC)
    ui.planButton = planButton

    -- One line between our button and Blizzard's Apply Changes, cut short with "..." when the
    -- talent's name is long; hovering it lists the plan in order.
    local info = CreateFrame("Frame", nil, bar)
    info:SetHeight(22)
    info:SetPoint("LEFT", planButton, "RIGHT", 12, 0)
    if frame.ApplyButton then
        info:SetPoint("RIGHT", frame.ApplyButton, "LEFT", -12, 0)
    else
        info:SetWidth(260)
    end
    info:SetScript("OnEnter", orderTooltip)
    info:SetScript("OnLeave", internal.onLeave)
    local summary = info:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    summary:SetPoint("LEFT")
    summary:SetPoint("RIGHT")
    summary:SetJustifyH("LEFT")
    summary:SetWordWrap(false)
    ui.summary = summary

    -- The plans of this character and spec, in Blizzard's dropdown, with what can be done to them.
    -- Probe: WowStyle1DropdownTemplate is Mainline's menu dropdown.
    local dropdown
    if WowStyle1DropdownMixin then
        dropdown = CreateFrame("DropdownButton", nil, bar, "WowStyle1DropdownTemplate")
        dropdown:SetWidth(170)
        dropdown:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -48, 8)
        dropdown:SetupMenu(setupMenu)
        ui.dropdown = dropdown
    end

    local controls = CreateFrame("Frame", nil, bar)
    controls:SetAllPoints()
    controls:Hide()
    ui.controls = controls

    local clear = ns.Frames.Button(controls, L.TALENTPLANNER_CLEAR, 90, function()
        ns.Confirm("TALENTPLANNER_CLEAR", L.TALENTPLANNER_CLEAR_CONFIRM, function()
            local plan = internal.getPlan(true)
            if plan then
                plan.picks = {}
                internal.refresh()
            end
        end)
    end)
    if dropdown then
        clear:SetPoint("RIGHT", dropdown, "LEFT", -12, 0)
    else
        clear:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -48, 8)
    end
    simpleTooltip(clear, L.TALENTPLANNER_CLEAR, L.TALENTPLANNER_CLEAR_DESC)

    local reset = ns.Frames.Button(controls, L.TALENTPLANNER_RESET, 90, function()
        ns.Confirm("TALENTPLANNER_RESET", L.TALENTPLANNER_RESET_CONFIRM, function()
            local plan = internal.getPlan(true)
            local tree = internal.tree
            if plan and tree then
                plan.picks = Plan.FromRanks(tree, tree.ranks)
                internal.refresh()
            end
        end)
    end)
    reset:SetPoint("RIGHT", clear, "LEFT", -6, 0)
    simpleTooltip(reset, L.TALENTPLANNER_RESET, L.TALENTPLANNER_RESET_DESC)

    local level = CreateFrame("EditBox", nil, controls, "InputBoxTemplate")
    level:SetSize(28, 20)
    level:SetPoint("RIGHT", reset, "LEFT", -16, 0)
    level:SetAutoFocus(false)
    level:SetNumeric(true)
    level:SetMaxLetters(2)
    level:SetJustifyH("CENTER")
    level:SetScript("OnEnterPressed", applyLevel)
    level:SetScript("OnEditFocusLost", applyLevel)
    level:SetScript("OnEscapePressed", function(self)
        self:SetText("") -- refresh puts the saved level back
        self:ClearFocus()
    end)
    simpleTooltip(level, L.TALENTPLANNER_LEVEL, L.TALENTPLANNER_LEVEL_DESC)
    ui.level = level

    local levelLabel = controls:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    levelLabel:SetPoint("RIGHT", level, "LEFT", -8, 0)
    levelLabel:SetText(L.TALENTPLANNER_LEVEL)

    -- Our buttons go in the tree's own panel so they scale and move with Blizzard's.
    local nodes = CreateFrame("Frame", nil, frame.ButtonsParent or frame)
    nodes:SetAllPoints()
    ui.nodes = nodes

    -- The next planned talent's glow: Blizzard's node glow, gold so it stands out from the green
    -- one Blizzard gives every talent you can learn.
    local glow = CreateFrame("Frame", nil, nodes)
    glow:Hide()
    local texture = glow:CreateTexture(nil, "OVERLAY")
    texture:SetAllPoints()
    texture:SetAtlas(ATLAS_GLOW)
    texture:SetBlendMode("ADD")
    texture:SetVertexColor(1, 0.82, 0)
    local pulse = texture:CreateAnimationGroup()
    pulse:SetLooping("REPEAT")
    local fadeIn = pulse:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0.2)
    fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(0.6)
    fadeIn:SetOrder(1)
    local fadeOut = pulse:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0.2)
    fadeOut:SetDuration(0.6)
    fadeOut:SetOrder(2)
    glow:SetScript("OnShow", function()
        pulse:Play()
    end)
    glow:SetScript("OnHide", function()
        pulse:Stop()
    end)
    ui.glow = glow
end
