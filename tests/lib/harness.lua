-- The checks a spec makes, counted per spec file. A failed check prints where it was made (file and
-- line) and what it got, and the run goes on, so one run shows every failure.
local Harness = {}

local format, tostring, type, pairs = string.format, tostring, type, pairs

-- A value as a failure shows it: strings quoted, so "1" and 1 (or "" and nil) look different.
local function show(value)
    if type(value) == "string" then
        return format("%q", value)
    end
    return tostring(value)
end

-- Whether two values are the same, looking inside tables (keys and values both ways).
local function same(a, b, seen)
    if a == b then
        return true
    end
    if type(a) ~= "table" or type(b) ~= "table" then
        return false
    end
    seen = seen or {}
    if seen[a] == b then
        return true
    end
    seen[a] = b
    for key, value in pairs(a) do
        if not same(value, b[key], seen) then
            return false
        end
    end
    for key in pairs(b) do
        if a[key] == nil then
            return false
        end
    end
    return true
end

-- The first difference between two tables, as a path ("[2].name"), for a failure to show.
local function difference(a, b, path)
    path = path or ""
    if type(a) ~= "table" or type(b) ~= "table" then
        return path ~= "" and path or "(top)", a, b
    end
    for key, value in pairs(a) do
        if not same(value, b[key]) then
            return difference(value, b[key], path .. "[" .. show(key) .. "]")
        end
    end
    for key, value in pairs(b) do
        if a[key] == nil then
            return path .. "[" .. show(key) .. "]", nil, value
        end
    end
end

---A new set of checks for one spec file.
---@param name string the spec's name, for the report
---@param verbose? boolean print every check, not only failures
---@return table checks eq, same, near, ok, raises, and the counts
function Harness.New(name, verbose)
    local checks = { name = name, count = 0, failed = 0 }

    -- Where the spec made the check: `depth` frames up from here.
    local function where(depth)
        local info = debug.getinfo(depth + 1, "Sl")
        if not info then
            return name
        end
        return format("%s:%d", info.short_src:gsub("^.*[/\\]tests[/\\]", "tests/"), info.currentline or 0)
    end

    local function record(pass, what, detail, depth)
        checks.count = checks.count + 1
        if pass then
            if verbose then
                print(format("  ok   %s", what))
            end
            return true
        end
        checks.failed = checks.failed + 1
        print(format("FAIL %s %s%s", where(depth + 1), what, detail and (": " .. detail) or ""))
        return false
    end

    ---`got` is `want` (==).
    function checks.eq(got, want, what)
        return record(got == want, what, format("got %s, wanted %s", show(got), show(want)), 2)
    end

    ---`got` is the same as `want`, looking inside tables.
    function checks.same(got, want, what)
        if same(got, want) then
            return record(true, what, nil, 2)
        end
        local path, a, b = difference(got, want)
        return record(false, what, format("at %s got %s, wanted %s", path or "(top)", show(a), show(b)), 2)
    end

    ---`got` is a number within `within` (1e-9) of `want`.
    function checks.near(got, want, what, within)
        local pass = type(got) == "number" and math.abs(got - want) < (within or 1e-9)
        return record(pass, what, format("got %s, wanted %s", show(got), show(want)), 2)
    end

    ---`value` is true (anything but nil and false).
    function checks.ok(value, what)
        return record(value and true or false, what, format("got %s", show(value)), 2)
    end

    ---`fn` raises an error, whose message has `pattern` in it when one is given.
    function checks.raises(fn, pattern, what)
        local fine, err = pcall(fn)
        if fine then
            return record(false, what, "no error", 2)
        end
        local message = tostring(err)
        local pass = not pattern or message:find(pattern) ~= nil
        return record(pass, what, format("error %s doesn't match %s", show(message), show(pattern)), 2)
    end

    return checks
end

Harness.same = same

return Harness
