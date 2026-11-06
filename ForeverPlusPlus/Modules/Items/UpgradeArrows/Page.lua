-- Upgrade Arrows' own page in Settings (`/fpp weights`): a Class dropdown and a Tree dropdown,
-- then a slider row per stat of that profile under small headers, with its value and an undo
-- arrow while it isn't the default. For the character's own class the Tree dropdown (Auto, each
-- talent tab, and Feral Bear for Druids) is also the character's own Profile choice, what gear
-- is judged by; another class's trees can be edited ahead of playing it. Only the stats the profile
-- weighs are listed unless Show All is ticked. Drawn with ns.SettingsKit so it looks like the
-- Modules page, which uses the same slider and dropdown templates.
local _, ns = ...

local ipairs, pairs, format, tonumber, tostring, abs = ipairs, pairs, string.format, tonumber, tostring, math.abs
local _G, CreateFrame = _G, CreateFrame

local L = ns.L
local Kit = ns.SettingsKit
local ItemStats = ns.ItemStats
local Talents = ns.Talents

local module = ns.modules.UpgradeArrows
local internal = module.internal

-- The stats in groups, in the order the page lists them (every key of ItemStats.ORDER).
local GROUPS = {
    { L.UPGRADEARROWS_GROUP_ATTRIBUTES, { "STR", "AGI", "STA", "INT", "SPI", "HEALTH", "MANA" } },
    { L.UPGRADEARROWS_GROUP_MELEE, { "AP", "HIT", "CRIT", "HASTE", "EXPERTISE", "ARMORPEN" } },
    { L.UPGRADEARROWS_GROUP_RANGED, { "RAP" } },
    { L.UPGRADEARROWS_GROUP_SPELL, { "SP", "HEAL", "SPELLHIT", "SPELLCRIT", "MP5", "HP5" } },
    { L.UPGRADEARROWS_GROUP_DEFENSE, { "ARMOR", "DEF", "DODGE", "PARRY", "BLOCK", "BLOCKVALUE" } },
    { L.UPGRADEARROWS_GROUP_WEAPONS, { "DPS", "DPS_OFF", "DPS_RANGED" } },
    { L.UPGRADEARROWS_GROUP_RESISTANCES, { "RES_FIRE", "RES_NATURE", "RES_FROST", "RES_SHADOW", "RES_ARCANE" } },
}

-- The classes the Class dropdown lists, in Blizzard's order.
local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

local MAX_WEIGHT, STEP = 20, 0.01 -- every default is a multiple of the step, so none drifts
local EPSILON = 0.001 -- two weights this close are the same, whatever floating point says
local ROW_HEIGHT, HEADER_HEIGHT = 26, 24
local NAME_WIDTH, SLIDER_WIDTH, RESET_SIZE = 190, 250, 22

local ui -- the page's frames, once built
local editing -- the profile shown: from internal.Profile
local editingClass -- the class shown; the character's own at first
local treeChoice = {} -- class -> the tree picked for a class other than the character's
local showAll = false

local function nearly(a, b)
    return abs((a or 0) - (b or 0)) < EPSILON
end

-- The stat's name, with "per 1%" in gray after a chance stat's.
local function statName(stat)
    local name = L["UPGRADEARROWS_STAT_" .. stat]
    if ItemStats.PERCENT[stat] then
        name = format("%s |cff808080%s|r", name, L.UPGRADEARROWS_PER_PERCENT)
    end
    return name
end

-- A weight as text: up to two decimals, without trailing zeros ("1", "0.35", "0.5").
local function weightText(value)
    local text = format("%.2f", value or 0)
    text = (text:gsub("0+$", ""))
    text = (text:gsub("%.$", ""))
    return text
end

-- Classes and trees ---------------------------------------------------------------------------

local playerClass = internal.PlayerClass

-- A class's name in the player's language. Probe: the table is Blizzard's; without it, the token.
local function className(class)
    local names = _G.LOCALIZED_CLASS_NAMES_MALE
    local name = names and names[class]
    return ns.IsText(name, true) and name or class
end

-- A talent tab's name: the live one for the character's own class, else ours.
local function tabName(class, index)
    if class == playerClass() then
        local tabs = Talents.Tabs()
        local tab = tabs and tabs[index]
        if tab and tab.name ~= "" then
            return tab.name
        end
    end
    return internal.TabName(class, index)
end

-- The Tree dropdown's choices for a class, each with its value: Auto (the character's own class
-- only), each talent tab, and Bear for a Druid.
local function treeChoices(class)
    local list = {}
    if class == playerClass() then
        list[#list + 1] = { value = "auto", name = L.UPGRADEARROWS_PROFILE_AUTO }
    end
    for i = 1, 3 do
        list[#list + 1] = { value = tostring(i), index = i, name = tabName(class, i) }
    end
    if class == "DRUID" then
        list[#list + 1] = { value = "bear", bear = true, name = L.UPGRADEARROWS_PROFILE_BEAR }
    end
    return list
end

-- The Tree dropdown's value for a class: the Profile setting for the character's own, else
-- what was picked here.
local function treeValue(class)
    if class == playerClass() then
        return internal.ProfileChoice()
    end
    return treeChoice[class] or "1"
end

-- The profile the dropdowns show, with the module's saved weights read in, and whether it's a
-- guess (Auto with no talent points). For the character's own class it's the module's own.
local function resolveProfile()
    local class = editingClass
    if class == playerClass() then
        local current = internal.CurrentProfile()
        if current then
            return internal.Profile(current.class, current.index, current.bear), current.guess
        end
    end
    return internal.ResolveProfile(class, treeValue(class))
end

-- A profile's name for the player: "Arms (Warrior)".
local function profileName(profile)
    local tree = profile.bear and L.UPGRADEARROWS_PROFILE_BEAR or tabName(profile.class, profile.index)
    return format(L.UPGRADEARROWS_PAGE_PROFILE_NAME, tree, className(profile.class))
end

-- The line under the dropdowns: what the module judges gear by now, or whom another class's
-- weights are for.
local function usedText(guess)
    if not editing then
        return ""
    end
    if editingClass ~= playerClass() then
        return format(L.UPGRADEARROWS_PAGE_OTHER_CLASS, className(editingClass))
    end
    local name = profileName(editing)
    if internal.ProfileChoice() == "auto" then
        local best = Talents.Dominant()
        if guess or not best then
            return format(L.UPGRADEARROWS_PAGE_USED_GUESS, name)
        end
        return format(L.UPGRADEARROWS_PAGE_USED_AUTO, name, best.spent)
    end
    return format(L.UPGRADEARROWS_PAGE_USED, name)
end

-- Rows ------------------------------------------------------------------------------------------

-- Whether a stat's row shows: always with Show All, else while the profile weighs it or the
-- player set it.
local function rowShown(stat)
    if showAll or not editing then
        return true
    end
    return not nearly(editing.defaults[stat], 0) or editing.weights[stat] ~= nil
end

local function currentWeight(stat)
    return editing and editing.weights[stat] or 0
end

local function defaultWeight(stat)
    return editing and editing.defaults[stat] or 0
end

-- The undo arrow at a row's right, shown while the weight isn't the profile's default. Without
-- the art, no arrow (SettingsKit.NewResetButton).
local function addResetButton(row, stat)
    local button = Kit.NewResetButton(row, RESET_SIZE, function()
        if editing then
            internal.SetWeight(editing, stat, defaultWeight(stat))
            ui.refresh()
        end
    end)
    if not button then
        return nil
    end
    button:SetScript("OnEnter", function(self)
        Kit.ShowTooltip(self, L.SETTINGS_RESET, format(L.UPGRADEARROWS_PAGE_DEFAULT, weightText(defaultWeight(stat))))
    end)
    button:SetScript("OnLeave", Kit.HideTooltip)
    return button
end

-- Blizzard's slider with steppers, 0 to 20 by 0.05, its value shown at its right. Probe:
-- Mainline's; without it the row shows the value as text only.
local function addSlider(row, stat)
    if not (MinimalSliderWithSteppersMixin and Settings and Settings.CreateSliderOptions) then
        return nil
    end
    local ok, slider = pcall(CreateFrame, "Frame", nil, row, "MinimalSliderWithSteppersTemplate")
    if not (ok and slider and slider.Init and slider.RegisterCallback) then
        return nil
    end
    slider:SetWidth(SLIDER_WIDTH)
    slider:SetPoint("LEFT", NAME_WIDTH, 0)
    local options = Settings.CreateSliderOptions(0, MAX_WEIGHT, STEP)
    if MinimalSliderWithSteppersMixin.Label then
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, weightText)
    end
    slider:Init(currentWeight(stat), options.minValue, options.maxValue, options.steps, options.formatters)
    slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
        -- A refresh setting the slider to what's saved changes nothing.
        if ui.loading or not editing then
            return
        end
        value = tonumber(format("%.2f", value))
        if value and not nearly(value, currentWeight(stat)) then
            internal.SetWeight(editing, stat, value)
            ui.refreshRow(stat)
        end
    end, slider)
    return slider
end

local function newRow(parent, stat)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(parent:GetWidth(), ROW_HEIGHT)
    local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    name:SetPoint("LEFT", 8, 0)
    name:SetWidth(NAME_WIDTH - 12)
    name:SetJustifyH("LEFT")
    name:SetText(statName(stat))
    -- A derived attribute says what the game gives for a point of it, over its name.
    if internal.DERIVED[stat] then
        local hit = CreateFrame("Frame", nil, row)
        hit:SetPoint("TOPLEFT")
        hit:SetPoint("BOTTOMLEFT")
        hit:SetWidth(NAME_WIDTH - 12)
        hit:EnableMouse(true)
        hit:SetScript("OnEnter", function(self)
            local text = editing and internal.DerivedText(stat, editing)
            if text then
                Kit.ShowTooltip(self, L["UPGRADEARROWS_STAT_" .. stat], text)
            end
        end)
        hit:SetScript("OnLeave", Kit.HideTooltip)
    end
    row.slider = addSlider(row, stat)
    if not row.slider then
        row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.value:SetPoint("LEFT", NAME_WIDTH, 0)
    end
    row.reset = addResetButton(row, stat)
    row.stat = stat
    return row
end

local function newHeader(parent, text)
    local header = CreateFrame("Frame", nil, parent)
    header:SetSize(parent:GetWidth(), HEADER_HEIGHT)
    local label = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("BOTTOMLEFT", 8, 2)
    label:SetText(text)
    return header
end

-- Refreshing --------------------------------------------------------------------------------------

local function refreshRow(stat)
    local row = ui.rows[stat]
    if not row then
        return
    end
    local value = currentWeight(stat)
    ui.loading = true
    if row.slider then
        row.slider:SetValue(value)
    elseif row.value then
        row.value:SetText(weightText(value))
    end
    ui.loading = false
    if row.reset then
        row.reset:SetShown(not nearly(value, defaultWeight(stat)))
    end
end

local function refresh()
    if not ui then
        return
    end
    editingClass = editingClass or playerClass()
    local guess
    editing, guess = resolveProfile()
    ui.used:SetText(usedText(guess))
    for _, dropdown in ipairs({ ui.classDropdown, ui.treeDropdown }) do
        if dropdown.GenerateMenu then
            dropdown:GenerateMenu()
        end
    end
    if ui.classText then
        ui.classText:SetText(className(editingClass))
    end
    if ui.treeText then
        ui.treeText:SetText(profileName(editing))
    end
    for stat in pairs(ui.rows) do
        refreshRow(stat)
    end
    Kit.Layout(ui.content)
end

-- The page --------------------------------------------------------------------------------------

-- Blizzard's menu dropdown, filled by `fill(root)` each time it opens. Probe: Mainline's; without
-- it, a text the caller sets through the second value.
local function newDropdown(frame, width, fill)
    if WowStyle1DropdownMixin then
        local ok, dropdown = pcall(CreateFrame, "DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
        if ok and dropdown and dropdown.SetupMenu then
            dropdown:SetWidth(width)
            dropdown:SetupMenu(function(_, root)
                fill(root)
            end)
            return dropdown
        end
    end
    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    return text, text
end

---Draws the page the first time it's shown (called by Settings/Settings.lua).
---@param frame table the empty page
function module:BuildPage(frame)
    ui = { rows = {}, refresh = refresh, refreshRow = refreshRow }
    -- Blizzard's dropdowns fill their menus as soon as they're made, so the class they list for
    -- must be known before then.
    editingClass = editingClass or playerClass()
    Kit.AddPageTitle(frame, module.pageTitle)

    -- Defaults at the top right, as on the other pages, for the shown profile.
    local reset = Kit.NewButton(frame, L.UPGRADEARROWS_PAGE_RESET, 96, function()
        if not editing then
            return
        end
        ns.Confirm("UPGRADEARROWS_RESET", L.UPGRADEARROWS_PAGE_RESET_CONFIRM, function()
            internal.ResetWeights(editing)
            refresh()
        end, profileName(editing))
    end)
    reset:SetPoint("TOPRIGHT", -12, -19)
    Kit.AddTooltip(reset, L.UPGRADEARROWS_PAGE_RESET, L.UPGRADEARROWS_PAGE_RESET_DESC)

    local showAllBox = Kit.AddLabeledCheck(frame, reset, L.UPGRADEARROWS_PAGE_SHOW_ALL, function(checked)
        showAll = checked
        refresh()
    end)
    showAllBox:SetChecked(showAll)
    Kit.AddTooltip(showAllBox, L.UPGRADEARROWS_PAGE_SHOW_ALL, L.UPGRADEARROWS_PAGE_SHOW_ALL_DESC)

    -- Export and Import, left of Show All: the shown profile as a Pawn-format string to copy,
    -- and such a string pasted in, which replaces every weight of the shown profile.
    local export = Kit.NewButton(frame, L.UPGRADEARROWS_PAGE_EXPORT, 80, function()
        if not editing then
            return
        end
        local name = format(L.UPGRADEARROWS_PAGE_EXPORT_NAME, profileName(editing))
        local tree = editing.bear and L.UPGRADEARROWS_PROFILE_BEAR or tabName(editing.class, editing.index)
        ns.Prompt("UPGRADEARROWS_EXPORT", format(L.UPGRADEARROWS_PAGE_EXPORT_TEXT, profileName(editing)),
            ItemStats.WeightString(name, editing.class, tree, editing.weights))
    end)
    export:SetPoint("RIGHT", showAllBox, "LEFT", -12, 0)
    Kit.AddTooltip(export, L.UPGRADEARROWS_PAGE_EXPORT, L.UPGRADEARROWS_PAGE_EXPORT_DESC)
    local import = Kit.NewButton(frame, L.UPGRADEARROWS_PAGE_IMPORT, 80, function()
        if not editing then
            return
        end
        ns.Prompt("UPGRADEARROWS_IMPORT", L.UPGRADEARROWS_PAGE_IMPORT_TEXT, "", function(text)
            local weights, name, unknown = ItemStats.ParseWeightString(text)
            if not weights then
                ns.Print(L.UPGRADEARROWS_PAGE_IMPORT_BAD)
                return
            end
            local count = 0
            for _, stat in ipairs(ItemStats.ORDER) do
                local value = weights[stat] or 0
                if weights[stat] then
                    count = count + 1
                end
                internal.SetWeight(editing, stat, value)
            end
            ns.Print(format(L.UPGRADEARROWS_PAGE_IMPORTED, count, profileName(editing), name or ""))
            if unknown and #unknown > 0 then
                ns.Print(format(L.UPGRADEARROWS_PAGE_IMPORT_UNKNOWN, table.concat(unknown, ", ")))
            end
            refresh()
        end)
    end)
    import:SetPoint("RIGHT", export, "LEFT", -8, 0)
    Kit.AddTooltip(import, L.UPGRADEARROWS_PAGE_IMPORT, L.UPGRADEARROWS_PAGE_IMPORT_DESC)

    -- Class, then Tree, on one row under the title.
    local classLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    classLabel:SetPoint("TOPLEFT", 10, -64)
    classLabel:SetText(L.UPGRADEARROWS_PAGE_CLASS)
    ui.classDropdown, ui.classText = newDropdown(frame, 150, function(root)
        for _, class in ipairs(CLASSES) do
            root:CreateRadio(className(class), function()
                return editingClass == class
            end, function()
                editingClass = class
                refresh()
            end)
        end
    end)
    ui.classDropdown:SetPoint("LEFT", classLabel, "RIGHT", 8, 0)
    Kit.AddTooltip(ui.classDropdown, L.UPGRADEARROWS_PAGE_CLASS, L.UPGRADEARROWS_PAGE_CLASS_DESC)

    local treeLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    treeLabel:SetPoint("LEFT", ui.classDropdown, "RIGHT", 16, 0)
    treeLabel:SetText(L.UPGRADEARROWS_PAGE_TREE)
    ui.treeDropdown, ui.treeText = newDropdown(frame, 170, function(root)
        for _, choice in ipairs(treeChoices(editingClass)) do
            root:CreateRadio(choice.name, function()
                return treeValue(editingClass) == choice.value
            end, function()
                if editingClass == playerClass() then
                    internal.SetProfile(choice.value)
                else
                    treeChoice[editingClass] = choice.value
                end
                refresh()
            end)
        end
    end)
    ui.treeDropdown:SetPoint("LEFT", treeLabel, "RIGHT", 8, 0)
    Kit.AddTooltip(ui.treeDropdown, L.UPGRADEARROWS_PROFILE, L.UPGRADEARROWS_PROFILE_DESC)

    ui.used = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ui.used:SetPoint("TOPLEFT", 10, -90)
    ui.used:SetPoint("RIGHT", -40, 0)
    ui.used:SetJustifyH("LEFT")

    local note = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", 10, -106)
    note:SetPoint("RIGHT", -40, 0)
    note:SetJustifyH("LEFT")
    note:SetText(L.UPGRADEARROWS_PAGE_NOTE)

    -- That the arrows are an estimate, a paragraph of its own.
    local guide = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    guide:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -8)
    guide:SetPoint("RIGHT", -40, 0)
    guide:SetJustifyH("LEFT")
    guide:SetText(L.UPGRADEARROWS_PAGE_GUIDE)

    local scroll = Kit.NewScroll(frame)
    scroll:SetPoint("TOPLEFT", guide, "BOTTOMLEFT", -6, -8)
    scroll:SetPoint("BOTTOMRIGHT", -28, 8)
    local width = 560
    ui.content = Kit.NewStack(scroll, width, 2)
    scroll:SetScrollChild(ui.content)
    scroll:HookScript("OnSizeChanged", function(_, w)
        ui.content:SetWidth(w)
    end)

    for _, group in ipairs(GROUPS) do
        local stats = group[2]
        local header = newHeader(ui.content, group[1])
        Kit.AddEntry(ui.content, header, function()
            for _, stat in ipairs(stats) do
                if rowShown(stat) then
                    return true
                end
            end
            return false
        end, 8)
        for _, stat in ipairs(stats) do
            local row = newRow(ui.content, stat)
            ui.rows[stat] = row
            Kit.AddEntry(ui.content, row, function()
                return rowShown(stat)
            end)
        end
    end

    frame:HookScript("OnShow", function()
        editingClass = playerClass() -- back to your own class each time the page opens
        refresh()
    end)
    refresh()
end

ns.AddCommand("weights", "", L.UPGRADEARROWS_COMMAND, function()
    ns.OpenSettings(module.name)
end, "UpgradeArrows")
