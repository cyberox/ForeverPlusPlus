-- Presets: named sets of settings on top of the modules' defaults, such as Developer's Defaults.
-- A preset is registered here, in Lib, with its title; each module says for itself what it does
-- under it, in its own file:
--
--   module.presets = {
--       developer = { enabled = true, options = { hideJunk = true } },
--   }
--
-- `enabled` turns the module on (or, false, off) and `options` sets option values in place of its
-- defaults. A preset can extend another (`extends`): it starts as everything its parent has, and a
-- module declares only where it differs, so a value is looked up along the chain, nearest first.
--
-- A profile can be based on a preset (Lib/Store.lua keeps the link): then a setting the player
-- hasn't set reads what the preset says before the module's default, so what a later release adds
-- to the preset reaches the profile. A preset never says anything about a module that is always on
-- or that this client doesn't get, never turns on a locked module, and never touches data (a
-- default that is a table) or an option that is one of Blizzard's settings (`cvar`).
local _, ns = ...

local ipairs, pairs, type, error, tostring, setmetatable = ipairs, pairs, type, error, tostring,
    setmetatable

local L = ns.L

local Presets = {}
ns.Presets = Presets

local registry = {} -- name -> { name, title, description, extends }
local order = {} -- names, in the order registered

---Adds a preset. `extends` names one registered before it, so a chain can't loop back on itself:
---naming a preset that isn't there (yet) is an error, at load.
---@param name string a lowercase key, the one modules use in `module.presets`
---@param info { title: string, description?: string, extends?: string }
---@return string name
function Presets.Register(name, info)
    if type(name) ~= "string" or not name:match("^[%l%d_]+$") then
        error("Forever++: a preset's name is a lowercase key, not " .. tostring(name), 2)
    elseif registry[name] then
        error("Forever++: a preset called " .. name .. " already exists", 2)
    elseif type(info) ~= "table" or type(info.title) ~= "string" then
        error("Forever++: preset " .. name .. " needs a title", 2)
    elseif info.extends ~= nil and not registry[info.extends] then
        error("Forever++: preset " .. name .. " extends " .. tostring(info.extends)
            .. ", which isn't registered before it", 2)
    end
    registry[name] = { name = name, title = info.title, description = info.description,
        extends = info.extends }
    order[#order + 1] = name
    return name
end

---Whether this version has a preset by that name.
---@param name any
---@return boolean
function Presets.Exists(name)
    return type(name) == "string" and registry[name] ~= nil
end

---Every preset's name, in the order they were registered.
---@return string[]
function Presets.List()
    local list = {}
    for i, name in ipairs(order) do
        list[i] = name
    end
    return list
end

---A preset's title, for buttons and dropdowns, or nil for one that isn't there.
---@param name string
---@return string?
function Presets.Title(name)
    local preset = Presets.Exists(name) and registry[name]
    return preset and preset.title or nil
end

---A preset's description, or nil.
---@param name string
---@return string?
function Presets.Description(name)
    local preset = Presets.Exists(name) and registry[name]
    return preset and preset.description or nil
end

---A preset and the ones it extends, nearest first: { "streamer", "developer" }. Empty for one
---that isn't there. Stops at a preset already in the chain, so even a registry changed by hand
---can't loop.
---@param name string
---@return string[]
function Presets.Chain(name)
    local chain, seen = {}, {}
    local preset = Presets.Exists(name) and registry[name]
    while preset and not seen[preset.name] do
        seen[preset.name] = true
        chain[#chain + 1] = preset.name
        preset = preset.extends and registry[preset.extends]
    end
    return chain
end

-- The module a preset may speak for: there, on this client, and not a tool that is always on.
local function presetModule(moduleName)
    local module = ns.modules and ns.modules[moduleName]
    if not module or module.alwaysOn or module.unavailable then
        return nil
    end
    return module
end

-- Whether `key` is one a preset may set: a setting with a default that isn't data, and not one of
-- Blizzard's settings. Found once per module and key, since options don't change after load.
local settableKeys = setmetatable({}, { __mode = "k" }) -- module -> key -> boolean
local function settable(module, key)
    local known = settableKeys[module]
    if known and known[key] ~= nil then
        return known[key]
    end
    local default = module.defaults and module.defaults[key]
    local fine = default ~= nil and type(default) ~= "table"
    for _, option in ipairs(fine and module.options or {}) do
        if option.key == key then
            fine = not option.cvar
        end
    end
    known = known or {}
    settableKeys[module] = known
    known[key] = fine
    return fine
end

---Whether a preset turns a module on (true) or off (false), or nil when it says nothing about it
---(nor does any preset it extends). Nil for a locked module, which no preset turns on, and for a
---module that is always on or that this client doesn't get.
---@param name string
---@param moduleName string
---@return boolean?
function Presets.Enabled(name, moduleName)
    local module = presetModule(moduleName)
    if not module or module.locked then
        return nil
    end
    local own = module.presets
    if type(own) ~= "table" then
        return nil
    end
    -- Along the chain without making a table: module.db reads through here. A chain is at most
    -- as long as the list, which stops a registry changed by hand from looping.
    local preset, steps = Presets.Exists(name) and registry[name], #order
    while preset and steps > 0 do
        local part = own[preset.name]
        if type(part) == "table" and type(part.enabled) == "boolean" then
            return part.enabled
        end
        preset, steps = preset.extends and registry[preset.extends], steps - 1
    end
    return nil
end

---What a preset says for one of a module's settings, or nil when it says nothing (nor does any
---preset it extends). `enabled` is the module's on and off, as Presets.Enabled. Nil for data and
---for an option that is one of Blizzard's settings.
---@param name string
---@param moduleName string
---@param key string
---@return any
function Presets.Value(name, moduleName, key)
    if key == "enabled" then
        return Presets.Enabled(name, moduleName)
    end
    local module = presetModule(moduleName)
    local own = module and module.presets
    if type(own) ~= "table" then
        return nil
    end
    local preset, steps = Presets.Exists(name) and registry[name], #order
    while preset and steps > 0 do
        local part = own[preset.name]
        local options = type(part) == "table" and part.options
        local value
        if type(options) == "table" then
            value = options[key]
        end
        if value ~= nil then
            if type(value) == "table" or not settable(module, key) then
                return nil
            end
            return value
        end
        preset, steps = preset.extends and registry[preset.extends], steps - 1
    end
    return nil
end

---Everything a preset says, along its chain and resolved as Presets.Value reads it:
---{ [module] = { enabled = true, [key] = value } }.
---@param name string
---@return table<string, table<string, any>>
function Presets.Resolve(name)
    local out = {}
    if not Presets.Exists(name) then
        return out
    end
    local chain = Presets.Chain(name)
    for _, moduleName in ipairs(ns.order or {}) do
        local module = ns.modules[moduleName]
        local own = type(module.presets) == "table" and module.presets
        if own then
            local keys = { enabled = true }
            for _, level in ipairs(chain) do
                local part = own[level]
                for key in pairs(type(part) == "table" and type(part.options) == "table" and part.options or {}) do
                    keys[key] = true
                end
            end
            for key in pairs(keys) do
                local value = Presets.Value(name, moduleName, key)
                if value ~= nil then
                    out[moduleName] = out[moduleName] or {}
                    out[moduleName][key] = value
                end
            end
        end
    end
    return out
end

---A preset as ns.ApplyPreset takes it: the modules it turns on, in load order, and per module the
---option values it sets.
---@param name string
---@return string[] enables
---@return table<string, table<string, any>> options
function Presets.Flat(name)
    local resolved = Presets.Resolve(name)
    local enables, options = {}, {}
    for _, moduleName in ipairs(ns.order or {}) do
        local values = resolved[moduleName]
        if values then
            if values.enabled == true then
                enables[#enables + 1] = moduleName
            end
            for key, value in pairs(values) do
                if key ~= "enabled" then
                    options[moduleName] = options[moduleName] or {}
                    options[moduleName][key] = value
                end
            end
        end
    end
    return enables, options
end

-- Popups ----------------------------------------------------------------------------------------
-- The Defaults and New Profile popups offer a button per preset while they fit. With more presets
-- than the popup has room for, one button opens a menu of them instead.

-- Shows the menu of every preset at the cursor. Probe: MenuUtil is Mainline's.
local function showMenu(onPick)
    local menu = MenuUtil
    if not (menu and menu.CreateContextMenu) then
        return
    end
    menu.CreateContextMenu(nil, function(_, root)
        for _, name in ipairs(order) do
            local button = root:CreateButton(registry[name].title, function()
                onPick(name)
            end)
            local description = registry[name].description
            if description and button and button.SetTooltip then
                button:SetTooltip(function(tooltip)
                    tooltip:SetText(registry[name].title)
                    tooltip:AddLine(description, 1, 1, 1, true)
                end)
            end
        end
    end)
end

---The popup buttons for the presets: { text, fn } for each, in order, while there are at most
---`room` of them; past that, one button that opens a menu of them all. `onPick(name)` runs for
---the one picked.
---@param room integer how many buttons the popup has left for presets
---@param onPick fun(name: string)
---@return { text: string, fn: function }[]
function Presets.Buttons(room, onPick)
    local buttons = {}
    if #order <= room then
        for i, name in ipairs(order) do
            buttons[i] = { text = registry[name].title, fn = function() onPick(name) end }
        end
    elseif room > 0 then
        buttons[1] = { text = L.PRESETS_MORE, fn = function() showMenu(onPick) end }
    end
    return buttons
end

---The presets as one phrase for a sentence that offers them: the title when there is one,
---"a preset" when there are more.
---@return string
function Presets.Mention()
    if #order == 1 then
        return registry[order[1]].title
    end
    return L.PRESETS_A_PRESET
end

-- The presets this version has. Others go after it: one may extend one registered before it.
Presets.Register("developer", { title = L.DEFAULTS_DEVELOPER, description = L.PRESETS_DEVELOPER_DESC })
