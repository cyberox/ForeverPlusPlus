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
eq(next(strings.L) ~= nil, true, "locales: the enUS strings load")
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
eq(strings.L.MOVABLEWINDOWS_TITLE, "Movable Windows", "locales: a string reads its English")
