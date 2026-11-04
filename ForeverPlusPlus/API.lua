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
local tonumber, tostring, setmetatable, format, floor = tonumber, tostring, setmetatable, string.format, math.floor
local match, sort = string.match, table.sort
local C_Item = C_Item

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
    return r, g, b, format("ff%02x%02x%02x", floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5))
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

---Whether a module is on, by its internal name ("ItemTooltips", "ClassColors"; see GetModules).
---Nil for a name Forever++ doesn't have.
export("IsModuleEnabled", function(name)
    local module = type(name) == "string" and ns.modules[name]
    if not module then
        return nil
    end
    return module.enabled and true or false
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

-- An item's disenchant outcomes from its item info, or nil (not disenchantable, or not cached yet).
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

---What disenchanting an item gives, most likely first: a list of { itemID, chance (0 to 1), min,
---max }. Nil when it can't be disenchanted, or the client hasn't loaded the item yet. Classic's
---rules; Forever's may differ.
export("GetDisenchantResults", function(item)
    local list = outcomes(item)
    if not list then
        return nil
    end
    local copy = {}
    for i, each in ipairs(list) do
        copy[i] = { itemID = each.item, chance = each.chance, min = each.min, max = each.max }
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

-- Callbacks --------------------------------------------------------------------------------------
-- RegisterCallback(event, fn, owner): fn(event, ...) runs on each event. An owner (any value, such
-- as the caller's addon table) can hold one function per event; without one, the function itself
-- is the owner. Events:
--   READY           saved data has loaded (once, after PLAYER_LOGIN)
--   PRICES_UPDATED  auction prices changed: a scan or browse, a reset, or their source changed (at
--                   most once a second)

local EVENTS = { READY = true, PRICES_UPDATED = true }
local callbacks = {} -- event -> owner -> fn

---Calls every function registered for `event`, each wrapped so one failing can't stop the rest.
---@param event string
function API.Fire(event, ...)
    local owners = callbacks[event]
    if not owners then
        return
    end
    for _, fn in pairs(owners) do
        finish(pcall(fn, event, ...))
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

-- The global ---------------------------------------------------------------------------------------

ForeverPlusPlusAPI = readOnly({ v1 = readOnly(v1, "ForeverPlusPlusAPI.v1") }, "ForeverPlusPlusAPI")
