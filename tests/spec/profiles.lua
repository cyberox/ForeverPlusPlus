-- Profiles: making, naming, deleting, the characters on each, and switching (with Core's part
-- stubbed; spec/core.lua switches with the real one).
local T = ...
local ns, eq, ok = T.ns, T.eq, T.ok

local commands = {}
ns.AddCommand = function(name, _, _, fn) commands[name] = fn end
local said = {}
ns.Print = function(text) said[#said + 1] = text end
ns.PrintLine = function() end
local inCombat, waiting = false, {}
InCombatLockdown = function() return inCombat end
ns.AfterCombat = function(fn)
    if inCombat then waiting[#waiting + 1] = fn else fn() end
end
local function endCombat()
    inCombat = false
    local list = waiting
    waiting = {}
    for _, fn in ipairs(list) do fn() end
end
local swaps = 0
ns.ChangeProfile = function(swap)
    swaps = swaps + 1
    swap()
end
local guid = "Player-1-A"
UnitGUID = function() return guid end
UnitName = function() return guid == "Player-1-A" and "Ann" or "Bob", "Surname" end
GetRealmName = function() return "Forever" end
UnitClass = function() return "Mage", "MAGE" end
T.player.level = 12

ns.modules = {
    Win = { name = "Win", defaults = { enabled = false, size = 1, positions = {} }, perProfile = { positions = true } },
    Tool = { name = "Tool", alwaysOn = true, defaults = { enabled = true, mode = "a" } },
}
T.load("Lib/Profiles")
local Profiles, Store = ns.Profiles, ns.Store

-- Updating from 1.5.0: one profile, Default, the settings the player had.
ns.db = { settings = { Win = { enabled = true, size = 3 } }, data = { Win = { positions = { Bags = { x = 1 } } } } }
ns.charDB = { version = 5 }
local heard = {}
Profiles.OnChanged(function(switched) heard[#heard + 1] = switched end)
Profiles.Login(false)
eq(Profiles.Current(), "default", "profiles: an updated character uses Default")
eq(Profiles.Count(), 1, "profiles: there is only Default at first")
eq(Profiles.Name("default"), "Default", "profiles: Default's name")
eq(ns.db.characters[guid].name .. "," .. ns.db.characters[guid].class .. "," .. ns.db.characters[guid].level,
    "Ann,MAGE,12", "profiles: the character is remembered with its class and level")
local modulesOn, changed = Profiles.Summary("default")
eq(modulesOn .. "," .. changed, "1,1", "profiles: Default's summary counts modules on and settings changed")

-- Names.
eq(Profiles.CleanName("  |cffff0000Raid|r |T123:0|t  Night\n "), "Raid Night", "profiles: a name loses its codes")
eq(Profiles.CleanName(("x"):rep(50)), ("x"):rep(Profiles.MAX_NAME), "profiles: a name is cut to its length")
local id, why = Profiles.Create("  ")
eq(id == nil and why ~= nil, true, "profiles: an empty name is refused")
id, why = Profiles.Create("default")
eq(id == nil and why ~= nil, true, "profiles: Default's name is taken")

-- Making them.
local raid = Profiles.Create("Raid", "default")
ok(raid, "profiles: a copy is made")
eq(ns.db.profiles[raid].settings.Win.size, 3, "profiles: a copy has the settings")
eq(ns.db.profiles[raid].data.Win.positions.Bags.x, 1, "profiles: a copy has Default's profile data")
ns.db.profiles[raid].data.Win.positions.Bags.x = 2
eq(ns.db.data.Win.positions.Bags.x, 1, "profiles: a copy is its own")
local fresh = Profiles.Create("Fresh")
eq(next(ns.db.profiles[fresh].settings or {}), nil, "profiles: one from defaults has nothing changed")
eq(Profiles.Find("RAID"), raid, "profiles: found by name, any case")
eq(table.concat(Profiles.List(), ","), "default," .. fresh .. "," .. raid, "profiles: Default first, then by name")
eq(Profiles.Current(), "default", "profiles: making one doesn't switch")
eq(#heard > 0, true, "profiles: listeners hear of changes")

-- Renaming.
eq(Profiles.Rename("default", "Main"), nil, "profiles: Default can't be renamed")
eq(Profiles.Rename(raid, "fresh"), nil, "profiles: nor another to a name that's taken")
eq(Profiles.Rename(raid, "Raids"), true, "profiles: a rename")
eq(Profiles.Name(raid), "Raids", "profiles: renamed")
eq(Profiles.Rename(raid, "raids"), true, "profiles: a rename to its own name in another case")

-- Switching, live and in combat.
heard = {}
eq(Profiles.Switch(raid), true, "profiles: a switch out of combat is now")
eq(Profiles.Current(), raid, "profiles: switched")
eq(Store.profile .. "," .. ns.charDB.profile, raid .. "," .. raid, "profiles: Store and the character follow")
eq(ns.db.characters[guid].profile, raid, "profiles: the account's record follows")
eq(heard[#heard], true, "profiles: listeners hear of the switch")
inCombat = true
eq(Profiles.Switch("default"), false, "profiles: in combat it waits")
eq(Profiles.Current(), raid, "profiles: and hasn't switched yet")
endCombat()
eq(Profiles.Current(), "default", "profiles: once combat ends it switches")
swaps = 0
Profiles.Switch("default")
eq(swaps, 0, "profiles: switching to the profile in use changes nothing")
eq(Profiles.Switch("nope"), nil, "profiles: a profile that isn't there")

-- Another character: Bob logs in, new to the addon, and takes New Characters Use.
Profiles.SetNewCharacters(fresh)
eq(Profiles.NewCharacters(), fresh, "profiles: New Characters Use")
guid = "Player-1-B"
ns.charDB = {}
Profiles.Login(true)
eq(Profiles.Current(), fresh, "profiles: a new character starts on New Characters Use")
-- Back on Ann, Bob is moved to Raids, and takes it at his next login.
guid = "Player-1-A"
ns.charDB = { version = 6 }
local bobDB = { version = 6, profile = fresh }
Profiles.Login(false)
eq(Profiles.Current(), "default", "profiles: an old character keeps its profile, not New Characters Use")
eq(#Profiles.Characters(), 2, "profiles: both characters are listed")
eq(#Profiles.Users(fresh), 1, "profiles: one uses Fresh")
eq(Profiles.SetCharacter("Player-1-B", raid), true, "profiles: another character's profile is set")
eq(Profiles.Current(), "default", "profiles: and this character's isn't")
eq(#Profiles.Users(raid), 1, "profiles: the list shows it at once")
guid = "Player-1-B"
ns.charDB = bobDB
Profiles.Login(false)
eq(Profiles.Current(), raid, "profiles: the other character takes it at its next login")

-- Two characters on one profile, and deleting it.
guid = "Player-1-A"
ns.charDB = { version = 6 }
Profiles.Login(false)
Profiles.Switch(raid)
eq(#Profiles.Users(raid), 2, "profiles: two characters share a profile")
Profiles.SetNewCharacters(raid)
eq(Profiles.Delete("default"), nil, "profiles: Default can't be deleted")
eq(Profiles.Delete(raid), true, "profiles: deleting the profile in use")
eq(Profiles.Current(), "default", "profiles: sends this character to Default")
eq(Profiles.Exists(raid), false, "profiles: and it's gone")
eq(#Profiles.Users("default"), 2, "profiles: and its other characters too")
eq(Profiles.NewCharacters(), "default", "profiles: and New Characters Use goes back to Default")
guid = "Player-1-B"
ns.charDB = bobDB
Profiles.Login(false)
eq(Profiles.Current(), "default", "profiles: the other character is on Default at its next login")
guid = "Player-1-A"
ns.charDB = { version = 6, profile = "p99" }
Profiles.Login(false)
eq(Profiles.Current(), "default", "profiles: a profile that's gone reads as Default")

-- Forgetting.
Profiles.Forget("Player-1-A")
eq(#Profiles.Characters(), 2, "profiles: this character can't be forgotten")
Profiles.Forget("Player-1-B")
eq(#Profiles.Characters(), 1, "profiles: another can")

-- Replacing what a profile holds, and /fpp profile.
local made = Profiles.CreateFrom("Imported", { Win = { enabled = true, size = 7 } }, { Win = { positions = { A = { x = 9 } } } })
eq(ns.db.profiles[made].settings.Win.size, 7, "profiles: one made from contents")
swaps = 0
Profiles.Replace("default", { Win = { size = 5 } }, { Win = { positions = { B = { x = 4 } } } })
eq(swaps, 1, "profiles: replacing the profile in use is live")
eq(ns.db.settings.Win.size .. "," .. ns.db.data.Win.positions.B.x, "5,4", "profiles: Default's contents replaced")
eq(ns.db.data.Win.positions.Bags, nil, "profiles: its old profile data is gone")
commands.profiles("imported")
eq(Profiles.Current(), made, "profiles: /fpp profiles <name> switches")
said = {}
commands.profiles("nothing")
eq(#said, 1, "profiles: /fpp profiles with a name that isn't one says so")
eq(Profiles.UsersText(1) .. "|" .. Profiles.UsersText(3), "1 character|3 characters", "profiles: users text")
