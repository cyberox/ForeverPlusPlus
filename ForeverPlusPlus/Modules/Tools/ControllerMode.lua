-- Controller Mode: a page under Forever++ in Settings that keeps a setup for the game's
-- controller interface and one for keyboard and mouse: a Forever++ profile, one of Blizzard's Edit
-- Mode layouts, and a set of addons each. When the character logs in on the other of the two, it
-- switches to that one's profile and layout, and asks to reload when the addons loaded aren't that
-- one's set. Nothing happens while the interface is the one it last set up for, so a profile or
-- layout picked by hand stays, and nothing asks to reload when the addons already match.
--
-- Its setups are kept for the account and not in a profile, since it changes the profile; only
-- whether it is on is a profile's, as for any module. So a profile it switches to has it turned
-- on, or it could never switch back. Which of the two it last set up for is kept for each
-- character. A setup with nothing chosen changes nothing, so it costs one check at login until
-- something is. Off by default: while it's off its page is gone and nothing is checked.
--
-- Forever only: the controller interface is this client's (Lib/Gamepad.lua).
local _, ns = ...

local ipairs, format, concat, next = ipairs, string.format, table.concat, next
local ReloadUI = ReloadUI

local L = ns.L
local Gamepad, Profiles, AddOns, EditMode = ns.Gamepad, ns.Profiles, ns.AddOns, ns.EditMode

local module = ns.NewModule("ControllerMode", L.CONTROLLERMODE_DESC, {
    enabled = false,
    -- What each interface uses, for the account: `profile` (a profile's id), `layout` (a key of
    -- EditMode.Layouts), and `addons` (a set of AddOns.States), each nil to leave it alone.
    modes = { gamepad = {}, mkb = {} },
    -- `mode`: the interface this character was last set up for. Data, for each character.
    applied = {},
})
module.perCharacter = { applied = true }
module.title = L.CONTROLLERMODE_TITLE
module.category = "system"
module.added = "1.9.0"

local MODES = {
    { key = "gamepad", name = L.CONTROLLERMODE_GAMEPAD },
    { key = "mkb", name = L.CONTROLLERMODE_MKB },
}
local NONE = "none" -- a dropdown's Don't Change
local MAX_NAMES = 6 -- addons named in the reload question before "and N more"

local page -- the page's parts, once it's built

---The interface the game shows now: "gamepad" or "mkb".
---@return string
local function current()
    return Gamepad.On() and "gamepad" or "mkb"
end

local function modeName(key)
    for _, mode in ipairs(MODES) do
        if mode.key == key then
            return mode.name
        end
    end
end

-- Addon names as one line: the first few, then how many more.
local function names(list)
    if #list <= MAX_NAMES then
        return concat(list, ", ")
    end
    return format(L.CONTROLLERMODE_AND_MORE, concat(list, ", ", 1, MAX_NAMES), #list - MAX_NAMES)
end

-- Asks to reload into a setup's addons. Nothing is turned on or off unless the player says yes.
local function askReload(mode, set, on, off)
    local lines = { format(L.CONTROLLERMODE_RELOAD, modeName(mode)) }
    if #on > 0 then
        lines[#lines + 1] = format(L.CONTROLLERMODE_RELOAD_ON, names(on))
    end
    if #off > 0 then
        lines[#lines + 1] = format(L.CONTROLLERMODE_RELOAD_OFF, names(off))
    end
    lines[#lines + 1] = L.CONTROLLERMODE_RELOAD_ASK
    -- The whole question is the %s, so an addon's name with a % in it can't break the popup.
    ns.Confirm("CONTROLLERMODE_RELOAD", "%s", function()
        AddOns.Apply(set)
        ReloadUI()
    end, concat(lines, "\n\n"))
end

local layoutsReady

---Switches to a setup: its profile and layout now (after combat, in combat), and its addons after
---a reload the player agrees to. True when anything had to change.
---@param mode string "gamepad" or "mkb"
---@return boolean changed
local function apply(mode)
    local setup = module.db.modes[mode]
    local changed = false
    local profile = setup.profile
    if profile and Profiles.Exists(profile) and Profiles.Current() ~= profile then
        Profiles.SwitchAndSay(profile)
        -- After the switch, which waits for combat too: on in the profile it switched to, or
        -- this character would stay on that profile whatever interface it logs in on next.
        ns.AfterCombat(function()
            if Profiles.Current() == profile and not module.enabled then
                ns.SetEnabled(module.name, true)
            end
        end)
        changed = true
    end
    if setup.layout then
        local layouts, active = EditMode.Layouts()
        if #layouts == 0 then
            -- Asked before the game has its layouts, at login: once more when it has.
            module:On("EDIT_MODE_LAYOUTS_UPDATED", layoutsReady)
        elseif active ~= setup.layout and EditMode.SetLayout(setup.layout) ~= nil then
            changed = true
        end
    end
    if setup.addons then
        local on, off = AddOns.Changes(setup.addons)
        if #on + #off > 0 then
            askReload(mode, setup.addons, on, off)
            changed = true
        end
    end
    return changed
end

-- The layouts came after the first look: the layout of the setup in use, this once.
function layoutsReady()
    module:Off("EDIT_MODE_LAYOUTS_UPDATED", layoutsReady)
    local layout = module.db.modes[current()].layout
    if layout then
        EditMode.SetLayout(layout)
    end
end

local checked = false -- once each time the interface loads

-- The game can't change interface without loading again, so one look as the character enters the
-- world is enough. Only a change of interface since the last look sets anything up.
local function onWorld()
    if checked then
        return
    end
    checked = true
    local mode = current()
    local applied = module.db.applied
    if applied.mode ~= mode then
        applied.mode = mode
        apply(mode)
    end
end

function module:OnEnable()
    self:On("PLAYER_ENTERING_WORLD", onWorld)
end

-- Turned on while playing, not at login: the interface in use counts as seen, so nothing is set
-- up at the next loading screen. Set Up Now does it when the player wants it.
ns.OnModuleChanged(function(name, key)
    if name == module.name and key == nil and module.enabled then
        checked = true
        module.db.applied.mode = current()
    end
end)

-- The page ----------------------------------------------------------------------------------------

local LABEL_WIDTH, DROPDOWN_WIDTH, ROW = 150, 240, 30

local function profileChoices()
    local list = { { NONE, L.CONTROLLERMODE_NO_CHANGE } }
    for _, id in ipairs(Profiles.List()) do
        list[#list + 1] = { id, Profiles.Name(id) }
    end
    return list
end

-- The layouts made for an interface: Blizzard offers a layout only on the one it was made for.
local function layoutChoices(mode)
    local list = { { NONE, L.CONTROLLERMODE_NO_CHANGE } }
    for _, layout in ipairs((EditMode.Layouts())) do
        if layout.key and layout.gamepad == (mode == "gamepad") then
            list[#list + 1] = { layout.key, layout.name }
        end
    end
    return list
end

local function addonsText(set)
    if not set then
        return L.CONTROLLERMODE_ADDONS_NONE
    end
    local on = 0
    for _, state in next, set do
        if state then
            on = on + 1
        end
    end
    return format(L.CONTROLLERMODE_ADDONS_SAVED, on)
end

local function refresh()
    if not page then
        return
    end
    page.now:SetText(format(L.CONTROLLERMODE_NOW, modeName(current())))
    for _, part in ipairs(page.modes) do
        local setup = module.db.modes[part.key]
        for _, dropdown in ipairs(part.dropdowns) do
            dropdown:GenerateMenu()
        end
        part.addons:SetText(addonsText(setup.addons))
        part.clear:SetEnabled(setup.addons ~= nil)
    end
end

local function label(frame, text, y, template)
    local line = frame:CreateFontString(nil, "OVERLAY", template or "GameFontNormal")
    line:SetPoint("TOPLEFT", 16, y)
    line:SetJustifyH("LEFT")
    line:SetText(text)
    return line
end

-- A gold label with a dropdown beside it, saving `field` of a setup (nil for Don't Change).
local function dropdownRow(frame, part, y, text, tooltip, list, field)
    local Kit = ns.SettingsKit
    local line = label(frame, text, y)
    line:SetWidth(LABEL_WIDTH)
    local dropdown = Kit.NewDropdown(frame, DROPDOWN_WIDTH, list, function()
        return module.db.modes[part.key][field] or NONE
    end, function(value)
        module.db.modes[part.key][field] = value ~= NONE and value or nil
    end)
    if dropdown then
        dropdown:SetPoint("LEFT", line, "RIGHT", 14, 0)
        Kit.AddTooltip(dropdown, text, tooltip)
        part.dropdowns[#part.dropdowns + 1] = dropdown
    end
end

-- One interface's setup: a header, its profile, its layout, and its addons.
local function buildMode(frame, mode, y)
    local Kit = ns.SettingsKit
    local part = { key = mode.key, dropdowns = {} }
    label(frame, mode.name, y, "GameFontHighlightLarge")
    y = y - 28
    dropdownRow(frame, part, y, L.CONTROLLERMODE_PROFILE, L.CONTROLLERMODE_PROFILE_DESC, profileChoices, "profile")
    y = y - ROW
    dropdownRow(frame, part, y, L.CONTROLLERMODE_LAYOUT, L.CONTROLLERMODE_LAYOUT_DESC, function()
        return layoutChoices(mode.key)
    end, "layout")
    y = y - ROW
    local line = label(frame, L.CONTROLLERMODE_ADDONS, y)
    line:SetWidth(LABEL_WIDTH)
    part.addons = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    part.addons:SetPoint("LEFT", line, "RIGHT", 14, 0)
    part.addons:SetWidth(DROPDOWN_WIDTH)
    part.addons:SetJustifyH("LEFT")
    local save = Kit.NewButton(frame, L.CONTROLLERMODE_ADDONS_SAVE, 130, function()
        module.db.modes[mode.key].addons = AddOns.States()
        refresh()
    end)
    save:SetPoint("LEFT", part.addons, "RIGHT", 10, 0)
    Kit.AddTooltip(save, L.CONTROLLERMODE_ADDONS_SAVE, L.CONTROLLERMODE_ADDONS_SAVE_DESC)
    part.clear = Kit.NewButton(frame, L.CONTROLLERMODE_ADDONS_CLEAR, 70, function()
        module.db.modes[mode.key].addons = nil
        refresh()
    end)
    part.clear:SetPoint("LEFT", save, "RIGHT", 6, 0)
    Kit.AddTooltip(part.clear, L.CONTROLLERMODE_ADDONS_CLEAR, L.CONTROLLERMODE_ADDONS_CLEAR_DESC)
    page.modes[#page.modes + 1] = part
    return y - ROW - 14
end

---Draws the page the first time it's shown (called by Settings/Settings.lua).
---@param frame table the empty page
function module:BuildPage(frame)
    local Kit = ns.SettingsKit
    page = { modes = {} }
    Kit.AddPageTitle(frame, module.title)

    -- Sets up for the interface in use now, where the Defaults button would be: for a setup just
    -- chosen, which otherwise waits for the next change of interface.
    local now = Kit.NewButton(frame, L.CONTROLLERMODE_APPLY, 110, function()
        local mode = current()
        module.db.applied.mode = mode
        if not apply(mode) then
            ns.Print(format(L.CONTROLLERMODE_NOTHING, modeName(mode)))
        end
        refresh()
    end)
    now:SetPoint("TOPRIGHT", -12, -19)
    Kit.AddTooltip(now, L.CONTROLLERMODE_APPLY, L.CONTROLLERMODE_APPLY_DESC)

    local note = label(frame, L.CONTROLLERMODE_NOTE, -62, "GameFontHighlight")
    note:SetPoint("RIGHT", -40, 0)
    note:SetWordWrap(true)
    page.now = label(frame, "", -112, "GameFontDisable")

    local y = -144
    for _, mode in ipairs(MODES) do
        y = buildMode(frame, mode, y)
    end

    frame:HookScript("OnShow", refresh)
    Profiles.OnChanged(refresh)
    refresh()
end
