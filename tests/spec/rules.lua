-- Rules: the rules in AGENTS.md a machine can check exactly, over every file both addons load.
-- Globals come from each file's bytecode (tests/lib/bytecode.lua), so `C_Item.GetItemInfo` and a
-- name in a comment never count. Each rule's exceptions are listed here, with why.
local T = ...
local eq = T.eq

local Bytecode = assert(loadfile("tests/lib/bytecode.lua"))()

-- Classic globals the client doesn't have, from docs/forever-api.md ("Removed Classic globals").
-- UnitBuff and UnitDebuff went with UnitAura in Retail 11.0.
local REMOVED = {}
for name in ([[GetItemInfo GetItemInfoInstant GetSpellInfo UnitAura UnitBuff UnitDebuff
    GetContainerItemInfo IsAddOnLoaded GetAddOnMetadata SetDesaturation GetMouseFocus EasyMenu
    GetQuestLogTitle GetNumQuestLogEntries GetSpecialization GetSpecializationInfo GetTalentInfo
    GetTalentTabInfo GetNumTalentTabs GetActiveTalentGroup CombatLogGetCurrentEventInfo
    GetMerchantItemInfo GetItemStats]]):gmatch("%S+") do
    REMOVED[name] = true
end

-- Globals only some files may read: name -> file -> why.
local ONLY = {
    -- Never to detect Forever (an earlier build had Mainline's); probe for the API instead.
    WOW_PROJECT_ID = {
        ["ForeverPlusPlus/Modules/Interface/Tooltips.lua"] = "a friend's game against ours",
        ["ForeverPlusPlus/Modules/Tools/SelfTest.lua"] = "reports it",
    },
    -- Chat goes through ns.Print and module:Print.
    print = { ["ForeverPlusPlus/Core.lua"] = "ns.Print" },
}

-- What a file's first line of code must be, after comments.
local function firstCode(text)
    local inBlock
    for line in text:gmatch("([^\n]*)\n?") do
        line = line:gsub("\r$", "")
        if inBlock then
            if line:find(inBlock, 1, true) then
                inBlock = nil
            end
        else
            local level = line:match("^%s*%-%-%[(=*)%[")
            if level then
                local close = "]" .. level .. "]"
                if not line:find(close, 1, true) then
                    inBlock = close
                end
            elseif line:match("%S") and not line:match("^%s*%-%-") then
                return line
            end
        end
    end
end

local function headerOk(path, line)
    line = line and line:gsub("%s*%-%-.*$", "")
    if path:match("^" .. T.ROOT) then
        return line == "local addonName, ns = ..." or line == "local _, ns = ..."
    end
    return line == "local ns = ForeverPlusPlusCompanion()"
end

local paths = T.LuaFiles()
for _, path in ipairs(paths) do
    local text = T.Read(path) or ""
    local chunk = loadfile(path)
    local uses, strings = {}, {}
    if chunk then
        uses, strings = Bytecode.Globals(chunk)
    end

    local first = firstCode(text)
    eq(headerOk(path, first), true, "rules: " .. path .. " starts with its addon's ns (" .. tostring(first) .. ")")

    local removed, only = {}, {}
    for _, use in ipairs(uses) do
        if not use.write and REMOVED[use.name] then
            removed[#removed + 1] = ("%s (line %d)"):format(use.name, use.line)
        end
        if ONLY[use.name] and not ONLY[use.name][path] then
            only[#only + 1] = ("%s (line %d)"):format(use.name, use.line)
        end
    end
    table.sort(removed)
    table.sort(only)
    eq(table.concat(removed, ", "), "", "rules: " .. path .. " uses no removed Classic global")
    eq(table.concat(only, ", "), "", "rules: " .. path .. " reads no global kept to other files")
    -- It never fires for addons, and registering it only wastes a frame's time.
    eq(strings.COMBAT_LOG_EVENT_UNFILTERED, nil, "rules: " .. path .. " doesn't use COMBAT_LOG_EVENT_UNFILTERED")

    local tabs, trailing, number = {}, {}, 0
    for line in text:gmatch("([^\n]*)\n?") do
        number = number + 1
        if line:match("^ *\t") then
            tabs[#tabs + 1] = number
        end
        if line:match("[ \t]\r?$") then
            trailing[#trailing + 1] = number
        end
    end
    eq(table.concat(tabs, ", "), "", "rules: " .. path .. " indents with spaces, not tabs (lines)")
    eq(table.concat(trailing, ", "), "", "rules: " .. path .. " has no trailing spaces (lines)")
end
eq(#paths > 150, true, "rules: the scan finds the files (" .. #paths .. ")")

-- .luarc.json mustn't vouch for a removed global, or the globals spec would let it through.
local listed = {}
local list = (T.Read(".luarc.json") or ""):match('"diagnostics%.globals"%s*:%s*(%b[])') or ""
for name in list:gmatch('"([^"]+)"') do
    if REMOVED[name] then
        listed[#listed + 1] = name
    end
end
eq(table.concat(listed, ", "), "", "rules: .luarc.json lists no removed Classic global")

-- The checks themselves, on code with known answers.
local uses, strings = Bytecode.Globals(assert(loadstring(
    "local C_Item = {}\nlocal a = C_Item.GetItemInfo(1)\nlocal b = GetItemInfo(1)\n-- UnitAura\nf('COMBAT_LOG_EVENT_UNFILTERED')")))
local hits = {}
for _, use in ipairs(uses) do
    if REMOVED[use.name] then
        hits[#hits + 1] = use.name .. ":" .. use.line
    end
end
eq(table.concat(hits, " "), "GetItemInfo:3", "rules: a removed global counts, a C_ method or comment doesn't")
eq(strings.COMBAT_LOG_EVENT_UNFILTERED, true, "rules: an event name in the code is found")
eq(firstCode("-- a\n--[[ b\nc ]]\n\nlocal _, ns = ...\n"), "local _, ns = ...", "rules: comments before the first line are skipped")
