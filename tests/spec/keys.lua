-- Keys: the modifier key a module lets the player hold, its dropdown, and old Hold Shift to Skip
-- checkboxes becoming key dropdowns.
local T = ...
local ns, eq = T.ns, T.eq

-- Which keys are held.
local held = {}
IsShiftKeyDown = function() return held.shift end
IsControlKeyDown = function() return held.ctrl end
IsAltKeyDown = function() return held.alt end
T.load("Locales/enUS/Automation")
T.load("Lib/Keys") -- it caches the three
local Keys = ns.Keys

eq(Keys.IsDown("shift"), false, "keys: nothing held")
held.shift = true
eq(Keys.IsDown("shift"), true, "keys: shift held")
eq(Keys.IsDown("ctrl"), false, "keys: another key isn't")
held.shift, held.alt = nil, 1
eq(Keys.IsDown("alt"), true, "keys: any true answer is held")
eq(Keys.IsDown("none"), false, "keys: None is never held")
eq(Keys.IsDown("nonsense"), false, "keys: an unknown key isn't held")

local option = Keys.Option("skipKey", "Skip Key", "Hold it to skip.", "General", "1.0.0")
eq(option.key == "skipKey" and option.section == "General" and option.changed, "1.0.0",
    "keys: the dropdown option")
eq(option.choices, Keys.CHOICES, "keys: with the same choices as every other")
local values = {}
for _, choice in ipairs(Keys.CHOICES) do
    values[#values + 1] = choice[1]
    eq(type(choice[2]) == "string" and choice[2] ~= "", true, "keys: " .. choice[1] .. " has a name")
end
eq(table.concat(values, ","), "shift,ctrl,alt,none", "keys: the choices, in order")

-- Hold Shift to Skip checkboxes become key dropdowns.
local shiftSaved = { AutoGossip = { shiftSkips = false }, AutoRepair = { shiftSkips = true },
    AutoQuest = { shiftSkips = "odd" } }
Keys.MigrateShift(shiftSaved, "AutoGossip", "shiftSkips", "skipKey")
Keys.MigrateShift(shiftSaved, "AutoRepair", "shiftSkips", "skipKey")
Keys.MigrateShift(shiftSaved, "AutoSellJunk", "shiftSkips", "skipKey")
Keys.MigrateShift(shiftSaved, "AutoQuest", "shiftSkips", "skipKey")
eq(shiftSaved.AutoGossip.skipKey, "none", "keys: an unticked checkbox is None")
eq(shiftSaved.AutoRepair.skipKey, "shift", "keys: a ticked checkbox is Shift")
eq(shiftSaved.AutoRepair.shiftSkips, nil, "keys: the checkbox goes")
eq(shiftSaved.AutoSellJunk, nil, "keys: nothing saved, nothing made")
eq(shiftSaved.AutoQuest.skipKey == nil and shiftSaved.AutoQuest.shiftSkips, "odd",
    "keys: a value that isn't a checkbox's is left alone")
