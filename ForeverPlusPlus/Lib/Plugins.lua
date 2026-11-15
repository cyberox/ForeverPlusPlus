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
-- The same goes for everything else it's handed: its settings, a timer, and a map layer are small
-- tables of their own over ours, never our objects. Three rules hold all the way through:
--   * What a plugin gives us is checked where it's given. A mistake of its own (a wrong type, a
--     missing argument) raises an error there, in its code, naming the mistake.
--   * Every function it gives us is called guarded (`guarded`), so its error is reported and
--     never stops what called it.
--   * Our own work behind a call runs protected (`safe`): an error of ours is reported and the
--     call returns nil.
--
-- Core is told which modules are plugins' (`Remember`), so the settings of one whose addon is off
-- or gone for a session aren't cleared with those of modules that no longer exist.
local addonName, ns = ...

local type, pairs, ipairs, error, setmetatable, match = type, pairs, ipairs, error, setmetatable, string.match
local pcall, tostring, format, huge, min, max = pcall, tostring, string.format, math.huge, math.min, math.max
local select = select

local L = ns.L

local Plugins = {}
ns.Plugins = Plugins

local NAME = "^[%a][%w_]*$"

local handles = setmetatable({}, { __mode = "k" }) -- handle -> its module
local modules = setmetatable({}, { __mode = "k" }) -- module -> its handle
-- Module -> what this file keeps for it: the plugin's OnDisable, and its map layers, taken off
-- the map when it turns off.
local states = setmetatable({}, { __mode = "k" })

local function fail(message, level)
    error(addonName .. ": " .. message, (level or 1) + 1)
end

-- A plugin's function, wrapped so an error in it is reported (ns.Call) and answers `fallback`
-- instead of stopping what called it. Core and Settings call these in the middle of their own
-- work: login, laying out the Modules page. A plugin's mistake mustn't cost the player those.
local function guarded(fn, fallback)
    return function(...)
        local done, result = false, nil
        ns.Call(function(...)
            result = fn(...)
            done = true
        end, ...)
        if done then
            return result
        end
        return fallback
    end
end

local function finish(ok, ...)
    if ok then
        return ...
    end
    local handler = geterrorhandler and geterrorhandler()
    if handler then
        handler(...)
    end
    return nil
end

-- Our half of a call a plugin makes: an error of ours is reported and the call returns nil, as
-- every v1 function does (API.lua's `export`).
local function safe(fn, ...)
    return finish(pcall(fn, ...))
end

-- A number that is one: not NaN and not infinite. Either would break arithmetic it reaches, and
-- written to the saved variables it makes a file the game can't read back.
local function finite(value)
    return type(value) == "number" and value == value and value ~= huge and value ~= -huge
end

-- Whether Forever++ has read the saved settings (PLAYER_LOGIN): too late for a new module, and
-- for what Core reads only then.
local function started()
    return ns.db ~= nil
end

-- A read-only table over `contents`, with a metatable the plugin can't read or replace.
local function readOnly(contents, label)
    return setmetatable({}, {
        __index = contents,
        __newindex = function()
            error(label .. " is read only", 2)
        end,
        __metatable = false,
    })
end

-- Defaults ---------------------------------------------------------------------------------------

local DEPTH = 8 -- how deep a table default may nest: a table inside itself would never end

-- A copy of a default's value, and whether it's something the saved variables can hold: true or
-- false, text, a number, or a table of those under text and number keys. The copy is ours, so
-- nothing the plugin does to its table later reaches what Store reads.
local function copyData(value, depth)
    local kind = type(value)
    if kind == "boolean" or kind == "string" then
        return value, true
    elseif kind == "number" then
        return value, finite(value)
    elseif kind ~= "table" or depth > DEPTH then
        return nil, false
    end
    local copy = {}
    for key, inner in pairs(value) do
        local keyKind = type(key)
        if keyKind ~= "string" and not (keyKind == "number" and finite(key)) then
            return nil, false
        end
        local innerCopy, ok = copyData(inner, depth + 1)
        if not ok then
            return nil, false
        end
        copy[key] = innerCopy
    end
    return copy, true
end

-- Options ----------------------------------------------------------------------------------------

-- The option fields a plugin may set, and each one's type ("any" for a value of the option's own
-- kind). Anything else is left out of the copy.
local OPTION_FIELDS = {
    key = "string", name = "string", description = "string", section = "string", added = "string",
    requires = "string", slider = "string", choices = "table", shown = "function",
    min = "number", max = "number", step = "number", format = "string",
    editMode = "boolean", -- in the Edit Mode dialog of the frame the kit's EditMode.Register gave it
}

-- A copy of an option one of our builders made (Sounds.Option, ItemButtons.SizeOption), for the
-- kit's Options to hand a plugin: only the fields a plugin may set, and choices of its own, so it
-- never holds a table our own dropdowns read.
local function builtOption(option)
    local copy = {}
    for field in pairs(OPTION_FIELDS) do
        copy[field] = option[field]
    end
    if option.choices then
        copy.choices = {}
        for i, choice in ipairs(option.choices) do
            copy.choices[i] = { choice[1], choice[2] }
        end
    end
    return copy
end

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
    if copy.shown then
        copy.shown = guarded(copy.shown, true) -- an option whose test broke still shows
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
        -- Settings does arithmetic on all of these as it lays the page out.
        if not (finite(copy.min) and finite(copy.max) and copy.min < copy.max and finite(default)
            and default >= copy.min and default <= copy.max) then
            fail("option " .. key .. ": a slider needs min under max and a default between them", 4)
        end
        if copy.step and not (finite(copy.step) and copy.step > 0) then
            fail("option " .. key .. ": a slider's step is a number above 0", 4)
        end
        -- Settings formats the value with it on every draw; one that can't would break the page.
        if copy.format and not pcall(format, copy.format, default) then
            fail("option " .. key .. ": its format doesn't take a number", 4)
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
        keys[copy.key] = copy
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
    -- Settings walks up `requires` until it ends, so a ring of them would never return.
    for _, copy in ipairs(copies) do
        local up, steps = copy, 0
        while up.requires do
            up, steps = keys[up.requires], steps + 1
            if steps > #copies then
                fail("option " .. copy.key .. ": its requires leads back to itself", 3)
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
        copies[index] = { name = action.name, button = action.button, fn = guarded(action.fn),
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
            shown = type(row.shown) == "function" and guarded(row.shown, true) or nil }
    end
    return copies
end

-- The handle -------------------------------------------------------------------------------------

-- What a plugin may set on its handle: the type each takes.
local FIELDS = {
    title = "string", category = "string", added = "string", quickToggle = "string",
    options = "table", actions = "table", notice = "table", perCharacter = "table",
    oldKeys = "table", oldNames = "table",
    OnEnable = "function", OnDisable = "function", OnOptionChanged = "function",
    IsAvailable = "function", Problem = "function",
}

-- The fields Core reads once, at PLAYER_LOGIN: set later, they'd do nothing.
local AT_LOAD = { options = true, perCharacter = true, oldKeys = true, oldNames = true }

-- The Minimap Button's quick toggle groups a module can join (its QUICK_GROUPS).
local QUICK_GROUPS = { loot = true, npcs = true, world = true, nameplates = true, gathering = true,
    other = true }

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
        -- Core calls it with our module; the plugin's function gets its handle. Guarded: one that
        -- errors answers false (not available, no problem) and the rest of login goes on.
        local run = guarded(value, false)
        if key == "OnDisable" then
            states[module].OnDisable = run -- the module's own OnDisable calls it (Register)
            return
        end
        module[key] = function(_, ...)
            return run(handle, ...)
        end
        return
    end
    if started() and AT_LOAD[key] then
        fail(key .. " is set while the plugin loads, before PLAYER_LOGIN", 2)
    end
    if key == "quickToggle" then
        if not QUICK_GROUPS[value] then
            fail("quickToggle is loot, npcs, world, nameplates, gathering, or other", 2)
        end
        module.quickToggle = value
    elseif key == "oldKeys" then
        -- { new = "old" }: a setting or data this version renamed, moved at login (Migrate).
        local keys = {}
        for new, old in pairs(value) do
            if type(new) ~= "string" or new == "enabled" or module.defaults[new] == nil then
                fail("oldKeys names one of the module's defaults, then the name it had", 2)
            end
            if type(old) ~= "string" or old == "enabled" or module.defaults[old] ~= nil then
                fail("oldKeys." .. new .. " is the old name, one the defaults no longer have", 2)
            end
            keys[new] = old
        end
        states[module].oldKeys = keys
    elseif key == "oldNames" then
        -- The names this module had in older versions of the plugin.
        local names = {}
        for index, old in ipairs(value) do
            if type(old) ~= "string" or not match(old, NAME) or old == module.name then
                fail("oldNames lists the names the module had before", 2)
            end
            names[index] = old
        end
        states[module].oldNames = names
    elseif key == "options" then
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

-- A plugin's settings: its own table over the module's `db`, which is Store's and Core reads too.
-- It reads and sets only what the plugin's defaults name, and a value of the default's own type.
-- It looks `module.db` up each time, so it stays right through a profile switch.
local views = setmetatable({}, { __mode = "k" }) -- module -> its view

local function settingsView(module)
    local view = views[module]
    if view then
        return view
    end
    local defaults = module.defaults
    view = setmetatable({}, {
        __index = function(_, key)
            if module.db and type(key) == "string" and defaults[key] ~= nil then
                return module.db[key]
            end
            return nil
        end,
        __newindex = function(_, key, value)
            local default
            if type(key) == "string" then
                default = defaults[key]
            end
            if default == nil then
                fail("db has no \"" .. tostring(key) .. "\": a setting is one of the module's defaults", 2)
            end
            if key == "enabled" then
                fail("db.enabled is the player's to set, on the Modules page", 2)
            end
            if not module.db then
                fail("db is there from PLAYER_LOGIN on", 2)
            end
            if value ~= nil and (type(value) ~= type(default) or type(value) == "number" and not finite(value)) then
                fail("db." .. key .. " takes a " .. type(default) .. ", or nil for its default", 2)
            end
            module.db[key] = value
        end,
        __metatable = false,
    })
    views[module] = view
    return view
end

local function getField(handle, key)
    local module = handles[handle]
    if key == "name" then
        return module.name
    elseif key == "db" then
        return module.db and settingsView(module) or nil
    elseif key == "enabled" then
        return module.enabled and true or false
    end
    return nil
end

local function listen(module, event, fn)
    module:On(event, fn)
    return true
end

local function listenUnit(module, event, units, fn)
    module:OnUnit(event, units, fn)
    return true
end

-- The module methods a handle has, with the handle in the module's place. Each checks what it's
-- given before Core sees it: Core trusts our own modules with these, and a wrong value would
-- error deep in it, or sit in a list it walks on every event.
local function addMethods(handle, module)
    local function check(self, ok, usage)
        if self ~= handle or not ok then
            fail("call it as module:" .. usage, 3)
        end
    end

    -- Only while the module is on, as ours listen from OnEnable: Core stops a module's events as
    -- it turns off, so one added while it's off would be heard until the next time it did.
    function handle.On(self, event, fn)
        check(self, type(event) == "string" and type(fn) == "function", "On(event, fn)")
        if not module.enabled or not safe(ns.HasEvent, event) then
            return false
        end
        return safe(listen, module, event, fn) or false
    end

    -- A unit event for one or two units, which the game then sends for no others.
    function handle.OnUnit(self, event, units, fn)
        check(self, type(event) == "string" and type(units) == "table" and type(units[1]) == "string"
            and (units[2] == nil or type(units[2]) == "string") and units[3] == nil
            and type(fn) == "function", "OnUnit(event, { unit, unit2 }, fn)")
        if not module.enabled or not safe(ns.HasEvent, event) then
            return false
        end
        return safe(listenUnit, module, event, { units[1], units[2] }, fn) or false
    end

    -- Lines on item tooltips, with ours at the sell price (Lib/ItemTooltip.lua). Its hooks can't
    -- come off, so each of the plugin's functions gets one wrapper that does nothing while the
    -- module is off, the same one however often it asks.
    local tooltipFns = { OnInfo = {}, OnPrices = {} }
    local function onItemTooltip(self, fn, where, usage)
        check(self, type(fn) == "function", usage)
        local wrapper = tooltipFns[where][fn]
        if not wrapper then
            local run = guarded(fn)
            wrapper = function(tooltip, data)
                if module.enabled then
                    run(tooltip, data)
                end
            end
            tooltipFns[where][fn] = wrapper
        end
        safe(ns.ItemTooltip[where], wrapper, module)
    end

    function handle.OnItemInfo(self, fn)
        onItemTooltip(self, fn, "OnInfo", "OnItemInfo(fn)")
    end

    function handle.OnItemPrices(self, fn)
        onItemTooltip(self, fn, "OnPrices", "OnItemPrices(fn)")
    end

    function handle.Hook(self, target, method, fn)
        if type(target) == "string" then
            check(self, type(method) == "function", "Hook(name, fn) for a global function")
        else
            check(self, type(target) == "table" and type(method) == "string" and type(fn) == "function",
                "Hook(target, method, fn)")
        end
        safe(module.Hook, module, target, method, fn)
    end

    function handle.HookScript(self, frame, script, fn)
        check(self, (frame == nil or type(frame) == "table") and type(script) == "string"
            and type(fn) == "function", "HookScript(frame, script, fn)")
        safe(module.HookScript, module, frame, script, fn)
    end

    function handle.TooltipPostCall(self, kind, fn)
        check(self, kind ~= nil and type(fn) == "function", "TooltipPostCall(kind, fn)")
        safe(module.TooltipPostCall, module, kind, fn)
    end

    function handle.Print(self, message)
        check(self, type(message) == "string", "Print(message)")
        if module.db then -- its Chat Messages setting isn't read before PLAYER_LOGIN
            safe(module.Print, module, message)
        end
    end
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
        -- Store fills saved data from these at login, tables inside tables too.
        local copy, ok = copyData(value, 1)
        if not ok then
            fail("the default " .. key .. " must be true or false, text, a number, or a table of those", 2)
        end
        own[key] = copy
    end
    -- Off until the player turns it on, unless the plugin says otherwise: ours default to on only
    -- for what nearly everyone wants.
    if own.enabled == nil then
        own.enabled = false
    elseif type(own.enabled) ~= "boolean" then
        fail("the default enabled must be true or false", 2)
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
    addMethods(handle, module)
    local state = { layers = {}, marks = {}, frames = {} }
    states[module] = state
    -- The plugin's OnDisable, then what the kit put up for it: a map layer left on would show
    -- while the module is off, with nothing for the player to turn it off with. The same goes
    -- for its marks on items and its frames' boxes in Edit Mode.
    function module.OnDisable()
        if state.OnDisable then
            state.OnDisable(handle)
        end
        for _, layer in ipairs(state.layers) do
            safe(layer.Disable, layer)
        end
        for _, marks in ipairs(state.marks) do
            safe(marks.Disable)
        end
        for frame in pairs(state.frames) do
            safe(ns.EditMode.Unregister, frame)
        end
    end
    handles[handle], modules[module] = module, handle
    return setmetatable(handle, { __index = getField, __newindex = setField, __metatable = false })
end

---The module behind a plugin's handle, for the kit's helpers that take one; nil for anything else.
---@param handle any
---@return table|nil
function Plugins.Module(handle)
    if handle == nil then
        return nil
    end
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

-- Moves `t[old]` to `t[new]` for each renamed key, where the new one isn't set and the value is of
-- the new default's type; the old key goes either way.
local function moveKeys(t, keys, defaults)
    if type(t) ~= "table" then
        return
    end
    for new, old in pairs(keys) do
        local value = t[old]
        if value ~= nil then
            if t[new] == nil and type(value) == type(defaults[new]) then
                t[new] = value
            end
            t[old] = nil
        end
    end
end

---Moves what the player saved under a plugin module's old name (`oldNames`) and its settings' old
---names (`oldKeys`) to where they now go, in every profile, before Store.Prune clears what no
---module has. It has no version to run once by: a move leaves nothing behind to move again. An
---old name is only one a plugin had, never a module of ours or one that's loaded.
---@param db table ForeverPlusPlusDB
---@param char table ForeverPlusPlusCharDB
function Plugins.Migrate(db, char)
    local seen = type(db.plugins) == "table" and db.plugins or {}
    local charData = type(char.data) == "table" and char.data or {}
    for name, module in pairs(ns.modules) do
        local state = states[module]
        if state then
            for _, old in ipairs(state.oldNames or {}) do
                if seen[old] and not ns.modules[old] then
                    ns.Store.Rename(db, { [old] = name })
                    if charData[old] ~= nil and charData[name] == nil then
                        charData[name] = charData[old]
                    end
                    -- `seen` keeps the old name, so the next character's own data moves too.
                    charData[old] = nil
                end
            end
            if state.oldKeys then
                for _, root in ipairs(ns.Store.Roots(db)) do
                    moveKeys(type(root.settings) == "table" and root.settings[name], state.oldKeys,
                        module.defaults)
                    moveKeys(type(root.data) == "table" and root.data[name], state.oldKeys, module.defaults)
                end
                moveKeys(charData[name], state.oldKeys, module.defaults)
            end
        end
    end
end

-- The kit ----------------------------------------------------------------------------------------

-- The module a timer or a map layer is made for. Each is made once, while the plugin loads, as
-- Core has our own modules make theirs at file load: one made in OnEnable would be made again
-- every time the module turned on, and none of them can be freed. Without a module there would be
-- nothing to stop it with when the plugin's module turns off.
local function ownerAtLoad(handle, what)
    local module = Plugins.Module(handle)
    if not module then
        fail(what .. " needs your module, as RegisterModule returned it", 3)
    end
    if started() then
        fail(what .. " is made once, while the plugin loads (before PLAYER_LOGIN), not in OnEnable", 3)
    end
    return module
end

-- Timers ---------------------------------------------------------------------------------------

local function startTimer(timer, seconds, fn)
    timer:Start(seconds, fn)
    return true
end

-- A plugin's timer: its three methods over one of ours (Frames.Timer), which stays out of reach.
local function newTimer(module)
    local timer = ns.Frames.Timer(module)
    local wrapper
    local function check(self, ok, usage)
        if self ~= wrapper or not ok then
            fail("call it as timer:" .. usage, 3)
        end
    end
    wrapper = readOnly({
        -- Nothing starts while the module is off: a run waiting from then would happen once it
        -- turned on again.
        Start = function(self, seconds, fn)
            check(self, finite(seconds) and seconds >= 0 and type(fn) == "function", "Start(seconds, fn)")
            if not module.enabled then
                return false
            end
            return safe(startTimer, timer, seconds, guarded(fn)) or false
        end,
        Cancel = function(self)
            check(self, true, "Cancel()")
            safe(timer.Cancel, timer)
        end,
        IsPending = function(self)
            check(self, true, "IsPending()")
            return safe(timer.IsPending, timer) or false
        end,
    }, "a plugin's timer")
    return wrapper
end

-- The world map --------------------------------------------------------------------------------

local SIZE_MIN, SIZE_MAX = 4, 128 -- an icon's size in pixels: one that can be seen, and no wall

-- A tooltip line as MapTooltip.AddLines takes it, or nil for anything else: text, or a table of
-- text, a color with r, g, and b, and optionally `right`. Copied, so the tooltip never reads a
-- table the plugin still holds.
local function copyLine(line)
    if type(line) == "string" then
        return line
    end
    if type(line) ~= "table" or type(line[1]) ~= "string" then
        return nil
    end
    local color = line[2]
    if type(color) ~= "table" or not (finite(color.r) and finite(color.g) and finite(color.b)) then
        return line[1]
    end
    return { line[1], { r = color.r, g = color.g, b = color.b },
        right = type(line.right) == "string" and line.right or nil }
end

local function copyLines(lines)
    local copies = {}
    if type(lines) == "table" then
        for _, line in ipairs(lines) do
            copies[#copies + 1] = copyLine(line)
        end
    end
    return copies
end

-- The functions a plugin's icon may have for clicks, each called with what `fn(pin, button)` got.
local CLICKS = { "click", "ctrlClick", "shiftClick" }
-- Its text fields; `title` it must have, since the tooltip is drawn from it.
local TEXTS = { "title", "kind", "clickHint", "shiftHint" }

-- An icon as MapPins takes it, made from what a plugin gave `add`: only the fields docs/api.md
-- names, each checked, since MapPins trusts our own modules with them and reads them later, as
-- the map zooms and the mouse moves. Returns nil and what's wrong with it.
local function copyIcon(x, y, info)
    if not (finite(x) and finite(y)) then
        return nil, "x and y are numbers"
    end
    if type(info) ~= "table" then
        return nil, "info is a table"
    end
    local atlas, texture = info.atlas, info.texture
    if type(atlas) ~= "string" and type(texture) ~= "string" and not finite(texture) then
        return nil, "info needs an atlas or a texture"
    end
    if not finite(info.size) then
        return nil, "info.size is a number"
    end
    local icon = {
        atlas = type(atlas) == "string" and atlas or nil,
        size = max(SIZE_MIN, min(SIZE_MAX, info.size)),
        desaturated = info.desaturated and true or false,
        round = info.round and true or nil,
        waypoint = info.waypoint and true or nil,
    }
    if not icon.atlas then
        icon.texture = texture
    end
    for _, field in ipairs(TEXTS) do
        local value = info[field]
        if value ~= nil and type(value) ~= "string" then
            return nil, "info." .. field .. " is text"
        end
        icon[field] = value
    end
    if not icon.title then
        return nil, "info needs a title"
    end
    local color = info.color
    if color ~= nil then
        if type(color) ~= "table" or not (finite(color[1]) and finite(color[2]) and finite(color[3])) then
            return nil, "info.color is { r, g, b }"
        end
        icon.color = { color[1], color[2], color[3] }
    end
    if info.alpha ~= nil then
        if not finite(info.alpha) then
            return nil, "info.alpha is a number"
        end
        icon.alpha = max(0, min(1, info.alpha))
    end
    -- The plugin's functions get its own `info` back, with whatever else it keeps there, and for
    -- a click a plain table saying where the icon is: never our icon, nor the pin's frame.
    local lines = info.lines
    if type(lines) == "function" then
        local run = guarded(lines)
        icon.lines = function()
            return copyLines(run(info))
        end
    elseif lines ~= nil then
        if type(lines) ~= "table" then
            return nil, "info.lines is a list, or a function giving one"
        end
        icon.lines = copyLines(lines)
    end
    for _, field in ipairs(CLICKS) do
        local fn = info[field]
        if fn ~= nil then
            if type(fn) ~= "function" then
                return nil, "info." .. field .. " is a function"
            end
            local run = guarded(fn)
            icon[field] = function(pin, button)
                run({ x = x, y = y, mapID = pin.mapID, info = info }, button)
            end
        end
    end
    return icon
end

local FILTER_ORDER = 100 -- in the map's filter menu, after every module of ours

-- A setting of the module's that is true or false, for a filter menu checkbox to turn.
local function toggleKey(module, key, what)
    if type(key) ~= "string" or key == "enabled" or type(module.defaults[key]) ~= "boolean" then
        fail(what .. " is one of the module's defaults that is true or false", 5)
    end
    return key
end

-- What NewMapLayer's `filter` asks for, checked and copied: `{ name, key, kinds = { { name, key } } }`.
local function copyFilter(module, filter)
    if type(filter) ~= "table" or type(filter.name) ~= "string" then
        fail("NewMapLayer's filter is { name, key, kinds }", 4)
    end
    local copy = { name = filter.name, key = toggleKey(module, filter.key, "filter.key"), kinds = {} }
    if filter.kinds ~= nil and type(filter.kinds) ~= "table" then
        fail("filter.kinds is a list of { name, key }", 4)
    end
    for index, kind in ipairs(filter.kinds or {}) do
        if type(kind) ~= "table" or type(kind.name) ~= "string" then
            fail("filter.kinds is a list of { name, key }", 4)
        end
        copy.kinds[index] = { name = kind.name, key = toggleKey(module, kind.key, "a kind's key") }
    end
    return copy
end

-- A plugin's map layer: three methods over one of ours (MapPins.New), which stays out of reach.
-- With `filter`, the layer has a checkbox in the map's filter menu under the Forever++ title while
-- the module is on, as our own layers do, and shows only while that setting is on.
local function newLayer(module, fill, filter)
    filter = filter ~= nil and copyFilter(module, filter) or nil
    local run = guarded(fill)
    local layer = ns.MapPins.New(function(mapID, add)
        -- `add` works only while `fill` runs: kept and called later, it would put an icon on
        -- whatever map is showing by then.
        local open = true
        run(mapID, function(x, y, info)
            if not open then
                fail("add is for inside fill", 2)
            end
            local icon, problem = copyIcon(x, y, info)
            if not icon then
                fail("add(x, y, info): " .. problem, 2)
            end
            safe(add, x, y, icon)
        end)
        open = false
    end)
    local layers = states[module].layers
    layers[#layers + 1] = layer
    -- Shows the layer when the module is on and the filter's setting (if any) says so, and takes
    -- it off the map otherwise.
    local function show()
        if module.enabled and (not filter or module.db[filter.key]) then
            safe(layer.Enable, layer)
            return true
        end
        safe(layer.Disable, layer)
        return false
    end
    if filter then
        local kinds = {}
        for index, kind in ipairs(filter.kinds) do
            kinds[index] = {
                name = kind.name,
                get = function() return module.db[kind.key] end,
                set = function(on)
                    ns.SetOption(module.name, kind.key, on and true or false)
                    safe(layer.Refresh, layer)
                end,
            }
        end
        safe(ns.WorldMap.AddFilter, FILTER_ORDER, function()
            return module.enabled and true or false
        end, function(root)
            ns.WorldMap.FilterLayer(root, filter.name, function()
                return module.db[filter.key]
            end, function(on)
                -- As from the Settings page, so the plugin hears of it in OnOptionChanged.
                ns.SetOption(module.name, filter.key, on and true or false)
                show()
            end, kinds)
        end)
    end
    local wrapper
    local function check(self, usage)
        if self ~= wrapper then
            fail("call it as layer:" .. usage, 3)
        end
    end
    wrapper = readOnly({
        -- Only while the module is on; it comes off by itself when the module turns off. With a
        -- filter, only while its setting is on too: calling this again after that changed (from
        -- OnOptionChanged) shows or hides the layer to match.
        Enable = function(self)
            check(self, "Enable()")
            return show()
        end,
        Disable = function(self)
            check(self, "Disable()")
            safe(layer.Disable, layer)
        end,
        Refresh = function(self)
            check(self, "Refresh()")
            safe(layer.Refresh, layer)
        end,
    }, "a plugin's map layer")
    return wrapper
end

-- Marks on items -------------------------------------------------------------------------------

-- Where a plugin's marks go, and the size, corner, and padding they take when the module has no
-- setting of that name: what our own marks default to.
local MARK_PLACES = { "bags", "bank", "merchant", "auction", "loot" }
local MARK_LOOK = { size = 14, corner = "TOPLEFT", padding = 1 }
local MARK_CORNERS = { TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true }

-- A plugin's marks on item icons: three methods over Lib/ItemButtons.lua, which finds Blizzard's
-- item buttons and keeps our textures off their frames. `test(link, place)` says whether an item
-- gets the mark. The plugin never sees a button or a texture.
local function newMarks(module, test, look)
    if type(look) ~= "table" or (type(look.atlas) ~= "string" and type(look.texture) ~= "string"
        and not finite(look.texture)) then
        fail("NewItemMarks(test, module, look): look needs an atlas or a texture", 3)
    end
    local color = look.color
    if color ~= nil and (type(color) ~= "table"
        or not (finite(color[1]) and finite(color[2]) and finite(color[3]))) then
        fail("NewItemMarks: look.color is { r, g, b }", 3)
    end
    local atlas = type(look.atlas) == "string" and look.atlas or nil
    local texture, r, g, b = look.texture, color and color[1], color and color[2], color and color[3]
    local run = guarded(test, false)
    local ItemButtons = ns.ItemButtons
    local active = false

    local marks = ItemButtons.Overlays(function(icon)
        local mark = icon:GetParent():CreateTexture(nil, "OVERLAY", nil, 7)
        if atlas then
            mark:SetAtlas(atlas)
        else
            mark:SetTexture(texture)
        end
        if r then
            mark:SetVertexColor(r, g, b)
        end
        return mark
    end)

    -- The module's own Size, Corner, and Padding settings where its defaults have them (the
    -- kit's Options make the options), ours otherwise.
    local function setting(key, ok)
        local value = module.db[key]
        if value == nil or not ok(value) then
            return MARK_LOOK[key]
        end
        return value
    end
    local function place()
        return {
            size = setting("size", finite),
            corner = setting("corner", function(value) return MARK_CORNERS[value] end),
            padding = setting("padding", finite),
        }
    end

    -- The walk over every place is ours (ItemButtons.Walk), as our own marking modules use it. A
    -- place is on unless the module has a setting of its name that is off.
    local walk = ItemButtons.Walk(module, function(icon, link, where)
        if not icon then
            return
        end
        local mark = marks:Set(icon, link and run(link, where))
        if mark then
            ItemButtons.PlaceMark(mark, icon, place())
        end
    end, { shows = function(where)
        return active and module.db[where] ~= false
    end })

    local function refresh()
        walk:Refresh()
    end
    -- A merchant's links are missing until the game has loaded its items; look again once it has.
    local refreshSoon = ns.Frames.Coalesce(function()
        if active then
            refresh()
        end
    end, 0.5, module)
    local function onItemInfo()
        if active and ItemButtons.MerchantShown() then
            refreshSoon()
        end
    end

    local function hook()
        walk:Hook()
        module:On("GET_ITEM_INFO_RECEIVED", onItemInfo)
        refresh()
    end
    local function disable()
        active = false
        walk:Stop()
        marks:HideAll()
    end
    local list = states[module].marks
    list[#list + 1] = { Disable = disable }

    local wrapper
    local function check(self, usage)
        if self ~= wrapper then
            fail("call it as marks:" .. usage, 3)
        end
    end
    wrapper = readOnly({
        -- Only while the module is on; the marks come off by themselves when it turns off.
        Enable = function(self)
            check(self, "Enable()")
            if not module.enabled then
                return false
            end
            active = true
            safe(hook)
            return true
        end,
        Disable = function(self)
            check(self, "Disable()")
            safe(disable)
        end,
        -- After what `test` answers changed, or one of the module's mark settings.
        Refresh = function(self)
            check(self, "Refresh()")
            if active then
                safe(refresh)
            end
        end,
    }, "a plugin's item marks")
    return wrapper
end

-- Edit Mode --------------------------------------------------------------------------------------

-- Whether the module's defaults have what a frame in Edit Mode is placed and sized from.
local function placedFromSettings(module)
    local defaults = module.defaults
    return finite(defaults.x) and finite(defaults.y) and finite(defaults.scale)
        and defaults.scale >= 50 and defaults.scale <= 200
end

local function isProtected(frame)
    return frame:IsProtected()
end

-- The rest -------------------------------------------------------------------------------------

-- A color for an item tooltip line as Lib/ItemTooltip.lua takes it: one of its names, or a copy of
-- { r, g, b }. White for none.
local LINE_COLORS = { gray = true, white = true, gold = true }

local function lineColor(color, usage)
    if color == nil then
        return "white"
    elseif LINE_COLORS[color] then
        return color
    elseif type(color) == "table" and finite(color[1]) and finite(color[2]) and finite(color[3]) then
        return { color[1], color[2], color[3] }
    end
    fail("ItemTooltip." .. usage .. ": color is gray, white, gold, or { r, g, b }", 3)
end

local function lineAlign(align, usage)
    if align == nil then
        return "right"
    elseif align ~= "right" and align ~= "inline" then
        fail("ItemTooltip." .. usage .. ": align is right or inline", 3)
    end
    return align
end

-- The text arguments of one of the kit's option builders.
local function texts(usage, ...)
    for i = 1, select("#", ...) do
        if type((select(i, ...))) ~= "string" then
            fail("Options." .. usage, 3)
        end
    end
end

-- A read-only table of some of a library's functions, by name, each called protected. The
-- library is looked up when one is called, so a function it lacks answers nil.
local function pick(library, names, label, checks)
    local contents = {}
    for _, name in ipairs(names) do
        contents[name] = checks and checks[name] or function(...)
            return safe(ns[library][name], ...)
        end
    end
    return readOnly(contents, label)
end

-- A tooltip line's text, from text or a number.
local function lineText(value, usage)
    if type(value) == "number" then
        return tostring(value)
    elseif type(value) ~= "string" then
        fail("Tooltip." .. usage, 3)
    end
    return value
end

-- The plugin's function -> the guarded one QuestieDB waits with, so Cancel finds it. Weak both
-- ways: QuestieDB holds the guarded one while it waits, and nothing needs it after.
local readyFns = setmetatable({}, { __mode = "kv" })

local kit

---The helpers a plugin's module uses, as a read-only table (docs/api.md lists them). Built once.
---@return table kit
function Plugins.Kit()
    if kit then
        return kit
    end
    kit = readOnly({
        -- Combat and timing
        AfterCombat = function(fn)
            if type(fn) ~= "function" then
                fail("AfterCombat(fn)", 2)
            end
            safe(ns.AfterCombat, guarded(fn))
        end,
        Coalesce = function(fn, delay, handle)
            if type(fn) ~= "function" or delay ~= nil and not (finite(delay) and delay >= 0) then
                fail("Coalesce(fn, delay, module)", 2)
            end
            local module = ownerAtLoad(handle, "Coalesce")
            local queue, cancel = ns.Frames.Coalesce(guarded(fn), delay, module)
            -- Nothing is queued while the module is off, as with a timer.
            return function()
                if module.enabled then
                    safe(queue)
                end
            end, function()
                safe(cancel)
            end
        end,
        Timer = function(handle)
            return newTimer(ownerAtLoad(handle, "Timer"))
        end,
        HasEvent = function(event)
            return type(event) == "string" and safe(ns.HasEvent, event) or false
        end,
        -- Secret values
        IsReadable = ns.IsReadable,
        IsText = ns.IsText,
        IsNumber = ns.IsNumber,
        -- The world map
        NewMapLayer = function(fill, handle, filter)
            if type(fill) ~= "function" then
                fail("NewMapLayer(fill, module, filter)", 2)
            end
            return newLayer(ownerAtLoad(handle, "NewMapLayer"), fill, filter)
        end,
        -- Marks on items
        NewItemMarks = function(test, handle, look)
            if type(test) ~= "function" then
                fail("NewItemMarks(test, module, look)", 2)
            end
            return newMarks(ownerAtLoad(handle, "NewItemMarks"), test, look)
        end,
        -- Item tooltips: lines in the style of ours, for a function given to module:OnItemInfo or
        -- module:OnItemPrices.
        ItemTooltip = readOnly({
            AddInfo = function(tooltip, label, text, color, align)
                if type(tooltip) ~= "table" or type(label) ~= "string"
                    or (type(text) ~= "string" and not finite(text)) then
                    fail("ItemTooltip.AddInfo(tooltip, label, text, color, align)", 2)
                end
                safe(ns.ItemTooltip.AddInfo, tooltip, label, tostring(text), lineAlign(align, "AddInfo"),
                    lineColor(color, "AddInfo"))
            end,
            AddPrice = function(tooltip, data, label, copper, align)
                if type(tooltip) ~= "table" or type(data) ~= "table" or type(label) ~= "string"
                    or not (finite(copper) and copper >= 0) then
                    fail("ItemTooltip.AddPrice(tooltip, data, label, copper, align)", 2)
                end
                safe(ns.ItemTooltip.AddPrice, tooltip, data, label, copper, "stack",
                    lineAlign(align, "AddPrice"), "gray")
            end,
            ItemID = function(data)
                return type(data) == "table" and safe(ns.ItemTooltip.ItemID, data) or nil
            end,
        }, "the kit's ItemTooltip"),
        -- Edit Mode: a frame of the plugin's own, moved and sized like Blizzard's.
        EditMode = readOnly({
            Register = function(handle, frame, label, apply, onChange)
                local module = Plugins.Module(handle)
                if not module or type(frame) ~= "table" or type(frame.SetPoint) ~= "function"
                    or type(label) ~= "string" or type(apply) ~= "function"
                    or (onChange ~= nil and type(onChange) ~= "function") then
                    fail("EditMode.Register(module, frame, label, apply, onChange)", 2)
                end
                if not placedFromSettings(module) then
                    fail("EditMode.Register needs the defaults x, y, and scale (50 to 200)", 2)
                end
                -- Moving a protected frame in combat is blocked, and one of Blizzard's isn't ours
                -- to move at all.
                if safe(isProtected, frame) ~= false then
                    fail("EditMode.Register is for a frame of your own that isn't protected", 2)
                end
                if not module.enabled then
                    return false
                end
                states[module].frames[frame] = true
                safe(ns.EditMode.RegisterModule, module, frame, label, guarded(apply),
                    onChange and guarded(onChange) or nil)
                return true
            end,
            Place = function(frame, x, y)
                if type(frame) ~= "table" or not (finite(x) and finite(y)) then
                    fail("EditMode.Place(frame, x, y)", 2)
                end
                safe(ns.EditMode.Place, frame, x, y)
            end,
            IsActive = function()
                return safe(ns.EditMode.IsActive) and true or false
            end,
        }, "the kit's EditMode"),
        -- Options every module names and fills alike, each a new table for `module.options`
        Options = readOnly({
            Sound = function(key, description, requires)
                texts("Sound(key, description, requires)", key, description, requires or "")
                return builtOption(ns.Sounds.Option(key, description, { requires = requires }))
            end,
            Key = function(key, name, description)
                texts("Key(key, name, description)", key, name, description)
                return builtOption(ns.Keys.Option(key, name, description))
            end,
            Chat = function(description)
                texts("Chat(description)", description)
                return builtOption(ns.ChatOption(description))
            end,
            MarkCorner = function(description)
                texts("MarkCorner(description)", description)
                return builtOption(ns.ItemButtons.CornerOption(description))
            end,
            MarkSize = function(name, description)
                texts("MarkSize(name, description)", name, description)
                return builtOption(ns.ItemButtons.SizeOption(name, description))
            end,
            MarkPadding = function()
                return builtOption(ns.ItemButtons.PaddingOption())
            end,
            MarkPlace = function(place, description)
                texts("MarkPlace(place, description)", place, description)
                local known = false
                for _, name in ipairs(MARK_PLACES) do
                    known = known or name == place
                end
                if not known then
                    fail("Options.MarkPlace: place is bags, bank, merchant, auction, or loot", 2)
                end
                return builtOption(ns.ItemButtons.PlaceOption(place, description))
            end,
            MapIconSize = function(key)
                texts("MapIconSize(key)", key)
                return builtOption(ns.MapPins.SizeOption(key))
            end,
            MapIconOpacity = function(key)
                texts("MapIconOpacity(key)", key)
                return builtOption(ns.MapPins.OpacityOption(key))
            end,
            MapOnContinents = function(key)
                texts("MapOnContinents(key)", key)
                return builtOption(ns.MapPins.ContinentOption(key))
            end,
        }, "the kit's Options"),
        -- What the Sound and Key options' settings mean
        PlaySound = function(key)
            if type(key) == "string" then
                safe(ns.Sounds.Play, key)
            end
        end,
        IsKeyDown = function(key)
            return type(key) == "string" and safe(ns.Keys.IsDown, key) or false
        end,
        -- Blizzard's map pin, and the map tree
        SetWaypoint = function(map, x, y, name)
            if not (finite(x) and finite(y)) then
                return false, "range"
            elseif not finite(map) then
                return false, "zone"
            end
            return safe(ns.WorldMap.SetWaypoint, map, x, y, type(name) == "string" and name or nil)
        end,
        IsContinent = function(info, cosmic)
            return type(info) == "table" and safe(ns.WorldMap.IsContinent, info, cosmic) or false
        end,
        Tooltip = pick("MapTooltip", { "Note", "Detail", "Pair" }, "the kit's Tooltip", {
            Note = function(text)
                return safe(ns.MapTooltip.Note, lineText(text, "Note(text)"))
            end,
            Detail = function(text)
                return safe(ns.MapTooltip.Detail, lineText(text, "Detail(text)"))
            end,
            Pair = function(label, value)
                return safe(ns.MapTooltip.Pair, lineText(label, "Pair(label, value)"),
                    lineText(value, "Pair(label, value)"))
            end,
        }),
        -- The QuestieDB addon's data, in our shapes
        QuestieDB = pick("QuestieDB", { "Status", "IsAvailable", "IsReady", "OnReady", "Cancel", "Ids",
            "IdsByName", "Quest", "Npc", "Item", "Object", "UiMapID" }, "the kit's QuestieDB", {
            OnReady = function(fn)
                if type(fn) ~= "function" then
                    fail("QuestieDB.OnReady(fn)", 2)
                end
                local run = readyFns[fn] or guarded(fn)
                readyFns[fn] = run
                safe(ns.QuestieDB.OnReady, run)
            end,
            Cancel = function(fn)
                local run = fn ~= nil and readyFns[fn]
                if run then
                    safe(ns.QuestieDB.Cancel, run)
                end
            end,
        }),
    }, "the plugin kit")
    return kit
end
