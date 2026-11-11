-- /fpp and the presets in the Defaults popup. Loaded right after Core.lua: modules add their own
-- commands with ns.AddCommand as they load. Everything here uses only Core's public functions.
local _, ns = ...

local ipairs, type, format, tostring = ipairs, type, string.format, tostring
local concat, strsplit, strtrim = table.concat, strsplit, strtrim

local L = ns.L

-- Presets -------------------------------------------------------------------------------------

-- What the Developer's Defaults preset does, on top of every module's default settings, as each
-- module declares it in its own file: `module.developer = { enabled = true, options = { key =
-- value } }`, turned on and set differently from its defaults. A locked module isn't turned on.
local function developerPreset()
    local enables, options = {}, {}
    for _, name in ipairs(ns.order) do
        local module = ns.modules[name]
        local developer = module.developer
        if developer then
            if developer.enabled and not module.locked then
                enables[#enables + 1] = name
            end
            options[name] = developer.options
        end
    end
    return enables, options
end

---The Developer's Defaults preset as ns.ApplyPreset takes it, for a profile made from it
---(Profiles.CreateFromPreset) without applying it to the one in use.
---@return string[] enables module names it turns on
---@return table<string, table<string, any>> options per module, option values it sets
function ns.DeveloperPreset()
    return developerPreset()
end

---Puts every module's options (`module.options`) back to their defaults, then turns on the
---modules in `enable`, in the profile in use only (Lib/Profiles.lua); the others stay as they are.
---Everything else a module saves stays: data (prices, seen cinematics, chat
---history) and what's set in Edit Mode (positions and scale). What it puts back to the default is
---forgotten, not saved as a choice, so a later release's better default reaches it; what it sets
---otherwise (an override, a module turned on) is saved like the player's own choice.
---Modules that are always on have nothing to reset. Applies live, like the checkboxes do.
---@param enable? string[] module names to turn on whatever their default is
---@param options? table<string, table<string, any>> per module, option values used instead of its defaults
function ns.ApplyPreset(enable, options)
    local wanted = {}
    for _, name in ipairs(enable or {}) do
        wanted[name] = true
    end
    local changed = {}
    for _, name in ipairs(ns.order) do
        local module = ns.modules[name]
        if not (module.alwaysOn or module.unavailable) then
            local overrides = options and options[name]
            for _, option in ipairs(module.options or {}) do
                local key = option.key
                local default = module.defaults[key]
                local value = default
                if overrides and overrides[key] ~= nil then
                    value = overrides[key]
                end
                -- An option that is one of Blizzard's settings (`cvar`) stays the player's.
                if type(value) ~= "table" and not option.cvar then
                    local before = module.db[key]
                    -- nil forgets the choice; the default reads back
                    if value == default then
                        module.db[key] = nil
                    else
                        module.db[key] = value
                    end
                    if before ~= value then
                        changed[#changed + 1] = { module, key }
                    end
                end
            end
        end
    end
    for _, name in ipairs(ns.order) do
        local module = ns.modules[name]
        local on = wanted[name] or module.defaults.enabled
        ns.SetEnabled(name, on)
        if on == module.defaults.enabled and not (module.alwaysOn or module.unavailable) then
            module.db.enabled = nil -- at its default: forgotten, not a choice
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

---Defaults plus the modules the developer turns on (Developer's Defaults in the Defaults popup).
function ns.ApplyDeveloperDefaults()
    ns.ApplyPreset(developerPreset())
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
