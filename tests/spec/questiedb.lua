-- QuestieDB: reading the QuestieDB addon through a stub of LibQuestieDB with the same shape as its
-- public API (docs/questiedb.md). Every record here is made up.
local T = ...
local ns, eq, same, ok = T.ns, T.eq, T.same, T.ok

-- What Lib/AddOns.lua and the waiting need from Core.
local handlers = {}
ns.On = function(event, fn)
    handlers[event] = fn
end
ns.Off = function(event)
    handlers[event] = nil
end
local afterCombat = {}
ns.AfterCombat = function(fn)
    afterCombat[#afterCombat + 1] = fn
end

-- The addon list: QuestieDB's state in C_AddOns. Set before Lib/AddOns.lua, which caches it.
local addon = { installed = false, loaded = false, enabled = true, onDemand = false }
C_AddOns = {
    IsAddOnLoaded = function(name)
        return name == "QuestieDB" and addon.loaded
    end,
    GetAddOnInfo = function(name)
        if name ~= "QuestieDB" or not addon.installed then
            return name, nil, nil, false, "MISSING"
        end
        if addon.onDemand and not addon.loaded then
            return name, "QuestieDB", "", false, "DEMAND_LOADED"
        end
        return name, "QuestieDB", "", addon.enabled, addon.enabled and nil or "DISABLED"
    end,
    IsAddOnLoadOnDemand = function()
        return addon.onDemand
    end,
    GetAddOnMetadata = function(_, key)
        return key == "Version" and "9.9.9" or nil
    end,
}
T.load("Lib/AddOns")
T.load("Lib/QuestieDB")
local Q = ns.QuestieDB

-- A made-up database in QuestieDB's shapes: 0-100 coordinates by area ID, packed GetAll values.
local SCHEMA = {
    Quest = { "name", "startedBy", "finishedBy", "requiredLevel", "questLevel", "requiredRaces",
        "requiredClasses", "objectivesText", "triggerEnd", "objectives", "sourceItemId",
        "preQuestGroup", "preQuestSingle", "childQuests", "inGroupWith", "exclusiveTo", "zoneOrSort",
        "requiredSkill", "requiredMinRep", "requiredMaxRep", "requiredSourceItems",
        "nextQuestInChain", "questFlags", "specialFlags", "parentQuest", "reputationReward",
        "breadcrumbForQuestId", "breadcrumbs", "extraObjectives", "requiredSpell",
        "requiredSpecialization", "requiredMaxLevel" },
    Npc = { "name", "minLevelHealth", "maxLevelHealth", "minLevel", "maxLevel", "rank", "spawns",
        "waypoints", "zoneID", "questStarts", "questEnds", "factionID", "friendlyToFaction",
        "subName", "npcFlags" },
    Item = { "name", "npcDrops", "objectDrops", "itemDrops", "startQuest", "questRewards", "flags",
        "foodType", "itemLevel", "requiredLevel", "ammoType", "class", "subClass", "vendors",
        "relatedQuests", "teachesSpell" },
    Object = { "name", "questStarts", "questEnds", "spawns", "zoneID", "factionID", "waypoints" },
}

local DATA = {
    Quest = {
        [900001] = {
            name = "Test Errand", questLevel = 12, requiredLevel = 8, requiredMaxLevel = 0,
            startedBy = { { 800001 }, nil, { 700002 } }, finishedBy = { { 800001 }, { 600001 } },
            objectives = {
                { { 800002, "Grumblers slain", 0 } },
                { { 600001, nil, 0 } },
                { { 700001, "Shiny Bits", 0 } },
                { 55, 3000 },
                { { { 800003, 800004 }, 800002, "Grumbler routed", 0 } },
                { { 12345, "Cast it", 0 } },
            },
            objectivesText = { "Bring the bits." },
            preQuestGroup = { 900000 }, preQuestSingle = nil, nextQuestInChain = 900002,
            exclusiveTo = nil, zoneOrSort = 10, requiredRaces = 0, requiredClasses = 8,
            sourceItemId = 0, requiredSkill = { 186, 50 }, breadcrumbForQuestId = 0,
        },
        [900002] = {
            name = "Sorted Errand", questLevel = 15, requiredLevel = 10, requiredMaxLevel = 20,
            startedBy = {}, finishedBy = {}, objectives = {}, zoneOrSort = -61,
            preQuestSingle = { 900001, 0 },
        },
    },
    Npc = {
        [800001] = {
            name = "Testy McTest", subName = "Errand Giver", minLevel = 10, maxLevel = 12, rank = 1,
            spawns = { [10] = { { 50, 25 }, { 10, 90, 7 } }, [20] = { { -1, -1 } }, [30] = { { 1, 1 } } },
            zoneID = 10, questStarts = { 900001 }, questEnds = { 900001 }, friendlyToFaction = "AH",
            npcFlags = 2,
        },
    },
    Item = {
        [700001] = {
            name = "Shiny Bits", npcDrops = { 800002, 800003 }, objectDrops = { 600001 }, itemDrops = nil,
            vendors = { 800001 }, questRewards = nil, startQuest = 0, relatedQuests = { 900001 },
            itemLevel = 5, requiredLevel = 0, class = 12, subClass = 0, teachesSpell = 0,
        },
    },
    Object = {
        [600001] = {
            name = "Test Crate", spawns = { [10] = { { 40, 60 } } }, zoneID = 10,
            questStarts = nil, questEnds = { 900001 },
        },
    },
}

local nameReads = 0
local function entity(kind, data)
    local keys = {}
    for i, field in ipairs(SCHEMA[kind]) do
        keys[field] = i
    end
    local e = {}
    e.GetAll = function(id, fields)
        local row = data[id]
        if not row then
            return nil
        end
        local out = { n = #fields }
        for i, field in ipairs(fields) do
            assert(keys[field], "no field " .. field)
            out[i] = row[field]
        end
        return out
    end
    e.GetAllIds = function()
        local list = {}
        for id in pairs(data) do
            list[#list + 1] = id
        end
        table.sort(list)
        return list
    end
    e.IdsByName = function(name)
        nameReads = nameReads + 1
        local list
        for id, row in pairs(data) do
            if row.name == name then
                list = list or {}
                list[#list + 1] = id
            end
        end
        return list
    end
    return e, keys
end

local function newLib(changes)
    local lib = { Meta = {}, contractVersion = 4, minSupportedContract = 1, readMode = "baked" }
    for kind in pairs(SCHEMA) do
        local e, keys = entity(kind, DATA[kind])
        lib[kind] = e
        lib.Meta[kind] = { keys = keys }
    end
    lib.RequireContract = function(v)
        return v >= lib.minSupportedContract and v <= lib.contractVersion, "mismatch"
    end
    local support = {
        ZoneDB = { private = {
            areaIdToUiMapId = "return { [10] = 1411, [20] = 1581, [30] = 1412 }",
            areaIdToUiMapIdOverride = "return { [30] = 0 }",
        } },
        QuestieClassicItemDrops = {
            wowheadData = "return { [700001] = { [800002] = 25.5, [800003] = 3 } }",
            cmangosData = "return { [700001] = { [800002] = 99 }, [700009] = { [800001] = 1 } }",
        },
    }
    lib.Support = { Get = function(name) return support[name] end }
    for key, value in pairs(changes or {}) do
        lib[key] = value
    end
    return lib
end

local function fresh(lib)
    LibQuestieDB = lib
    Q.Reset()
end

-- Not installed, off, and waiting to load ------------------------------------------------------

fresh(nil)
eq(Q.Status(), "missing", "questiedb: not installed")
eq(Q.IsAvailable(), false, "questiedb: not installed isn't available")
eq(Q.IsReady(), false, "questiedb: not installed isn't ready")
eq(Q.Problem(), false, "questiedb: not installed isn't a problem")
eq(Q.Quest(900001), nil, "questiedb: no quest without it")
same(Q.Ids("Quest"), {}, "questiedb: no IDs without it")
eq(Q.UiMapID(10), nil, "questiedb: no zones without it")
eq(Q.DropRates(700001), nil, "questiedb: no drops without it")
local notices = Q.Notices()
eq(notices[1].shown() and not notices[2].shown(), true, "questiedb: the missing notice shows")
ok(notices[1].text and notices[1].description and notices[2].text, "questiedb: notices have text")

local called = 0
local function onReady()
    called = called + 1
end
Q.OnReady(onReady)
eq(called == 0 and handlers.ADDON_LOADED == nil, true, "questiedb: nothing waits while it's missing")

addon.installed, addon.enabled = true, false
eq(Q.Status(), "off", "questiedb: installed but off")
eq(notices[1].shown(), true, "questiedb: the notice shows while it's off")

addon.enabled, addon.onDemand = true, true
eq(Q.Status(), "waiting", "questiedb: on demand, not loaded yet")
eq(Q.IsAvailable() and not Q.IsReady(), true, "questiedb: waiting is available, not ready")
eq(notices[1].shown(), false, "questiedb: no notice while it can load")
local loads = 0
C_AddOns.LoadAddOn = function(name)
    loads = loads + 1
    addon.loaded = true
    LibQuestieDB = newLib()
    handlers.ADDON_LOADED(nil, name)
end
Q.OnReady(onReady)
Q.OnReady(onReady)
eq(called == 0 and #afterCombat == 1 and handlers.ADDON_LOADED ~= nil, true,
    "questiedb: waits once, and loads it after combat")
afterCombat[1]()
eq(loads == 1 and called == 1, true, "questiedb: ready once loaded")
eq(handlers.ADDON_LOADED, nil, "questiedb: stops listening once loaded")
Q.OnReady(onReady)
eq(called, 2, "questiedb: ready now calls at once")

-- Cancel before it loads.
fresh(nil)
addon.loaded, afterCombat = false, {}
Q.OnReady(onReady)
Q.Cancel(onReady)
eq(handlers.ADDON_LOADED, nil, "questiedb: cancel stops the wait")

-- Wrong shape and contract --------------------------------------------------------------------

addon.onDemand, addon.loaded = false, true
fresh(nil)
eq(Q.Status(), "shape", "questiedb: loaded without its global")
fresh(newLib({ contractVersion = 0 }))
eq(Q.Status() == "contract" and Q.Problem() and not Q.IsReady(), true, "questiedb: a contract without ours")
eq(notices[2].shown() and not notices[1].shown(), true, "questiedb: the problem notice shows")
fresh(newLib({ RequireContract = function() error("boom") end }))
eq(Q.Status(), "shape", "questiedb: a contract check that errors")
local broken = newLib()
broken.Npc = { GetAllIds = broken.Npc.GetAllIds }
fresh(broken)
eq(Q.Status(), "shape", "questiedb: a missing GetAll")
eq(Q.Npc(800001), nil, "questiedb: no reads from the wrong shape")
broken = newLib()
broken.Meta.Quest.keys.objectives = nil
fresh(broken)
eq(Q.Problem(), true, "questiedb: a field gone from the schema")
broken = newLib()
broken.Meta.Item = nil
broken.Meta.ItemMeta = { itemKeys = { } }
fresh(broken)
eq(Q.Status(), "shape", "questiedb: the documented Meta spelling, missing a field")
broken.Meta.ItemMeta.itemKeys = newLib().Meta.Item.keys
fresh(broken)
eq(Q.Status(), "ready", "questiedb: the documented Meta spelling")

-- Reads ---------------------------------------------------------------------------------------

fresh(newLib())
eq(Q.Status() == "ready" and Q.IsReady() and not Q.Problem(), true, "questiedb: ready")
eq(notices[1].shown() or notices[2].shown(), false, "questiedb: no notices while ready")
same(Q.Info(), { status = "ready", version = "9.9.9", contract = 4, minContract = 1, readMode = "baked" },
    "questiedb: info")

local quest = Q.Quest(900001)
same(quest, {
    id = 900001, name = "Test Errand", level = 12, requiredLevel = 8, classes = 8,
    areaID = 10, uiMapID = 1411,
    starters = { npcs = { 800001 }, objects = {}, items = { 700002 } },
    finishers = { npcs = { 800001 }, objects = { 600001 } },
    objectives = {
        { kind = "npc", id = 800002, text = "Grumblers slain" },
        { kind = "object", id = 600001 },
        { kind = "item", id = 700001, text = "Shiny Bits" },
        { kind = "reputation", id = 55, value = 3000 },
        { kind = "killCredit", id = 800002, ids = { 800003, 800004 }, text = "Grumbler routed" },
        { kind = "spell", id = 12345, text = "Cast it" },
    },
    objectivesText = { "Bring the bits." },
    prerequisites = { all = { 900000 }, any = {} },
    next = 900002, exclusiveTo = {}, requiredSkill = { id = 186, value = 50 },
}, "questiedb: a quest in our shape")
local sorted = Q.Quest(900002)
eq(sorted.sortID == 61 and sorted.areaID == nil and sorted.maxLevel == 20, true, "questiedb: a quest under a category")
same(sorted.prerequisites.any, { 900001 }, "questiedb: any one prerequisite, without 0")
eq(Q.Quest(1), nil, "questiedb: an unknown quest")
eq(Q.Quest("900001"), nil, "questiedb: a quest ID that isn't a number")

local npc = Q.Npc(800001)
table.sort(npc.spawns, function(a, b) return a.x > b.x end)
same(npc, {
    id = 800001, name = "Testy McTest", subName = "Errand Giver", minLevel = 10, maxLevel = 12,
    rank = 1, flags = 2, friendlyTo = "AH", areaID = 10, uiMapID = 1411,
    spawns = {
        { uiMapID = 1411, x = 0.5, y = 0.25, areaID = 10 },
        { uiMapID = 1411, x = 0.1, y = 0.9, areaID = 10, phase = 7 },
    },
    instances = { 20 },
    questStarts = { 900001 }, questEnds = { 900001 },
}, "questiedb: an NPC, spawns 0-1 on a uiMapID, the override's 0 left out")

same(Q.Item(700001), {
    id = 700001, name = "Shiny Bits", level = 5, class = 12, subClass = 0,
    npcDrops = { 800002, 800003 }, objectDrops = { 600001 }, containers = {}, vendors = { 800001 },
    questRewards = {}, relatedQuests = { 900001 },
}, "questiedb: an item")

same(Q.Object(600001), {
    id = 600001, name = "Test Crate", areaID = 10, uiMapID = 1411,
    spawns = { { uiMapID = 1411, x = 0.4, y = 0.6, areaID = 10 } }, instances = {},
    questStarts = {}, questEnds = { 900001 },
}, "questiedb: an object")

-- Copies, not theirs: changing what we got doesn't change the next read.
quest.starters.npcs[1] = 1
eq(Q.Quest(900001).starters.npcs[1], 800001, "questiedb: reads are our own copies")

eq(Q.UiMapID(20), 1581, "questiedb: an area's map")
eq(Q.UiMapID(30), nil, "questiedb: an override of 0 is no map")
eq(Q.UiMapID(99), nil, "questiedb: an unknown area")

same(Q.Ids("Quest"), { 900001, 900002 }, "questiedb: every quest ID")
same(Q.Ids("Spell"), {}, "questiedb: an unknown kind")
same(Q.IdsByName("Object", "Test Crate"), { 600001 }, "questiedb: IDs by name")
same(Q.IdsByName("Object", "Nothing"), {}, "questiedb: no IDs by name")

same(Q.DropRates(700001), { [800002] = 25.5, [800003] = 3 }, "questiedb: Wowhead's drop rates first")
same(Q.DropRates(700009), { [800001] = 1 }, "questiedb: CMaNGOS's for an item Wowhead's lack")
eq(Q.DropRates(1), nil, "questiedb: no drop rates")

-- A change on their side: errors become nil, and a support table that isn't Lua is no table.
local erring = newLib()
erring.Quest.GetAll = function() error("changed") end
erring.Support = { Get = function() return { private = { areaIdToUiMapId = "this isn't lua" } } end }
fresh(erring)
eq(Q.Quest(900001), nil, "questiedb: an erroring read is nil")
eq(Q.UiMapID(10), nil, "questiedb: a zone table that won't load")
eq(Q.DropRates(700001), nil, "questiedb: no drop table")

-- Support text runs with no globals, so it can only build a table.
local sneaky = newLib()
sneaky.Support = { Get = function(name)
    if name == "ZoneDB" then
        return { private = { areaIdToUiMapId = "C_AddOns = nil return { [10] = 5 }" } }
    end
end }
fresh(sneaky)
eq(Q.UiMapID(10) == 5 and C_AddOns ~= nil, true, "questiedb: support text can't touch our globals")
