-- Character Window: tidies the Character window. The Equipment Manager, Titles, and Pet tabs that
-- sit across the top of the stats pane move to the side, under the Character, Reputation, and
-- other tabs, and the pane's header (the portrait tab) goes, so the stats start at the top. The
-- window's title becomes your level and name in your class color, each item gets a durability bar
-- (Durability.lua), and the Skills tab can show the skills of the weapons you wear in green
-- (Skills.lua).
local _, ns = ...

local _G, ipairs, pairs, type, CreateFrame = _G, ipairs, pairs, type, CreateFrame
local format, UnitLevel, UnitName, UnitPVPName = string.format, UnitLevel, UnitName, UnitPVPName
local HasPetUI, SetPortraitTexture = HasPetUI, SetPortraitTexture

local L = ns.L
local Colors = ns.Colors

local module = ns.NewModule("CharacterWindow", L.CHARACTERWINDOW_DESC, {
    enabled = true,
    sideTabs = true,
    colorTitle = true,
    durability = "always", -- "off", or which items get a bar (Durability.lua)
    weaponSkills = true, -- green skill bars for the weapons worn (Skills.lua)
})
module.title = L.CHARACTERWINDOW_TITLE
module.category = "character"
module.internal = {}
local internal = module.internal

-- Before 0.8.0, Durability Bars was a module of its own, with a Show dropdown. CharacterFrame is
-- this module's name at that layout; Core's layout version 3 renames it (RENAMED).
ns.Migrate(1, function(db)
    local saved = db.modules or {}
    local old = saved.DurabilityBars
    if not old then
        return
    end
    local db = saved.CharacterFrame or {}
    saved.CharacterFrame = db
    db.durability = old.enabled == false and "off" or old.show
    saved.DurabilityBars = nil
end)

module.options = {
    {
        key = "sideTabs", name = L.CHARACTERWINDOW_SIDETABS, description = L.CHARACTERWINDOW_SIDETABS_DESC,
        changed = "0.8.0", -- the Titles tab
    },
    { key = "colorTitle", name = L.CHARACTERWINDOW_COLORTITLE, description = L.CHARACTERWINDOW_COLORTITLE_DESC },
    {
        key = "durability", name = L.CHARACTERWINDOW_DURABILITY,
        description = L.CHARACTERWINDOW_DURABILITY_DESC, added = "0.8.0",
        choices = {
            { "always", L.CHARACTERWINDOW_DURABILITY_ALWAYS },
            { "worn", L.CHARACTERWINDOW_DURABILITY_WORN },
            { "half", L.CHARACTERWINDOW_DURABILITY_HALF },
            { "quarter", L.CHARACTERWINDOW_DURABILITY_QUARTER },
            { "off", L.CHARACTERWINDOW_DURABILITY_OFF },
        },
    },
    {
        key = "weaponSkills", name = L.CHARACTERWINDOW_WEAPONSKILLS,
        description = L.CHARACTERWINDOW_WEAPONSKILLS_DESC, added = "0.8.2",
    },
}

local ADDON = "Blizzard_UIPanels_Game"
local STATS = 1 -- Blizzard's PAPERDOLL_SIDEBARS index for the stats; every other one gets a side tab
local SPACING = 2 -- between side tabs, ours included, as Blizzard spaces its own
local BOTTOM = 6 -- kept clear above the bottom of the window
local MODEL_RAISE = 20 -- how far the character moves up while the level strip is gone

local started
local tabs = {} -- sidebar index -> our side tab, from STATS + 1 to numSidebars
local numSidebars = 0
local panes -- pane -> true for the scrolling lists (stats, pet, titles), false for the others
local petPane

local function frameOf(index)
    return _G.GetPaperDollSideBarFrame and _G.GetPaperDollSideBarFrame(index)
end

-- Sidebars are found by their pane, not their place: build 70170 put Titles third and moved the
-- pet to fourth (Forever only).
local function isPet(index)
    return frameOf(index) == petPane
end

-- Title ----------------------------------------------------------------------------------------

local function updateTitle()
    local frame = _G.CharacterFrame
    if not (module.db.colorTitle and (frame.activeSubframe or "PaperDollFrame") == "PaperDollFrame") then
        return
    end
    local text = frame:GetTitleText()
    -- The level in gold and the name in the class color, so the text itself is plain white.
    local level = Colors.Text(NORMAL_FONT_COLOR, UnitLevel("player"))
    local name = UnitPVPName("player") or UnitName("player")
    local color = Colors.Class("player")
    text:SetText(format(L.CHARACTERWINDOW_TITLE_FORMAT, level, color and Colors.Text(color, name) or name))
    text:SetTextColor(1, 1, 1)
end

-- Blizzard's own title back, for when the option or the module turns off.
local function restoreTitle()
    _G.CharacterFrame:UpdateTitle()
end

-- Blizzard's "Level 18 Mage" line on the rock strip over the model says what the title already
-- does, so while the title shows the level the line goes, and so does the strip: the model's
-- background runs up to the top of the pane in its place. Blizzard shows and hides the line for
-- the pet pane (whose own line stays), so it's faded instead.
local function updateLevelLine()
    local hide = module.enabled and module.db.colorTitle
    local line, paperDoll = _G.PaperDollLevelInfo, _G.PaperDollFrame
    if line then
        line:SetAlpha(hide and 0 or 1)
    end
    local host, scene = paperDoll.TopBackgroundStripHost, paperDoll.CharacterModelScene
    if not (host and host.TopBackgroundStrip and scene) then
        return
    end
    host:SetAlpha(hide and 0 or 1)
    -- The zoom and rotate buttons move up into the strip's place too, level with the arrow
    -- that folds the stats away: 6 below the top of the pane instead of Blizzard's 40.
    local controls, pane = scene.ControlFrame, _G.CharacterFrameLeftPaneHost
    if controls and pane then
        controls:SetPoint("TOP", pane, "TOP", 0, hide and -6 or -40)
    end
    -- And the character moves up into the room the strip leaves. Blizzard never translates this
    -- scene's view (its panning moves the camera), so 0, 0 puts it back.
    if scene.SetViewTranslation then
        scene:SetViewTranslation(0, hide and MODEL_RAISE or 0)
    end
    if hide then
        scene:SetPoint("TOPLEFT", host, "TOPLEFT")
        scene:SetPoint("TOPRIGHT", host, "TOPRIGHT")
    else
        scene:SetPoint("TOPLEFT", host.TopBackgroundStrip, "BOTTOMLEFT")
        scene:SetPoint("TOPRIGHT", host.TopBackgroundStrip, "BOTTOMRIGHT")
    end
end

-- Header ---------------------------------------------------------------------------------------

local function collapsed()
    return _G.CharacterFrame:IsRightPaneCollapsed()
end

-- The tab row goes. The level lines stay where they are, on the strip over the model, and
-- Blizzard swaps the player's for the pet's itself.
local function updateHeader()
    if module.db.sideTabs then
        _G.PaperDollSidebarTabs:Hide()
    end
end

-- The stats, pet stats, titles, and equipment sets panes hang from the bottom of the stone
-- header, so they move up to the top of the right pane.
local function anchorPanes(up)
    local host = _G.CharacterFrame.RightPaneHost
    for pane, stats in pairs(panes) do
        if up then
            pane:SetPoint("TOPLEFT", host, "TOPLEFT")
        else
            pane:SetPoint("TOPLEFT", host.StoneBg, "BOTTOMLEFT")
        end
        -- The lists leave room at the bottom for a divider line; take most of it back so they
        -- run further down.
        if stats then
            pane.ScrollBox:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -30, up and 4 or 30)
            -- The scrollbar stops a little short of the list's end, so it isn't pressed against
            -- the window's edge.
            pane.ScrollBar:SetPoint("BOTTOMLEFT", pane.ScrollBox, "BOTTOMRIGHT", 0, up and 10 or 0)
        end
    end
    host.StoneBg:SetAlpha(up and 0 or 1)
end

-- Blizzard's header back.
local function showHeader()
    anchorPanes(false)
    _G.PaperDollSidebarTabs:SetShown(_G.PaperDollFrame:IsShown() and not collapsed())
end

local function applyHeader()
    if module.db.sideTabs then
        anchorPanes(true)
        updateHeader()
    else
        showHeader()
    end
end

-- Side tabs ------------------------------------------------------------------------------------

-- The pet's portrait, cropped to the tab like the Character tab's. A new portrait can undo the
-- crop, so it goes on again each time.
local function petPortrait(tab)
    SetPortraitTexture(tab.Icon, "pet")
    if tab.UpdateIconInterior then
        tab:UpdateIconInterior()
    end
end

-- Like Blizzard's sidebar tabs: the name, and while the tab can't be used, why in red (no titles
-- yet, no pet).
local function tooltipFor(info, tab)
    return function(tooltip)
        _G.GameTooltip_SetTitle(tooltip, info.name)
        local reason = info.disabledTooltip
        if type(reason) == "function" then
            reason = reason()
        end
        if not tab.active and reason then
            _G.GameTooltip_AddErrorLine(tooltip, reason, true)
        end
        return true
    end
end

-- The scale for our tabs, so the last one ends inside the window. Blizzard's own six tabs fill
-- most of its 484 high side, so ours get smaller when they wouldn't fit at full size.
local function fit(frame, last, count, height)
    local bottom, lastBottom = frame:GetBottom(), last and last:GetBottom()
    if count == 0 or height <= 0 or not (bottom and lastBottom) then
        return 1
    end
    local scale = (lastBottom - bottom - BOTTOM - count * SPACING) / (count * height)
    return scale < 1 and scale > 0 and scale or 1
end

local function refreshTabs()
    local frame = _G.CharacterFrame
    local show = module.db.sideTabs and frame:IsShown()
    local onPaperDoll = _G.PaperDollFrame:IsShown() and not collapsed()

    local last
    for _, tab in ipairs(frame.ModeTabs.Tabs) do
        if tab:IsShown() then
            last = tab
        end
    end

    local count, height = 0, 0
    for index = STATS + 1, numSidebars do
        local tab = tabs[index]
        local visible = show and last and (not isPet(index) or HasPetUI()) and true or false
        tab:SetShown(visible)
        if visible then
            count, height = count + 1, tab:GetHeight()
        end
    end
    local scale = fit(frame, last, count, height)

    local above = last
    local ownSelected
    for index = STATS + 1, numSidebars do
        local tab = tabs[index]
        if tab:IsShown() then
            local pet = isPet(index)
            -- A tab's offsets are in its own scale, so they're divided by it to stay the same gap.
            tab:SetScale(scale)
            tab:ClearAllPoints()
            tab:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -SPACING / scale)
            above = tab
            local bar = frameOf(index)
            local checked = onPaperDoll and bar and bar:IsShown() or false
            ownSelected = ownSelected or checked
            tab:SetChecked(checked)
            tab.active = _G.PAPERDOLL_SIDEBARS[index].IsActive()
            tab:SetAlpha(tab.active and 1 or 0.5)
            tab.Icon:SetDesaturated(not tab.active)
            if pet then
                petPortrait(tab)
            end
        end
    end

    -- The Character tab isn't the selected one while one of ours is.
    if show then
        frame.ModeTabs.CharacterTab:SetChecked(_G.PaperDollFrame:IsShown() and not ownSelected)
    end
    updateHeader()
end

-- A side tab opens the Character window's pane for it, and the Character tab goes back to stats.
local function toggle(index)
    local frame = _G.CharacterFrame
    if frame:IsRightPaneCollapsed() then
        frame:SetRightPaneCollapsed(false)
    end
    if not _G.PaperDollFrame:IsShown() then
        _G.ToggleCharacter("PaperDollFrame", true)
    end
    _G.PaperDollFrame_SetSidebar(_G.PaperDollSidebarTabs, index)
    refreshTabs()
end

local function onModeTabClicked(_, tab)
    if module.db.sideTabs and tab.frameName == "PaperDollFrame" then
        _G.PaperDollFrame_SetSidebar(_G.PaperDollSidebarTabs, STATS)
    end
end

-- Use the icon Blizzard's own tab shows, so it stays in step with the game, at our tab's size.
local function copyIcon(icon, source)
    local atlas = source.GetAtlas and source:GetAtlas()
    if atlas then
        icon:SetAtlas(atlas)
    else
        icon:SetTexture(source:GetTexture())
        icon:SetTexCoord(source:GetTexCoord())
    end
    local width, height = source:GetSize()
    icon:SetSize(36, width > 0 and 36 * height / width or 36)
end

local function makeTab(index)
    local info = _G.PAPERDOLL_SIDEBARS[index]
    local tab = CreateFrame("Frame", nil, _G.CharacterFrame, "LargeSideTabButtonTemplate")
    tab:EnableMouse(true)
    tab.tooltipText = info.name
    local setup = tooltipFor(info, tab)
    function tab:GetTooltipTextSetupFunction()
        return setup
    end
    tab:Hide()
    local source = _G["PaperDollSidebarTab" .. index]
    if isPet(index) then
        tab:SetFillToInterior(true)
    elseif source then
        copyIcon(tab.Icon, source.Icon)
    end
    tab:SetCustomOnMouseUpHandler(function(self, button, upInside)
        if button == "LeftButton" and upInside and self.active then
            toggle(index)
        end
    end)
    return tab
end

-- Start ----------------------------------------------------------------------------------------

local function start()
    if started or not (_G.CharacterFrame and _G.PaperDollSidebarTabs and _G.PaperDollFrame
        and _G.PAPERDOLL_SIDEBARS and _G.PaperDollFrame_SetSidebar) then
        return
    end
    started = true

    petPane = _G.CharacterStatsPanePetScrollBox
    panes = {
        [_G.CharacterStatsPaneScrollBox] = true,
        [petPane] = true,
        [_G.CharacterStatsPane] = false,
        [_G.PaperDollFrame.EquipmentManagerPane] = false,
    }
    -- The titles list has the stats lists' scroll box and bar, and the same gap under them.
    if _G.PaperDollFrame.TitleManagerPane then
        panes[_G.PaperDollFrame.TitleManagerPane] = true
    end
    numSidebars = #_G.PAPERDOLL_SIDEBARS
    for index = STATS + 1, numSidebars do
        tabs[index] = makeTab(index)
    end

    -- Blizzard shows the header again whenever the pane opens.
    module:HookScript(_G.PaperDollSidebarTabs, "OnShow", updateHeader)
    module:HookScript(_G.PaperDollFrame, "OnShow", refreshTabs)
    module:HookScript(_G.PaperDollFrame, "OnHide", refreshTabs)
    module:Hook("PaperDollFrame_UpdateSidebarTabs", refreshTabs)
    module:Hook("PaperDollFrame_SetSidebar", refreshTabs)
    module:Hook(_G.CharacterFrame, "RefreshRightPane", refreshTabs)
    module:Hook(_G.CharacterFrame, "UpdateTabLayout", refreshTabs)
    module:Hook(_G.CharacterFrame, "SetSelectedModeTabByFrame", refreshTabs)
    module:Hook(_G.CharacterFrame, "OnModeTabClicked", onModeTabClicked)
    module:HookScript(_G.CharacterFrame, "OnShow", refreshTabs)
    module:HookScript(_G.CharacterFrame, "OnHide", refreshTabs)
    module:Hook(_G.CharacterFrame, "UpdateTitle", updateTitle)

    applyHeader()
    refreshTabs()
    updateTitle()
    updateLevelLine()
end

local function onPortrait(event, unit)
    if not started then
        return
    end
    -- Only the pet's portrait is drawn on a tab; UNIT_PORTRAIT_UPDATE comes for every unit.
    if event == "UNIT_PORTRAIT_UPDATE" and ns.IsText(unit) and unit ~= "pet" then
        return
    end
    for index, tab in pairs(tabs) do
        if isPet(index) and tab:IsShown() then
            petPortrait(tab)
        end
    end
end

-- Blizzard only updates its pet tab while the stats pane is open, so ours follows the pet on the
-- Reputation and other panes too.
local function onPet(_, unit)
    if started and unit == "player" then
        refreshTabs()
    end
end

-- Blizzard only rechecks which of its tabs can be used when the stats pane changes, so a first
-- title or equipment set wouldn't wake up our tab until then.
local function onTabsChanged()
    if started and _G.CharacterFrame:IsShown() then
        refreshTabs()
    end
end

-- Blizzard redoes the title for a new name or title, but not for a new level.
local function onLevel(_, unit)
    if started and unit == "player" and _G.CharacterFrame:IsShown() then
        updateTitle()
    end
end

-- Once the character frame has loaded: the tabs and title, the durability bars, and the skills.
local function load()
    start()
    internal.updateDurability()
    internal.updateWeaponSkills()
end

function module:OnEnable()
    internal.enableDurability()
    internal.enableWeaponSkills()
    self:On("UNIT_LEVEL", onLevel)
    self:On("UNIT_PET", onPet)
    self:On("UNIT_PORTRAIT_UPDATE", onPortrait)
    self:On("PORTRAITS_UPDATED", onPortrait)
    self:On("KNOWN_TITLES_UPDATE", onTabsChanged)
    self:On("EQUIPMENT_SETS_CHANGED", onTabsChanged)
    if _G.CharacterFrame then
        start()
    end
    if started then
        applyHeader()
        refreshTabs()
        updateTitle()
        updateLevelLine()
        internal.updateDurability()
        internal.updateWeaponSkills()
    else
        ns.AddOns.WhenLoaded(ADDON, load)
    end
end

function module:OnDisable()
    ns.AddOns.Cancel(ADDON, load)
    internal.updateDurability()
    internal.updateWeaponSkills()
    if not started then
        return
    end
    showHeader()
    for _, tab in pairs(tabs) do
        tab:Hide()
    end
    _G.CharacterFrame.ModeTabs.CharacterTab:SetChecked(_G.PaperDollFrame:IsShown())
    restoreTitle()
    updateLevelLine()
end

function module:OnOptionChanged(key)
    if key == "durability" then
        internal.updateDurability()
        return
    elseif key == "weaponSkills" then
        internal.updateWeaponSkills()
        return
    end
    if not (self.enabled and started) then
        return
    end
    if key == "sideTabs" then
        applyHeader()
        refreshTabs()
    elseif key == "colorTitle" then
        if self.db.colorTitle then
            updateTitle()
        else
            restoreTitle()
        end
        updateLevelLine()
    end
end
