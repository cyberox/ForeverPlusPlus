-- The "Forever++" pages in the game's Settings > AddOns list, built from Blizzard's own settings
-- templates so they look like any other options page. Few entries, so the sidebar stays short:
--   Forever++        the Modules page: every module (the only place modules turn on and off) in
--                    a list on the left, with a checkbox each, under a label per
--                    `module.category`. Clicking one shows it on the right: its title, category
--                    and description, its Enabled checkbox, its `notice` (a warning) while that
--                    applies, then its options (checkboxes, dropdowns and sliders) and buttons
--                    (from `module.actions`), greyed out while it's off. An option can sit under
--                    another (`requires`), and is greyed out while its `available()` is false. A module made of parts (`module:NewPart`) has a
--                    section for each, headed by the part's Enabled checkbox (a part turned on
--                    by a dropdown is that one row), with the part's options greyed out while
--                    it's off.
--                    `alwaysOn` modules (tools) aren't listed. A search box at the top narrows
--                    the list to modules by title and description, or by an option's name or
--                    description, and highlights those options; a New checkbox beside it lists
--                    only modules marked NEW. A module or option added since the player last
--                    looked (`added`), or an option changed since then (`changed`), is marked NEW.
--                    The Debug module shows, under its Enabled checkbox, the rows Debug.lua adds:
--                    sections of Forever++'s own buttons and modules' options marked
--                    `debug = true` and buttons from `module.debugActions`, each placed by its
--                    `section`: What's New (Reset Seen Version, Reset Welcome), Diagnostics (Copy
--                    Debug Info, Print Module Events, Reload UI), Testing, and Logging
--     <Tool>         a page a module draws itself (`BuildPage`)
--     Changelog      the releases in Changelog.lua in a list like the Modules page's, with the
--                    selected one's notes beside it, and a By Module checkbox, a search box and
--                    the Defaults button at the top like Modules
--     About          what the addon is, how many modules are on, the version, links, and the /fpp
--                    commands, with the Defaults button at the top right like Modules
-- Without subpages (an older Settings API), the Modules page is the only page.
-- This file has the Modules page and what the pages share; Changelog.lua and About.lua draw the
-- others, and Debug.lua the Debug module's rows, through `S` (ns.SettingsUI). The pieces a drawn
-- page is made of are in Lib/SettingsKit.lua.
local _, ns = ...

local ipairs, pairs, next, format, type, sort = ipairs, pairs, next, string.format, type, table.sort
local strlower, concat = string.lower, table.concat
local min, max, pcall, tostring = math.min, math.max, pcall, tostring
local InCombatLockdown, CreateFrame = InCombatLockdown, CreateFrame
local wipe = wipe
local C_Timer = C_Timer
local L = ns.L
local hasTemplate = ns.Frames.HasTemplate
local Kit = ns.SettingsKit
local showTooltip, addTooltip = Kit.ShowTooltip, Kit.AddTooltip
local newCheckbox, newButton = Kit.NewCheckbox, Kit.NewButton
local newStack, addEntry, layoutStack = Kit.NewStack, Kit.AddEntry, Kit.Layout
local newSplit, paint, hover = Kit.NewSplit, Kit.Paint, Kit.Hover
local newListButton, newEmptyRow, addSearchBox = Kit.NewListButton, Kit.NewEmptyRow, Kit.AddSearchBox

-- What the Settings files share. Debug.lua, Changelog.lua and About.lua load after this one and add
-- the functions that draw their parts (S.AddDebugRows, S.BuildChangelog, S.BuildAbout).
local S = {}
ns.SettingsUI = S

local modulesCategory -- the Modules page, the top Forever++ entry, for /fpp
local pages = {} -- module name -> the page it draws itself, for ns.OpenSettings(name)
local pageOrder = {} -- the modules with a page of their own, in sidebar order
local aboutCategory -- the About page, for ns.OpenAbout

-- Opens a Forever++ page (after combat, if the player is in combat).
local function open(category)
    if not (category and Settings.OpenToCategory and category.GetID) then
        return false
    end
    if InCombatLockdown() then
        ns.Print(L.SETTINGS_AFTER_COMBAT)
    end
    ns.AfterCombat(function()
        -- Through the client when it can: it opens the panel from its own event, so Blizzard's
        -- pages (and the pooled rows they share) aren't set up while our code is running, which
        -- taints them (the Nameplates preview and Discord buttons then error).
        if C_SettingsUtil and C_SettingsUtil.OpenSettingsPanel then
            C_SettingsUtil.OpenSettingsPanel(category:GetID())
        else
            Settings.OpenToCategory(category:GetID())
        end
    end)
    return true
end

-- A frame for a page drawn by `build(frame)` instead of from settings, such as a list. Settings
-- needs the frame now, so it starts empty and is filled the first time it's shown. It starts
-- hidden: a new frame is shown, and Settings showing a frame that already is doesn't fire OnShow,
-- which would leave the page empty until the player left it and came back.
local function canvasFrame(build)
    local frame = CreateFrame("Frame")
    frame:Hide()
    local built = false
    frame:SetScript("OnShow", function(self)
        if not built then
            built = true
            build(self)
        end
    end)
    return frame
end

local function addCanvasPage(category, name, build)
    return Settings.RegisterCanvasLayoutSubcategory(category, canvasFrame(build), name)
end

-- Whether a module's own page is in the sidebar: always for a tool, and only while it's on for a
-- module the player turns on and off.
local function pageShown(name)
    local module = ns.modules[name]
    return module.alwaysOn or module.enabled
end

-- Puts a module's page in the sidebar or takes it out, as the module turns on and off. Settings has
-- no way to hide a page, so this adds it to or removes it from the Forever++ entry's subpages (its
-- own list, which Blizzard reads when it draws the sidebar), and has the sidebar drawn again.
local function updatePage(name)
    local page = pages[name]
    local list = page and modulesCategory.GetSubcategories and modulesCategory:GetSubcategories()
    if not list then
        return
    end
    local at, index = 1, nil
    for _, other in ipairs(pageOrder) do
        if other == name then
            break
        end
        if pageShown(other) then
            at = at + 1
        end
    end
    for i, category in ipairs(list) do
        if category == page then
            index = i
        end
    end
    local want = pageShown(name)
    if want == (index ~= nil) then
        return
    end
    if want then
        table.insert(list, at, page)
    else
        table.remove(list, index)
    end
    local categoryList = SettingsPanel and SettingsPanel.GetCategoryList and SettingsPanel:GetCategoryList()
    if categoryList and categoryList.CreateCategories then
        categoryList:CreateCategories()
    end
end

-- Our Defaults popup, laid out like Blizzard's, that offers only Forever++'s two presets:
-- Developer's Defaults | Cancel | Recommended Defaults.
local function askDefaults()
    ns.ConfirmChoice("DEFAULTS_CHOICE", L.DEFAULTS_ASK, L.DEFAULTS_DEVELOPER,
        ns.ApplyDeveloperDefaults, L.DEFAULTS_RECOMMENDED, function() ns.ApplyPreset() end)
end
S.askDefaults = askDefaults

-- NEW labels ----------------------------------------------------------------------------------
-- A module added (`added`) after the version the player last saw it in gets Blizzard's NEW label
-- after its name, the one Blizzard's own new settings get. So does an option added or changed
-- (`changed`) since then, unless its module is new itself (a longer word like CHANGED squeezes the
-- option's name), and the module's name in the list with it.
-- A module is seen once the player has clicked it and moved on (to another module, or off the
-- page): its labels stay while it shows. The page opens on the first module with a marked option.
-- What's saved stays small: the version everything was seen in (ns.db.seenVersion), and the version
-- each module was seen in since (ns.db.seenModules), dropped once nothing seen can be marked.
-- What's tagged after the last release in Changelog.lua isn't released yet, so only a development
-- copy has it: it stays marked whatever was seen, so everything added since the release shows.
local newRows = {} -- module name (a new module), module table (one with a marked option), or
                   -- option table -> true while it's marked
local newOrder -- the modules to mark, once trackNew has run
local selected -- the module shown on the right of the Modules page
local viewing -- the module the player is looking at, to call seen once they move on
local refreshAll -- redraws the Modules page (defined with it, below)

-- Probe: NewFeatureLabelTemplate is Mainline's (LibUIDropDownMenu uses it on Forever).
local function canLabel()
    return hasTemplate("NewFeatureLabelTemplate")
end

-- The newest version in Changelog.lua with a date, so released, and older than `before` if given.
local function lastRelease(before)
    for _, release in ipairs(ns.changelog or {}) do
        if release.date and (not before or ns.Text.NewerVersion(before, release.version)) then
            return release.version
        end
    end
    return "0"
end

-- Whether `version` is after the last release, so not released yet.
local function unreleased(version)
    return type(version) == "string" and ns.Text.NewerVersion(version, lastRelease()) and true
        or false
end

-- A version after the one module `name` was last seen in, and not after this one, or one not
-- released yet.
local function since(version, name)
    local Text = ns.Text
    if type(version) ~= "string" then
        return false
    end
    if unreleased(version) then
        return true
    end
    local seenIn = ns.db.seenVersion
    local module = ns.db.seenModules[name]
    if type(module) == "string" and Text.NewerVersion(module, seenIn) then
        seenIn = module
    end
    return Text.NewerVersion(version, seenIn) and not Text.NewerVersion(version, ns.version)
        and true or false
end

local TAG_GAP = 6 -- between a text's end and its label
local TAG_PADDING = 8 -- the room a label takes after its text, besides its own text

-- A function that shows a NEW label just after `text`, a font string, or hides it: the text at most
-- `room` wide, less the label's room while it shows. With `after` (an option's checkbox), the label
-- goes just after that instead, so the text keeps its room and the labels line up beside their
-- checkboxes. It returns how far past the text's end the label reaches (0 while hidden or
-- after `after`), for something after it. The label is made the first time it's needed.
local function newLabel(parent, text, room, after)
    local label
    return function(shown)
        if shown and not label and canLabel() then
            label = CreateFrame("Frame", nil, parent, "NewFeatureLabelTemplate")
        end
        local tag = 0
        if shown and label and label.Label then
            tag = ns.Text.Width(label.Label) -- Blizzard's own NEW, in the game's language
        elseif shown then
            tag = 26
        end
        local full = ns.Text.Width(text)
        local beside = shown and after
        local inline = shown and not beside
        text:SetWidth(min(full + 2, room - (inline and tag + TAG_PADDING or 0)))
        if label then
            -- Half the label's text past where it starts: the template centers its text on the
            -- frame. On the text's line, it starts after the text, or where it's cut short.
            label:ClearAllPoints()
            if beside then
                label:SetPoint("CENTER", after, "RIGHT", TAG_GAP + tag / 2, 0)
            else
                local width = min(full, text:GetWidth())
                label:SetPoint("CENTER", text, "LEFT", width + TAG_GAP + tag / 2, 0)
            end
            label:SetShown(shown and true or false)
        end
        return inline and TAG_GAP + tag or 0
    end
end
S.newLabel = newLabel

-- An update that keeps a NEW label just after `text` while `key` (a module's name, or one of its
-- options) is marked, or `other` (the slider in an option's row, or the module in the list). With
-- `after`, as newLabel.
local function newMark(parent, text, room, key, other, after)
    local show = newLabel(parent, text, room, after)
    return function()
        show(newRows[key] or (other and newRows[other]))
    end
end

-- Marks what's new in `newOrder`'s modules, afresh. With nothing marked but what's unreleased,
-- everything up to this version has been seen, so that's saved instead of each module.
local function markNew()
    wipe(newRows)
    local unseen -- something marked that seeing it takes away
    local function mark(key, module, version, name)
        if since(version, name) then
            newRows[key] = true
            if module then
                newRows[module] = true
            end
            unseen = unseen or not unreleased(version)
            return true
        end
    end
    for _, name in ipairs(newOrder or {}) do
        local module = ns.modules[name]
        -- All of a new module is new, so its options aren't marked.
        if not mark(name, nil, module.added, name) then
            for _, option in ipairs(module.options or {}) do
                if not option.debug and not mark(option, module, option.added, name) then
                    mark(option, module, option.changed, name)
                end
            end
        end
    end
    if not unseen and newOrder then
        if ns.Text.NewerVersion(ns.version, ns.db.seenVersion) then
            ns.db.seenVersion = ns.version
        end
        wipe(ns.db.seenModules)
    end
end

-- Saves that the player has seen the module they were looking at, once they move on from it, and
-- drops its labels.
local function moveOn(name)
    local left = viewing
    viewing = name
    local module = left and left ~= name and ns.modules[left]
    if module and (newRows[left] or newRows[module]) then
        ns.db.seenModules[left] = ns.version
        markNew()
        refreshAll()
    end
end

-- Whether the Modules page is the one showing.
local function onModulesPage()
    return SettingsPanel:IsShown() and SettingsPanel:GetCurrentCategory() == modulesCategory
end

-- The module on the right is being looked at while the Modules page shows; leaving the page moves
-- on from it.
local function updateSeen()
    moveOn(onModulesPage() and selected or nil)
end

-- Probe: Settings.CategoryChanged and GetCurrentCategory are Mainline's (the `forever` UI source
-- has them); without them nothing is marked new.
local function trackNew(order)
    if not (SettingsPanel and SettingsPanel.GetCurrentCategory and EventRegistry
        and EventRegistry.RegisterCallback and canLabel()) then
        return
    end
    newOrder = order
    markNew()
    EventRegistry:RegisterCallback("Settings.CategoryChanged", updateSeen, newRows)
    SettingsPanel:HookScript("OnShow", updateSeen)
    SettingsPanel:HookScript("OnHide", updateSeen)
end

-- Options -------------------------------------------------------------------------------------
-- The pieces a module's options are drawn with.

-- A slider option's value as its label shows it: `option.format` (a format string, such as "%d%%",
-- or a function of the value, for labels like "Never" at 0), or the number.
local function sliderText(option, value)
    if type(option.format) == "function" then
        return option.format(value)
    end
    return format(option.format or "%s", value)
end

local function sliderOptions(option)
    local options = Settings.CreateSliderOptions(option.min, option.max, option.step or 1)
    if MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label then
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
            return sliderText(option, value)
        end)
    end
    return options
end

-- A module's button `action` (`{ name, button, description, fn }`, and `confirm`, a question to
-- ask before `fn` runs, with `key` naming its popup so a command can ask the same one) as the
-- function its button calls.
local function actionFn(module, action, i)
    if not action.confirm then
        return action.fn
    end
    local key = action.key or format("%s_ACTION%d", module.name:upper(), i)
    return function()
        ns.Confirm(key, action.confirm, action.fn)
    end
end
S.actionFn = actionFn

-- Module categories ---------------------------------------------------------------------------

-- The Modules page's groups: a module's `category` and its label. They show in the order their
-- labels sort in the player's language, with Other last. A module without one goes under Other.
local CATEGORIES = {
    { "automation", L.CATEGORY_AUTOMATION },
    { "character", L.CATEGORY_CHARACTER },
    { "chat", L.CATEGORY_CHAT },
    { "interface", L.CATEGORY_INTERFACE },
    { "items", L.CATEGORY_ITEMS },
    { "map", L.CATEGORY_MAP },
    { "quests", L.CATEGORY_QUESTS },
    { "system", L.CATEGORY_SYSTEM },
    { "tools", L.CATEGORY_TOOLS },
    { "units", L.CATEGORY_UNITS },
}
sort(CATEGORIES, function(a, b) return strlower(a[2]) < strlower(b[2]) end)
CATEGORIES[#CATEGORIES + 1] = { "other", L.CATEGORY_OTHER }
local CATEGORY_NAMES, CATEGORY_RANKS = {}, {} -- by `category`: its label, its place in that order
for i, group in ipairs(CATEGORIES) do
    CATEGORY_NAMES[group[1]] = group[2]
    CATEGORY_RANKS[group[1]] = i
end

local function categoryOf(module)
    return CATEGORY_NAMES[module.category] and module.category or "other"
end
S.CATEGORY_NAMES, S.CATEGORY_RANKS, S.categoryOf = CATEGORY_NAMES, CATEGORY_RANKS, categoryOf

-- Modules page --------------------------------------------------------------------------------
-- A page we draw ourselves, built the first time it's shown: under the title, a search box and
-- our Defaults button; then a compact checklist of every module on the left, grouped under small
-- gold category labels, and the selected module on the right, each side scrolling on its own.
-- Our own frames from Blizzard's templates and art (the Settings panel's minimal checkboxes,
-- sliders and dropdowns, and its sidebar highlight), so nothing of Blizzard's pooled Settings
-- rows is touched. Every change goes through ns.SetEnabled and ns.SetOption, then
-- ns.RefreshSetting, which puts that module back to what's saved wherever it shows, so /fpp and
-- the page agree.

local LIST_WIDTH = 186 -- the module list
local ROW_HEIGHT = 26 -- an option's row, as in Blizzard's lists
local INDENT = 10 -- an option under another (`requires`)
local CONTROL_LEFT = 165 -- where an option's control starts, after its name
local DESCRIPTION_LINES = 4 -- the room a description always takes, so the options stay put

local listed = {} -- the names of the modules on the page, by category, then title
local searchText = {} -- module name -> its title, description, and options' text, lowercased
local filter, filterText -- the search text, lowercased and as typed, or nil while the box is empty
local newOnly -- the New checkbox: only modules marked NEW show, off each time Settings opens
local page -- the page's frames, once built
local bound = {} -- module name -> functions that put what shows of it back to what's saved
local refreshModule -- puts one module back to what's saved wherever it shows

local function isNew(name)
    return (newRows[name] or newRows[ns.modules[name]]) and true or false
end

local function matches(name)
    if newOnly and not isNew(name) then
        return false
    end
    return not filter or (searchText[name] or ""):find(filter, 1, true) ~= nil
end

-- Whether any listed module is marked NEW.
local function anyNew()
    for _, name in ipairs(listed) do
        if isNew(name) then
            return true
        end
    end
    return false
end

-- Whether the search shows a module of `group` (any module, without one).
local function anyMatch(group)
    for _, name in ipairs(listed) do
        if (not group or categoryOf(ns.modules[name]) == group) and matches(name) then
            return true
        end
    end
    return false
end

-- Runs `fn` now and whenever the module changes.
local function bind(name, fn)
    local list = bound[name]
    if not list then
        list = {}
        bound[name] = list
    end
    list[#list + 1] = fn
    fn()
end

-- Our Defaults button (askDefaults) at the top right of a page we draw: Modules, Changelog, About.
local function addPageDefaults(frame)
    local button = newButton(frame, SETTINGS_DEFAULTS or L.HOME_DEFAULTS, 96, askDefaults)
    button:SetPoint("TOPRIGHT", -10, -18)
    return button
end
S.addPageDefaults = addPageDefaults

local function setEnabled(name, on)
    ns.SetEnabled(name, on)
    ns.RefreshSetting(name)
end

local function setOption(module, option, value)
    ns.SetOption(module.name, option.key, value)
    ns.RefreshSetting(module.name)
end

-- The module's on/off checkbox, kept in step with its other one.
local function newModuleCheck(parent, name, size)
    local box = newCheckbox(parent, size, function(checked) setEnabled(name, checked) end)
    bind(name, function()
        box:SetChecked(ns.modules[name].db.enabled and true or false)
    end)
    return box
end

-- Blizzard's slider with steppers for a slider option. Probe: Mainline's.
local function newSlider(parent, module, option, width)
    if not (MinimalSliderWithSteppersMixin and Settings.CreateSliderOptions) then
        return
    end
    local ok, slider = pcall(CreateFrame, "Frame", nil, parent, "MinimalSliderWithSteppersTemplate")
    if not (ok and slider and slider.Init and slider.RegisterCallback) then
        return
    end
    slider:SetWidth(width)
    local options = sliderOptions(option)
    slider:Init(module.db[option.key], options.minValue, options.maxValue, options.steps,
        options.formatters)
    slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
        value = ns.SliderValue(option, value)
        -- Setting it back to what's saved (a refresh) changes nothing.
        if value and value ~= module.db[option.key] then
            setOption(module, option, value)
        end
    end, slider)
    return slider
end

-- Blizzard's menu dropdown for an option with `choices`. Probe: Mainline's.
local function newDropdown(parent, module, option, width)
    if not WowStyle1DropdownMixin then
        return
    end
    local ok, dropdown = pcall(CreateFrame, "DropdownButton", nil, parent,
        "WowStyle1DropdownTemplate")
    if not (ok and dropdown and dropdown.SetupMenu) then
        return
    end
    dropdown:SetWidth(width)
    dropdown:SetupMenu(function(_, root)
        for _, choice in ipairs(option.choices) do
            root:CreateRadio(choice[2], function(value)
                return module.db[option.key] == value
            end, function(value)
                setOption(module, option, value)
            end, choice[1])
        end
    end)
    return dropdown
end

-- Moves `scroll` so `frame`, in its `content`, is at the top. With `onlyIfHidden`, only when the
-- frame is below what shows. After a frame, once the new layout's sizes are known.
local function scrollTo(scroll, content, frame, onlyIfHidden)
    if not (C_Timer and frame) then
        return
    end
    C_Timer.After(0, function()
        local top, inner = content:GetTop(), frame:GetTop()
        if not (top and inner) then
            return
        end
        if onlyIfHidden then
            local bottom, height = frame:GetBottom(), scroll:GetHeight()
            if not (bottom and height and top - bottom > scroll:GetVerticalScroll() + height) then
                return
            end
        end
        local range = scroll:GetVerticalScrollRange() or 0
        scroll:SetVerticalScroll(min(max(top - inner - 4, 0), range))
    end)
end

-- What the search looks for in an option: its name and description (its tooltip), lowercased.
local function optionText(option)
    return strlower(format("%s\n%s", option.name or "", option.description or ""))
end

-- The selected module's rows -------------------------------------------------------------------
-- A view is a stack of the module's rows: a name on the left and its control after. Its
-- `updates` put its controls back to what's saved.

-- A row: `text` on the left, gold while `on()` and grey otherwise, and the space after it for a
-- control. Shown only while `shown()` is true, when given.
local function addRow(view, text, indent, on, shown)
    local row = CreateFrame("Frame", nil, view)
    row:EnableMouse(true)
    row:SetWidth(view:GetWidth())
    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", 4 + indent, 0)
    label:SetWidth(CONTROL_LEFT - 8 - indent)
    label:SetJustifyH("LEFT")
    label:SetText(text)
    row:SetHeight(max(ROW_HEIGHT, label:GetStringHeight() + 8))
    addEntry(view, row, shown)
    if on then
        view.updates[#view.updates + 1] = function()
            label:SetFontObject(on() and "GameFontNormal" or "GameFontDisable")
        end
    end
    return row, label
end

-- How wide a dropdown or button is in a row with `room` after the option's name.
local function controlWidth(room)
    return min(180, room - 16)
end

-- How wide every slider is, its arrows included, so they all look alike whatever their values.
local SLIDER_WIDTH = 180

-- How wide a slider starting `left` into a row with `room` is: SLIDER_WIDTH, or less where its
-- value label (drawn after it) wouldn't fit.
local function sliderWidth(row, option, room, left)
    local measure = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    local widest = 0
    for _, value in ipairs({ option.min, option.max }) do
        measure:SetText(sliderText(option, value))
        widest = max(widest, ns.Text.Width(measure))
    end
    measure:Hide()
    return max(60, min(SLIDER_WIDTH, room - 16 - left - widest - 12))
end

-- The room the reset arrow takes at the end of an option's row.
local RESET_SIZE = 20

-- An option's default as its control shows it: a slider's text, a dropdown's choice, or checked.
local function defaultText(module, option)
    local value = module.defaults[option.key]
    if option.min then
        return sliderText(option, value)
    elseif option.choices then
        for _, choice in ipairs(option.choices) do
            if choice[1] == value then
                return choice[2]
            end
        end
        return tostring(value)
    end
    return value and L.SETTINGS_CHECKED or L.SETTINGS_UNCHECKED
end

-- The undo arrow at the end of an option's row (and the slider in it, `pair`), shown while either
-- isn't at its default, that puts them back. Like the undo buttons on Blizzard's Talents and
-- Transmog windows. Probe: their atlases are Mainline's; without one, no arrow.
local function addResetButton(view, row, module, option, pair, on)
    local keys = { option, pair }
    local button, icon = Kit.NewResetButton(row, RESET_SIZE, function()
        for _, each in ipairs(keys) do
            ns.ResetOption(module.name, each.key) -- forgets the choice, not just the value
        end
        ns.RefreshSetting(module.name)
    end)
    if not button then
        return
    end
    local function changed()
        for _, each in ipairs(keys) do
            if module.db[each.key] ~= module.defaults[each.key] then
                return true
            end
        end
        return false
    end
    -- Greyed with the option, and still saying what it would do.
    button:SetMotionScriptsWhileDisabled(true)
    button:SetScript("OnEnter", function(self)
        local text = defaultText(module, option)
        if pair then
            text = format(L.SETTINGS_RESET_PAIR, text, defaultText(module, pair))
        end
        showTooltip(self, L.SETTINGS_RESET, format(L.SETTINGS_RESET_TO, text))
    end)
    button:SetScript("OnLeave", Kit.HideTooltip)
    view.updates[#view.updates + 1] = function()
        button:SetShown(changed())
        button:SetEnabled(on())
        icon:SetDesaturated(not on())
    end
end

-- One of the module's options, with `byKey` for the option it's under (`requires`) or the slider
-- in its row (`slider`), and `done` for those already drawn. With `gate`, it's also off while that
-- returns false (the Debug module's rows, off with Debug).
local function addOptionRow(view, module, option, byKey, done, gate)
    local parent = option.requires and byKey[option.requires]
    -- Under an option that is itself under another, it's on only while all of them are.
    local function on()
        if gate and not gate() then
            return false
        end
        -- Off with the module, and with its part's checkbox (`part`) when it's one of a part's.
        if not module.db.enabled or option.part and not ns.PartOn(module, option.part) then
            return false
        end
        -- Off while what it needs isn't there (`available`), such as another addon.
        if option.available and not option.available() then
            return false
        end
        local up = parent
        while up do
            local value = module.db[up.key]
            if not value or value == "off" then -- a checkbox, or a dropdown
                return false
            end
            up = up.requires and byKey[up.requires]
        end
        return true
    end
    local depth, up = 0, parent
    while up do
        depth = depth + 1
        up = up.requires and byKey[up.requires]
    end
    local indent = depth * INDENT
    -- A part's checkbox (`toggle`) is right under its section's header, which names it. A part's
    -- dropdown (a toggle with `choices`) is an ordinary option row with its own name.
    local name = option.toggle and not option.choices and L.SETTINGS_ENABLED or option.name
    local row, label = addRow(view, name, indent, on)
    local updates = view.updates
    local pair = option.slider and byKey[option.slider]
    -- Highlighted like a selected sidebar entry while the search finds it (or the slider in it).
    local r, g, b = NORMAL_FONT_COLOR:GetRGB()
    local highlight = ns.Frames.RowTexture(row, "BACKGROUND", "Options_List_Active", r, g, b, 0.15)
    highlight:Hide()
    view.found[#view.found + 1] = { row = row, highlight = highlight,
        text = optionText(option) .. (pair and "\n" .. optionText(pair) or "") }
    local paired = pair and pair.min
    local box
    if paired or not (option.min or option.choices) then
        box = newCheckbox(row, 30, function(checked) setOption(module, option, checked) end)
        box:SetPoint("LEFT", CONTROL_LEFT, 0)
    end
    -- The name wraps narrower while it's marked NEW, so the row's height follows it, unless the
    -- mark goes after a lone checkbox instead. A slider in the row has no name of its own here, so
    -- its mark goes on the row's.
    local mark = newMark(row, label, CONTROL_LEFT - 8 - indent, option, pair,
        not paired and box or nil)
    updates[#updates + 1] = function()
        mark()
        row:SetHeight(max(ROW_HEIGHT, label:GetStringHeight() + 8))
    end
    local room = view:GetWidth() - CONTROL_LEFT - RESET_SIZE
    addResetButton(view, row, module, option, paired and pair or nil, on)
    if box then
        updates[#updates + 1] = function()
            box:SetChecked(module.db[option.key] and true or false)
            box:SetEnabled(on())
        end
        addTooltip(row, option.name, option.description, box)
        if not paired then
            return
        end
        -- Its slider in the same row, greyed while the checkbox is off.
        done[pair.key] = true
        local slider = newSlider(row, module, pair, sliderWidth(row, pair, room, 36))
        if slider then
            slider:SetPoint("LEFT", box, "RIGHT", 6, 0)
            updates[#updates + 1] = function()
                slider:SetValue(module.db[pair.key])
                slider:SetEnabled(on() and module.db[option.key] and true or false)
            end
        end
    elseif option.min then
        local slider = newSlider(row, module, option, sliderWidth(row, option, room, 6))
        if not slider then
            return -- leave the option at its default without one
        end
        slider:SetPoint("LEFT", CONTROL_LEFT + 6, 0)
        updates[#updates + 1] = function()
            slider:SetValue(module.db[option.key])
            slider:SetEnabled(on())
        end
        addTooltip(row, option.name, option.description, slider.Slider)
    elseif option.choices then
        local dropdown = newDropdown(row, module, option, controlWidth(room))
        if not dropdown then
            return
        end
        dropdown:SetPoint("LEFT", CONTROL_LEFT + 6, 0)
        updates[#updates + 1] = function()
            dropdown:GenerateMenu()
            dropdown:SetEnabled(on())
        end
        addTooltip(row, option.name, option.description, dropdown)
    end
end

-- A row with a button: one of `module.actions`, the module's notice, or the way to its own page.
-- `title` heads its tooltip when `text` isn't plain.
local function addButtonRow(view, text, on, shown, button, fn, tooltip, title)
    local row = addRow(view, text, 0, on, shown)
    local control = newButton(row, button, min(180, view:GetWidth() - CONTROL_LEFT - 16), fn)
    control:SetPoint("LEFT", CONTROL_LEFT + 6, 0)
    if on then
        view.updates[#view.updates + 1] = function()
            control:SetEnabled(on())
        end
    end
    addTooltip(row, title or text, tooltip, control)
end

-- A line of text across the view: a section's header, a smaller one inside it, or "no options".
local function addLine(view, font, text, gap)
    local row = CreateFrame("Frame", nil, view)
    row:SetSize(view:GetWidth(), font == "GameFontHighlightLarge" and 24 or ROW_HEIGHT)
    local line = row:CreateFontString(nil, "OVERLAY", font)
    line:SetPoint("LEFT", 4, 0)
    line:SetText(text)
    addEntry(view, row, nil, gap or 16)
end

-- The module's rows, under its title, category and description: its notice, then its options and
-- buttons in the order it lists them, or a line saying it has none. Each change of `section`
-- starts a header with its name; options before the first section get an Options header. Inside a
-- section, each change of `subsection` (a part's own sections) starts a smaller one.
local function addModuleRows(view, module)
    local name = module.name
    local function on()
        return module.db.enabled and true or false
    end
    -- A gray row while `shown()` is true (always without one), such as a Blizzard setting the
    -- module needs being off, with a button that fixes it. ns.CVars.OffNotice makes one for a CVar.
    -- One without a `button` only says so, across the whole row: a warning kept out of the
    -- description. `module.notice` is one notice or a list of them.
    local notices = module.notice
    if notices and not notices[1] then
        notices = { notices }
    end
    for _, notice in ipairs(notices or {}) do
        if not notice.button then
            local row, label = addRow(view, format("|cff999999%s|r", notice.text), 0, nil, notice.shown)
            label:SetWidth(view:GetWidth() - 8)
            row:SetHeight(max(ROW_HEIGHT, label:GetStringHeight() + 8))
            addTooltip(row, notice.text, notice.description)
        else
            addButtonRow(view, format("|cff999999%s|r", notice.text), nil, notice.shown,
                notice.button, function()
                    notice.fn()
                    refreshModule(name)
                    -- A CVar can change a moment later (ns.CVars waits out combat).
                    if C_Timer then
                        C_Timer.After(0.2, function() refreshModule(name) end)
                    end
                end, notice.description, notice.text)
        end
    end
    local options, byKey, done = {}, {}, {}
    for _, option in ipairs(module.options or {}) do
        if not option.debug then
            options[#options + 1] = option
            byKey[option.key] = option
        end
    end
    -- The Debug module's rows (Debug.lua): every module's debug options and buttons.
    local extra = name == "Debug" and S.AddDebugRows
    -- A module's own page needs no button here: it's in the sidebar while the module is on.
    if #options == 0 and not module.actions then
        if extra then
            extra(view, on)
        else
            addLine(view, "GameFontDisable", L.SETTINGS_NO_OPTIONS)
        end
        return
    end
    local section, subsection
    if not (options[1] and options[1].section) then
        addLine(view, "GameFontHighlightLarge", L.SETTINGS_OPTIONS)
    end
    for _, option in ipairs(options) do
        if option.section and option.section ~= section then
            section, subsection = option.section, nil
            -- A part turned on by a dropdown is one row among the options, with no header.
            if not (option.toggle and option.choices) then
                addLine(view, "GameFontHighlightLarge", section)
            end
        end
        if option.subsection and option.subsection ~= subsection then
            subsection = option.subsection
            addLine(view, "GameFontHighlight", subsection, 8)
        end
        if not done[option.key] then
            addOptionRow(view, module, option, byKey, done)
        end
    end
    for i, action in ipairs(module.actions or {}) do
        addButtonRow(view, action.name, on, nil, action.button, actionFn(module, action, i),
            action.description)
    end
    if extra then
        extra(view, on)
    end
end
S.addOptionRow, S.addButtonRow, S.addLine = addOptionRow, addButtonRow, addLine

-- The module on the right: its title, its category, its description in DESCRIPTION_LINES, and its
-- Enabled checkbox in a row like its options', over its rows.
local function buildView(name)
    local module = ns.modules[name]
    local title = module.title or name
    local width = page.paneWidth
    local view = newStack(page.paneContent, width, 4)
    view:SetPoint("TOPLEFT")
    -- `follows`: other modules whose changes show here too (the Debug module's rows).
    view.updates, view.found, view.follows = {}, {}, {}

    local heading = view:CreateFontString(nil, "OVERLAY", "GameFontHighlightHuge")
    heading:SetPoint("TOPLEFT", 4, -4)
    heading:SetJustifyH("LEFT")
    heading:SetWordWrap(false)
    heading:SetText(title)
    view.updates[#view.updates + 1] = newMark(view, heading, width - 12, name)

    local group = view:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    group:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -4)
    group:SetText(CATEGORY_NAMES[categoryOf(module)])
    local description = view:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    description:SetPoint("TOPLEFT", group, "BOTTOMLEFT", 0, -10)
    description:SetWidth(width - 12)
    description:SetJustifyH("LEFT")
    description:SetJustifyV("TOP")
    -- The height of DESCRIPTION_LINES lines of this font, measured.
    description:SetText(("X\n"):rep(DESCRIPTION_LINES - 1) .. "X")
    local height = description:GetStringHeight()
    description:SetHeight(height)
    if description.SetMaxLines then
        description:SetMaxLines(DESCRIPTION_LINES) -- longer text ends in "..."
    end
    description:SetText(module.description or "")
    -- The whole description in a tooltip when it's cut short. Probe: IsTruncated is Mainline's.
    if description.IsTruncated then
        local hit = CreateFrame("Frame", nil, view)
        hit:SetAllPoints(description)
        hit:EnableMouse(true)
        hit:SetScript("OnEnter", function()
            if description:IsTruncated() then
                showTooltip(hit, title, module.description)
            end
        end)
        hit:SetScript("OnLeave", Kit.HideTooltip)
    end
    view.top = 4 + heading:GetStringHeight() + 4 + group:GetStringHeight() + 10 + height + 6
    view.bottom = 12

    local row = addRow(view, L.SETTINGS_ENABLED, 0)
    local box = newModuleCheck(row, name, 30)
    box:SetPoint("LEFT", CONTROL_LEFT, 0)
    addModuleRows(view, module)
    local function update()
        for _, each in ipairs(view.updates) do
            each()
        end
    end
    bind(name, update)
    for other in pairs(view.follows) do
        if other ~= name then
            bind(other, update)
        end
    end
    return view
end

-- The module list ------------------------------------------------------------------------------

-- Highlights the options of `view` the search finds. With `reveal`, scrolls the first of them into
-- sight when it's below what shows.
local function markFound(view, reveal)
    local first
    for _, entry in ipairs(view.found) do
        local found = filter and entry.text:find(filter, 1, true) ~= nil
        entry.highlight:SetShown(found)
        first = first or found and entry.row
    end
    if reveal then
        scrollTo(page.pane, page.paneContent, first, true)
    end
end

-- Shows `name` on the right (nil for none).
local function choose(name)
    selected = name
    for _, row in pairs(page.rows) do
        paint(row)
    end
    for other, view in pairs(page.views) do
        view:SetShown(other == name)
    end
    if name then
        local view = page.views[name]
        if not view then
            view = buildView(name)
            page.views[name] = view
        end
        layoutStack(view)
        page.paneContent:SetHeight(view:GetHeight())
        page.pane:SetVerticalScroll(0)
        markFound(view, true)
    end
    -- Last, since moving on from a module with labels redraws the page.
    if newOrder and onModulesPage() then
        moveOn(name)
    end
end

-- Shows `name` on the right and scrolls the list to it.
local function selectModule(name)
    choose(name)
    scrollTo(page.listScroll, page.list, page.rows[name])
end

-- The first listed module with an option the player hasn't seen yet, or nil.
local function firstNew()
    for _, name in ipairs(listed) do
        if newRows[ns.modules[name]] then
            return name
        end
    end
end

-- A row of the list: the module's checkbox and its name, white while it's on and grey while it's
-- off, with a NEW label while it's new. Clicking it selects the module.
local function newListRow(name)
    local module = ns.modules[name]
    local row = newListButton(page.list, function() return selected == name end)
    local box = newModuleCheck(row, name, 22)
    box:SetPoint("LEFT", 0, 0)
    -- The checkbox takes the mouse from the row, so it keeps the row's highlight.
    box:HookScript("OnEnter", function() hover(row, true) end)
    box:HookScript("OnLeave", function() hover(row, false) end)
    local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("LEFT", box, "RIGHT", 2, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    text:SetText(module.title or name)
    local mark = newMark(row, text, LIST_WIDTH - 26, name, module)
    bind(name, function()
        text:SetFontObject(module.db.enabled and "GameFontHighlight" or "GameFontDisable")
        mark()
    end)
    row:SetScript("OnClick", function()
        if selected ~= name then
            choose(name)
        end
    end)
    return row
end

-- Lays out the modules the search shows, keeps the selection on one of them (the first, when it
-- hides the selected one), and lays out the selected module's rows.
-- `reveal` scrolls the first option the search finds into sight (see markFound).
local function relayout(reveal)
    if not page then
        return
    end
    if newOnly and not anyNew() then
        page.empty.text:SetText(L.SETTINGS_NOTHING_NEW)
    else
        page.empty.text:SetText(format(L.SETTINGS_NO_MATCH, filterText or ""))
    end
    layoutStack(page.list)
    if not (selected and matches(selected)) then
        local first
        for _, name in ipairs(listed) do
            if matches(name) then
                first = name
                break
            end
        end
        choose(first)
    elseif page.views[selected] then
        layoutStack(page.views[selected])
        page.paneContent:SetHeight(page.views[selected]:GetHeight())
        markFound(page.views[selected], reveal)
    end
end

function refreshModule(name)
    for _, fn in ipairs(bound[name] or {}) do
        fn()
    end
    relayout()
end

function refreshAll()
    for _, list in pairs(bound) do
        for _, fn in ipairs(list) do
            fn()
        end
    end
    relayout()
end

-- The Modules page's search: the list narrows to the modules whose title or description has the
-- text, or an option's name or description, and those options are highlighted on the right.
local function searchModules(text)
    filter = text ~= "" and strlower(text) or nil
    filterText = text
    relayout(true)
end

-- A New checkbox left of the search box that narrows the list to the modules marked NEW, with the
-- search on top. It's off each time Settings opens, so the whole list is what the page opens on.
-- Without NEW labels on this client (trackNew didn't run), there's nothing to show, so no checkbox.
local function addNewOnly(frame, anchor)
    if not newOrder then
        return
    end
    local box = Kit.AddLabeledCheck(frame, anchor, L.SETTINGS_NEW_ONLY, function(checked)
        newOnly = checked or nil
        relayout()
    end)
    SettingsPanel:HookScript("OnShow", function()
        box:SetChecked(false)
        if newOnly then
            newOnly = nil
            relayout()
        end
    end)
end

local function buildModules(frame)
    Kit.AddPageTitle(frame, L.MODULES)
    page = newSplit(frame, LIST_WIDTH)
    page.rows, page.views = {}, {}

    local defaults = addPageDefaults(frame)
    page.search = addSearchBox(frame, defaults, L.SETTINGS_SEARCH, searchModules)
    addNewOnly(frame, page.search or defaults)

    -- "No modules match" while the search hides them all, or "Nothing new" while the New checkbox
    -- is on and nothing is marked.
    local empty = newEmptyRow(page.list, LIST_WIDTH)
    page.empty = empty
    addEntry(page.list, empty, function() return not anyMatch() end)
    local group
    for _, name in ipairs(listed) do
        local current = categoryOf(ns.modules[name])
        if current ~= group then
            group = current
            local label = CreateFrame("Frame", nil, page.list)
            label:SetSize(LIST_WIDTH, 16)
            local text = label:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            text:SetPoint("BOTTOMLEFT", 2, 2)
            text:SetText(CATEGORY_NAMES[current])
            addEntry(page.list, label, function() return anyMatch(current) end, 12)
        end
        page.rows[name] = newListRow(name)
        addEntry(page.list, page.rows[name], function() return matches(name) end)
    end

    -- Opens on the module ns.OpenSettings asked for, or the first with a new option to see, or
    -- else the first.
    selected = selected or firstNew()
    if selected then
        selectModule(selected)
    end
    relayout()
    -- After /fpp or a preset changed things while the page was closed, and for notices.
    frame:HookScript("OnShow", refreshAll)
end

-- Puts the version last seen back to the release before this one, so the Modules page marks what a
-- player updating from it would see, and opens it the way it would open for them: on the first
-- module with a marked option. A module's marks go once it's been clicked, as they do after an
-- update. Once this version is released it's the last release itself, so it can't be the one.
function S.resetSeen()
    ns.db.seenVersion = lastRelease(ns.version)
    wipe(ns.db.seenModules)
    markNew()
    if page then
        selected = firstNew()
        refreshAll()
        if selected then
            selectModule(selected)
        end
    end
    open(modulesCategory)
end

-- Module names in the order their titles sort in the player's language, whatever order the TOC
-- loads them in. Modules this client doesn't get are left out.
local function byTitle()
    local names = {}
    for _, name in ipairs(ns.order) do
        if not ns.modules[name].unavailable then
            names[#names + 1] = name
        end
    end
    local function key(name)
        return strlower(ns.modules[name].title or name)
    end
    sort(names, function(a, b) return key(a) < key(b) end)
    return names
end
S.byTitle = byTitle

---Adds the Forever++ pages to Settings > AddOns (called once, after ns.Start).
function ns.RegisterSettings()
    -- Probe: the Mainline Settings API is on Forever (build 70009), but it's a beta.
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
        return
    end
    local subpages = Settings.RegisterCanvasLayoutSubcategory ~= nil
    local order = byTitle()
    trackNew(order)
    -- Modules by category, then title: the order of the Modules page and of the tool pages.
    local grouped = {}
    for _, group in ipairs(CATEGORIES) do
        for _, name in ipairs(order) do
            if categoryOf(ns.modules[name]) == group[1] then
                grouped[#grouped + 1] = name
            end
        end
    end
    for _, name in ipairs(grouped) do
        local module = ns.modules[name]
        if not module.alwaysOn then
            listed[#listed + 1] = name
            local text = { strlower(format("%s\n%s", module.title or name,
                module.description or "")) }
            for _, option in ipairs(module.options or {}) do
                if not option.debug then
                    text[#text + 1] = optionText(option)
                end
            end
            if name == "Debug" and S.DebugSearchText then
                text[#text + 1] = S.DebugSearchText()
            end
            searchText[name] = concat(text, "\n")
        end
    end

    -- The top Forever++ entry is the Modules page; without subpages it's the only one.
    local category = Settings.RegisterCanvasLayoutCategory(canvasFrame(buildModules), ns.title)
    modulesCategory = category
    if not subpages then
        Settings.RegisterAddOnCategory(category)
        return
    end

    -- Pages modules draw themselves (tools such as Console Variables).
    for _, name in ipairs(grouped) do
        local module = ns.modules[name]
        if module.BuildPage then
            pages[name] = addCanvasPage(category, module.pageTitle or module.title or name, function(frame)
                module:BuildPage(frame)
            end)
            pageOrder[#pageOrder + 1] = name
        end
    end
    for _, name in ipairs(pageOrder) do
        updatePage(name)
    end
    addCanvasPage(category, L.CHANGELOG, S.BuildChangelog)
    aboutCategory = addCanvasPage(category, L.ABOUT, S.BuildAbout)
    Settings.RegisterAddOnCategory(category)
end

---Opens the Forever++ Modules page in Settings, or a module: its own page, or the Modules page
---with it selected (after combat, if the player is in combat).
---@param name? string a module
---@return boolean opened false when this client's Settings can't open to it
function ns.OpenSettings(name)
    if name and pages[name] and pageShown(name) then
        return open(pages[name])
    end
    if name and searchText[name] then
        if page then
            -- Searching for something else would hide it.
            if not matches(name) and page.search then
                page.search:SetText("")
            end
            selectModule(name)
        else
            selected = name -- the page opens on it
        end
    end
    return open(modulesCategory)
end

---Opens the Forever++ About page in Settings (after combat, if the player is in combat).
---@return boolean opened false when this client's Settings can't open to it
function ns.OpenAbout()
    return open(aboutCategory)
end

---Updates a module's controls after it changed somewhere else (/fpp toggle, set, a preset).
---@param name string
function ns.RefreshSetting(name)
    refreshModule(name)
    updatePage(name)
end
