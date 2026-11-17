-- Locales: every ns.L string the addon uses is defined in Locales/enUS/, and none is defined twice.
-- A missing one shows as nil in game (or breaks a format call), so it's caught here instead.
local T = ...
local eq = T.eq

local _, files = T.Toc()

-- Every enUS file the TOC loads, into a table of its own.
local strings = { L = {} }
strings.NewLocale = function()
    return strings.L
end
local defined = {} -- key -> "file:line" of its first definition
local twice = {}
for _, path in ipairs(files) do
    if path:match("^Locales/enUS/") then
        T.load(path:gsub("%.lua$", ""), strings)
        local number = 0
        for line in T.Read(T.ROOT .. path):gmatch("([^\n]*)\n?") do
            number = number + 1
            local key = line:match("^L%.([%w_]+)%s*=")
            if key then
                if defined[key] then
                    twice[#twice + 1] = ("%s (%s and %s:%d)"):format(key, defined[key], path, number)
                else
                    defined[key] = path .. ":" .. number
                end
            end
        end
    end
end
eq(table.concat(twice, ", "), "", "locales: no string is defined twice")

-- The strings each file uses: L.KEY, with or without ns. in front, outside comments.
local function used(text)
    local found, number = {}, 0
    for line in text:gmatch("([^\n]*)\n?") do
        number = number + 1
        local code = line:gsub("%-%-.*$", "")
        for key in code:gmatch("%f[%w_]L%.([%a_][%w_]*)") do
            found[#found + 1] = { key = key, line = number }
        end
    end
    return found
end

local total = 0
for _, path in ipairs(files) do
    if path:match("%.lua$") and not path:match("^Locales/") then
        local text = T.Read(T.ROOT .. path)
        local missing = {}
        for _, use in ipairs(text and used(text) or {}) do
            total = total + 1
            if strings.L[use.key] == nil then
                missing[#missing + 1] = ("%s (line %d)"):format(use.key, use.line)
            end
        end
        eq(table.concat(missing, ", "), "", "locales: every string " .. path .. " uses is defined")
    end
end
-- So a scan that finds nothing can't pass by itself.
eq(total > 1000, true, "locales: the scan finds the strings the files use (" .. total .. ")")

-- Another language: every key it sets is one enUS has, with the same placeholders (in any order,
-- since "%2$s of %1$s" may move them). A key enUS dropped, or a lost %s, is caught here.
local function placeholders(text)
    local found = {}
    for kind in text:gsub("%%%%", ""):gmatch("%%%d*%$?[-+ #0]*%d*%.?%d*([a-zA-Z])") do
        found[#found + 1] = kind
    end
    table.sort(found)
    return table.concat(found)
end
local function problems(theirs, english)
    local list = {}
    for key, text in pairs(theirs) do
        if english[key] == nil then
            list[#list + 1] = key .. " isn't an enUS key"
        elseif placeholders(text) ~= placeholders(english[key]) then
            list[#list + 1] = key .. " has other placeholders"
        end
    end
    table.sort(list)
    return table.concat(list, ", ")
end
eq(placeholders("%2$s of %1$d, 50%%"), "ds", "locales: placeholders are read whatever their order")
eq(problems({ A = "%s zu %d", B = "x", C = "%s" }, { A = "%d to %s", C = "%d" }),
    "B isn't an enUS key, C has other placeholders", "locales: a language's mistakes are found")

local languages = {} -- code -> its strings
for _, path in ipairs(files) do
    local code = path:match("^Locales/(%w+)/")
    if code and code ~= "enUS" then
        languages[code] = languages[code] or {}
        local theirs = languages[code]
        T.load(path:gsub("%.lua$", ""), { NewLocale = function() return theirs end })
    end
end
for code, theirs in pairs(languages) do
    eq(problems(theirs, strings.L), "", "locales: " .. code .. " matches enUS")
end
