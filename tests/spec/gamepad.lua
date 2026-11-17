-- Gamepad: whether the controller interface is on, its notices, reading a button from the
-- controller, a press of one, how the player's controller labels a button, and click hints.
local T = ...
local ns, eq = T.ns, T.eq

T.load("Lib/Secret")
T.load("Lib/Gamepad")
local Gamepad = ns.Gamepad
local BUTTON = Gamepad.BUTTON

-- The controller interface: only Forever's C_InputInterfaceStyle says.
eq(Gamepad.On(), false, "gamepad: no API, no controller interface")
Enum = Enum or {}
Enum.InputDeviceInterfaceType = { MouseAndKeyboard = 0, Gamepad = 1 }
local style = 0
C_InputInterfaceStyle = { GetCurrentStyle = function() return style end }
eq(Gamepad.On(), false, "gamepad: mouse and keyboard")
style = 1
eq(Gamepad.On(), true, "gamepad: the controller interface")

-- The notices show only while it's on.
local hides, limited = Gamepad.HidesNotice(), Gamepad.LimitedNotice()
eq(hides.text, ns.L.SETTINGS_CONTROLLER_HIDDEN, "gamepad: the hidden notice")
eq(limited.text, ns.L.SETTINGS_CONTROLLER_LIMITED, "gamepad: the limited notice")
eq(hides.shown() and limited.shown(), true, "gamepad: the notices show with it on")
style = 0
eq(hides.shown() or limited.shown(), false, "gamepad: and not with it off")

-- The controller's own state: buttons by name, counted from 0, in a table counted from 1.
local pad = {}
local PAD_NAMES = { [BUTTON.FACE_TOP] = 3, [BUTTON.LEFT_TRIGGER] = 8, [BUTTON.RIGHT_TRIGGER] = 9 }
C_GamePad = {
    ButtonBindingToIndex = function(name) return PAD_NAMES[name] end,
    GetDeviceMappedState = function() return pad.state end,
}
style = 1
eq(Gamepad.Down(BUTTON.FACE_TOP), false, "gamepad: no controller state, no button")
pad.state = { buttons = { false, false, false, true } }
eq(Gamepad.Down(BUTTON.FACE_TOP), true, "gamepad: a button is found one past its 0-based index")
eq(Gamepad.Down("NOTABUTTON"), false, "gamepad: an unknown button isn't down")
style = 0
eq(Gamepad.Down(BUTTON.FACE_TOP), false, "gamepad: nothing is read without the controller interface")
style, pad.state = 1, nil

-- A trigger held: Blizzard's modifiers, or read from the controller.
GamepadMode = {
    IsHUDBindingModifierDown = function() return pad.hud end,
    IsTargetingModifierDown = function() return pad.targeting end,
}
eq(Gamepad.TriggerHeld(), false, "gamepad: no trigger held")
pad.hud = true
eq(Gamepad.TriggerHeld(), true, "gamepad: Blizzard's modifier trigger")
pad.hud, pad.targeting = false, true
eq(Gamepad.TriggerHeld(), true, "gamepad: the targeting trigger counts too")
pad.targeting = false
pad.state = { buttons = { false, false, false, true } }
eq(Gamepad.TriggerHeld(), false, "gamepad: the top face button isn't a trigger")
pad.state = { buttons = { [10] = true } }
eq(Gamepad.TriggerHeld(), true, "gamepad: a trigger read from the controller")
style = 0
eq(Gamepad.TriggerHeld(), false, "gamepad: no trigger without the controller interface")
style, pad.state = 1, nil

-- A press: down now and not at the last look.
local top = { buttons = { false, false, false, true } }
local press = Gamepad.Press(BUTTON.FACE_TOP)
eq(press:Fired(), false, "press: not pressed")
pad.state = top
eq(press:Fired(), true, "press: pressed")
eq(press:Fired(), false, "press: held doesn't press again")
pad.state = nil
eq(press:Fired(), false, "press: let go")
pad.state = top
eq(press:Fired(), true, "press: pressed again")
pad.state = nil
press:Fired()
pad.state = top
press:Reset()
eq(press:Fired(), false, "press: held as watching starts isn't a press")
pad.state = nil
press:Reset(true)
eq(press:Fired(), false, "press: reset as held, a look without it")
pad.state = top
eq(press:Fired(), true, "press: then a press")
eq(Gamepad.Press(BUTTON.FACE_TOP, true):Fired(), false, "press: made as held, held isn't a press")
eq(Gamepad.Press(BUTTON.FACE_TOP):Fired(), true, "press: made as not held, held is a press")
pad.state = nil

-- A button is named as the game names it for the player's controller.
eq(Gamepad.Label(BUTTON.FACE_TOP), "Y", "gamepad: a button's Xbox letter where the game says nothing")
GetBindingText = function(button) return button == BUTTON.FACE_TOP and "<triangle>" or button end
eq(Gamepad.Label(BUTTON.FACE_TOP), "<triangle>", "gamepad: the game's own label for the button")
eq(Gamepad.Label(BUTTON.FACE_BOTTOM), "A", "gamepad: the button's name handed back isn't a label")
eq(Gamepad.Label("ODDBUTTON"), "ODDBUTTON", "gamepad: an unknown button is its name")
GetBindingText = nil

-- A click hint gives way to the button that does it.
eq(Gamepad.Hint("<Click to see its map>"), "<A to see its map>", "hint: the bottom face button by default")
eq(Gamepad.Hint("<Shift right click to forget this node>", BUTTON.RIGHT_STICK), "<R3 to forget this node>",
    "hint: another button")
eq(Gamepad.Hint("<Odd>"), "<Odd>", "hint: one that doesn't fit is left as written")
style = 0
eq(Gamepad.Hint("<Click to see its map>"), "<Click to see its map>", "hint: as written with it off")
