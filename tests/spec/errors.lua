-- Errors: Error Catcher's counts and window, for the minimap button.
local T = ...
local ns, eq = T.ns, T.eq

local Errors = ns.Errors
local heard, toggled = 0, 0
Errors.OnChanged(function()
    heard = heard + 1
end)
eq(Errors.IsOn(), false, "errors off at first")
eq(Errors.SessionCount(), 0, "no count while off")
Errors.Toggle() -- does nothing while off
Errors.Provide({
    session = function() return 3 end,
    saved = function() return 7 end,
    toggle = function() toggled = toggled + 1 end,
    clearSession = function() toggled = toggled + 10 end,
})
eq(Errors.IsOn(), true, "errors on once provided")
eq(heard, 1, "providing tells listeners")
eq(Errors.SessionCount(), 3, "session count")
eq(Errors.SavedCount(), 7, "saved count")
Errors.Toggle()
eq(toggled, 1, "toggle opens the window")
Errors.ClearSession()
eq(toggled, 11, "clear session reaches error catcher")
Errors.Changed()
eq(heard, 2, "changes tell listeners")
Errors.Provide(nil)
eq(Errors.IsOn(), false, "errors off again")
eq(Errors.SavedCount(), 0, "no saved count while off")
eq(heard, 3, "turning off tells listeners")
