-- Globals: no file writes a global AGENTS.md doesn't allow ("Lua rules"), and every global a file
-- reads is Lua's own or one .luarc.json knows, so a typo (fromat for format) or a leaked local
-- (a missing `local`) fails here instead of reading or writing nil in game. Read from each file's
-- bytecode (tests/lib/bytecode.lua). Writes through _G[...] are checked by the `rules` spec.
local T = ...
local eq = T.eq

local Bytecode = assert(loadfile("tests/lib/bytecode.lua"))()

-- The globals the addon may set, and the file that sets each when only one may.
local WRITES = {
    { name = "ForeverPlusPlusDB" },
    { name = "ForeverPlusPlusCharDB" },
    { name = "ForeverPlusPlusPlayersDB" },
    { name = "ForeverPlusPlusAPI", file = "ForeverPlusPlus/API.lua" },
    { name = "ForeverPlusPlusCompanion", file = "ForeverPlusPlus/Init.lua" },
    { name = "BINDING_HEADER_FOREVERPLUSPLUS" },
    { pattern = "^SLASH_FOREVERPLUSPLUS[%w_]*$" },
}

-- Lua 5.1 as the game has it: no io, os, require, dofile, or loadfile. A file that needs one of
-- the game's own (os.time, strsplit, ...) lists it in .luarc.json.
local BUILTINS = {}
for name in ([[_G _VERSION assert collectgarbage error getfenv getmetatable ipairs load loadstring
    next pairs pcall print rawequal rawget rawset select setfenv setmetatable tonumber tostring type
    unpack xpcall coroutine math string table bit]]):gmatch("%S+") do
    BUILTINS[name] = true
end

local luarc = T.Read(".luarc.json")
local list = luarc and luarc:match('"diagnostics%.globals"%s*:%s*(%b[])')
local KNOWN = {}
for name in (list or ""):gmatch('"([^"]+)"') do
    KNOWN[name] = true
end
eq(KNOWN.CreateFrame, true, "globals: .luarc.json's globals are read")

local function allowedWrite(name, path)
    for _, rule in ipairs(WRITES) do
        if rule.name == name or (rule.pattern and name:match(rule.pattern)) then
            return rule.file == nil or rule.file == path
        end
    end
    return false
end

-- Every .lua file each addon's TOC loads.
local paths = {}
local function addToc(root, toc)
    for line in io.lines(root .. toc) do
        line = line:gsub("\r$", "")
        if line:match("%S") and not line:match("^#") then
            local file = line:gsub("%s*%[.*$", ""):gsub("\\", "/"):match("^%s*(.-)%s*$")
            if file:match("%.lua$") then
                paths[#paths + 1] = root .. file
            end
        end
    end
end
addToc(T.ROOT, T.ADDON .. ".toc")
addToc("ForeverPlusPlus_AgentChat/", "ForeverPlusPlus_AgentChat.toc")

local reads = 0
for _, path in ipairs(paths) do
    local chunk, err = loadfile(path)
    eq(err, nil, "globals: " .. path .. " compiles")
    local writes, unknown = {}, {}
    for _, use in ipairs(chunk and Bytecode.Globals(chunk) or {}) do
        if use.write then
            if not allowedWrite(use.name, path) then
                writes[#writes + 1] = ("%s (line %d)"):format(use.name, use.line)
            end
        else
            reads = reads + 1
            if not BUILTINS[use.name] and not KNOWN[use.name] then
                unknown[#unknown + 1] = ("%s (line %d)"):format(use.name, use.line)
            end
        end
    end
    table.sort(writes)
    table.sort(unknown)
    eq(table.concat(writes, ", "), "", "globals: " .. path .. " writes only allowed globals")
    eq(table.concat(unknown, ", "), "",
        "globals: every global " .. path .. " reads is Lua's or in .luarc.json")
end
-- So a scan that finds nothing can't pass by itself.
eq(#paths > 150 and reads > 2000, true,
    ("globals: the scan finds the files and their reads (%d, %d)"):format(#paths, reads))

-- The reader itself, on a chunk with a known answer.
local found = {}
for _, use in ipairs(Bytecode.Globals(assert(loadstring("local a = fromat('x')\nleaked = {1, 2, a}")))) do
    found[#found + 1] = (use.write and "set " or "get ") .. use.name .. ":" .. use.line
end
table.sort(found)
eq(table.concat(found, " "), "get fromat:1 set leaked:2", "globals: the reader finds a typo and a leak")
