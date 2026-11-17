-- Menus: a menu described the way Blizzard's are, as our own plain entries, and when the
-- controller interface is on. The list frame itself isn't tested.
local T = ...
local ns, eq, same = T.ns, T.eq, T.same

T.load("Lib/Secret", ns)
T.load("Lib/Gamepad", ns)
T.load("Lib/Menus", ns)
local Menus = ns.Menus

-- The controller interface on (Lib/Gamepad.lua, tested in the gamepad spec).
eq(Menus.Available(), false, "available: no controller interface, and no Blizzard menu")
Enum = Enum or {}
Enum.InputDeviceInterfaceType = { MouseAndKeyboard = 0, Gamepad = 1 }
C_InputInterfaceStyle = { GetCurrentStyle = function() return 1 end }
eq(Menus.Available(), true, "available: ours needs nothing of Blizzard's")

-- A description, written as Blizzard's generators are.
local picked, on = nil, false
local root = Menus.Describe(function(owner, menu)
    menu:CreateTitle("Title for " .. owner)
    local button = menu:CreateButton("Plain", function(data) picked = data end, "plain")
    button:SetTooltip(function() end)
    menu:CreateDivider()
    menu:CreateCheckbox("Check", function() return on end, function() on = not on end)
    local sub = menu:CreateButton("More")
    sub:SetScrollMode(200) -- Blizzard's, nothing of ours: does nothing
    sub:CreateRadio("One", function(value) return value == 1 end, function() end, 1)
    sub:CreateRadio("Two", function(value) return value == 1 end, function() end, 2)
    local off = menu:CreateButton("Off")
    off:SetEnabled(false)
    local maybe = menu:CreateButton("Maybe")
    maybe:SetEnabled(function() return on end)
end, "me")

local kinds, texts = {}, {}
for i, entry in ipairs(root.items) do
    kinds[i], texts[i] = entry.kind, entry.text
end
same(kinds, { "title", "button", "divider", "checkbox", "button", "button", "button" }, "describe: each kind, in order")
same(texts, { "Title for me", "Plain", "", "Check", "More", "Off", "Maybe" }, "describe: each text")

local plain, check, more, off, maybe = root.items[2], root.items[4], root.items[5], root.items[6], root.items[7]
eq(type(plain.tooltip), "function", "describe: a tooltip is kept")
eq(root.items[1].tooltip, false, "describe: no tooltip is false, not a stand-in function")
eq(root.items[1].fn, false, "describe: nor is no function")
plain.fn(rawget(plain, "data"))
eq(picked, "plain", "describe: a button's function gets its data")
eq(#more.items, 2, "describe: a button's own entries are its submenu")
eq(#plain.items, 0, "describe: none for a plain button")

eq(Menus.IsSelected(check), false, "selected: a checkbox off")
check.fn()
eq(Menus.IsSelected(check), true, "selected: and on")
eq(Menus.IsSelected(more.items[1]), true, "selected: a radio is asked with its data")
eq(Menus.IsSelected(more.items[2]), false, "selected: and the other isn't")
eq(Menus.IsSelected(plain), false, "selected: a button never is")

eq(Menus.IsEnabled(plain), true, "enabled: by default")
eq(Menus.IsEnabled(off), false, "enabled: a flag")
eq(Menus.IsEnabled(maybe), true, "enabled: a function, asked each time")
on = false
eq(Menus.IsEnabled(maybe), false, "enabled: and again")
