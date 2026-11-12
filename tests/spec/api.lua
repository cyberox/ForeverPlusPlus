-- API: the public ForeverPlusPlusAPI.v1 other addons read.
local T = ...
local ns, eq = T.ns, T.eq

-- API.lua against the Lib files loaded above, with the few things it needs from Core stubbed.

do
    local reported = {}
    geterrorhandler = function()
        return function(err)
            reported[#reported + 1] = err
        end
    end
    local seenPlayers = {
        bob = { class = "MAGE", level = 42, race = "Gnome", guild = "Tinkers", seen = 5000 },
    }
    local moduleChanged -- what Core would call when a module or option changes
    local profilesChanged -- what Lib/Profiles.lua would call
    local api
    local gameEvents = {} -- event -> fn, what the API listens to
    local tooltips = {
        title = "Item Tooltips", description = "Tooltip lines.", category = "items", enabled = true,
        defaults = { enabled = true, sell = true, align = "edge", scale = 100 },
        db = { enabled = true, sell = false, align = "edge", scale = 100, prices = {} },
        options = {
            { key = "sell", name = "Sell Price" },
            { key = "align", name = "Align", choices = { { "edge", "Edge" }, { "inline", "Inline" } } },
            { key = "scale", name = "Scale", min = 50, max = 150 },
            { key = "trace", name = "Trace", debug = true },
        },
    }
    -- The module Recipe Colors and Item Tooltips' Crafting Costs went into, for the old names.
    local professions = {
        title = "Professions", description = "The professions window.", category = "character",
        enabled = true,
        defaults = { enabled = true, recipeColors = true, highlight = true, gray = true, crafting = true },
        db = { enabled = true, recipeColors = true, highlight = false, gray = true, crafting = false },
        options = {
            { key = "recipeColors", name = "Recipe Colors" },
            { key = "highlight", name = "Tint Row Highlights" },
            { key = "gray", name = "Gray Out Finished Recipes" },
            { key = "crafting", name = "Crafting Costs" },
        },
    }
    api = setmetatable({
        modules = {
            ItemTooltips = tooltips,
            Professions = professions,
            Gone = { title = "Gone", unavailable = true, defaults = {} },
        },
        order = { "ItemTooltips", "Professions", "Gone" },
        version = "1.0.0",
        L = setmetatable({ PROFESSIONS_COLORS = "Recipe Colors", PROFESSIONS_COLORS_DESC = "Colors." },
            { __index = ns.L }),
        PartOn = function(module, key) -- Core's
            local value = module.db[key]
            return value ~= nil and value ~= false and value ~= "off"
        end,
        OnModuleChanged = function(fn) moduleChanged = fn end,
        HasEvent = function() return true end,
        OptionKind = function(option) -- Core's: choices, then a range, else a checkbox
            return option.choices and "dropdown" or option.min and "slider" or "checkbox"
        end,
        On = function(event, fn) gameEvents[event] = fn end,
        OpenSettings = function(name) return name == "ItemTooltips" or name == "Professions" end,
        Frames = { Coalesce = function(fn) return fn end }, -- runs at once, so tests see each call
        Profiles = {
            current = "default", names = { default = "Default", p1 = "Raid", p2 = "Solo" },
            Current = function() return api.Profiles.current end,
            Name = function(id) return api.Profiles.names[id] end,
            Count = function() return 3 end,
            OnChanged = function(fn) profilesChanged = fn end,
        },
        Players = {
            Get = function(_, name)
                return name and seenPlayers[name:lower():match("^[^%-]+")]
            end,
            ClassName = function(token)
                return token == "MAGE" and "Mage" or nil
            end,
        },
    }, { __index = ns })
    T.load("API", api)
    local v1 = ForeverPlusPlusAPI.v1

    local apiVersion, addonVersion = v1.GetVersion()
    eq(apiVersion, 1, "api: version 1")
    eq(addonVersion, "1.0.0", "api: addon version")
    eq(pcall(function() ForeverPlusPlusAPI.v1.GetVersion = nil end), false, "api: v1 is read only")
    eq(pcall(function() ForeverPlusPlusAPI.v2 = {} end), false, "api: the root is read only")

    eq(v1.IsModuleEnabled("ItemTooltips"), true, "api: a module that's on")
    eq(v1.IsModuleEnabled("Nope"), nil, "api: a module that isn't there")
    local listed = v1.GetModules()
    eq(#listed, 2, "api: modules leave out unavailable ones")
    eq(listed[1].title, "Item Tooltips", "api: a module's title")
    eq(listed[2].name, "Professions", "api: a moved module is listed by its new name only")

    -- Prices, and the callback that says they changed.
    local updates = 0
    v1.RegisterCallback("PRICES_UPDATED", function() updates = updates + 1 end, "test")
    eq(v1.HasAuctionPrices(), false, "api: no prices without a source")
    eq(v1.GetAuctionPrice(4305), nil, "api: no price without a source")
    eq(v1.GetAuctionPriceSource(), nil, "api: no source")
    ns.Prices.SetSource({
        price = function(itemID)
            if itemID == 4305 then
                return 120, 1000
            elseif itemID == 666 then
                error("broken source")
            end
        end,
        itemByName = function(name)
            return name == "Bolt of Silk Cloth" and 4305 or nil
        end,
        inline = function() return false end,
        auctionator = function() return false end,
    })
    eq(updates, 1, "api: a new source tells PRICES_UPDATED")
    eq(v1.GetAuctionPriceSource(), "ForeverPlusPlus", "api: our own prices")
    local price, seen = v1.GetAuctionPrice(4305)
    eq(price, 120, "api: price by ID")
    eq(seen, 1000, "api: and when it was seen")
    eq((v1.GetAuctionPrice("|cffffffff|Hitem:4305::::::::60:::::|h[Bolt of Silk Cloth]|h|r")), 120,
        "api: price by link")
    eq((v1.GetAuctionPrice("4305")), 120, "api: price by ID as text")
    eq((v1.GetAuctionPrice("Bolt of Silk Cloth")), 120, "api: price by name")
    eq(v1.GetAuctionPrice({}), nil, "api: nonsense gets nil")
    eq(v1.GetAuctionPrice(666), nil, "api: our error returns nil")
    eq(#reported, 1, "api: and goes to the error handler")
    ns.Prices.Changed()
    eq(updates, 2, "api: changed prices tell PRICES_UPDATED")
    v1.RegisterCallback("PRICES_UPDATED", function() error("caller's bug") end, "broken")
    ns.Prices.Changed()
    eq(updates, 3, "api: one failing callback doesn't stop the others")
    eq(#reported, 2, "api: the failing callback is reported")
    v1.UnregisterCallback("PRICES_UPDATED", "broken")
    v1.UnregisterCallback("PRICES_UPDATED", "test")
    ns.Prices.Changed()
    eq(updates, 3, "api: unregistered callbacks stop")
    eq(v1.RegisterCallback("NOPE", function() end), nil, "api: an unknown event")
    eq(#reported, 3, "api: is reported")
    ns.Prices.SetSource(nil)
    eq(v1.GetDisenchantValue(4305), nil, "api: no disenchant value without prices")

    -- Players seen: a copy, so a caller can't change what's saved.
    local info = v1.GetPlayerInfo("Bob-Surname")
    eq(info and info.class, "MAGE", "api: player class")
    eq(info and info.className, "Mage", "api: player class name")
    eq(info and info.level, 42, "api: player level")
    eq(info and info.lastSeen, 5000, "api: when they were seen")
    info.level = 1
    eq(v1.GetPlayerInfo("Bob").level, 42, "api: player info is a copy")
    eq(v1.GetPlayerInfo("Nobody"), nil, "api: someone never seen")
    eq(v1.GetPlayerInfo(nil, nil), nil, "api: no name, no player")

    -- Colors, with a LevelRange whose color shows the level it was given.
    local levelRange = ns.Colors.LevelRange
    ns.Colors.LevelRange = function(low)
        return { r = low / 100, g = 1, b = 0 }
    end
    local r, _, _, hex = v1.GetLevelColor(20, 30)
    eq(r, 0.2, "api: level color")
    eq(hex, "ff33ff00", "api: and its hex")
    ns.Colors.LevelRange = levelRange
    eq((v1.GetLevelColor("x")), nil, "api: a level that isn't a number")
    eq(v1.GetClassColor(nil), nil, "api: no class, no color")

    -- Dungeons and raids.
    local list = v1.GetInstances()
    eq(#list > 20, true, "api: every instance")
    eq(list[1].minLevel <= list[#list].minLevel, true, "api: by lowest level")
    local deadmines = v1.GetInstanceInfo(36)
    eq(deadmines and deadmines.englishName, "The Deadmines", "api: instance by ID")
    eq(deadmines and deadmines.isRaid, false, "api: a dungeon isn't a raid")
    local mc = v1.GetInstanceInfo("molten core")
    eq(mc and mc.isRaid, true, "api: instance by name")
    eq(v1.GetInstanceInfo("Nowhere"), nil, "api: not an instance")

    eq(type(v1.GetSkinningSkill(30)), "number", "api: skinning skill for a level")

    -- Modules in full, and what changes in them.
    local full = v1.GetModuleInfo("ItemTooltips")
    eq(full and full.description, "Tooltip lines.", "api: module description")
    eq(full and #full.options, 3, "api: options, without debug ones")
    eq(full and full.options[1].value, false, "api: an option's value")
    eq(full and full.options[1].default, true, "api: and its default")
    eq(full and full.options[2].kind, "dropdown", "api: a dropdown")
    eq(full and full.options[2].choices[2], "inline", "api: its choices")
    eq(full and full.options[3].kind == "slider" and full.options[3].max, 150, "api: a slider")
    eq(v1.GetModuleInfo("Gone"), nil, "api: no info for an unavailable module")
    eq(v1.GetModuleOption("ItemTooltips", "align"), "edge", "api: one option")
    eq(v1.GetModuleOption("ItemTooltips", "prices"), nil, "api: data isn't an option")
    eq(v1.GetModuleOption("ItemTooltips", "trace"), nil, "api: nor is a debug option")
    eq(v1.OpenSettings("ItemTooltips"), true, "api: opens settings on a module")

    -- Old names: Recipe Colors is the Professions module's part, Crafting Costs its other one.
    eq(v1.IsModuleEnabled("RecipeColors"), true, "api: an old module name answers while its part is on")
    professions.db.recipeColors = false
    eq(v1.IsModuleEnabled("RecipeColors"), false, "api: off while its part is off")
    professions.db.recipeColors = true
    professions.enabled = false
    eq(v1.IsModuleEnabled("RecipeColors"), false, "api: and while its new module is off")
    local old = v1.GetModuleInfo("RecipeColors")
    eq(old and old.name, "RecipeColors", "api: an old module's info keeps its name")
    eq(old and old.title, "Recipe Colors", "api: its title is its part's")
    eq(old and old.enabled, false, "api: it says whether it's on")
    eq(old and #old.options, 2, "api: only the options it had")
    eq(old and old.options[1].key .. "=" .. tostring(old.options[1].value), "highlight=false",
        "api: read where they are now")
    professions.enabled = true
    eq(v1.GetModuleInfo("RecipeColors").enabled, true, "api: on with its module and part")
    eq(v1.GetModuleOption("RecipeColors", "highlight"), false, "api: an old module's option")
    eq(v1.GetModuleOption("RecipeColors", "gray"), true, "api: another")
    eq(v1.GetModuleOption("RecipeColors", "crafting"), nil, "api: not an option it had")
    eq(v1.GetModuleOption("ItemTooltips", "crafting"), false, "api: a moved option reads its new home")
    professions.db.crafting = true
    eq(v1.GetModuleOption("ItemTooltips", "crafting"), true, "api: and follows it")
    eq(v1.OpenSettings("RecipeColors"), true, "api: an old name opens its new module")
    local toggled, changed = {}, {}
    v1.RegisterCallback("MODULE_TOGGLED", function(_, name, on) toggled[#toggled + 1] = name .. ":" .. tostring(on) end)
    v1.RegisterCallback("OPTION_CHANGED", function(_, name, key, value)
        changed[#changed + 1] = name .. "." .. key .. "=" .. tostring(value)
    end)
    tooltips.enabled = false
    moduleChanged("ItemTooltips", nil)
    tooltips.db.align = "inline"
    moduleChanged("ItemTooltips", "align")
    moduleChanged("ItemTooltips", "trace") -- a debug option isn't told
    eq(table.concat(toggled, ","), "ItemTooltips:false", "api: MODULE_TOGGLED")
    eq(table.concat(changed, ","), "ItemTooltips.align=inline", "api: OPTION_CHANGED, not for debug options")

    -- The profile in use, and PROFILE_CHANGED on a switch or its rename, not another's.
    local savedDB = api.db
    api.db = nil
    eq(v1.GetProfile(), nil, "api: no profile before READY")
    api.db = savedDB or {}
    local profileName, profileCount = v1.GetProfile()
    eq(profileName .. "," .. profileCount, "Default,3", "api: the profile in use and how many")
    local told = {}
    v1.RegisterCallback("PROFILE_CHANGED", function(_, name) told[#told + 1] = name end)
    api.API.Fire("READY")
    api.Profiles.names.p2 = "Solo 2"
    profilesChanged(false)
    api.Profiles.current = "p1"
    profilesChanged(true)
    api.Profiles.names.p1 = "Raids"
    profilesChanged(false)
    eq(table.concat(told, ","), "Raid,Raids", "api: PROFILE_CHANGED")

    -- A profile based on a preset (Lib/Presets.lua, read through the real Lib/Store.lua view):
    -- GetProfilePreset names it, and options and on/off read the preset for what isn't set.
    api.db = nil
    eq(v1.GetProfilePreset(), nil, "api: no preset before READY")
    api.db = {}
    local Store = ns.Store
    local linkedDB = { settings = { Linked = { mode = "b" } }, preset = "developer" }
    local linked = {
        title = "Linked", description = "Linked.", category = "items",
        defaults = { enabled = false, size = 1, mode = "a", seen = {} },
        options = {
            { key = "size", name = "Size", min = 1, max = 9 },
            { key = "mode", name = "Mode", choices = { { "a", "A" }, { "b", "B" } } },
        },
        presets = { developer = { enabled = true, options = { size = 5, mode = "a" } } },
    }
    api.modules.Linked = linked
    api.order[#api.order + 1] = "Linked"
    ns.modules, ns.order = api.modules, api.order -- what Lib/Presets.lua reads
    linked.db = Store.Load(linkedDB, {}, "Linked", linked.defaults)
    linked.enabled = linked.db.enabled -- as Core turns it on
    api.Profiles.Preset = function() return Store.Preset(linkedDB, nil) end
    local preset = v1.GetProfilePreset()
    eq(preset and preset.name .. "|" .. preset.title, "developer|Developer's Defaults",
        "api: the profile in use's preset")
    eq(v1.GetModuleOption("Linked", "size"), 5, "api: an option the player hasn't set reads the preset")
    eq(v1.GetModuleOption("Linked", "mode"), "b", "api: one they set reads theirs")
    eq(v1.IsModuleEnabled("Linked"), true, "api: a module the preset turns on is on")
    local info = v1.GetModuleInfo("Linked")
    eq(info.options[1].value .. "," .. tostring(info.options[1].default), "5,1",
        "api: GetModuleInfo's value is the preset's, its default the module's")
    local presets = v1.GetPresets()
    eq(#presets .. "," .. presets[1].name .. "," .. presets[1].title, "1,developer,Developer's Defaults",
        "api: every preset")
    presets[1].name = "changed"
    eq(v1.GetPresets()[1].name, "developer", "api: GetPresets gives copies")
    linkedDB.preset = "fromnewer"
    eq(v1.GetProfilePreset(), nil, "api: a preset this version doesn't have is none")
    eq(v1.GetModuleOption("Linked", "size"), 1, "api: and options read their defaults")
    api.db = savedDB

    -- Upgrade scores, while Upgrade Arrows offers them.
    C_Item.GetItemInfo = function(id)
        if id == 100 then
            return "Sword", "|Hitem:100::::::::60|h[Sword]|h"
        end
    end
    eq(v1.HasUpgradeScores(), false, "api: no scores while Upgrade Arrows is off")
    eq(v1.GetItemUpgradeInfo(100), nil, "api: no upgrade info while it's off")
    local upgradesTold = 0
    v1.RegisterCallback("UPGRADES_UPDATED", function() upgradesTold = upgradesTold + 1 end)
    ns.Providers.Set("upgrades", {
        Evaluate = function(link)
            if link:find("item:100") then
                return { upgrade = true, downgrade = false, percent = 12, score = 56, rival = 50 }
            elseif link:find("item:200") then
                return false
            end
        end,
        Score = function(link) return link:find("item:100") and 56 or nil end,
        Profile = function() return { key = "MAGE:3", class = "MAGE", tab = 3, weights = { INT = 1 } } end,
    })
    eq(upgradesTold, 1, "api: UPGRADES_UPDATED when scores are offered")
    local upgrade = v1.GetItemUpgradeInfo(100)
    eq(upgrade and upgrade.isUpgrade, true, "api: an upgrade, by ID")
    eq(upgrade and upgrade.percent == 12 and upgrade.equippedScore, 50, "api: its percent and what it beats")
    eq(v1.GetItemUpgradeInfo("|Hitem:200::|h[Shirt]|h").canUpgrade, false, "api: can't be an upgrade")
    eq(v1.GetItemUpgradeInfo("|Hitem:300::|h[New]|h"), nil, "api: not loaded yet")
    eq(v1.GetItemScore(100), 56, "api: an item's score")
    eq(v1.GetUpgradeProfile().key, "MAGE:3", "api: the profile in use")
    ns.Providers.Set("upgrades", nil)
    eq(upgradesTold, 2, "api: and when they go")

    -- Flight times, while Flight Timer offers them.
    eq(v1.GetFlightTime(1, 2), nil, "api: no flight times while Flight Timer is off")
    ns.Providers.Set("flights", {
        Time = function(from, to) return from == 1 and to == 2 and 95 or nil end,
        Current = function() return { from = 1, to = 2, total = 95, elapsed = 100 } end,
    })
    eq(v1.GetFlightTime(1, 2), 95, "api: a flight time")
    eq(v1.GetFlightTime(2, 1), nil, "api: each way is its own")
    local flying = v1.GetCurrentFlight()
    eq(flying and flying.duration == 95 and flying.remaining, 0, "api: the flight underway, never below 0 left")
    eq(flying.estimate, nil, "api: no estimate for a timed flight")
    eq(v1.GetFlightEstimate(1, 2), nil, "api: no estimates from an older provider")
    ns.Providers.Set("flights", {
        Time = function() return nil end,
        Estimate = function(from, to) return from == 2 and to == 6 and 259 or nil end,
        Current = function() return { from = 2, to = 6, estimate = 259, elapsed = 10 } end,
    })
    eq(v1.GetFlightEstimate(2, 6), 259, "api: a flight estimate")
    eq(v1.GetFlightEstimate("2", 6), nil, "api: estimates take node IDs")
    flying = v1.GetCurrentFlight()
    eq(flying.duration == nil and flying.remaining == nil and flying.estimate, 259,
        "api: a first flight's estimate, its duration still unknown")
    ns.Providers.Set("flights", nil)
    eq(v1.GetFlightEstimate(2, 6), nil, "api: no estimates while Flight Timer is off")

    -- Gathering Map's nodes, while it offers them, copied.
    eq(v1.GetGatheringMaps(), nil, "api: no nodes while Gathering Map is off")
    local remembered = {
        [1436] = { { name = "Copper Vein", kind = "ore", x = 0.5, y = 0.4, count = 2, time = 99 } },
        [1429] = { { name = "Peacebloom", kind = "herb", x = 0.1, y = 0.2, count = 0 } },
    }
    ns.Providers.Set("gatheringNodes", { Maps = function() return remembered end })
    local maps = v1.GetGatheringMaps()
    eq(maps and maps[1] .. "," .. maps[2], "1429,1436", "api: the maps with nodes, lowest first")
    local vein = v1.GetGatheringNodes(1436)[1]
    eq(vein.name .. ":" .. vein.kind .. ":" .. vein.timesGathered .. ":" .. vein.lastGathered,
        "Copper Vein:ore:2:99", "api: a node")
    vein.name = "Changed"
    eq(remembered[1436][1].name, "Copper Vein", "api: nodes are copies")
    eq(v1.GetGatheringNodes(1429)[1].timesGathered, 0, "api: one not gathered yet")
    eq(#v1.GetGatheringNodes(1), 0, "api: a map without any")
    ns.Providers.Set("gatheringNodes", nil)
    eq(v1.GetGatheringNodes(1436), nil, "api: gone with Gathering Map")

    -- A node's loot comes as a copy.
    local looted = { [1] = { { name = "Copper Vein", kind = "ore", x = 0.1, y = 0.1, count = 1,
        loot = { [2770] = 4 } } } }
    ns.Providers.Set("gatheringNodes", { Maps = function() return looted end })
    local lootCopy = v1.GetGatheringNodes(1)[1].loot
    eq(lootCopy[2770], 4, "api: a node's loot")
    lootCopy[2770] = 99
    eq(looted[1][1].loot[2770], 4, "api: loot is a copy")
    ns.Providers.Set("gatheringNodes", nil)

    -- Any node by name: herbs and veins, chests, and fishing pools.
    eq(v1.GetWorldNodeInfo("Copper Vein").kind, "ore", "api: a vein's kind")
    eq(v1.GetWorldNodeInfo("Battered Chest").kind, "treasure", "api: a chest")
    eq(v1.GetWorldNodeInfo("Oily Blackmouth School").kind, "fish", "api: a fishing pool")
    eq(v1.GetWorldNodeInfo("Mailbox"), nil, "api: not a node")
    eq(v1.GetFishingPoolByObject(123456), nil, "api: an object never seen")

    -- Every flight flown, and the flight callbacks from Flight Timer's take-off and landing.
    local flightState = { current = nil, last = nil }
    ns.Providers.Set("flights", {
        Time = function() return nil end,
        Current = function() return flightState.current end,
        AllTimes = function() return { ["2>1"] = 80, ["1>2"] = 95 } end,
        Last = function() return flightState.last end,
    })
    local times = v1.GetFlightTimes()
    eq(#times .. ":" .. times[1].fromNodeID .. ">" .. times[1].toNodeID .. "=" .. times[1].seconds,
        "2:1>2=95", "api: flight times, in order")
    local flightEvents = {}
    v1.RegisterCallback("FLIGHT_STARTED", function(_, from, to) flightEvents[#flightEvents + 1] = "up " .. from .. ">" .. to end)
    v1.RegisterCallback("FLIGHT_ENDED", function(_, from, to, s) flightEvents[#flightEvents + 1] = "down " .. from .. ">" .. to .. " " .. tostring(s) end)
    flightState.current = { from = 1, to = 2, elapsed = 0 }
    ns.Providers.Changed("flights")
    flightState.current, flightState.last = nil, { from = 1, to = 2, seconds = 96 }
    ns.Providers.Changed("flights")
    eq(table.concat(flightEvents, ","), "up 1>2,down 1>2 96", "api: flight callbacks")
    ns.Providers.Set("flights", nil)

    -- Flight points this character has learned, a copy.
    local learned = { [12] = true, [40] = true }
    ns.Providers.Set("flightPoints", { Known = function() return learned end })
    local knownPoints = v1.GetKnownFlightPoints()
    eq(knownPoints[12] and knownPoints[40], true, "api: known flight points")
    knownPoints[99] = true
    eq(learned[99], nil, "api: known flight points are a copy")
    ns.Providers.Set("flightPoints", nil)
    eq(v1.GetKnownFlightPoints(), nil, "api: none while Points of Interest is off")

    -- Talents and professions, without the game's data offline.
    eq(v1.GetTalentTabs(), nil, "api: no talent tabs without the game's data")
    eq(v1.GetProfessionSkill(186), nil, "api: no profession without the game's data")

    -- The map pin.
    local mapPin
    C_Map = {
        GetMapInfo = function(mapID) return mapID == 1411 and { mapID = 1411 } or nil end,
        GetBestMapForUnit = function() return 1411 end,
        CanSetUserWaypointOnMap = function() return true end,
        SetUserWaypoint = function(point) mapPin = point end,
        GetUserWaypoint = function() return mapPin end,
        ClearUserWaypoint = function() mapPin = nil end,
    }
    UiMapPoint = { CreateFromCoordinates = function(mapID, px, py)
        return { uiMapID = mapID, position = { x = px, y = py } }
    end }
    local pinChanged = 0
    v1.RegisterCallback("WAYPOINT_CHANGED", function() pinChanged = pinChanged + 1 end)
    eq(gameEvents.USER_WAYPOINT_UPDATED ~= nil, true, "api: listens for the pin once someone asks")
    eq(v1.SetWaypoint(nil, 0.5, 0.4), true, "api: a pin on the player's map")
    local pinMap, pinX, pinY = v1.GetWaypoint()
    eq(pinMap == 1411 and pinX == 0.5 and pinY, 0.4, "api: reads the pin")
    local _, why = v1.SetWaypoint("Nowhere", 0.5, 0.5)
    eq(why, "zone", "api: no such zone")
    _, why = v1.SetWaypoint(1411, 50, 50)
    eq(why, "range", "api: spots are 0 to 1")
    gameEvents.USER_WAYPOINT_UPDATED()
    eq(pinChanged, 1, "api: WAYPOINT_CHANGED")
    v1.ClearWaypoint()
    eq(v1.GetWaypoint(), nil, "api: the pin is cleared")
    eq(v1.GetWaypointTarget(), nil, "api: no arrow target while Waypoints is off")
    eq(#reported, 3, "api: nothing else went to the error handler")
end
