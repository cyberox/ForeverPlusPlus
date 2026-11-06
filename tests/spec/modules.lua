-- Modules: every file the TOC loads loads offline, and every module's settings are well formed:
-- each option has a name, a description, and a default that fits it (a dropdown's is one of its
-- choices, a slider's is in its range), and every `requires`, `slider`, and `conflicts` names an
-- option the module has. These are the mistakes that only show in game, as a broken row in
-- Settings or an option that never greys out, often after a rename.
local T = ...
local eq = T.eq

-- A stand-in for every WoW global the code reads that isn't stubbed here: calling it, indexing
-- it, or calling a method on it gives back the stand-in, so a file's top level runs without the
-- client. Only loading is tested this way; nothing here runs a module.
local stub
local meta = {
    __index = function() return stub end,
    __call = function() return stub end,
    __concat = function(a, b)
        return (a == stub and "" or tostring(a)) .. (b == stub and "" or tostring(b))
    end,
    __tostring = function() return "<stub>" end,
}
for _, op in ipairs({ "__add", "__sub", "__mul", "__div", "__mod", "__pow", "__unm" }) do
    meta[op] = function() return 0 end
end
stub = setmetatable({}, meta)

-- Blizzard's colors (NORMAL_FONT_COLOR and the like): a ColorMixin's RGB and its fields.
local function color()
    local c = { r = 1, g = 0.82, b = 0, a = 1 }
    function c.GetRGB() return c.r, c.g, c.b end
    function c.GetRGBA() return c.r, c.g, c.b, c.a end
    function c.GenerateHexColor() return "ffffd100" end
    function c.WrapTextInColorCode(_, s) return s end
    return c
end

local env = {}
local real = _G
setmetatable(env, { __index = function(self, key)
    local value = real[key]
    if value ~= nil then
        return value
    end
    -- Blizzard's colors are ColorMixins, and its other all-caps globals are its strings.
    if type(key) == "string" and key:match("_COLOR$") then
        value = color()
    elseif type(key) == "string" and key:match("^[%u%d_]+$") and key:match("%u") then
        value = key
    else
        return stub
    end
    rawset(self, key, value)
    return value
end })
env._G = env

-- Blizzard's string and table helpers, and the few functions whose answers files branch on.
env.format, env.strlower, env.strupper = string.format, string.lower, string.upper
env.strsub, env.strfind, env.strmatch, env.strlen, env.strrep = string.sub, string.find, string.match,
    string.len, string.rep
env.gsub, env.strbyte, env.strchar = string.gsub, string.byte, string.char
env.tinsert, env.tremove, env.tconcat, env.sort = table.insert, table.remove, table.concat, table.sort
env.floor, env.ceil, env.abs, env.max, env.min, env.mod = math.floor, math.ceil, math.abs, math.max,
    math.min, math.fmod
env.wipe = function(t)
    for key in pairs(t) do
        t[key] = nil
    end
    return t
end
env.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
env.strsplit = function(sep, s)
    local parts = {}
    for piece in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do
        parts[#parts + 1] = piece
    end
    return unpack(parts)
end
env.Mixin = function(object, ...)
    for i = 1, select("#", ...) do
        for key, value in pairs((select(i, ...))) do
            object[key] = value
        end
    end
    return object
end
env.CreateFromMixins = function(...) return env.Mixin({}, ...) end
env.CopyTable = function(t)
    local copy = {}
    for key, value in pairs(t) do
        copy[key] = type(value) == "table" and env.CopyTable(value) or value
    end
    return copy
end
env.GetLocale = function() return "enUS" end
env.GetBuildInfo = function() return "1.60.1", "70790", "Nov 4 2026", 16001 end
env.issecretvalue = function() return false end
env.GetMoneyString = function(copper) return copper .. "c" end
env.InCombatLockdown = function() return false end
env.hooksecurefunc = function() end
env.securecallfunction = function(fn, ...) return fn(...) end
env.ForeverPlusPlusDB, env.ForeverPlusPlusPlayersDB, env.ForeverPlusPlusCharDB = nil, nil, nil

local ns = {}
local _, files = T.Toc()
local loaded, broken = 0, {}
for _, path in ipairs(files) do
    if path ~= "Init.lua" then -- it starts the addon at login
        local chunk, err = loadfile(T.ROOT .. path)
        local fine = chunk ~= nil
        if chunk then
            setfenv(chunk, env)
            fine, err = pcall(chunk, T.ADDON, ns)
        end
        if fine then
            loaded = loaded + 1
        else
            broken[#broken + 1] = path .. ": " .. tostring(err)
        end
    end
end
eq(table.concat(broken, "\n  "), "", "modules: every file loads offline")
eq(type(ns.modules) == "table" and #ns.order > 50, true, "modules: the modules are made")

local CATEGORIES = { automation = true, character = true, chat = true, interface = true, items = true,
    map = true, quests = true, system = true, tools = true, units = true }
local function version(text)
    return type(text) == "string" and text:match("^%d+%.%d+%.%d+$") ~= nil
        or type(text) == "string" and text:match("^%d+%.%d+%.%d+%-[%w%.]+$") ~= nil
end
local function text(value)
    return type(value) == "string" and value ~= ""
end

local checked, linked = 0, 0
for _, name in ipairs(ns.order or {}) do
    local module = ns.modules[name]
    checked = checked + #(module.options or {})
    for _, option in ipairs(module.options or {}) do
        linked = linked + (option.requires and 1 or 0) + (option.slider and 1 or 0) + #(option.conflicts or {})
    end
    local problems = {}
    local function problem(fmt, ...)
        problems[#problems + 1] = fmt:format(...)
    end
    if not text(module.title) then
        problem("no title")
    end
    if not text(module.description) then
        problem("no description")
    end
    -- A tool that's always on (a Debug button) isn't in the list, so it needs no category.
    if not CATEGORIES[module.category] and not module.alwaysOn then
        problem("category %s isn't one of the list", tostring(module.category))
    end
    if module.added ~= nil and not version(module.added) then
        problem("added %s isn't a version", tostring(module.added))
    end

    local byKey = {}
    for i, option in ipairs(module.options or {}) do
        local key = option.key
        if not text(key) then
            problem("option %d has no key", i)
        elseif byKey[key] then
            problem("%s is listed twice", key)
        else
            byKey[key] = option
        end
    end
    for _, option in ipairs(module.options or {}) do
        local key = tostring(option.key)
        local default = module.defaults[option.key]
        if not text(option.name) then
            problem("%s has no name", key)
        end
        if not (text(option.description) or option.toggle) then
            problem("%s has no description", key)
        end
        if default == nil and not option.cvar and not (option.toggle and option.choices) then
            problem("%s has no default", key)
        end
        if option.choices then
            local found = default == nil
            for _, choice in ipairs(option.choices) do
                found = found or choice[1] == default
                if not text(choice[2]) then
                    problem("%s's choice %s has no label", key, tostring(choice[1]))
                end
            end
            if not found then
                problem("%s's default %s isn't one of its choices", key, tostring(default))
            end
        elseif option.min then
            if not (type(option.max) == "number" and option.min < option.max) then
                problem("%s's range is wrong", key)
            elseif type(default) ~= "number" or default < option.min or default > option.max then
                problem("%s's default %s is outside %s to %s", key, tostring(default), option.min, option.max)
            elseif option.step and math.abs((default - option.min) / option.step
                - math.floor((default - option.min) / option.step + 0.5)) > 1e-6 then
                problem("%s's default %s isn't on a step", key, tostring(default))
            end
        elseif default ~= nil and type(default) ~= "boolean" and not option.toggle then
            problem("%s is a checkbox with a default of %s", key, tostring(default))
        end
        for _, field in ipairs({ "requires", "slider" }) do
            if option[field] ~= nil and not byKey[option[field]] then
                problem("%s's %s %s isn't an option", key, field, tostring(option[field]))
            end
        end
        if option.slider and byKey[option.slider] and not byKey[option.slider].min then
            problem("%s's slider %s isn't a slider", key, option.slider)
        end
        for _, conflict in ipairs(option.conflicts or {}) do
            if not byKey[conflict.key] then
                problem("%s conflicts with %s, which isn't an option", key, tostring(conflict.key))
            end
            if type(conflict.when) ~= "function" or not text(conflict.text) then
                problem("%s's conflict with %s needs `when` and `text`", key, tostring(conflict.key))
            end
        end
        for _, field in ipairs({ "added", "changed" }) do
            if option[field] ~= nil and not version(option[field]) then
                problem("%s's %s %s isn't a version", key, field, tostring(option[field]))
            end
        end
        if option.shown ~= nil and type(option.shown) ~= "function" then
            problem("%s's shown isn't a function", key)
        end
    end
    for i, action in ipairs(module.actions or {}) do
        if not (text(action.name) and text(action.button) and type(action.fn) == "function") then
            problem("action %d needs a name, a button, and fn", i)
        end
    end
    eq(table.concat(problems, "; "), "", "modules: " .. name .. "'s settings")
end

-- So a load that made no options can't pass by itself.
eq(checked > 300 and linked > 20, true, ("modules: options checked (%d, %d linked)"):format(checked, linked))

-- Console Variables' Popular list: each section has a header and items, each item a CVar name, a
-- plain name, and help, and no CVar is listed twice (the page would count it once).
local popular = ns.modules.ConsoleVariables and ns.modules.ConsoleVariables.internal.POPULAR
local seen, items, popularProblems = {}, 0, {}
for i, section in ipairs(popular or {}) do
    if not text(section.header) or #section == 0 then
        popularProblems[#popularProblems + 1] = ("section %d needs a header and items"):format(i)
    end
    for _, item in ipairs(section) do
        items = items + 1
        local name = item[1]
        if not (type(name) == "string" and name:match("^[%w_]+$") and text(item[2]) and text(item[3])) then
            popularProblems[#popularProblems + 1] = ("%s needs a CVar name, a name, and help"):format(tostring(name))
        elseif seen[name:lower()] then
            popularProblems[#popularProblems + 1] = name .. " is listed twice"
        end
        seen[type(name) == "string" and name:lower() or i] = true
    end
end
eq(table.concat(popularProblems, "; "), "", "modules: Console Variables' Popular list")
eq(items >= 30, true, ("modules: Popular has its CVars (%d)"):format(items))

-- Friendly plates' Health Bar When Hurt checkbox (through 1.0.2) becomes the Health Bar dropdown.
local migrate = ns.FriendlyPlates.MigrateHealthBar
local on, off, chosen, none = { barWhenHurt = true }, { barWhenHurt = false },
    { barWhenHurt = false, healthBar = "never" }, {}
migrate(on)
migrate(off)
migrate(chosen)
migrate(none)
migrate(nil)
eq(on.healthBar, "hurt", "modules: Health Bar When Hurt on stays When Hurt")
eq(off.healthBar, "combat", "modules: Health Bar When Hurt off becomes Only in Combat")
eq(chosen.healthBar, "never", "modules: a Health Bar already chosen is kept")
eq(none.healthBar, nil, "modules: no saved checkbox leaves Health Bar at its default")
