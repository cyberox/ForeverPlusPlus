-- The Debug module's rows on its own page in the sidebar (S.BuildDebugPage), while it's on: a
-- header for each section (What's New, Diagnostics, Tools, Previews, Layout, Logging), with
-- Forever++'s own buttons and then each module's options marked `debug = true` and buttons from
-- `module.debugActions` that name it; after them a header for each module with rows in no section.
-- Drawn with the Modules page's own rows (Settings.lua), and greyed out while Debug is off.
local _, ns = ...

local ipairs, pairs, format, concat, tostring = ipairs, pairs, string.format, table.concat, tostring
local strlower = string.lower
local GetBuildInfo = GetBuildInfo
local L = ns.L
local S = ns.SettingsUI

-- The sections, in order, by what a row is for. Forever++'s own rows and modules' debug options
-- and buttons name one with `section`; a module's rows that name none of these go under its title,
-- after them.
-- - What's New: putting back what a new install or update sees.
-- - Diagnostics: a look at the addon's state, in chat or to copy.
-- - Tools: runs a check or a capture of its own (Self Test, Gear Probe, Screenshots).
-- - Previews: made-up content so a module shows without the game giving it a reason.
-- - Layout: guides drawn over the game to line things up.
-- - Logging: options that print what a module does while it does it.
local DEBUG_SECTIONS = {
    L.DEBUG_SECTION_NEW, L.DEBUG_SECTION_DIAGNOSTICS, L.DEBUG_SECTION_TOOLS, L.DEBUG_SECTION_PREVIEWS,
    L.DEBUG_SECTION_LAYOUT, L.DEBUG_SECTION_LOGGING,
}

local function debugSection(row)
    for _, section in ipairs(DEBUG_SECTIONS) do
        if row.section == section then
            return section
        end
    end
end

-- A module's debug options, by key, for an option under another (`requires`).
local function debugOptions(module)
    local byKey = {}
    for _, option in ipairs(module.options or {}) do
        if option.debug then
            byKey[option.key] = option
        end
    end
    return byKey
end

-- Whether a module has debug options or buttons in `section` (nil: in none of the sections).
local function hasDebugRows(module, section)
    for _, option in ipairs(module.options or {}) do
        if option.debug and debugSection(option) == section then
            return true
        end
    end
    for _, action in ipairs(module.debugActions or {}) do
        if debugSection(action) == section then
            return true
        end
    end
    return false
end

-- Forever++'s own buttons ----------------------------------------------------------------------

-- One line for a bug report: the addon and client, and the modules on.
local function debugInfo()
    local gameVersion, build, _, interface = GetBuildInfo()
    local on = ns.ModulesOn()
    return format(L.DEBUG_INFO_LINE, ns.version, tostring(gameVersion), tostring(build),
        tostring(interface), GetLocale(), #on, concat(on, ", "))
end

-- How many hooks a module has made (`module:Hook`, `HookScript`, `TooltipPostCall`,
-- `TooltipLinePreCall`). They stay but
-- do nothing while the module is off.
local function hookCount(module)
    local count = 0
    for _, byMethod in pairs(module.hooked or {}) do
        for _, byFn in pairs(byMethod) do
            for _ in pairs(byFn) do
                count = count + 1
            end
        end
    end
    return count
end

-- Prints each module's events (`module:On`) and hooks, to check a module that's off listens to
-- nothing. A module that's off but still has events is printed in red.
local function printEvents()
    local leaks = 0
    for _, name in ipairs(S.byTitle()) do
        local module = ns.modules[name]
        local list = {}
        for _, entry in ipairs(module.events or {}) do
            list[#list + 1] = entry[1]
        end
        local hooks = hookCount(module)
        if #list > 0 or (module.enabled and hooks > 0) then
            local line = format(L.DEBUG_EVENTS_LINE, module.title or name,
                ns.StateText(module.enabled), #list, #list > 0 and concat(list, ", ") or "-", hooks)
            if not module.enabled and #list > 0 then
                leaks = leaks + 1
                line = "|cffdd4444" .. line .. "|r"
            end
            ns.Print(line)
        end
    end
    ns.Print(leaks > 0 and format(L.DEBUG_EVENTS_LEAKS, leaks) or L.DEBUG_EVENTS_CLEAN)
end

local DEBUG_TOOLS = {
    { name = L.DEBUG_RESET_SEEN, button = L.DEBUG_RESET_SEEN_BUTTON,
        description = L.DEBUG_RESET_SEEN_DESC, fn = S.resetSeen, section = L.DEBUG_SECTION_NEW },
    { name = L.DEBUG_RESET_WELCOME, button = L.DEBUG_RESET_WELCOME_BUTTON,
        description = L.DEBUG_RESET_WELCOME_DESC, section = L.DEBUG_SECTION_NEW,
        fn = function()
            ns.SetWelcome(true)
            ns.Print(L.DEBUG_RESET_WELCOME_DONE)
        end },
    { name = L.DEBUG_INFO, button = L.DEBUG_INFO_BUTTON, description = L.DEBUG_INFO_DESC,
        section = L.DEBUG_SECTION_DIAGNOSTICS,
        fn = function() ns.Prompt("DEBUG_INFO", L.DEBUG_INFO_PROMPT, debugInfo()) end },
    { name = L.DEBUG_EVENTS, button = L.DEBUG_EVENTS_BUTTON, description = L.DEBUG_EVENTS_DESC,
        fn = printEvents, section = L.DEBUG_SECTION_DIAGNOSTICS },
    { name = L.DEBUG_RELOAD, button = L.DEBUG_RELOAD_BUTTON, description = L.DEBUG_RELOAD_DESC,
        fn = function() ReloadUI() end, section = L.DEBUG_SECTION_TOOLS },
}

-- The rows -------------------------------------------------------------------------------------

-- A module's debug options and then its debug buttons in `section` (nil: in none of the sections).
-- They're on while Debug (`debugOn`) and the module are, or, for a button marked `whileOff`, while
-- Debug is, whether the module is on or not.
local function addRows(view, debugOn, module, section)
    local function moduleOn()
        return debugOn() and module.db.enabled and true or false
    end
    local byKey, done = debugOptions(module), {}
    for _, option in ipairs(module.options or {}) do
        if option.debug and debugSection(option) == section and not done[option.key] then
            S.addOptionRow(view, module, option, byKey, done, debugOn)
        end
    end
    for i, action in ipairs(module.debugActions or {}) do
        if debugSection(action) == section then
            S.addButtonRow(view, action.name, action.whileOff and debugOn or moduleOn, nil,
                action.button, S.actionFn(module, action, i), action.description)
        end
    end
    view.follows[module.name] = true -- its rows grey out with it
end

---Adds the Debug module's rows to `view`, the stack on its own page (S.BuildDebugPage).
---@param view table the Debug page's view (Settings.lua)
---@param debugOn function whether Debug is on
function S.AddDebugRows(view, debugOn)
    local order = S.byTitle()
    for _, section in ipairs(DEBUG_SECTIONS) do
        S.addLine(view, "GameFontHighlightLarge", section)
        for _, tool in ipairs(DEBUG_TOOLS) do
            if tool.section == section then
                S.addButtonRow(view, tool.name, debugOn, nil, tool.button, tool.fn,
                    tool.description)
            end
        end
        for _, name in ipairs(order) do
            if hasDebugRows(ns.modules[name], section) then
                addRows(view, debugOn, ns.modules[name], section)
            end
        end
    end
    for _, name in ipairs(order) do
        local module = ns.modules[name]
        if hasDebugRows(module, nil) then
            S.addLine(view, "GameFontHighlightLarge", module.title or name)
            addRows(view, debugOn, module, nil)
        end
    end
end

---What the Modules page's search finds the Debug module by: its rows' names and descriptions.
---@return string text lowercased
function S.DebugSearchText()
    local text = {}
    local function add(row)
        text[#text + 1] = strlower(format("%s\n%s", row.name or "", row.description or ""))
    end
    for _, tool in ipairs(DEBUG_TOOLS) do
        add(tool)
    end
    for _, name in ipairs(S.byTitle()) do
        local module = ns.modules[name]
        for _, option in ipairs(module.options or {}) do
            if option.debug then
                add(option)
            end
        end
        for _, action in ipairs(module.debugActions or {}) do
            add(action)
        end
    end
    return concat(text, "\n")
end

-- The page, made a tool page of the Debug module so Settings puts it in the sidebar while Debug
-- is on (Settings.lua's pages, read when Settings is built, after every file has loaded).
ns.modules.Debug.BuildPage = function(_, frame)
    S.BuildDebugPage(frame)
end
