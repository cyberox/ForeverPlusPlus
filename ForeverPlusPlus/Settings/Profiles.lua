-- The Profiles page, after the Modules entry in the sidebar: which profile this character uses and
-- which one new characters start on, at the top; under them the profiles in a list on the left,
-- with how many characters use each and a mark on this character's, and the selected one on the
-- right: its name, what it holds, who uses it, the preset it's based on (Based On), its buttons
-- (Use on This Character, Rename, Delete),
-- every character seen with a checkbox each (checked uses this profile), its Share buttons, and a
-- note on what a profile holds. Defaults on the Modules page resets the profile in use, so there
-- is no Reset here. Drawn from Lib/Profiles.lua each time something about the profiles changes.
local _, ns = ...

local ipairs, format, concat, max, pcall = ipairs, string.format, table.concat, math.max, pcall
local CreateFrame = CreateFrame
local L = ns.L
local S = ns.SettingsUI
local Kit = ns.SettingsKit
local Profiles = ns.Profiles
local Colors = ns.Colors

local LIST_WIDTH = 180
local TOP = 128 -- where the list and the pane start, under the two dropdown rows
local ROW = 26 -- a character's row

local page -- the page's parts, once it's built
local selectedID -- the profile shown on the right

-- A character's name in its class color.
local function colored(character)
    local color = Colors.ClassToken(character.class)
    return color and Colors.Text(color, character.name) or character.name
end

local function names(characters)
    local list = {}
    for i, character in ipairs(characters) do
        list[i] = colored(character)
    end
    return concat(list, ", ")
end

local function usedByText(users)
    return #users > 0 and format(L.PROFILES_USED_BY, names(users)) or L.PROFILES_UNUSED
end

-- A tooltip over `frame` (a button, enabled or not) from `get()`: its title and text.
local function addTooltip(frame, get)
    if frame.SetMotionScriptsWhileDisabled then
        frame:SetMotionScriptsWhileDisabled(true)
    end
    frame:HookScript("OnEnter", function(self)
        local title, text = get()
        Kit.ShowTooltip(self, title, text)
    end)
    frame:HookScript("OnLeave", Kit.HideTooltip)
end

-- Says so in chat when a switch waits for combat to end; one that happens now shows on the page.
local function switched(now, id)
    if now == false then
        ns.Print(format(L.PROFILES_AFTER_COMBAT, Profiles.Name(id)))
    end
end

-- Blizzard's menu dropdown of what `list()` gives, { value, text } each. Probe: Mainline's.
local function newDropdown(parent, width, list, get, set)
    if not WowStyle1DropdownMixin then
        return
    end
    local ok, dropdown = pcall(CreateFrame, "DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
    if not (ok and dropdown and dropdown.SetupMenu) then
        return
    end
    dropdown:SetWidth(width)
    dropdown:SetupMenu(function(_, root)
        for _, entry in ipairs(list()) do
            root:CreateRadio(entry[2], function(value)
                return get() == value
            end, function(value)
                set(value)
            end, entry[1])
        end
    end)
    return dropdown
end

-- Every profile, for a dropdown.
local function profileChoices()
    local list = {}
    for i, id in ipairs(Profiles.List()) do
        list[i] = { id, Profiles.Name(id) }
    end
    return list
end

local function newProfileDropdown(parent, get, set)
    return newDropdown(parent, 220, profileChoices, get, set)
end

-- The selected profile's preset (Lib/Presets.lua), "none" for none, for the Based On dropdown.
local NO_PRESET = "none"
local function presetChoices()
    local list = { { NO_PRESET, L.PROFILES_PRESET_NONE } }
    for _, name in ipairs(ns.Presets.List()) do
        list[#list + 1] = { name, ns.Presets.Title(name) }
    end
    return list
end

-- A gold label and a dropdown beside it, `y` down from the page's top.
local function addDropdownRow(frame, y, get, set, tooltip)
    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", 16, y)
    label:SetWidth(190)
    label:SetJustifyH("LEFT")
    local dropdown = newProfileDropdown(frame, get, set)
    if dropdown then
        dropdown:SetPoint("LEFT", label, "RIGHT", 14, 0)
        addTooltip(dropdown, tooltip)
    end
    return label, dropdown
end

local draw

-- New Profile: a name, then a copy of the selected profile, the defaults, or a preset (a button
-- each while they fit, else one that opens a menu of them).
local function newProfile()
    local from = selectedID
    ns.PromptName("PROFILES_NEW", L.PROFILES_NEW_ASK, "", function(name)
        local clean, why = Profiles.CheckName(name)
        if not clean then
            ns.Print(why)
            return
        end
        local fromName = Profiles.Name(from) or L.PROFILES_DEFAULT
        local function made(id, reason)
            if not id then
                ns.Print(reason)
                return
            end
            selectedID = id
            draw()
        end
        local buttons = {
            { text = format(L.PROFILES_COPY_OF, fromName), fn = function() made(Profiles.Create(clean, from)) end },
            { text = L.PROFILES_FROM_DEFAULTS, fn = function() made(Profiles.Create(clean)) end },
        }
        for _, button in ipairs(ns.Presets.Buttons(1, function(preset)
            made(Profiles.CreateFromPreset(clean, preset))
        end)) do
            buttons[#buttons + 1] = button
        end
        ns.ConfirmButtons("PROFILES_NEW_FROM", format(L.PROFILES_NEW_FROM, clean, fromName,
            ns.Presets.Mention()), buttons)
    end)
end

-- Import: paste, see what it holds, then add it as a new profile or put it over the selected one.
local function importProfile()
    local into = selectedID
    ns.Prompt("PROFILES_IMPORT", L.PROFILES_IMPORT_ASK, "", function(text)
        local profile, why = ns.ProfileShare.Import(text)
        if not profile then
            ns.Print(why)
            return
        end
        local intoName = Profiles.Name(into) or L.PROFILES_DEFAULT
        ns.ConfirmChoice("PROFILES_IMPORT_AS", format(L.PROFILES_IMPORT_FOUND, profile.name,
            profile.addon, profile.modulesOn, profile.changed), L.PROFILES_IMPORT_NEW, function()
            local id, reason = Profiles.CreateFrom(Profiles.FreeName(profile.name), profile.settings,
                profile.data, profile.preset)
            if not id then
                ns.Print(reason)
                return
            end
            selectedID = id
            ns.Print(format(L.PROFILES_IMPORT_DONE, Profiles.Name(id)))
            draw()
        end, format(L.PROFILES_IMPORT_REPLACE, intoName), function()
            switched(Profiles.Replace(into, profile.settings, profile.data, profile.preset), into)
        end)
    end, true)
end

-- One profile's row in the list: a mark on this character's, its name, and how many use it.
local function newListRow(list)
    local row = Kit.NewListButton(list, function() return false end)
    row.isSelected = function() return row.id ~= nil and row.id == selectedID end
    row.mark = row:CreateTexture(nil, "OVERLAY")
    row.mark:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    row.mark:SetSize(12, 12)
    row.mark:SetPoint("LEFT", 2, 0)
    row.count = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.count:SetPoint("RIGHT", -6, 0)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.text:SetPoint("LEFT", 16, 0)
    row.text:SetPoint("RIGHT", row.count, "LEFT", -4, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row:SetScript("OnClick", function()
        selectedID = row.id
        draw()
    end)
    row:HookScript("OnEnter", function(self)
        Kit.ShowTooltip(self, Profiles.Name(self.id) or "", usedByText(Profiles.Users(self.id)))
    end)
    row:HookScript("OnLeave", Kit.HideTooltip)
    Kit.AddEntry(list, row, function() return row.id ~= nil end)
    return row
end

-- A character's row: checked while it uses the selected profile. Checking moves it here and
-- unchecking sends it to Default; on Default a checked box can't be unchecked, since every
-- character uses a profile. Right-clicking another character forgets it.
local function newCharacterRow(parent, width)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(width, ROW)
    row:RegisterForClicks("RightButtonUp")
    local glow = row:CreateTexture(nil, "HIGHLIGHT")
    glow:SetAllPoints()
    glow:SetColorTexture(1, 1, 1, 0.07)
    row.box = Kit.NewCheckbox(row, ROW, function(checked)
        local character = row.character
        local now = Profiles.SetCharacter(character.key, checked and selectedID or Profiles.DEFAULT)
        if character.current then
            switched(now, checked and selectedID or Profiles.DEFAULT)
        end
        draw() -- puts the box back while a switch waits for combat
    end)
    row.box:SetPoint("LEFT", 0, 0)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetPoint("LEFT", row.box, "RIGHT", 4, 0)
    row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.detail:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
    row.where = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.where:SetPoint("RIGHT", -6, 0)
    local function tooltip()
        local character = row.character
        local here = character.profile == selectedID
        local text
        if here and selectedID == Profiles.DEFAULT then
            text = format(L.PROFILES_ON_DEFAULT_DESC, character.name)
        elseif here then
            text = format(L.PROFILES_UNCHECK_DESC, character.name)
        else
            text = format(L.PROFILES_CHECK_DESC, character.name, Profiles.Name(selectedID))
        end
        if not character.current then
            text = text .. "\n\n" .. L.PROFILES_FORGET_HINT
        end
        return character.name, text
    end
    addTooltip(row, tooltip)
    addTooltip(row.box, tooltip)
    row:SetScript("OnClick", function()
        local character = row.character
        if character and not character.current then
            ns.Confirm("PROFILES_FORGET", L.PROFILES_FORGET_ASK, function()
                Profiles.Forget(character.key)
            end, character.name)
        end
    end)
    return row
end

local function drawCharacter(row, character)
    row.character = character
    local here = character.profile == selectedID
    row.box:SetChecked(here)
    row.box:SetEnabled(not (here and selectedID == Profiles.DEFAULT))
    row.name:SetText(colored(character))
    local level = character.level and format(L.PROFILES_CHARACTER_LINE, character.level,
        ns.Players.ClassName(character.class) or "") or ""
    row.detail:SetText(level)
    if character.current and here then
        row.where:SetText(L.PROFILES_THIS_CHARACTER)
    elseif here then
        row.where:SetText("")
    else
        row.where:SetText(format(L.PROFILES_USES_OTHER, Profiles.Name(character.profile) or ""))
    end
end

-- A gold header in the pane with a faint line under it.
local function newHeader(parent, width, text)
    local header = CreateFrame("Frame", nil, parent)
    header:SetSize(width, 26)
    local label = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("BOTTOMLEFT", 0, 6)
    label:SetText(text)
    local line = header:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, 0.25)
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", 0, 0)
    return header
end

-- A row of buttons, each as wide as its text needs.
local function newButtonRow(parent, width, buttons)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(width, 22)
    local x = 0
    for _, info in ipairs(buttons) do
        local button = Kit.NewButton(frame, info.text, 40, info.fn)
        button:SetWidth(max(80, ns.Text.Width(button:GetFontString()) + 28))
        button:SetPoint("LEFT", x, 0)
        x = x + button:GetWidth() + 4
        if info.tooltip then
            addTooltip(button, info.tooltip)
        end
        info.button = button
    end
    return frame
end

-- A line of text in the pane that wraps, its frame as tall as the text.
local function newText(parent, width, font)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(width, 14)
    frame.text = frame:CreateFontString(nil, "OVERLAY", font)
    frame.text:SetPoint("TOPLEFT")
    frame.text:SetWidth(width)
    frame.text:SetJustifyH("LEFT")
    function frame.Set(_, text)
        frame.text:SetText(text)
        frame:SetHeight(max(14, frame.text:GetStringHeight()))
    end
    return frame
end

function draw()
    if not page then
        return
    end
    if not Profiles.Exists(selectedID) then
        selectedID = Profiles.Current()
    end
    local me = Profiles.Me()
    local current = Profiles.Current()
    page.mineLabel:SetText(format(L.PROFILES_USES, me and colored(me) or UnitName("player") or ""))
    for _, dropdown in ipairs(page.dropdowns) do
        dropdown:GenerateMenu()
    end

    -- The list.
    local ids = Profiles.List()
    for i, id in ipairs(ids) do
        local row = page.listRows[i] or newListRow(page.split.list)
        page.listRows[i] = row
        row.id = id
        row.text:SetText(Profiles.Name(id))
        row.count:SetText(#Profiles.Users(id))
        row.mark:SetShown(id == current)
    end
    for i = #ids + 1, #page.listRows do
        page.listRows[i].id = nil
    end
    Kit.Layout(page.split.list)
    for _, row in ipairs(page.listRows) do
        Kit.Paint(row)
    end

    -- The pane.
    local id, name = selectedID, Profiles.Name(selectedID)
    page.name:SetText(name)
    page.inUse:SetShown(id == current)
    local modulesOn, changed = Profiles.Summary(id)
    page.stats:Set(format(L.PROFILES_SUMMARY, modulesOn, changed) .. "\n" .. usedByText(Profiles.Users(id)))
    page.use.button:SetEnabled(id ~= current)
    page.rename.button:SetEnabled(id ~= Profiles.DEFAULT)
    page.delete.button:SetEnabled(id ~= Profiles.DEFAULT)
    local characters = Profiles.Characters()
    for i, character in ipairs(characters) do
        local row = page.characterRows[i]
        if not row then
            row = newCharacterRow(page.characters, page.width)
            row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW)
            page.characterRows[i] = row
        end
        drawCharacter(row, character)
        row:Show()
    end
    for i = #characters + 1, #page.characterRows do
        page.characterRows[i]:Hide()
    end
    page.characters:SetHeight(max(1, #characters * ROW))
    Kit.Layout(page.stack)
    page.split.paneContent:SetHeight(page.stack:GetHeight())
end
S.DrawProfiles = draw

function S.BuildProfiles(frame)
    Kit.AddPageTitle(frame, L.PROFILES)
    page = { listRows = {}, characterRows = {}, dropdowns = {} }

    local mineLabel, mine = addDropdownRow(frame, -66, Profiles.Current, function(id)
        switched(Profiles.Switch(id), id)
        draw()
    end, function()
        local me = Profiles.Me()
        return L.PROFILES_USES_TITLE, format(L.PROFILES_USES_DESC, me and me.name or "")
    end)
    page.mineLabel = mineLabel
    local newLabel, new = addDropdownRow(frame, -96, Profiles.NewCharacters, Profiles.SetNewCharacters,
        function() return L.PROFILES_NEW_CHARACTERS, L.PROFILES_NEW_CHARACTERS_DESC end)
    newLabel:SetText(L.PROFILES_NEW_CHARACTERS)
    page.dropdowns = { mine, new }

    local split = Kit.NewSplit(frame, LIST_WIDTH, nil, TOP)
    page.split = split
    split.listScroll:SetPoint("BOTTOMLEFT", 7, 38) -- room for New Profile under it
    local newButton = Kit.NewButton(frame, L.PROFILES_NEW, LIST_WIDTH, newProfile)
    newButton:SetPoint("BOTTOMLEFT", 7, 8)
    addTooltip(newButton, function() return L.PROFILES_NEW, format(L.PROFILES_NEW_DESC, ns.Presets.Mention()) end)

    local width = split.paneWidth
    page.width = width
    local content = split.paneContent
    local stack = Kit.NewStack(content, width, 6)
    stack:SetPoint("TOPLEFT")
    page.stack = stack

    local header = CreateFrame("Frame", nil, stack)
    header:SetSize(width, 20)
    page.name = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    page.name:SetPoint("LEFT")
    page.inUse = header:CreateFontString(nil, "OVERLAY", "GameFontGreenSmall")
    page.inUse:SetPoint("LEFT", page.name, "RIGHT", 10, 0)
    page.inUse:SetText(L.PROFILES_IN_USE)
    Kit.AddEntry(stack, header)

    page.stats = newText(stack, width, "GameFontDisable")
    Kit.AddEntry(stack, page.stats)

    -- Based On: the preset the selected profile follows for what it doesn't set itself, or None.
    local based = CreateFrame("Frame", nil, stack)
    based:SetSize(width, 26)
    local basedLabel = based:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    basedLabel:SetPoint("LEFT")
    basedLabel:SetText(L.PROFILES_PRESET)
    local preset = #ns.Presets.List() > 0 and newDropdown(based, 200, presetChoices, function()
        return Profiles.Preset(selectedID) or NO_PRESET
    end, function(value)
        local id = selectedID
        if Profiles.SetPreset(id, value ~= NO_PRESET and value or nil) == false then
            ns.Print(format(L.PROFILES_PRESET_AFTER_COMBAT, Profiles.Name(id)))
        end
        draw()
    end)
    if preset then
        preset:SetPoint("LEFT", basedLabel, "RIGHT", 14, 0)
        addTooltip(preset, function()
            return L.PROFILES_PRESET, format(L.PROFILES_PRESET_DESC, Profiles.Name(selectedID) or "")
        end)
        page.dropdowns[#page.dropdowns + 1] = preset
        Kit.AddEntry(stack, based, nil, 6)
    else
        based:Hide()
    end

    local function selectedName()
        return Profiles.Name(selectedID) or ""
    end
    local function always()
        return L.PROFILES_DEFAULT_ALWAYS
    end
    page.use = { text = L.PROFILES_USE, fn = function()
        switched(Profiles.Switch(selectedID), selectedID)
    end, tooltip = function()
        local me = Profiles.Me()
        return L.PROFILES_USE, format(L.PROFILES_USE_DESC, me and me.name or "", selectedName())
    end }
    page.rename = { text = L.PROFILES_RENAME, fn = function()
        local id = selectedID
        ns.PromptName("PROFILES_RENAME", format(L.PROFILES_RENAME_ASK, selectedName()), selectedName(),
            function(name)
                local ok, why = Profiles.Rename(id, name)
                if not ok then
                    ns.Print(why)
                end
            end)
    end, tooltip = function()
        return L.PROFILES_RENAME, selectedID == Profiles.DEFAULT and always() or format(L.PROFILES_RENAME_DESC, selectedName())
    end }
    page.delete = { text = L.PROFILES_DELETE, fn = function()
        local id = selectedID
        ns.Confirm("PROFILES_DELETE", L.PROFILES_DELETE_ASK, function()
            switched(Profiles.Delete(id), Profiles.DEFAULT)
        end, selectedName())
    end, tooltip = function()
        return L.PROFILES_DELETE, selectedID == Profiles.DEFAULT and always() or format(L.PROFILES_DELETE_DESC, selectedName())
    end }
    Kit.AddEntry(stack, newButtonRow(stack, width, { page.use, page.rename, page.delete }), nil, 10)

    Kit.AddEntry(stack, newHeader(stack, width, L.PROFILES_CHARACTERS_HEADER), nil, 10)
    page.characters = CreateFrame("Frame", nil, stack)
    page.characters:SetSize(width, 1)
    Kit.AddEntry(stack, page.characters, nil, 2)

    Kit.AddEntry(stack, newHeader(stack, width, L.PROFILES_SHARE), nil, 10)
    Kit.AddEntry(stack, newButtonRow(stack, width, {
        { text = L.PROFILES_EXPORT, fn = function()
            ns.Prompt("PROFILES_EXPORT", format(L.PROFILES_EXPORT_ASK, selectedName()),
                ns.ProfileShare.Export(selectedID), nil, true)
        end, tooltip = function()
            return L.PROFILES_EXPORT, format(L.PROFILES_EXPORT_DESC, selectedName())
        end },
        { text = L.PROFILES_IMPORT, fn = importProfile, tooltip = function()
            return L.PROFILES_IMPORT, format(L.PROFILES_IMPORT_DESC, selectedName())
        end },
    }), nil, 8)

    local note = newText(stack, width, "GameFontDisableSmall")
    note:Set(L.PROFILES_NOTE)
    Kit.AddEntry(stack, note, nil, 12)

    draw()
    frame:HookScript("OnShow", draw)
end

-- Anything about the profiles changing, or a module turned on or off (the counts), redraws it.
Profiles.OnChanged(function()
    draw()
end)
ns.OnModuleChanged(function()
    if page and page.stack:IsVisible() then
        draw()
    end
end)
