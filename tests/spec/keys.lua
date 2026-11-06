-- Keys: old Hold Shift to Skip checkboxes becoming key dropdowns.
local T = ...
local ns, eq = T.ns, T.eq

-- Hold Shift to Skip checkboxes become key dropdowns.
local shiftSaved = { AutoGossip = { shiftSkips = false }, AutoRepair = { shiftSkips = true } }
ns.Keys.MigrateShift(shiftSaved, "AutoGossip", "shiftSkips", "skipKey")
ns.Keys.MigrateShift(shiftSaved, "AutoRepair", "shiftSkips", "skipKey")
ns.Keys.MigrateShift(shiftSaved, "AutoSellJunk", "shiftSkips", "skipKey")
eq(shiftSaved.AutoGossip.skipKey, "none", "keys: an unticked checkbox is None")
eq(shiftSaved.AutoRepair.skipKey, "shift", "keys: a ticked checkbox is Shift")
eq(shiftSaved.AutoRepair.shiftSkips, nil, "keys: the checkbox goes")
eq(shiftSaved.AutoSellJunk, nil, "keys: nothing saved, nothing made")
