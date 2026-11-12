-- Prints what a wowf build's client tables hold for the data the addon keeps by hand or could
-- build features on: row counts, how many of a kind link up, and where they agree with the
-- addon's own seeds. docs/table-survey.md is its write-up for one build; rerun it after a patch
-- and compare. Not a generator: it writes nothing into the addon. Lua 5.1 and curl, from the
-- repo root:
--
--   lua5.1 tools/datagen/survey.lua [build]   (default: the build in tools/datagen/BUILD)
--
-- Tables are cached in tools/datagen/cache/<build>/ like generate.lua's, so a rerun downloads
-- nothing. The build's table list is cached there too (tables.txt), to say which tables are absent.
local dir = (arg and arg[0] or ""):match("^(.*)[/\\][^/\\]*$") or "."
package.path = dir .. "/?.lua;" .. package.path

local CSV = require("csv")

local ROOT = dir .. "/../.."
local CACHE = dir .. "/cache"
local AGENT = "Mozilla/5.0 (compatible; db2-table-fetch/1.0)"
local WINDOWS = package.config:sub(1, 1) == "\\"
local SPEED = 30 -- yards a second a flight covers on Forever (fits every timed direct flight, 70888)

local function readFile(path)
    local file = io.open(path, "rb")
    if not file then
        return nil
    end
    local text = file:read("*a")
    file:close()
    return text
end

local function fail(message)
    io.stderr:write("survey: ", message, "\n")
    os.exit(1)
end

local function makeDir(path)
    if WINDOWS then
        os.execute('mkdir "' .. path:gsub("/", "\\") .. '" 2>nul')
    else
        os.execute("mkdir -p '" .. path .. "'")
    end
end

local function curl(url, path)
    local command = ('curl -fsSL --retry 2 --max-time 180 -A "%s" -o "%s" "%s"'):format(AGENT, path, url)
    local status = os.execute(command)
    return status == 0 or status == true
end

local build = arg[1] or (readFile(dir .. "/BUILD") or ""):match("[%d%.]+")
if not build or not build:match("^%d+%.%d+%.%d+%.%d+$") then
    fail("give a build like 1.60.1.70888")
end
local folder = CACHE .. "/" .. build
makeDir(folder)

-- The names of the tables wago.tools has for this build, from its DB2 page.
local function tableList()
    local path = folder .. "/tables.txt"
    local text = readFile(path)
    if not text then
        local page = folder .. "/db2.html.part"
        if not curl("https://wago.tools/db2?build=" .. build, page) then
            fail("couldn't read the table list")
        end
        local html = (readFile(page) or ""):gsub("&quot;", '"')
        os.remove(page)
        local block = html:match('"tables":(%b{})') or ""
        local names = {}
        for name in block:gmatch(':"([%w_]+)"') do
            names[#names + 1] = name
        end
        if #names == 0 then
            fail("the DB2 page listed no tables")
        end
        text = table.concat(names, "\n") .. "\n"
        local file = io.open(path, "wb")
        file:write(text)
        file:close()
    end
    local set = {}
    for name in text:gmatch("[%w_]+") do
        set[name] = true
    end
    return set
end

local present = tableList()
local loaded = {}

-- A table's records, downloaded once. Nil when the build hasn't the table.
local function load(name, columns)
    if loaded[name] ~= nil then
        return loaded[name] or nil
    end
    if not present[name] then
        loaded[name] = false
        return nil
    end
    local path = folder .. "/" .. name .. ".csv"
    local text = readFile(path)
    if not text then
        io.stderr:write("survey: downloading ", name, "\n")
        if not curl(("https://wago.tools/db2/%s/csv?build=%s"):format(name, build), path .. ".part") then
            fail("couldn't download " .. name)
        end
        os.rename(path .. ".part", path)
        text = readFile(path)
    end
    loaded[name] = CSV.Records(text, name, columns or {})
    return loaded[name]
end

local function byID(records, key)
    local out = {}
    for _, r in ipairs(records or {}) do
        out[r[key or "ID"]] = r
    end
    return out
end

local function count(t)
    local n = 0
    for _ in pairs(t) do
        n = n + 1
    end
    return n
end

local out = {}
local function say(...)
    out[#out + 1] = string.format(...)
    print(out[#out])
end

local function section(title)
    say("")
    say("== %s", title)
end

say("Build %s: %d tables listed", build, count(present))

-- The addon's own seeds, read from its source.
local function source(path)
    return readFile(ROOT .. "/" .. path) or fail("can't read " .. path)
end
local professions = source("ForeverPlusPlus/Lib/Professions.lua")
local instances = source("ForeverPlusPlus/Lib/Instances.lua")
local zoneInfo = source("ForeverPlusPlus/Modules/Map/WorldMap/ZoneInfo/Data.lua")

-- 1 and 8. Locks: lockboxes, and the skills herbs, veins, and pools take ---------------------------
section("Locks (Lock, LockType, ItemSparse.LockID, GameObjects)")
local locks = byID(load("Lock", { "ID" }))
local lockTypes = byID(load("LockType", { "ID", "Name_lang" }))
local items = byID(load("ItemSparse", { "ID", "Display_lang", "LockID", "ItemLevel", "RequiredLevel",
    "OverallQualityID", "InventoryType", "SellPrice", "RequiredSkill", "RequiredSkillRank", "ItemSet" }))
say("Lock %d rows, LockType %d, ItemSparse %d", count(locks), count(lockTypes), count(items))
local skillsOf = {} -- lock type -> { skill -> count }
for _, lock in pairs(locks) do
    for i = 0, 7 do
        if lock["Type_" .. i] == "2" then
            local kind, skill = lock["_Index_" .. i], tonumber(lock["Skill_" .. i])
            skillsOf[kind] = skillsOf[kind] or {}
            skillsOf[kind][skill] = (skillsOf[kind][skill] or 0) + 1
        end
    end
end
local function pickLock(lockID)
    local lock = locks[lockID]
    for i = 0, 7 do
        if lock and lock["Type_" .. i] == "2" and lock["_Index_" .. i] == "1" then
            return tonumber(lock["Skill_" .. i])
        end
    end
end
local boxes = {}
for id, item in pairs(items) do
    local skill = item.LockID ~= "0" and pickLock(item.LockID)
    if skill then
        boxes[#boxes + 1] = { tonumber(id), item.Display_lang, skill }
    end
end
table.sort(boxes, function(a, b) return a[1] < b[1] end)
say("Items with a Pick Lock lock: %d", #boxes)
for _, box in ipairs(boxes) do
    say("  %6d %-32s Lockpicking %d", box[1], box[2], box[3])
end
local function skillList(kind)
    local list = {}
    for skill in pairs(skillsOf[kind] or {}) do
        list[#list + 1] = skill
    end
    table.sort(list)
    return list
end
for _, kind in ipairs({ "1", "2", "3", "19" }) do
    say("Lock type %s (%s) skills: %s", kind, lockTypes[kind] and lockTypes[kind].Name_lang or "?",
        table.concat(skillList(kind), " "))
end
-- The seed's herbs and veins: { HERB or MINE, skill, item }.
for _, line in ipairs({ { "HERB", "2" }, { "MINE", "3" } }) do
    local seen, found, missing = {}, 0, {}
    for skill in professions:gmatch("{ " .. line[1] .. ", (%d+), %d+ }") do
        if not seen[skill] then
            seen[skill] = true
            if (skillsOf[line[2]] or {})[tonumber(skill)] then
                found = found + 1
            else
                missing[#missing + 1] = skill
            end
        end
    end
    say("Seed %s skills found among the lock's: %d of %d%s", line[1], found, count(seen),
        #missing > 0 and (" (not: " .. table.concat(missing, " ") .. ")") or "")
end
local objects = load("GameObjects", { "ID", "Name_lang", "TypeID" }) or {}
local chestLike = 0
for _, object in ipairs(objects) do
    local name = object.Name_lang:lower()
    if name:find("chest") or name:find("vein") or name:find("deposit") or name:find("school") then
        chestLike = chestLike + 1
    end
end
say("GameObjects: %d rows, %d named like a chest, vein, deposit, or school (client-side objects only)",
    #objects, chestLike)

-- 2. Random suffixes ----------------------------------------------------------------------------
section("Random suffixes (ItemBonus, ItemNameDescription, ItemBonusTreeNode, ItemXBonusTree, RandPropPoints)")
for _, name in ipairs({ "ItemRandomProperties", "ItemRandomSuffix" }) do
    say("%s: %s", name, present[name] and "present" or "absent")
end
local bonuses = load("ItemBonus", { "ParentItemBonusListID", "Type", "Value_0", "Value_1" }) or {}
local descriptions = byID(load("ItemNameDescription", { "ID", "Description_lang" }))
local suffixName, suffixStats = {}, {}
for _, bonus in ipairs(bonuses) do
    local list = bonus.ParentItemBonusListID
    if bonus.Type == "5" then
        suffixName[list] = descriptions[bonus.Value_0] and descriptions[bonus.Value_0].Description_lang
    elseif bonus.Type == "2" then
        suffixStats[list] = (suffixStats[list] or 0) + 1
    end
end
local names, withStats = {}, 0
for list, name in pairs(suffixName) do
    names[name] = true
    if suffixStats[list] then
        withStats = withStats + 1
    end
end
say("Bonus lists with a name (suffixes): %d, %d with stat allocations (type 2), %d distinct names",
    count(suffixName), withStats, count(names))
local trees = load("ItemXBonusTree", { "ItemID", "ItemBonusTreeID" }) or {}
local treeItems, sparse = {}, 0
for _, row in ipairs(trees) do
    if not treeItems[row.ItemID] then
        treeItems[row.ItemID] = true
        if items[row.ItemID] then
            sparse = sparse + 1
        end
    end
end
say("Items with a bonus tree: %d, of which in ItemSparse (item level, quality, slot known): %d",
    count(treeItems), sparse)
say("RandPropPoints: %d rows", #(load("RandPropPoints", { "ID" }) or {}))

-- 3. Item sets ----------------------------------------------------------------------------------
section("Item sets (ItemSet, ItemSetSpell)")
local sets = load("ItemSet", { "ID", "Name_lang" }) or {}
local setSpells = load("ItemSetSpell", { "ItemSetID", "SpellID", "Threshold" }) or {}
local known, highest = 0, 0
for _, set in ipairs(sets) do
    local any = false
    for i = 0, 16 do
        local item = items[set["ItemID_" .. i] or "0"]
        if item then
            any = true
            highest = math.max(highest, tonumber(item.RequiredLevel))
        end
    end
    if any then
        known = known + 1
    end
end
say("ItemSet %d rows, ItemSetSpell %d; sets with an item in ItemSparse %d (highest required level %d)",
    #sets, #setSpells, known, highest)

-- 4. Taxi ---------------------------------------------------------------------------------------
section("Taxi (TaxiNodes, TaxiPath, TaxiPathNode)")
local nodes = byID(load("TaxiNodes", { "ID", "Name_lang" }))
local paths = load("TaxiPath", { "ID", "FromTaxiNode", "ToTaxiNode", "Cost" }) or {}
local points = {}
for _, p in ipairs(load("TaxiPathNode", { "PathID", "NodeIndex", "ContinentID", "Loc_0", "Loc_1", "Loc_2" }) or {}) do
    points[p.PathID] = points[p.PathID] or {}
    table.insert(points[p.PathID], p)
end
local function pathLength(pathID)
    local list = points[pathID] or {}
    table.sort(list, function(a, b) return tonumber(a.NodeIndex) < tonumber(b.NodeIndex) end)
    local total = 0
    for i = 2, #list do
        local a, b = list[i - 1], list[i]
        if a.ContinentID == b.ContinentID then
            local dx = tonumber(a.Loc_0) - tonumber(b.Loc_0)
            local dy = tonumber(a.Loc_1) - tonumber(b.Loc_1)
            local dz = tonumber(a.Loc_2) - tonumber(b.Loc_2)
            total = total + math.sqrt(dx * dx + dy * dy + dz * dz)
        end
    end
    return total
end
local flown, withCost = 0, 0
for _, path in ipairs(paths) do
    if nodes[path.FromTaxiNode] and nodes[path.ToTaxiNode] and pathLength(path.ID) > 0 then
        flown = flown + 1
        if path.Cost ~= "0" then
            withCost = withCost + 1
        end
    end
end
say("TaxiNodes %d, TaxiPath %d (%d between two nodes with points, %d with a cost)", count(nodes),
    #paths, flown, withCost)
for _, pair in ipairs({ { "2", "6" }, { "2", "19" }, { "4", "12" }, { "23", "25" }, { "33", "28" } }) do
    for _, path in ipairs(paths) do
        if path.FromTaxiNode == pair[1] and path.ToTaxiNode == pair[2] then
            local length = pathLength(path.ID)
            say("  %s > %s: %.0f yd, about %.0f s at %d yd/s, cost %s", nodes[pair[1]].Name_lang,
                nodes[pair[2]].Name_lang, length, length / SPEED, SPEED, path.Cost)
        end
    end
end

-- 5. Dungeons and zones -------------------------------------------------------------------------
section("Dungeons and zones (LFGDungeons, ContentTuning, Map, AreaTable, UiMapAssignment)")
local tuning = byID(load("ContentTuning", { "ID", "MinLevelSquish", "MaxLevelSquish" }))
local finder = load("LFGDungeons", { "ID", "Name_lang", "TypeID", "ContentTuningID" }) or {}
local maps = byID(load("Map", { "ID", "MapName_lang", "InstanceType", "AreaTableID" }))
local areas = byID(load("AreaTable", { "ID", "AreaName_lang", "ParentAreaID", "ExplorationLevel",
    "ContentTuningID" }))
-- The dungeon finder's level by its name, which is the map's name for most.
local finderLevel = {}
for _, row in ipairs(finder) do
    local t = tuning[row.ContentTuningID]
    if row.TypeID == "0" and t then
        finderLevel[row.Name_lang] = tonumber(t.MinLevelSquish)
    end
end
-- A dungeon's area has the same tuning as its finder entry, whose name can differ ("Deadmines").
local areaLevel, areaLevelByName = {}, {}
for _, area in pairs(areas) do
    local t = tuning[area.ContentTuningID]
    if area.ContentTuningID ~= "0" and t then
        areaLevel[area.ID] = tonumber(t.MinLevelSquish)
        areaLevelByName[area.AreaName_lang] = areaLevel[area.ID]
    end
end
local same, differ, absent = 0, 0, 0
for key, id, name, low in instances:gmatch("(%w+) = { (%d+), \"([^\"]+)\", (%d+), %d+") do
    local map = maps[id]
    local level = finderLevel[name] or (map and areaLevel[map.AreaTableID]) or areaLevelByName[name]
    if not level then
        absent = absent + 1
        say("  %-16s %-28s lowest %2s, tables: none", key, name, low)
    elseif level == tonumber(low) then
        same = same + 1
    else
        differ = differ + 1
        say("  %-16s %-28s lowest %2s, tables %2d", key, name, low, level)
    end
end
say("Instances.lua lowest levels: %d same, %d differ, %d absent (no highest level in any table)",
    same, differ, absent)
local mapArea = {}
for _, row in ipairs(load("UiMapAssignment", { "UiMapID", "AreaID", "OrderIndex" }) or {}) do
    if row.AreaID ~= "0" and not mapArea[row.UiMapID] then
        mapArea[row.UiMapID] = row.AreaID
    end
end
local children = {}
for _, area in pairs(areas) do
    children[area.ParentAreaID] = children[area.ParentAreaID] or {}
    table.insert(children[area.ParentAreaID], area)
end
local exact, near, total = 0, 0, 0
for mapID, low, high in zoneInfo:gmatch("\n    %[(%d+)%] = { (%d+), (%d+),") do
    local lo, hi
    for _, area in ipairs(children[mapArea[mapID] or ""] or {}) do
        local level = tonumber(area.ExplorationLevel)
        if level > 0 then
            lo, hi = math.min(lo or level, level), math.max(hi or level, level)
        end
    end
    if lo then
        total = total + 1
        if lo == tonumber(low) and hi == tonumber(high) then
            exact = exact + 1
        elseif math.abs(lo - low) <= 2 and math.abs(hi - high) <= 2 then
            near = near + 1
        end
    end
end
say("Zone Info level ranges vs the zone's subzone ExplorationLevel range: %d exact, %d within 2, of %d",
    exact, near, total)

-- 6. Professions --------------------------------------------------------------------------------
section("Professions (SkillLineAbility, ItemEffect, ItemXItemEffect, SpellReagents)")
local PROFESSIONS = { { 164, "Blacksmithing" }, { 165, "Leatherworking" }, { 171, "Alchemy" },
    { 197, "Tailoring" }, { 202, "Engineering" }, { 333, "Enchanting" }, { 185, "Cooking" },
    { 129, "First Aid" } }
local effects = byID(load("ItemEffect", { "ID", "TriggerType", "SpellID" }))
local taughtBy = {}
for _, row in ipairs(load("ItemXItemEffect", { "ItemID", "ItemEffectID" }) or {}) do
    local effect = effects[row.ItemEffectID]
    if effect and effect.TriggerType == "6" then -- on learn: the spell is the recipe
        taughtBy[effect.SpellID] = taughtBy[effect.SpellID] or row.ItemID
    end
end
local reagents = byID(load("SpellReagents", { "SpellID" }), "SpellID")
local abilities = load("SkillLineAbility", { "SkillLine", "Spell", "MinSkillLineRank" }) or {}
for _, profession in ipairs(PROFESSIONS) do
    local line = tostring(profession[1])
    local n, item, named, reagent, learnOne = 0, 0, 0, 0, 0
    for _, row in ipairs(abilities) do
        if row.SkillLine == line then
            n = n + 1
            local teacher = taughtBy[row.Spell]
            if teacher then
                item = item + 1
                if items[teacher] then
                    named = named + 1
                end
            end
            if reagents[row.Spell] then
                reagent = reagent + 1
            end
            if row.MinSkillLineRank == "1" then
                learnOne = learnOne + 1
            end
        end
    end
    say("  %-15s %4d abilities, %4d with reagents, %4d taught by an item (%d of those in ItemSparse), %d with MinSkillLineRank 1",
        profession[2], n, reagent, item, named, learnOne)
end

-- 7. Factions -----------------------------------------------------------------------------------
section("Factions (Faction, FactionTemplate)")
local factions = load("Faction", { "ID", "ReputationIndex" }) or {}
local reputations = 0
for _, faction in ipairs(factions) do
    if faction.ReputationIndex ~= "-1" then
        reputations = reputations + 1
    end
end
say("Faction %d rows, %d with a reputation; FactionTemplate %d", #factions, reputations,
    #(load("FactionTemplate", { "ID" }) or {}))

-- 9. Disenchanting ------------------------------------------------------------------------------
section("Disenchanting (ItemDisenchantLoot)")
local brackets = load("ItemDisenchantLoot", { "Class", "Quality", "MinLevel", "MaxLevel", "SkillRequired" }) or {}
local QUALITY = { ["2"] = "uncommon", ["3"] = "rare", ["4"] = "epic" }
for _, quality in ipairs({ "2", "3", "4" }) do
    local list = {}
    for _, row in ipairs(brackets) do
        if row.Quality == quality and row.Class == "4" then
            list[#list + 1] = row
        end
    end
    table.sort(list, function(a, b) return tonumber(a.MinLevel) < tonumber(b.MinLevel) end)
    local text = {}
    for _, row in ipairs(list) do
        text[#text + 1] = row.MinLevel .. "-" .. row.MaxLevel
    end
    say("  %-8s armor brackets: %s", QUALITY[quality], table.concat(text, " "))
end
local skilled = 0
for _, row in ipairs(brackets) do
    if row.SkillRequired ~= "0" then
        skilled = skilled + 1
    end
end
say("ItemDisenchantLoot %d rows, %d with a SkillRequired; outcomes are not in the client", #brackets, skilled)

-- 10. Other -------------------------------------------------------------------------------------
section("Other")
local itemRows = load("Item", { "ID", "ClassID" }) or {}
local missing = 0
for _, row in ipairs(itemRows) do
    if not items[row.ID] then
        missing = missing + 1
    end
end
say("Item %d rows, ItemSparse %d: %d items have no ItemSparse row (no name, level, or price)",
    #itemRows, count(items), missing)
local priced = 0
for _, item in pairs(items) do
    if item.SellPrice ~= "0" then
        priced = priced + 1
    end
end
say("ItemSparse with a SellPrice: %d", priced)
local encounters = load("DungeonEncounter", { "MapID", "Name_lang" }) or {}
local encounterMaps = {}
for _, row in ipairs(encounters) do
    encounterMaps[row.MapID] = true
end
say("DungeonEncounter %d rows on %d maps", #encounters, count(encounterMaps))
for _, name in ipairs({ "JournalEncounter", "JournalEncounterItem", "JournalInstance", "ItemRandomSuffix" }) do
    say("%s: %s", name, present[name] and "present" or "absent")
end
say("SpellLevels %d rows; AreaPOI %d; QuestV2 %d (IDs only)", #(load("SpellLevels", { "SpellID" }) or {}),
    #(load("AreaPOI", { "ID" }) or {}), #(load("QuestV2", { "ID" }) or {}))
