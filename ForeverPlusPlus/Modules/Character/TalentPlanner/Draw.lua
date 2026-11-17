-- Talent Planner on Blizzard's tree: while planning, our buttons over Blizzard's talent buttons
-- (theirs go transparent) with the plan's ranks in Blizzard's own art, the plan's points on the tab
-- headers, and Blizzard's row gates faded; out of planning, the glow on the plan's next talent.
-- TalentPlanner.lua's refresh calls these.
local _, ns = ...

local ipairs, pairs, format, concat = ipairs, pairs, string.format, table.concat
local max, min, setmetatable = math.max, math.min, setmetatable
local CreateFrame, IsShiftKeyDown, PlaySound, GameTooltip = CreateFrame, IsShiftKeyDown, PlaySound,
    GameTooltip

local L = ns.L
local Plan = ns.TalentPlan
local showError = ns.Frames.ErrorMessage

local module = ns.modules.TalentPlanner
local internal = module.internal

local GLOW_SIZE = 62 / 40 -- Blizzard's node glow is 62 across on a 40 button

-- Blizzard's square talent node art (TalentButtonArtMixin.ArtSet.Square), which Forever's
-- Classic-style trees use.
local ATLAS_MAXED = "talents-node-square-yellow"
local ATLAS_OPEN = "talents-node-square-green"
local ATLAS_CLOSED = "talents-node-square-gray"
local ATLAS_SHADOW = "talents-node-square-shadow"

local overlays = {} -- nodeID -> our button over Blizzard's
local labels = {} -- header -> our point count over a tab header's
local faded = setmetatable({}, { __mode = "k" }) -- Blizzard regions we set to alpha 0 -> true

local function playSound(name)
    local kit = SOUNDKIT and SOUNDKIT[name]
    if kit and PlaySound then
        PlaySound(kit)
    end
end

function internal.onLeave()
    GameTooltip:Hide()
end

-- Showing Blizzard's parts again ---------------------------------------------------------------

local INVISIBLE = TalentButtonUtil and TalentButtonUtil.BaseVisualState
    and TalentButtonUtil.BaseVisualState.Invisible

local function fade(region)
    faded[region] = true
    region:SetAlpha(0)
end

-- With the controller interface on, a faded talent button of Blizzard's isn't enough: its cursor
-- lands on any visible button, see-through or not, and with ours right over Blizzard's it took
-- theirs for some talents, where A is Blizzard's Add Point and not our click (in game
-- 2026-11-16). So while planning theirs are hidden, which is all that takes them off the
-- cursor's list (SmartNavigationMixin:IsButtonValid, build 70938). Talent buttons aren't
-- protected, and ours keep their place: a hidden frame still has its rectangle.
local hidden = setmetatable({}, { __mode = "k" }) -- Blizzard talent buttons we hid -> true

local function hide(button)
    hidden[button] = true
    button:Hide()
end

-- Puts back the alpha of everything we faded. A talent button Blizzard keeps invisible (alpha 0
-- is how it hides nodes) stays that way.
local function unfadeAll()
    for region in pairs(faded) do
        local hiddenNode = INVISIBLE and region.GetVisualState and region:GetVisualState() == INVISIBLE
        region:SetAlpha(hiddenNode and 0 or 1)
    end
    faded = setmetatable({}, { __mode = "k" })
    if next(hidden) then
        -- Only the buttons the tree still uses: one it has since put away stays hidden.
        local frame = internal.frame
        if frame and frame.EnumerateAllTalentButtons then
            for button in frame:EnumerateAllTalentButtons() do
                if hidden[button] then
                    button:Show()
                end
            end
        end
        hidden = setmetatable({}, { __mode = "k" })
    end
end

-- Takes the plan off the tree: our buttons and counts go, Blizzard's come back.
function internal.clearPlanVisuals()
    unfadeAll()
    for _, overlay in pairs(overlays) do
        overlay:Hide()
    end
    for _, label in pairs(labels) do
        label:Hide()
    end
end

-- Drawing -------------------------------------------------------------------------------------

local function onNodeClick(self, mouse)
    local tree = internal.tree
    local plan = internal.getPlan(true)
    local node = plan and tree and tree.nodes[self.nodeID]
    if not node then
        return
    end
    local points = internal.pointsOf(plan)
    local times = IsShiftKeyDown() and node.max or 1
    local changed, reason = false, nil
    for _ = 1, times do
        local ok
        if mouse == "RightButton" then
            ok, reason = Plan.Remove(tree, plan.picks, node.id, points)
        else
            ok, reason = Plan.Add(tree, plan.picks, node.id, points)
        end
        if not ok then
            break
        end
        changed = true
    end
    if changed then
        playSound(mouse == "RightButton" and "UI_CLASS_TALENT_NODE_REFUND" or "UI_CLASS_TALENT_NODE_SPEND")
        internal.refresh()
        if GameTooltip:IsOwned(self) then
            self:GetScript("OnEnter")(self)
        end
    elseif reason ~= "none" then
        showError(internal.reasonText(reason, node, plan))
    end
end

-- The controller's Y ------------------------------------------------------------------------------
-- With the controller interface on, A reaches a talent of ours as a left click and nothing
-- reaches it as a right one. The footer's Remove Point on Y asks Blizzard's own talent buttons,
-- and ours answering as those do tainted the controller's bindings ("action blocked" on closing
-- the window); a held trigger isn't reported inside the window (both in game, 2026-11-16). So
-- while the cursor is on a talent of ours it watches the Y button itself, a plain read of the
-- controller's state, and a press takes a point out.

local watched -- the talent of ours the cursor is on
local relaying = false -- drawOverlays is hiding our buttons to lay them out again
local yPress = ns.Gamepad.Press(ns.Gamepad.BUTTON.FACE_TOP) -- Y (GAMEPAD_FACE_TOP)

local function unwatchY(self)
    self:SetScript("OnUpdate", nil)
    if watched == self then
        watched = nil
    end
end

local function watchY(self)
    if watched ~= self then
        unwatchY(self)
        return
    end
    if yPress:Fired() then
        onNodeClick(self, "RightButton")
    end
end

local function onNodeLeave(self)
    unwatchY(self)
    internal.onLeave()
end

local function onNodeEnter(self)
    local tree = internal.tree
    local plan = internal.getPlan(true)
    local node = plan and tree and tree.nodes[self.nodeID]
    if not node then
        return
    end
    -- Also called to redraw the tooltip after a click, when the watch is already on.
    if watched ~= self and ns.Gamepad.On() then
        watched = self
        yPress:Reset() -- held as the cursor arrives isn't a press
        self:SetScript("OnUpdate", watchY)
    end
    internal.describe(node)
    local first = internal.firstLevel()
    local points = Plan.PointsAt(plan.level, first)
    local counts, tabs = Plan.Simulate(tree, plan.picks, points)
    local count = counts[node.id] or 0
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(node.name, 1, 1, 1)
    GameTooltip:AddLine(format(L.TALENTPLANNER_RANK, count, node.max), 1, 1, 1)
    -- Blizzard's own description of the rank, as its talent tooltips show it.
    if GameTooltip.AppendInfo then
        GameTooltip:AddLine(" ")
        GameTooltip:AppendInfo("GetTraitEntry", node.entryID, max(count, 1))
        if count > 0 and count < node.max then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(TALENT_BUTTON_TOOLTIP_NEXT_RANK or L.TALENTPLANNER_NEXT_RANK, 1, 1, 1)
            GameTooltip:AppendInfo("GetTraitEntry", node.entryID, count + 1)
        end
    end
    local levels = internal.levelsFor(plan, node.id, points, first)
    if #levels > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine(L.TALENTPLANNER_PLANNED, concat(levels, ", "), 1, 1, 1, 1, 1, 1)
    end
    if count < node.max then
        local ok, reason = Plan.CanTake(tree, counts, tabs, node.id)
        if ok and min(#plan.picks, points) >= points then
            reason = "points"
        end
        if reason then
            GameTooltip:AddLine(internal.reasonText(reason, node, plan), 1, 0.125, 0.125, true)
        end
    end
    GameTooltip:AddLine(" ")
    local green = GREEN_FONT_COLOR -- a click hint, green as Blizzard's instruction lines are
    local hint
    local Gamepad = ns.Gamepad
    if Gamepad.On() then
        -- The buttons as the player's own controller shows them.
        local add, remove = Gamepad.Label(Gamepad.BUTTON.FACE_BOTTOM), Gamepad.Label(Gamepad.BUTTON.FACE_TOP)
        if count < node.max then
            hint = format(L.TALENTPLANNER_CLICK_PAD, add, remove)
        else
            hint = format(L.TALENTPLANNER_CLICK_PAD_MAXED, remove)
        end
    else
        hint = count < node.max and L.TALENTPLANNER_CLICK or L.TALENTPLANNER_CLICK_MAXED
    end
    GameTooltip:AddLine(hint, green.r, green.g, green.b, true)
    GameTooltip:Show()
end

-- The first time a talent is shown its spell isn't loaded yet; when it loads, Blizzard redraws the
-- tooltip from the data it was given, which is only the rank's text we appended, so our name,
-- rank, and lines would be gone until the next hover. Draw ours again over it.
local redrawing = false
function internal.onTooltipRefreshed(tooltip)
    if redrawing or tooltip ~= GameTooltip then
        return
    end
    local owner = tooltip:GetOwner()
    if owner and owner.nodeID and overlays[owner.nodeID] == owner and owner:IsMouseOver() then
        redrawing = true
        onNodeEnter(owner)
        redrawing = false
    end
end

local function makeOverlay(id)
    local button = CreateFrame("Button", nil, internal.ui.nodes)
    button.nodeID = id
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button.Shadow = button:CreateTexture(nil, "BACKGROUND")
    button.Shadow:SetPoint("CENTER")
    button.Shadow:SetAtlas(ATLAS_SHADOW, true)
    button.Icon = button:CreateTexture(nil, "BORDER")
    button.Icon:SetPoint("CENTER")
    button.Border = button:CreateTexture(nil, "ARTWORK")
    button.Border:SetPoint("CENTER")
    button.Hover = button:CreateTexture(nil, "HIGHLIGHT")
    button.Hover:SetPoint("CENTER")
    button.Hover:SetBlendMode("ADD")
    button.Hover:SetAlpha(0.4)
    -- Where and how Blizzard's talent buttons write their rank (TalentButtonArtTemplate).
    button.Text = button:CreateFontString(nil, "OVERLAY", "SystemFont16_Shadow_ThickOutline")
    button.Text:SetPoint("BOTTOM", 11, 4)
    button:SetScript("OnClick", onNodeClick)
    button:SetScript("OnEnter", onNodeEnter)
    button:SetScript("OnLeave", onNodeLeave)
    button:SetScript("OnHide", function(self)
        if not relaying then
            unwatchY(self)
        end
    end)
    overlays[id] = button
    return button
end

-- Copies the size of a Blizzard region onto ours, so our art matches theirs at any button size.
local function sizeLike(ours, theirs, fallback)
    if theirs and theirs.GetSize then
        ours:SetSize(theirs:GetSize())
    else
        ours:SetSize(fallback, fallback)
    end
end

function internal.drawOverlays(plan)
    -- Hidden and shown again below: not a reason to stop watching the controller's Y on the one
    -- its cursor is on (a redraw of anyone's doing, such as a level up, would leave Y dead).
    relaying = true
    for _, overlay in pairs(overlays) do
        overlay:Hide()
    end
    relaying = false
    if not internal.planning then
        if watched then
            unwatchY(watched)
        end
        return
    end
    local tree = internal.tree
    local points = internal.pointsOf(plan)
    local counts, tabs = Plan.Simulate(tree, plan.picks, points)
    local full = min(#plan.picks, points) >= points
    for button in internal.frame:EnumerateAllTalentButtons() do
        local node = tree.nodes[button:GetNodeID()]
        if node then
            internal.describe(node)
            fade(button)
            if ns.Gamepad.On() then
                hide(button)
            end
            local overlay = overlays[node.id] or makeOverlay(node.id)
            overlay:ClearAllPoints()
            overlay:SetAllPoints(button)
            overlay:SetFrameLevel(button:GetFrameLevel() + 2)
            local width = button:GetWidth()
            sizeLike(overlay.Icon, button.Icon, width * 0.9)
            sizeLike(overlay.Border, button.StateBorder, width * 1.2)
            sizeLike(overlay.Hover, button.StateBorder, width * 1.2)
            overlay.Icon:SetTexture(node.icon)
            local count = counts[node.id] or 0
            local open = not full and Plan.CanTake(tree, counts, tabs, node.id)
            local atlas, color
            -- Gold at its highest rank in the plan, learned or not: green there read as room for
            -- another point.
            if count >= node.max then
                atlas, color = ATLAS_MAXED, YELLOW_FONT_COLOR
            elseif count > 0 or open then
                atlas, color = ATLAS_OPEN, GREEN_FONT_COLOR
            else
                atlas, color = ATLAS_CLOSED, DISABLED_FONT_COLOR
            end
            overlay.Border:SetAtlas(atlas)
            overlay.Hover:SetAtlas(atlas)
            overlay.Icon:SetDesaturated(count == 0 and not open)
            overlay.Text:SetText(format("%d/%d", count, node.max))
            overlay.Text:SetShown(not (node.max == 1 and tree.hideSingle))
            if color then
                overlay.Text:SetTextColor(color:GetRGB())
            end
            overlay:Show()
        end
    end
    -- The one being watched didn't come back (its talent left the tree): nothing to watch.
    if watched and not watched:IsShown() then
        unwatchY(watched)
    end
end

-- While planning, each tab header shows the plan's points in that tab instead of the spent ones.
function internal.drawHeaders(plan)
    for _, label in pairs(labels) do
        label:Hide()
    end
    local frame = internal.frame
    if not (internal.planning and plan and frame.treeHeaders) then
        return
    end
    local _, tabs = Plan.Simulate(internal.tree, plan.picks, internal.pointsOf(plan))
    for _, header in ipairs(frame.treeHeaders) do
        local info = header.displayInfo
        if info and header.Text then
            fade(header.Text)
            local label = labels[header]
            if not label then
                label = CreateFrame("Frame", nil, internal.ui.bar)
                label:SetAllPoints(header.Text)
                label.Text = label:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                label.Text:SetPoint("CENTER")
                labels[header] = label
            end
            label:SetFrameLevel(header:GetFrameLevel() + 1)
            label.Text:SetText(tabs[info.groupID] or 0)
            label:Show()
        end
    end
end

-- Blizzard's row gates say how many points the learned talents still need; the plan has its own.
function internal.drawGates()
    local frame = internal.frame
    if internal.planning and frame.gatePool then
        for gate in frame.gatePool:EnumerateActive() do
            fade(gate)
        end
    end
end

function internal.drawGlow(plan)
    local glow = internal.ui.glow
    glow:Hide()
    if internal.planning or not (module.db.glow and plan) then
        return
    end
    local index, id = Plan.Next(plan.picks, internal.tree.ranks)
    local _, unspent = internal.currency()
    if not index or index > internal.pointsOf(plan) or unspent <= 0 then
        return
    end
    local button = internal.frame:GetTalentButtonByNodeID(id)
    if button then
        local size = button:GetWidth() * GLOW_SIZE
        glow:ClearAllPoints()
        glow:SetPoint("CENTER", button)
        glow:SetSize(size, size)
        glow:SetFrameLevel(button:GetFrameLevel() + 2)
        glow:Show()
    end
end
