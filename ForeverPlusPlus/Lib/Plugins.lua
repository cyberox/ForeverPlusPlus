-- Plugins: modules another addon adds to Forever++ through the public API (API.lua's
-- RegisterModule and GetPluginKit; docs/api.md is the contract). A plugin's module shows on the
-- Modules page with its options, follows profiles, and turns on and off like ours.
--
-- A plugin never gets our own module table. It gets a handle: a table that takes only the fields
-- the contract names (a title, options, the functions Core calls), checks them as they're set, and
-- passes them on. So how our modules are written can keep changing, as it does, and only this file
-- has to keep the handle meaning what docs/api.md says. Options and buttons are copied field by
-- field for the same reason: a plugin can't reach what only our own modules may use (an option
-- that sets a CVar, a debug option).
--
-- Core is told which modules are plugins' (`Remember`), so the settings of one whose addon is off
-- or gone for a session aren't cleared with those of modules that no longer exist.
local addonName, ns = ...

local type, pairs, ipairs, error, setmetatable, match = type, pairs, ipairs, error, setmetatable, string.match

local L = ns.L

local Plugins = {}
ns.Plugins = Plugins

local NAME = "^[%a][%w_]*$"

local handles = setmetatable({}, { __mode = "k" }) -- handle -> its module
local modules = setmetatable({}, { __mode = "k" }) -- module -> its handle

local function fail(message, level)
    error(addonName .. ": " .. message, (level or 1) + 1)
end

-- Options ----------------------------------------------------------------------------------------

-- The option fields a plugin may set, and each one's type ("any" for a value of the option's own
-- kind). Anything else is left out of the copy.
local OPTION_FIELDS = {
    key = "string", name = "string", description = "string", section = "string", added = "string",
    requires = "string", slider = "string", choices = "table", shown = "function",
    min = "number", max = "number", step = "number", format = "string",
}

-- A copy of one option with only the fields above, checked against the module's defaults.
local function copyOption(option, defaults, index)
    if type(option) ~= "table" then
        fail("option " .. index .. " isn't a table", 4)
    end
    local copy = {}
    for field, kind in pairs(OPTION_FIELDS) do
        local value = option[field]
        if value ~= nil then
            if type(value) ~= kind then
                fail("option " .. index .. ": " .. field .. " must be a " .. kind, 4)
            end
            copy[field] = value
        end
    end
    local key = copy.key
    if not key or not copy.name then
        fail("option " .. index .. " needs a key and a name", 4)
    end
    local default = defaults[key]
    if key == "enabled" or default == nil or type(default) == "table" then
        fail("option " .. key .. " needs a default that isn't a table, and can't be \"enabled\"", 4)
    end
    if copy.choices then
        local choices, found = {}, false
        for i, choice in ipairs(copy.choices) do
            if type(choice) ~= "table" or type(choice[1]) ~= "string" or type(choice[2]) ~= "string" then
                fail("option " .. key .. ": each choice is { value, name }, both text", 4)
            end
            choices[i] = { choice[1], choice[2] }
            found = found or choice[1] == default
        end
        if not found then
            fail("option " .. key .. ": its default isn't one of its choices", 4)
        end
        copy.choices = choices
    elseif copy.min or copy.max then
        if not (copy.min and copy.max and copy.min < copy.max and type(default) == "number") then
            fail("option " .. key .. ": a slider needs min under max and a number for its default", 4)
        end
    elseif type(default) ~= "boolean" then
        fail("option " .. key .. ": a checkbox needs true or false for its default", 4)
    end
    return copy
end

local function copyOptions(options, defaults)
    local copies, keys = {}, {}
    for index, option in ipairs(options) do
        local copy = copyOption(option, defaults, index)
        if keys[copy.key] then
            fail("two options are called " .. copy.key, 3)
        end
        keys[copy.key] = true
        copies[index] = copy
    end
    -- An option another one names must be there.
    for _, copy in ipairs(copies) do
        for _, field in ipairs({ "requires", "slider" }) do
            if copy[field] and not keys[copy[field]] then
                fail("option " .. copy.key .. ": no option called " .. copy[field], 3)
            end
        end
    end
    return copies
end

-- Buttons: `{ name, button, description, section, confirm, fn }`.
local function copyActions(actions)
    local copies = {}
    for index, action in ipairs(actions) do
        if type(action) ~= "table" or type(action.name) ~= "string" or type(action.button) ~= "string"
            or type(action.fn) ~= "function" then
            fail("button " .. index .. " needs a name, a button text, and a function", 3)
        end
        copies[index] = { name = action.name, button = action.button, fn = action.fn,
            description = type(action.description) == "string" and action.description or nil,
            section = type(action.section) == "string" and action.section or nil,
            confirm = type(action.confirm) == "string" and action.confirm or nil }
    end
    return copies
end

-- Notices: gray rows above the options, `{ text, description, shown }`, one or a list. They say
-- something; a button on one is for our own modules.
local function copyNotices(notice, own)
    local list = notice[1] and notice or { notice }
    local copies = { own }
    for index, row in ipairs(list) do
        if type(row) ~= "table" or type(row.text) ~= "string" then
            fail("notice " .. index .. " needs a text", 3)
        end
        copies[#copies + 1] = { text = row.text,
            description = type(row.description) == "string" and row.description or nil,
            shown = type(row.shown) == "function" and row.shown or nil }
    end
    return copies
end

-- The handle -------------------------------------------------------------------------------------

-- What a plugin may set on its handle: the type each takes.
local FIELDS = {
    title = "string", category = "string", added = "string",
    options = "table", actions = "table", notice = "table", perCharacter = "table",
    OnEnable = "function", OnDisable = "function", OnOptionChanged = "function",
    IsAvailable = "function", Problem = "function",
}

-- The module methods a handle has, with the handle in the module's place.
local METHODS = { "On", "Hook", "HookScript", "TooltipPostCall", "Print" }

-- Whether Forever++ has read the saved settings (PLAYER_LOGIN): too late for a new module, and
-- for what Core reads only then.
local function started()
    return ns.db ~= nil
end

local function setField(handle, key, value)
    local module = handles[handle]
    local kind = FIELDS[key]
    if not kind then
        fail("a plugin's module has no \"" .. tostring(key) .. "\" to set", 2)
    end
    if type(value) ~= kind then
        fail(key .. " must be a " .. kind, 2)
    end
    if kind == "function" then
        -- Core calls it with our module; the plugin's function gets its handle.
        module[key] = function(_, ...)
            return value(handle, ...)
        end
        return
    end
    if started() and (key == "options" or key == "perCharacter") then
        fail(key .. " is set while the plugin loads, before PLAYER_LOGIN", 2)
    end
    if key == "options" then
        module.options = copyOptions(value, module.defaults)
    elseif key == "actions" then
        module.actions = copyActions(value)
    elseif key == "notice" then
        module.notice = copyNotices(value, module.pluginNotice)
    elseif key == "perCharacter" then
        local keys = {}
        for name, on in pairs(value) do
            if type(name) ~= "string" or type(module.defaults[name]) ~= "table" then
                fail("perCharacter names defaults that are tables", 2)
            end
            keys[name] = on and true or nil
        end
        module.perCharacter = keys
    else
        module[key] = value
    end
end

local function getField(handle, key)
    local module = handles[handle]
    if key == "name" or key == "db" then
        return module[key]
    elseif key == "enabled" then
        return module.enabled and true or false
    end
    return nil
end

---Makes a module for a plugin and returns its handle. Called while the plugin's files load,
---before PLAYER_LOGIN. Errors on a mistake (a name taken, defaults that aren't a table).
---@param name string letters, digits, and underscores, starting with a letter
---@param description string
---@param defaults table its settings and their defaults; `enabled` false unless given
---@param addon? string the plugin's addon folder, named in the module's notice
---@return table handle
function Plugins.Register(name, description, defaults, addon)
    if type(name) ~= "string" or not match(name, NAME) then
        fail("RegisterModule needs a name of letters, digits, and underscores", 2)
    end
    if type(description) ~= "string" or type(defaults) ~= "table" then
        fail("RegisterModule(name, description, defaults)", 2)
    end
    if started() then
        fail("RegisterModule is for the time a plugin loads, before PLAYER_LOGIN", 2)
    end
    if ns.modules[name] then
        fail("there is already a module called " .. name, 2)
    end
    local own = {}
    for key, value in pairs(defaults) do
        if type(key) ~= "string" then
            fail("a default's key must be text", 2)
        end
        own[key] = value
    end
    -- Off until the player turns it on, unless the plugin says otherwise: ours default to on only
    -- for what nearly everyone wants.
    if own.enabled == nil then
        own.enabled = false
    end
    local module = ns.NewModule(name, description, own)
    module.plugin = type(addon) == "string" and addon ~= "" and addon or true
    -- Whose it is, always shown: problems with it aren't ours to fix.
    module.pluginNotice = {
        text = module.plugin == true and L.PLUGIN_NOTICE or L.PLUGIN_NOTICE_ADDON:format(module.plugin),
        description = L.PLUGIN_NOTICE_DESC,
    }
    module.notice = { module.pluginNotice }

    local handle = {}
    for _, method in ipairs(METHODS) do
        handle[method] = function(self, ...)
            if self ~= handle then
                fail("call it as module:" .. method .. "(...)", 2)
            end
            return module[method](module, ...)
        end
    end
    handles[handle], modules[module] = module, handle
    return setmetatable(handle, { __index = getField, __newindex = setField, __metatable = false })
end

---The module behind a plugin's handle, for the kit's helpers that take one; nil for anything else.
---@param handle any
---@return table|nil
function Plugins.Module(handle)
    return handles[handle]
end

---Notes the plugins' modules in the saved variables and adds every plugin module ever seen there
---to `known`, so Store.Prune keeps the settings of one whose addon isn't loaded this session.
---@param db table ForeverPlusPlusDB
---@param known table<string, boolean>
function Plugins.Remember(db, known)
    if type(db.plugins) ~= "table" then
        db.plugins = {}
    end
    for name, module in pairs(ns.modules) do
        if module.plugin then
            db.plugins[name] = true
        end
    end
    for name in pairs(db.plugins) do
        known[name] = true
    end
end

-- The kit ----------------------------------------------------------------------------------------

local function readOnly(contents, label)
    return setmetatable({}, {
        __index = contents,
        __newindex = function()
            error(label .. " is read only", 2)
        end,
        __metatable = false,
    })
end

-- A read-only table of some of a library's functions, by name.
local function pick(source, names, label)
    local contents = {}
    for _, name in ipairs(names) do
        contents[name] = source[name]
    end
    return readOnly(contents, label)
end

local kit

---The helpers a plugin's module uses, as a read-only table (docs/api.md lists them). Built once.
---@return table kit
function Plugins.Kit()
    if kit then
        return kit
    end
    local function owner(handle)
        return handles[handle]
    end
    kit = readOnly({
        -- Combat and timing
        AfterCombat = function(fn)
            return ns.AfterCombat(fn)
        end,
        Coalesce = function(fn, delay, handle)
            return ns.Frames.Coalesce(fn, delay, owner(handle))
        end,
        Timer = function(handle)
            return ns.Frames.Timer(owner(handle))
        end,
        HasEvent = function(event)
            return ns.HasEvent(event)
        end,
        -- Secret values
        IsReadable = ns.IsReadable,
        IsText = ns.IsText,
        IsNumber = ns.IsNumber,
        -- The world map
        NewMapLayer = function(fill)
            return ns.MapPins.New(fill)
        end,
        SetWaypoint = function(map, x, y)
            return ns.WorldMap.SetWaypoint(map, x, y)
        end,
        IsContinent = function(info, cosmic)
            return ns.WorldMap.IsContinent(info, cosmic)
        end,
        Tooltip = pick(ns.MapTooltip, { "Note", "Detail", "Pair" }, "the kit's Tooltip"),
        -- The QuestieDB addon's data, in our shapes
        QuestieDB = pick(ns.QuestieDB, { "Status", "IsAvailable", "IsReady", "OnReady", "Cancel", "Ids",
            "IdsByName", "Quest", "Npc", "Item", "Object", "UiMapID" }, "the kit's QuestieDB"),
    }, "the plugin kit")
    return kit
end
