-- Offline tests for Forever++. Plain Lua 5.1, no WoW client: from the repo root,
--
--   lua tests/run.lua              every spec
--   lua tests/run.lua store text   only the specs with one of those in their name
--   lua tests/run.lua -v           every check, not only failures
--
-- Each file in tests/spec/ is a spec, found by itself and run in name order. A spec gets a fresh
-- copy of the addon (tests/lib/env.lua: its own globals and `ns`) and the checks in
-- tests/lib/harness.lua, as `local T = ...`. A spec that errors is a failure, and the run goes on.
-- The exit code is 0 only when every check passed. See tests/README.md.

local function import(path)
    return assert(loadfile(path))()
end

local Env = import("tests/lib/env.lua")
local Harness = import("tests/lib/harness.lua")

local verbose, wanted = false, {}
for _, word in ipairs(arg or {}) do
    if word == "-v" or word == "--verbose" then
        verbose = true
    else
        wanted[#wanted + 1] = word:lower()
    end
end

-- The spec files, by listing the folder (cmd's dir on Windows, ls elsewhere).
local function specFiles()
    local windows = package.config:sub(1, 1) == "\\"
    local command = windows and 'dir /b "tests\\spec\\*.lua"' or "ls tests/spec/*.lua"
    local pipe = assert(io.popen(command), "can't list tests/spec")
    local files = {}
    for line in pipe:lines() do
        local name = line:match("([%w_%-]+)%.lua%s*$")
        if name then
            files[#files + 1] = name
        end
    end
    pipe:close()
    table.sort(files)
    return files
end

local function picked(name)
    if #wanted == 0 then
        return true
    end
    for _, word in ipairs(wanted) do
        if name:lower():find(word, 1, true) then
            return true
        end
    end
    return false
end

local total, failed, broken, rows = 0, 0, 0, {}
local specs = specFiles()
assert(#specs > 0, "no specs in tests/spec")
for _, name in ipairs(specs) do
    if picked(name) then
        if verbose then
            print(name)
        end
        local checks = Harness.New(name, verbose)
        local T = Env.New()
        for key, fn in pairs(checks) do
            if type(fn) == "function" then
                T[key] = fn
            end
        end
        local chunk, err = loadfile("tests/spec/" .. name .. ".lua")
        local ok = chunk ~= nil
        if chunk then
            setfenv(chunk, T.env)
            ok, err = xpcall(function() chunk(T) end, debug.traceback)
        end
        local status = "ok"
        if not ok then
            broken = broken + 1
            status = "ERROR"
            print(("ERROR tests/spec/%s.lua: %s"):format(name, tostring(err)))
        elseif checks.count == 0 then
            broken = broken + 1
            status = "EMPTY"
            print(("EMPTY tests/spec/%s.lua made no checks"):format(name))
        elseif checks.failed > 0 then
            status = "FAIL"
        end
        total, failed = total + checks.count, failed + checks.failed
        rows[#rows + 1] = ("  %-12s %4d checks %s"):format(name, checks.count,
            status == "ok" and "" or ("  " .. status .. (checks.failed > 0 and (" " .. checks.failed) or "")))
    end
end

assert(#rows > 0, "no spec matches " .. table.concat(wanted, ", "))
print(table.concat(rows, "\n"))
print(("%d checks, %d failed%s"):format(total, failed, broken > 0 and (", " .. broken .. " specs broken") or ""))
os.exit((failed == 0 and broken == 0) and 0 or 1)
