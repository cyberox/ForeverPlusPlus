-- QuestieDB: the one place Forever++ reads the QuestieDB addon's quest, NPC, item, and world object
-- data, through its public API (`LibQuestieDB`) at run time. We ship none of its data or code, so a
-- module that needs it is off by default and says so with `QuestieDB.Notices()`.
--
-- Everything here is read only: we never register Corrections, change its locale, or drop its
-- caches, since Questie and other addons share the same tables. Every call into it is protected,
-- so a change on its side returns nil instead of an error, and `Problem()` says when the installed
-- version doesn't have the shape we expect. What we return is our own plain tables, never its.
--
-- Its coordinates are 0-100 percents keyed by AreaTable IDs; ours are 0-1 on a uiMapID, as
-- ns.WorldMap's. The area-to-map table is QuestieDB's own support data. docs/questiedb.md has what
-- its API offers and how each shape here comes from it.
--
-- It costs nothing until a module asks: nothing is listened to at load, and the zone and drop
-- tables are read the first time something wants them.
local _, ns = ...

local type, pairs, ipairs, pcall, next = type, pairs, ipairs, pcall, next
local loadstring, setfenv = loadstring, setfenv
local floor = math.floor

local L = ns.L

local QuestieDB = {}
ns.QuestieDB = QuestieDB

QuestieDB.ADDON = "QuestieDB" -- its folder and TOC name; the baked QuestieDB_Forever.toc is the same addon
QuestieDB.CONTRACT = 1 -- the contract we read against: entity reads only (docs/questiedb.md)

-- The kinds of data, as QuestieDB names its entity tables.
local KINDS = { Quest = true, Npc = true, Item = true, Object = true }

-- The fields we read from each kind. Every one is checked against its schema before we trust the
-- API, so a field renamed on their side is a Problem() rather than a quiet nil.
local FIELDS = {
    Quest = { "name", "questLevel", "requiredLevel", "requiredMaxLevel", "startedBy", "finishedBy",
        "objectives", "objectivesText", "preQuestGroup", "preQuestSingle", "nextQuestInChain",
        "exclusiveTo", "zoneOrSort", "requiredRaces", "requiredClasses", "sourceItemId",
        "requiredSkill", "breadcrumbForQuestId", "questFlags", "specialFlags" },
    Npc = { "name", "subName", "minLevel", "maxLevel", "rank", "spawns", "zoneID", "questStarts",
        "questEnds", "friendlyToFaction", "npcFlags" },
    Item = { "name", "npcDrops", "objectDrops", "itemDrops", "vendors", "questRewards", "startQuest",
        "relatedQuests", "itemLevel", "requiredLevel", "class", "subClass", "teachesSpell" },
    Object = { "name", "spawns", "zoneID", "questStarts", "questEnds" },
}

-- The API --------------------------------------------------------------------------------------

local status -- "ready", "contract", or "shape", once LibQuestieDB is there; nil before
local lib -- LibQuestieDB, once checked

-- Calls fn(...) protected: its first result, or nil when it errors.
local function try(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, result = pcall(fn, ...)
    if ok then
        return result
    end
    return nil
end

-- Whether every field we read is in a kind's schema (Meta.<Kind>.keys, or the documented
-- Meta.<Kind>Meta.<kind>Keys spelling of the same table).
local function hasFields(api, kind)
    local meta = type(api.Meta) == "table" and api.Meta or nil
    if not meta then
        return false
    end
    local keys = type(meta[kind]) == "table" and meta[kind].keys
    if type(keys) ~= "table" then
        local spelled = meta[kind .. "Meta"]
        keys = type(spelled) == "table" and spelled[kind:sub(1, 1):lower() .. kind:sub(2) .. "Keys"]
    end
    if type(keys) ~= "table" then
        return false
    end
    for _, field in ipairs(FIELDS[kind]) do
        if keys[field] == nil then
            return false
        end
    end
    return true
end

-- What the installed LibQuestieDB is to us: "ready", "contract" (a contract range without ours),
-- or "shape" (something we call is missing).
local function check(api)
    if type(api) ~= "table" or type(api.RequireContract) ~= "function" then
        return "shape"
    end
    local ok, fits = pcall(api.RequireContract, QuestieDB.CONTRACT)
    if not ok then
        return "shape"
    end
    if not fits then
        return "contract"
    end
    for kind in pairs(KINDS) do
        local entity = api[kind]
        if type(entity) ~= "table" or type(entity.GetAll) ~= "function"
            or type(entity.GetAllIds) ~= "function" or not hasFields(api, kind) then
            return "shape"
        end
    end
    return "ready"
end

-- LibQuestieDB once it's there and checked, else nil. The verdict is kept: the installed addon
-- can't change without a /reload.
local function api()
    if lib then
        return status == "ready" and lib or nil
    end
    local found = LibQuestieDB
    if type(found) ~= "table" then
        return nil
    end
    lib, status = found, check(found)
    return status == "ready" and lib or nil
end

-- C_AddOns' answer about QuestieDB: whether it's installed, loaded, loadable now, and loaded on
-- demand. Probe: without C_AddOns, only whether its global is there.
local function addon()
    local addons = C_AddOns
    if type(addons) ~= "table" then
        return false, false, false, false
    end
    local name = QuestieDB.ADDON
    local loaded = try(addons.IsAddOnLoaded, name) and true or false
    local installed = loaded
    local loadable = false
    if type(addons.GetAddOnInfo) == "function" then
        local ok, found, _, _, canLoad, reason = pcall(addons.GetAddOnInfo, name)
        if ok and found and reason ~= "MISSING" then
            installed = true
            -- An on-demand addon not loaded yet says DEMAND_LOADED rather than loadable.
            loadable = (canLoad or reason == "DEMAND_LOADED") and true or false
        end
    end
    if not installed and type(addons.DoesAddOnExist) == "function" then
        installed = try(addons.DoesAddOnExist, name) and true or false
    end
    local onDemand = try(addons.IsAddOnLoadOnDemand, name) and true or false
    return installed, loaded, loadable, onDemand
end

---Where QuestieDB stands: `"ready"` (its API answers), `"missing"` (not installed), `"off"`
---(installed but turned off in the AddOns list, or it couldn't load), `"waiting"` (installed and
---loaded on demand, not loaded yet), `"contract"` (a version without our contract), or `"shape"`
---(its API lacks something we call).
---@return string
function QuestieDB.Status()
    if api() then
        return "ready"
    end
    if lib then
        return status or "shape" -- set with `lib`, so never nil here
    end
    local installed, loaded, loadable, onDemand = addon()
    if not installed then
        return "missing"
    end
    if not loaded and onDemand and loadable then
        return "waiting"
    end
    if loaded then
        -- Loaded, yet no LibQuestieDB: a version that names it differently.
        return "shape"
    end
    return "off"
end

---Whether QuestieDB is installed, on, and has the API we expect, or will once it loads on demand.
---@return boolean
function QuestieDB.IsAvailable()
    local now = QuestieDB.Status()
    return now == "ready" or now == "waiting"
end

---Whether its data can be read right now.
---@return boolean
function QuestieDB.IsReady()
    return api() ~= nil
end

---Whether the installed QuestieDB doesn't fit what we read (a contract or shape we don't know),
---for a module's `Problem()`.
---@return boolean
function QuestieDB.Problem()
    local now = QuestieDB.Status()
    return now == "contract" or now == "shape"
end

-- Waiting for it ------------------------------------------------------------------------------

local waiting = {} -- fn -> true, for OnReady
local listening = false

local function onLoaded()
    listening = false
    local fns = waiting
    waiting = {}
    if not api() then
        return
    end
    for fn in pairs(fns) do
        ns.Call(fn)
    end
end

local function load()
    local addons = C_AddOns
    if type(addons) == "table" then
        try(addons.LoadAddOn, QuestieDB.ADDON)
    end
end

---Calls `fn()` now if QuestieDB is ready, or once it is: it's loaded first if it loads on demand
---(after combat, since loading it all takes a moment). Nothing is called while it's missing, off,
---or the wrong shape. The same `fn` waits once; `Cancel` stops it, for a module turned off first.
---@param fn fun()
function QuestieDB.OnReady(fn)
    if api() then
        fn()
        return
    end
    local now = QuestieDB.Status()
    if now ~= "waiting" then
        return
    end
    waiting[fn] = true
    if not listening then
        listening = true
        ns.AddOns.WhenLoaded(QuestieDB.ADDON, onLoaded)
        ns.AfterCombat(load)
    end
end

---Stops waiting to call `fn` when QuestieDB is ready.
---@param fn function
function QuestieDB.Cancel(fn)
    waiting[fn] = nil
    if listening and not next(waiting) then
        listening = false
        ns.AddOns.Cancel(QuestieDB.ADDON, onLoaded)
    end
end

---What the installed QuestieDB says about itself, for Self Test: its version (from its TOC), its
---contract range, and whether it reads baked data or its source files.
---@return table info `{ status, version, contract, minContract, readMode }`, any of them nil
function QuestieDB.Info()
    local info = { status = QuestieDB.Status() }
    local addons = C_AddOns
    if type(addons) == "table" then
        info.version = try(addons.GetAddOnMetadata, QuestieDB.ADDON, "Version")
    end
    local found = LibQuestieDB
    if type(found) == "table" then
        local contract, minContract, mode = found.contractVersion, found.minSupportedContract, found.readMode
        info.contract = type(contract) == "number" and contract or nil
        info.minContract = type(minContract) == "number" and minContract or nil
        info.readMode = type(mode) == "string" and mode or nil
    end
    return info
end

-- Plain values out of theirs -----------------------------------------------------------------

-- An ID, or nil for QuestieDB's 0 ("none") and anything that isn't a number.
local function id(value)
    if type(value) == "number" and value ~= 0 then
        return value
    end
    return nil
end

-- A number, or nil for 0 and anything else: levels and masks that 0 means "not set" for.
local number = id

-- A string, or nil.
local function str(value)
    return type(value) == "string" and value or nil
end

-- A list of IDs as our own list: only the non-zero numbers, in order.
local function ids(list)
    local out = {}
    if type(list) == "table" then
        for _, value in ipairs(list) do
            if id(value) then
                out[#out + 1] = value
            end
        end
    end
    return out
end

-- A list of strings as our own list.
local function strings(list)
    local out = {}
    if type(list) == "table" then
        for _, value in ipairs(list) do
            if type(value) == "string" then
                out[#out + 1] = value
            end
        end
    end
    return out
end

-- A record's fields, by name: GetAll's packed values for FIELDS[kind], or nil for an unknown ID.
local function read(kind, entityID)
    local found = api()
    if not found or type(entityID) ~= "number" then
        return nil
    end
    local entity = found[kind]
    local values = try(entity.GetAll, entityID, FIELDS[kind])
    if type(values) ~= "table" then
        return nil
    end
    local fields = {}
    for i, field in ipairs(FIELDS[kind]) do
        fields[field] = values[i]
    end
    return fields
end

-- Zones ---------------------------------------------------------------------------------------

local zones -- area ID -> uiMapID (false: no map), read once from QuestieDB's ZoneDB support data

-- One of its support tables, which it keeps as Lua source text (`return { ... }`) for Questie's
-- loadstring: run with no globals, so it can only build a table. Takes a table as it is.
local function source(value)
    if type(value) == "table" then
        return value
    end
    if type(value) ~= "string" or not loadstring then
        return nil
    end
    local chunk = loadstring(value)
    if not chunk then
        return nil
    end
    setfenv(chunk, {})
    local result = try(chunk)
    return type(result) == "table" and result or nil
end

-- A support module's table (`Support.Get(name)`), or nil.
local function support(name)
    local found = api()
    local lib_ = found and found.Support
    if type(lib_) ~= "table" then
        return nil
    end
    local module = try(lib_.Get, name)
    return type(module) == "table" and module or nil
end

local function loadZones()
    zones = {}
    local zoneDB = support("ZoneDB")
    local private = zoneDB and type(zoneDB.private) == "table" and zoneDB.private
    if not private then
        return
    end
    -- Its overrides win, as Questie reads them; 0 there means "shown on no map".
    for _, list in ipairs({ source(private.areaIdToUiMapId) or {}, source(private.areaIdToUiMapIdOverride) or {} }) do
        for area, map in pairs(list) do
            if type(area) == "number" and type(map) == "number" then
                zones[area] = map ~= 0 and map or false
            end
        end
    end
end

---The uiMapID QuestieDB maps an AreaTable ID (a zone or a place in one) to, or nil when it has none.
---@param areaID number
---@return number|nil uiMapID
function QuestieDB.UiMapID(areaID)
    if not api() or type(areaID) ~= "number" then
        return nil
    end
    if not zones then
        loadZones()
    end
    return zones[areaID] or nil
end

-- Spawns as our own list, `{ uiMapID, x, y, areaID, phase }` with x and y 0-1 on that map, and the
-- areas of instances it's in (QuestieDB's -1, -1 "somewhere inside" point). A spawn in an area
-- with no map is left out.
local function spawns(list)
    local out, instances = {}, {}
    if type(list) ~= "table" then
        return out, instances
    end
    for area, points in pairs(list) do
        if type(area) == "number" and type(points) == "table" then
            local map = QuestieDB.UiMapID(area)
            for _, point in ipairs(points) do
                local x, y = type(point) == "table" and point[1], type(point) == "table" and point[2]
                if type(x) == "number" and type(y) == "number" then
                    if x == -1 and y == -1 then
                        instances[#instances + 1] = area
                    elseif map then
                        out[#out + 1] = { uiMapID = map, x = x / 100, y = y / 100, areaID = area,
                            phase = id(point[3]) }
                    end
                end
            end
        end
    end
    return out, instances
end

-- The readers --------------------------------------------------------------------------------

-- Objective kinds, in QuestieDB's group order.
local function objectives(groups)
    local out = {}
    if type(groups) ~= "table" then
        return out
    end
    local function each(group, fn)
        if type(groups[group]) == "table" then
            for _, row in ipairs(groups[group]) do
                if type(row) == "table" then
                    fn(row)
                end
            end
        end
    end
    for group, kind in ipairs({ "npc", "object", "item" }) do
        each(group, function(row)
            if id(row[1]) then
                out[#out + 1] = { kind = kind, id = row[1], text = str(row[2]) }
            end
        end)
    end
    local rep = groups[4]
    if type(rep) == "table" and id(rep[1]) and type(rep[2]) == "number" then
        out[#out + 1] = { kind = "reputation", id = rep[1], value = rep[2] }
    end
    each(5, function(row)
        if id(row[2]) then
            out[#out + 1] = { kind = "killCredit", id = row[2], ids = ids(row[1]), text = str(row[3]) }
        end
    end)
    each(6, function(row)
        if id(row[1]) then
            out[#out + 1] = { kind = "spell", id = row[1], text = str(row[2]), itemID = id(row[3]) }
        end
    end)
    return out
end

-- QuestieDB's Enum.questFlags bits we read (its docs: src/corrections/enum/quests.lua).
local QUEST_RAID, QUEST_DAILY, QUEST_WEEKLY, QUEST_MONTHLY = 64, 4096, 32768, 65536

-- Whether a bit of a flag mask is set (Lua 5.1 has no bit operators; the client's `bit` isn't
-- needed for one bit).
local function hasFlag(mask, bit)
    return floor(mask / bit) % 2 == 1
end

-- A list field of a startedBy/finishedBy table.
local function group(tbl, index)
    return ids(type(tbl) == "table" and tbl[index] or nil)
end

---A quest, or nil when QuestieDB isn't ready or doesn't know it.
---
---`{ id, name, level, requiredLevel, maxLevel, races, classes, areaID, uiMapID, sortID,
---starters = { npcs, objects, items }, finishers = { npcs, objects }, objectives, objectivesText,
---prerequisites = { all, any }, next, exclusiveTo, breadcrumbFor, sourceItemID, requiredSkill,
---flags, specialFlags, repeatable, raid }`.
---`objectives` is a list of `{ kind, id, text }` (`kind` is `"npc"`, `"object"`, `"item"`,
---`"reputation"` with `value`, `"killCredit"` with `ids`, or `"spell"` with `itemID`). Every
---prerequisite in `all` and one of `any` must be done. `areaID` (and its `uiMapID`) is the zone the
---quest is listed in; `sortID` is the quest log category of one listed under a category instead.
---`races` and `classes` are masks, nil for anyone. `flags` and `specialFlags` are QuestieDB's
---quest flag masks (0 when none); `repeatable` is true for a repeatable, daily, weekly, or monthly
---quest, and `raid` for one its flags mark as a raid quest.
---@param questID number
---@return table|nil
function QuestieDB.Quest(questID)
    local f = read("Quest", questID)
    if not f then
        return nil
    end
    local zone = type(f.zoneOrSort) == "number" and f.zoneOrSort or 0
    local flags = type(f.questFlags) == "number" and f.questFlags or 0
    local special = type(f.specialFlags) == "number" and f.specialFlags or 0
    local skill = type(f.requiredSkill) == "table" and id(f.requiredSkill[1])
        and { id = f.requiredSkill[1], value = type(f.requiredSkill[2]) == "number" and f.requiredSkill[2] or 0 }
    return {
        id = questID,
        name = str(f.name),
        level = number(f.questLevel),
        requiredLevel = number(f.requiredLevel),
        maxLevel = number(f.requiredMaxLevel),
        races = number(f.requiredRaces),
        classes = number(f.requiredClasses),
        areaID = zone > 0 and zone or nil,
        uiMapID = zone > 0 and QuestieDB.UiMapID(zone) or nil,
        sortID = zone < 0 and -zone or nil,
        starters = { npcs = group(f.startedBy, 1), objects = group(f.startedBy, 2), items = group(f.startedBy, 3) },
        finishers = { npcs = group(f.finishedBy, 1), objects = group(f.finishedBy, 2) },
        objectives = objectives(f.objectives),
        objectivesText = strings(f.objectivesText),
        prerequisites = { all = ids(f.preQuestGroup), any = ids(f.preQuestSingle) },
        next = id(f.nextQuestInChain),
        exclusiveTo = ids(f.exclusiveTo),
        breadcrumbFor = id(f.breadcrumbForQuestId),
        sourceItemID = id(f.sourceItemId),
        requiredSkill = skill or nil,
        flags = flags,
        specialFlags = special,
        repeatable = special % 2 == 1 or hasFlag(flags, QUEST_DAILY) or hasFlag(flags, QUEST_WEEKLY) or hasFlag(flags, QUEST_MONTHLY),
        raid = hasFlag(flags, QUEST_RAID),
    }
end

---An NPC, or nil when QuestieDB isn't ready or doesn't know it.
---
---`{ id, name, subName, minLevel, maxLevel, rank, flags, friendlyTo, areaID, uiMapID, spawns,
---instances, questStarts, questEnds }`. `spawns` is a list of `{ uiMapID, x, y, areaID, phase }`
---with x and y 0-1 on that map; `instances` lists the area IDs of dungeons it's somewhere inside.
---`friendlyTo` is `"A"`, `"H"`, or `"AH"`; `flags` QuestieDB's NPC flag mask
---(`LibQuestieDB.Enum.npcFlags`).
---@param npcID number
---@return table|nil
function QuestieDB.Npc(npcID)
    local f = read("Npc", npcID)
    if not f then
        return nil
    end
    local list, instances = spawns(f.spawns)
    local friendly = f.friendlyToFaction
    return {
        id = npcID,
        name = str(f.name),
        subName = str(f.subName),
        minLevel = number(f.minLevel),
        maxLevel = number(f.maxLevel),
        rank = type(f.rank) == "number" and f.rank or 0,
        flags = type(f.npcFlags) == "number" and f.npcFlags or 0,
        friendlyTo = (friendly == "A" or friendly == "H" or friendly == "AH") and friendly or nil,
        areaID = id(f.zoneID),
        uiMapID = id(f.zoneID) and QuestieDB.UiMapID(f.zoneID) or nil,
        spawns = list,
        instances = instances,
        questStarts = ids(f.questStarts),
        questEnds = ids(f.questEnds),
    }
end

---An item, or nil when QuestieDB isn't ready or doesn't know it.
---
---`{ id, name, level, requiredLevel, class, subClass, npcDrops, objectDrops, containers, vendors,
---questRewards, startsQuest, relatedQuests, teachesSpell }`: where it comes from as ID lists (NPCs
---that drop it, objects that hold it, items that contain it, NPCs that sell it, quests that give
---it). Drop chances aren't here; see `QuestieDB.DropRates`.
---@param itemID number
---@return table|nil
function QuestieDB.Item(itemID)
    local f = read("Item", itemID)
    if not f then
        return nil
    end
    return {
        id = itemID,
        name = str(f.name),
        level = number(f.itemLevel),
        requiredLevel = number(f.requiredLevel),
        class = type(f.class) == "number" and f.class or nil,
        subClass = type(f.subClass) == "number" and f.subClass or nil,
        npcDrops = ids(f.npcDrops),
        objectDrops = ids(f.objectDrops),
        containers = ids(f.itemDrops),
        vendors = ids(f.vendors),
        questRewards = ids(f.questRewards),
        startsQuest = id(f.startQuest),
        relatedQuests = ids(f.relatedQuests),
        teachesSpell = id(f.teachesSpell),
    }
end

---A world object (a chest, a node, a quest object), or nil when QuestieDB isn't ready or doesn't
---know it: `{ id, name, areaID, uiMapID, spawns, instances, questStarts, questEnds }`, with `spawns`
---and `instances` as `QuestieDB.Npc`'s.
---@param objectID number
---@return table|nil
function QuestieDB.Object(objectID)
    local f = read("Object", objectID)
    if not f then
        return nil
    end
    local list, instances = spawns(f.spawns)
    return {
        id = objectID,
        name = str(f.name),
        areaID = id(f.zoneID),
        uiMapID = id(f.zoneID) and QuestieDB.UiMapID(f.zoneID) or nil,
        spawns = list,
        instances = instances,
        questStarts = ids(f.questStarts),
        questEnds = ids(f.questEnds),
    }
end

---Every ID of a kind (`"Quest"`, `"Npc"`, `"Item"`, `"Object"`), ascending, as our own list; empty
---while QuestieDB isn't ready.
---@param kind string
---@return number[]
function QuestieDB.Ids(kind)
    local found = api()
    if not found or not KINDS[kind] then
        return {}
    end
    return ids(try(found[kind].GetAllIds))
end

---The IDs of a kind whose name is exactly `name` in the game's language, ascending, as our own
---list; empty when none is. The first call for a kind makes QuestieDB index every name of it (tens
---of milliseconds), so call it where a stall won't show, not first on a hover.
---@param kind string
---@param name string
---@return number[]
function QuestieDB.IdsByName(kind, name)
    local found = api()
    if not found or not KINDS[kind] or type(name) ~= "string" then
        return {}
    end
    return ids(try(found[kind].IdsByName, name))
end

-- Drop chances --------------------------------------------------------------------------------

-- Item ID -> { NPC ID -> percent }, from QuestieDB's drop support data: Wowhead's numbers, then
-- CMaNGOS's for an item Wowhead's lack. Not part of its documented contract (the module's name is
-- its Classic drop table's), so it's probed and may be gone in a later version.
local drops

local function loadDrops()
    drops = {}
    local module = support("QuestieClassicItemDrops") or support("DropDB")
    if not module then
        return
    end
    for _, key in ipairs({ "wowheadData", "cmangosData" }) do
        local list = source(module[key])
        if list then
            for item, rates in pairs(list) do
                if type(item) == "number" and type(rates) == "table" and not drops[item] then
                    drops[item] = rates
                end
            end
        end
    end
end

---The chance, in percent, each NPC drops an item with, as far as QuestieDB's drop tables know:
---`{ [npcID] = percent }`, or nil when they don't have it. The first call reads the whole table, so
---call it out of combat.
---@param itemID number
---@return table<number, number>|nil
function QuestieDB.DropRates(itemID)
    if not api() or type(itemID) ~= "number" then
        return nil
    end
    if not drops then
        loadDrops()
    end
    local rates = drops[itemID]
    if not rates then
        return nil
    end
    local out = {}
    for npc, chance in pairs(rates) do
        if type(npc) == "number" and type(chance) == "number" then
            out[npc] = chance
        end
    end
    return next(out) and out or nil
end

-- Settings ------------------------------------------------------------------------------------

---The gray rows a module that needs QuestieDB puts in `module.notice`: that it needs the addon,
---while it's missing or off, and that the installed version doesn't fit, while that's so. A
---module with notices of its own adds these to its list.
---@return table[] notices
function QuestieDB.Notices()
    return {
        {
            text = L.QUESTIEDB_NEEDED,
            description = L.QUESTIEDB_NEEDED_DESC,
            shown = function()
                local now = QuestieDB.Status()
                return now == "missing" or now == "off"
            end,
        },
        {
            text = L.QUESTIEDB_PROBLEM,
            description = L.QUESTIEDB_PROBLEM_DESC,
            shown = QuestieDB.Problem,
        },
    }
end

---Forgets what was read and checked, for the tests (a new stub of LibQuestieDB).
function QuestieDB.Reset()
    lib, status, zones, drops = nil, nil, nil, nil
    waiting, listening = {}, false
end
