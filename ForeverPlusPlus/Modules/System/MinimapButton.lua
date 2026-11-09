-- Minimap Button: Forever++'s button on the minimap, in the addon compartment, or both. A click
-- opens a menu of quick module toggles and a right-click Forever++ settings (the other way round
-- with Swap Clicks off); while Error Catcher is on, a click with a key held shows its errors,
-- clears this session's, or clears them all (each key is an option), and the button shows how
-- many this session caught (through ns.Errors, never
-- Error Catcher itself). After a fresh install the button wears Blizzard's NEW label, and its
-- first click opens the About page instead, once; no popup at login.
local _, ns = ...

local format, type, tremove, sort = string.format, type, table.remove, table.sort
local cos, sin, rad, floor = math.cos, math.sin, math.rad, math.floor
local abs, max = math.abs, math.max
local ipairs, pairs, next, wipe = ipairs, pairs, next, wipe
local CreateFrame, GetCursorPosition = CreateFrame, GetCursorPosition

local L = ns.L
local Errors = ns.Errors
local Keys = ns.Keys
local Colors = ns.Colors

-- The tooltip's colors, Blizzard's where it has them.
local RED = RED_FONT_COLOR and { RED_FONT_COLOR:GetRGB() } or { 1, 0.1, 0.1 }
local GOLD = NORMAL_FONT_COLOR and { NORMAL_FONT_COLOR:GetRGB() } or { 1, 0.82, 0 }
local GREEN = { 0.1, 1, 0.1 } -- Blizzard's hint green
local WHITE = { 1, 1, 1 }
local GRAY = Colors.GRAY
local GOLD_CODE = Colors.Code(GOLD[1], GOLD[2], GOLD[3])

local module = ns.NewModule("MinimapButton", L.MINIMAPBUTTON_DESC, {
    enabled = true,
    where = "minimap", -- minimap, compartment, or both
    swapClicks = true, -- the quick toggles on a click and settings on a right-click
    keysLeftClick = true, -- with Swap Clicks, the error keys stay on a click
    menuSide = "auto", -- the quick toggles at the cursor as Blizzard opens them, or left or right
    menuOrder = "groups", -- the quick toggles by what you're doing, by category, or A to Z
    -- Keys held with a click, while Error Catcher is on.
    errorsKey = "shift", -- shows the errors
    clearModifier = "ctrl", -- clears this session's errors
    clearAllKey = "alt", -- clears every saved error, after asking
    -- Data, not settings: a table, so presets leave it alone.
    saved = {
        angle = 200, -- the button's place around the minimap, in degrees, until it's dragged
        -- x, y: where it was dragged to, from the minimap's middle, in its pixels
    },
    -- Module name -> true (the player added it to the quick toggles) or false (took it out).
    quickToggles = {},
})
module.title = L.MINIMAPBUTTON_TITLE
module.category = "system"
module.developer = { options = { menuSide = "left" } }
module.added = "0.8.0"

-- Before 0.8.0 the button was Error Catcher's, with its Minimap Button checkbox, Clear Key, and the
-- button's place. A player who had turned that button off keeps it off the minimap.
ns.Migrate(1, function(db)
    local saved = db.modules or {}
    local old = saved.ErrorCatcher
    if not (old and (old.minimap ~= nil or old.clearModifier ~= nil)) then
        return
    end
    local db = saved.MinimapButton or {}
    saved.MinimapButton = db
    ns.MoveSettings(old, db, { "clearModifier" })
    if old.minimap == false then
        db.where = "compartment"
    end
    if type(old.saved) == "table" and old.saved.angle then
        db.saved = db.saved or {}
        db.saved.angle = old.saved.angle
        old.saved.angle = nil
    end
    old.minimap, old.clearModifier = nil, nil
end)

local button
local compartment -- our entry in the addon compartment, while it's there

-- What a click does with a key held, while Error Catcher is on: the first whose key is held wins,
-- so showing the errors beats clearing them when two share a key.
local KEY_ACTIONS = {
    { setting = "errorsKey", hint = L.MINIMAPBUTTON_HINT_ERRORS,
        run = function() Errors.Toggle() end },
    { setting = "clearModifier", hint = L.MINIMAPBUTTON_HINT_CLEAR,
        run = function() Errors.ClearSession() end },
    { setting = "clearAllKey", hint = L.MINIMAPBUTTON_HINT_CLEAR_ALL,
        run = function() Errors.ClearAll() end },
}

-- A key's name for the tooltip, such as Ctrl, from the dropdown's choices.
local KEY_NAMES = {}
for _, choice in ipairs(Keys.CHOICES) do
    KEY_NAMES[choice[1]] = choice[2]
end

-- The modules the quick toggles menu turns on and off, grouped by what you're doing rather than
-- by the Modules page's categories, where nearly all of them are Automation. A module joins a
-- group by saying so in its own file: `module.quickToggle = "loot"`, one of the keys below. Each
-- group lists its modules by title in alphabetical order, so the order holds in every language.
-- One that isn't available on this client (Hide Beta Feedback off the beta) is left out, and so
-- is a group left empty.
-- The player picks more or fewer in the menu's Customize submenu (`quickToggles`); a module they
-- add that has no group of its own shows under its Modules page category, after these groups and
-- before Other.
local QUICK_GROUPS = {
    { L.MINIMAPBUTTON_GROUP_LOOT, key = "loot" },
    { L.MINIMAPBUTTON_GROUP_NPCS, key = "npcs" },
    { L.MINIMAPBUTTON_GROUP_WORLD, key = "world" },
    { L.MINIMAPBUTTON_GROUP_NAMEPLATES, key = "nameplates" },
    -- Then, while Gathering Map is on, the kinds it shows (its Kinds, through ns.Providers).
    { L.MINIMAPBUTTON_GROUP_GATHERING, key = "gathering", kinds = true },
    { L.MINIMAPBUTTON_GROUP_OTHER, key = "other" },
}
local QUICK_KEYS = {}
for _, group in ipairs(QUICK_GROUPS) do
    QUICK_KEYS[group.key] = true
end

local Kit = ns.SettingsKit
local GROUP_COLOR = Colors.Code(GRAY[1], GRAY[2], GRAY[3])
-- A Customize category with more modules than this scrolls, since submenus don't fit themselves
-- to the screen. Menu rows are 20 high (MenuTemplates).
local MAX_ROWS, ROW_HEIGHT = 18, 20

local function byTitle(a, b)
    return a.title < b.title
end

-- Whether a module can be offered at all: one with a checkbox, that this client has. A locked one
-- (the game broke it) can't be turned on, so it isn't offered.
local function offerable(other)
    return other and not other.alwaysOn and not other.unavailable and not other.locked
end

-- The group a module joined in its own file, if it's one of ours.
local function defaultGroup(other)
    return QUICK_KEYS[other.quickToggle] and other.quickToggle or nil
end

-- Whether the menu offers a module: the player's pick, or else whether it joined a group.
local function isQuick(name, other)
    local picked = module.db.quickToggles[name]
    if picked ~= nil then
        return picked and true or false
    end
    return defaultGroup(other) ~= nil
end

-- Saves only a pick that differs from the module's own default, so a later default reaches it.
local function setQuick(name, other, on)
    local picked = nil
    if on ~= (defaultGroup(other) ~= nil) then
        picked = on
    end
    module.db.quickToggles[name] = picked
end

-- The modules the menu offers, by group key: a quick group's, or the category of one added
-- without a group (`added[category]`). Each list sorted by title.
local function quickLists()
    local groups, added = {}, {}
    for _, name in ipairs(ns.order) do
        local other = ns.modules[name]
        if offerable(other) and isQuick(name, other) then
            local key, lists = defaultGroup(other), groups
            if not key then
                -- An added module of no category goes under our own Other, not a second one.
                key = Kit.CategoryOf(other)
                lists = key == "other" and groups or added
            end
            local list = lists[key] or {}
            lists[key] = list
            list[#list + 1] = { name = name, module = other, title = other.title or name }
        end
    end
    for _, lists in ipairs({ groups, added }) do
        for _, list in pairs(lists) do
            sort(list, byTitle)
        end
    end
    return groups, added
end

-- Turned on and off through Core, as the Modules page does, so Settings and /fpp follow along.
local function addGroup(root, label, entries)
    if not (entries and #entries > 0) then
        return false
    end
    if label then
        root:CreateTitle(GROUP_COLOR .. label .. "|r")
    end
    for _, entry in ipairs(entries) do
        local name, other = entry.name, entry.module
        root:CreateCheckbox(entry.title,
            function() return other.db.enabled end,
            function()
                ns.SetEnabled(name, not other.db.enabled) -- Settings follows by itself
            end)
    end
    return true
end

-- Gathering Map's kinds after its group's modules, while it's on to offer them.
local function addKinds(root)
    local gathering = ns.Providers.Get("gatheringNodes")
    local kinds = gathering and gathering.Kinds and gathering.Kinds() or {}
    if #kinds > 0 then
        root:CreateTitle(GROUP_COLOR .. L.MINIMAPBUTTON_GATHERING_SHOWS .. "|r")
        for _, kind in ipairs(kinds) do
            root:CreateCheckbox(kind.name, kind.IsShown, function()
                kind.Toggle()
                ns.RefreshSetting("GatheringMap")
            end)
        end
    end
end

-- A module's title and description, as the Modules page shows them, on its Customize checkbox.
local function moduleTooltip(entry)
    local other = entry.module
    return function(tooltip)
        tooltip:SetText(entry.title, 1, 1, 1)
        if type(other.description) == "string" and other.description ~= "" then
            tooltip:AddLine(other.description, GOLD[1], GOLD[2], GOLD[3], true)
        end
    end
end

-- Customize, from the button in the module's settings: a submenu per Modules page category, each
-- with a checkbox per module for whether the quick toggles offer it. It isn't in the quick toggles
-- menu itself, since an open menu only redraws its checks, never adds or drops rows
-- (MenuResponse.Refresh is ReinitializeAll in Blizzard_Menu's Menu.lua), so a pick there wouldn't
-- show until it opened again.
local function customizeItems(_, root)
    root:CreateTitle(L.MINIMAPBUTTON_CUSTOMIZE_NAME)
    local byCategory = {}
    for _, name in ipairs(ns.order) do
        local other = ns.modules[name]
        if offerable(other) then
            local key = Kit.CategoryOf(other)
            local list = byCategory[key] or {}
            byCategory[key] = list
            list[#list + 1] = { name = name, module = other, title = other.title or name }
        end
    end
    for _, category in ipairs(Kit.CATEGORIES) do
        local entries = byCategory[category[1]]
        if entries then
            sort(entries, byTitle)
            local sub = root:CreateButton(category[2])
            if #entries > MAX_ROWS and sub.SetScrollMode then
                sub:SetScrollMode(MAX_ROWS * ROW_HEIGHT)
            end
            for _, entry in ipairs(entries) do
                local name, other = entry.name, entry.module
                local box = sub:CreateCheckbox(entry.title,
                    function() return isQuick(name, other) end,
                    function() setQuick(name, other, not isQuick(name, other)) end)
                if box.SetTooltip then
                    box:SetTooltip(moduleTooltip(entry))
                end
            end
        end
    end
    root:CreateDivider()
    local reset = root:CreateButton(L.MINIMAPBUTTON_CUSTOMIZE_RESET, function()
        wipe(module.db.quickToggles)
        return MenuResponse and MenuResponse.Refresh
    end)
    if reset.SetEnabled then
        reset:SetEnabled(function() return next(module.db.quickToggles) ~= nil end)
    end
end

-- Menu Order's Category and A to Z: every module the menu offers by its Modules page category
-- (`byCategory`) or in one list, each sorted by title.
local function offeredLists(byCategory)
    local lists = {}
    for _, name in ipairs(ns.order) do
        local other = ns.modules[name]
        if offerable(other) and isQuick(name, other) then
            local key = byCategory and Kit.CategoryOf(other) or "all"
            local list = lists[key] or {}
            lists[key] = list
            list[#list + 1] = { name = name, module = other, title = other.title or name }
        end
    end
    for _, list in pairs(lists) do
        sort(list, byTitle)
    end
    return lists
end

local function quickMenuItems(_, root)
    root:CreateTitle(ns.title)
    local order = module.db.menuOrder
    if order == "category" then
        local lists = offeredLists(true)
        for _, category in ipairs(Kit.CATEGORIES) do
            addGroup(root, category[2], lists[category[1]])
        end
        addKinds(root)
    elseif order == "title" then
        addGroup(root, nil, offeredLists(false).all)
        addKinds(root)
    else
        local groups, added = quickLists()
        for _, group in ipairs(QUICK_GROUPS) do
            if group.key == "other" then
                -- The categories of modules the player added, before Other.
                for _, category in ipairs(Kit.CATEGORIES) do
                    addGroup(root, category[2], added[category[1]])
                end
            end
            if addGroup(root, group[1], groups[group.key]) and group.kinds then
                addKinds(root)
            end
        end
    end
    root:CreateDivider()
    local customize = root:CreateButton(L.MINIMAPBUTTON_CUSTOMIZE_OPEN, function()
        ns.OpenSettings(module.name)
    end)
    if customize.SetTooltip then
        customize:SetTooltip(function(tooltip)
            tooltip:SetText(L.MINIMAPBUTTON_CUSTOMIZE_NAME, 1, 1, 1)
            tooltip:AddLine(L.MINIMAPBUTTON_CUSTOMIZE_OPEN_DESC, GOLD[1], GOLD[2], GOLD[3], true)
        end)
    end
end

-- The Customize button's menu, at the cursor, owned by the button so it closes with Settings.
local function openCustomize()
    if MenuUtil and MenuUtil.CreateContextMenu then
        local owner = GetMouseFoci and GetMouseFoci()[1]
        MenuUtil.CreateContextMenu(owner or UIParent, customizeItems)
    end
end

-- Menu Side's anchor: a corner of the menu on the cursor, the right one for Left and the left one
-- for Right, and a bottom corner in the bottom half of the screen so it grows up from there. As
-- Blizzard's InputUtil.AnchorRegionToCursor does, with its fix for letterboxing.
local function menuAnchor(side)
    local parent = GetAppropriateTopLevelParent()
    local x, y = InputUtil.GetCursorPosition(parent)
    local _, _, _, left = parent:GetPointByName("TOPLEFT")
    if left then
        x = x - left
    end
    local corner = (y < parent:GetHeight() / 2 and "BOTTOM" or "TOP")
        .. (side == "left" and "RIGHT" or "LEFT")
    return AnchorUtil.CreateAnchor(corner, parent, "BOTTOMLEFT", x, y)
end

-- Auto is Blizzard's context menu: its top-left corner at the cursor, flipped up at the bottom of
-- the screen and pushed back on at the right. Left and Right put the corner they name there
-- instead, through Blizzard_Menu's own OpenMenu (Gethe's `forever` branch, 2026-10-16).
local function quickMenu(owner)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        return
    end
    local side = module.db.menuSide
    if side ~= "auto" and Menu and Menu.GetManager and Menu.PopulateDescription
        and MenuUtil.CreateRootMenuDescription and MenuVariants and AnchorUtil and InputUtil
        and GetAppropriateTopLevelParent then
        local root = MenuUtil.CreateRootMenuDescription(MenuVariants.GetDefaultContextMenuMixin())
        Menu.PopulateDescription(quickMenuItems, owner, root)
        if Menu.GetManager():OpenMenu(owner, root, menuAnchor(side)) then
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        end
        return
    end
    MenuUtil.CreateContextMenu(owner, quickMenuItems)
end

-- Which mouse button opens the quick toggles: the right one, or the left with Swap Clicks.
local function menuButton()
    return module.db.swapClicks and "LeftButton" or "RightButton"
end

-- Which mouse button the error keys go with: the settings click, or the left one with Error
-- Keys on Left-Click.
local function keyButton()
    local db = module.db
    return (db.swapClicks and not db.keysLeftClick) and "RightButton" or "LeftButton"
end

local function onClick(owner, mouse)
    if mouse == keyButton() and Errors.IsOn() then
        -- Clearing needs a key held, so it's never an accident.
        for _, action in ipairs(KEY_ACTIONS) do
            if Keys.IsDown(module.db[action.setting]) then
                action.run()
                return
            end
        end
    end
    if mouse == menuButton() then
        quickMenu(owner)
        return
    end
    if not (ns.WelcomePending() and ns.OpenAbout()) then
        ns.OpenSettings()
    end
end

-- A count row: a white label, and the count at the right in `color`, or a gray None at 0.
local function addCount(label, count, color)
    if count > 0 then
        GameTooltip:AddDoubleLine(label, count, 1, 1, 1, color[1], color[2], color[3])
    else
        GameTooltip:AddDoubleLine(label, L.MINIMAPBUTTON_TIP_NONE, 1, 1, 1, GRAY[1], GRAY[2], GRAY[3])
    end
end

-- A hint row: what it does, and the click for it in green, as Blizzard's own hints. The main
-- clicks are white; `minor` ones (errors, moving the button) are gray, so the main ones stand out.
local function addHint(action, click, minor)
    local color = minor and GRAY or WHITE
    GameTooltip:AddDoubleLine(action, click, color[1], color[2], color[3], GREEN[1], GREEN[2],
        GREEN[3])
end

-- The tooltip: the version, the error counts, then a hint for each click. `drag` adds the hint
-- about dragging, which only the minimap button does.
local function showTooltip(owner, drag)
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:AddDoubleLine(ns.title, ns.version, GOLD[1], GOLD[2], GOLD[3], GRAY[1], GRAY[2],
        GRAY[3])
    local errors = Errors.IsOn()
    if errors then
        addCount(L.MINIMAPBUTTON_TIP_SESSION, Errors.SessionCount(), RED)
        addCount(L.MINIMAPBUTTON_TIP_SAVED, Errors.SavedCount(), GOLD)
        GameTooltip:AddLine(" ")
    end
    -- The settings click and the quick toggles click, as Swap Clicks has them.
    local swapped = module.db.swapClicks
    local settingsClick = swapped and L.MINIMAPBUTTON_RIGHT_CLICK or L.MINIMAPBUTTON_LEFT_CLICK
    local keyClick = keyButton() == "RightButton" and L.MINIMAPBUTTON_KEY_RIGHT_CLICK
        or L.MINIMAPBUTTON_KEY_LEFT_CLICK
    addHint(ns.WelcomePending() and L.MINIMAPBUTTON_HINT_WELCOME or L.MINIMAPBUTTON_HINT_SETTINGS,
        settingsClick)
    addHint(L.MINIMAPBUTTON_HINT_TOGGLES, swapped and L.MINIMAPBUTTON_LEFT_CLICK or L.MINIMAPBUTTON_RIGHT_CLICK)
    if errors then
        for _, action in ipairs(KEY_ACTIONS) do
            local key = module.db[action.setting]
            if key ~= "none" and KEY_NAMES[key] then
                -- The key in gold; |r goes back to the line's green.
                addHint(action.hint, format(keyClick, GOLD_CODE .. KEY_NAMES[key] .. "|r"), true)
            end
        end
    end
    if drag then
        addHint(L.MINIMAPBUTTON_HINT_MOVE, L.MINIMAPBUTTON_LEFT_DRAG, true)
    end
    GameTooltip:Show()
end

-- This session's error count on the button and in the compartment's text, while Error Catcher
-- is on and has caught any.
local function refresh()
    local count = Errors.SessionCount()
    if compartment then
        -- Read when the compartment's menu opens, so it shows the count from then on.
        compartment.text = count > 0 and format(L.MINIMAPBUTTON_COMPARTMENT_COUNT, ns.title, count)
            or ns.title
    end
    if button then
        button.count:SetText(count > 0 and count or "")
        -- Blizzard's NEW label, as on new things in its own menus, until the About page is seen.
        local new = ns.WelcomePending()
        if new and not button.new and ns.Frames.HasTemplate("NewFeatureLabelTemplate") then
            button.new = CreateFrame("Frame", nil, button, "NewFeatureLabelTemplate")
            button.new:SetPoint("CENTER", button, "TOP", 0, -2)
        end
        if button.new then
            button.new:SetShown(new)
        end
    end
end

-- The minimap button ----------------------------------------------------------------------------

local REACH = 40 -- how far past the minimap's edge a drag can take the button, in its pixels

-- Where the player dragged it (`saved.x`, `saved.y`, from the minimap's middle), or until they
-- have, around the minimap's edge at the saved angle, its middle 10 past it: on a circle, or on a
-- square while the minimap is square (Lib/MinimapPins.lua), so it stays on the edge in a corner.
local function place()
    local saved = module.db.saved
    local x, y
    if saved.x and saved.y then
        x, y = saved.x, saved.y
    else
        local angle = rad(saved.angle or 200)
        local radius = Minimap:GetWidth() / 2 + 10
        x, y = cos(angle), sin(angle)
        if ns.MinimapPins.Square() then
            local far = max(abs(x), abs(y))
            x, y = x / far, y / far
        end
        x, y = x * radius, y * radius
    end
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- The cursor, from the minimap's middle, in its pixels.
local function cursorOnMap()
    local x, y = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    return cx / scale - x, cy / scale - y
end

local grabX, grabY -- the cursor's offset from the button's middle when the drag began

local function clamp(v, limit)
    return v < -limit and -limit or v > limit and limit or v
end

-- While dragging: the button goes wherever the cursor takes it, on or around the minimap, keeping
-- the spot it was picked up by under the cursor (like the day and night indicator's drag).
local function follow()
    local x, y = cursorOnMap()
    local limit = Minimap:GetWidth() / 2 + REACH
    local saved = module.db.saved
    saved.x = floor(clamp(x - grabX, limit) + 0.5)
    saved.y = floor(clamp(y - grabY, limit) + 0.5)
    place()
end

local function startDrag(self)
    GameTooltip_Hide()
    local x, y = cursorOnMap()
    local bx, by = self:GetCenter()
    local mx, my = Minimap:GetCenter()
    local ratio = self:GetEffectiveScale() / Minimap:GetEffectiveScale()
    grabX, grabY = x - (bx * ratio - mx), y - (by * ratio - my)
    self:SetScript("OnUpdate", follow)
end

---Puts the button back on the minimap's edge, where it starts.
local function resetPlace()
    local saved = module.db.saved
    saved.x, saved.y, saved.angle = nil, nil, nil
    if button and button:IsShown() then
        place()
    end
end

local function onEnter(self)
    showTooltip(self, true)
end

-- The usual round minimap button: Blizzard's tracking border around a small icon, laid out as
-- LibDBIcon does on Mainline clients like Forever's (the Classic offsets sit up and to the left).
local function newMinimapButton()
    local b = CreateFrame("Button", nil, Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local background = b:CreateTexture(nil, "BACKGROUND")
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetSize(24, 24)
    background:SetPoint("CENTER")
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ns.icon)
    icon:SetSize(18, 18)
    icon:SetPoint("CENTER")
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(50, 50)
    border:SetPoint("TOPLEFT")
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", 2, 1)

    b:SetScript("OnClick", onClick)
    b:SetScript("OnDragStart", startDrag)
    b:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    b:SetScript("OnEnter", onEnter)
    b:SetScript("OnLeave", GameTooltip_Hide)
    return b
end

-- The addon compartment ---------------------------------------------------------------------------
-- The menu under the minimap that lists addons. Forever has it (Manners, an addon for this
-- client, registers there the same way). Registered here rather than with the TOC's
-- AddonCompartmentFunc, so it can come and go with the option.

local function compartmentFrame()
    local frame = AddonCompartmentFrame
    if frame and frame.RegisterAddon then
        return frame
    end
end

local function addCompartment()
    local frame = compartmentFrame()
    if compartment or not frame then
        return
    end
    compartment = {
        text = ns.title,
        icon = ns.icon,
        notCheckable = true,
        registerForAnyClick = true,
        -- The mouse button comes inside the input data; the TOC's way passes it as a string.
        func = function(_, input)
            onClick(frame, type(input) == "table" and input.buttonName or input)
        end,
        funcOnEnter = function(owner)
            showTooltip(type(owner) == "table" and owner.IsObjectType and owner or frame, false)
        end,
        funcOnLeave = GameTooltip_Hide,
    }
    refresh()
    frame:RegisterAddon(compartment)
end

-- Blizzard has no way to unregister, so ours comes out of its list, as LibDBIcon does, and the
-- compartment redraws. The list holds only addons' entries, so this touches nothing secure.
local function removeCompartment()
    local frame = compartmentFrame()
    local entries = frame and frame.registeredAddons
    if compartment and entries then
        for i = #entries, 1, -1 do
            if entries[i] == compartment then
                tremove(entries, i)
            end
        end
        if frame.UpdateDisplay then
            frame:UpdateDisplay()
        end
    end
    compartment = nil
end

-- Shows the minimap button and the compartment entry the option asks for, and only those.
local function update()
    local where = module.enabled and module.db.where or "none"
    if (where == "minimap" or where == "both") and Minimap then
        button = button or newMinimapButton()
        place()
        button:Show()
    elseif button then
        button:SetScript("OnUpdate", nil)
        button:Hide()
    end
    if where == "compartment" or where == "both" then
        addCompartment()
    else
        removeCompartment()
    end
    refresh()
end

-- The module ----------------------------------------------------------------------------------

module.options = {
    {
        key = "where",
        name = L.MINIMAPBUTTON_WHERE,
        description = L.MINIMAPBUTTON_WHERE_DESC,
        choices = {
            { "minimap", L.MINIMAPBUTTON_WHERE_MINIMAP },
            { "compartment", L.MINIMAPBUTTON_WHERE_COMPARTMENT },
            { "both", L.MINIMAPBUTTON_WHERE_BOTH },
        },
    },
    {
        key = "swapClicks",
        name = L.MINIMAPBUTTON_SWAP,
        description = L.MINIMAPBUTTON_SWAP_DESC,
        added = "1.0.0-beta.1",
    },
    {
        key = "keysLeftClick",
        name = L.MINIMAPBUTTON_KEYS_LEFT,
        description = L.MINIMAPBUTTON_KEYS_LEFT_DESC,
        requires = "swapClicks",
        added = "1.0.0-beta.1",
    },
    {
        key = "menuSide",
        name = L.MINIMAPBUTTON_MENU_SIDE,
        description = L.MINIMAPBUTTON_MENU_SIDE_DESC,
        choices = {
            { "auto", L.MINIMAPBUTTON_MENU_SIDE_AUTO },
            { "left", L.MINIMAPBUTTON_MENU_SIDE_LEFT },
            { "right", L.MINIMAPBUTTON_MENU_SIDE_RIGHT },
        },
        added = "1.0.0-beta.1",
    },
    {
        key = "menuOrder",
        name = L.MINIMAPBUTTON_MENU_ORDER,
        description = L.MINIMAPBUTTON_MENU_ORDER_DESC,
        choices = {
            { "groups", L.MINIMAPBUTTON_MENU_ORDER_GROUPS },
            { "category", L.MINIMAPBUTTON_MENU_ORDER_CATEGORY },
            { "title", L.MINIMAPBUTTON_MENU_ORDER_TITLE },
        },
        added = "1.4.0",
    },
    Keys.Option("errorsKey", L.MINIMAPBUTTON_ERRORS_KEY, L.MINIMAPBUTTON_ERRORS_KEY_DESC),
    -- Changed: a click instead of a right-click, and Shift is a choice.
    Keys.Option("clearModifier", L.MINIMAPBUTTON_CLEAR_KEY, L.MINIMAPBUTTON_CLEAR_KEY_DESC, nil,
        "0.9.0"),
    Keys.Option("clearAllKey", L.MINIMAPBUTTON_CLEAR_ALL_KEY, L.MINIMAPBUTTON_CLEAR_ALL_KEY_DESC),
}
module.actions = {
    {
        name = L.MINIMAPBUTTON_CUSTOMIZE_NAME,
        button = L.MINIMAPBUTTON_CUSTOMIZE,
        description = L.MINIMAPBUTTON_CUSTOMIZE_DESC,
        fn = openCustomize,
    },
    {
        name = L.MINIMAPBUTTON_PLACE_NAME,
        button = L.MINIMAPBUTTON_PLACE_RESET,
        description = L.MINIMAPBUTTON_PLACE_RESET_DESC,
        fn = resetPlace,
    },
}

for _, option in ipairs(module.options) do
    if option.key == "errorsKey" or option.key == "clearAllKey" then
        option.added = "0.9.0"
    end
end

local function onChanged()
    if module.enabled then
        refresh()
    end
end
Errors.OnChanged(onChanged)
ns.OnWelcomed(onChanged)

-- The minimap turned square or round: onto its new edge.
local function onShapeChanged()
    if button and button:IsShown() then
        place()
    end
end

function module:OnEnable()
    ns.MinimapPins.OnShapeChanged(onShapeChanged, true)
    update()
end

function module:OnDisable()
    ns.MinimapPins.OnShapeChanged(onShapeChanged, false)
    update()
end

function module:OnOptionChanged(key)
    if key == "where" then
        update()
    end
end

-- The Screenshots tool's picture: the button's tooltip as hovering it shows it.
module.screenshot = {
    id = "minimap",
    name = L.SCREENSHOTS_SCENE_MINIMAP,
    modules = { MinimapButton = { where = "minimap" } },
    open = function()
        if not (module.enabled and button and button:IsShown()) then
            return L.SCREENSHOTS_NO_BUTTON
        end
        showTooltip(button, true)
    end,
    isShown = function() return GameTooltip:IsVisible() and true or false end,
    close = function() GameTooltip:Hide() end,
}
