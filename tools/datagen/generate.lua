-- Writes the addon's data files that come from the client's database tables, as wago.tools
-- publishes them for a build of Forever (product wowf). Lua 5.1 and curl, from the repo root:
--
--   lua5.1 tools/datagen/generate.lua [build]   every generated file, for build (default: latest)
--   lua5.1 tools/datagen/generate.lua --latest  print the latest wowf build
--   lua5.1 tools/datagen/generate.lua --paths   print the files it writes
--   lua5.1 tools/datagen/generate.lua --self-test
--
-- .github/workflows/table-data.yml runs it daily and opens a pull request for a new build.
--
-- Tables are saved under tools/datagen/cache/<build>/ (not committed), so a rerun downloads
-- nothing. The build the files came from is written to tools/datagen/BUILD. Output is sorted and
-- formatted the same every time: the same build gives the same bytes.
local dir = (arg and arg[0] or ""):match("^(.*)[/\\][^/\\]*$") or "."
package.path = dir .. "/?.lua;" .. package.path

local CSV = require("csv")

local SCRIPT = "tools/datagen/generate.lua"
local ROOT = dir .. "/../.."
local CACHE = dir .. "/cache"
local BUILD_FILE = dir .. "/BUILD"
local PRODUCT = "wowf"
local AGENT = "Mozilla/5.0 (compatible; db2-table-fetch/1.0)"
local WINDOWS = package.config:sub(1, 1) == "\\"

-- What it writes. Each takes the tables it lists (as CSV text by name) and returns the file.
local GENERATORS = require("generators")

local function fail(message)
    io.stderr:write("datagen: ", message, "\n")
    os.exit(1)
end

local function isBuild(text)
    return type(text) == "string" and text:match("^%d+%.%d+%.%d+%.%d+$") ~= nil
end

local function readFile(path)
    local file = io.open(path, "rb")
    if not file then
        return nil
    end
    local text = file:read("*a")
    file:close()
    return text
end

local function writeFile(path, text)
    local file, err = io.open(path, "wb")
    if not file then
        fail("can't write " .. path .. ": " .. tostring(err))
    end
    file:write(text)
    file:close()
end

local function makeDir(path)
    if WINDOWS then
        os.execute('mkdir "' .. path:gsub("/", "\\") .. '" 2>nul')
    else
        os.execute("mkdir -p '" .. path .. "'")
    end
end

-- Runs curl; the URL is built from checked parts only (a table name and a build number).
local function curl(url, path)
    local command = ('curl -fsSL --retry 2 --max-time 120 -A "%s" -o "%s" "%s"'):format(AGENT, path, url)
    local status = os.execute(command)
    return status == 0 or status == true
end

local function latestBuild()
    local url = "https://wago.tools/api/builds/" .. PRODUCT .. "/latest"
    local pipe = io.popen(('curl -fsSL --retry 2 --max-time 60 -A "%s" "%s"'):format(AGENT, url))
    local body = pipe and pipe:read("*a") or ""
    if pipe then
        pipe:close()
    end
    local product = body:match('"product"%s*:%s*"([^"]*)"')
    local version = body:match('"version"%s*:%s*"([^"]*)"')
    if product ~= PRODUCT or not isBuild(version) then
        return nil
    end
    return version
end

-- A table's CSV for a build, from the cache or else downloaded into it.
local function getTable(name, build)
    if not name:match("^%w+$") then
        fail("bad table name " .. name)
    end
    local folder = CACHE .. "/" .. build
    local path = folder .. "/" .. name .. ".csv"
    local text = readFile(path)
    if text then
        return text
    end
    makeDir(folder)
    local url = ("https://wago.tools/db2/%s/csv?build=%s"):format(name, build)
    io.stderr:write("datagen: downloading ", name, " for ", build, "\n")
    local part = path .. ".part"
    if not curl(url, part) then
        os.remove(part)
        fail("couldn't download " .. url)
    end
    text = readFile(part)
    if not text or not text:match("^[^\n]*,") then
        os.remove(part)
        fail(url .. " didn't return a CSV table")
    end
    os.remove(path)
    os.rename(part, path)
    return text
end

local command = arg[1]
if command == "--latest" then
    local build = latestBuild()
    if not build then
        fail("couldn't read the latest " .. PRODUCT .. " build from wago.tools")
    end
    print(build)
    os.exit(0)
elseif command == "--paths" then
    for _, generator in ipairs(GENERATORS) do
        print(generator.path)
    end
    print("tools/datagen/BUILD")
    os.exit(0)
elseif command == "--self-test" then
    print(("datagen: %d CSV checks passed"):format(CSV.SelfTest()))
    os.exit(0)
end

local build = command
if build == nil then
    build = latestBuild()
    if not build then
        fail("couldn't read the latest " .. PRODUCT .. " build from wago.tools; give one")
    end
elseif not isBuild(build) then
    fail("a build looks like 1.60.1.70888, not " .. tostring(build))
end

local tables = {}
for _, generator in ipairs(GENERATORS) do
    for _, name in ipairs(generator.tables) do
        tables[name] = tables[name] or getTable(name, build)
    end
end
-- Every file is made before any is written, so a failure leaves the tree as it was.
local texts = {}
for i, generator in ipairs(GENERATORS) do
    local ok, text = pcall(generator.Build, tables, build, SCRIPT, ROOT)
    if not ok then
        fail(generator.path .. ": " .. tostring(text))
    end
    if text:find("[\128-\255]") then
        fail(generator.path .. ": output isn't ASCII")
    end
    texts[i] = text
end
for i, generator in ipairs(GENERATORS) do
    writeFile(ROOT .. "/" .. generator.path, texts[i])
    print("datagen: wrote " .. generator.path)
end
writeFile(BUILD_FILE, build .. "\n")
print("datagen: build " .. build)
