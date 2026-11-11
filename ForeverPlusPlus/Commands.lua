-- /fpp and the presets in the Defaults popup. Loaded right after Core.lua: modules add their own
-- commands with ns.AddCommand as they load. Everything here uses only Core's public functions and
-- Lib (Lib/Presets.lua and Lib/Store.lua, read once the addon has loaded).
local _, ns = ...

local ipairs, type, format, tostring = ipairs, type, string.format, tostring
local concat, strsplit, strtrim = table.concat, strsplit, strtrim

local L = ns.L

-- Presets -------------------------------------------------------------------------------------

-- What a preset does to each module is declared in the module's own file (`module.presets`) and
-- read through Lib/Presets.lua. Here are the ways the Defaults popup puts the profile in use back:
-- to the plain defaults with what `enable` and `options` say on top (ns.ApplyPreset), or based on
-- a preset (ns.UsePreset), which then keeps following it.

-- Bases the profile in use on `preset` (nil for none), puts every module's options
-- (`module.options`) back to what a reset gives (ns.BaseValue: the preset's value, else the
-- default) with `options` on top, and turns the modules on or off as their base says, or on for
-- those in `enable`. What it puts back is forgotten, not saved as a choice, so a later release's
-- better default, or a preset that grew, reaches it; what it sets otherwise (an override, a module
-- in `enable`) is saved like the player's own choice. Modules that are always on, data, and
-- options that are one of Blizzard's settings (`cvar`) are left as they are.
local function reset(preset, enable, options)
    local before = {}
    for _, name in ipairs(ns.order) do
        local module = ns.modules[name]
        if not (module.alwaysOn or module.unavailable) then
            for _, option in ipairs(module.options or {}) do
                local key = option.key
                if type(module.defaults[key]) ~= "table" and not option.cvar then
                    before[#before + 1] = { module, key, module.db[key] }
                end
            end
        end
    end
    local Store = ns.Store
    Store.SetPreset(ns.db, Store.profile, preset)
    local changed = {}
    for _, entry in ipairs(before) do
        local module, key, was = entry[1], entry[2], entry[3]
        local base = ns.BaseValue(module, key)
        local overrides = options and options[module.name]
        local value = overrides and overrides[key]
        if value == nil or type(value) == "table" then
            value = base
        end
        if value == base then
            module.db[key] = nil -- forgotten: the base reads back
        else
            module.db[key] = value
        end
        if was ~= value then
            changed[#changed + 1] = entry
        end
    end
    local wanted = {}
    for _, name in ipairs(enable or {}) do
        wanted[name] = true
    end
    for _, name in ipairs(ns.order) do
        local module = ns.modules[name]
        local base = ns.BaseValue(module, "enabled") and true or false
        local on = wanted[name] or base
        ns.SetEnabled(name, on)
        if on == base and not (module.alwaysOn or module.unavailable) then
            module.db.enabled = nil -- at its base: forgotten, not a choice
        end
    end
    for _, entry in ipairs(changed) do
        local module, key = entry[1], entry[2]
        if module.enabled then
            ns.OptionChanged(module, key)
        end
    end
    for _, name in ipairs(ns.order) do
        ns.RefreshSetting(name)
    end
end

---Puts the profile in use (Lib/Profiles.lua) back to the modules' defaults, then turns on the
---modules in `enable` and sets the option values in `options`; the other profiles stay as they
---are. Without either, it's Recommended Defaults in the Defaults popup. The profile is based on no
---preset afterwards. Everything else a module saves stays: data (prices, seen cinematics, chat
---history) and what's set in Edit Mode (positions and scale). Applies live, like the checkboxes.
---@param enable? string[] module names to turn on whatever their default is
---@param options? table<string, table<string, any>> per module, option values used instead of its defaults
function ns.ApplyPreset(enable, options)
    reset(nil, enable, options)
end

---Bases the profile in use on a preset (Lib/Presets.lua) and puts it back to it: every option
---the player set reads the preset's value, else its default, and the modules are on as the preset
---says. It looks as ns.ApplyPreset(Presets.Flat(name)) would leave it, but stays based on the
---preset, so what a later release adds to it reaches this profile. Applies live.
---@param name string
---@return boolean done false for a preset this version doesn't have
function ns.UsePreset(name)
    if not ns.Presets.Exists(name) then
        return false
    end
    reset(name)
    return true
end

-- /fpp ----------------------------------------------------------------------------------------

local commands, commandOrder = {}, {} -- name -> { usage, description, fn }, and their order

---Adds `/fpp <name>`, for a module's own command. `fn` gets the text typed after the name.
---@param name string one lowercase word
---@param usage string what follows the name in /fpp help, or ""
---@param description string one line for /fpp help
---@param fn fun(rest: string)
---@param owner? string a module the command needs: it works and is listed only while that one is on
function ns.AddCommand(name, usage, description, fn, owner)
    if commands[name] then
        error("Forever++: /fpp " .. name .. " already exists", 2) -- the later one would hide it
    end
    commands[name] = { usage = usage, description = description, fn = fn, owner = owner }
    commandOrder[#commandOrder + 1] = name
end

-- A command whose module is off is as if it weren't there.
local function commandOn(info)
    local owner = info and (info.owner and ns.modules[info.owner])
    return info and (not owner or owner.enabled) or false
end

local function findModule(query)
    query = query:lower()
    for _, name in ipairs(ns.order) do
        if name:lower() == query and not ns.modules[name].unavailable then
            return ns.modules[name]
        end
    end
end

local function list()
    ns.Print(L.SLASH_MODULES)
    for _, name in ipairs(ns.order) do
        local module = ns.modules[name]
        if not (module.alwaysOn or module.unavailable) then
            ns.PrintLine(format("  %s  %s  |cff999999%s|r",
                ns.StateText(module.db.enabled and not module.locked), name,
                module.description))
        end
    end
end

-- /fpp options and /fpp set work on any module's `module.options`: a checkbox takes on/off, a
-- dropdown takes one of its choice keys, a slider a number. `enabled` is the module's own on/off.

local booleans = { on = true, off = false, ["true"] = true, ["false"] = false, yes = true,
    no = false, ["1"] = true, ["0"] = false }

local function findOption(module, query)
    query = query:lower()
    for _, option in ipairs(module.options or {}) do
        if option.key:lower() == query then
            return option
        end
    end
end

-- "on", "off", the choice key, or the number, and what it may be set to.
local function describe(module, option)
    local value = module.db[option.key]
    local kind = ns.OptionKind(option)
    if kind == "slider" then
        return tostring(value), format("%s-%s", option.min, option.max)
    elseif kind == "checkbox" then
        return value and "on" or "off", "on, off"
    end
    local keys = {}
    for i, choice in ipairs(option.choices) do
        keys[i] = choice[1]
    end
    return tostring(value), concat(keys, ", ")
end

local function listOptions(module)
    ns.Print(format(L.OPTIONS_HEADER, module.name, module.enabled and L.ON or L.OFF,
        module.name))
    if not module.options or #module.options == 0 then
        ns.PrintLine(format("  |cff999999%s|r", L.OPTIONS_NONE))
    end
    for _, option in ipairs(module.options or {}) do
        local value, allowed = describe(module, option)
        ns.PrintLine(format("  %s = |cffffd100%s|r  |cff999999%s (%s)%s|r", option.key, value,
            option.name, allowed, option.debug and L.OPTIONS_DEBUG or ""))
    end
end

-- /fpp set <module> <option> [value]. Without a value it only shows the current one and what it
-- can be, and changes nothing, unless `flip` (/fpp toggle) turns a checkbox the other way.
local function set(rest, flip)
    local moduleName, key, value = strsplit(" ", rest or "", 3)
    local module = moduleName and moduleName ~= "" and findModule(moduleName)
    if not module then
        ns.Print(moduleName and moduleName ~= "" and format(L.NO_MODULE, moduleName)
            or L.SET_USAGE)
        return
    end
    if not key or key == "" then
        listOptions(module)
        return
    end
    value = value and strtrim(value):lower()
    if key:lower() == "enabled" then
        if module.alwaysOn then
            ns.Print(format(L.MODULE_ALWAYS_ON, module.title or module.name))
            return
        end
        local on = booleans[value or ""]
        if on == nil and flip and not value then
            on = not module.enabled
        end
        if on == nil then
            ns.Print(format(L.MODULE_STATE_ALLOWED, module.name,
                module.enabled and L.ON or L.OFF))
            return
        end
        ns.SetEnabled(module.name, on)
        -- What it is now, not what was asked: a locked module stays off.
        ns.Print(format(L.MODULE_STATE, module.name, module.enabled and L.ON or L.OFF))
        return
    end
    local option = findOption(module, key)
    if not option then
        ns.Print(format(L.NO_OPTION, module.name, key, module.name))
        return
    end
    local new
    local kind = ns.OptionKind(option)
    if kind == "slider" then
        new = ns.SliderValue(option, value)
    elseif kind == "dropdown" then
        for _, choice in ipairs(option.choices) do
            if choice[1]:lower() == value then
                new = choice[1]
            end
        end
    elseif value then
        new = booleans[value]
    elseif flip then
        new = not module.db[option.key]
    end
    if new == nil then
        local current, allowed = describe(module, option)
        ns.Print(format(L.OPTION_STATE_ALLOWED, module.name, option.key, current, allowed))
        if option.description then
            ns.PrintLine(format("  |cff999999%s: %s|r", option.name, option.description))
        end
        return
    end
    ns.SetOption(module.name, option.key, new)
    ns.Print(format(L.OPTION_STATE, module.name, option.key, (describe(module, option))))
end

SLASH_FOREVERPLUSPLUS1 = "/fpp"
SLASH_FOREVERPLUSPLUS2 = "/forever++"
SlashCmdList.FOREVERPLUSPLUS = function(message)
    local command, rest = strsplit(" ", strtrim(message or ""), 2)
    command = (command or ""):lower()
    if commandOn(commands[command]) then
        commands[command].fn(rest or "")
    elseif commands[command] then
        -- A module's command while that module is off: say so, rather than open Settings.
        local owner = ns.modules[commands[command].owner]
        ns.Print(format(L.COMMAND_NEEDS_MODULE, command, owner.title or owner.name))
    elseif command == "toggle" and rest then
        -- /fpp toggle <module> [option] [value]: the module itself when no option is named.
        set(rest:find(" ") and rest or rest .. " enabled", true)
    elseif command == "set" then
        set(rest)
    elseif command == "options" and rest then
        local module = findModule(rest)
        if module then
            listOptions(module)
        else
            ns.Print(format(L.NO_MODULE, rest))
        end
    elseif command == "reset" then
        -- It throws away saved data too (prices, flight times, chat history), so it asks first.
        -- Every module turns off before the wipe, so each puts back what it changed (the player's
        -- own CVars, kept only in the saved data, macros, frames); CVars wait out combat.
        ns.Confirm("RESET_ALL", L.RESET_CONFIRM, function()
            ns.AfterCombat(function()
                for _, name in ipairs(ns.order) do
                    ns.SetEnabled(name, false)
                end
                ForeverPlusPlusDB, ForeverPlusPlusCharDB = nil, nil
                ReloadUI()
            end)
        end)
    elseif command == "list" or command == "help" or not ns.OpenSettings() then
        list()
        for _, line in ipairs(ns.Commands()) do
            ns.PrintLine(format("  %s  |cff999999%s|r", line[1], line[2]))
        end
    end
end

---Every /fpp command, built in and added by modules, for help text and the About page.
---@return table lines { { "/fpp ...", description }, ... }
function ns.Commands()
    local lines = {
        { "/fpp, /forever++", L.SLASH_OPEN },
        { "/fpp list", L.SLASH_LIST },
        { "/fpp toggle <module> [option]", L.SLASH_TOGGLE },
        { "/fpp options <module>", L.SLASH_OPTIONS },
        { "/fpp set <module> <option> [value]", L.SLASH_SET },
        { "/fpp reset", L.SLASH_RESET },
    }
    for _, name in ipairs(commandOrder) do
        local info = commands[name]
        if commandOn(info) then
            local usage = info.usage ~= "" and " " .. info.usage or ""
            lines[#lines + 1] = { format("/fpp %s%s", name, usage), info.description }
        end
    end
    return lines
end
