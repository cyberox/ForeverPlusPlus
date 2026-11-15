-- A fresh copy of the addon for one spec file: its own globals and its own `ns`, with the enUS
-- strings and the pure-logic Lib files loaded the way the client loads them (the addon name and
-- the shared `ns` as the chunk's arguments). Every chunk runs in the environment table, so the
-- stubs a spec sets (C_Map, CreateFrame, ...) and the globals the addon sets (ForeverPlusPlusAPI)
-- stay in that spec and never reach the next one. Lua's own libraries come from the real _G.
local Env = {}

local Standin = assert(loadfile("tests/lib/standin.lua"))()

Env.ADDON = "ForeverPlusPlus"
Env.ROOT = "ForeverPlusPlus/"

-- What every spec gets loaded. Lib files that need frames (Frames, Players, ...) are loaded by the
-- specs that test them, after their stubs.
Env.LOCALES = { "Core", "Map" }
Env.DATA = { "Instances", "Professions", "Spells" } -- the hand-kept data those Lib files read
Env.LIBS = {
    "Secret", "Colors", "Text", "GameData", "WorldMap", "Generated/InstanceLevels", "Instances", "Chat", "TalentPlan", "Errors",
    "Prices", "Providers", "Generated/DisenchantBrackets", "Disenchant", "Presets", "Store", "Keys", "Professions", "ItemStats", "Equipment",
    "Talents", "Quests", "Taxi", "Generated/TaxiRoutes", "ItemButtons", "Gathering",
}

-- The stubbed WoW globals every spec starts with. `player` and `game` are tables the stubs read,
-- since the Lib files cache these functions at load: a spec changes the table, not the function.
local function stub(env, player, game)
    env.UnitLevel = function()
        return player.level
    end
    env.UnitFactionGroup = function()
        return player.faction
    end
    env.GetQuestDifficultyColor = function(level)
        -- Marks the level asked about, so tests can tell which one the code picked.
        return { r = level, g = 0, b = 0 }
    end
    env.QuestDifficultyColors = { difficult = { r = "difficult", g = 0, b = 0 } }
    env.FACTION_ALLIANCE, env.FACTION_HORDE = "Alliance", "Horde"
    env.Enum = { UIMapType = { Cosmic = 0, World = 1, Continent = 2, Zone = 3 } }
    env.ITEM_MIN_SKILL = "Requires %s (%d)"
    -- Nothing is secret until a spec sets game.secret: nil is never secret, as in the game.
    env.issecretvalue = function(value)
        return game.secret ~= nil and value == game.secret
    end
    env.GetRealZoneText = function(id)
        return game.zoneNames[id] or ""
    end
    env.C_Item = {
        -- An ID, or a table of the whole answer (id, type, subtype, equip location, ...).
        GetItemInfoInstant = function(name)
            local item = game.cachedItems[name]
            if type(item) == "table" then
                return unpack(item)
            end
            return item
        end,
    }
    -- What the player wears (Lib/Equipment.lua): slot -> link.
    env.GetInventoryItemLink = function(_, slot)
        return game.worn[slot]
    end
    env.CanDualWield = function()
        return game.dualWield
    end
    env.GetTime = function()
        return game.now
    end
    env.time = function()
        return game.clock
    end
    -- Marks the number it's given, so tests can tell Text.Number went through it.
    env.BreakUpLargeNumbers = function(n)
        return "big:" .. n
    end
end

---The addon's TOC: its `## Key: value` fields and the files it loads, in order ("Lib/Text.lua").
---@return table fields
---@return string[] files
function Env.Toc()
    local fields, files = {}, {}
    for line in io.lines(Env.ROOT .. Env.ADDON .. ".toc") do
        line = line:gsub("\r$", "")
        local key, value = line:match("^##%s*([%w%-_]+):%s*(.-)%s*$")
        if key then
            fields[key] = value
        elseif line:match("%S") and not line:match("^#") then
            files[#files + 1] = (line:gsub("%s*%[.*$", ""):gsub("\\", "/"):match("^%s*(.-)%s*$"))
        end
    end
    return fields, files
end

---Every .lua file Forever++'s TOC loads, from the repo root.
---@return string[] paths
function Env.LuaFiles()
    local paths = {}
    local _, files = Env.Toc()
    for _, file in ipairs(files) do
        paths[#paths + 1] = Env.ROOT .. file
    end
    for i = #paths, 1, -1 do
        if not paths[i]:match("%.lua$") then
            table.remove(paths, i)
        end
    end
    return paths
end

---Every .lua file in the addon folder, by listing it (cmd's dir on Windows, find elsewhere), as
---the TOC writes them ("Lib/Text.lua"), sorted. What the TOC should list, whatever it does list.
---@return string[] files
function Env.DiskFiles()
    local windows = package.config:sub(1, 1) == "\\"
    local folder = Env.ROOT:sub(1, -2)
    local command = windows and ('dir /s /b "' .. folder .. '\\*.lua"') or ("find " .. folder .. " -name '*.lua'")
    local pipe = assert(io.popen(command), "can't list " .. folder)
    local files = {}
    for line in pipe:lines() do
        -- The path after the addon's folder, whatever comes before it: dir gives full paths, and
        -- the repository's own folder has the addon's name too, so the last one is the addon's.
        local path = ("/" .. line:gsub("\\", "/"):gsub("%s+$", "")):match("^.*/" .. folder .. "/(.+%.lua)$")
        if path then
            files[#files + 1] = path
        end
    end
    pipe:close()
    table.sort(files)
    return files
end

---A whole file's text, or nil when it can't be read.
---@param path string from the repo root
---@return string|nil
function Env.Read(path)
    local file = io.open(path, "rb")
    if not file then
        return nil
    end
    local text = file:read("*a")
    file:close()
    return text
end

---A new environment with the addon loaded in it.
---@return table T what a spec gets: env, ns, player, game, load, and the addon's name
function Env.New()
    local env = setmetatable({}, { __index = _G })
    env._G = env
    local player = { level = 30, faction = "Horde" }
    local game = {
        secret = nil, -- the one value issecretvalue says is secret
        zoneNames = {}, -- GetRealZoneText: id -> name
        cachedItems = {}, -- C_Item.GetItemInfoInstant: name or link -> ID or answer
        worn = {}, -- GetInventoryItemLink: slot -> link
        dualWield = false,
        now = 0, -- GetTime
        clock = 0, -- time
    }
    stub(env, player, game)

    local ns = {}
    ns.L = {}
    ns.NewLocale = function()
        return ns.L
    end
    ns.Call = function(fn, ...)
        return fn(...)
    end

    -- Loads one of the addon's files ("Lib/Players") into `into` (the spec's `ns` by default), in
    -- this environment.
    local function load(path, into)
        local chunk = assert(loadfile(Env.ROOT .. path .. ".lua"))
        setfenv(chunk, env)
        return chunk(Env.ADDON, into or ns)
    end

    for _, file in ipairs(Env.LOCALES) do
        load("Locales/enUS/" .. file)
    end
    for _, file in ipairs(Env.DATA) do
        load("Data/" .. file)
    end
    for _, file in ipairs(Env.LIBS) do
        load("Lib/" .. file)
    end
    -- The whole addon, every file in the TOC, loaded into an `ns` of its own against a stand-in
    -- client on top of this spec's globals (tests/lib/standin.lua). `before(env, stub)` sets the
    -- globals the spec's checks need before the files load, and `around(path, ns, loaded)` runs
    -- before each file (`loaded` nil) and after it (true or false).
    local function whole(before, around)
        local _, files = Env.Toc()
        return Standin.Load(env, Env.ROOT, Env.ADDON, files, before, around)
    end
    local T = {
        env = env, ns = ns, player = player, game = game, load = load, Whole = whole, ADDON = Env.ADDON,
        ROOT = Env.ROOT, Toc = Env.Toc, Read = Env.Read, LuaFiles = Env.LuaFiles, DiskFiles = Env.DiskFiles,
    }

    -- The real Core, loaded and not yet logged in, for a spec that tests it (tests/lib/core.lua).
    -- It runs in this environment, so the stubs it sets are the spec's.
    function T.Core()
        local chunk = assert(loadfile("tests/lib/core.lua"))
        setfenv(chunk, env)
        return chunk(T)
    end
    return T
end

return Env
