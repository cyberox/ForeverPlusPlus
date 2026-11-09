-- The pieces our drawn Settings pages are made of: the Modules, Changelog and About pages, and a
-- tool page a module draws itself (`BuildPage`). Our own frames from Blizzard's templates and art
-- (the Settings panel's title, minimal checkboxes, sidebar highlight and search box), so a drawn
-- page looks like Blizzard's own and nothing of Blizzard's pooled Settings rows is touched.
local _, ns = ...

local ipairs, max = ipairs, math.max
local CreateFrame = CreateFrame
local GameTooltip = GameTooltip
local hasTemplate, hasAtlas = ns.Frames.HasTemplate, ns.Frames.HasAtlas

local Kit = {}
ns.SettingsKit = Kit

local LIST_LEFT, LIST_ROW = 7, 20 -- a split page's list, and its rows

-- Module categories ---------------------------------------------------------------------------
-- The Modules page's groups: a module's `category` and its label, in the order their labels sort
-- in the player's language, with Other last. A module without one goes under Other. Here rather
-- than in Settings, so a module that lists modules by category (the Minimap Button's quick
-- toggles) groups them the same way.
local L = ns.L
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
table.sort(CATEGORIES, function(a, b) return string.lower(a[2]) < string.lower(b[2]) end)
CATEGORIES[#CATEGORIES + 1] = { "other", L.CATEGORY_OTHER }
local CATEGORY_NAMES, CATEGORY_RANKS = {}, {} -- by `category`: its label, its place in that order
for i, group in ipairs(CATEGORIES) do
    CATEGORY_NAMES[group[1]] = group[2]
    CATEGORY_RANKS[group[1]] = i
end
---Each category as { key, label }, in the Modules page's order.
Kit.CATEGORIES = CATEGORIES
Kit.CATEGORY_NAMES, Kit.CATEGORY_RANKS = CATEGORY_NAMES, CATEGORY_RANKS

---A module's category key, "other" when it has none of the list.
---@param module table
---@return string
function Kit.CategoryOf(module)
    return CATEGORY_NAMES[module.category] and module.category or "other"
end

---Puts a page's title and the divider under it at the top of a drawn page, like Blizzard's own
---Settings pages.
---@param frame table the page
---@param text string
---@return table title the title's font string, for a note beside it
function Kit.AddPageTitle(frame, text)
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightHuge")
    title:SetPoint("TOPLEFT", 7, -22)
    title:SetText(text)
    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetAtlas("Options_HorizontalDivider", true)
    divider:SetPoint("TOP", 0, -50)
    return title
end

---A scrolling area for a drawn page. Probe: falls back to the older template if Mainline's (the
---thin scroll bar) isn't on this client.
---@param parent table
---@return table scroll
function Kit.NewScroll(parent)
    local template = "ScrollFrameTemplate"
    if not hasTemplate(template) then
        template = "UIPanelScrollFrameTemplate"
    end
    return CreateFrame("ScrollFrame", nil, parent, template)
end

---A tooltip like Blizzard's settings tooltips: a white title, and gold text under it.
---@param owner table
---@param title string
---@param text? string
function Kit.ShowTooltip(owner, title, text)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(title, 1, 1, 1)
    if text and text ~= "" then
        local gold = NORMAL_FONT_COLOR
        GameTooltip:AddLine(text, gold.r, gold.g, gold.b, true)
    end
    GameTooltip:Show()
end

---Hides the tooltip if `owner` is the one showing it.
---@param owner table
function Kit.HideTooltip(owner)
    if GameTooltip:GetOwner() == owner then
        GameTooltip:Hide()
    end
end

---The tooltip a row shows over itself and its controls (`...`), as Blizzard's settings rows do.
---@param row table
---@param title string
---@param text? string nothing shows without it
function Kit.AddTooltip(row, title, text, ...)
    if not text or text == "" then
        return
    end
    local function enter()
        Kit.ShowTooltip(row, title, text)
    end
    local function leave()
        Kit.HideTooltip(row)
    end
    for _, frame in ipairs({ row, ... }) do
        frame:HookScript("OnEnter", enter)
        frame:HookScript("OnLeave", leave)
    end
end

---A checkbox like the Settings panel's (its minimal art), calling `onClick(checked)`. Probe: the
---art is Mainline's; without it, the older gold check.
---@param parent table
---@param size number
---@param onClick fun(checked: boolean)
---@return table box
function Kit.NewCheckbox(parent, size, onClick)
    local box
    if hasAtlas("checkbox-minimal") then
        box = CreateFrame("CheckButton", nil, parent)
        box:SetSize(size, size)
        box:SetNormalAtlas("checkbox-minimal")
        box:SetPushedAtlas("checkbox-minimal")
        local check = box:CreateTexture(nil, "ARTWORK")
        check:SetAtlas("checkmark-minimal")
        check:SetAllPoints()
        box:SetCheckedTexture(check)
        local grey = box:CreateTexture(nil, "ARTWORK")
        grey:SetAtlas("checkmark-minimal-disabled")
        grey:SetAllPoints()
        box:SetDisabledCheckedTexture(grey)
    else
        box = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        box:SetSize(size, size)
    end
    box:SetScript("OnClick", function(self)
        local checked = self:GetChecked() and true or false
        if PlaySound and SOUNDKIT then
            PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
                or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        end
        onClick(checked)
    end)
    return box
end

---A small checkbox with `text` after it, its right edge `anchor`'s left, at the top of a page:
---the Modules page's New and the Changelog's By Module. Clicking the word clicks the box, like
---Blizzard's checkboxes with a label.
---@param frame table the page
---@param anchor table what it sits left of
---@param text string
---@param onClick fun(checked: boolean)
---@return table box
function Kit.AddLabeledCheck(frame, anchor, text, onClick)
    local box = Kit.NewCheckbox(frame, 22, onClick)
    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetText(text)
    label:SetPoint("RIGHT", anchor, "LEFT", -12, 0)
    box:SetPoint("RIGHT", label, "LEFT", -2, 0)
    box:SetHitRectInsets(0, -(ns.Text.Width(label) + 2), 0, 0)
    return box
end

---A button from Blizzard's panel button template, 22 high, calling `fn()`.
---@param parent table
---@param text string
---@param width number
---@param fn fun()
---@return table button
function Kit.NewButton(parent, text, width, fn)
    return ns.Frames.Button(parent, text, width, fn)
end

---The undo arrow at the right end of a row, `size` square, calling `onClick()` with the checkbox
---sound: like the undo buttons on Blizzard's Talents and Transmog windows, pressed in a pixel
---while enabled. The caller adds its tooltip. Probe: the atlases are Mainline's; without one, nil.
---@param row table
---@param size number
---@param onClick fun()
---@return table? button
---@return table? icon
function Kit.NewResetButton(row, size, onClick)
    local atlas = ns.Frames.FirstAtlas("common-icon-undo", "talents-button-undo")
    if not atlas then
        return nil
    end
    local button = CreateFrame("Button", nil, row)
    button:SetSize(size, size)
    button:SetPoint("RIGHT", -2, 0)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAtlas(atlas)
    icon:SetSize(16, 16)
    icon:SetPoint("CENTER")
    button:SetHighlightAtlas(atlas, "ADD")
    button:GetHighlightTexture():SetAllPoints(icon)
    button:SetScript("OnMouseDown", function(self)
        if self:IsEnabled() then
            icon:SetPoint("CENTER", 1, -1)
        end
    end)
    button:SetScript("OnMouseUp", function() icon:SetPoint("CENTER") end)
    button:SetScript("OnClick", function()
        if PlaySound and SOUNDKIT then
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        end
        onClick()
    end)
    return button, icon
end

-- Stacks ----------------------------------------------------------------------------------------
-- A stack is a frame whose entries ({ frame, shown, gap }) sit one under the other, `top` down
-- from its top, each only while its `shown()` is true. A split page's list is one, and so are the
-- Modules page's rows on the right.

---@param parent table
---@param width number
---@param gap number the space between entries, unless an entry gives its own
---@return table stack
function Kit.NewStack(parent, width, gap)
    local stack = CreateFrame("Frame", nil, parent)
    stack:SetWidth(width)
    stack.entries, stack.gap, stack.top, stack.bottom = {}, gap, 0, 0
    return stack
end

---@param stack table
---@param frame table
---@param shown? fun(): boolean always shown without it
---@param gap? number the space above it
function Kit.AddEntry(stack, frame, shown, gap)
    stack.entries[#stack.entries + 1] = { frame = frame, shown = shown, gap = gap }
end

---Shows and places a stack's entries, and sizes the stack to them.
---@param stack table
function Kit.Layout(stack)
    local y, any = -stack.top, false
    for _, entry in ipairs(stack.entries) do
        local shown = not entry.shown or entry.shown() and true or false
        entry.frame:SetShown(shown)
        if shown then
            if any then
                y = y - (entry.gap or stack.gap)
            end
            entry.frame:ClearAllPoints()
            entry.frame:SetPoint("TOPLEFT", 0, y)
            y = y - entry.frame:GetHeight()
            any = true
        end
    end
    stack:SetHeight(max(-y + stack.bottom, 1))
end

-- Split pages ------------------------------------------------------------------------------------
-- The Modules and Changelog pages, and Console Variables: under the title, a narrow list on the
-- left with rows like the Settings sidebar's, a faint gold line, and a pane on the right for what's
-- selected, each side scrolling on its own.

---A list `listWidth` wide and a pane right of it and its scroll bar, as `split.listScroll` and
---`split.list` (a stack), and `split.pane` and `split.paneContent` (`split.paneWidth` wide). With
---`scrollBox`, the pane is a WowScrollBoxList instead, with `split.scrollBar` and no paneContent,
---for a page with too many rows to make a frame for each.
---@param frame table the page
---@param listWidth number
---@param scrollBox? boolean
---@return table split
function Kit.NewSplit(frame, listWidth, scrollBox)
    local width = frame:GetWidth()
    width = width > 0 and width or 615
    local paneLeft = LIST_LEFT + listWidth + 41
    local split = {}

    local list = Kit.NewScroll(frame)
    list:SetPoint("TOPLEFT", LIST_LEFT, -60)
    list:SetPoint("BOTTOMLEFT", LIST_LEFT, 8)
    list:SetWidth(listWidth)
    split.listScroll = list
    split.list = Kit.NewStack(list, listWidth, 2)
    split.list.bottom = 8
    list:SetScrollChild(split.list)

    local line = frame:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, 0.25)
    line:SetWidth(1)
    line:SetPoint("TOPLEFT", paneLeft - 12, -66)
    line:SetPoint("BOTTOMLEFT", paneLeft - 12, 14)

    local pane
    if scrollBox then
        pane = CreateFrame("Frame", nil, frame, "WowScrollBoxList")
        split.scrollBar = CreateFrame("EventFrame", nil, frame, "MinimalScrollBar")
        split.scrollBar:SetPoint("TOPLEFT", pane, "TOPRIGHT", 8, 0)
        split.scrollBar:SetPoint("BOTTOMLEFT", pane, "BOTTOMRIGHT", 8, 0)
    else
        pane = Kit.NewScroll(frame)
    end
    pane:SetPoint("TOPLEFT", paneLeft, -60)
    pane:SetPoint("BOTTOMRIGHT", -32, 8)
    split.pane, split.paneWidth = pane, width - paneLeft - 32
    if not scrollBox then
        split.paneContent = CreateFrame("Frame", nil, pane)
        split.paneContent:SetWidth(split.paneWidth)
        pane:SetScrollChild(split.paneContent)
    end
    return split
end

---Blizzard's sidebar highlight while a list row is selected or under the mouse. Call it on every
---row after the selection changes.
---@param row table from NewListButton
function Kit.Paint(row)
    local atlas
    if row.isSelected() then
        atlas = "Options_List_Active"
    elseif row.over then
        atlas = "Options_List_Hover"
    end
    if atlas and hasAtlas(atlas) then
        row.highlight:SetAtlas(atlas)
        row.highlight:Show()
    else
        row.highlight:Hide()
    end
end

---Lights a list row while the mouse is over it, or over a control in it that takes the mouse.
---@param row table from NewListButton
---@param over boolean
function Kit.Hover(row, over)
    row.over = over
    Kit.Paint(row)
end

---A row of a split page's list, lit while `isSelected()` is true and under the mouse.
---@param list table the split's list
---@param isSelected fun(): boolean
---@return table row
function Kit.NewListButton(list, isSelected)
    local row = CreateFrame("Button", nil, list)
    row:SetSize(list:GetWidth(), LIST_ROW)
    row.isSelected = isSelected
    row.highlight = row:CreateTexture(nil, "BACKGROUND")
    row.highlight:SetAllPoints()
    row:SetScript("OnEnter", function() Kit.Hover(row, true) end)
    row:SetScript("OnLeave", function() Kit.Hover(row, false) end)
    return row
end

---A split page's list row in grey for when it lists nothing, with its `text` set by the page.
---@param list table the split's list
---@param width number
---@return table row
function Kit.NewEmptyRow(list, width)
    local empty = CreateFrame("Frame", nil, list)
    empty:SetSize(width, 40)
    empty.text = empty:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    empty.text:SetPoint("TOPLEFT", 2, -4)
    empty.text:SetWidth(width - 4)
    empty.text:SetJustifyH("LEFT")
    return empty
end

---A search box at the top of a page we draw, left of `anchor` (its Defaults button) or at the top
---right without one, with `instructions` in gray while it's empty. It calls `onChange(text)` with
---the text, trimmed, as it's typed. Blizzard's own search, at the top left of the panel, finds
---settings across every addon, not what our pages list. Probe: SearchBoxTemplate is Mainline's.
---@param frame table the page
---@param anchor? table
---@param instructions string
---@param onChange fun(text: string)
---@return table? box nil without the template
function Kit.AddSearchBox(frame, anchor, instructions, onChange)
    if not hasTemplate("SearchBoxTemplate") then
        return
    end
    local box = CreateFrame("EditBox", nil, frame, "SearchBoxTemplate")
    box:SetSize(200, 20)
    if anchor then
        box:SetPoint("RIGHT", anchor, "LEFT", -12, 0)
    else
        box:SetPoint("TOPRIGHT", -12, -19) -- where the Defaults button would be
    end
    box:SetAutoFocus(false)
    if box.Instructions then
        box.Instructions:SetText(instructions)
    end
    -- After the template's own OnTextChanged, which shows the clear button and the gray text.
    box:HookScript("OnTextChanged", function(self)
        onChange(strtrim(self:GetText()))
    end)
    return box
end
