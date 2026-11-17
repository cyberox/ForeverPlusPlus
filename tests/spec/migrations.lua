-- Migrations, end to end: a saved file as an older release left it, brought up to date by the real
-- steps from the real module files, and read back the way the module reads it today. Each step is
-- added by its module's file as it loads (ns.Migrate, ns.MigrateCharacter), so the whole addon is
-- loaded here and Store.Upgrade runs them in their real order, one release's step feeding the next.
-- Professions' own step (layout 7), the only one that sees profiles, is in tests/spec/store.lua.
local T = ...
local eq, same = T.eq, T.same

-- Who is logged in, and the CVars the steps set: what the steps ask the client.
local who = { guid = "Player-1-0000AAAA", name = "Aleth", realm = "Stormforge", class = "MAGE" }
local cvarsSet = {}
local ns, _, broken = T.Whole(function(env, stub)
    env.UnitGUID = function() return who.guid end
    -- The second value is a surname on Forever, which no step may take for a realm.
    env.UnitName = function() return who.name, "Surname" end
    env.GetRealmName = function() return who.realm end
    env.UnitClass = function() return who.class, who.class end
    env.C_CVar = setmetatable({
        SetCVar = function(name, value) cvarsSet[name] = value end,
    }, { __index = function() return stub end })
end)
eq(table.concat(broken, "\n  "), "", "migrations: every file loads")

local Store = ns.Store
-- At login a step that errors is reported and the rest go on. Here it should stop the spec.
ns.Call = function(fn, ...) return fn(...) end

-- The core adds its own two steps at login (ns.Start, which needs the client): layout 2 splits the
-- 0.8 layout into settings, data, and unclaimed per-character data, and layout 3 renames modules.
-- The same two calls, with the renames these files cross (Core.lua's RENAMED has the rest).
Store.Step(2, function(db)
    local perCharacter = {}
    for name, module in pairs(ns.modules) do
        perCharacter[name] = module.perCharacter
    end
    Store.Split(db, perCharacter)
end)
Store.Step(3, function(db)
    Store.Rename(db, { GatherTracking = "GatheringTracking", CharacterFrame = "CharacterWindow" })
end)

-- A login: the steps the saved file hasn't had.
local function login(db, char)
    char = char or {}
    Store.Upgrade(db, char)
    return char
end

-- What a module reads afterwards (`module.db`). A setting the module no longer has reads nil, so
-- a value that reads back here ended up under a key the module really uses.
local function read(db, name, char)
    local module = ns.modules[name]
    return Store.Load(db, char or {}, name, module.defaults, module.perCharacter, nil, module.perProfile)
end

-- A module's saved settings as they are, before anything reads them.
local function raw(db, name)
    return db.settings and db.settings[name] or {}
end

-- 0.7.0 and before ----------------------------------------------------------------------------------
-- Every module's settings and data were under `modules`, with every default saved. Sell Price,
-- Item Count, and Auction Prices were modules, as were the world map's parts and Durability Bars,
-- and the minimap button was Error Catcher's.
do
    local db = { modules = {
        SellPrice = { enabled = false, mode = "one", align = "inline", color = "gold" },
        ItemCount = { enabled = true, mode = "stack", align = "right", bank = false },
        AuctionPrices = {
            enabled = true, mode = "stack", align = "right", color = "white", scanAge = "inline",
            crafting = false, vendor = { [2320] = 9 },
            houses = {
                ["Stormforge-Horde"] = { scannedAt = 1700000600,
                    items = { [2589] = { price = 120, seenAt = 1700000600 } } },
                -- A house last scanned before 0.7.0: copper by item, with the scan's time.
                ["Stormforge-Alliance"] = { scannedAt = 1700001200, prices = { [774] = 55 } },
            },
        },
        PointsOfInterest = {
            enabled = false, dungeons = false, dungeonSize = 120,
            learnedNodes = { ["Aleth-Stormforge"] = { [10] = true }, ["Bram-Stormforge"] = { [20] = true } },
            leyLineSpots = { [1413] = { "spot" } },
        },
        ZoneInfo = { enabled = true, dungeons = "key", corner = "TOPLEFT" },
        Coordinates = { enabled = true },
        DurabilityBars = { enabled = true, show = "half" },
        ErrorCatcher = { enabled = true, minimap = false, clearModifier = "alt", saved = { angle = 45 } },
    } }
    local aleth = login(db)

    -- Item Tooltips: on if any of the three was, each line on or off as its module was.
    eq(raw(db, "ItemTooltips").auction, true, "0.7: Auction Prices was on")
    eq(raw(db, "ItemTooltips").enabled, true, "0.7: Item Tooltips is on, since two of the three were")
    local tooltips = read(db, "ItemTooltips")
    eq(tooltips.enabled, true, "0.7: and reads on")
    eq(tooltips.sellPrice, false, "0.7: Sell Price was off")
    eq(tooltips.itemCount, true, "0.7: Item Count was on")
    eq(tooltips.mode, "one", "0.7: the shared price options are Sell Price's")
    eq(tooltips.align, "inline", "0.7: both of them")
    eq(tooltips.sellPriceColor, "gold", "0.7: Sell Price's color keeps its own name")
    eq(tooltips.auctionColor, "white", "0.7: and Auction Prices' its own")
    eq(tooltips.bank, false, "0.7: Item Count's options come along")
    eq(tooltips.scanAge, "inline", "0.7: Auction Prices' options come along")
    for _, name in ipairs({ "SellPrice", "ItemCount", "AuctionPrices" }) do
        eq(db.settings[name] == nil and db.data[name] == nil, true, "0.7: nothing is left of " .. name)
    end

    -- Its prices: moved with it (layout 1), then packed to one string each (layout 4).
    local copper, seenAt = ns.Prices.Unpack(tooltips.houses["Stormforge-Horde"].items[2589])
    eq(copper, 120, "0.7: an auction price is kept")
    eq(seenAt, 1700000600, "0.7: with the time it was seen")
    eq(tooltips.houses["Stormforge-Horde"].scannedAt, 1700000600, "0.7: and the house's last scan")
    copper, seenAt = ns.Prices.Unpack(tooltips.houses["Stormforge-Alliance"].items[774])
    eq(copper, 55, "0.7: a price from before 0.7.0 is kept")
    eq(seenAt, 1700001200, "0.7: as seen at its house's scan")
    eq(tooltips.houses["Stormforge-Alliance"].prices, nil, "0.7: the old price list is gone")

    -- Crafting Costs and the merchant prices it learned went on to Professions (layout 7).
    local professions = read(db, "Professions")
    eq(professions.crafting, false, "0.7: Crafting Costs was off, and still is in Professions")
    eq(professions.enabled, true, "0.7: Professions itself is on")
    eq(professions.vendor[2320], 9, "0.7: merchant prices are Professions' now")
    eq(db.data.ItemTooltips.vendor, nil, "0.7: and not Item Tooltips'")

    -- World Map: on if any part was, each part's checkbox its old module's.
    eq(raw(db, "WorldMap").zoneInfo, true, "0.7: Zone Info was on")
    eq(raw(db, "WorldMap").coordinates, true, "0.7: Coordinates was on")
    eq(raw(db, "WorldMap").unexploredAreas, nil, "0.7: a part that wasn't saved has no choice saved")
    local map = read(db, "WorldMap", aleth)
    eq(map.enabled, true, "0.7: World Map is on, since Zone Info was")
    eq(map.pointsOfInterest, false, "0.7: Points of Interest was off")
    eq(map.unexploredAreas, true, "0.7: and reads its default")
    -- Two parts had an option called `dungeons`: each keeps its own.
    eq(map.dungeons, false, "0.7: Points of Interest's Dungeons")
    eq(map.zoneDungeons, "key", "0.7: Zone Info's Dungeons, under its new name")
    eq(map.dungeonSize, 120, "0.7: Points of Interest's options come along")
    eq(map.corner, "TOPLEFT", "0.7: Zone Info's options come along")
    eq(map.leyLineSpots[1413][1], "spot", "0.7: ley lines found stay the account's")
    for _, name in ipairs({ "PointsOfInterest", "ZoneInfo", "Coordinates" }) do
        eq(db.settings[name] == nil and db.data[name] == nil, true, "0.7: nothing is left of " .. name)
    end

    -- Learned flight points were kept for every character by "Name-Realm": each takes its own.
    eq(map.learnedNodes[10], true, "0.7: this character's flight points are its own")
    eq(map.learnedNodes[20], nil, "0.7: and not another character's")
    eq(db.unclaimed.WorldMap.learnedNodes["Aleth-Stormforge"], nil, "0.7: taken from the account")
    eq(db.unclaimed.WorldMap.learnedNodes["Bram-Stormforge"][20], true, "0.7: the other's wait for it")
    -- A character of the same name on another realm takes nothing.
    who.name, who.realm = "Bram", "Elsewhere"
    local stranger = login(db)
    eq(stranger.data == nil or stranger.data.WorldMap == nil, true, "0.7: a namesake on another realm takes none")
    who.realm = "Stormforge"
    local bram = login(db)
    eq(bram.data.WorldMap.learnedNodes[20], true, "0.7: the other character takes its own at its login")
    eq(db.unclaimed.WorldMap, nil, "0.7: and nothing is left waiting")
    who.name = "Aleth"

    -- Durability Bars became Character Window's Durability dropdown (and the module was renamed).
    eq(read(db, "CharacterWindow").durability, "half", "0.7: Durability Bars' Show is Character Window's Durability")
    eq(db.settings.DurabilityBars == nil and db.settings.CharacterFrame == nil, true, "0.7: under the module's name today")

    -- The minimap button left Error Catcher, with its key and its place.
    local button = read(db, "MinimapButton")
    eq(button.where, "compartment", "0.7: a button turned off stays off the minimap")
    eq(button.clearModifier, "alt", "0.7: its Clear Key comes along")
    eq(button.saved.angle, 45, "0.7: and where it was dragged to")
    eq(raw(db, "ErrorCatcher").enabled, true, "0.7: Error Catcher keeps its own settings")
    eq(raw(db, "ErrorCatcher").minimap == nil and raw(db, "ErrorCatcher").clearModifier == nil, true,
        "0.7: without the button's")
end

-- The other way for each: everything off, and nothing to move.
do
    local db = { modules = {
        SellPrice = { enabled = false, mode = "stack", align = "right", color = "white" },
        PointsOfInterest = { enabled = false, dungeons = true },
        ZoneInfo = { enabled = false, dungeons = "always" },
        DurabilityBars = { enabled = false, show = "worn" },
        ErrorCatcher = { enabled = true, minimap = true, clearModifier = "ctrl", saved = { angle = 200 } },
    } }
    login(db)
    eq(raw(db, "ItemTooltips").enabled, false, "0.7: Item Tooltips is off when its one module was")
    eq(raw(db, "ItemTooltips").itemCount, nil, "0.7: a line whose module wasn't saved has no choice saved")
    eq(raw(db, "WorldMap").enabled, false, "0.7: World Map is off when every part was")
    eq(read(db, "WorldMap").zoneInfo, false, "0.7: with each part off")
    eq(read(db, "CharacterWindow").durability, "off", "0.7: Durability Bars off is Durability set to Off")
    eq(raw(db, "MinimapButton").where, nil, "0.7: a button left on has no place saved")
    eq(read(db, "MinimapButton").where, "minimap", "0.7: so it stays on the minimap")

    -- A file with none of the old modules gets none of the new ones' settings made up.
    local plain = { modules = { ErrorCatcher = { enabled = true }, Waypoints = { enabled = true, x = 5, y = 100 } } }
    login(plain)
    for _, name in ipairs({ "ItemTooltips", "WorldMap", "CharacterWindow", "MinimapButton", "WaylaidCrates" }) do
        eq(plain.settings[name], nil, "0.7: no settings made up for " .. name)
    end
    eq(plain.settings.Waypoints.y, 100, "0.7: and what was saved stays")
end

-- 0.8.4 ---------------------------------------------------------------------------------------------
-- Still under `modules`. The hold-Shift checkboxes, Gathering Tracking's one Swap slider, Item
-- Tooltips' Waylaid Crate Costs, Coordinates' own CVar values, and plans and chat kept for the
-- whole account.
do
    local db = { seenVersion = "0.8.4", modules = {
        SkipCinematics = { enabled = true, skip = "seen", shiftWatches = false },
        AutoRepair = { enabled = true, shiftSkips = true },
        AutoSellJunk = { enabled = true, shiftSkips = false },
        AutoGossip = { enabled = true },
        GatherTracking = { enabled = true, track = "both", swap = 12 },
        Waypoints = { enabled = true, x = 0, y = 530 },
        QuestTracker = { enabled = true, opacity = 30 },
        ItemTooltips = { enabled = true, mode = "stack", crates = "below" },
        WorldMap = { enabled = true, coordinates = true,
            saved = { worldMapShowPlayerCoords = "0", coordsByTenths = "1" } },
        TalentPlanner = { enabled = true, builds = {
            ["Player-1-0000AAAA-1"] = { active = 1, list = { { name = "Fire" } } },
            ["Player-1-0000AAAA-3"] = { active = 1, list = { { name = "Frost" } } },
            ["Player-1-0000BBBB-2"] = { active = 1, list = { { name = "Fury" } } },
        } },
        ChatHistory = { enabled = true, lines = 100, saved = { [1] = { { "hello", 1, 1, 1 } } } },
    } }
    who.guid = "Player-1-0000AAAA"
    local first = login(db)

    -- Hold Shift became a key: Shift while it was on, None while it was off.
    eq(raw(db, "SkipCinematics").shiftWatches, nil, "0.8: the Hold Shift to Watch checkbox is gone")
    eq(read(db, "SkipCinematics").watchKey, "none", "0.8: off is no key")
    eq(raw(db, "AutoRepair").skipKey, "shift", "0.8: Hold Shift to Skip on is the Shift key")
    eq(read(db, "AutoSellJunk").skipKey, "none", "0.8: and off is no key")
    eq(raw(db, "AutoGossip").skipKey, nil, "0.8: a checkbox that wasn't saved saves no key")

    -- Swap was one slider; it's a checkbox and its slider (and the module was renamed).
    local tracking = read(db, "GatheringTracking")
    eq(tracking.swap, true, "0.8: a Swap of 12 seconds is Swap on")
    eq(tracking.swapEvery, 12, "0.8: every 12 seconds")
    eq(tracking.track, "both", "0.8: its other settings come along under the new name")
    eq(db.settings.GatherTracking, nil, "0.8: nothing is left under the old name")

    -- 0.8.4's own defaults, saved as if chosen, take today's.
    eq(raw(db, "Waypoints").y, nil, "0.8: the arrow's old default place isn't a choice")
    eq(read(db, "Waypoints").y, ns.modules.Waypoints.defaults.y, "0.8: so it reads today's")
    eq(raw(db, "QuestTracker").opacity, nil, "0.8: nor the tracker's old default background")
    eq(read(db, "QuestTracker").opacity, ns.modules.QuestTracker.defaults.opacity, "0.8: which reads today's")

    -- Waylaid Crate Costs is Waylaid Crates' Bundle Costs.
    eq(read(db, "WaylaidCrates").costs, "below", "0.8: Waylaid Crate Costs is Bundle Costs")
    eq(raw(db, "ItemTooltips").crates, nil, "0.8: and has left Item Tooltips")
    eq(raw(db, "ItemTooltips").mode, "stack", "0.8: which keeps its own settings")

    -- Coordinates held the player's own CVar values: put back, since nothing holds them now.
    same(cvarsSet, { worldMapShowPlayerCoords = "0", coordsByTenths = "1" }, "0.8: the player's map CVars are put back")
    eq(raw(db, "WorldMap").saved, nil, "0.8: and aren't kept as a setting")
    eq((db.data.WorldMap or {}).saved, nil, "0.8: nor as data")
    eq(raw(db, "WorldMap").coordinates, true, "0.8: the rest of World Map's settings stay")

    -- Talent plans were kept by "<GUID>-<spec tab>": each character takes its own, by tab.
    local plans = read(db, "TalentPlanner", first).builds
    eq(plans[1].list[1].name, "Fire", "0.8: this character's first tab's plans")
    eq(plans[3].list[1].name, "Frost", "0.8: and its third's")
    eq(plans[2], nil, "0.8: not another character's")
    local waiting = db.unclaimed.TalentPlanner.builds
    eq(waiting["Player-1-0000AAAA-1"] == nil and waiting["Player-1-0000AAAA-3"] == nil, true,
        "0.8: taken from the account")
    eq(waiting["Player-1-0000BBBB-2"].list[1].name, "Fury", "0.8: the other character's wait for it")

    -- Chat lines were the account's: the first character to log in takes them.
    eq(read(db, "ChatHistory", first).saved[1][1][1], "hello", "0.8: the first character takes the saved chat")
    eq(db.unclaimed.ChatHistory, nil, "0.8: so none waits")

    -- A character with neither logs in between: it takes nothing and leaves the rest waiting.
    who.guid = "Player-1-0000CCCC"
    local other = login(db)
    eq(other.data == nil or other.data.TalentPlanner == nil, true, "0.8: a character with no plans takes none")
    eq(other.data == nil or other.data.ChatHistory == nil, true, "0.8: and no chat")
    eq(db.unclaimed.TalentPlanner.builds["Player-1-0000BBBB-2"] ~= nil, true, "0.8: the plans still wait")
    who.guid = "Player-1-0000BBBB"
    local second = login(db)
    eq(second.data.TalentPlanner.builds[2].list[1].name, "Fury", "0.8: the second character takes its own")
    eq(second.data.TalentPlanner.builds[1], nil, "0.8: and only its own")
    eq(db.unclaimed.TalentPlanner, nil, "0.8: nothing is left waiting")
    -- Logging in again changes nothing: each step runs once per character.
    first.data.TalentPlanner.builds[1].list[1].name = "Arcane"
    login(db, first)
    eq(first.data.TalentPlanner.builds[1].list[1].name, "Arcane", "0.8: a second login leaves a character's plans alone")
    who.guid = "Player-1-0000AAAA"
end

-- The same settings the other way: what the player did choose is kept.
do
    cvarsSet = {}
    local db = { modules = {
        SkipCinematics = { enabled = true, shiftWatches = true },
        GatherTracking = { enabled = true, swap = 2 }, -- the slider's first stop, which read Never
        Waypoints = { enabled = true, x = 40, y = 530 },
        QuestTracker = { enabled = true, opacity = 45 },
        ItemTooltips = { enabled = true, mode = "one" },
        WorldMap = { enabled = true, saved = {} },
    } }
    login(db)
    eq(raw(db, "SkipCinematics").watchKey, "shift", "0.8: Hold Shift to Watch on is the Shift key")
    eq(raw(db, "GatheringTracking").swap, false, "0.8: Swap at Never is Swap off")
    eq(raw(db, "GatheringTracking").swapEvery, nil, "0.8: with no time saved for it")
    eq(read(db, "Waypoints").y, 530, "0.8: an arrow moved sideways keeps its height")
    eq(read(db, "Waypoints").x, 40, "0.8: and its place across")
    eq(read(db, "QuestTracker").opacity, 45, "0.8: a background the player chose is kept")
    eq(db.settings.WaylaidCrates, nil, "0.8: no Bundle Costs saved without Waylaid Crate Costs")
    eq(read(db, "ItemTooltips").mode, "one", "0.8: Item Tooltips keeps what was chosen")
    eq(next(cvarsSet), nil, "0.8: no CVars to put back, none set")

    -- The slowest stop that swaps, and an arrow whose place across was never saved.
    local edge = { modules = { GatherTracking = { swap = 3 }, Waypoints = { y = 530 } } }
    login(edge)
    eq(read(edge, "GatheringTracking").swap, true, "0.8: the first real stop is Swap on")
    eq(read(edge, "GatheringTracking").swapEvery, 3, "0.8: every 3 seconds")
    eq(raw(edge, "Waypoints").y, nil, "0.8: the old default height alone isn't a choice either")
end

-- 1.0.2 (layout 4) ------------------------------------------------------------------------------------
-- Settings and data apart, one profile. The nameplates' icons grew with Name Size, Health Bar When
-- Hurt was a checkbox, and Upgrade Arrows' tree was one setting for every character.
do
    local db = { version = 4, data = {}, settings = {
        PlayerNameplates = { nameSize = 130, barWhenHurt = false },
        NpcNameplates = { barWhenHurt = true },
        UpgradeArrows = { enabled = true, profile = "2" },
    } }
    who.class = "MAGE"
    local mage = login(db, { version = 4, data = {} })
    local plates = read(db, "PlayerNameplates")
    eq(plates.iconSize, 130, "1.0: the icons keep the size Name Size gave them")
    eq(plates.nameSize, 130, "1.0: and Name Size stays")
    eq(plates.healthBar, "combat", "1.0: Health Bar When Hurt off is Only in Combat")
    eq(raw(db, "NpcNameplates").healthBar, "hurt", "1.0: and on is When Hurt, for NPCs too")

    -- The tree is the first character's to log in, when it fits its class.
    eq(raw(db, "UpgradeArrows").profile, nil, "1.0: the account's one tree choice is gone")
    eq(read(db, "UpgradeArrows", mage).trees.MAGE, "2", "1.0: the first character keeps it, for its class")
    who.class = "WARRIOR"
    local warrior = login(db, { version = 4, data = {} })
    eq(next(read(db, "UpgradeArrows", warrior).trees), nil, "1.0: an alt starts at Auto")
    eq(read(db, "UpgradeArrows", mage).trees.MAGE, "2", "1.0: and the first character's choice stays")

    -- A file that had those settings already keeps them.
    local chosen = { version = 4, data = {}, settings = {
        PlayerNameplates = { nameSize = 130, iconSize = 100, barWhenHurt = false, healthBar = "never" },
    } }
    login(chosen, { version = 4 })
    eq(read(chosen, "PlayerNameplates").iconSize, 100, "1.0: an Icon Size already saved is kept")
    eq(read(chosen, "PlayerNameplates").healthBar, "never", "1.0: and a Health Bar already chosen")

    -- Tree choices that don't carry over: Bear for another class, Auto, and what isn't a tree.
    local function treesAfter(choice, class, char)
        local saved = { version = 4, data = {}, settings = { UpgradeArrows = { profile = choice } } }
        who.class = class
        char = login(saved, char or { version = 4 })
        return read(saved, "UpgradeArrows", char).trees, raw(saved, "UpgradeArrows").profile
    end
    local trees, left = treesAfter("bear", "MAGE")
    eq(next(trees), nil, "1.0: Bear isn't kept for a Mage")
    eq(left, nil, "1.0: but the old setting still goes")
    same(treesAfter("bear", "DRUID"), { DRUID = "bear" }, "1.0: Bear is kept for a Druid")
    same(treesAfter("3", "DRUID"), { DRUID = "3" }, "1.0: and so is a tab")
    eq(next(treesAfter("auto", "MAGE")), nil, "1.0: Auto saves nothing")
    eq(next(treesAfter("4", "MAGE")), nil, "1.0: a tab that isn't one saves nothing")
    eq(next(treesAfter(2, "MAGE")), nil, "1.0: nor a number where the choice is text")
    -- A character that had picked trees for other classes keeps them beside the new one.
    same(treesAfter("1", "MAGE", { version = 4, data = { UpgradeArrows = { trees = { DRUID = "bear" } } } }),
        { DRUID = "bear", MAGE = "1" }, "1.0: a character's other choices stay")
    who.class = "MAGE"
end

-- Each step once -----------------------------------------------------------------------------------
-- A step is for files older than its layout. Run on a newer one it would undo what the player has
-- done since: Name Size set after 1.1.0 isn't an Icon Size.
do
    local db = { version = 5, data = {}, settings = {
        PlayerNameplates = { nameSize = 130 },
        Waypoints = { x = 0, y = 530 },
    } }
    login(db, { version = 5 })
    eq(raw(db, "PlayerNameplates").iconSize, nil, "once: a layout 5 file's Name Size isn't copied to Icon Size")
    eq(raw(db, "Waypoints").y, 530, "once: nor is a height of 530 chosen since taken for the old default")

    -- A layout 3 file (0.9.0): prices still tables, and nothing older runs again.
    local old = { version = 3, settings = { QuestTracker = { opacity = 30 } }, data = { ItemTooltips = { houses = {
        ["Stormforge-Horde"] = { scannedAt = 1700000600, items = { [2589] = { price = 120, seenAt = 1700000660 } } },
    } } } }
    login(old, { version = 3 })
    local copper, seenAt = ns.Prices.Unpack(read(old, "ItemTooltips").houses["Stormforge-Horde"].items[2589])
    eq(copper, 120, "once: a layout 3 file's prices are packed")
    eq(seenAt, 1700000660, "once: with each item's own time")
    eq(raw(old, "QuestTracker").opacity, 30, "once: a background of 30 chosen in 0.9.0 is a choice")

    -- A current file, profiles and all, is left exactly as it is.
    local function current()
        return {
            version = Store.VERSION, newCharacters = "raid",
            settings = { PlayerNameplates = { nameSize = 130, barWhenHurt = false }, UpgradeArrows = { profile = "2" } },
            data = { ItemTooltips = { houses = { h = { scannedAt = 5, items = { [1] = "120,10" } } } } },
            profiles = { raid = { name = "Raid", settings = { Waypoints = { x = 0, y = 530 } }, data = {} } },
        }
    end
    local now, char = current(), { version = Store.VERSION, data = { UpgradeArrows = { trees = {} } } }
    login(now, char)
    same(now, current(), "once: a current file is untouched")
    same(char, { version = Store.VERSION, data = { UpgradeArrows = { trees = {} } } }, "once: and a current character")
end
