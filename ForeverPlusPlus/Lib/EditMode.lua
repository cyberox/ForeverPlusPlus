-- Edit Mode for our own frames, made to look and work like Blizzard's own system frames: while
-- the player is in Blizzard's Edit Mode, a frame registered here gets the same blue selection box,
-- which turns gold when clicked. It drags with snapping to the screen's middle and edges and to
-- our other frames, and opens a small settings dialog and a right-click menu (scale, the frame's
-- own settings, and reset position) like Blizzard's; while the dialog is up, the arrow keys nudge
-- the frame a pixel (ten with Shift). A module's options marked `editMode = true` are those
-- settings (RegisterModule), shown here instead of on the Modules page. Edit Mode has no way for an addon to add a frame to its layouts (that needs its
-- protected system code), so the position is the module's, not part of an Edit Mode layout.
-- Nothing is hooked until a module registers a frame.
local _, ns = ...

local pairs, ipairs, type, pcall, setmetatable = pairs, ipairs, type, pcall, setmetatable
local abs, min, max = math.abs, math.min, math.max
local format = string.format
local CreateFrame, UIParent, hooksecurefunc = CreateFrame, UIParent, hooksecurefunc
local GetCursorPosition, Screenshot, wipe = GetCursorPosition, Screenshot, wipe
local InCombatLockdown = InCombatLockdown

local L = ns.L
local call = ns.Call

local EditMode = {}
ns.EditMode = EditMode

local SNAP = 10 -- how close, in pixels, before a frame snaps to a line
local GOLD = { NORMAL_FONT_COLOR:GetRGB() }

local registered = {} -- frame -> { label, onMove, onChange, scale, reset, selection }
-- Frames taken off (Unregister) -> their info, so registering one again reuses its selection box
-- instead of making another each time its module turns on.
local unregistered = setmetatable({}, { __mode = "k" })
local hooked = false
local selected -- the frame of ours that is selected, if any

---Whether Edit Mode is open. Probe: EditModeManagerFrame is Mainline's.
---@return boolean
function EditMode.IsActive()
    return EditModeManagerFrame and EditModeManagerFrame:IsShown() or false
end

-- Positions ---------------------------------------------------------------------------------------

-- Keeps a frame's box on the screen.
local function clamp(center, length, size)
    return max(length / 2, min(size - length / 2, center))
end

---Puts `frame` at an offset from the center of the screen, in screen units, whatever its own
---scale is, kept inside the screen like Blizzard's own frames. Modules use this for a frame that
---takes its scale itself. The offset given isn't changed, so a window made smaller for a while
---doesn't lose where the player put the frame.
---@param frame table
---@param x number
---@param y number
function EditMode.Place(frame, x, y)
    local scale = frame:GetScale()
    local ratio = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    x = clamp(x + width / 2, frame:GetWidth() * ratio, width) - width / 2
    y = clamp(y + height / 2, frame:GetHeight() * ratio, height) - height / 2
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", x / scale, y / scale)
end

-- A frame's box in screen units: center, width, and height. Nil until the frame has a place.
local function box(frame)
    local cx, cy = frame:GetCenter()
    if not cx then
        return
    end
    local ratio = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return cx * ratio, cy * ratio, frame:GetWidth() * ratio, frame:GetHeight() * ratio
end

-- Moves `frame` to a center in screen units and hands the offset to its module to save.
local function moveTo(frame, info, cx, cy)
    local ux, uy = UIParent:GetCenter()
    local x, y = cx - ux, cy - uy
    EditMode.Place(frame, x, y)
    info.onMove(x, y)
end

-- Snapping ------------------------------------------------------------------------------------------

local guides -- the two lines drawn where a frame snaps: { vertical, horizontal }

local function guide(index)
    guides = guides or {}
    if not guides[index] then
        local line = UIParent:CreateTexture(nil, "OVERLAY")
        line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.8)
        line:SetDrawLayer("OVERLAY", 7)
        line:Hide()
        guides[index] = line
    end
    return guides[index]
end

local function hideGuides()
    if guides then
        for _, line in pairs(guides) do
            line:Hide()
        end
    end
end

-- The lines on one axis to snap to: the screen's edges and middle, and every other frame of ours
-- that is showing. `axis` is 1 for x, 2 for y.
local function lines(frame, axis)
    local size = axis == 1 and UIParent:GetWidth() or UIParent:GetHeight()
    local list = { 0, size / 2, size }
    for other in pairs(registered) do
        if other ~= frame and other:IsShown() then
            local cx, cy, w, h = box(other)
            if cx then
                local center, length = axis == 1 and cx or cy, axis == 1 and w or h
                list[#list + 1] = center - length / 2
                list[#list + 1] = center
                list[#list + 1] = center + length / 2
            end
        end
    end
    return list
end

-- Where a dragged frame's center goes on one axis: pulled onto the nearest line within reach, for
-- its near edge, middle, or far edge. Second value is the line it snapped to, if any.
local function snap(frame, center, length, axis)
    local best, bestLine
    for _, line in pairs(lines(frame, axis)) do
        for _, edge in pairs({ -length / 2, 0, length / 2 }) do
            local off = line - (center + edge)
            if abs(off) <= SNAP and (not best or abs(off) < abs(best)) then
                best, bestLine = off, line
            end
        end
    end
    if best then
        return center + best, bestLine
    end
    return center
end

local function showGuides(vertical, horizontal)
    if vertical then
        local line = guide(1)
        line:ClearAllPoints()
        line:SetPoint("TOP", UIParent, "BOTTOMLEFT", vertical, UIParent:GetHeight())
        line:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", vertical, 0)
        line:SetWidth(2)
        line:Show()
    elseif guides and guides[1] then
        guides[1]:Hide()
    end
    if horizontal then
        local line = guide(2)
        line:ClearAllPoints()
        line:SetPoint("LEFT", UIParent, "BOTTOMLEFT", 0, horizontal)
        line:SetPoint("RIGHT", UIParent, "BOTTOMRIGHT", 0, horizontal)
        line:SetHeight(2)
        line:Show()
    elseif guides and guides[2] then
        guides[2]:Hide()
    end
end

-- The drag: follows the cursor, keeping the spot that was grabbed under it, snapping as it goes.
local function dragUpdate(selection)
    local frame = selection:GetParent()
    local info = registered[frame]
    if not info or not info.grab then
        return
    end
    local mx, my = GetCursorPosition()
    local ratio = UIParent:GetEffectiveScale()
    local _, _, width, height = box(frame)
    if not width then
        return
    end
    local cx, vertical = snap(frame, mx / ratio + info.grab[1], width, 1)
    local cy, horizontal = snap(frame, my / ratio + info.grab[2], height, 2)
    cx = clamp(cx, width, UIParent:GetWidth())
    cy = clamp(cy, height, UIParent:GetHeight())
    moveTo(frame, info, cx, cy)
    showGuides(vertical, horizontal)
end

local function dragStart(frame, info)
    local cx, cy = box(frame)
    if not cx then
        return
    end
    local mx, my = GetCursorPosition()
    local ratio = UIParent:GetEffectiveScale()
    info.grab = { cx - mx / ratio, cy - my / ratio }
    info.selection:SetScript("OnUpdate", dragUpdate)
end

local function dragStop(frame, info)
    info.grab = nil
    info.selection:SetScript("OnUpdate", nil)
    hideGuides()
    EditMode.Refresh()
end

-- The selection box --------------------------------------------------------------------------------

-- Blizzard's two looks for a frame in Edit Mode: blue while it can be picked, gold once picked.
-- Its layout is a local in its own file, so the same pieces are laid out here, from its atlases
-- (named for the look). Without those atlases a plain tint stands in.
local KITS = { [false] = "editmode-actionbar-highlight", [true] = "editmode-actionbar-selected" }
local LAYOUT = {
    TopRightCorner = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = 8, y = 8 },
    TopLeftCorner = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = -8, y = 8 },
    BottomLeftCorner = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = -8, y = -8 },
    BottomRightCorner = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = 8, y = -8 },
    TopEdge = { atlas = "_%s-NineSlice-EdgeTop" },
    BottomEdge = { atlas = "_%s-NineSlice-EdgeBottom" },
    LeftEdge = { atlas = "!%s-NineSlice-EdgeLeft" },
    RightEdge = { atlas = "!%s-NineSlice-EdgeRight" },
    Center = { layer = "BORDER", atlas = "%s-NineSlice-Center", x = -8, y = 8, x1 = 8, y1 = -8 },
}
local KIT_PARTS = { "Corner", "Center" }

-- Whether a look's atlases are there (the corners and the fill; the edges follow them).
local function hasKit(kit)
    if not (NineSliceUtil and NineSliceUtil.ApplyLayout) then
        return false
    end
    for _, part in pairs(KIT_PARTS) do
        if not ns.Frames.HasAtlas(kit .. "-NineSlice-" .. part) then
            return false
        end
    end
    return true
end

-- Blizzard's boxes say "Click To Edit" while the mouse is over them, and the frame's name for as
-- long as one is picked.
local function showHint(selection, isSelected)
    selection.hint:SetText(isSelected and selection.info.label or L.EDITMODE_CLICK_TO_EDIT)
    selection.hint:SetShown(selection.hovered or isSelected or false)
end

local function look(selection, isSelected)
    showHint(selection, isSelected)
    local kit = KITS[isSelected]
    if hasKit(kit) then
        NineSliceUtil.ApplyLayout(selection, LAYOUT, kit)
        selection.tint:Hide()
    else
        if isSelected then
            selection.tint:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.3)
        else
            selection.tint:SetColorTexture(0.2, 0.5, 1, 0.3)
        end
        selection.tint:Show()
    end
end

local pick, deselect, refreshDialog

-- A setting's value as text: a slider's `format` is a pattern ("%d%%") or a function.
local function valueText(setting, value)
    local fmt = setting.format
    if type(fmt) == "function" then
        return fmt(value)
    end
    return format(fmt or "%d", value)
end

-- A frame's own settings in its right-click menu, after the scale: a dropdown's or a slider's
-- values as a submenu of choices, a checkbox as one.
local function addMenuSettings(root, info)
    for _, setting in ipairs(info.settings or {}) do
        if setting.kind == "checkbox" then
            root:CreateCheckbox(setting.name, function() return setting.get() and true or false end,
                function()
                    call(setting.set, not setting.get())
                    EditMode.Refresh()
                end)
        else
            local sub = root:CreateButton(setting.name)
            local function add(label, value)
                sub:CreateRadio(label, function() return setting.get() == value end, function()
                    call(setting.set, value)
                    EditMode.Refresh()
                end)
            end
            if setting.kind == "dropdown" then
                for _, choice in ipairs(setting.choices) do
                    add(choice[2], choice[1])
                end
            else
                for value = setting.min, setting.max, setting.step do
                    add(valueText(setting, value), value)
                end
            end
        end
    end
end

local function newSelection(frame, info)
    local selection = CreateFrame("Frame", nil, frame)
    selection:SetAllPoints(frame)
    selection:SetFrameLevel(frame:GetFrameLevel() + 10)
    selection:EnableMouse(true)
    selection:RegisterForDrag("LeftButton")
    selection.info = info
    selection.hint = selection:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    selection.hint:SetPoint("CENTER")
    selection.tint = selection:CreateTexture(nil, "BACKGROUND")
    selection.tint:SetAllPoints()
    selection.tint:Hide()
    look(selection, false)
    -- Blizzard's Edit Mode loads after us, so its art isn't there yet when a module turns on: draw
    -- the box again each time it shows.
    selection:SetScript("OnShow", function(self)
        self.hovered = false
        look(self, selected == frame)
    end)
    selection:SetScript("OnEnter", function(self)
        self.hovered = true
        showHint(self, selected == frame)
    end)
    selection:SetScript("OnLeave", function(self)
        self.hovered = false
        showHint(self, selected == frame)
    end)
    selection:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then
            pick(frame)
        end
    end)
    -- Right-click, as on Blizzard's frames: a menu with the scale, the frame's settings, and reset.
    selection:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" and MenuUtil and MenuUtil.CreateContextMenu then
            pick(frame)
            MenuUtil.CreateContextMenu(self, function(_, root)
                root:CreateTitle(info.label)
                local scale = info.scale
                if scale then
                    local sub = root:CreateButton(L.EDITMODE_SCALE)
                    for value = scale.min, scale.max, scale.step do
                        sub:CreateRadio(format(scale.format or "%d%%", value),
                            function() return scale.get() == value end,
                            function()
                                scale.set(value)
                                EditMode.Refresh()
                            end)
                    end
                end
                addMenuSettings(root, info)
                if info.reset then
                    root:CreateButton(L.EDITMODE_RESET_POSITION, function() call(info.reset) end)
                end
            end)
        end
    end)
    selection:SetScript("OnDragStart", function() pick(frame) dragStart(frame, info) end)
    selection:SetScript("OnDragStop", function() dragStop(frame, info) end)
    selection:Hide()
    return selection
end

-- The settings dialog -----------------------------------------------------------------------------

local dialog

-- The keys held while the dialog is up, for Shift: the dialog keeps every key, as Blizzard's does.
local downKeys = {}
local NUDGE = { UP = { 0, 1 }, DOWN = { 0, -1 }, LEFT = { -1, 0 }, RIGHT = { 1, 0 } }

-- An arrow key moves the selected frame a pixel, or ten with Shift, as Blizzard's frames do.
local function nudge(key)
    local frame = selected
    local info = frame and registered[frame]
    local step = NUDGE[key]
    if not (info and step) then
        return
    end
    local cx, cy, width, height = box(frame)
    if not cx then
        return
    end
    local amount = (downKeys.LSHIFT or downKeys.RSHIFT) and 10 or 1
    moveTo(frame, info, clamp(cx + step[1] * amount, width, UIParent:GetWidth()),
        clamp(cy + step[2] * amount, height, UIParent:GetHeight()))
end

local function newSlider(parent)
    local ok, slider = pcall(CreateFrame, "Slider", nil, parent, "MinimalSliderWithSteppersTemplate")
    if ok and slider and slider.Init and slider.RegisterCallback and MinimalSliderWithSteppersMixin then
        return slider
    end
end

local function newDialog()
    local frame = ns.Frames.TemplateBox(UIParent, "DialogBorderTranslucentTemplate")
    frame:SetFrameStrata("DIALOG")
    -- Wide enough for the slider's steppers and its value label at the right, with the same room
    -- at the right edge as the Scale label has at the left (20).
    frame:SetSize(380, 130)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    -- Like Blizzard's settings dialog, this one takes the keyboard while a frame is selected and
    -- keeps every key: the arrows nudge, Escape lets go, and Print Screen still takes a picture.
    -- No key goes on to the game, so nothing changes keyboard propagation.
    frame:EnableKeyboard(true)
    frame:SetScript("OnKeyDown", function(_, key)
        downKeys[key] = true
        if key == "PRINTSCREEN" then
            Screenshot()
        elseif key == "ESCAPE" then
            deselect()
        else
            nudge(key)
        end
    end)
    frame:SetScript("OnKeyUp", function(_, key)
        downKeys[key] = nil
    end)
    frame:SetScript("OnHide", function()
        wipe(downKeys)
    end)

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    frame.title:SetPoint("TOP", 0, -15)

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)
    close:SetScript("OnClick", function() deselect() end)

    frame.scaleLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.scaleLabel:SetPoint("TOPLEFT", 20, -50)
    frame.scaleLabel:SetText(L.EDITMODE_SCALE)
    frame.slider = newSlider(frame)
    if frame.slider then
        frame.slider:SetPoint("LEFT", frame.scaleLabel, "LEFT", 90, 0)
        frame.slider:SetWidth(200)
        frame.slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged,
            function(_, value)
                local info = selected and registered[selected]
                if info and info.scale and not frame.refreshing then
                    call(info.scale.set, value)
                    -- A frame that changes size changes what it snaps against.
                    EditMode.Refresh()
                end
            end, frame)
    end

    frame.reset = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.reset:SetSize(200, 24)
    frame.reset:SetText(L.EDITMODE_RESET_POSITION)
    frame.reset:SetScript("OnClick", function()
        local info = selected and registered[selected]
        if info and info.reset then
            call(info.reset)
        end
    end)
    frame:Hide()
    return frame
end

local settingRows = {} -- every frame's setting rows, all on the one dialog; the selected one's show
local ROW_HEIGHT, ROW_STEP = 30, 36

-- The slider's value label at its right, in the setting's own format.
local function sliderLabels(setting)
    local formatter = CreateMinimalSliderFormatter and MinimalSliderWithSteppersMixin.Label
        and CreateMinimalSliderFormatter(MinimalSliderWithSteppersMixin.Label.Right,
            function(value) return valueText(setting, value) end)
    return formatter and { [MinimalSliderWithSteppersMixin.Label.Right] = formatter } or nil
end

-- A row of the dialog for one of a frame's settings: its name at the left and its control where
-- the scale slider is, or a checkbox with its name after it. `row.update` shows the value now.
local function newSettingRow(setting)
    local row = CreateFrame("Frame", nil, dialog)
    row:SetSize(340, ROW_HEIGHT)
    row.update = function() end
    if setting.kind == "checkbox" then
        local box = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        box:SetSize(28, 28)
        box:SetPoint("LEFT", -4, 0)
        local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        text:SetPoint("LEFT", box, "RIGHT", 2, 0)
        text:SetText(setting.name)
        box:SetScript("OnClick", function(self)
            call(setting.set, self:GetChecked() and true or false)
            EditMode.Refresh()
        end)
        row.update = function() box:SetChecked(setting.get() and true or false) end
        return row
    end
    local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT")
    label:SetText(setting.name)
    if setting.kind == "dropdown" then
        local ok, dropdown = pcall(CreateFrame, "DropdownButton", nil, row, "WowStyle1DropdownTemplate")
        if ok and dropdown and dropdown.SetupMenu then
            dropdown:SetWidth(200)
            dropdown:SetPoint("LEFT", label, "LEFT", 90, 0)
            dropdown:SetupMenu(function(_, root)
                for _, choice in ipairs(setting.choices) do
                    root:CreateRadio(choice[2], function() return setting.get() == choice[1] end, function()
                        call(setting.set, choice[1])
                        EditMode.Refresh()
                    end)
                end
            end)
            row.update = function() dropdown:GenerateMenu() end
        end
        return row
    end
    local slider = newSlider(row)
    if slider then
        slider:SetPoint("LEFT", label, "LEFT", 90, 0)
        slider:SetWidth(200)
        slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
            if not dialog.refreshing then
                call(setting.set, value)
                EditMode.Refresh()
            end
        end, row)
        row.update = function()
            slider:Init(setting.get(), setting.min, setting.max, (setting.max - setting.min) / setting.step,
                sliderLabels(setting))
        end
    end
    return row
end

-- Sets the dialog up for the selected frame: its name, its scale slider if it has one, its own
-- settings, and a reset button if it has one; and puts it beside the frame, on whichever side has
-- more room.
function refreshDialog()
    local frame = selected
    local info = frame and registered[frame]
    if not info then
        if dialog then
            dialog:Hide()
        end
        return
    end
    dialog = dialog or newDialog()
    dialog.title:SetText(info.label)
    local height = 50
    local scale = info.scale
    local showSlider = scale and dialog.slider
    dialog.scaleLabel:SetShown(showSlider and true or false)
    if dialog.slider then
        dialog.slider:SetShown(showSlider and true or false)
    end
    if showSlider then
        dialog.refreshing = true
        local steps = (scale.max - scale.min) / scale.step
        local formatter = CreateMinimalSliderFormatter and MinimalSliderWithSteppersMixin.Label
            and CreateMinimalSliderFormatter(MinimalSliderWithSteppersMixin.Label.Right,
                function(value) return format(scale.format or "%d%%", value) end)
        dialog.slider:Init(scale.get(), scale.min, scale.max, steps,
            formatter and { [MinimalSliderWithSteppersMixin.Label.Right] = formatter } or nil)
        dialog.refreshing = false
        height = height + 40
    end
    -- Only other frames' rows hide: hiding a row while its slider is dragged (each change refreshes
    -- the dialog) would drop the drag.
    local mine = {}
    for _, row in ipairs(info.rows or {}) do
        mine[row] = true
    end
    for _, row in ipairs(settingRows) do
        if not mine[row] then
            row:Hide()
        end
    end
    if info.settings then
        info.rows = info.rows or {}
        dialog.refreshing = true
        for i, setting in ipairs(info.settings) do
            local row = info.rows[i]
            if not row then
                row = newSettingRow(setting)
                info.rows[i] = row
                settingRows[#settingRows + 1] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 20, -(height - 8))
            call(row.update)
            row:Show()
            height = height + ROW_STEP
        end
        dialog.refreshing = false
    end
    dialog.reset:SetShown(info.reset ~= nil)
    if info.reset then
        dialog.reset:ClearAllPoints()
        dialog.reset:SetPoint("TOP", 0, -height)
        height = height + 34
    end
    dialog:SetHeight(height + 20)
    -- Beside the frame on the side of the screen with room, and above it when it fills the width.
    local cx, cy, width = box(frame)
    dialog:ClearAllPoints()
    if cx then
        local left = cx - width / 2
        local right = UIParent:GetWidth() - (cx + width / 2)
        if left >= dialog:GetWidth() + 10 or right >= dialog:GetWidth() + 10 then
            if right >= left then
                dialog:SetPoint("LEFT", frame, "RIGHT", 10, 0)
            else
                dialog:SetPoint("RIGHT", frame, "LEFT", -10, 0)
            end
        elseif cy > UIParent:GetHeight() / 2 then
            dialog:SetPoint("TOP", frame, "BOTTOM", 0, -10)
        else
            dialog:SetPoint("BOTTOM", frame, "TOP", 0, 10)
        end
    else
        dialog:SetPoint("CENTER")
    end
    dialog:Show()
end

---Redraws the settings dialog for the selected frame, after its scale or place changed.
function EditMode.Refresh()
    if selected then
        refreshDialog()
    end
end

-- Selecting ---------------------------------------------------------------------------------------

local selecting = false -- true while we ask Blizzard's own dialog to close

function deselect()
    if selected then
        local info = registered[selected]
        selected = nil
        if info then
            info.selection:SetScript("OnUpdate", nil)
            look(info.selection, false)
        end
    end
    hideGuides()
    refreshDialog()
end

function pick(frame)
    if selected == frame then
        return
    end
    deselect()
    local info = registered[frame]
    if not info then
        return
    end
    selected = frame
    -- Only one frame is selected at a time, so Blizzard's own selection and dialog go. Never in
    -- combat: ClearSelectedSystem runs through a secure delegate only out of combat; in combat it
    -- clears and highlights Blizzard's frames in our (tainted) call, which the client blocks
    -- (PlayerFrame:SetClampRectInsets) and which leaves their Edit Mode state tainted after
    -- (Gethe `forever` branch, EditModeManager.lua:762, checked 2026-11-04). Blizzard's selection
    -- then stays until the player picks something else.
    if EditModeManagerFrame and EditModeManagerFrame.ClearSelectedSystem and not InCombatLockdown() then
        selecting = true
        pcall(EditModeManagerFrame.ClearSelectedSystem, EditModeManagerFrame)
        selecting = false
    end
    look(info.selection, true)
    refreshDialog()
end

local function setActive(active)
    if not active then
        deselect()
    end
    for _, info in pairs(registered) do
        info.selection:SetShown(active)
        if info.onChange then
            call(info.onChange, active)
        end
    end
end

local function install()
    if hooked or not EditModeManagerFrame then
        return
    end
    hooked = true
    hooksecurefunc(EditModeManagerFrame, "EnterEditMode", function() setActive(true) end)
    hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function() setActive(false) end)
    -- Picking one of Blizzard's frames lets go of ours.
    for _, name in pairs({ "SelectSystem", "SetSelectedSystem" }) do
        if type(EditModeManagerFrame[name]) == "function" then
            hooksecurefunc(EditModeManagerFrame, name, function()
                if not selecting then
                    deselect()
                end
            end)
        end
    end
end

-- Registering -------------------------------------------------------------------------------------

---Makes `frame` selectable and draggable in Edit Mode, like Blizzard's own frames. It is placed
---from an offset from the center of the screen (`EditMode.Place`), and `onMove` gets the new offset
---when it moves.
---@param frame table
---@param label string the dialog's title and the right-click menu's
---@param onMove fun(x: number, y: number)
---@param options? { onChange: fun(active: boolean)?, scale: { min: number, max: number, step: number, format: string?, get: fun(): number, set: fun(value: number) }?, reset: fun()?, settings: table[]? }
--- onChange is called when Edit Mode opens or closes, and now if it's open. scale gives the
--- dialog a scale slider; reset gives it a Reset To Default Position button. settings are the
--- frame's own, in the dialog under the scale and in the right-click menu: each { name, kind =
--- "dropdown" (with choices, { value, label } each) or "slider" (with min, max, step, and format,
--- a pattern or a function) or "checkbox", get = fun(): any, set = fun(value) }.
function EditMode.Register(frame, label, onMove, options)
    options = options or {}
    local wasRegistered = registered[frame] ~= nil
    local info = registered[frame] or unregistered[frame] or {}
    info.label, info.onMove, info.onChange = label, onMove, options.onChange
    info.scale, info.reset = options.scale, options.reset
    if info.settings ~= options.settings then
        info.settings, info.rows = options.settings, nil
    end
    if wasRegistered then
        return
    end
    unregistered[frame] = nil
    -- Blizzard's Edit Mode frames stay on screen, also when the game window shrinks.
    frame:SetClampedToScreen(true)
    info.selection = info.selection or newSelection(frame, info)
    registered[frame] = info
    install()
    if EditMode.IsActive() then
        info.selection:Show()
        if info.onChange then
            call(info.onChange, true)
        end
    end
end

-- A module's options marked `editMode = true` as the frame's settings: a dropdown for `choices`, a
-- slider for `min`, a checkbox otherwise. Changing one goes through ns.SetOption, so the module
-- hears of it in OnOptionChanged as from the Settings page. Made once per module.
local moduleSettings = setmetatable({}, { __mode = "k" })

local function settingsOf(module)
    if moduleSettings[module] then
        return moduleSettings[module]
    end
    local list = {}
    for _, option in ipairs(module.options or {}) do
        if option.editMode then
            local key = option.key
            list[#list + 1] = {
                name = option.name,
                kind = option.choices and "dropdown" or option.min and "slider" or "checkbox",
                choices = option.choices,
                min = option.min, max = option.max, step = option.step, format = option.format,
                get = function() return module.db[key] end,
                set = function(value) ns.SetOption(module.name, key, value) end,
            }
        end
    end
    moduleSettings[module] = #list > 0 and list or false
    return moduleSettings[module]
end

---`EditMode.Register` for a module's frame placed from its own settings: the offset in
---`module.db.x` and `y`, Reset To Default Position back to the module's defaults, a 50% to 200%
---scale slider for `module.db.scale`, and the module's options marked `editMode = true`. `apply`
---puts the frame where the settings now say.
---@param module table
---@param frame table
---@param label string
---@param apply fun()
---@param onChange? fun(active: boolean)
function EditMode.RegisterModule(module, frame, label, apply, onChange)
    EditMode.Register(frame, label, function(x, y)
        module.db.x, module.db.y = x, y
    end, {
        onChange = onChange,
        settings = settingsOf(module) or nil,
        reset = function()
            module.db.x, module.db.y = nil, nil -- forgotten: the default spot, today's or a later one
            apply()
        end,
        scale = {
            min = 50, max = 200, step = 10, format = "%d%%",
            get = function() return module.db.scale end,
            set = function(value)
                module.db.scale = value
                apply()
            end,
        },
    })
end

---Takes the selection box off a frame, for a module turning off.
---@param frame table
function EditMode.Unregister(frame)
    local info = registered[frame]
    if not info then
        return
    end
    if selected == frame then
        deselect()
    end
    registered[frame] = nil
    unregistered[frame] = info
    info.selection:Hide()
    if info.onChange then
        call(info.onChange, false)
    end
end
