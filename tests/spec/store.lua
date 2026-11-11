-- Store: the saved variables' layout, the steps that bring it up to date, and module.db.
local T = ...
local ns, eq, same = T.ns, T.eq, T.same

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

-- Profiles: Default is the account's own settings and data, so saved variables from before profiles read the
-- same; another profile is a root of its own, read through the same view once it's in use.
local pdb = {
    version = 5,
    settings = { Win = { enabled = true, size = 3, gone = 1 } },
    data = { Win = { positions = { Bags = { x = 1 } }, prices = { a = 5 } } },
    profiles = { raid = { name = "Raid",
        settings = { Win = { size = 9, stale = true }, Gone = { enabled = true } },
        data = { Win = { positions = { Bags = { x = 2 } }, prices = { stray = 1 } }, Gone = { list = { a = {} } } } } },
}
local pchar = { version = 5 }
Store.Upgrade(pdb, pchar)
eq(pdb.version, Store.VERSION, "profiles: the layout is current")
eq(pdb.settings.Win.size, 3, "profiles: updating keeps Default's settings where they were")
local winDefaults = { enabled = false, size = 1, positions = {}, prices = {} }
local win = Store.Load(pdb, pchar, "Win", winDefaults, nil, nil, { positions = true })
eq(win.size, 3, "profiles: Default reads the account's settings")
eq(win.positions.Bags.x, 1, "profiles: Default's profile data is where it always was")
eq(pdb.settings.Win.gone, nil, "profiles: Default's dropped settings are cleared")
eq(pdb.profiles.raid.settings.Win.stale, nil, "profiles: another profile's dropped settings are cleared too")
eq(pdb.profiles.raid.data.Win.prices, nil, "profiles: a profile keeps only its profile data")
eq(pdb.profiles.raid.data.Win.positions.Bags.x, 2, "profiles: and keeps its own profile data")
Store.profile = "raid"
eq(win.size, 9, "profiles: switching changes what the view reads")
eq(win.enabled, false, "profiles: what a profile hasn't set reads the default")
eq(win.positions.Bags.x, 2, "profiles: profile data follows the profile")
eq(win.prices.a, 5, "profiles: account data stays the account's")
win.size = 4
eq(pdb.profiles.raid.settings.Win.size, 4, "profiles: a write goes to the profile in use")
eq(pdb.settings.Win.size, 3, "profiles: and leaves Default alone")
Store.profile = "missing"
eq(win.size, 3, "profiles: a profile that isn't there reads Default")
Store.profile = nil
Store.Prune(pdb, pchar, { Win = true })
eq(pdb.profiles.raid.settings.Gone, nil, "profiles: prune treats every profile")
eq(pdb.profiles.raid.data.Gone, nil, "profiles: prune treats every profile's data")
pdb.profiles.empty = { name = "Empty", settings = { Win = {} }, data = { Win = { positions = {} } } }
Store.Tidy(pdb, pchar)
eq(next(pdb.profiles.empty.settings), nil, "profiles: tidy treats every profile")
eq(pdb.profiles.empty.name, "Empty", "profiles: tidy keeps a profile with nothing changed")
Store.Rename(pdb, { Win = "Window" })
eq(pdb.profiles.raid.settings.Window.size, 4, "profiles: renaming a module renames it in every profile")

-- Version 7: Recipe Colors and Item Tooltips' Crafting Costs become parts of the Professions module.
-- Its step, from the module's own file, in an `ns` with only what the step and the file's load use.
do
    local into = {
        L = {}, Store = Store, Prices = ns.Prices,
        Migrate = function(version, fn) Store.Step(version, fn) end,
        MoveSettings = function(from, to, keys) -- Core's
            for new, old in pairs(keys) do
                if type(new) == "number" then
                    new = old
                end
                if from[old] ~= nil then
                    to[new] = from[old]
                end
            end
        end,
        NewModule = function() return {} end,
    }
    T.load("Modules/Character/Professions/Professions", into)
    eq(Store.VERSION, 7, "professions: the step is version 7")

    -- As 1.4.0 saved it (layout 5), with three more profiles to see each case in every profile.
    local db = {
        version = 5,
        seenModules = { RecipeColors = "1.4.0", ItemTooltips = "1.4.0" },
        settings = {
            -- Recipe Colors off, and Item Tooltips' Auction Prices off, so Crafting Costs showed nothing.
            RecipeColors = { enabled = false, highlight = false },
            ItemTooltips = { auction = false, mode = "one" },
        },
        data = {
            ItemTooltips = { vendor = { [2320] = 9 }, houses = { ["Realm-Horde"] = { scannedAt = 1 } } },
            MinimapButton = { quickToggles = { RecipeColors = true, ItemTooltips = false } },
        },
        profiles = {
            -- Recipe Colors on with an option changed, Crafting Costs off, Profit in Recipe List on.
            raid = { name = "Raid", settings = {
                RecipeColors = { enabled = true, gray = false },
                ItemTooltips = { crafting = false, craftingRows = true },
            }, data = { MinimapButton = { quickToggles = { RecipeColors = false } } } },
            -- Item Tooltips off: Crafting Costs showed nothing.
            alt = { name = "Alt", settings = { ItemTooltips = { enabled = false } }, data = {} },
            -- Everything at its default.
            fresh = { name = "Fresh", settings = {}, data = {} },
        },
    }
    Store.Upgrade(db, { version = 5 })
    eq(db.version, 7, "professions: the layout is version 7")

    local new = db.settings.Professions
    same(new, { enabled = false, recipeColors = false, skillUps = false, crafting = false, highlight = false },
        "professions: everything off leaves the module off, each part off")
    eq(db.settings.RecipeColors, nil, "professions: Recipe Colors' settings are gone")
    eq(db.settings.ItemTooltips.mode, "one", "professions: Item Tooltips keeps its own settings")
    eq(db.settings.ItemTooltips.auction, false, "professions: and its Auction Prices stays off")
    same(db.data.Professions, { vendor = { [2320] = 9 } }, "professions: merchant prices move")
    eq(db.data.ItemTooltips.vendor, nil, "professions: and leave Item Tooltips")
    eq(db.data.ItemTooltips.houses["Realm-Horde"].scannedAt, 1, "professions: auction prices stay")
    same(db.data.MinimapButton.quickToggles, { Professions = true, ItemTooltips = false },
        "professions: a quick toggle pick moves")
    same(db.seenModules, { Professions = "1.4.0", ItemTooltips = "1.4.0" },
        "professions: the version it was seen in moves")

    local raid = db.profiles.raid.settings
    same(raid.Professions, { recipeColors = true, gray = false, crafting = false },
        "professions: a part off, another on with its option, the module on")
    same(raid.ItemTooltips, {}, "professions: Crafting Costs' settings leave Item Tooltips")
    same(db.profiles.raid.data.MinimapButton.quickToggles, { Professions = false },
        "professions: a quick toggle taken out stays out, in another profile")

    same(db.profiles.alt.settings.Professions, { crafting = false },
        "professions: Item Tooltips off turns Crafting Costs off, the module stays on")
    eq(db.profiles.fresh.settings.Professions, nil, "professions: untouched defaults save nothing")

    -- What the module reads afterwards, through its defaults.
    local defaults = { enabled = true, recipeColors = true, highlight = true, gray = true,
        skillUps = true, points = "left", detail = true, crafting = true, craftingRows = true, vendor = {} }
    local view = Store.Load(db, {}, "Professions", defaults)
    eq(view.enabled, false, "professions: Default reads the module off")
    eq(view.vendor[2320], 9, "professions: and the merchant prices")
    Store.profile = "fresh"
    eq(view.enabled and view.recipeColors and view.skillUps and view.crafting, true,
        "professions: a profile at its defaults reads every part on")
    Store.profile = "raid"
    eq(view.crafting, false, "professions: another profile reads its own part off")
    Store.profile = nil
end
