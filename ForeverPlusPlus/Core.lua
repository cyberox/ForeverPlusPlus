-- Forever++ core: the shared namespace, events, saved settings, and modules. /fpp and the presets
-- are in Commands.lua.
-- Every other file gets the same `ns` table through `...`.
local addonName, ns = ...

local pairs, ipairs, next, type, print, format = pairs, ipairs, next, type, print, string.format
local tonumber, floor, min, max = tonumber, math.floor, math.min, math.max
local concat, setmetatable = table.concat, setmetatable
local InCombatLockdown, GetLocale, hooksecurefunc, _G = InCombatLockdown, GetLocale, hooksecurefunc, _G

-- Calls a function so that an error in it is reported but doesn't stop the caller, so one broken
-- handler can't stop the others. Probe: securecallfunction is Mainline's; without it, call plainly.
local call = securecallfunction or function(fn, ...)
    return fn(...)
end
ns.Call = call -- for the Lib files that run other files' callbacks

ns.name = addonName
ns.title = "Forever++"
ns.icon = "Interface\\AddOns\\" .. addonName .. "\\Media\\Icon" -- also the TOC's IconTexture
ns.modules = {} -- name -> module, in ns.order
ns.order = {}

---Prints a line in chat with no name in front, for the lines that follow an ns.Print. It gets
---the chat timestamp while the player has timestamps on, as Blizzard's own lines do (print()
---adds none).
---@param text string
function ns.PrintLine(text)
    print((ns.Chat and ns.Chat.Stamp() or "") .. text)
end

---Prints a line in chat with the addon's name in front.
---@param message string
function ns.Print(message)
    ns.PrintLine(format("|cff33d0ffForever++|r %s", message))
end

---"On" in green or "Off" in red, for a module's state.
---@param on boolean
---@return string
function ns.StateText(on)
    return on and format("|cff44dd44%s|r", ns.L.ON) or format("|cffdd4444%s|r", ns.L.OFF)
end

-- Locale --------------------------------------------------------------------------------------
-- ns.L.KEY is player-facing text in the client's language. Every key is in Locales/enUS/;
-- another locale's file sets only what it translates, and the rest falls back to enUS.

local enUS = {}
local L = setmetatable({}, {
    __index = function(_, key)
        return enUS[key] or key -- a missing key shows as itself instead of erroring
    end,
})
ns.L = L

---Returns the table a locale file fills with its strings, or nil when the client uses another
---language (the file then stops). enUS is always filled, since it's the fallback.
---@param locale string a GetLocale() code, such as "enUS" or "deDE"
---@return table|nil
function ns.NewLocale(locale)
    if locale == "enUS" then
        return enUS
    elseif locale == GetLocale() then
        return L
    end
end

-- Events --------------------------------------------------------------------------------------
-- One frame for the whole addon. Handlers get (event, ...).

local events = CreateFrame("Frame")
local handlers = {} -- event -> list of functions
-- Handler -> the module that added it with module:On, for the Profiler page (Lib/Profiler.lua).
local owners = setmetatable({}, { __mode = "k" })

-- Calls each handler in `list`, timed for the Profiler page while it records.
local function dispatch(list, event, ...)
    local profiler = ns.Profiler
    if profiler and profiler.recording then
        for i = 1, #list do
            local fn = list[i]
            profiler.CallFrom(owners[fn], event, call, fn, event, ...)
        end
        return
    end
    for i = 1, #list do
        call(list[i], event, ...)
    end
end

events:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if list then
        dispatch(list, event, ...)
    end
end)

---Calls `fn(event, ...)` whenever `event` fires. Adding the same `fn` twice changes nothing.
---@param event string
---@param fn fun(event: string, ...)
function ns.On(event, fn)
    local list = handlers[event]
    if not list then
        -- Register first: an event this client lacks throws here, and must leave nothing behind
        -- for Off to unregister.
        events:RegisterEvent(event)
        list = {}
        handlers[event] = list
    end
    for i = 1, #list do
        if list[i] == fn then
            return
        end
    end
    list[#list + 1] = fn
end

---Whether this client has `event`. Registering one it doesn't have is an error, and Forever is a
---beta, so check an event a patch may add or drop before `ns.On` or `module:On`. Probe: without
---C_EventUtils.IsEventValid, every event counts as there.
---@param event string
---@return boolean
function ns.HasEvent(event)
    local utils = C_EventUtils
    return not (utils and utils.IsEventValid) or utils.IsEventValid(event) and true or false
end

---Stops calling `fn` for `event`.
---@param event string
---@param fn function
function ns.Off(event, fn)
    local old = handlers[event]
    if not old then
        return
    end
    -- Build a new list instead of removing in place: a handler may call this while OnEvent is
    -- still looping over the old one, and shifting it would skip or call a missing entry.
    local list = {}
    for i = 1, #old do
        if old[i] ~= fn then
            list[#list + 1] = old[i]
        end
    end
    handlers[event] = list
    if #list == 0 then
        handlers[event] = nil
        events:UnregisterEvent(event)
    end
end

-- Unit events ---------------------------------------------------------------------------------
-- A UNIT_* event fires for every unit: each nameplate, party member and target. RegisterUnitEvent
-- has the client drop the ones for other units before any Lua runs, so a handler for the player's
-- auras costs nothing while a crowd's auras change. A frame keeps one unit filter per event, so
-- each event and unit list gets a frame of its own, made on first use and kept for reuse (frames
-- can't be freed).

local unitEvents = {} -- "EVENT|unit|unit" -> { frame, list, units, on }

-- Unit tokens in a payload aren't known to be secret, but a secret can't be compared.
local issecret = issecretvalue or function()
    return false
end

---Like ns.On, for a UNIT_* event of one or two units only: `ns.OnUnit("UNIT_AURA", { "player" },
---fn)`. Handlers get (event, unit, ...) as with ns.On. UNVERIFIED on Forever: without
---RegisterUnitEvent the frame hears every unit and other units are filtered out here instead.
---@param event string
---@param units string[] one or two unit tokens
---@param fn fun(event: string, unit: string, ...)
function ns.OnUnit(event, units, fn)
    if #units < 1 or #units > 2 then
        error("Forever++: OnUnit takes one or two units", 2)
    end
    local key = event .. "|" .. concat(units, "|")
    local entry = unitEvents[key]
    if not entry then
        local frame = CreateFrame("Frame")
        entry = { frame = frame, list = {}, units = {} }
        for _, unit in ipairs(units) do
            entry.units[unit] = true
        end
        local filtered = frame.RegisterUnitEvent and true or false
        frame:SetScript("OnEvent", function(_, name, unit, ...)
            if not filtered and (issecret(unit) or not entry.units[unit]) then
                return
            end
            dispatch(entry.list, name, unit, ...)
        end)
        unitEvents[key] = entry
    end
    for i = 1, #entry.list do
        if entry.list[i] == fn then
            return
        end
    end
    if not entry.on then
        -- Register first, as ns.On does: an event this client lacks throws here.
        if entry.frame.RegisterUnitEvent then
            entry.frame:RegisterUnitEvent(event, units[1], units[2])
        else
            entry.frame:RegisterEvent(event)
        end
        entry.on = true
    end
    entry.list[#entry.list + 1] = fn
end

---Stops calling `fn` for `event` of `units` (the same list given to ns.OnUnit).
---@param event string
---@param units string[]
---@param fn function
function ns.OffUnit(event, units, fn)
    local entry = unitEvents[event .. "|" .. concat(units, "|")]
    if not entry then
        return
    end
    -- A new list, as in ns.Off: a handler may call this while OnEvent loops over the old one.
    local list = {}
    for i = 1, #entry.list do
        if entry.list[i] ~= fn then
            list[#list + 1] = entry.list[i]
        end
    end
    entry.list = list
    if #list == 0 and entry.on then
        entry.on = false
        entry.frame:UnregisterEvent(event)
    end
end

-- Combat --------------------------------------------------------------------------------------
-- Protected frames and many CVars can't change in combat; changes made then wait for it to end.

local afterCombat = {} -- functions waiting, in order

local function runAfterCombat()
    ns.Off("PLAYER_REGEN_ENABLED", runAfterCombat)
    local waiting = afterCombat
    afterCombat = {}
    for i = 1, #waiting do
        call(waiting[i])
    end
end

---Calls `fn` now, or once combat ends if the player is in combat. Calls run in the order made.
---@param fn function
function ns.AfterCombat(fn)
    if not InCombatLockdown() then
        fn()
        return
    end
    if #afterCombat == 0 then
        ns.On("PLAYER_REGEN_ENABLED", runAfterCombat)
    end
    afterCombat[#afterCombat + 1] = fn
end

-- Saved settings ------------------------------------------------------------------------------
-- Lib/Store.lua lays out ForeverPlusPlusDB and ForeverPlusPlusCharDB: each module's settings
-- (only what the player changed) apart from what it collects, and a version so the steps that
-- bring an older layout up to date each run once. `module.db` reads and writes both.

---What control an option is: "dropdown" (it has `choices`), "slider" (`min`), or "checkbox".
---Settings, `/fpp set`, the public API, and the saved-value checks all go by this.
---@param option table
---@return string
function ns.OptionKind(option)
    if option.choices then
        return "dropdown"
    elseif option.min then
        return "slider"
    end
    return "checkbox"
end

---A slider option's value brought into its range and onto its steps, or nil when it isn't a
---number.
---@param option table an option with `min`, `max` and `step`
---@param value any
---@return number?
function ns.SliderValue(option, value)
    value = tonumber(value)
    if not value then
        return nil
    end
    local step = option.step or 1
    value = option.min + floor((value - option.min) / step + 0.5) * step
    return max(option.min, min(option.max, value))
end

-- Resets dropdown settings whose saved value is no longer one of the choices, and brings slider
-- settings back into their range.
local function checkValues(module)
    for _, option in pairs(module.options or {}) do
        local value = module.db[option.key]
        local kind = ns.OptionKind(option)
        if kind == "dropdown" then
            local valid = false
            for _, choice in pairs(option.choices) do
                valid = valid or choice[1] == value
            end
            if not valid then
                module.db[option.key] = nil -- back to the default: the choice is gone
            end
        elseif kind == "slider" then
            -- Only a saved value out of range changes; writing every slider would save its
            -- default as if the player chose it.
            local fixed = ns.SliderValue(option, value)
            if fixed == nil then
                module.db[option.key] = nil
            elseif fixed ~= value then
                module.db[option.key] = fixed
            end
        end
    end
end

-- Moving settings -----------------------------------------------------------------------------
-- When a release renames, merges, or moves a module, setting, or data between modules, a step
-- moves what the player saved to where it now goes, once, at the first login with that release,
-- before settings and data no module has are cleared.

---Adds a step that moves saved settings from where an older version kept them, run once when the
---saved layout is older than `version`. Give a new step the next version (Store.VERSION + 1, and
---raise Store.VERSION to it). Version 1 steps work on the 0.8 layout, `db.modules`; later ones on
---`db.settings[module]` and `db.data[module]` (see Lib/Store.lua).
---@param version integer
---@param fn fun(db: table) ForeverPlusPlusDB
function ns.Migrate(version, fn)
    ns.Store.Step(version, fn)
end

---Like ns.Migrate, for a character's own saved variables: `fn(char, db)` runs once per character.
---@param version integer
---@param fn fun(char: table, db: table) ForeverPlusPlusCharDB, ForeverPlusPlusDB
function ns.MigrateCharacter(version, fn)
    ns.Store.CharacterStep(version, fn)
end

---Copies saved values from `from` to `to`. `keys` lists them: a plain entry keeps its name, and
---`new = "old"` renames one. Values `from` doesn't have leave `to` as it is.
---@param from table
---@param to table
---@param keys table
function ns.MoveSettings(from, to, keys)
    for new, old in pairs(keys) do
        if type(new) == "number" then
            new = old
        end
        if from[old] ~= nil then
            to[new] = from[old]
        end
    end
end

-- Modules -------------------------------------------------------------------------------------

-- Methods every module has.
local Module = {}
Module.__index = Module

---Like ns.On, but the module remembers it and turns it off by itself when the module turns off.
---Use it for events the module listens to while it's on.
---@param event string
---@param fn fun(event: string, ...)
function Module:On(event, fn)
    self.events = self.events or {}
    for _, entry in ipairs(self.events) do
        if entry[1] == event and entry[2] == fn then
            return -- already listening; a module that syncs its events often mustn't pile them up
        end
    end
    ns.On(event, fn) -- before recording it, so an event this client lacks isn't turned off later
    self.events[#self.events + 1] = { event, fn }
    owners[fn] = owners[fn] or self
end

---Like ns.OnUnit, turned off by itself when the module turns off (see `module:On`).
---@param event string
---@param units string[] one or two unit tokens
---@param fn fun(event: string, unit: string, ...)
function Module:OnUnit(event, units, fn)
    self.events = self.events or {}
    local key = concat(units, "|")
    for _, entry in ipairs(self.events) do
        if entry[1] == event and entry[2] == fn and entry[3] == key then
            return
        end
    end
    ns.OnUnit(event, units, fn)
    self.events[#self.events + 1] = { event, fn, key, units }
    owners[fn] = owners[fn] or self
end

-- Stops one entry of `module.events`, whichever kind it is.
local function stop(entry)
    if entry[4] then
        ns.OffUnit(entry[1], entry[4], entry[2])
    else
        ns.Off(entry[1], entry[2])
    end
end

---Stops one event added with `module:On` or `module:OnUnit` before the module turns off.
---@param event string
---@param fn function
function Module:Off(event, fn)
    local list = {}
    for _, entry in ipairs(self.events or {}) do
        if entry[1] == event and entry[2] == fn then
            stop(entry)
        else
            list[#list + 1] = entry
        end
    end
    self.events = list
end

---Listens to `events` ({ EVENT = fn }) only while `when` holds: the name of an option that is on
---(any value but false, nil or "off"), or `when(db)` for anything else. Core checks it when the
---module (or part) turns on and after every option change, so neither OnEnable nor OnOptionChanged
---needs to. Call it once, at file load, next to the handlers. Events this client doesn't have are
---skipped. A handler given here mustn't also be added with `module:On`.
---@param when string|fun(db: table): any
---@param events table<string, function>
function Module:OnWhile(when, events)
    self.whiles = self.whiles or {}
    self.whiles[#self.whiles + 1] = { when = when, events = events }
end

-- Whether an option counts as on: any value but nil, false, or a dropdown's "off".
local function optionOn(module, key)
    local value = module.db[key]
    return value ~= nil and value ~= false and value ~= "off"
end

---Whether a part's toggle is on: a checkbox that is checked, or a dropdown (a toggle with
---`choices`) set to anything but "off".
---@param module table the module the part belongs to
---@param key string the part's toggle key
---@return boolean
function ns.PartOn(module, key)
    return optionOn(module, key)
end

local function holds(module, when)
    if type(when) == "function" then
        return when(module.db) and true or false
    end
    return optionOn(module, when)
end

-- Listens to the events of each `module:OnWhile` that holds, and stops the rest.
local function syncWhiles(module)
    for _, entry in ipairs(module.whiles or {}) do
        local on = module.enabled and holds(module, entry.when)
        for event, fn in pairs(entry.events) do
            if on and ns.HasEvent(event) then
                module:On(event, fn)
            else
                module:Off(event, fn)
            end
        end
    end
end

-- Hooks once per module, target, method and function, so `OnEnable` can ask for them every time
-- it runs. The hook itself can't come off, so it does nothing while the module is off.
local function child(t, key)
    local value = t[key]
    if not value then
        value = {}
        t[key] = value
    end
    return value
end

-- What module:TooltipLinePreCall hooks are kept under, apart from the post calls, since a line
-- type and a tooltip type can share a number.
local LINE_PRE_CALLS = {}

-- What a hook is on, as the Profiler page names it: "GameTooltip:Show", "UnitFrame_Update", or
-- "PlayerFrame OnEnter" for a script. Made once, when it's hooked.
local function hookName(target, method)
    local script = type(method) == "string" and method:match("^script:(.+)$")
    if target == _G then
        return method
    end
    -- module:TooltipLinePreCall: the kind of line, by its Enum.TooltipDataLineType name.
    if target == LINE_PRE_CALLS then
        for name, value in pairs(Enum and Enum.TooltipDataLineType or {}) do
            if value == method then
                return "TooltipLinePreCall " .. name
            end
        end
        return "TooltipLinePreCall " .. tostring(method)
    end
    -- module:TooltipPostCall: the kind of tooltip, by its Enum.TooltipDataType name.
    if target == TooltipDataProcessor then
        for name, value in pairs(Enum and Enum.TooltipDataType or {}) do
            if value == method then
                return "TooltipPostCall " .. name
            end
        end
        return "TooltipPostCall " .. tostring(method)
    end
    -- A frame without a name of its own (an aura button) goes by its nearest named parent's, as
    -- "UpdateDuration in BuffFrame"; a table that isn't a frame by the method alone.
    local function nameOf(object)
        local name = type(object.GetName) == "function" and object:GetName()
        return type(name) == "string" and name ~= "" and name or nil
    end
    local name = type(target) == "table" and nameOf(target)
    local label = script or tostring(method)
    if name then
        return script and (name .. " " .. label) or (name .. ":" .. label)
    end
    local parent = type(target) == "table" and type(target.GetParent) == "function" and target:GetParent()
    for _ = 1, 5 do
        if type(parent) ~= "table" then
            break
        end
        local parentName = nameOf(parent)
        if parentName then
            return label .. " in " .. parentName
        end
        parent = type(parent.GetParent) == "function" and parent:GetParent()
    end
    return label
end

local function hookOnce(module, target, method, fn, install)
    local byFn = child(child(child(module, "hooked"), target), method)
    if not byFn[fn] then
        byFn[fn] = true
        local source = hookName(target, method)
        install(function(...)
            if module.enabled then
                -- Through `call`, as events are: an error in our hook is reported, and doesn't
                -- surface inside Blizzard's own code or stop the hooks after ours. What `fn`
                -- returns is passed on, for a line pre call (true leaves the line out).
                local profiler = ns.Profiler
                if profiler and profiler.recording then
                    return profiler.CallFrom(module, source, call, fn, ...)
                end
                return call(fn, ...)
            end
        end)
    end
end

---Calls `fn` after a function or method of a Blizzard object runs (`hooksecurefunc`), but only
---while the module is on, and hooks it just once however often this is called. Use it in
---`OnEnable` instead of a `hooked` flag: `module:Hook("ToggleSheath", fn)` for a global function,
---or `module:Hook(object, "Method", fn)`. `fn` gets the same arguments the hooked function did.
---Does nothing when the object or function isn't on this client, so callers needn't probe first.
---@param target table|string|nil an object, or the name of a global function
---@param method string|function the method's name, or `fn` when `target` is a global's name
---@param fn? function
function Module:Hook(target, method, fn)
    if type(target) == "string" then
        target, method, fn = _G, target, method
    end
    if type(target) ~= "table" or type(target[method]) ~= "function" then
        return
    end
    hookOnce(self, target, method, fn, function(hook)
        hooksecurefunc(target, method, hook)
    end)
end

---Like `module:Hook`, for a frame's script: `frame:HookScript(script, fn)` that runs only while
---the module is on, hooked once. Does nothing when the frame isn't there.
---@param frame table?
---@param script string such as "OnEvent"
---@param fn function
function Module:HookScript(frame, script, fn)
    if not frame then
        return
    end
    hookOnce(self, frame, "script:" .. script, fn, function(hook)
        frame:HookScript(script, hook)
    end)
end

---Like `module:Hook`, for every tooltip of one kind (`TooltipDataProcessor.AddTooltipPostCall`):
---`fn(tooltip, data)` runs after the game fills one in, while the module is on. Does nothing on a
---client without TooltipDataProcessor.
---@param kind any such as Enum.TooltipDataType.Item, or TooltipDataProcessor.AllTypes
---@param fn function
function Module:TooltipPostCall(kind, fn)
    if not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and kind) then
        return
    end
    hookOnce(self, TooltipDataProcessor, kind, fn, function(hook)
        TooltipDataProcessor.AddTooltipPostCall(kind, hook)
    end)
end

---Like `module:TooltipPostCall`, before the game adds each tooltip line of one kind
---(`TooltipDataProcessor.AddLinePreCall`): `fn(tooltip, lineData)` runs while the module is on,
---and a true return leaves the line out. It runs before every such line of every tooltip, so keep
---it cheap, and check an option in `fn`. Does nothing on a client without line pre calls.
---@param kind any such as Enum.TooltipDataLineType.QuestTitle, or TooltipDataProcessor.AllTypes
---@param fn function
function Module:TooltipLinePreCall(kind, fn)
    if not (TooltipDataProcessor and TooltipDataProcessor.AddLinePreCall and kind) then
        return
    end
    hookOnce(self, LINE_PRE_CALLS, kind, fn, function(hook)
        TooltipDataProcessor.AddLinePreCall(kind, hook)
    end)
end

---Prints a line in chat that the module shows by itself (not in reply to a command), unless the
---player turned its chat messages off. A module that prints these puts `chat = true` in its
---defaults and `ns.ChatOption(...)` in its options.
---@param message string
function Module:Print(message)
    if self.db.chat ~= false then
        ns.Print(message)
    end
end

---The "Chat Messages" checkbox for a module that uses `module:Print`.
---@param description string what the module says in chat
---@param section? string its Settings header, on a page with sections
---@return table option for `module.options`
function ns.ChatOption(description, section)
    return { key = "chat", name = ns.L.CHAT_MESSAGES, description = description, section = section }
end

-- Stops every event the module added with `module:On` or `module:OnUnit`.
local function offAll(module)
    for _, entry in ipairs(module.events or {}) do
        stop(entry)
    end
    module.events = nil
end

---Creates a module: one change to the game's UI, switched on and off on its own. Give it
---`OnEnable` and an `OnDisable` that undoes it, and put its settings in `defaults`. Events
---added with `module:On` and hooks added with `module:Hook` stop by themselves when it turns
---off, and so do timers from `Frames.Timer(module)` and `Frames.Coalesce(fn, delay, module)`, so
---a module that only does those needs no `OnDisable`; anything else `OnEnable` changes (a frame,
---a CVar) `OnDisable` must put back. Set
---`module.title` for a friendlier name in Settings (the name stays the /fpp key), and
---`module.category` for its group on the Modules page (see Settings/Settings.lua). A tool with
---nothing to turn off sets `module.alwaysOn`: it has no toggle and stays on. A module only for
---some clients gives `module:IsAvailable()`; when it returns false at login, the module stays off
---and out of Settings and /fpp list. A default that is a table is data the module collects, not a
---setting; one kept for each character on its own goes in `module.perCharacter` ({ [key] = true }),
---and one that belongs to the profile, like a setting (window positions), in `module.perProfile`.
---@param name string shown in /fpp
---@param description string one line for /fpp
---@param defaults? table its settings and data; `enabled` defaults to true
---@return table module with .db (its saved settings) once the addon has loaded
function ns.NewModule(name, description, defaults)
    if ns.modules[name] then
        error("Forever++: a module called " .. name .. " already exists", 2)
    end
    local module = setmetatable({ name = name, description = description,
        defaults = defaults or {} }, Module)
    if module.defaults.enabled == nil then
        module.defaults.enabled = true
    end
    ns.modules[name] = module
    ns.order[#ns.order + 1] = name
    return module
end

-- Parts -----------------------------------------------------------------------------------------
-- A module can be made of parts that the player turns on and off one by one inside it, like the
-- World Map module's layers. Each part is written like a module of its own, in its own file.

---Adds a part to a module: a piece of it with its own checkbox, the option `toggle.key`, that heads
---its section in Settings. A toggle with `choices` is a dropdown instead: the part is on while it's
---set to anything but "off" (see ns.PartOn), and hears in its `OnOptionChanged` when it moves
---between the other choices. A part is written like a module: `OnEnable`, an `OnDisable` that
---undoes it, `OnOptionChanged`, `part:On`, `part:OnWhile`, `part:Hook`, `part:Print` and timers
---given the part all work the same, and it is on while both the module and its checkbox are. Its
---settings go in `defaults` and its options in `part:AddOptions`; both join the module's, so their
---keys must differ from the other parts'. Its `db` is the module's.
---@param toggle table the checkbox option: `key`, `name`, `description`, and `section`, the header its options go under, and `choices` for a dropdown
---@param defaults? table its settings; a checkbox defaults to on, a dropdown's default goes here
---@return table part
function Module:NewPart(toggle, defaults)
    local part = setmetatable({ name = self.name, module = self, key = toggle.key,
        section = toggle.section, own = {}, dropdown = toggle.choices ~= nil }, Module)
    toggle.toggle = true
    defaults = defaults or {}
    if defaults[toggle.key] == nil and not toggle.choices then
        defaults[toggle.key] = true
    end
    for key, value in pairs(defaults) do
        if self.defaults[key] ~= nil then
            error("Forever++: " .. self.name .. " already has a setting called " .. key, 2)
        end
        self.defaults[key] = value
    end
    self.parts = self.parts or {}
    self.parts[#self.parts + 1] = part
    self.options = self.options or {}
    self.options[#self.options + 1] = toggle
    return part
end

---Adds a part's options to its module's, under the part's section and greyed out in Settings while
---its checkbox is off. An option's own `section` becomes a smaller header inside the part's. The
---part hears about them in its `OnOptionChanged`.
---@param options table[] options, as in `module.options`
function Module:AddOptions(options)
    local module = self.module
    for _, option in ipairs(options) do
        option.subsection = option.section
        option.section = self.section
        option.part = self.key
        self.own[option.key] = true
        module.options[#module.options + 1] = option
    end
end

local function enable(module)
    if module.enabled then
        return
    end
    module.enabled = true
    if module.OnEnable then
        call(module.OnEnable, module) -- an error here must not stop the modules after it
    end
    syncWhiles(module)
    for _, part in ipairs(module.parts or {}) do
        if ns.PartOn(module, part.key) then
            enable(part)
        end
    end
end

-- Cancels the module's timers (Frames.Timer and Frames.Coalesce given the module), so none runs
-- after it turned off.
local function cancelTimers(module)
    for _, timer in ipairs(module.timers or {}) do
        timer:Cancel()
    end
end

local function disable(module)
    if not module.enabled then
        return
    end
    for _, part in ipairs(module.parts or {}) do
        disable(part)
    end
    module.enabled = false
    if module.OnDisable then
        call(module.OnDisable, module)
    end
    cancelTimers(module) -- after OnDisable, which may have used one
    offAll(module)
end

local changeListeners = {} -- fn(name, key) for each module turned on or off, or option changed
local started = false -- ns.Start has run: modules turning on at login aren't changes
-- A `cvar` option set in combat waits for it to end to change the CVar (ns.CVars.Apply). Until
-- then it reads what the player chose, and the module hears about it once the CVar has changed:
-- module name -> option key -> true or false.
local pendingCVars = {}

---Calls `fn(name, key)` after the player turns a module on or off (`key` nil) or changes one of
---its options (`key` the option's), from Settings, a command, or a preset; not for the modules
---that turn on at login.
---@param fn fun(name: string, key: string?)
function ns.OnModuleChanged(fn)
    changeListeners[#changeListeners + 1] = fn
end

local function moduleChanged(name, key)
    if not started then
        return
    end
    for _, fn in ipairs(changeListeners) do
        call(fn, name, key)
    end
end

-- Tells a module one of its options changed. A module and a part hear about their options only
-- while they're on (OnEnable reads them anyway), and a part's checkbox turns it on or off. A part
-- that stays on while its dropdown moves between choices hears about that too.
local function optionChanged(module, key)
    local waiting = pendingCVars[module.name]
    if waiting and waiting[key] ~= nil then
        return -- told once the CVar changes, after combat
    end
    if module.enabled and module.OnOptionChanged then
        call(module.OnOptionChanged, module, key) -- as a part's: one error mustn't stop a preset
    end
    syncWhiles(module)
    for _, part in ipairs(module.parts or {}) do
        if key == part.key then
            if not (module.enabled and ns.PartOn(module, key)) then
                disable(part)
            elseif not part.enabled then
                enable(part)
            elseif part.dropdown and part.OnOptionChanged then
                call(part.OnOptionChanged, part, key)
            end
        elseif part.own[key] and part.enabled and part.OnOptionChanged then
            call(part.OnOptionChanged, part, key)
        end
        syncWhiles(part) -- a part's OnWhile may name any of the module's options
    end
    moduleChanged(module.name, key)
end

---Tells a module one of its options changed, once its value is already saved (the presets set
---every value first, then tell each module).
---@param module table
---@param key string
ns.OptionChanged = optionChanged

local welcomed = {} -- functions to call when the welcome is seen, or reset to show again

---True from a fresh install until the player first sees the About page.
---@return boolean
function ns.WelcomePending()
    return ns.db and ns.db.welcome == true or false
end

---Calls fn once the player has seen the About page after a fresh install, and again whenever the
---welcome is reset (the Debug module's Reset Welcome), so it can show and hide what offers it.
---@param fn function
function ns.OnWelcomed(fn)
    welcomed[#welcomed + 1] = fn
end

---Marks the About page seen (false, from Settings/About.lua when it's first shown), or offers it
---again as on a fresh install, keeping every setting (true, from the Debug module's Reset Welcome).
---@param pending boolean
function ns.SetWelcome(pending)
    if ns.WelcomePending() == pending then
        return
    end
    ns.db.welcome = pending or nil
    for _, fn in ipairs(welcomed) do
        call(fn)
    end
end

---A field from the TOC, such as "Notes", or "" when it has none.
---@param field string
---@return string
function ns.Metadata(field)
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    return get and get(addonName, field) or ""
end

---The modules the player has on, by their internal names (what the code and issues call them),
---leaving out tools that are always on.
---@return string[]
function ns.ModulesOn()
    local names = {}
    for _, name in ipairs(ns.order) do
        local module = ns.modules[name]
        if module.enabled and not module.alwaysOn then
            names[#names + 1] = name
        end
    end
    return names
end

-- Modules renamed in layout version 3 so their names match their titles: old -> new.
local RENAMED = {
    GatherTracking = "GatheringTracking",
    CharacterFrame = "CharacterWindow",
    ChannelNames = "ShortChannelNames",
    ChatFading = "PersistentChat",
    BagSlots = "BagSlotCounter",
    UnusableItems = "UnusableItemsTint",
    BestReward = "BestQuestReward",
    QuestIcons = "ForeverQuestIcons",
    QuestPlates = "QuestNameplates",
    AddOnList = "AddOnsList",
    Framerate = "MovableFramerate",
    HideFeedback = "HideBetaFeedback",
    CVarBrowser = "ConsoleVariables",
    NpcPlates = "NpcNameplates",
    PlayerPlates = "PlayerNameplates",
}

-- The core's own steps. Version 2 splits the 0.8 layout into settings, data, and per-character
-- data each character takes when it logs in; version 3 renames modules to match their titles.
local function addCoreSteps()
    local Store = ns.Store
    Store.Step(2, function(db)
        local perCharacter = {}
        for name, module in pairs(ns.modules) do
            perCharacter[name] = module.perCharacter
        end
        -- Version 1 still had the old names.
        for old, new in pairs(RENAMED) do
            perCharacter[old] = perCharacter[new]
        end
        Store.Split(db, perCharacter)
    end)
    Store.Step(3, function(db)
        Store.Rename(db, RENAMED)
    end)
end

-- Checkbox options with `cvar` are one of Blizzard's own settings shown among the module's: they
-- read and set the CVar, not saved settings, and their default is the client's. Store.Load links
-- them. Not on a client without the CVar, where the option reads its declared default.
-- In combat the choice waits in pendingCVars; once the CVar is set after it, the module and the
-- page hear about it, if it now reads differently from before the click or from the choice (the
-- client refused it).
local function cvarOptions(module)
    local linked
    local C_CVar = _G.C_CVar
    for _, option in ipairs(module.options or {}) do
        local name, key = option.cvar, option.key
        if name and C_CVar and C_CVar.GetCVar(name) ~= nil then
            local default = C_CVar.GetCVarDefault and C_CVar.GetCVarDefault(name)
            if default ~= nil then
                module.defaults[key] = default == "1"
            end
            linked = linked or {}
            linked[key] = {
                get = function()
                    local waiting = pendingCVars[module.name]
                    local value = waiting and waiting[key]
                    if value ~= nil then
                        return value
                    end
                    return ns.CVars.IsOn(name)
                end,
                set = function(value)
                    if value == nil then
                        value = module.defaults[key]
                    end
                    value = value and true or false
                    if not InCombatLockdown() then
                        ns.CVars.Apply(name, value and "1" or "0")
                        return
                    end
                    local waiting = pendingCVars[module.name] or {}
                    pendingCVars[module.name] = waiting
                    local first = waiting[key] == nil
                    waiting[key] = value
                    if not first then
                        return -- the change already waiting takes the latest choice
                    end
                    local was = ns.CVars.IsOn(name)
                    ns.AfterCombat(function()
                        local want = waiting[key]
                        waiting[key] = nil
                        ns.CVars.Apply(name, want and "1" or "0", function()
                            local now = ns.CVars.IsOn(name)
                            if now ~= was or now ~= want then
                                optionChanged(module, key)
                            end
                            ns.RefreshSetting(module.name)
                        end)
                    end)
                end,
            }
        end
    end
    return linked
end

---Loads the saved settings and enables every module that is on (called once, at PLAYER_LOGIN).
function ns.Start()
    local Store = ns.Store
    ForeverPlusPlusDB = type(ForeverPlusPlusDB) == "table" and ForeverPlusPlusDB or {}
    ForeverPlusPlusCharDB = type(ForeverPlusPlusCharDB) == "table" and ForeverPlusPlusCharDB or {}
    ns.db, ns.charDB = ForeverPlusPlusDB, ForeverPlusPlusCharDB
    -- Players seen (Lib/Players.lua) are a variable of their own, so thousands of them stay out of
    -- the settings.
    ForeverPlusPlusPlayersDB = type(ForeverPlusPlusPlayersDB) == "table" and ForeverPlusPlusPlayersDB or {}
    ns.playersDB = ForeverPlusPlusPlayersDB
    addCoreSteps()
    local fresh = Store.Upgrade(ns.db, ns.charDB)
    -- The last version whose Modules page the player has seen all of, and the version each module
    -- clicked since was seen in; Settings/Settings.lua marks what's added or changed after them as
    -- new. A fresh install has nothing to catch up on; saved settings from before this was kept
    -- have seen none of them.
    ns.version = ns.Metadata("Version")
    if type(ns.db.seenVersion) ~= "string" then
        ns.db.seenVersion = fresh and ns.version or "0"
    end
    if type(ns.db.seenModules) ~= "table" then
        ns.db.seenModules = {}
    end
    -- A fresh install has the About page to see, which the Minimap Button offers once.
    if fresh then
        ns.db.welcome = true
    end
    local known = {}
    for _, name in ipairs(ns.order) do
        known[name] = true
    end
    Store.Prune(ns.db, ns.charDB, known)
    ns.GameData.Prune(ns.db)
    ns.Players.Prune(ns.playersDB)
    -- Before the game writes the saved variables, drop what's empty so the file holds only what
    -- was saved. module.db makes it again if a module saves at logout after this.
    ns.On("PLAYER_LOGOUT", function()
        Store.Tidy(ns.db, ns.charDB)
        if next(ns.playersDB) == nil then
            ForeverPlusPlusPlayersDB = nil
        end
    end)
    for _, name in ipairs(ns.order) do
        local module = ns.modules[name]
        module.db = Store.Load(ns.db, ns.charDB, name, module.defaults, module.perCharacter,
            cvarOptions(module), module.perProfile)
        for _, part in ipairs(module.parts or {}) do
            part.db = module.db
        end
        checkValues(module)
        if module.OnLoad then
            call(module.OnLoad, module)
        end
        if module.alwaysOn then
            module.db.enabled = not module.defaults.enabled or nil -- on, without saving the default
        end
        -- A module only for some clients (IsAvailable false) stays off and out of sight.
        module.unavailable = module.IsAvailable and not module:IsAvailable() or nil
        -- A locked module (`module.locked`, one the game broke) stays off, whatever was saved.
        if module.db.enabled and not module.unavailable and not module.locked then
            enable(module)
        end
    end
    started = true
end

---Turns a module on or off and remembers it.
---@param name string
---@param on boolean
function ns.SetEnabled(name, on)
    local module = ns.modules[name]
    if module.alwaysOn or module.unavailable or (module.locked and on) then
        -- a tool that's always there, a module this client doesn't get, or one that's locked off
        return
    end
    local was = module.enabled and true or false
    module.db.enabled = on
    if on then
        enable(module)
    else
        disable(module)
    end
    if was ~= (module.enabled and true or false) then
        moduleChanged(name, nil)
    end
end

---Changes one of a module's options (from `module.options`) and tells the module. The value is
---saved even when it's the default, so it stays the player's choice until they reset it.
---@param name string
---@param key string
---@param value any
function ns.SetOption(name, key, value)
    local module = ns.modules[name]
    module.db[key] = value
    optionChanged(module, key)
end

---Puts one of a module's options back to its default and forgets the choice, so a later release
---changing the default reaches it too (the undo arrow, Debug turning off). Tells the module when
---the value it reads changed.
---@param name string
---@param key string
function ns.ResetOption(name, key)
    local module = ns.modules[name]
    local before = module.db[key]
    module.db[key] = nil
    if module.db[key] ~= before then
        optionChanged(module, key)
    end
end
