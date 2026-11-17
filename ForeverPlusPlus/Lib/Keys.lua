-- The modifier key a module lets the player hold to skip what it does (Auto Quest, Auto Gossip,
-- Auto Repair, Auto Sell Junk, Auto Release), to let something through (Skip Cinematics), to
-- pick another action (Minimap Button, World Map's Zone Info), or to drag (Movable Windows), so
-- each offers the same choices under the same names.
local _, ns = ...

local type = type
local IsShiftKeyDown, IsControlKeyDown, IsAltKeyDown = IsShiftKeyDown, IsControlKeyDown, IsAltKeyDown
local L = ns.L

local Keys = {}
ns.Keys = Keys

-- Key, then name, as a dropdown's `choices` take them.
Keys.CHOICES = {
    { "shift", L.KEY_SHIFT },
    { "ctrl", L.KEY_CTRL },
    { "alt", L.KEY_ALT },
    { "none", L.KEY_NONE },
}

local DOWN = { shift = IsShiftKeyDown, ctrl = IsControlKeyDown, alt = IsAltKeyDown }

local padIndex = {} -- a controller button's name -> its place in the state's buttons, or false

---Whether a controller button is down right now, by its name ("PAD4" is Y, the top face button;
---"PADLTRIGGER"), with the controller interface on. A plain read of the controller's state
---(C_GamePad.GetDeviceMappedState), so it works where the game hands the button to nothing of
---ours: Y over a talent of Talent Planner's (seen in game 2026-11-16). For a press, the caller
---compares with the last look.
---@param button string
---@return boolean
function Keys.PadDown(button)
    local pad = ns.Menus.GamepadUI() and C_GamePad
    if not (pad and pad.GetDeviceMappedState and pad.ButtonBindingToIndex) then
        return false
    end
    local index = padIndex[button]
    if index == nil then
        index = pad.ButtonBindingToIndex(button)
        index = index and index + 1 or false -- that index counts from 0, the state's table from 1
        padIndex[button] = index
    end
    local state = index and pad.GetDeviceMappedState()
    return state and state.buttons and state.buttons[index] and true or false
end

---Whether a trigger is held with the controller interface on. Blizzard's own modifiers (which swap
---its action bars or start targeting while held: GamepadMode.IsHUDBindingModifierDown and
---IsTargetingModifierDown, HoldBindings.lua, build 70938) say so only out in the world: with the
---talent window open a held trigger wasn't reported (in game, 2026-11-16). So the triggers are
---also read themselves.
---@return boolean
function Keys.PadHeld()
    local mode = ns.Menus.GamepadUI() and _G.GamepadMode
    if not mode then
        return false
    end
    local hud, targeting = mode.IsHUDBindingModifierDown, mode.IsTargetingModifierDown
    return ns.IsTrue(hud and hud()) or ns.IsTrue(targeting and targeting())
        or Keys.PadDown("PADLTRIGGER") or Keys.PadDown("PADRTRIGGER")
end

---Whether `key` (a key of `Keys.CHOICES`) is held down. Always false for "none" or a key not
---listed. With the controller interface on there's no keyboard, so a held trigger stands in for
---whichever key is set.
---@param key string
---@return boolean
function Keys.IsDown(key)
    local down = DOWN[key]
    if down == nil then
        return false
    end
    return down() and true or Keys.PadHeld()
end

---Whether lines and details shown only while Shift is held show now: Shift, or always with the
---controller interface on, where nothing can be held over a tooltip.
---@return boolean
function Keys.Detail()
    return IsShiftKeyDown() and true or ns.Menus.GamepadUI()
end

---A dropdown option for the key setting `key` (such as "skipKey"); its default, such as "shift",
---goes in the module's defaults.
---@param key string the setting
---@param name string
---@param description string
---@param section? string
---@param changed? string the version it last changed in, for its NEW tag
---@return table option
function Keys.Option(key, name, description, section, changed)
    return { key = key, name = name, description = description, choices = Keys.CHOICES,
        section = section, changed = changed }
end

---Moves an old "hold Shift" checkbox setting of `saved[module]` to a key setting: Shift while it
---was on, None while it was off. For ns.Migrate.
---@param saved table every module's saved settings
---@param module string
---@param old string the checkbox's setting
---@param new string the key's setting
function Keys.MigrateShift(saved, module, old, new)
    local db = saved[module]
    if not (db and type(db[old]) == "boolean") then
        return
    end
    db[new] = db[old] and "shift" or "none"
    db[old] = nil
end
