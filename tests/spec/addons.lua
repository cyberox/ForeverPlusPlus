-- AddOns: this character's addons as a set by name: which are on, what a saved set would change,
-- and changing them.
local T = ...
local ns, eq = T.ns, T.eq

-- Four installed addons, by index; Recount and Forever++ are on.
local installed = { "Bagnon", "ForeverPlusPlus", "Questie", "Recount" }
local on = { ForeverPlusPlus = true, Recount = true }
local saved = 0
Enum.AddOnEnableState = { None = 0, Some = 1, All = 2 }
UnitGUID = function() return "Player-1-A" end
C_AddOns = {
    IsAddOnLoaded = function() return true end,
    GetNumAddOns = function() return #installed end,
    GetAddOnInfo = function(index) return installed[index] end,
    GetAddOnEnableState = function(index, guid)
        return guid == "Player-1-A" and on[installed[index]] and 2 or 0
    end,
    EnableAddOn = function(name, guid)
        on[name] = guid == "Player-1-A" or on[name]
    end,
    DisableAddOn = function(name, guid)
        if guid == "Player-1-A" then
            on[name] = nil
        end
    end,
    SaveAddOns = function() saved = saved + 1 end,
}
T.load("Lib/AddOns")
local AddOns = ns.AddOns

local states = AddOns.States()
eq(states.Recount, true, "addons: one that's on")
eq(states.Bagnon, false, "addons: one that's off")
eq(states.Missing, nil, "addons: one that isn't installed")

local turnOn, turnOff = AddOns.Changes(states)
eq(#turnOn + #turnOff, 0, "addons: the set just saved changes nothing")

-- A set from another time: Bagnon and Questie on, Recount off, and it would turn Forever++ off.
local set = { Bagnon = true, Questie = true, Recount = false, ForeverPlusPlus = false, Gone = true }
turnOn, turnOff = AddOns.Changes(set)
eq(table.concat(turnOn, ","), "Bagnon,Questie", "addons: what to turn on, in order")
eq(table.concat(turnOff, ","), "Recount", "addons: what to turn off, never Forever++")

-- An addon installed since the set was saved is left as it is.
installed[#installed + 1] = "Zygor"
on.Zygor = true
turnOn, turnOff = AddOns.Changes(set)
eq(#turnOff, 1, "addons: an addon the set doesn't name stays on")

AddOns.Apply(set)
eq(on.Bagnon and on.Questie, true, "addons: applied, turned on")
eq(on.Recount, nil, "addons: applied, turned off")
eq(on.ForeverPlusPlus and on.Zygor, true, "addons: applied, the rest left")
eq(saved, 1, "addons: applied, saved once")
turnOn, turnOff = AddOns.Changes(set)
eq(#turnOn + #turnOff, 0, "addons: nothing left to change after applying")

C_AddOns = nil
eq(next(AddOns.States()), nil, "addons: no API, no addons")
