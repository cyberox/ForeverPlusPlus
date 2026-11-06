-- Store: the saved variables' layout, the steps that bring it up to date, and module.db.
local T = ...
local ns, eq = T.ns, T.eq

local Store = ns.Store

-- A fresh install is current at once and runs no steps.
local ran = {}
Store.Step(1, function(db) ran[#ran + 1] = "1:" .. tostring(db.modules ~= nil) end)
Store.Step(2, function(db)
    ran[#ran + 1] = "2"
    Store.Split(db, { TalentPlanner = { builds = true } })
end)
Store.Step(3, function(db)
    ran[#ran + 1] = "3"
    Store.Rename(db, { BagSlots = "BagSlotCounter" })
end)
Store.CharacterStep(2, function(char, db)
    Store.Claim(char, db, "TalentPlanner", "builds", function(entries)
        local mine = entries["G-1"] and { [1] = entries["G-1"] }
        entries["G-1"] = nil
        return mine
    end)
end)
local freshDB, freshChar = {}, {}
eq(Store.Upgrade(freshDB, freshChar), true, "store: empty saved variables are a fresh install")
eq(#ran, 0, "store: a fresh install runs no account steps")
eq(freshDB.version, Store.VERSION, "store: a fresh install is current")
eq(freshChar.version, Store.VERSION, "store: a fresh character is current")

-- The 0.8 layout: every setting and table in `modules`, under the old names.
local oldDB = { seenModules = { BagSlots = "0.8.2" }, modules = {
    BagSlots = { enabled = true, size = "large", position = "top" },
    TalentPlanner = { enabled = true, builds = { ["G-1"] = { active = 1 }, ["H-1"] = { active = 2 } } },
} }
local oldChar = {}
eq(Store.Upgrade(oldDB, oldChar), false, "store: saved settings aren't a fresh install")
eq(table.concat(ran, ","), "1:true,2,3", "store: steps run in version order, version 1 on the old layout")
eq(oldDB.modules, nil, "store: the old layout is gone")
eq(oldDB.settings.BagSlotCounter.position, "top", "store: settings follow a renamed module")
eq(oldDB.settings.BagSlots, nil, "store: the old name is gone")
eq(oldDB.seenModules.BagSlotCounter, "0.8.2", "store: the version a module was seen in follows it")
eq(oldChar.data.TalentPlanner.builds[1].active, 1, "store: a character takes its own data")
eq(oldDB.unclaimed.TalentPlanner.builds["H-1"].active, 2, "store: another character's data waits")
ran = {}
Store.Upgrade(oldDB, oldChar)
eq(#ran, 0, "store: each step runs once")

-- What a module reads and writes.
local defaults = { enabled = true, size = "large", position = "bottomright", banks = {}, seen = { list = {} } }
oldDB.settings.BagSlotCounter.stale = 5
oldDB.data.BagSlotCounter = { gone = {} }
local view = Store.Load(oldDB, oldChar, "BagSlotCounter", defaults)
local settings = oldDB.settings.BagSlotCounter
eq(view.size, "large", "store: a setting reads its default")
eq(settings.size, nil, "store: the 0.8 layout's settings at their default are dropped")
eq(settings.stale, nil, "store: a setting the defaults dropped is cleared")
eq(view.position, "top", "store: a changed setting reads what was chosen")
view.position = "bottomright"
eq(settings.position, "bottomright", "store: a choice at the default stays saved")
defaults.position = "left" -- a later release's new default
eq(view.position, "bottomright", "store: so a new default doesn't change the player's choice")
view.position = nil
eq(settings.position, nil, "store: nil forgets the choice")
eq(view.position, "left", "store: and the new default reads back")
defaults.position = "bottomright"
view.size = "huge"
eq(settings.size, "huge", "store: a changed setting is saved")
eq(type(view.banks), "table", "store: data reads its table")
eq(oldDB.data.BagSlotCounter.banks, view.banks, "store: data is saved apart from settings")
eq(type(view.seen.list), "table", "store: data is filled with its default tables")
eq(oldDB.data.BagSlotCounter.gone, nil, "store: data the defaults dropped is cleared")
local plans = Store.Load(oldDB, oldChar, "TalentPlanner", { enabled = true, builds = {} }, { builds = true })
eq(plans.builds[1].active, 1, "store: per-character data reads the character's table")
plans.builds[2] = { active = 3 }
eq(oldChar.data.TalentPlanner.builds[2].active, 3, "store: per-character data is saved for the character")
-- A key moved out of perCharacter takes the character's data to the account, and back.
local moved = Store.Load(oldDB, oldChar, "TalentPlanner", { enabled = true, builds = {} })
eq(moved.builds[2].active, 3, "store: data moved to the account keeps what the character had")
eq(oldChar.data.TalentPlanner.builds, nil, "store: data moved to the account leaves the character")
moved = Store.Load(oldDB, oldChar, "TalentPlanner", { enabled = true, builds = {} }, { builds = true })
eq(moved.builds[2].active, 3, "store: data moved back to the character comes along")
-- A linked setting (one of Blizzard's) reads and writes elsewhere, and nothing of it is saved.
local blizzard = { value = false, sets = {} }
oldDB.settings.WorldMap = { coordsTenths = true }
local linkedView = Store.Load(oldDB, oldChar, "WorldMap", { enabled = true, coordsTenths = false }, nil, {
    coordsTenths = {
        get = function() return blizzard.value end,
        set = function(value) blizzard.sets[#blizzard.sets + 1] = tostring(value) end,
    },
})
eq(oldDB.settings.WorldMap.coordsTenths, nil, "store: a linked setting saved here is dropped")
eq(linkedView.coordsTenths, false, "store: a linked setting reads its own value")
blizzard.value = true
eq(linkedView.coordsTenths, true, "store: a linked setting follows its own value")
linkedView.coordsTenths = false
linkedView.coordsTenths = nil
eq(table.concat(blizzard.sets, ","), "false,nil", "store: setting a linked setting sets it there")
eq(oldDB.settings.WorldMap.coordsTenths, nil, "store: setting a linked setting saves nothing here")
oldDB.unclaimed.Gone = { list = { a = {} } }
Store.Prune(oldDB, oldChar, { BagSlotCounter = true })
eq(oldDB.settings.TalentPlanner, nil, "store: a module that's gone loses its settings")
eq(oldDB.unclaimed.Gone, nil, "store: a module that's gone loses its unclaimed data")
view.size = nil
Store.Tidy(oldDB, oldChar)
eq(oldDB.settings.BagSlotCounter, nil, "store: tidy drops a module with no changed settings")
eq(oldDB.data.BagSlotCounter, nil, "store: tidy drops data with nothing collected")
view.position = "top"
eq(oldDB.settings.BagSlotCounter.position, "top", "store: a write after tidy is saved again")
eq(type(view.seen.list), "table", "store: data after tidy is made again")
view.banks.x = 1
eq(oldDB.data.BagSlotCounter.banks.x, 1, "store: data made again is saved")
