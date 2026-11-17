-- Gamepad: the game's controller interface. Whether it's on, the notices of a module it hides or
-- limits, its buttons by where they sit, reading one straight from the controller, a press of
-- one, how the player's controller labels it, and a click hint written for it.
--
-- The buttons are named by where they sit, never by a letter: "A" or "Y" is another button on
-- another controller.
local _, ns = ...

local type, setmetatable = type, setmetatable
local _G = _G

local Gamepad = {}
ns.Gamepad = Gamepad

-- The game's names for the controller's buttons, by where they sit.
Gamepad.BUTTON = {
    FACE_BOTTOM = "PAD1",
    FACE_RIGHT = "PAD2",
    FACE_LEFT = "PAD3",
    FACE_TOP = "PAD4",
    DPAD_UP = "PADDUP",
    DPAD_DOWN = "PADDDOWN",
    DPAD_LEFT = "PADDLEFT",
    DPAD_RIGHT = "PADDRIGHT",
    RIGHT_STICK = "PADRSTICK", -- pressed
    LEFT_TRIGGER = "PADLTRIGGER",
    RIGHT_TRIGGER = "PADRTRIGGER",
}
local BUTTON = Gamepad.BUTTON

---Whether the game shows its controller interface. Probe: C_InputInterfaceStyle is Forever's
---(Blizzard_SharedXML's InputUtil.IsGamepadUIEnabled, Gethe `forever` branch).
---@return boolean
function Gamepad.On()
    local C, types = _G.C_InputInterfaceStyle, _G.Enum and _G.Enum.InputDeviceInterfaceType
    if not (C and C.GetCurrentStyle and types and types.Gamepad) then
        return false
    end
    return ns.IsTrue(C.GetCurrentStyle() == types.Gamepad)
end

---A `module.notice` entry for a module whose Blizzard frame the controller interface hides (the
---usual action bars, stance bar, bag bar, and micro menu), shown only while it's on.
---@return table notice
function Gamepad.HidesNotice()
    return {
        text = ns.L.SETTINGS_CONTROLLER_HIDDEN, description = ns.L.SETTINGS_CONTROLLER_HIDDEN_DESC,
        shown = Gamepad.On,
    }
end

---A `module.notice` entry for a module that needs a mouse click, a drag, a held key, or a window
---the controller's cursor can't reach, so some or all of it does nothing with the controller
---interface on. Shown only while it's on.
---@return table notice
function Gamepad.LimitedNotice()
    return {
        text = ns.L.SETTINGS_CONTROLLER_LIMITED, description = ns.L.SETTINGS_CONTROLLER_LIMITED_DESC,
        shown = Gamepad.On,
    }
end

local padIndex = {} -- a controller button's name -> its place in the state's buttons, or false

---Whether a controller button is down right now, by its name (`Gamepad.BUTTON.FACE_TOP`, the top
---face button; `LEFT_TRIGGER`), with the controller interface on. A plain read of the controller's
---state (C_GamePad.GetDeviceMappedState), so it works where the game hands the button to nothing
---of ours: the top face button over a talent of Talent Planner's (seen in game 2026-11-16). For a
---press, see `Gamepad.Press`.
---@param button string
---@return boolean
function Gamepad.Down(button)
    local pad = Gamepad.On() and C_GamePad
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

local Press = {}
Press.__index = Press

---Whether the button was pressed since the last look: down now and not at the last look. True
---once a press, however long it's held. Look every frame, so a short press isn't missed.
---@return boolean
function Press:Fired()
    local down = Gamepad.Down(self.button)
    local fired = down and not self.was
    self.was = down
    return fired
end

---Starts over, as if the button was last seen `held` (by default, as it is now), so a button
---already held as the caller starts watching isn't a press.
---@param held? boolean
function Press:Reset(held)
    if held == nil then
        held = Gamepad.Down(self.button)
    end
    self.was = held and true or false
end

---Watches one button for presses: `:Fired()` each frame, `:Reset()` where watching starts.
---@param button string its name, as `Gamepad.Down` takes it
---@param held? boolean whether to count it as held before the first look (false by default)
---@return table press
function Gamepad.Press(button, held)
    return setmetatable({ button = button, was = held and true or false }, Press)
end

-- What a button is called where the game can't say, as on an Xbox controller.
local PAD_NAMES = {
    [BUTTON.FACE_BOTTOM] = "A", [BUTTON.FACE_RIGHT] = "B", [BUTTON.FACE_LEFT] = "X",
    [BUTTON.FACE_TOP] = "Y", [BUTTON.RIGHT_STICK] = "R3",
}

---A controller button as the player's own controller shows it: the game's small icon for it (a
---letter, a PlayStation shape, a Steam glyph), which Blizzard's own prompts use, for a hint or a
---label of ours. Never write "A" or "Y" in text: they're other buttons on another controller.
---@param button string its name, as `Gamepad.Down` takes it
---@return string label
function Gamepad.Label(button)
    local getText = _G.GetBindingText
    local text = getText and getText(button, "KEY_", true) -- abbreviated: the small icon
    if type(text) == "string" and text ~= "" and text ~= button then
        return text
    end
    return PAD_NAMES[button] or button
end

---A click hint for the controller interface: with it on, the click named at its start gives way
---to the button that does it there, as the player's controller shows it ("<Click to see its map>"
---becomes "<(the button) to see its map>"). Up to the hint's first " to ", so English, and the
---hint comes back as written where that doesn't fit or the controller interface is off.
---@param text string the hint, as written for the mouse
---@param button? string the button that does it, the bottom face button by default
---@return string hint
function Gamepad.Hint(text, button)
    if not Gamepad.On() then
        return text
    end
    local rest = text:match("^<.- to (.+)$")
    return rest and ("<" .. Gamepad.Label(button or BUTTON.FACE_BOTTOM) .. " to " .. rest) or text
end

---Whether a trigger is held with the controller interface on. Blizzard's own modifiers (which swap
---its action bars or start targeting while held: GamepadMode.IsHUDBindingModifierDown and
---IsTargetingModifierDown, HoldBindings.lua, build 70938) say so only out in the world: with the
---talent window open a held trigger wasn't reported (in game, 2026-11-16). So the triggers are
---also read themselves.
---@return boolean
function Gamepad.TriggerHeld()
    local mode = Gamepad.On() and _G.GamepadMode
    if not mode then
        return false
    end
    local hud, targeting = mode.IsHUDBindingModifierDown, mode.IsTargetingModifierDown
    return ns.IsTrue(hud and hud()) or ns.IsTrue(targeting and targeting())
        or Gamepad.Down(BUTTON.LEFT_TRIGGER) or Gamepad.Down(BUTTON.RIGHT_TRIGGER)
end
