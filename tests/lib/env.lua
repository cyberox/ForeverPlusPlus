-- A fresh copy of the addon for one spec file: its own globals and its own `ns`, with the enUS
-- strings and the pure-logic Lib files loaded the way the client loads them (the addon name and
-- the shared `ns` as the chunk's arguments). Every chunk runs in the environment table, so the
-- stubs a spec sets (C_Map, CreateFrame, ...) and the globals the addon sets (ForeverPlusPlusAPI)
-- stay in that spec and never reach the next one. Lua's own libraries come from the real _G.
local Env = {}

Env.ADDON = "ForeverPlusPlus"
Env.ROOT = "ForeverPlusPlus/"

-- What every spec gets loaded. Lib files that need frames (Frames, Players, ...) are loaded by the
-- specs that test them, after their stubs.
Env.LOCALES = { "Core", "Map" }
Env.LIBS = {
    "Secret", "Colors", "Text", "GameData", "WorldMap", "Instances", "Chat", "TalentPlan", "Errors",
    "Prices", "Providers", "Disenchant", "Store", "Keys", "Professions", "ItemStats", "Equipment",
    "Talents", "Quests", "Taxi",
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
    env.issecretvalue = function(value)
        return value == game.secret
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
    for _, file in ipairs(Env.LIBS) do
        load("Lib/" .. file)
    end
    return {
        env = env, ns = ns, player = player, game = game, load = load, ADDON = Env.ADDON,
        ROOT = Env.ROOT, Toc = Env.Toc, Read = Env.Read,
    }
end

return Env
