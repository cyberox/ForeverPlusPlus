-- Menus: a context menu at the cursor. It's Blizzard's own (MenuUtil.CreateContextMenu), except
-- while the game shows its controller interface, when it's a plain list of our own instead.
--
-- Why: with the controller interface on, Blizzard's menu frame tells the controller's focus
-- manager it showed (MenuProxyMixin:OnShow fires "MenuProxy.OnShow", heard in
-- Blizzard_GamepadSharedUtility's FrameControlsManager.lua). Opened from addon code, that runs
-- tainted: the manager writes its own state (shownFrames, isUIFocused, the suspended frame) in
-- our name, SmartNavigation refuses ("Interface action failed because of an AddOn"), and from then
-- on Blizzard's own SetPreferredGamepadInteractTarget is blocked whenever the manager runs: on
-- Escape, opening chat, closing a menu (Cameron's taint.log, build 70888, 2026-11-14; Gethe
-- `forever` branch). A frame of our own never reaches the manager. Other Forever addons do the
-- same (WhatsTraining draws its own menus; read to learn how, none of its code is here).
--
-- A menu is described the way Blizzard's is, so one generator serves both:
-- `function(owner, root)` calling `root:CreateTitle`, `CreateDivider`, `CreateButton`,
-- `CreateCheckbox`, and `CreateRadio`, with a button's own Create* calls making its submenu, and
-- `SetTooltip` and `SetEnabled` on what they return. Anything else Blizzard's descriptions offer
-- (`SetScrollMode` and the rest) does nothing on ours.
--
-- Ours works with the mouse, and with a controller's own buttons while it's open: the D-pad
-- moves, A picks, B goes back. It costs nothing until a menu opens.
local _, ns = ...

local ipairs, type, setmetatable, rawget, unpack, max = ipairs, type, setmetatable, rawget, unpack, math.max
local CreateFrame, UIParent, GetCursorPosition, GameTooltip = CreateFrame, UIParent, GetCursorPosition, GameTooltip
local GetTime = GetTime
local _G = _G

local Menus = {}
ns.Menus = Menus

---Whether the game shows its controller interface. Probe: C_InputInterfaceStyle is Forever's
---(Blizzard_SharedXML's InputUtil.IsGamepadUIEnabled, Gethe `forever` branch).
---@return boolean
function Menus.GamepadUI()
    local C, types = _G.C_InputInterfaceStyle, _G.Enum and _G.Enum.InputDeviceInterfaceType
    if not (C and C.GetCurrentStyle and types and types.Gamepad) then
        return false
    end
    return ns.IsTrue(C.GetCurrentStyle() == types.Gamepad)
end

---A `module.notice` entry for a module whose Blizzard frame the controller interface hides (the
---usual action bars, stance bar, bag bar, and micro menu), shown only while it's on.
---@return table notice
function Menus.PadHidesNotice()
    return {
        text = ns.L.SETTINGS_CONTROLLER_HIDDEN, description = ns.L.SETTINGS_CONTROLLER_HIDDEN_DESC,
        shown = Menus.GamepadUI,
    }
end

-- The description ---------------------------------------------------------------------------------

-- What Blizzard's descriptions offer that ours has no use for: called, it does nothing.
local function nothing(self)
    return self
end

local Element = {}
local elementMeta = {
    __index = function(_, key)
        return Element[key] or nothing
    end,
}

-- Every field is set, to false when it has nothing, so reading one never falls through to
-- `nothing` above. `data` may be nil and is read with rawget.
local function add(parent, kind, text, fn, data, isSelected)
    local entry = setmetatable({
        kind = kind, text = text or "", fn = fn or false, data = data, isSelected = isSelected or false,
        tooltip = false, enabled = true, items = {},
    }, elementMeta)
    parent.items[#parent.items + 1] = entry
    return entry
end

function Element:CreateTitle(text)
    return add(self, "title", text)
end

function Element:CreateDivider()
    return add(self, "divider")
end

function Element:CreateButton(text, fn, data)
    return add(self, "button", text, fn, data)
end

function Element:CreateCheckbox(text, isSelected, fn, data)
    return add(self, "checkbox", text, fn, data, isSelected)
end

function Element:CreateRadio(text, isSelected, fn, data)
    return add(self, "radio", text, fn, data, isSelected)
end

function Element:SetTooltip(fn)
    self.tooltip = fn or false
end

function Element:SetEnabled(enabled)
    self.enabled = enabled
end

---A menu as our own plain description: `{ items = { entry, ... } }`, each entry
---`{ kind, text, fn, data, isSelected, tooltip, enabled, items }` with `kind` one of `"title"`,
---`"divider"`, `"button"`, `"checkbox"`, or `"radio"`, and `items` its submenu.
---@param generator fun(owner: any, root: table)
---@param owner any
---@return table root
function Menus.Describe(generator, owner)
    local root = setmetatable({ kind = "root", items = {} }, elementMeta)
    generator(owner, root)
    return root
end

---Whether an entry can be picked now: `SetEnabled` took a flag or a function of the entry.
---@param entry table
---@return boolean
function Menus.IsEnabled(entry)
    local enabled = entry.enabled
    if type(enabled) == "function" then
        enabled = enabled(entry)
    end
    return enabled and true or false
end

---Whether a checkbox or radio entry is ticked.
---@param entry table
---@return boolean
function Menus.IsSelected(entry)
    local isSelected = entry.isSelected
    return isSelected and isSelected(rawget(entry, "data")) and true or false
end

-- Our own list ------------------------------------------------------------------------------------

local ROW_HEIGHT, DIVIDER_HEIGHT = 20, 10
local PAD = 10 -- between the frame's edge and its rows
local MARK = 16 -- the tick's column, and the submenu arrow's
local MIN_WIDTH = 120
-- Blizzard's menu art, the first this client has (probed: names change between builds).
local TICK = { "common-dropdown-icon-checkmark-yellow", "checkmark-minimal", "common-icon-checkmark" }
local RADIO = { "common-dropdown-icon-radialtick-yellow", "common-dropdown-icon-checkmark-yellow", "checkmark-minimal" }
local ARROW = { "common-dropdown-icon-next", "common-icon-forwardarrow", "NPE_ArrowRight" }

local levels = {} -- depth -> its frame
local owner -- the frame the open menu belongs to, or nil while none is open
local afterPick -- called after each pick in the open menu (a dropdown's text follows it)
local radiosClose = false -- a dropdown's menu closes on a radio pick, as Blizzard's does
local closedOwner, closedAt -- the owner of the menu a click just closed, and when
local focus = { depth = 0, index = 0 } -- the row a controller is on

local close, fill

local function atlas(texture, names)
    local name = ns.Frames.FirstAtlas(unpack(names))
    if name then
        texture:SetAtlas(name, false)
    end
    return name ~= nil
end

local function pickable(entry)
    local kind = entry.kind
    return (kind == "button" or kind == "checkbox" or kind == "radio") and Menus.IsEnabled(entry)
end

-- A row's tick, color, and arrow as its entry stands now: a pick redraws these, never the rows.
local function paint(row)
    local entry = row.entry
    local kind = entry.kind
    local enabled = Menus.IsEnabled(entry)
    row.tick:SetShown((kind == "checkbox" or kind == "radio") and Menus.IsSelected(entry))
    row.arrow:SetShown(#entry.items > 0)
    if kind == "title" then
        row.text:SetFontObject("GameFontNormalSmall")
    else
        row.text:SetFontObject(enabled and "GameFontHighlightSmall" or "GameFontDisableSmall")
    end
    row:SetEnabled(pickable(entry))
end

local function repaint()
    for _, frame in ipairs(levels) do
        if frame:IsShown() then
            for i = 1, frame.count do
                paint(frame.rows[i])
            end
        end
    end
end

local function hideFrom(depth)
    for i = depth, #levels do
        levels[i]:Hide()
    end
    if GameTooltip:IsOwned(levels[1]) then
        GameTooltip:Hide()
    end
end

local function showTooltip(row)
    local entry = row.entry
    if entry.tooltip then
        GameTooltip:SetOwner(levels[1], "ANCHOR_NONE")
        GameTooltip:SetPoint("TOPLEFT", row, "TOPRIGHT", PAD, 0)
        entry.tooltip(GameTooltip, entry)
        GameTooltip:Show()
    elseif GameTooltip:IsOwned(levels[1]) then
        GameTooltip:Hide()
    end
end

-- The mouse or the controller came to a row: its submenu opens beside it, and any other closes.
local function enter(row)
    local frame = row:GetParent()
    local entry = row.entry
    if #entry.items > 0 and Menus.IsEnabled(entry) then
        fill(frame.depth + 1, entry, row)
    else
        hideFrom(frame.depth + 1)
    end
    showTooltip(row)
end

-- A pick. As Blizzard's menus do: a checkbox or radio stays open and redraws, a button closes
-- unless its function asks for a redraw (MenuResponse.Refresh), and a button that only holds a
-- submenu does nothing.
local function pick(row)
    local entry = row.entry
    if not pickable(entry) then
        return
    end
    local fn = entry.fn
    if not fn then
        return
    end
    local stays = entry.kind == "checkbox" or (entry.kind == "radio" and not radiosClose)
    local after = afterPick
    local response = fn(rawget(entry, "data"))
    local refresh = _G.MenuResponse and _G.MenuResponse.Refresh
    if response ~= nil then
        stays = refresh ~= nil and response == refresh
    end
    if after then
        after()
    end
    if not owner then
        return -- the pick closed it (its window went away)
    end
    if stays then
        repaint()
    else
        close()
    end
end

local function newRow(frame)
    local row = CreateFrame("Button", nil, frame)
    row:SetHeight(ROW_HEIGHT)
    row:SetHighlightTexture(ns.Frames.RowTexture(row, "HIGHLIGHT", "common-dropdown-highlight", 1, 1, 1, 0.12))
    row.tick = row:CreateTexture(nil, "ARTWORK")
    row.tick:SetSize(MARK - 4, MARK - 4)
    row.tick:SetPoint("LEFT", 0, 0)
    row.arrow = row:CreateTexture(nil, "ARTWORK")
    row.arrow:SetSize(MARK - 6, MARK - 6)
    row.arrow:SetPoint("RIGHT", 0, 0)
    if not atlas(row.arrow, ARROW) then
        row.arrow:SetColorTexture(1, 0.82, 0, 0.8)
    end
    row.line = row:CreateTexture(nil, "ARTWORK")
    row.line:SetColorTexture(1, 1, 1, 0.15)
    row.line:SetHeight(1)
    row.line:SetPoint("LEFT", 0, 0)
    row.line:SetPoint("RIGHT", 0, 0)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", MARK, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row:SetMotionScriptsWhileDisabled(true) -- a title under the mouse still closes another row's submenu
    row:SetScript("OnEnter", enter)
    row:SetScript("OnClick", pick)
    return row
end

-- The controller's buttons while a menu is open. Probe: the pad's names are Blizzard's bindings.
local function move(step)
    local frame = levels[focus.depth]
    if not (frame and frame:IsShown()) or frame.count == 0 then
        return
    end
    local index = focus.index
    for _ = 1, frame.count do
        index = (index - 1 + step) % frame.count + 1
        if pickable(frame.rows[index].entry) then
            break
        end
    end
    local old = frame.rows[focus.index]
    if old then
        old:UnlockHighlight()
    end
    focus.index = index
    local row = frame.rows[index]
    row:LockHighlight()
    enter(row)
end

local function focusOn(depth)
    local old = levels[focus.depth] and levels[focus.depth].rows[focus.index]
    if old then
        old:UnlockHighlight()
    end
    focus.depth, focus.index = depth, 0
    move(1)
end

local function onPadButton(_, button)
    local frame = levels[focus.depth]
    local row = frame and frame.rows[focus.index]
    if button == "PADDUP" then
        move(-1)
    elseif button == "PADDDOWN" then
        move(1)
    elseif button == "PADDRIGHT" or button == "PAD1" then
        if row and #row.entry.items > 0 and levels[focus.depth + 1] and levels[focus.depth + 1]:IsShown() then
            focusOn(focus.depth + 1)
        elseif row and button == "PAD1" then
            pick(row)
        end
    elseif button == "PADDLEFT" or button == "PAD2" then
        if focus.depth > 1 then
            -- Back to the row the submenu hangs from.
            hideFrom(focus.depth)
            focus.depth = focus.depth - 1
            focus.index = levels[focus.depth].openIndex or 1
            local back = levels[focus.depth].rows[focus.index]
            if back then
                back:LockHighlight()
            end
        elseif button == "PAD2" then
            close()
        end
    end
end

-- A click anywhere but on the menu closes it.
local function onMouseDown()
    for _, frame in ipairs(levels) do
        if frame:IsShown() and frame:IsMouseOver() then
            return
        end
    end
    -- A click on the dropdown it hangs from closes it; that click mustn't open it again.
    closedOwner, closedAt = owner, GetTime()
    close()
end

-- The owner went away (its window closed): so does the menu.
local function watchOwner()
    if owner and owner ~= UIParent and owner.IsVisible and not ns.IsTrue(owner:IsVisible()) then
        close()
    end
end

local function level(depth)
    local frame = levels[depth]
    if frame then
        return frame
    end
    local template = ns.Frames.HasTemplate("TooltipBackdropTemplate") and "TooltipBackdropTemplate" or nil
    frame = CreateFrame("Frame", nil, UIParent, template)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(100 + depth * 10)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:Hide()
    frame.depth, frame.rows, frame.count = depth, {}, 0
    if not template then
        local back = frame:CreateTexture(nil, "BACKGROUND")
        back:SetAllPoints()
        back:SetColorTexture(0.05, 0.05, 0.05, 0.95)
    end
    if depth == 1 then
        frame:SetScript("OnUpdate", watchOwner)
        if frame.EnableGamePadButton then
            frame:SetScript("OnGamePadButtonDown", onPadButton)
        end
    end
    levels[depth] = frame
    return frame
end

-- Lays a level's rows out from an entry's items and shows it: at `anchor` (a row, for a submenu,
-- or nil for the cursor).
function fill(depth, parent, anchor)
    local frame = level(depth)
    if frame:IsShown() and frame.parent == parent then
        return
    end
    hideFrom(depth)
    frame.parent = parent
    local width, y = MIN_WIDTH, -PAD
    for i, entry in ipairs(parent.items) do
        local row = frame.rows[i]
        if not row then
            row = newRow(frame)
            frame.rows[i] = row
        end
        row.entry = entry
        row:UnlockHighlight()
        local divider = entry.kind == "divider"
        row.line:SetShown(divider)
        row.text:SetText(entry.text)
        if entry.kind == "radio" then
            atlas(row.tick, RADIO)
        else
            atlas(row.tick, TICK)
        end
        paint(row)
        row:SetHeight(divider and DIVIDER_HEIGHT or ROW_HEIGHT)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", PAD, y)
        row:SetPoint("RIGHT", -PAD, 0)
        row:Show()
        y = y - row:GetHeight()
        width = max(width, row.text:GetStringWidth() + MARK * 2)
    end
    for i = #parent.items + 1, #frame.rows do
        frame.rows[i]:Hide()
    end
    frame.count = #parent.items
    frame:SetSize(width + PAD * 2, -y + PAD)
    frame:ClearAllPoints()
    if anchor and anchor.entry then
        -- A submenu: beside its row, on the left when the right has no room.
        local right = anchor:GetRight()
        local room = right and UIParent:GetWidth() - right or 0
        if room >= frame:GetWidth() then
            frame:SetPoint("TOPLEFT", anchor, "TOPRIGHT", PAD, PAD)
        else
            frame:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -PAD, PAD)
        end
        local above = levels[depth - 1]
        for i = 1, above.count do
            if above.rows[i] == anchor then
                above.openIndex = i
            end
        end
    elseif anchor and anchor.SetPoint then
        anchor:SetPoint(frame, true) -- Blizzard's AnchorMixin, as its own menus take
    else
        local scale = UIParent:GetEffectiveScale()
        local x, cursorY = GetCursorPosition()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, cursorY / scale)
    end
    frame:Show()
end

function close()
    if not owner then
        return
    end
    owner, afterPick, radiosClose = nil, nil, false
    ns.Off("GLOBAL_MOUSE_DOWN", onMouseDown)
    hideFrom(1)
    if levels[1].EnableGamePadButton then
        levels[1]:EnableGamePadButton(false)
    end
end

---Closes our own menu, if one is open.
function Menus.Close()
    close()
end

---Whether a menu can open: Blizzard's is there, or the controller interface is on and it's ours.
---@return boolean
function Menus.Available()
    return Menus.GamepadUI() or (_G.MenuUtil and _G.MenuUtil.CreateContextMenu) and true or false
end

---Opens a context menu at the cursor: Blizzard's, or our own list while the controller interface
---is on. `generator(owner, root)` describes it as Blizzard's menus are described. `anchor`, one of
---Blizzard's anchors (AnchorUtil.CreateAnchor), places our own somewhere else; Blizzard's own
---always opens at the cursor, so a caller that places that one opens it itself.
---@param menuOwner table? the frame it belongs to; it closes when that hides
---@param generator fun(owner: any, root: table)
---@param anchor table?
---@return boolean opened
function Menus.Open(menuOwner, generator, anchor)
    if not Menus.GamepadUI() then
        local util = _G.MenuUtil
        if not (util and util.CreateContextMenu) then
            return false
        end
        util.CreateContextMenu(menuOwner, generator)
        return true
    end
    close()
    local root = Menus.Describe(generator, menuOwner)
    if #root.items == 0 then
        return false
    end
    owner = menuOwner or UIParent
    fill(1, root, anchor)
    ns.On("GLOBAL_MOUSE_DOWN", onMouseDown)
    local first = levels[1]
    if first.EnableGamePadButton then
        first:EnableGamePadButton(true)
        focus.depth, focus.index = 1, 0
    end
    return true
end

---Gives one of Blizzard's dropdown buttons (a `DropdownButton` frame we made from
---`WowStyle1DropdownTemplate`) its menu, in place of calling its `SetupMenu`. The button, its text,
---and the mouse wheel stay Blizzard's; only opening changes: with the controller interface on, the
---list that drops down is our own. `OpenMenu` is replaced on our own frame, never on the mixin.
---@param dropdown table
---@param generator fun(owner: any, root: table)
function Menus.SetupDropdown(dropdown, generator)
    dropdown:SetupMenu(generator)
    local blizzardOpen = dropdown.OpenMenu
    dropdown.OpenMenu = function(self)
        if not Menus.GamepadUI() then
            return blizzardOpen(self)
        end
        if not self:IsEnabled() or (closedOwner == self and closedAt == GetTime()) then
            return
        end
        local util = _G.AnchorUtil
        Menus.Open(self, generator, util and util.CreateAnchor and util.CreateAnchor("TOPLEFT", self, "BOTTOMLEFT", 0, 0) or nil)
        if owner == self then
            radiosClose = true
            afterPick = function()
                self:GenerateMenu() -- its text follows the pick
            end
        end
    end
end
