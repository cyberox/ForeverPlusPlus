-- How Forever++'s saved variables are laid out, the steps that bring an older layout up to date,
-- and the table each module reads its settings and data through (`module.db`).
--
--   ForeverPlusPlusDB = {
--       version = 7,            -- the layout, so each step below runs once
--       settings = { [module] = { [key] = value } },  -- the Default profile's: only what the player changed
--       data = { [module] = { [key] = table } },      -- what modules collect: prices, flight times;
--                                                     -- and the Default profile's data
--       preset = "developer",                         -- the preset Default is based on, if any
--       profiles = { [id] = { name = "Raid",          -- every profile but Default, by an id of
--           preset = "developer",                     -- its own, laid out as Default is
--           settings = { [module] = { [key] = value } },
--           data = { [module] = { [key] = table } } } },  -- (only `module.perProfile` keys)
--       newCharacters = id,                           -- the profile a new character starts on
--       characters = { [guid] = { name, realm, class, level, profile, moved } },
--                                                     -- every character seen, for the Profiles page
--       unclaimed = { [module] = { [key] = table } }, -- per-character data from version 1, until
--                                                     -- each character logs in and takes its own
--       gameData = { [set] = { values, build } },     -- what play taught Lib/GameData.lua
--       seenVersion, seenModules, foldedCategories, welcome, changelogByModule, selfTest, ...
--                                                     -- the core's own
--   }
--   ForeverPlusPlusCharDB = { version = 7, profile = id, data = { [module] = { [key] = table } } }
--   ForeverPlusPlusPlayersDB: players seen, kept by Lib/Players.lua apart from all this
--
-- A module's settings are its scalar defaults. What the player sets is saved, even when it's the
-- default, so a later release changing that default doesn't change their choice; only a reset (the
-- undo arrow, Defaults, `/fpp reset`) forgets it, by setting it to nil, and then a better default
-- reaches them, as it does everyone who never touched the setting. Its data is every default that is a table;
-- presets and Defaults never touch it. Keys listed in `module.perCharacter` keep their data in the
-- character's table instead of the account's, and keys in `module.perProfile` in the profile's.
--
-- Profiles: the Default profile is the account's own `settings` and `data`, where they always were,
-- so a player with one profile has the layout they had before profiles; another profile is a root
-- of its own in `profiles` with the same two tables. `Store.profile` is the id of the one in use
-- (nil for Default), and every `module.db` reads through it, so switching needs no new views.
-- Lib/Profiles.lua keeps the rest: names, characters, and switching.
--
-- Presets: a profile may be based on one (its root's `preset`, Lib/Presets.lua). A setting the
-- player hasn't set then reads what the preset says before its default, at read time, so a later
-- release adding to the preset reaches the profile, and a reset falls back to the preset. A profile
-- with no `preset` reads as it always did, and a name this version doesn't know reads as none, so
-- the field needed no step of its own (it came with 1.6.0, in layout 7).
local _, ns = ...

local pairs, ipairs, type, next, setmetatable, sort = pairs, ipairs, type, next, setmetatable, table.sort

local Store = {}
ns.Store = Store

-- Version 6 adds profiles beside the settings; nothing moves, since Default is where settings were.
-- Version 7 merges Recipe Colors and Item Tooltips' Crafting Costs into the Professions module.
Store.VERSION = 7

---The id of the profile every `module.db` reads, or nil for Default. Lib/Profiles.lua sets it.
---@type string?
Store.profile = nil

-- `t[key]`, made a table first when it isn't one.
local function child(t, key)
    local value = t[key]
    if type(value) ~= "table" then
        value = {}
        t[key] = value
    end
    return value
end

---The table that holds a profile's `settings` and `data`: the account's own for Default (nil) or
---a profile that isn't there, else the profile's entry in `db.profiles`.
---@param db table ForeverPlusPlusDB
---@param id? string
---@return table
function Store.Root(db, id)
    local profiles = db.profiles
    local profile = id and type(profiles) == "table" and profiles[id]
    if type(profile) == "table" then
        return profile
    end
    return db
end

---The preset a profile is based on (Lib/Presets.lua), when this version has it. A name saved by a
---newer version, or of a preset since removed, reads as none, and stays saved for that version.
---@param db? table ForeverPlusPlusDB
---@param id? string
---@return string?
function Store.Preset(db, id)
    local name = db and Store.Root(db, id).preset
    local presets = ns.Presets
    if name ~= nil and presets and presets.Exists(name) then
        return name
    end
    return nil
end

---Bases a profile on a preset, or on none (nil). Nothing else in it changes.
---@param db table
---@param id? string
---@param name? string
function Store.SetPreset(db, id, name)
    Store.Root(db, id).preset = name
end

---What a setting reads when the player hasn't set it, so what a reset gives: what the profile's
---preset says, else the module's default. `defaults` is the module's.
---@param db? table
---@param id? string the profile, nil for Default
---@param name string the module
---@param key string
---@param defaults table
---@return any
function Store.Base(db, id, name, key, defaults)
    local preset = Store.Preset(db, id)
    if preset and type(defaults[key]) ~= "table" then
        local value = ns.Presets.Value(preset, name, key)
        if value ~= nil then
            return value
        end
    end
    return defaults[key]
end

---Every profile's root, Default's (the account's) first, for whatever must treat them all alike:
---tidying, pruning, renaming a module.
---@param db table
---@return table[]
function Store.Roots(db)
    local roots = { db }
    if type(db.profiles) == "table" then
        for _, profile in pairs(db.profiles) do
            if type(profile) == "table" then
                roots[#roots + 1] = profile
            end
        end
    end
    return roots
end

-- Steps -----------------------------------------------------------------------------------------
-- A step brings the saved variables from the version before its own to its own. Each runs once:
-- the version saved says which have run.

local steps, characterSteps = {}, {}
local loose = false -- the saved settings came from the 0.8 layout this login (Store.Upgrade)

local function add(list, version, fn)
    list[#list + 1] = { version = version, fn = fn, order = #list }
end

local function run(list, from, ...)
    local due = {}
    for _, step in ipairs(list) do
        if step.version > from then
            due[#due + 1] = step
        end
    end
    sort(due, function(a, b)
        if a.version ~= b.version then
            return a.version < b.version
        end
        return a.order < b.order
    end)
    for _, step in ipairs(due) do
        -- Through ns.Call when the core is there, so one broken step doesn't stop the others.
        if ns.Call then
            ns.Call(step.fn, ...)
        else
            step.fn(...)
        end
    end
end

---Adds a step for the account's saved variables: `fn(db)` gets ForeverPlusPlusDB once, when the
---saved version is older than `version`. Version 1 steps work on the 0.8 layout (`db.modules`,
---every module's settings and data by module name); later ones on the layout above.
---@param version integer
---@param fn fun(db: table)
function Store.Step(version, fn)
    add(steps, version, fn)
end

---Adds a step for a character's saved variables: `fn(char, db)` gets ForeverPlusPlusCharDB and
---ForeverPlusPlusDB once per character, when its saved version is older than `version`. Use it to
---take this character's part of `db.unclaimed`.
---@param version integer
---@param fn fun(char: table, db: table)
function Store.CharacterStep(version, fn)
    add(characterSteps, version, fn)
end

---Runs the steps the saved variables haven't had and marks them current. A fresh install (an empty
---table) has nothing to bring up to date.
---@param db table ForeverPlusPlusDB
---@param char table ForeverPlusPlusCharDB
---@return boolean fresh true when `db` was empty
function Store.Upgrade(db, char)
    local fresh = next(db) == nil
    if fresh then
        db.version = Store.VERSION
    end
    -- The 0.8 layout saved every default as if the player chose it; Store.Load drops those.
    loose = loose or (db.version or 0) < 2
    run(steps, db.version or 0, db)
    db.version = Store.VERSION
    run(characterSteps, char.version or 0, char, db)
    char.version = Store.VERSION
    return fresh
end

-- Version 2: settings apart from data -------------------------------------------------------------

---Splits the 0.8 layout's `db.modules` into `settings` and `data`: tables are data, the rest
---settings. Per-character data (`perCharacter[module][key]`, keyed by character inside) goes to
---`unclaimed` for each character to take. Settings equal to their default are dropped later, by
---Store.Load, which knows the defaults.
---@param db table
---@param perCharacter table<string, table<string, boolean>>
function Store.Split(db, perCharacter)
    db.settings, db.data, db.unclaimed = db.settings or {}, db.data or {}, db.unclaimed or {}
    for name, saved in pairs(db.modules or {}) do
        if type(saved) == "table" then
            for key, value in pairs(saved) do
                local into = db.settings
                if type(value) == "table" and next(value) == nil then
                    into = nil -- nothing collected yet; Store.Load makes it again
                elseif type(value) == "table" then
                    into = perCharacter[name] and perCharacter[name][key] and db.unclaimed or db.data
                end
                if into then
                    into[name] = into[name] or {}
                    into[name][key] = value
                end
            end
        end
    end
    db.modules = nil
end

-- Every table the account keeps by module name: each profile's settings and data, unclaimed
-- data, and (with `seen`) the version each module was last seen in.
local function byModule(db, seen)
    local list = {}
    for _, root in ipairs(Store.Roots(db)) do
        list[#list + 1] = root.settings
        list[#list + 1] = root.data
    end
    list[#list + 1] = db.unclaimed
    if seen then
        list[#list + 1] = db.seenModules
    end
    local tables = {}
    for _, byName in pairs(list) do
        if type(byName) == "table" then
            tables[#tables + 1] = byName
        end
    end
    return tables
end

---Renames modules everywhere the account keeps them by name: every profile's settings and data,
---unclaimed data, and the version each was last seen in. `names` is { [old] = new }.
---@param db table
---@param names table<string, string>
function Store.Rename(db, names)
    for _, byName in ipairs(byModule(db, true)) do
        for old, new in pairs(names) do
            if byName[old] ~= nil and byName[new] == nil then
                byName[new] = byName[old]
            end
            byName[old] = nil
        end
    end
end

---For a character step: takes this character's part of `db.unclaimed[name][key]` (data version 1
---kept for every character, by a key of each) into the character's own data, and drops what's
---left empty. `take(entries)` removes this character's entries and returns them as the table the
---module now keeps, or nil when it had none.
---@param char table
---@param db table
---@param name string the module
---@param key string its per-character data
---@param take fun(entries: table): table?
function Store.Claim(char, db, name, key, take)
    local byKey = db.unclaimed and db.unclaimed[name]
    local entries = byKey and byKey[key]
    if type(entries) ~= "table" then
        return
    end
    local part = take(entries)
    if type(part) == "table" then
        local own = child(child(char, "data"), name)
        own[key] = part
    end
    if next(entries) == nil then
        byKey[key] = nil
        if next(byKey) == nil then
            db.unclaimed[name] = nil
        end
    end
end

-- Loading -----------------------------------------------------------------------------------------

local function isData(defaults, key)
    return type(defaults[key]) == "table"
end

-- Fills `target` with what it lacks of `defaults`, tables inside too.
local function fill(target, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then
                target[key] = {}
            end
            fill(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
end

---Gets a module's saved settings and data ready and returns the table it reads them through:
---a setting reads what the player chose or else its default; setting one saves it, even at the
---default, and setting it to nil forgets the choice, so it reads the default again. A data key
---reads its table, in the account's, the character's, or (`perProfile`) the profile's saved
---variables. Settings read the profile in use (`Store.profile`) on every read and write, so a
---switch changes what the view reads. Settings and data the defaults no longer have are dropped,
---in every profile (and settings at their default when they came from the 0.8 layout, which saved
---them all). Data whose key moved in or out of `perCharacter` moves with it; a key moved into
---`perProfile` stays with Default, which keeps its data in the account's table.
---A `linked` setting is kept somewhere else (one of Blizzard's settings): it reads `get()` and
---setting it calls `set(value)`, nil for the default, and nothing of it is saved here.
---@param db table ForeverPlusPlusDB
---@param char table ForeverPlusPlusCharDB
---@param name string
---@param defaults table
---@param perCharacter? table<string, boolean>
---@param linked? table<string, { get: fun(): any, set: fun(value: any) }>
---@param perProfile? table<string, boolean>
---@return table view
function Store.Load(db, char, name, defaults, perCharacter, linked, perProfile)
    perCharacter = perCharacter or {}
    linked = linked or {}
    perProfile = perProfile or {}
    -- Looked up on each use, not kept: Store.Tidy drops empty tables before the game saves, and
    -- a write after it (a module saving at logout) makes them again; and the profile can change.
    local function settingsTable()
        return child(child(Store.Root(db, Store.profile), "settings"), name)
    end
    local function dataTable(key)
        local home = db
        if perCharacter[key] then
            home = char
        elseif perProfile[key] then
            home = Store.Root(db, Store.profile)
        end
        return child(child(home, "data"), name)
    end
    local function dataFor(key)
        local store = dataTable(key)
        if type(store[key]) ~= "table" then
            store[key] = {}
        end
        fill(store[key], defaults[key])
        return store[key]
    end
    for _, root in ipairs(Store.Roots(db)) do
        local settings = type(root.settings) == "table" and root.settings[name]
        for key, value in pairs(type(settings) == "table" and settings or {}) do
            if defaults[key] == nil or isData(defaults, key) or linked[key]
                or (loose and root == db and value == defaults[key]) then
                settings[key] = nil
            end
        end
        -- A profile other than Default keeps only its own data.
        local data = root ~= db and type(root.data) == "table" and root.data[name]
        for key in pairs(type(data) == "table" and data or {}) do
            if not (isData(defaults, key) and perProfile[key] and not perCharacter[key]) then
                data[key] = nil
            end
        end
    end
    -- The account's table holds account data and Default's profile data; the character's its own.
    -- A key `perCharacter` moved between the two takes its data along, unless the other side
    -- already has some.
    local account, own = child(child(db, "data"), name), child(child(char, "data"), name)
    for _, pair in ipairs({ { account, own, true }, { own, account, false } }) do
        local store, other, belongsElsewhere = pair[1], pair[2], pair[3]
        for key, value in pairs(store) do
            local data = isData(defaults, key)
            if not data or (perCharacter[key] and true or false) == belongsElsewhere then
                if data and other[key] == nil then
                    other[key] = value
                end
                store[key] = nil
            end
        end
    end
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            dataFor(key)
        end
    end
    return setmetatable({}, {
        __index = function(_, key)
            if isData(defaults, key) then
                local store = dataTable(key)
                return type(store[key]) == "table" and store[key] or dataFor(key)
            elseif linked[key] then
                return linked[key].get()
            end
            local root = Store.Root(db, Store.profile)
            local value = child(child(root, "settings"), name)[key]
            if value == nil then
                -- Not set: the profile's preset, then the default. A profile on no preset has
                -- no `preset`, so this costs it one field.
                if root.preset ~= nil then
                    return Store.Base(db, Store.profile, name, key, defaults)
                end
                return defaults[key]
            end
            return value
        end,
        __newindex = function(_, key, value)
            if isData(defaults, key) then
                dataTable(key)[key] = value
            elseif linked[key] then
                linked[key].set(value)
            else
                settingsTable()[key] = value -- nil forgets it
            end
        end,
    })
end

-- Whether a table holds nothing but empty tables, all the way down.
local function hollow(t)
    for _, value in pairs(t) do
        if type(value) ~= "table" or not hollow(value) then
            return false
        end
    end
    return true
end

---Drops what's left empty before the game writes the saved variables (at logout or /reload):
---a module with no changed settings, and data with nothing collected, which Store.Load makes
---again, in every profile. Keeps the file to what was actually saved. A profile itself stays,
---even with nothing changed: the player made it.
---@param db table
---@param char table
function Store.Tidy(db, char)
    local tables = byModule(db)
    tables[#tables + 1] = char.data
    for _, byName in ipairs(tables) do
        for name, byKey in pairs(byName) do
            for key, value in pairs(byKey) do
                if type(value) == "table" and hollow(value) then
                    byKey[key] = nil
                end
            end
            if next(byKey) == nil then
                byName[name] = nil
            end
        end
    end
end

---Drops the settings and data of modules that no longer exist, in every profile, unclaimed data
---included. `known` is { [name] = true }.
---@param db table
---@param char table
---@param known table<string, boolean>
function Store.Prune(db, char, known)
    local tables = byModule(db)
    tables[#tables + 1] = char.data
    for _, byName in ipairs(tables) do
        for name in pairs(byName) do
            if not known[name] then
                byName[name] = nil
            end
        end
    end
end
