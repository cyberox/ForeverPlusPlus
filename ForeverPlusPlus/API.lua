-- The public API: what other addons may read from Forever++, as the global ForeverPlusPlusAPI.
-- Everything else in the addon is private to `ns`; this file is the only door, and docs/api.md is
-- its contract for addon authors.
--
-- Rules that keep it safe for both sides:
--   * Versioned. ForeverPlusPlusAPI.v1 never changes in a way that breaks a caller: functions and
--     return values are only ever added. A breaking change ships as v2 beside it.
--   * Read only. Callers get copies and plain values, never our own tables, and can't replace a
--     function another addon also calls.
--   * Can't break the caller. Every call is wrapped: an error of ours is reported to the error
--     handler (BugSack) and the call returns nil, as it does for anything we don't know.
--   * Says what it doesn't have. Data comes from modules the player may have off (no auction prices
--     without Item Tooltips' Auction Prices), and from what Forever++ has seen; nil means unknown.
local addonName, ns = ...

local type, pairs, ipairs, pcall, error = type, pairs, ipairs, pcall, error
local tonumber, tostring, setmetatable, floor = tonumber, tostring, setmetatable, math.floor
local match, sort = string.match, table.sort
local C_Item, InCombatLockdown = C_Item, InCombatLockdown

local API = {}
ns.API = API

local v1 = {} -- the functions, behind a read-only table

-- Safety -----------------------------------------------------------------------------------------

local function report(err)
    local handler = geterrorhandler and geterrorhandler()
    if handler then
        handler(err)
    end
end

local function finish(ok, ...)
    if ok then
        return ...
    end
    report(...)
    return nil
end

-- Adds a function to v1, wrapped so an error of ours returns nil instead of reaching the caller.
local function export(name, fn)
    v1[name] = function(...)
        return finish(pcall(fn, ...))
    end
end

local function readOnly(contents, label)
    return setmetatable({}, {
        __index = contents,
        __newindex = function()
            error(label .. " is read only", 2)
        end,
        __metatable = false,
    })
end

-- Shared helpers ---------------------------------------------------------------------------------

-- An item ID from an ID, a "4305" string, an item link or "item:4305" string, or an item's name
-- (the client's item cache, or else the items with an auction price).
local function itemID(item)
    if type(item) == "number" then
        return item > 0 and floor(item) or nil
    end
    if type(item) ~= "string" or item == "" then
        return nil
    end
    local id = tonumber(item) or tonumber(match(item, "item:(%d+)"))
    if id then
        return id
    end
    return ns.Prices.ItemByName(item)
end

-- A color's r, g, b (0 to 1) and its "ffrrggbb" hex, like a class color's colorStr.
local function colorValues(color)
    if type(color) ~= "table" then
        return nil
    end
    local r, g, b
    if color.GetRGB then
        r, g, b = color:GetRGB()
    else
        r, g, b = color.r, color.g, color.b
    end
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
        return nil
    end
    return r, g, b, ns.Colors.Hex(r, g, b)
end

-- General ----------------------------------------------------------------------------------------

---This API's version (1 for v1) and Forever++'s, such as "1.0.0".
export("GetVersion", function()
    return 1, ns.version or ns.Metadata("Version")
end)

---Whether Forever++ has loaded its saved data (after PLAYER_LOGIN). Before it, saved data such as
---players seen and module states isn't there yet; the READY callback says when it is.
export("IsReady", function()
    return ns.db ~= nil
end)

-- Old names ------------------------------------------------------------------------------------
-- A module that became a part of another keeps answering by its old name, with the new truth, so
-- an addon written against the old one doesn't break: on while the new module and its part are,
-- and its options read where they went. Options that moved out of a module that is still there
-- answer by their old module too. GetModules and the callbacks know only the new names.

local MOVED_MODULES = {
    -- Recipe Colors, a module up to 1.4.0, is the Professions module's Recipe Colors part.
    RecipeColors = { module = "Professions", part = "recipeColors", title = "PROFESSIONS_COLORS",
        description = "PROFESSIONS_COLORS_DESC", options = { highlight = "highlight", gray = "gray" } },
}
local MOVED_OPTIONS = {
    -- Crafting Costs, Item Tooltips' option up to 1.4.0, is the Professions module's part.
    ItemTooltips = { crafting = { "Professions", "crafting" } },
}

-- The module a moved one went to, and its entry above, when this client gets that module.
local function movedModule(name)
    local moved = type(name) == "string" and MOVED_MODULES[name]
    local module = moved and ns.modules[moved.module]
    if module and not module.unavailable then
        return module, moved
    end
end

-- Whether a moved module counts as on: its new module and its part both are.
local function movedEnabled(module, moved)
    return module.enabled and ns.PartOn(module, moved.part) and true or false
end

---Whether a module is on, by its internal name ("ItemTooltips", "ClassColors"; see GetModules).
---Nil for a name Forever++ doesn't have.
export("IsModuleEnabled", function(name)
    local module = type(name) == "string" and ns.modules[name]
    -- One this client doesn't get is no module at all, as GetModules has it.
    if not module or module.unavailable then
        local new, moved = movedModule(name)
        if new then
            return movedEnabled(new, moved)
        end
        return nil
    end
    return module.enabled and true or false
end)

---The name of the profile this character uses ("Default" until the player makes another one), and
---how many profiles there are. Nil before READY.
export("GetProfile", function()
    if not ns.db then
        return nil
    end
    local Profiles = ns.Profiles
    return Profiles.Name(Profiles.Current()), Profiles.Count()
end)

---The preset the profile in use is based on, as { name, title }: `name` is its key ("developer"),
---`title` its name in the player's language ("Developer's Defaults"). A profile based on a preset
---reads the preset's values for what the player hasn't set, so GetModuleOption and IsModuleEnabled
---already include them. Nil for a profile based on none, and before READY.
export("GetProfilePreset", function()
    if not ns.db then
        return nil
    end
    local Profiles = ns.Profiles
    local name = Profiles.Preset(Profiles.Current())
    if not name then
        return nil
    end
    return { name = name, title = ns.Presets.Title(name) }
end)

---Every preset Forever++ has, in order, as { name, title, description }.
export("GetPresets", function()
    local list = {}
    for _, name in ipairs(ns.Presets.List()) do
        list[#list + 1] = { name = name, title = ns.Presets.Title(name),
            description = ns.Presets.Description(name) }
    end
    return list
end)

-- The module called `name`, when this client gets it.
local function findModule(name)
    local module = type(name) == "string" and ns.modules[name]
    if module and not module.unavailable then
        return module
    end
end

-- The option `key` of a module, from what Settings shows (not data, not debug options).
local function findOption(module, key)
    for _, option in ipairs(module.options or {}) do
        if option.key == key and not option.debug then
            return option
        end
    end
end

-- One option as GetModuleInfo lists it, under `key` (its old key, for a moved module).
local function optionInfo(module, option, key)
    local choices
    if option.choices then
        choices = {}
        for i, choice in ipairs(option.choices) do
            choices[i] = choice[1]
        end
    end
    return {
        key = key or option.key,
        name = option.name,
        kind = ns.OptionKind(option),
        value = module.db and module.db[option.key],
        default = module.defaults[option.key],
        choices = choices,
        min = option.min,
        max = option.max,
    }
end

---A module in full: { name, title, description, category, enabled, options }, where options is a
---list of { key, name, kind ("checkbox", "dropdown", or "slider"), value, default, choices (a
---dropdown's values), min, max }, as the Modules page shows them. Nil for a module that isn't
---there.
export("GetModuleInfo", function(name)
    local module = findModule(name)
    local moved
    if not module then
        module, moved = movedModule(name)
        if not module then
            return nil
        end
    end
    local options = {}
    if moved then
        -- Only the options it had, by their old keys, read where they are now.
        for _, option in ipairs(module.options or {}) do
            for old, new in pairs(moved.options) do
                if option.key == new and not option.debug then
                    options[#options + 1] = optionInfo(module, option, old)
                end
            end
        end
    else
        for _, option in ipairs(module.options or {}) do
            if not option.debug then
                options[#options + 1] = optionInfo(module, option)
            end
        end
    end
    local enabled = module.enabled and true or false
    local title, description = module.title or name, module.description
    if moved then
        enabled = movedEnabled(module, moved)
        title, description = ns.L[moved.title] or title, ns.L[moved.description] or description
    end
    return {
        name = name,
        title = title,
        description = description,
        category = module.category,
        enabled = enabled,
        -- Locked off because the game broke it: it can't be turned on, so don't send the player
        -- to. And whether it has found it can't work (its name is red in Settings).
        locked = module.locked and true or false,
        problem = module.Problem and module:Problem() and true or false,
        options = options,
    }
end)

---One of a module's options as the player set it (or, unset, what the profile's preset says, or
---its default: what the module itself reads), or nil for an option the module doesn't have. Read
---only: the player's settings are theirs to change.
export("GetModuleOption", function(name, key)
    local module = findModule(name)
    local moved = MOVED_OPTIONS[name] and MOVED_OPTIONS[name][key]
    if moved then
        module, key = findModule(moved[1]), moved[2]
    elseif not module then
        local into
        module, into = movedModule(name)
        key = into and into.options[key]
    end
    if not (module and module.db and key and findOption(module, key)) then
        return nil
    end
    return module.db[key]
end)

---Opens Forever++'s settings on a module (or the Modules page without one), for a button in
---another addon's options that sends the player here. False in combat, when Settings can't open.
export("OpenSettings", function(name)
    if InCombatLockdown and InCombatLockdown() then
        return false
    end
    if not ns.OpenSettings then
        return false
    end
    if not findModule(name) then
        name = movedModule(name) and MOVED_MODULES[name].module or nil -- an old name opens its new module
    end
    return ns.OpenSettings(name) and true or false
end)

---Every module: a list of { name, title, category, enabled } in load order. Leaves out modules
---this client doesn't get.
export("GetModules", function()
    local list = {}
    for _, name in ipairs(ns.order) do
        local module = ns.modules[name]
        if not module.unavailable then
            list[#list + 1] = {
                name = name,
                title = module.title or name,
                category = module.category,
                enabled = module.enabled and true or false,
            }
        end
    end
    return list
end)

-- Auction prices ---------------------------------------------------------------------------------

---Whether Forever++ has auction prices to give: Item Tooltips' Auction Prices is on.
export("HasAuctionPrices", function()
    return ns.Prices.Available()
end)

---Where the prices come from: "Auctionator" (the player chose its prices), "ForeverPlusPlus" (our
---own scans), or nil without prices.
export("GetAuctionPriceSource", function()
    if not ns.Prices.Available() then
        return nil
    end
    return ns.Prices.UsingAuctionator() and "Auctionator" or "ForeverPlusPlus"
end)

---The lowest buyout for one of an item, in copper, and the time() it was seen (nil when unknown).
---Nil for no price. `item` is an item ID, link, or name.
export("GetAuctionPrice", function(item)
    local id = itemID(item)
    if not id then
        return nil
    end
    local copper, seenAt = ns.Prices.Auction(id)
    if type(copper) ~= "number" then
        return nil
    end
    return copper, seenAt
end)

-- Disenchanting ----------------------------------------------------------------------------------

-- An item's disenchant outcomes and bracket from its item info (see ns.Disenchant.ForItem): nil,
-- nil when not disenchantable or not cached yet, nil and a bracket when its results aren't known.
local function outcomes(item)
    local id = itemID(item)
    if not (id and C_Item and C_Item.GetItemInfo) then
        return nil
    end
    local _, _, quality, itemLevel, _, _, _, _, equipLoc, _, _, classID = C_Item.GetItemInfo(id)
    if not quality then
        return nil
    end
    return ns.Disenchant.ForItem(classID, quality, equipLoc, itemLevel)
end

---Whether an item can be disenchanted, by the game's own brackets, even when what it gives isn't
---known yet. Nil when the client hasn't loaded the item yet.
export("CanDisenchant", function(item)
    local id = itemID(item)
    if not (id and C_Item and C_Item.GetItemInfo) or not C_Item.GetItemInfo(id) then
        return nil
    end
    local _, bracket = outcomes(item)
    return bracket ~= nil
end)

---What disenchanting an item gives, most likely first: a list of { itemID, chance (0 to 1), min,
---max }, with `seen` on each when it's learned from the player's disenchants (how many). Nil when
---it can't be disenchanted, what it gives isn't known yet, or the client hasn't loaded the item
---yet. Classic's rules where the game's brackets match them; Forever's may differ.
export("GetDisenchantResults", function(item)
    local list = outcomes(item)
    if not list then
        return nil
    end
    local copy = {}
    for i, each in ipairs(list) do
        copy[i] = { itemID = each.item, chance = each.chance, min = each.min, max = each.max, seen = each.seen }
    end
    return copy
end)

---What disenchanting an item is worth on average, in copper, at the auction prices, and how many
---of its outcomes had no price (the total leaves them out). Nil without prices or outcomes.
export("GetDisenchantValue", function(item)
    if not ns.Prices.Available() then
        return nil
    end
    local list = outcomes(item)
    if not list then
        return nil
    end
    return ns.Disenchant.Value(list, ns.Prices.Auction)
end)

-- Upgrade Arrows ---------------------------------------------------------------------------------
-- Offered by Upgrade Arrows while it's on (Lib/Providers.lua), judged by the same stat weights and
-- the same comparison against what's worn as its arrows.

-- An item link from an ID, link, or name: a link keeps the suffix and enchant a score depends on.
local function itemLink(item)
    if type(item) == "string" and match(item, "item:%d+") then
        return item
    end
    local id = itemID(item)
    if not (id and C_Item and C_Item.GetItemInfo) then
        return nil
    end
    local _, link = C_Item.GetItemInfo(id)
    return link
end

---Whether upgrade scores can be read: Upgrade Arrows is on.
export("HasUpgradeScores", function()
    return ns.Providers.Get("upgrades") ~= nil
end)

---How an item compares with what the player wears, as Upgrade Arrows judges it: { isUpgrade,
---isDowngrade, percent (better or worse than what it replaces; nil against an empty slot), score,
---equippedScore }. { canUpgrade = false } for something that can't be an upgrade (not gear, can't
---be used, already worn); canUpgrade is true otherwise. Nil while Upgrade Arrows is off or the
---client hasn't loaded the item. Pass a link where you have one: it carries the item's suffix.
export("GetItemUpgradeInfo", function(item)
    local upgrades = ns.Providers.Get("upgrades")
    local link = upgrades and itemLink(item)
    if not link then
        return nil
    end
    local result = upgrades.Evaluate(link)
    if result == false then
        return { canUpgrade = false, isUpgrade = false, isDowngrade = false }
    elseif not result then
        return nil
    end
    return {
        canUpgrade = true,
        isUpgrade = result.upgrade and true or false,
        isDowngrade = result.downgrade and true or false,
        percent = result.percent,
        score = result.score,
        equippedScore = result.rival,
    }
end)

---An item's score by the stat weights in use, whether or not it could be an upgrade. Nil while
---Upgrade Arrows is off or the client hasn't loaded the item.
export("GetItemScore", function(item)
    local upgrades = ns.Providers.Get("upgrades")
    local link = upgrades and itemLink(item)
    if not link then
        return nil
    end
    return upgrades.Score(link)
end)

---The stat weights gear is judged by: { key ("MAGE:3"), class, tab (the talent tab, nil for Bear),
---bear, guess (true while there are no talent points to go by), weights = { [stat] = weight } },
---stats in short keys such as "STR", "SP", "HIT". Nil while Upgrade Arrows is off.
export("GetUpgradeProfile", function()
    local upgrades = ns.Providers.Get("upgrades")
    return upgrades and upgrades.Profile() or nil
end)

-- Flight Timer -----------------------------------------------------------------------------------
-- Offered by Flight Timer while it's on. Flight points are the game's node IDs (C_TaxiMap's
-- nodeID), and a time is known once the player has flown that route.

---Seconds the flight from one flight point to another takes, once it has been flown, or nil.
export("GetFlightTime", function(fromNodeID, toNodeID)
    local flights = ns.Providers.Get("flights")
    if not (flights and type(fromNodeID) == "number" and type(toNodeID) == "number") then
        return nil
    end
    return flights.Time(fromNodeID, toNodeID)
end)

---Estimated seconds of the direct flight from one flight point to another, from the game's own
---flight paths, flown or not, or nil when no direct path joins them (or Flight Timer is off).
export("GetFlightEstimate", function(fromNodeID, toNodeID)
    local flights = ns.Providers.Get("flights")
    if not (flights and flights.Estimate and type(fromNodeID) == "number"
        and type(toNodeID) == "number") then
        return nil
    end
    return flights.Estimate(fromNodeID, toNodeID)
end)

---The flight underway: { fromNodeID, toNodeID, duration (nil the first time a route is flown),
---estimate (the first time, Flight Timer's estimate when it has one), elapsed, remaining }, in
---seconds. Nil while not flying or Flight Timer is off.
export("GetCurrentFlight", function()
    local flights = ns.Providers.Get("flights")
    local current = flights and flights.Current()
    if not current then
        return nil
    end
    local remaining = current.total and current.total - current.elapsed
    return {
        fromNodeID = current.from,
        toNodeID = current.to,
        duration = current.total,
        estimate = current.estimate,
        elapsed = current.elapsed,
        remaining = remaining and (remaining > 0 and remaining or 0) or nil,
    }
end)

---Every flight this account has flown and timed: a list of { fromNodeID, toNodeID, seconds }, or
---nil while Flight Timer is off.
export("GetFlightTimes", function()
    local flights = ns.Providers.Get("flights")
    if not (flights and flights.AllTimes) then
        return nil
    end
    local list = {}
    for route, seconds in pairs(flights.AllTimes()) do
        local from, to = match(route, "^(%d+)>(%d+)$")
        if from and type(seconds) == "number" then
            list[#list + 1] = { fromNodeID = tonumber(from), toNodeID = tonumber(to), seconds = seconds }
        end
    end
    sort(list, function(a, b)
        if a.fromNodeID ~= b.fromNodeID then
            return a.fromNodeID < b.fromNodeID
        end
        return a.toNodeID < b.toNodeID
    end)
    return list
end)

-- Points of Interest (a part of World Map) ----------------------------------------------------

---The flight points this character has learned, as far as Forever++ has seen at a flight master:
---a set of the game's node IDs (C_TaxiMap's nodeID) -> true. Forever's own map list can't say which
---are learned. Nil while World Map's Points of Interest is off.
export("GetKnownFlightPoints", function()
    local points = ns.Providers.Get("flightPoints")
    if not points then
        return nil
    end
    local known = {}
    for nodeID in pairs(points.Known() or {}) do
        if type(nodeID) == "number" then
            known[nodeID] = true
        end
    end
    return known
end)

-- Talents ----------------------------------------------------------------------------------------
-- Forever keeps Classic's three talent trees inside the Mainline talent system, so the game has
-- no "spec" to ask for.

---The player's talent trees in order: a list of { index, name, spent }, and the index of the one
---with the most points (the first wins a tie). Nil while the game has no talent data yet.
export("GetTalentTabs", function()
    local tabs = ns.Talents.Tabs()
    if not tabs then
        return nil
    end
    local list = {}
    for i, tab in ipairs(tabs) do
        list[i] = { index = tab.index, name = tab.name, spent = tab.spent }
    end
    local dominant = ns.Talents.Dominant()
    return list, dominant and dominant.index
end)

-- Waypoints and maps -----------------------------------------------------------------------------
-- The waypoint is Blizzard's own map pin (the user waypoint), the one /way and a map click set,
-- so it shows on the map, in the world, and on Waypoints' arrow. Spots are 0 to 1 across and down
-- a map, as C_Map gives them.

---A zone's map ID by its name (in the player's language; "#1429" for a map ID), a zone before any
---other map of that name, then the first zone whose name starts with it. Nil when there's none.
export("FindZone", function(name)
    if type(name) ~= "string" then
        return nil
    end
    return ns.WorldMap.FindMap(name)
end)

---Where the player stands: map ID and x, y (0 to 1). Nil when the game can't say, as in a dungeon.
export("GetPlayerPosition", function()
    return ns.WorldMap.PlayerPosition()
end)

---Puts the map pin at x, y (0 to 1) on `map`: a map ID, a zone name (as FindZone), or nil for the
---player's map. True when it's set; else false and why: "zone" (no such zone), "range" (x or y
---outside 0 to 1), "map" (no pin allowed there, like in a dungeon), or "unavailable".
export("SetWaypoint", function(map, x, y)
    if type(x) ~= "number" or type(y) ~= "number" then
        return false, "range"
    end
    local mapID = map
    if type(map) == "string" then
        mapID = ns.WorldMap.FindMap(map)
    elseif map == nil then
        mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    end
    if type(mapID) ~= "number" then
        return false, "zone"
    end
    return ns.WorldMap.SetWaypoint(mapID, x, y)
end)

---The map pin: map ID and x, y (0 to 1), or nil when there's none.
export("GetWaypoint", function()
    if not (C_Map and C_Map.GetUserWaypoint) then
        return nil
    end
    local point = C_Map.GetUserWaypoint()
    local position = point and point.position
    if not (position and type(position.x) == "number" and type(position.y) == "number") then
        return nil
    end
    return point.uiMapID, position.x, position.y
end)

---Takes the map pin away.
export("ClearWaypoint", function()
    if C_Map and C_Map.ClearUserWaypoint then
        C_Map.ClearUserWaypoint()
    end
end)

---What Waypoints' arrow points at: { kind ("pin", "quest" for the quest selected on the map, or
---"corpse"), mapID, x, y, title (a quest's), yards (nil when the game can't say how far) }. Nil
---while there's nothing to point at, or Waypoints or its Arrow is off.
export("GetWaypointTarget", function()
    local waypoints = ns.Providers.Get("waypoints")
    return waypoints and waypoints.Target() or nil
end)

-- Players seen -----------------------------------------------------------------------------------

---What Forever++ last saw of another player, for the account: { class (token, "MAGE"),
---className (localized), level, race (localized), guild, lastSeen (time()) }, any field nil when
---unknown. Nil for someone never seen. `name` may carry a surname ("Bob-Surname"); `guid` is
---optional and tells players on other realms apart. Learned while a module that uses it is on
---(Chat Levels, Class Colors' Offline Friends, Whisper Window); what was saved reads either way.
export("GetPlayerInfo", function(name, guid)
    if type(name) ~= "string" then
        name = nil
    end
    if type(guid) ~= "string" then
        guid = nil
    end
    if not (name or guid) then
        return nil
    end
    local entry = ns.Players.Get(guid, name)
    if not entry then
        return nil
    end
    return {
        class = entry.class,
        className = ns.Players.ClassName(entry.class),
        level = entry.level,
        race = entry.race,
        guild = entry.guild,
        lastSeen = entry.seen,
    }
end)

---A player's class color from what Forever++ last saw of them: r, g, b (0 to 1) and "ffrrggbb".
---Nil when their class isn't known.
export("GetPlayerClassColor", function(name, guid)
    local info = v1.GetPlayerInfo(name, guid)
    if not (info and info.class) then
        return nil
    end
    return colorValues(ns.Colors.ClassToken(info.class))
end)

-- Colors -----------------------------------------------------------------------------------------

---A class token's color ("MAGE"): r, g, b (0 to 1) and "ffrrggbb", or nil.
export("GetClassColor", function(classToken)
    if type(classToken) ~= "string" then
        return nil
    end
    return colorValues(ns.Colors.ClassToken(classToken))
end)

---The color of a level range against the player's level, like a quest's (red or orange above
---you, yellow while you're in it, green or gray once outleveled): r, g, b and "ffrrggbb". `high`
---defaults to `low`, for one level.
export("GetLevelColor", function(low, high)
    if type(low) ~= "number" then
        return nil
    end
    if type(high) ~= "number" then
        high = low
    end
    return colorValues(ns.Colors.LevelRange(low, high))
end)

-- Dungeons and raids -----------------------------------------------------------------------------

local function instanceInfo(key, instance)
    return {
        key = key,
        instanceID = instance[1],
        name = ns.Instances.Name(instance),
        englishName = instance[2],
        minLevel = instance[3],
        maxLevel = instance[4],
        isRaid = instance[5] and true or false,
    }
end

---Every dungeon and raid Forever++ knows, by lowest level: a list of { key, instanceID, name (in the
---player's language), englishName, minLevel, maxLevel, isRaid }. Levels follow the dungeon finder
---once it has listed them.
export("GetInstances", function()
    -- Brought up to date first: the walk mustn't add dungeons to the table it walks.
    ns.Instances.Refresh()
    local list = {}
    for key, instance in pairs(ns.Instances.byKey) do
        list[#list + 1] = instanceInfo(key, instance)
    end
    sort(list, function(a, b)
        if a.minLevel ~= b.minLevel then
            return (a.minLevel or 0) < (b.minLevel or 0)
        end
        return a.englishName < b.englishName
    end)
    return list
end)

---One dungeon or raid, by instance ID or name (the player's language or English), shaped as in
---GetInstances. Nil when it isn't one.
export("GetInstanceInfo", function(instance)
    ns.Instances.Refresh()
    if type(instance) == "string" then
        local found = ns.Instances.ByName(instance)
        if not found then
            return nil
        end
        for key, each in pairs(ns.Instances.byKey) do
            if each == found then
                return instanceInfo(key, each)
            end
        end
    elseif type(instance) == "number" then
        for key, each in pairs(ns.Instances.byKey) do
            if each[1] == instance then
                return instanceInfo(key, each)
            end
        end
    end
    return nil
end)

-- Gathering --------------------------------------------------------------------------------------

---A herb or vein by its name in the world: { skillLine (182 Herbalism, 186 Mining), skill (needed),
---itemID (what it gives) }, any field nil when not known yet. Nil for a name that isn't a node.
export("GetGatheringNode", function(name)
    if type(name) ~= "string" then
        return nil
    end
    local node = ns.Professions.Node(name)
    if not node then
        return nil
    end
    return { skillLine = node[1], skill = node[2], itemID = node[3] }
end)

---The gathering skill an item comes from: its skill line and the skill of the lowest herb or vein
---that gives it, or nil. `item` is an item ID, link, or name.
export("GetItemGatheringSkill", function(item)
    local id = itemID(item)
    if not id then
        return nil
    end
    return ns.Professions.ItemSkill(id)
end)

---The Skinning skill a creature of `level` needs.
export("GetSkinningSkill", function(level)
    if type(level) ~= "number" then
        return nil
    end
    return ns.Professions.SkinningNeed(level)
end)

-- Gathering Map ----------------------------------------------------------------------------------
-- Offered by Gathering Map while it's on: the herbs, veins, chests, and fishing pools it remembers
-- for the account, by zone map ID (C_Map's uiMapID), whatever this character shows or hides.

---The zone map IDs with remembered nodes, lowest first, or nil while Gathering Map is off.
export("GetGatheringMaps", function()
    local nodes = ns.Providers.Get("gatheringNodes")
    if not nodes then
        return nil
    end
    local ids = {}
    for mapID in pairs(nodes.Maps()) do
        ids[#ids + 1] = mapID
    end
    sort(ids)
    return ids
end)

---The nodes remembered on a zone map: a list of { name, kind ("herb", "ore", "treasure", "fish"),
---x, y (0 to 1 across the map), timesGathered (0 for one seen or tried but not gathered),
---lastGathered (time(), or nil) }. An empty list for a map without any; nil while Gathering Map is
---off.
export("GetGatheringNodes", function(mapID)
    local nodes = ns.Providers.Get("gatheringNodes")
    if not (nodes and type(mapID) == "number") then
        return nil
    end
    local list = {}
    for _, node in ipairs(nodes.Maps()[mapID] or {}) do
        local loot = {}
        for item, count in pairs(node.loot or {}) do
            if type(item) == "number" and type(count) == "number" then
                loot[item] = count
            end
        end
        list[#list + 1] = { name = node.name, kind = node.kind, x = node.x, y = node.y,
            timesGathered = node.count or 0, lastGathered = node.time, loot = loot }
    end
    return list
end)

---Any node by the name the world shows: a herb or vein, a treasure chest, or a fishing pool, as
---{ kind ("herb", "ore", "treasure", "fish"), skillLine, skill (needed), itemID (what it gives),
---lockpicking (the Lockpicking a locked chest takes) }, any field nil when not known yet. Nil for
---a name that isn't one Forever++ knows. Learned in play, so names Forever adds fill in.
export("GetWorldNodeInfo", function(name)
    if type(name) ~= "string" then
        return nil
    end
    local Professions = ns.Professions
    local node = Professions.Node(name)
    if node then
        return { kind = Professions.LineKind(node[1]), skillLine = node[1], skill = node[2],
            itemID = node[3] }
    end
    local chest, lock = Professions.Chest(name)
    if chest then
        return { kind = "treasure", skillLine = lock and Professions.LOCKPICKING or nil,
            lockpicking = lock }
    end
    if Professions.Pool(name) then
        return { kind = "fish", skillLine = Professions.FISHING }
    end
    return nil
end)

---The fishing pool a world object ID (from a GUID) was seen as, by the name the world shows, or
---nil.
export("GetFishingPoolByObject", function(objectID)
    if type(objectID) ~= "number" then
        return nil
    end
    return ns.Professions.PoolByObject(objectID)
end)

---The player's skill in a profession by skill line (182 Herbalism, 186 Mining, 356 Fishing, 393
---Skinning, a crafting one, or 633 Lockpicking for a rogue): rank (with gear and racial bonuses),
---level (as its window shows it), max (the most its rank allows), and its name. Nil without it.
export("GetProfessionSkill", function(skillLine)
    if type(skillLine) ~= "number" then
        return nil
    end
    local rank, name = ns.Professions.Rank(skillLine)
    if not rank then
        return nil
    end
    local level, max = ns.Professions.Progress(skillLine)
    return { rank = rank, level = level or rank, max = max, name = name }
end)

-- Callbacks --------------------------------------------------------------------------------------
-- RegisterCallback(event, fn, owner): fn(event, ...) runs on each event. An owner (any value, such
-- as the caller's addon table) can hold one function per event; without one, the function itself
-- is the owner. Events:
--   READY             saved data has loaded (once, after PLAYER_LOGIN)
--   PRICES_UPDATED    auction prices changed: a scan or browse, a reset, or their source changed
--                     (at most once a second)
--   UPGRADES_UPDATED  upgrade scores changed: gear, level, talents, weights, Upgrade Arrows'
--                     options, or it turned on or off (at most twice a second)
--   MODULE_TOGGLED    name, enabled: the player turned a module on or off
--   OPTION_CHANGED    name, key, value: the player changed one of a module's options
--   WAYPOINT_CHANGED  the map pin was set, moved, or cleared, by anyone
--   GATHERING_NODES_UPDATED  Gathering Map's nodes changed: a gather, a forget, an import, or it
--                     turned on or off (at most twice a second)
--   GATHERED          gather: the player gathered a herb, vein, chest, or fishing pool, or tried
--                     one too high for their skill (listened for only once someone registers)
--   FLIGHT_STARTED    fromNodeID, toNodeID: a flight took off (while Flight Timer is on)
--   FLIGHT_ENDED      fromNodeID, toNodeID, seconds: it landed
--   PROFILE_CHANGED   name: this character switched to another profile, or the one it uses was
--                     renamed or replaced by an import
-- What a game event drives (WAYPOINT_CHANGED) is listened to only once someone registers for it.

local listen = {} -- event -> fn that starts listening, run on the first registration

listen.WAYPOINT_CHANGED = function()
    if ns.HasEvent("USER_WAYPOINT_UPDATED") then
        ns.On("USER_WAYPOINT_UPDATED", function()
            API.Fire("WAYPOINT_CHANGED")
        end)
    end
end

-- A gather as another addon gets it: a copy, since Lib/Gathering's own table mustn't be kept.
local function gatherInfo(gather)
    local items = {}
    for i, item in ipairs(gather.items or {}) do
        items[i] = { id = item.id, count = item.count }
    end
    return {
        name = gather.name,
        kind = gather.kind,
        skillLine = gather.line,
        mapID = gather.mapID,
        x = gather.x,
        y = gather.y,
        objectID = gather.objectID,
        items = items,
        requires = gather.requires,
    }
end

listen.GATHERED = function()
    ns.Gathering.Listen(function(gather)
        if gather.name then
            API.Fire("GATHERED", gatherInfo(gather))
        end
    end, true)
end

local EVENTS = { READY = true, PRICES_UPDATED = true, UPGRADES_UPDATED = true, MODULE_TOGGLED = true,
    OPTION_CHANGED = true, WAYPOINT_CHANGED = true, GATHERING_NODES_UPDATED = true, GATHERED = true,
    FLIGHT_STARTED = true, FLIGHT_ENDED = true, PROFILE_CHANGED = true }
local callbacks = {} -- event -> owner -> fn
local profileName -- the profile name PROFILE_CHANGED last told (or READY's), so a rename of another isn't told

---Calls every function registered for `event`, each wrapped so one failing can't stop the rest.
---@param event string
function API.Fire(event, ...)
    if event == "READY" then
        profileName = ns.Profiles.Name(ns.Profiles.Current())
    end
    local owners = callbacks[event]
    if not owners then
        return
    end
    -- The functions as they are now: a callback that registers or unregisters one mustn't change
    -- the table this walks.
    local fns = {}
    for _, fn in pairs(owners) do
        fns[#fns + 1] = fn
    end
    for i = 1, #fns do
        finish(pcall(fns[i], event, ...))
    end
end

export("RegisterCallback", function(event, fn, owner)
    -- A caller's mistake goes to the error handler too (the call returns nil), so its author sees it.
    if not EVENTS[event] then
        error(addonName .. ": no API event called " .. tostring(event), 0)
    end
    if type(fn) ~= "function" then
        error(addonName .. ": RegisterCallback needs a function", 0)
    end
    callbacks[event] = callbacks[event] or {}
    callbacks[event][owner or fn] = fn
    if listen[event] then
        local start = listen[event]
        listen[event] = nil
        start()
    end
    return true
end)

export("UnregisterCallback", function(event, owner)
    local owners = callbacks[event]
    if owners and owner ~= nil then
        owners[owner] = nil
    end
end)

-- Prices change in bursts while the auction house is browsed, so they're told once a second.
local pricesChanged = ns.Frames.Coalesce(function()
    API.Fire("PRICES_UPDATED")
end, 1)
ns.Prices.OnChanged(pricesChanged)

-- Scores are forgotten for every piece of gear changed, a few at a time.
ns.Providers.OnChanged("upgrades", ns.Frames.Coalesce(function()
    API.Fire("UPGRADES_UPDATED")
end, 0.5))

-- Flight Timer says when a flight takes off and lands; Current tells which it is.
local flying
ns.Providers.OnChanged("flights", function()
    local flights = ns.Providers.Get("flights")
    local current = flights and flights.Current()
    if current and not flying then
        flying = current
        API.Fire("FLIGHT_STARTED", current.from, current.to)
    elseif not current and flying then
        local last = flights and flights.Last and flights.Last()
        local from, to = flying.from, flying.to
        flying = nil
        API.Fire("FLIGHT_ENDED", from, to, last and last.from == from and last.to == to and last.seconds
            or nil)
    end
end)

-- A forget or an import changes many nodes at once.
ns.Providers.OnChanged("gatheringNodes", ns.Frames.Coalesce(function()
    API.Fire("GATHERING_NODES_UPDATED")
end, 0.5))

ns.Profiles.OnChanged(function(switched)
    local name = ns.Profiles.Name(ns.Profiles.Current())
    if switched or name ~= profileName then
        profileName = name
        API.Fire("PROFILE_CHANGED", name)
    end
end)

ns.OnModuleChanged(function(name, key)
    local module = ns.modules[name]
    if key == nil then
        API.Fire("MODULE_TOGGLED", name, module.enabled and true or false)
    elseif findOption(module, key) then
        API.Fire("OPTION_CHANGED", name, key, module.db[key])
    end
end)

-- The global ---------------------------------------------------------------------------------------

ForeverPlusPlusAPI = readOnly({ v1 = readOnly(v1, "ForeverPlusPlusAPI.v1") }, "ForeverPlusPlusAPI")
